package OMP::MSBDB;

=head1 NAME

OMP::MSBDB - A database of MSBs

=head1 SYNOPSIS

  $sp = new OMP::SciProg( XML => $xml );
  $db = new OMP::MSBDB( Password => $passwd, 
                        ProjectID => $sp->projectID,
			DB => $connection,
		      );

  $status = $db->storeSciProg( SciProg => $sp );

  $msb = $db->fetchMSB( msbid => $id,
                        checksum => $checksum );
  $sp  = $db->fetchSciProg();

  @match = $db->queryMSB( $query_object );


=head1 DESCRIPTION

This class is responsible for storing and retrieving science 
programs and MSBs to and from the database. Database is loosely
defined in this context.

=cut

use 5.006;
use strict;
use warnings;
use Carp;

# OMP dependencies
use OMP::SciProg;
use OMP::MSB;
use OMP::Error;
use OMP::General;
use OMP::ProjDB;
use OMP::Constants qw/ :done :fb /;
use OMP::Range;
use OMP::Info::MSB;
use OMP::Info::Obs;
use OMP::Info::Comment;
use OMP::Project::TimeAcct;
use OMP::TimeAcctDB;
use OMP::MSBDoneDB;

use Time::Piece qw/ :override /;

use Astro::Telescope;
use Astro::Coords;
use Data::Dumper;

# Use this for the reliable file opening
use File::Spec;
use Fcntl;
use Errno; # else $!{EEXIST} does not work

use base qw/ OMP::BaseDB /;

our $VERSION = (qw$Revision$)[1];

# Name of the table containing the MSB data
our $MSBTABLE = "ompmsb";
our $PROJTABLE = $OMP::ProjDB::PROJTABLE;
our $OBSTABLE = "ompobs";
our $SCITABLE = "ompsciprog";

# Default number of results to return from a query
our $DEFAULT_RESULT_COUNT = 10;

# Debug messages
our $DEBUG = 0;

# Artificial "INFINITIES" for unbounded ranges
my %INF = (
	   tau => 101,
	   seeing => 5000,
	  );

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

Create a new instance of an C<OMP::MSBDB> object.

  $db = new OMP::MSBDB( ProjectID => $project,
			Password  => $passwd
			DB => $connection,
		      );

The password and project if arguments are required for Science Program
access.  The password refers to the Project (see C<OMP::ProjDB>).
MSB-based methods do not need to know this information so it does
not always need to be supplied.

If supplied, the database connection object must be of type
C<OMP::DBbackend>.  It is not accepted if that is not the case.
(but no error is raised - this is probably a bug).

=cut

# Use base class version

=back

=head2 Accessor Methods

=over 4

=item B<projectid>

The project ID associated with this object.

  $pid = $db->projectid;
  $db->projectid( "M01BU53" );

All project IDs are upper-cased automatically.

=cut

# inherit from base class

=item B<password>

The password associated with this object.

 $passwd = $db->password;
 $db->password( $passwd );

=cut

# inherit from base class

=back

=head2 General Methods

=over 4

=item B<storeSciProg>

Store a science program object into the database.

  $status = $db->storeSciProg( SciProg => $sp );

Requires a password and project identifier. If the FreezeTimeStamp
key is present and set to true timestamp checking is disabled and
the timestamp is not updated when writing XML to disk. This is to
allows the science program to be modified internally without affecting
the external checking but can be dangerous if used without thought
since it will most likely lead to confusion, either because the
PI re-uploads without realising that the program has been modified,
or because the back up system looks at the timestamp to determine whether
to backup the file. Timestamps should be modified when re-uploading
after a MSB accept for this reason. FreezeTimeStamp implies NoFeedback
and NoCache (unless set explicitly).

  $status = $db->storeSciProg( SciProg => $sp,
                               FreezeTimeStamp => 1,
                               NoFeedback => 1,
                               NoCache => 1);

The NoFeedback key can be used to disable the writing of an
entry to the feedback table on store. This is useful when an MSB
is being accepted since the MSB acceptance will itself lead
to a feedback entry.

The NoCache switch, if true, can be used to prevent the system
from attempting to write a backup of the submitted science program
to disk. This is important for MSB acceptance etc, since the
purpose for the cache is to track a limited number of PI submissions,
not to track MSB accepts.

The C<Force> key can be used for force the saving of the program
to the database even if the timestamps do not match. This option
should be used with care. Default is false (no force).

The scheduling fields (eg tau and seeing) must be populated.

Suspend flags are not touched since now the Observing Tool
has the ability to un-suspend.

Returns true on success and C<undef> on error (this may be
modified to raise an exception).

=cut

sub storeSciProg {
  my $self = shift;

  # Get the arguments
  my %args = @_;

  # Make sure the project actually exists
  # (in some cases the password will be verified even if the project
  # does not exist)
  $self->_verify_project_exists;

  # Verify the password as soon as possible
  $self->_verify_project_password();

  # Check them
  return undef unless exists $args{SciProg};
  return undef unless UNIVERSAL::isa($args{SciProg}, "OMP::SciProg");

  # Implied states
  $args{NoCache} = 1 if (!exists $args{NoCache} && $args{FreezeTimeStamp});
  $args{NoFeedback} = 1 if (!exists $args{NoFeedback} && $args{FreezeTimeStamp});

  # Before we do anything else we connect to the database
  # begin a transaction and lock out the tables.
  # This has the side effect of locking out the tables until
  # we have finished with them (else it will block waiting for
  # access). This allows us to use the DB lock to control when we
  # can write a science program to disk)
  $self->_db_begin_trans;
  $self->_dblock;

  # Write the Science Program to disk
  $self->_store_sci_prog( $args{SciProg}, $args{FreezeTimeStamp},
			  $args{Force}, $args{NoCache} )
    or throw OMP::Error::SpStoreFail("Error storing science program into database\n");

  # Get the summaries for each msb as a hash containing observations
  # as arrays of hashes
  my @rows = map {
    my $info = $_->info;

    # Check that tau and seeing are there
    throw OMP::Error::SpBadStructure("No scheduling information in science program. Did you forget to put in a Site Quality component?\n")
      if (!$info->tau() or !$info->seeing());

    # Return the reference to the array
    $info;

  } $args{SciProg}->msb;

  # Insert the summaries into rows of the database
  $self->_insert_rows( @rows );

  # And file with feedback system unless told otherwise
  unless ($args{NoFeedback}) {
    # Add a little note if we used the admin password
    my $note = $self->_password_text_info();

    $self->_notify_feedback_system(
				   subject => "Science program submitted",
				   text => "Science program submitted for project <b>".
				            $self->projectid ."</b> $note\n",
				   status => OMP__FB_HIDDEN,
				   msgtype => OMP__FB_MSG_SP_SUBMITTED,
				  );
  }

  # Now disconnect from the database and free the lock
  $self->_dbunlock;
  $self->_db_commit_trans;

  return 1;
}

=item B<fetchSciProg>

Retrieve a science program from the database.

  $sp = $db->fetchSciProg()

It is returned as an C<OMP::SciProg> object.
It is assumed that the DB object has already been instantiated
with the relevant project ID and password.

Note that no file or database locking is involved. This method simply
reads the file that is there and returns it. If it so happens that the
file is about to be updated then there is nothing that can be done to
prevent this. The routine that stores the science program guarantees
to do it in such a way that it will be impossible for a partial
science program to be retrieved (as would happen if the file is read
just as the file is being written).

The optional argument can be used to disable feedback notification (ie if it
is being called from an internal method) if true.

=cut

sub fetchSciProg {
  my $self = shift;
  my $internal = shift;

  # Test to see if the file exists first so that we can
  # raise a special UnknownProject exception.
  my $pid = $self->projectid;
  $pid = '' unless defined $pid;
  throw OMP::Error::UnknownProject("No science program available for \"$pid\"")
    unless $self->_get_old_sciprog_timestamp;

  # Verify the password [staff access is allowed]
  $self->_verify_project_password(1);

  # Instantiate a new Science Program object
  # The file name is derived automatically
  my $sp = new OMP::SciProg( XML => $self->_db_fetch_sciprog())
    or throw OMP::Error::SpRetrieveFail("Unable to fetch science program\n");

  # And file with feedback system.
  unless ($internal) {

    # remove any obs labels here since the OT does not use them
    # and it is best that they are regenerated on submission
    # [They are retained only when an MSB is retrieved]
    # Note that we do not strip them when we are doing an internal
    # fetch of the science program since fetchMSB has to fetch
    # a science program in order to obtain the labels
    for my $msb ($sp->msb) {
      $msb->_clear_obs_counter;
    }

    # Add a little note if we used the admin password
    my $note = $self->_password_text_info();

    $self->_notify_feedback_system(
				   subject => "Science program retrieved",
				   text => "Science program retrieved for project <b>".
				   $self->projectid ."</b> $note\n",
				   msgtype => OMP__FB_MSG_SP_RETRIEVED,
				  );
  }

  return $sp;
}

=item B<removeSciProg>

Remove the science program from the database.

  $db->removeSciProg();

Hopefully this is intentional. Project or administrator password
is required (both password and project ID are obtained from the object).

=cut

sub removeSciProg {
  my $self = shift;

  # Verify the password
  $self->_verify_project_password();

  # Before we do anything else we connect to the database
  # begin a transaction and lock out the tables.
  # This has the side effect of locking out the tables until
  # we have finished with them (else it will block waiting for
  # access). This allows us to use the DB lock to control when we
  # can write a science program to disk)
  $self->_db_begin_trans;
  $self->_dblock;

  # Remove the science program
  $self->_remove_old_sciprog();

  # Remove the observation and MSB entries
  $self->_clear_old_rows();

  # Add a little note if we used the admin password
  my $note = $self->_password_text_info();

  $self->_notify_feedback_system(
				 subject => "Science program deleted",
				 text => "Science program for project <b>".
				 $self->projectid ."</b> deleted $note\n",
				 msgtype => OMP__FB_MSG_SP_DELETED,
				);

  OMP::General->log_message( "Science program deleted for project " .
			     $self->projectid() . 
			     " $note\n"
			   );

  # Now disconnect from the database and free the lock
  $self->_dbunlock;
  $self->_db_commit_trans;

}


=item B<fetchMSB>

Retrieve an MSB (in the form of an OMP::MSB object) from the database.
The MSB can be identified either explicitly by specifying the index
(msbid) from the table, by specifying the index (msbid) with a
verification checksum or by specifying just the checksum.  If a
checksum and msbid are provided the a check is made on the database
table before even attempting to load the science program.  This allows
some flexibility in retrieving the MSB.

In all cases the project ID is verified (as stored in the object) as a
sanity check if it is present. Once the checksum is determined (either
from the table or supplied by the user) the Science Program is scanned
until the relevant MSB can be located.

Note that the checksum is guaranteed to be unique (partly because
it is used to determine MSBs that are identical when the Science
Program is stored in the DB) so long as the project ID is available.

If the project ID is not available from the object then queries
using just the checksum can not be guaranteed (although statistics
are in your favour).

The OMP will probably always use the index and checksum approach for
remote retrieval since, assuming an MSB has a unique index, this
allows for us to determine when a science program has been resubmitted
since we obtained the information. This is important since we want to
make sure that our query is still valid.

The checksum approach allows us to always retrieve the same MSB
regardless of whether the science program has been resubmitted since
we last looked (this is used when marking an MSB as done).

Just use the index:

   $msb = $db->fetchMSB( msbid => $index );

Use the index and checksum (both are used for the DB query):

   $msb = $db->fetchMSB( msbid => $index, checksum => $checksum );

Use the checksum and the project id (available from the object):

   $msb = $db->fetchMSB( checksum => $checksum );

It is an error for multiple MSBs to match the supplied criteria.

An exception is raised (C<MSBMissing>) if the MSB can not be located.
This may indicate that the science program has been resubmitted or
the checksum was invalid [there is no distinction].

Fetching an MSB does not involve database locking because
an internal consistency check is provided since we compare
checksum (supplied or from the databse) with that in the file.
If the checksum matches in the database but fails to match
in the science program (because it was updated between doing
the query and reading from the science program) then we will still
catch an inconsitency.

=cut

sub fetchMSB {
  my $self = shift;
  my %args = @_;

  # Administrator password so that we can fetch and store
  # science programs without resorting to knowing the
  # actual password or to disabling password authentication
  $self->password("***REMOVED***");


  # The important result is the checksum
  my $checksum;

  # If we are querying the database by MSB ID...
  my $usingmsbid;
  if (exists $args{msbid} && defined $args{msbid}) {

    # Call method to do search on database. This assumes that we
    # can map projectid, checksum and id to valid column names
    # Returns a hash with the row entries
    my %details = $self->_fetch_row(%args);

    # We could not find anything
    throw OMP::Error::MSBMissing("Could not locate requested MSB in database. Maybe you need to resubmit the query?")
      unless %details;

    # Get the checksum
    $checksum = $details{checksum};

    # And the project ID
    $self->projectid( $details{projectid} );

    # indicate that we used an MSBID
    $usingmsbid = 1;

  } elsif (exists $args{checksum}) {
    $checksum = $args{checksum};
  } else {
    throw OMP::Error::BadArgs("No checksum or MSBid provided. Unable to retrieve MSB.");
  }

  # Retrieve the relevant science program
  my $sp = $self->fetchSciProg(1);

  # Get the MSB
  my $msb = $sp->fetchMSB( $checksum );

  # if we did not get an MSB back this means the checksums
  # are now different to what was stored in the database
  # if the checksum was requested we provide a different error to
  # that triggered if we got an msbid
  unless ($msb) {
    if ($usingmsbid) {
      # used an MSBID
      throw OMP::Error::FatalError("A checksum was obtained from the database table but there was no corresponding MSB in the science program. This likely means that the checksum calculation has been changed/broken since the Science Program was submitted");
    } else {
      # user supplied checksum
      throw OMP::Error::MSBMissing("Unable to retrieve MSB in science program - the required checksum does not match any current MSBs.");
    }
  }

  # To aid with the translation to a sequence we now
  # have to add checksum and projectid as explicit elements
  # in each SpObs in the MSB (since each SpObs is translated
  # independently). We use "msbid" and "project" as tag names
  # since they match the FITS headers.
  $msb->addFITStoObs;

  # Update the msb done table to indicate that we have retrieved an
  # MSB.  This is needed so that the done table includes all MSBs that
  # have been retrieved such that the information can be associated
  # with done flags and comments even if the MSB is removed from the
  # science program during the observation. This requires a transaction.
  # Connect to the DB (and lock it out)
  $self->_notify_msb_done( $checksum, $sp->projectID, $msb,
			   "MSB retrieved from DB", OMP__DONE_FETCH );

  return $msb;
}

=item B<queryMSB>

Query the database for the MSBs that match the supplied query.

  @results = $db->queryMSB( $query );

The query is represented by an C<OMP::MSBQuery> object.  By default
the result is returned as an array of XML strings. Alternative formats
are those supported by C<OMP::Info::MSB::summary> with the caveat that
the results are returned in an array where each msb summary is
executed in scalar context. A special option of 'object' will cause
the results to be returned directly as an array of C<OMP::Info::MSB>
objects.

  @results = $db->queryMSB( $query, $format );

The results are actually summaries of the table entries rather than
direct summaries of MSBs. It is assumed that the table contains
all the necessary information from the MSB itself so that there is
no need to open each science program to obtain more information.

=cut

sub queryMSB {
  my $self = shift;
  my $query = shift;
  my $format = shift;
  $format ||= 'xmlshort';

  # Run the query and obtain an array of hashes in order up to
  # the maximum number
  my @results = $self->_run_query($query);

  return @results if $format eq 'object';

  # Now go through the hash and translate it to an XML string
  # This assumes that the database table contains everything
  # we need for a summary (ie we don't want to have to open
  # up the science programs to get extra information)
  # We also will need to fix the order at some point since the
  # QT will probably be relying on it for display
  # Use the OMP::MSB code to generate an MSBSummary
  # (since that is the code used to generate the table entry)

  my @xml = map { scalar($_->summary($format))  } @results;

  return @xml;
}

=item B<doneMSB>

Mark the specified MSB as having been observed.

  $db->doneMSB( $checksum );

Optionally takes a second argument, a C<OMP::Info::Comment> object
containing an override comment and associated user.

  $db->doneMSB( $checksum, $comment );

The MSB is located using the Project identifier (stored in the object)
and the checksum.  If an MSB can not be located it is likely that the
science program has been reorganized.

This method locks the database since we are modifying the database
tables. We do not want to retrieve a science program, modify it and
store it again if someone has modified the science program between us
retrieving and storing it.

The time remaining on the project is decremented by the estimated
time taken to observe the MSB (via OMP::TimeAcctDB).

Invokes the C<hasBeenObserved> method on the MSB object.

Configuration arguments can be supplied via a reference to a hash
as the last argument.

The only configuration option is

  adjusttime => 1/0

Default is to adjust the time accounting when accepting an MSB. If this
argument is false the time pending will not be incremented.

  $db->doneMSB( $checksum, { adjusttime => 0 });
  $db->doneMSB( $checksum, $comment, { adjusttime => 0 });

=cut

sub doneMSB {
  my $self = shift;
  my $checksum = shift;

  # If last arg is a hash read it off
  my %optargs = ( adjusttime => 1 );
  if (ref($_[-1]) eq 'HASH') {
    # Remove last element from @_
    my $newopt = pop(@_);
    %optargs = (%optargs, %$newopt);
  }

  # Now read the comment assuming any args remain
  my $comment = shift;

  OMP::General->log_message("Attempting to mark MSB for project ". $self->projectid . " as done [$checksum]");

  # Administrator password so that we can fetch and store
  # science programs without resorting to knowing the
  # actual password or to disabling password authentication
  $self->password("***REMOVED***");

  # Connect to the DB (and lock it out)
  $self->_db_begin_trans;
  $self->_dblock;

  # We could use the MSBDB::fetchMSB method if we didn't need the science
  # program object. Unfortunately, since we intend to modify the
  # science program we need to get access to the object here
  # Retrieve the relevant science program
  my $sp = $self->fetchSciProg(1);

  # Get the MSB
  my $msb = $sp->fetchMSB( $checksum );

  if ($msb) {
     OMP::General->log_message("MSB Retrieved successfully");
  } else {
     OMP::General->log_message("Unable to retrieve corresponding MSB");
  }

  # We are going to force the comment object through if we have one
  # This allows us to preserve date information.

  # Work out the reason and user
  my $author;
  my $reason = "MSB marked as done";
  if (defined $comment) {
    $author = $comment->author; # for logging
    my $text = $comment->text;
    if (defined $text && $text =~ /\w/) {
      # prepend a descriptive comment to current text
      $reason .= ": ".$text;
    }
    $comment->text( $reason );
  } else {
    $comment = new OMP::Info::Comment( text => $reason );
  }

  # Force status
  $comment->status( OMP__DONE_DONE );

  # Update the msb done table (need to do this even if the MSB
  # no longer exists in the science program). Note that this implies
  # the science program exists....Probably should be using self->projectid
  $self->_notify_msb_done( $checksum, $sp->projectID, $msb,
			   $comment );

  OMP::General->log_message("Marked MSB as done in the done table");

  # Give up if we dont have a match
  unless (defined $msb) {
    # Disconnect and commit the comment
    $self->_dbunlock;
    $self->_db_commit_trans;

    # and return
    return;
  }

  # Mark it as observed
  $msb->hasBeenObserved();

  OMP::General->log_message("MSB marked as done in science program object");

  # Now need to store the MSB back to disk again
  # since this has the advantage of updating the database table
  # and making sure reorganized Science Program is stored.
  # Note that we need the timestamp to change but do not want
  # feedback table notification of this (since we have done that
  # already).
  $self->storeSciProg( SciProg => $sp, NoCache => 1, NoFeedback => 1);

  OMP::General->log_message("Science program stored back to database");

  # Now decrement the time for the project if required
  if ($optargs{adjusttime}) {
    my $acctdb = new OMP::TimeAcctDB(
				     ProjectID => $sp->projectID,
				     DB => $self->db,
				    );

    # need TimeAcct object
    my $acct = new OMP::Project::TimeAcct(
					  projectid => $sp->projectID,
					  confirmed => 0,
					  date => scalar(gmtime()),
					  timespent => $msb->estimated_time,
					 );

    $acctdb->incPending( $acct );
    OMP::General->log_message("Incremented time on project");
  }

  # Might want to send a message to the feedback system at this
  # point
  $reason = '';
  if (defined $comment) {
    $reason = ": ".$comment->text
      if defined $comment->text && $comment->text =~ /\w/;
  }

  $self->_notify_feedback_system(
				 program => "OMP::MSBDB",
				 subject => "MSB Observed",
				 text => "Marked MSB with checksum"
				 . " $checksum as done $reason",
				 author => $author,
				 msgtype => OMP__FB_MSG_MSB_OBSERVED,
				);

  OMP::General->log_message("Send feedback message and complete transaction");

  # Disconnect
  $self->_dbunlock;
  $self->_db_commit_trans;

}

=item B<undoMSB>

Inrement the remaining counter of the MSB by one.

  $db->undoMSB( $checksum );

The MSB is located using the Project identifier (stored in the object)
and the checksum. If an MSB can not be located it is likely that the
science program has been reorganized.

This method locks the database since we are modifying the database
tables. We do not want to retrieve a science program, modify it and
store it again if someone has modified the science program between us
retrieving and storing it.

The time remaining on the project is not adjusted.  In most cases this
is simply the reverse of C<doneMSB> except when AND/OR logic is
involved. Note that C<doneMSB> reorganizes the MSBs to account for
logic but this can not be reversed without having knowledge of what
has changed and whether subsequent observations have occurred (the
science program is only reorganized the first time an MSB in an OR
block is observed).

=cut

sub undoMSB {
  my $self = shift;
  my $checksum = shift;

  # Administrator password so that we can fetch and store
  # science programs without resorting to knowing the
  # actual password or to disabling password authentication
  $self->password("***REMOVED***");

  # Connect to the DB (and lock it out)
  $self->_db_begin_trans;
  $self->_dblock;

  # We could use the MSBDB::fetchMSB method if we didn't need the science
  # program object. Unfortunately, since we intend to modify the
  # science program we need to get access to the object here
  # Retrieve the relevant science program
  my $sp = $self->fetchSciProg(1);

  # Get the MSB
  my $msb = $sp->fetchMSB( $checksum );

  # Update the msb done table (need to do this even if the MSB
  # no longer exists in the science program
  $self->_notify_msb_done( $checksum, $sp->projectID, $msb,
                           "MSB done status reversed.",
                           OMP__DONE_UNDONE );

  # Give up if we dont have a match
  unless (defined $msb) {
    # Disconnect and commit the comment
    $self->_dbunlock;
    $self->_db_commit_trans;

    # and return
    return;
  }

  # Mark it as not observed
  $msb->undoObserve;

  # Now need to store the MSB back to disk again
  # since this has the advantage of updating the database table
  # and making sure reorganized Science Program is stored.
  # Note that we need the timestamp to change but do not want
  # feedback table notification of this (since we have done that
  # already).
  $self->storeSciProg( SciProg => $sp, NoCache => 1, NoFeedback => 1);


  # Might want to send a message to the feedback system at this
  # point
  $self->_notify_feedback_system(
				 program => "OMP::MSBDB",
				 subject => "MSB Observe Undone",
				 text => "Incremented by 1 the number of remaining ".
                                          "observations for MSB with checksum" .
				          " $checksum",
				 msgtype => OMP__FB_MSG_MSB_UNOBSERVED,
				);

  # Disconnect
  $self->_dbunlock;
  $self->_db_commit_trans;

}

=item B<alldoneMSB>

Mark the specified MSB as having been completely observed. The number
of repeats remaining is set to the magic value indicating it has
been removed (see C<OMP::MSB::REMOVED>).

  $db->doneMSB( $checksum );

The MSB is located using the Project identifier (stored in the object)
and the checksum.  If an MSB can not be located it is likely that the
science program has been reorganized.

This method locks the database since we are modifying the database
tables. We do not want to retrieve a science program, modify it and
store it again if someone has modified the science program between us
retrieving and storing it.

No time is removed from the project since this action is not associated
with observing.

Invokes the C<hasBeenCompletelyObserved> method on the relevant MSB
object.

=cut

sub alldoneMSB {
  my $self = shift;
  my $checksum = shift;

  # Administrator password so that we can fetch and store
  # science programs without resorting to knowing the
  # actual password or to disabling password authentication
  $self->password("***REMOVED***");

  # Connect to the DB (and lock it out)
  $self->_db_begin_trans;
  $self->_dblock;

  # We could use the MSBDB::fetchMSB method if we didn't need the
  # science program object. Unfortunately, since we intend to modify
  # the science program we need to get access to the object here
  # Retrieve the relevant science program
  my $sp = $self->fetchSciProg(1);

  # Get the MSB
  my $msb = $sp->fetchMSB( $checksum );

  # Update the msb done table (need to do this even if the MSB
  # no longer exists in the science program
  $self->_notify_msb_done( $checksum, $sp->projectID, $msb,
			   "MSB removed from consideration",
			   OMP__DONE_ALLDONE );

  # Give up if we dont have a match
  unless (defined $msb) {
    # Disconnect and commit the comment
    $self->_dbunlock;
    $self->_db_commit_trans;

    # and return
    return;
  }

  $msb->hasBeenCompletelyObserved();

  # Now need to store the MSB back to disk again
  # since this has the advantage of updating the database table
  # and making sure reorganized Science Program is stored.
  # Note that we need the timestamp to change but do not want
  # feedback table notification of this (since we have done that
  # already).
  $self->storeSciProg( SciProg => $sp, NoCache => 1, NoFeedback => 1);

  # Might want to send a message to the feedback system at this
  # point
  $self->_notify_feedback_system(
				 program => "OMP::MSBDB",
				 subject => "MSB All Observed",
				 text => "Marked MSB with checksum"
				 . " $checksum as completely done",
				 msgtype => OMP__FB_MSG_MSB_ALL_OBSERVED,
				);

  # Disconnect
  $self->_dbunlock;
  $self->_db_commit_trans;

}

=item B<suspendMSB>

Cause the MSB to go into a "suspended" state such that the next
time it is translated only some of the files will be sent to
the sequencer.

The "suspended" flag is cleared only when an MSB is marked
as "done".

  $db->suspendMSB( $checksum, $label );

The label must match the observation labels generated by the
C<unroll_obs> method in C<OMP::MSB>. This label is used by the
translator to determine which observation to start at.

Nothing happens if the MSB can no longer be located since this
simply indicates that the science program has been reorganized
or the MSB modified.

An optional comment object can be supplied to associate the
action with a particular reason and observer.

  $db->suspendMSB( $checksum, $label, $comment);

=cut

sub suspendMSB {
  my $self = shift;
  my $checksum = shift;
  my $label = shift;
  my $comment = shift;

  # Administrator password so that we can fetch and store
  # science programs without resorting to knowing the
  # actual password or to disabling password authentication
  $self->password("***REMOVED***");

  # Connect to the DB (and lock it out)
  $self->_db_begin_trans;
  $self->_dblock;

  # We could use the MSBDB::fetchMSB method if we didn't need the science
  # program object. Unfortunately, since we intend to modify the
  # science program we need to get access to the object here
  # Retrieve the relevant science program
  my $sp = $self->fetchSciProg(1);

  # Get the MSB
  my $msb = $sp->fetchMSB( $checksum );

  # Update the msb done table (need to do this even if the MSB
  # no longer exists in the science program BUT make sure the
  # message is different in that case
  my $msg;
  if (defined $msb) {
    $msg = "MSB suspended at observation $label.";
  } else {
    $msg = "Attempted to suspend MSB at observation $label but the MSB is no longer in the science program.",

  }

  # Work out the reason and user
  my $author;
  if (defined $comment) {
    $author = $comment->author;
    $msg .= ": ". $comment->text
      if defined $comment->text && $comment->text =~ /\w/;
  }


  # Might want to send a message to the feedback system at this
  # point
  # do this early in case the MSBDone message fails!
  $self->_notify_feedback_system(
				 program => "OMP::MSBDB",
				 subject => "MSB suspended",
				 text => "$msg : checksum is $checksum",
				 author => $author,
				 msgtype => OMP__FB_MSG_MSB_SUSPENDED,
				);

  # if the MSB never existed in the system this will generate an error
  # message and throw an exception. In practice this is not a problem
  # since it was clearly never retrieved from the system!
  $self->_notify_msb_done( $checksum, $sp->projectID, $msb,
			   $msg, OMP__DONE_SUSPENDED, $author );

  # Give up if we dont have a match
  unless (defined $msb) {
    # Disconnect and commit the comment
    $self->_dbunlock;
    $self->_db_commit_trans;

    # and return
    return;
  }

  # Mark it as observed
  $msb->hasBeenSuspended($label);

  # Now need to store the MSB back to disk again
  # since this has the advantage of updating the database table
  # and making sure reorganized Science Program is stored.
  # Note that we need the timestamp to change but do not want
  # feedback table notification of this (since we have done that
  # already).
  $self->storeSciProg( SciProg => $sp, NoCache => 1, NoFeedback => 1);

  # Disconnect
  $self->_dbunlock;
  $self->_db_commit_trans;

}

=item B<getSubmitted>

Return projects for which a science program has been submitted within a given
range of time.  First argument should be an epoch time representing the minimum date of
the date range.  The optional second argument should be an epoch time representing the
maximum date.  Default for maximum date is current time.  Returns an array of C<OMP::Project>
objects.

  @projects = $db->getSubmitted($lo, $hi);

=cut

sub getSubmitted {
  my $self = shift;
  my $lodate = shift;
  my $hidate = shift;

  # Default to now
  if (!$hidate) {
    my $now = OMP::General->today();
    $hidate = $now->epoch;
  }

  # Lock the db
  $self->_dblock;

  # Query the database
  my @projectids = $self->_get_submitted($lodate, $hidate);

  # Unlock the db
  $self->_dbunlock;

  # Get the project objects
  my @projects;
  for my $projectid (@projectids) {
    my $projdb = new OMP::ProjDB( DB => $self->db,
				  ProjectID => $projectid,
				  Password => $self->password, );

    my $obj  = $projdb->projectDetails('object');
    push @projects, $obj;
  }

  return @projects;
}

=item B<listModifiedPrograms>

Return an array of project IDs for projects whose programs have been modified
since the given date.

  @projects = $db->listModifiedPrograms($time);

Only argument is a C<Time::Piece> object.  If called without arguments all
programs will be returned.  Returns undef if no projects have been modified.

=cut

sub listModifiedPrograms {
  my $self = shift;
  my $date = shift;

  # No XML query interface to science programs, so we'll have to do an SQL query
  my $sql = "SELECT projectid FROM $SCITABLE WHERE timestamp > " . ($date ? $date->epoch : 0);
  my $ref = $self->_db_retrieve_data_ashash( $sql );

  my @results = map { $_->{projectid} } @$ref;
}


=cut

=back

=head2 Internal Methods

=over 4

=item B<_store_sci_prog>

Store the science program to the "database"

  $status = $db->_store_sci_prog( $sp, $freeze, $force, $nocache );

The XML is stored in the database. Transaction management deals with the
case where the upload fails part way through.

If a entry already exists in the database the timestamp is retrieved
and compared with the current version of the science program.
(using the C<timestamp> attribute of the SpProg). If they
differ the new file is not stored (the new science program should
have the timestamp of the old science program).

A timestamp is added to the science program automatically just before
it is written to the database. The overhead in fetching the timestamp
from the database is minimal compared with having to read the old
science program and instantiate a science program object in order to
read the timestamp.

If the optional second argument is present and true, timestamp
checking is disabled and the timestamp is not modified. This is to
allow internal reorganizations to use this routine without affecting
external checking.

A third (optional) argument [presence of which requires the second
argument to be supplied] can be used to disable time stamp checking
completely whilst still generating a new timestamp. This option should
be used with care and should not be used without explicit request
of the owner of the science program. Default is false.

The fourth (optional) argument [requiring the previous two optional args]
controls whether the file is written to the backup file cache or not. By
default the cache file is written unless the timestamp is to be frozen.
ie default is true is freeze is true but false otherwise.

Returns good status or throws exception on error (!!).

=cut

sub _store_sci_prog {
  my $self = shift;
  throw OMP::Error::BadArgs('Usage: $db->_store_sci_prog( $sp )') unless @_;
  my $sp = shift;

  my $freeze = shift;
  my $force = shift;


  # Default to freeze state if not defined
  my $nocache;
  if (@_) {
    $nocache = shift;
  } else {
    $nocache = $freeze;
  }



  # Check to see if sci prog exists already (if it does it returns
  # the timestamp else undef)
  my $tstamp = $self->_get_old_sciprog_timestamp;

  # If we have a timestamp we need to compare it with what we
  # have now
  if (defined $tstamp) {

    # Disable timestamp checks if freeze is set
    # or we are forcing the store
    unless ($freeze or $force) {
      # Get the timestamp from the current file (we have the old one
      # already)
      my $spstamp = $sp->timestamp;
      if (defined $spstamp) {
	throw OMP::Error::SpChangedOnDisk("Science Program has changed on disk\n")
	  unless $tstamp == $spstamp;
      } else {
	throw OMP::Error::SpChangedOnDisk("A science program is already in the database with a timestamp but this science program does not include a timestamp at all.\n")

      }
    }

    # Clear the old science program
    $self->_remove_old_sciprog;

  }

  # Put a new timestamp into the science program prior to writing
  $sp->timestamp( time() ) unless $freeze;

  # and store it
  my $exstat = $self->_db_store_sciprog( $sp );

  # For initial safety purposes, store a text version on disk
  # dont care about exit status - do not call this if we are
  # not caching
  unless ($nocache) {
    $self->_store_sciprog_todisk( $sp );
  }

  return $exstat;
}


=item B<_remove_old_sciprog>

Remove an existing science program XML from the database.

  $db->_remove_old_sciprog;

Raises SpStoreFail exception on failure.

=cut

sub _remove_old_sciprog {
  my $self = shift;
  my $proj = $self->projectid;

  $self->_db_delete_data( $SCITABLE, "projectid = '$proj' ");

}

=item B<_get_old_sciprog_timestamp>

This retrieves the timestamp of a science program as stored 
in the "database". If no such science program exists returns
undef.

This can be used to check existence.

Currently we retrieve the timestamp from a database table.

=cut

sub _get_old_sciprog_timestamp {
  my $self = shift;
  my $proj = $self->projectid;

  # Construct and run the query
  my $sql = "SELECT timestamp FROM $SCITABLE WHERE projectid = '$proj'";
  my $ref = $self->_db_retrieve_data_ashash( $sql );

  # Assume that no $ref means no entry in db
  return undef unless defined $ref;

  # Assume that an emptry array means no entry in db
  return undef unless @$ref;

  my $tstamp = $ref->[0]->{timestamp};
  return $tstamp;
}

=item B<_db_store_sciprog>

Store a science program in the database. Assumes the database is ready
to accept an insert.

 $self->_db_store_sciprog( $sp );

Return true on success or throws an exception on failure.

=cut

sub _db_store_sciprog {
  my $self = shift;
  my $sp = shift;
  my $proj = $self->projectid;

  print "Entering _db_store_sciprog\n" if $DEBUG;
  print "Timestamp: ", $sp->timestamp,"\n" if $DEBUG;
  print "Project:   ", $proj,"\n" if $DEBUG;

  # Escape characters
  # For some reason the DB upload does not allow single quotes
  # even when they are escaped. We get around this by replacing
  # a single quote with literal &apos;. Ironically this is what is
  # in the XML saved by the OT - for some reason the XML::LibXML parser
  # manages to translate the &apos; to a single quote for me
  # "automagically". This is a KLUGE until I can work out how to deal
  # with single quotes properly.
  my $spxml = "$sp";
  $spxml =~ s/\'/\&apos;/g;

  # Insert the data into the science program
  $self->_db_insert_data($SCITABLE,
			 $proj, $sp->timestamp,
			 {
			  TEXT => $spxml,
			  COLUMN => 'sciprog',
			 }
			);


  # Now fetch it back to check for truncation issues
  # This adds quite a bit of overhead. XXXX remove before release
  my $xml = $self->_db_fetch_sciprog();
  $xml =~ s/\&apos;/\'/g; # level the playing field
  if (length($xml) ne length("$sp")) {
    my $orilen = length("$sp");
    my $newlen = length($xml);
    my $retrvtxt = "";
    $retrvtxt = "['$xml']" if $newlen < 30;
    throw OMP::Error::SpStoreFail("Science program was truncated during store (now $newlen $retrvtxt rather than $orilen)\n");
  }

  return 1;
}

=item B<_store_sciprog_todisk>

Write the science program to disk. A new version is created for each
submission.

  $db->_store_sciprog_todisk( $sp );

This method exists simply to store old versions of science programmes
as backups in case the database goes down. Once we feel confident
with the database backup system we will remove this overhead.

If we can not open the file send an email.

This method is not meant to be JAC-agnostic.

Filename separators (/) are replaced with underscores.

=cut

sub _store_sciprog_todisk {
  my $self = shift;
  my $sp = shift;

  # Directory for writing. Currently hard-wired into a location
  # on mauiola
  my $cachedir = File::Spec->catdir(File::Spec->rootdir,"omp-cache");

  # Construct a simple error message
  my ($user, $addr, $email) = OMP::General->determine_host;
  my $projectid = uc($sp->projectID);
  $projectid =~ s/\//_/g; # replace slashes with underscores
  my $err = "Error writing science program ($projectid) to disk\n" .
    "Request from $email\nReason:\n\n";
  my %deferr = ( to => [OMP::User->new(email=>'timj@jach.hawaii.edu')],
		 from => new OMP::User->new(email=>'omp_group@jach.hawaii.edu'),
		 subject => 'failed to write sci prog to disk');

  # Check we have a directory
  unless (-d $cachedir) {
    $self->_mail_information(%deferr,
			     message => "$err directory $cachedir not present"
			    );
    return;
  }

  # Open a unique output file named "projectid_NNN.xml"
  # Code stolen from SCUBA::ODF
  # First read the disk to get the number
  my $guess = $projectid . '_(\d\d\d)';
  opendir my $DIRH,$cachedir
    || do {
      $self->_mail_information(%deferr,
			       message => "$err Error reading directory $cachedir"
			      );
      return;
    };
  my @numbers = sort { $a <=> $b }
    map { /$guess/ && $1 }  grep /$guess$/, readdir($DIRH);
  closedir($DIRH);

  # First index to try
  my $start = 1 + (@numbers ? $numbers[-1] : 0 );

  # Get current umask and set to known umask
  my $umask = umask;
  umask(066);

  # Now try to open the file up to 20 times
  # The looping is not really required if combined with the
  # readdir (it simply allows for a number of concurrent accesses
  # by different threads).
  # If we turn off the readdir we will need to make sure this number
  # matches the number of digits supported in INDEX.
  my $MAX_TRIES = 20;
  my $fmt = '%s_%03d';
  my ($fh, $file);
  my $end = $MAX_TRIES + $start;
  for (my $i = $start; $i < $end; $i++) {

    # Create the file name
    my $file = File::Spec->catfile($cachedir,
				   sprintf($fmt,$projectid,$i));

    my $open_success = sysopen($fh, $file,
                               O_CREAT|O_RDWR|O_EXCL,0600);

    if ($open_success) {
      # abort the loop
      last;
    } else {
      # Abort with error if there was some error other than
      # EEXIST
      unless ($!{EEXIST}) {
        umask($umask);
	$self->_mail_information(%deferr,
				 message => "$err Could not create temp file $file: $!"
			      );
	return;

      }
      # clear the file handle so that we can know on exit of the loop
      # whether we did a good open.
      undef $fh;
    }

    # Loop for another try
  }

  # reset umask
  umask($umask);

  # if we do not have a filehandle we need to abort
  if (!$fh) {
    $self->_mail_information(%deferr,
			     message => "$err Could not create temp file after $MAX_TRIES attempts!!!"
			    );
    return;
  }

  # Now write the science program and return
  print $fh "$sp";
  close $fh;

  # And remove old numbers
  if (@numbers > 3) {
    my $last = $#numbers - 3;
    for my $n (@numbers[0..$last]) {
      my $file = File::Spec->catdir($cachedir,
				    sprintf($fmt,$projectid,$n));
      # do not test return value
      unlink($file);
    }
  }

  return;
}

=item B<_db_fetch_sciprog>

Retrieve the XML from the database and return it.

  $xml = $db->_db_fetch_sciprog();

Note this does not return a science program object (although I cant
think of a good reason why).

=cut

sub _db_fetch_sciprog {
  my $self = shift;
  my $proj = $self->projectid;
  my $dbh = $self->_dbhandle;
  throw OMP::Error::DBError("Database handle not valid") unless defined $dbh;

  # need to set the textsize to a value large enough to contain
  # the science program itself. I would like to do this by setting
  # it to the length of the current science program but frossie
  # insists that I just pick a large number and be done with it
  # (until the JCMT board is over) - that is a funny comment given the 
  # timescales
  my $sql = ($self->db->has_textsize ? "SET TEXTSIZE 330000000" : "" ) .
    "(SELECT sciprog FROM $SCITABLE WHERE projectid = '$proj')";

  # Run the query
  my $ref = $self->_db_retrieve_data_ashash( $sql );

  # It is not there!
  throw OMP::Error::SpRetrieveFail("Science program does not seem to be in database") unless @$ref;

  return $ref->[0]->{sciprog};
}

=item B<_get_next_msb_index>

Return the primary index to use for each row in the MSB database. This
number is determined to be unique for all entries ever made.

The current index is obtained by reading the highest value from the 
database. For efficiency we only want to do this once per transaction.

In order to guarantee uniqueness it should be obtained before the old
rows are removed.

=cut

sub _get_next_index {
  my $self = shift;

  # Return the current max index
  my $max = $self->_db_findmax( $MSBTABLE, "msbid" );

  # Get the next highest
  $max++;

  return $max;
}

=item B<_verify_project_exists>

Looks in the project database to determine whether the project ID
defined in this object really does exist.

Throws OMP::Error::UnknownProject exception.

=cut

sub _verify_project_exists {
  my $self = shift;

  # Ask the project DB class
  my $proj = new OMP::ProjDB(
			     ProjectID => $self->projectid,
			     DB => $self->db,
			     Password => $self->password,
			    );
  my $there = $proj->verifyProject();

  throw OMP::Error::UnknownProject("Project ".$self->projectid .
				   " does not exist. Please try another project id" ) unless $there;
  return 1;
}

=item B<_verify_project_password>

Verify that the supplied plain text password matches the encrypted
password in the project database. This is just a thin wrapper around
C<OMP::ProjDB::verifyPassword>.

  $db->_verify_project_password();

The project ID, database connection and password are obtained from the
object.

Throws C<OMP::Error::Authentication> exception if the password does
not match.

If the password matches the administrator password this routine always
succeeds.

If the optional argument is set to true, an additional comparison with
the staff password will be used before querying the project
database. In some cases staff can have access to project data and this
provides a means to give some staff access without giving full
administrator access.

  $db->_verify_project_password( $allow_staff );

THIS DOES NOT WORK AT THE MOMENT BECAUSE THE OMP::PROJECT CLASS
ALWAYS CHECKS AGAINST STAFF,ADMIN AND QUEUE PASSWORD ANYWAY

=cut

sub _verify_project_password {
  my $self = shift;
  my $allow_staff = shift;

  # Is the staff password sufficient?
  if ($allow_staff) {
    # dont throw an exception on failure
    return if OMP::General->verify_administrator_password($self->password, 1);
  }

  # Ask the project DB class
  my $proj = new OMP::ProjDB(
			     ProjectID => $self->projectid,
			     DB => $self->db,
			     Password => $self->password,
			    );

  $proj->verifyPassword()
    or throw OMP::Error::Authentication("Incorrect password for project ID ".
					$self->projectid );

  return;
}

=item B<_password_text_info>

Retrieve some text describing whether the password was actually the
staff, administrator or queue password. This can be appendended to
feedback messages. Returns empty string if the actual project
password was used.

  $string = $self->_password_text_info();

The assumption is that the password will verify against the project.
Requires that the project details are retrieved from the project
database. This is required in order to determine the associated
queue information.

=cut

sub _password_text_info {
  my $self = shift;
  my $password = $self->password();

  my $note = '';
  if (OMP::General->verify_administrator_password( $password, 1)) {
    $note = "[using the administrator password]"
  } elsif (OMP::General->verify_staff_password( $password, 1)) {
    $note = "[using the staff password]"
  } else {
    # get database connection
    my $projdb = new OMP::ProjDB(
				 ProjectID => $self->projectid,
				 DB => $self->db,
				 Password => $self->password,
				);

    # get the project information
    my $proj = $projdb->projectDetails('object');

    if ($proj && OMP::General->verify_queman_password($password, $proj->country, 1)) {
      $note = "[using the ".$proj->country." queue manager password]";
    }


  }

}

=back

=head2 DB Connectivity

These methods connect directly to the database. If the database is changed
(for example to move to DB_File or even Storable) then these are the
only routines that need to be modified.

=over 4

=item B<_insert_rows>

Insert all the rows into the MSB and Obs database using the information
provided in the array of hashes:

  $db->_insert_rows( @summaries );

where @summaries contains elements of class C<OMP::Info::MSB>.

=cut

sub _insert_rows {
  my $self = shift;
  my @summaries = @_;

  # Get the next index to use for the MSB table
  my $index = $self->_get_next_index();

  # We need to remove the existing rows associated with this
  # project id
  $self->_clear_old_rows;

  # Get the DB handle
  my $dbh = $self->_dbhandle or
    throw OMP::Error::DBError("Database handle not valid");

  # Now loop over each summary inserting the information 
  for my $summary (@summaries) {

    # Add the contents to the database
    $self->_insert_row( $summary,
			dbh  => $dbh,
			index=> $index,
		      );

    # increment the index for next pass
    $index++;

  }

}


=item B<_insert_row>

Insert a row into the database using the information provided in the
C<OMP::Info::MSB> object.

  $db->_insert_row( $info, %config );

The contents of the hash are usually obtained by calling the
C<info> method of the C<OMP::MSB> class.

This method inserts MSB data into the MSB table and the observation
summaries into the observation table.

Usually called from C<_insert_rows>. Expects the config hash to include
special keys:

  index  - index to use for next MSB row
  dbh    - the database handle

that are used to share state between row inserts. This provides
quite a large optimization over obtaining the index from the database
each time. Note that DBI can not support multiple statement
handles and rollbacks simultaneously. Therefore we can not prepare
the MSB insert in advance whilst also supporting an MSBOBS statement
handle. Since there will be more MSBOBS inserts than MSB inserts
(in general) we only use a statement handle for the MSBOBS table.

=cut

sub _insert_row {
  my $self = shift;
  my $msbinfo = shift;
  my %config = @_;

  print "Entering _insert_row\n" if $DEBUG;

  # Get the next index
  my $index = $config{index};

  # Get the database handle from the hash
  my $dbh = $config{dbh} or
    throw OMP::Error::DBError("Database handle not valid in _insert_row");

  # Get the MSB summary
  my %data = $msbinfo->summary('hashlong');
  $data{obscount} = $msbinfo->obscount;

  # Throw an exception if we are missing tau or seeing
  throw OMP::Error::SpBadStructure("There seems to be no site quality information. Unable to schedule MSB.\n")
    unless (defined $data{seeing} and defined $data{tau});

  # Throw an exception if we are missing observations
  throw OMP::Error::MSBMissingObserve("1 or more of the MSBs is missing an Observe\n") if $data{obscount} == 0;

  # Store the data
  my $proj = $self->projectid;
  print "Inserting row as index $index\n" if $DEBUG;
  OMP::General->log_message( "Inserting MSB row as index $index [$proj]");

  # If the upper limits for range variables are undefined we
  # need to specify an infinity ourselves for the database
  my $seeingmax = ( $data{seeing}->max ? $data{seeing}->max : $INF{seeing});
  my $taumax = ( $data{tau}->max ? $data{tau}->max : $INF{tau});

  # If a max or minimum elevation has not been supplied we do not care.
  # A NULL can be stored in the table. We will calculate a suitable
  # minimum elevation when we fetch the entries from the database.
  my ($maxel, $minel);
  if ($data{elevation}) {
    ($minel, $maxel) = $data{elevation}->minmax;
  }

  # cloud and moon are implicit ranges

  # Insert the MSB data
  $self->_db_insert_data( $MSBTABLE,
			  $index, $proj, $data{remaining}, $data{checksum},
			  $data{obscount}, $data{tau}->min, $taumax, 
			  $data{seeing}->min, $seeingmax, $data{priority},
			  $data{telescope}, $data{moon}, $data{cloud},
			  $data{timeest}, $data{title},
			  "$data{datemin}", "$data{datemax}", $minel,
			  $maxel, $data{approach});

  # Now the observations
  # We dont use the generic interface here since we want to
  # reuse the statement handle
  # Get the observation query handle
  my $obsst = $dbh->prepare("INSERT INTO $OBSTABLE VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)")
    or throw OMP::Error::DBError("Error preparing MSBOBS insert SQL: $DBI::errstr\n");

  my $count;
  for my $obs (@{ $data{observations} }) {

    $count++;

    # Get the obs id (based on the msb id)
    my $obsid = sprintf( "%d%03d", $index, $count);

    # If coordinates have not been set then we need to raise an exception
    # since we can not schedule this. Note that calibrations
    # will come back as Astro::Coords::Calibration
    unless (exists $obs->{coords} and defined $obs->{coords} 
	   and UNIVERSAL::isa($obs->{coords},"Astro::Coords")) {
      throw OMP::Error::SpBadStructure("Coordinate information could not be found in an MSB. Unable to schedule.\n");
    }
    my @coords = $obs->{coords}->array;

    # If we dont have an instrument we raise an exception
    unless (exists $obs->{instrument} and defined $obs->{instrument}) {
      throw OMP::Error::SpBadStructure("No instrument defined in MSB. Unable to schedule.\n");
    }

    # Wavelength must be a number (just check for presence of any number)
    $obs->{wavelength} = $obs->{waveband}->wavelength if $obs->{waveband};
    $obs->{wavelength} = -1 unless (defined $obs->{wavelength} and 
                                     $obs->{wavelength} =~ /\d/);

    $obsst->execute(
		    $obsid, $index, $proj, uc($obs->{instrument}), 
		    $obs->{type}, $obs->{pol}, $obs->{wavelength},
		    $obs->{disperser},
		    $obs->{coords}->type, $obs->{target},
		    @coords[1..10], $obs->{timeest}
		   )
      or throw OMP::Error::DBError("Error inserting new obs rows: $DBI::errstr");

  }

}


=item B<_clear_old_rows>

Remove all rows associated with the current project ID.

If this is combined with an insert then care should be taken
to make sure that a single database transaction is being used
(see C<_db_begin_trans>). This will guarantee that the old rows
can not be removed without inserting new ones.

=cut

sub _clear_old_rows {
  my $self = shift;

  # Get the DB handle
  my $proj = $self->projectid;

  # Remove the old data
  print "Clearing old msb and obs rows for project ID $proj\n" if $DEBUG;
  $self->_db_delete_project_data( $MSBTABLE, $OBSTABLE );

}

=item B<_fetch_row>

Retrieve a row of information from the database table.

  %result = $db->_fetch_row( msbid => $key );

The information is returned as a hash with keys identical to
the database column names.

The query will be formed by using any or all of C<checksum>,
C<id> and C<projectid> depending on whether they are set in the
argument hash or in the object.

Returns empty list if no match can be found.

=cut

sub _fetch_row {
  my $self = shift;
  my %query = @_;

  # Get the project id if it is here
  $query{projectid} = $self->projectid
    if defined $self->projectid;

  # Assume that query keys match column names
  my @substrings = map { " $_ = ? " } sort keys %query;

  # and construct the SQL command using bind variables so that 
  # we dont have to worry about quoting
  my $sql = "SELECT * FROM $MSBTABLE WHERE" .
    join("AND", @substrings);
  print "STATEMENT: $sql\n" if $DEBUG;

  # Run the query
  my $ref = $self->_db_retrieve_data_ashash($sql,
					    map { $query{$_} } sort keys %query
					   );

  # Dont throw an error here. It is up to the caller to decide whether
  # to do or not.
#  throw OMP::Error::DBError("Error fetching specified row - no matches for [$sql]")
#    unless @$ref;

  # The result is now the first entry in @$ref
  my %result;
  %result = %{ $ref->[0] } if @$ref;

  return %result;
}

=item B<_run_query>

Run a query on the database table using an C<OMP::MSBQuery> object and
return the matching rows (up to a maximum number) as an array of hash
references.

  @results  = $db->_run_query( $query );

The query object controls the maximum number of results that
can be retrieved (see L<OMP::MSBQuery/maxCount>).

=cut

sub _run_query {
  my $self = shift;
  my $query = shift;

  # Get the sql
  my $sql = $query->sql( $MSBTABLE, $OBSTABLE, $PROJTABLE,
			 $OMP::ProjDB::PROJQUEUETABLE,
			 $OMP::ProjDB::PROJUSERTABLE );

  # Run the initial query
  my $ref = $self->_db_retrieve_data_ashash( $sql );

#  print Dumper($ref);
  # No point hanging around if nothing retrieved
  return () unless @$ref;

  throw OMP::Error::MSBMalformedQuery("Result of query did not include msbid field!") unless exists $ref->[0]->{msbid};

  # Now for each MSB we need to retrieve all of the Observation
  # information and store it in the results hash
  # Convention dictates that this information ...???
  # We can not simply extract all the MSBIDs in one go since we
  # will overflow the query buffer. Need to split the list into
  # chunks and query each in turn. Abort the loop once we hit
  # the requisite number of matches.

  # For now kluge it so that we do the fetch for all the MSBIDs
  # even if we know that we only need the first few from the first
  # query (assuming they match the observability constraints). When
  # we have time we should either think of a better way of doing this
  # in the SQL or at least expand the loop to include the observability
  # tests, jumping out when we have enough matches.
  my $MAX_ID = 250;
  my @observations;
  my $start_index = 0;
  # make sure we use <= in case we have, say, 1 MSB matching
  # so that 0 (index) <= 0 ($#$ref)
  while ($start_index <= $#$ref) {
    my $end_index = ( $start_index + $MAX_ID < $#$ref ?
		    $start_index + $MAX_ID : $#$ref);
    my @clauses = map { " msbid = ".$_->{msbid}. ' ' }
      @$ref[$start_index..$end_index];
    $sql = "SELECT * FROM $OBSTABLE WHERE ". join(" OR ", @clauses);
    my $obsref = $self->_db_retrieve_data_ashash( $sql );
    push(@observations, @$obsref);
    $start_index = $end_index + 1;
  }

  # Now loop over the results and store the observations in the
  # correct place. First need to create the obs arrays by msbid
  # (using msbid as key)
  my %msbs;
  for my $row (@observations) {
    my $msb = $row->{msbid};
    if (exists $msbs{$msb}) {
      push(@{$msbs{$msb}}, $row);
    } else {
      $msbs{$msb} = [ $row ];
    }
    delete $row->{msbid}; # not needed

    # Create the waveband objects
    # Only create the coordinate object if required since there is
    # some overhead involved and we don't want to do it for every single
    # row since there could be thousands of observations even though
    # we only need the first 10
    $row->{waveband} = new Astro::WaveBand(Instrument => $row->{instrument},
					   Wavelength => $row->{wavelength});

  }

  # And now attach it to the relevant MSB
  # If there are no observations this will store undef (will happen
  # if a dummy science program is uploaded)
  for my $row (@$ref) {
    my $msb = $row->{msbid};
    $row->{observations} = $msbs{$msb};

    # delete the spurious "nobs" key that is created by the join
    delete $row->{nobs};

    # and move the newpriority column over the priority since
    # I have not yet worked out how to force PostGres to order by
    # a new column that matches a previous column
    $row->{priority} = $row->{newpriority} if exists $row->{newpriority};
    delete $row->{newpriority};

  }

  # Now to limit the number of matches to return
  # Determine how many MSBs we have been asked to return
  my $max = $query->maxCount;

  # An array to store the successful matches
  my @observable;

  # Decide whether to do an explicit check for observability
  if (0) {

    # Slice if necessary
    if (defined $max) {
      $max--; # convert to index
      $max = ( $max < $#$ref && $max > -1 ? $max : $#$ref);
    } else {
      $max = $#$ref;
    }
    @observable = @$ref[0..$max];

  } else {

    # KLUGE *******************************
    # Since we do not yet have a stored procedure to calculate whether
    # the target is observable we have to do it by hand for each
    # observation in an MSB
    # Note that we have to be careful about the following:
    #  1. Checking that the observation is above that requested
    #     in SpSchedConstraint
    #  2. Checking that the target is within the allowed range
    #     (between 10 and 87 deg el at JCMT and 
    #      HA = +/- 4.5h and dec > -42 and dec < 60 deg at UKIRT )
    #  3. Check that it stays within that range for the duration
    #     of the observation
    #  4. As a final check make sure that the last target in an MSB
    #     has not set by the time the first has finished.
    #     (this happens automatically since we increment the reference
    #     date by the estimated duration of each observation)

    # The reference date is obtained from the query. It will either
    # be the current time or a time that was specified in the query.
    my $refdate = $query->refDate;


    # Determine whether we are interested in checking for
    # observability. We cant jump out the for loop because
    # the person receiving the query will still want to 
    # know hour angle and things
    my %qconstraints = $query->constraints;

    # Get the elevation/airmass and hour angle constraints
    my $amrange = $query->airmass;
    my $harange = $query->ha;

    # Loop over each MSB in order
    for my $msb ( @$ref ) {

      # Reset the reference time for this msb
      my $date = $refdate;

      # Get the telescope name from the MSB and create a telescope object
      my $telescope = new Astro::Telescope( $msb->{telescope} );

      # Use a flag variable to indicate whether all
      # the observations are observable
      # Begin by assuming all is okay so that we can drop out the
      # loop and unset it on failure
      my $isObservable = 1;

      # in the current design minimum elevation constraints are a function
      # of the MSB and not the Observation itself. The hope is that most
      # people will be happy with defaults and that most MSBs contain
      # a single science target anyway.
      # For now default the min elevation to 0 degrees if it has not
      # been stored in the table.  In the final version we should default
      # to some value corresponding the minimum of 30 degrees and the
      # the elevation required for the source to be available at least 50
      # per cent of the time it is above the horizon. This will require
      # we run through all the observations to determine this. Hope that
      # overhead is not too great given that this quantity could be
      # calculated as a static value at submission time.
      # [and we may well do that eventually]
      # THIS MUST BE IN DEGREES
      my $minel = $msb->{minel};
      $minel = 30 unless defined $minel; # use 30 for now as min
      $minel *= Astro::SLA::DD2R; # convert to radians

      my $maxel = $msb->{maxel};
      $maxel *= Astro::SLA::DD2R if defined $maxel;

      # create the range object
      my $elconstraint = new OMP::Range( Max => $maxel, Min => $minel );

      # Rising or setting can be done simply by multiplying
      # the hour angle by the approach value. If they are the
      # same sign we get a positive number and so match,
      # If we have no preference simply use zero
      my $approach = $msb->{approach};
      $approach = 0 unless defined $approach;

      # Loop over each observation.
      # We have to keep track of the reference time
      OBSLOOP: for my $obs ( @{ $msb->{observations} } ) {

	# Create the coordinate object in order to calculate
	# observability. Special case calibrations since they
	# are difficult to spot from looking at the standard args
	if ($obs->{coordstype} eq 'CAL') {
	  $obs->{coords} = new Astro::Coords();
	} else {
	  my %coords;
	  my $coordstype = $obs->{coordstype};
	  if ($coordstype eq 'RADEC') {
	    %coords = (
		       ra => $obs->{ra2000},
		       dec => $obs->{dec2000},
		       type => 'J2000',
		      );
	  } elsif ($coordstype eq 'PLANET') {
	    %coords = ( planet => $obs->{target});
	  } elsif ($coordstype eq 'ELEMENTS') {

	    %coords = (
		       # For up-ness tests we do not need
		       # the epoch of perihelion
		       elements => {
				    EPOCH => $obs->{el1},
				    ORBINC => $obs->{el2},
				    ANODE => $obs->{el3},
				    PERIH => $obs->{el4},
				    AORQ => $obs->{el5},
				    E => $obs->{el6},
				    AORL => $obs->{el7},
				    DM => $obs->{el8},
				   },
		      );
	  } elsif ($coordstype eq 'FIXED') {
	    %coords = ( az => $obs->{ra2000},
			el => $obs->{dec2000});
	  }
	  $coords{name} = $obs->{target};

	  # and create the object
	  $obs->{coords} = new Astro::Coords(%coords);

	  # throw if we have a problem
	  throw OMP::Error::FatalError("Major problem generating coordinate object from ". Dumper($msb,\%coords)) unless defined $obs->{coords};


	}

	# Get the coordinate object.
	my $coords = $obs->{coords};

	# throw if we have a problem
	throw OMP::Error::FatalError("Major problem generating coordinate object") unless defined $coords;

	# Set the teelscope
	$coords->telescope( $telescope );

	# Loop over two times. The current time and the current
	# time incremented by the observation time estimate
	# Note that we do not test for the case where the source
	# is not observable between the two reference times
	# For example at JCMT where the source may transit above
	# 87 degrees
	for my $delta (0, $obs->{timeest}) {

	  # increment the date
	  $date += $delta;

	  # Set the time in the coordinates object
	  $coords->datetime( $date );

	  # If we are a CAL observation just skip
	  # make sure to add the time estimate though!
	  next if $obs->{coordstype} eq 'CAL';

	  # Now see if we are observable (dropping out the loop if not
	  # since there is no point checking further) This knows about
	  # different telescopes automatically Also check that we are
	  # above the minimum elevation (which is not related to the
	  # queries but is a scheduling constraint)
	  # In some cases we dont even want to test for observability
	  if ($qconstraints{observability}) {
	    if  ( ! $coords->isObservable or
		  ! $elconstraint->contains( $coords->el ) or
		  ! ($coords->ha(normalize=>1)*$approach >= 0)
		) {
	      $isObservable = 0;
	      last OBSLOOP;
	    }
	  }

	  # Now check for hour angle and elevation constraints
	  # imposed from the query.
	  if ($harange) {
	    unless ($harange->contains($coords->ha(format => 'h',normalize=>1))) {
	      $isObservable = 0;
	      last OBSLOOP;
	    }
	  }
	  if ($amrange) {
	    unless ($amrange->contains($coords->airmass)) {
	      $isObservable = 0;
	      last OBSLOOP;
	    }
	  }


	}

      }

      # If the MSB is observable store it in the output array
      if ($isObservable) {
	push(@observable, $msb);

	# Jump out the loop if we have enough matches
	# A negative $max will never match
	last if scalar(@observable) == $max;

      }

    }

  }

  # Now fix up the seeing and tau entries so that they
  # are OMP::Range objects rather than max and min
  for my $msb (@observable) {
    for my $key (qw/ tau seeing /) {

      # Determine the key names
      my $maxkey = $key . "max";
      my $minkey = $key . "min";

      # If we have an open ended range we need to
      # specify undef for the limit rather than the magic
      # value (since OMP::Range understands lower limits)
      $msb->{$maxkey} = undef if (defined $msb->{$maxkey} && 
				  $msb->{$maxkey} == $INF{$key});

      # Set up the array
      $msb->{$key} = new OMP::Range( Min => $msb->{$minkey},
				     Max => $msb->{$maxkey});

      # Remove old entries from hash
      delete $msb->{$maxkey};
      delete $msb->{$minkey};

    }
  }

  # Now convert the hashes to OMP::Info objects
  for my $msb (@observable) {

    # Fix up date objects - should be OMP::Range
    for (qw/ datemax datemin /) {
      $msb->{$_} = OMP::General->parse_date( $msb->{$_});
    }

    # Observations
    for my $obs (@{$msb->{observations}}) {
      $obs = new OMP::Info::Obs( %$obs );
    }
    $msb = new OMP::Info::MSB( %$msb );
  }

  return @observable;
}

=back

=head2 Done table

=over 4

=item B<_notify_msb_done>

Send a message to the MSB done system so that the message can be
stored in the done table.

  $self->_notify_msb_done( $checksum, $projectid, $msb,
			   "MSB retrieved from DB", OMP__DONE_FETCH,
			   $user,
			 );

The arguments are:

  checksum - MSB checksum (determined from msb if undef)
  projectid - Associated project ID (determined from object if undef)
  msb - The MSB object (optional)
  message - the required message
  status - the type of message (see OMP::Constants)
  user   - OMP::User object [optional]

This is a thin wrapper around C<OMP::MSBDoneDB::addMSBcomment>.

Alternatively, the comment information can be supplied in the form
of an OMP::Info::Comment object. The arguments would then be:

  checksum
  projectid
  msb  (can be undef)
  comment object

The caller is responsible for configuring the comment object so that it
includes a valid status.

=cut

sub _notify_msb_done {
  my $self = shift;
  my ($checksum, $projectid, $msb, $text, $status, $user) = @_;

  $projectid = $self->projectid
    unless defined $projectid;

  my $done = new OMP::MSBDoneDB(
				ProjectID => $projectid,
			        DB => $self->db,
			       );

  # If we have an msb object, get the info object
  # else just have the checksum
  my $info = ( $msb ? $msb->info() : $checksum);

  # if the 'text' argument is already a comment object we do not
  # need to make a comment object
  my $comment;
  if (defined $text && UNIVERSAL::isa($text,"OMP::Info::Comment")) {
    $comment = $text;

  } else {
    # Create a comment object
    $comment = new OMP::Info::Comment( text => $text,
				       status => $status);

    # Add the author if supplied
    $comment->author( $user ) if defined $user;
  }

  # Add the comment
  $done->addMSBcomment( $info, $comment );

}

=item B<_get_submitted>

Query database for projects where science program was submitted within
the given date range.  First and second arguments are the min and max
of the date range as epoch dates.  Returns an array of project IDs.

  @projectids = $db->_get_submitted($lo, $hi);

=cut

sub _get_submitted {
  my $self = shift;
  my $lodate = shift;
  my $hidate = shift;

  # Construct and run the query
  my $sql = "SELECT projectid FROM $SCITABLE WHERE timestamp between $lodate and $hidate";
  my $ref = $self->_db_retrieve_data_ashash( $sql );

  # Place the project IDs in an array
  my @projectids = map {$_->{projectid}} @$ref;

  # Return the array
  return @projectids;
}

=back


=head1 SEE ALSO

This class inherits from C<OMP::BaseDB>.

For related classes see C<OMP::ProjDB> and C<OMP::FeedbackDB>.

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
