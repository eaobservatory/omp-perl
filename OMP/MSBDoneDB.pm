package OMP::MSBDoneDB;

=head1 NAME

OMP::MSBDoneDB - Manipulate MSB Done table

=head1 SYNOPSIS

  use OMP::MSBDoneDB;

  $db = new OMP::MSBDoneDB( ProjectID => 'm01bu05',
                            DB => new OMP::DBbackend);

  @output = OMP::MSBServer->historyMSB( $checksum );
  $db->addMSBcomment( $checksum, $comment );
  @output = $db->observedMSBs( $date, $allcomments );
  @output = $db->queryMSBdone( $query, $allcomments );

=head1 DESCRIPTION

The MSB "done" table exists to allow us to associate user supplied
comments with MSBs that have been observed. It does this by having a
simple logging table where a new row is added each time an MSB is
observed or commented upon.

The existence of this table allows comments for an MSB to be
associated directly with data stored in the data archive (where the
MSB checksum will be stored in the FITS headers). There is no direct
link with the OMP MSB table. This can be thought of as a specialised
MSB Feedback table.

As each MSB comment comes in it is simply added to the table and a
status flag of previous entries is updated (set to false). One wrinkle
is that there is no guarantee that an MSB will still be in the MSB
table (science program) when the trigger to mark the MSB as done is
received (a new science program may have been submitted in the
interim). To overcome this problem a row is added to the table each
time an MSB is retrieved from the system using C<fetchMSB>- this
guarantees that the MSB summary information is available to us since
we simply read the table prior to submitting a new row.

=cut

use 5.006;
use warnings;
use strict;

use Carp;
use OMP::Error qw/ :try /;
use OMP::Constants qw/ :done /;
use OMP::Info::MSB;
use OMP::Info::Comment;
use OMP::UserServer;
use OMP::MSBDoneQuery;
use OMP::General;
use Time::Piece;

use base qw/ OMP::BaseDB /;

our $VERSION = (qw$Revision$)[1];
our $MSBDONETABLE = "ompmsbdone";

=head1 METHODS

=head2 Public Methods

=over 4

=item B<historyMSB>

Retrieve the observation history for the specified MSB (identified
by checksum and project ID) or project.

  $msbinfo = $db->historyMSB( $checksum );
  @info  = $db->historyMSB();

The information is retrieved as an C<OMP::Info::MSB> object
(with a checksum supplied) or an array of those objects.

If the checksum is not supplied a full project observation history is
returned (this is simply an array of MSB information objects).

If no checksum is supplied, returns a list when called in an array
context and a reference to an array when called in a scalar context.

One of project or checksum must be available.

=cut

sub historyMSB {
  my $self = shift;
  my $checksum = shift;

  # Construct the query
  my $projectid = $self->projectid;

  throw OMP::Error::BadArgs( "Must supply either checksum or projectid to historyMSB" )
    if (!defined $checksum && !defined $projectid);

  my $xml = '<?xml version="1.0" encoding="ISO-8859-1"?>'."\n<MSBDoneQuery>" .
    ( $checksum ? "<checksum>$checksum</checksum>" : "" ) .
      ( $projectid ? "<projectid>$projectid</projectid>" : "" ) .
	  "</MSBDoneQuery>";

  my $query = new OMP::MSBDoneQuery( XML => $xml );

  # Assume we have already got all the information
  # so we do not need to do a subsequent query
  my @responses = $self->queryMSBdone( $query );

  if ($checksum) {
    throw OMP::Error::FatalError("More than one match for checksum '$checksum' [".scalar(@responses)." matches]")
      if scalar(@responses) > 1;
    return $responses[0];
  } elsif (wantarray) {
    return @responses
  } else {
    # Scalar context and no checksum
    return \@responses;
  }
}

=item B<historyMSBtid>

Retrieve the observation history for the specified MSB transaction.

  $msbinfo = $db->historyMSBtid( $msbtid );

The information is retrieved as an C<OMP::Info::MSB> object. An exception
is thrown if the transaction ID is associated with more than one MSB.

=cut

sub historyMSBtid {
  my $self = shift;
  my $msbtid = shift;
  return unless $msbtid;
  return unless $msbtid =~ /\w/;

  # Construct the query
  my $xml = '<?xml version="1.0" encoding="ISO-8859-1"?>'."\n<MSBDoneQuery>" .
      "<msbtid>$msbtid</msbtid>" .
	  "</MSBDoneQuery>";

  my $query = new OMP::MSBDoneQuery( XML => $xml );

  # Execute the query
  my @responses = $self->queryMSBdone( $query );

  throw OMP::Error::FatalError("More than one match for MSB TID $msbtid [".scalar(@responses)." matches]")
    if scalar(@responses) > 1;

  return $responses[0];
}

=item B<addMSBcomment>

Add a comment to the specified MSB.

 $db->addMSBcomment( $checksum, $comment );

The comment is supplied as an C<OMP::Info::Comment> object (and will
therefore include a status and a date).

If the MSB has not yet been observed this command will fail
since there is no way to determine the MSB parameters.

Optionally, an object of class C<OMP::Info::MSB> can be supplied
instead of the checksum.

  $db->addMSBcomment( $msbinfo, $comment );

This can be used to extract summary information if the MSB is not
currently in the table. [No attempt is made to query the MSB table
for this information if it is unavailable.]

If a number is supplied instead of a comment object, it is assumed
to be an index into the comments contained in the C<OMP::Info::MSB>
object.

  $db->addMSBcomment( $msbinfo, $index );

It is also possible to supply the comment as a string (anything that
is not an integer or a reference will be treated as a string). The
default status of such an object would be OMP__DONE_COMMENT.

  $db->addMSBcomment( $msbinfo, $comment_string);

If no comment is supplied at all, the last comment will be extracted
from the C<OMP::Info::Comment> object (if supplied) and stored.

  $db->addMSBcomment( $msbinfo );

If the comment does not specify a status default behaviour is to treat
the comment as OMP__DONE_COMMENT. See C<OMP::Constants> for more
information on the different comment status.

=cut

sub addMSBcomment {
  my $self = shift;

  # Simple arguments
  my $msbinfo = shift;
  my $comment = shift;

  # Normalise the arguments to simplify the internal calling
  # scheme. Includes sanity checks

  # If msbinfo is not a ref hope that it is a checksum
  # Also check that we have a projectid and set the object version
  # if we dont have it there
  if (UNIVERSAL::isa($msbinfo, "OMP::Info::MSB")) {
    my $projectid = $self->projectid;
    my $msbproj   = $msbinfo->projectid;
    if (defined $projectid and !defined $msbproj) {
      $msbproj->projectid( $projectid );
    } elsif (!defined $projectid and !defined $msbproj) {
      throw OMP::Error::FatalError("Unable to determine projectid");
    } elsif (defined $msbproj and !defined $projectid) {
      $self->projectid( $msbproj );
    }

  } else {
    my $projectid = $self->projectid;
    throw OMP::Error::FatalError("checksum supplied without project ID")
      unless $projectid;
    $msbinfo = new OMP::Info::MSB( checksum => $msbinfo,
				   projectid => $projectid,
				 );
  }

  # Do we have a comment or an index (or no comment at all)
  if ($comment) {
    # See if we are a blessed reference
    if (ref($comment)) {
      # fall over if we arent a comment object
      throw OMP::Error::BadArgs("Wrong class for comment object: ". ref($comment))
	unless UNIVERSAL::isa($comment, "OMP::Info::Comment");

    } elsif ($comment =~ /^\d+$/) {
      # An integer index
      $comment = ($msbinfo->comments)[$comment];
    } else {
      # Some random text
      # Dont bother to add a status yet
      $comment = new OMP::Info::Comment( text => $comment );
    }
  } else {
    # Assume last index
    $comment = ($msbinfo->comments)[-1];
  }

  # Make sure we have a defined comment
  throw OMP::Error::BadArgs("Unable to determine comment object")
    unless defined $comment;

  # Make sure we have a checksum of some kind
  throw OMP::Error::BadArgs("Unable to determine MSB checksum")
    unless defined $msbinfo->checksum;

  # Lock the database (since we are writing)
  $self->_db_begin_trans;
  $self->_dblock;

  $self->_store_msb_done_comment($msbinfo, $comment);

  # End transaction
  $self->_dbunlock;
  $self->_db_commit_trans;

}

=item B<observedMSBs>

Return all the MSBs observed (ie "marked as done") on the specified
date. If a project ID has been set only those MSBs observed on the
date for the specified project will be returned.

  $output = $db->observedMSBs( date => $date, returnall => $allcomments );
  @output = $db->observedMSBs( date => $date, returnall => $allcomments );

The C<returnall> parameter governs whether all the comments
associated with the observed MSBs are returned (regardless of when
they were added) or only those added for the specified night. If the
value is false only the comments for the night are returned.

If no date is defined the date is not used in the query at all.
If the current UT date is required then use the "usenow" key:

  $output = $db->observedMSBs( usenow => 1, returnall => $allcomments);

"usenow" overrides any date. If neither date nor usenow are specified
no date is used in the query (ie all dates) but a project must
be specified.

The definition of "observed" includes MSBs that were completed,
rejected, suspended or aborted.

=cut

sub observedMSBs {
  my $self = shift;
  my %args = @_;

  # Do we mean today? Override if we have usenow
  my $date;
  if (exists $args{usenow} && $args{usenow}) {
    $date = OMP::General->today;
  } elsif (exists $args{date}) {
    # Use the supplied date if we have one
    $date = $args{date};

    # if the date is an object ask for "datetime"
    if (UNIVERSAL::can($date, "datetime")) {
      $date = $date->datetime;
    }

  }

  # Construct the query
  my $projectid = $self->projectid;

  my $xml = "<MSBDoneQuery>" .
    "<status>". OMP__DONE_DONE ."</status>" .
      "<status>" . OMP__DONE_REJECTED . "</status>" .
	"<status>" . OMP__DONE_SUSPENDED . "</status>" .
	  "<status>" . OMP__DONE_ABORTED . "</status>" .
            ($date ?"<date delta=\"1\">$date</date>" : "" ) .
	      ( $projectid ? "<projectid>$projectid</projectid>" : "" ) .
	        "</MSBDoneQuery>";

  my $query = new OMP::MSBDoneQuery( XML => $xml );

  my @results = $self->queryMSBdone( $query, $args{returnall} );
  return (wantarray ? @results : \@results );
}

=item B<observedDates>

Return a list of all dates on which data for the specified
project has been taken.

  @dates = $db->observedDates();

Assumes that this information can be gleaned from the MSBDone
database rather than from the data archive itself. It is arguably
more efficient to do it this way since there are far fewer MSBs
observed than actual data files.

The optional first argument controls whether the dates are
returned as an array of C<Time::Piece> objects or an array
of date strings (YYYYMMDD format).

  @objects = $db->observedDates( 1 );

Throws an exception if the project ID can not be determined from the
class (since there is no reason why you would want to ask for 
all the nights that any data was observed).

The definition of "observed" includes MSBs that were completed,
rejected, suspended or aborted.

=cut

sub observedDates {
  my $self = shift;
  my $projectid = $self->projectid;
  my $useobj = shift;

  throw OMP::Error::FatalError("observedDates method must have access to a project ID") unless $projectid;

  # Form the query
  my $xml = "<MSBDoneQuery>" .
    "<status>". OMP__DONE_DONE . "</status>" .
      "<status>" . OMP__DONE_REJECTED . "</status>" .
	"<status>" . OMP__DONE_SUSPENDED . "</status>" .
	  "<status>" . OMP__DONE_ABORTED . "</status>" .
	    "<projectid>$projectid</projectid>".
	      "</MSBDoneQuery>";

  my $query = new OMP::MSBDoneQuery( XML => $xml );

  # Execute the query - note that we dont need all the comments
  # since we are only interested in dates
  my @results = $self->queryMSBdone( $query, 0 );

  # Now need to go through each MSB forming a hash indexed by
  # the actual UT day
  my %days;
  for my $msb (@results) {
    # Get the comments
    my @comments = $msb->comments;

    for my $comment (@comments) {
      # this should always be true since that was the query
      my $cstat = $comment->status;
      if ($cstat == OMP__DONE_DONE ||
	  $cstat == OMP__DONE_REJECTED ||
	  $cstat == OMP__DONE_ABORTED ||
	  $cstat == OMP__DONE_SUSPENDED
	 ) {
	my $date = $comment->date;
	my $ut = sprintf("%04d%02d%02d", $date->year, $date->mon, $date->mday);

	# Store it in the hash
	$days{$ut}++;
      }

    }

  }

  # Now return the keys in sorted order
  # converting to objects if needed
  my @dates = sort keys %days;

  @dates = map { OMP::General->parse_date($_); } @dates
    if $useobj;

  return @dates;
}

=item B<validateMSBtid>

Confirm that the supplied MSB transaction ID is associated with the
supplied checksum.

  $result = $db->validateMSBtid;

Returns true if the MSB transaction ID is associated with this
checksum. False otherwise.

Returns true if the supplied transaction ID is undefined (since there
is no requirement for a transacton ID to be associated with an MSB).

=cut

sub validateMSBtid {
  my $self = shift;
  my $checksum = shift;
  my $msbtid = shift;
  return 1 unless defined $msbtid;

  # Query for this MSBTID
  my $msbinfo = $self->historyMSBtid( $msbtid );

  return 0 unless defined $msbinfo;
  return 1 if $msbinfo->checksum eq $checksum;
  return 0;
}

=item B<titleMSB>

Retrieve the title of the MSB associated with the supplied
checksum. This is a convenience wrapper around historyMSB. Note that
the MSB must be present in the "done" table for this to work.

  $title = $db->titleMSB( $checksum );

Returns undef if the MSBID/checksum is not known. Use
C<OMP::MSBDB->getMSBtitle> to query the active MSB table.

=cut

sub titleMSB {
  my $self = shift;
  my $checksum = shift;

  # get the MSB information 
  my $msb = $self->historyMSB( $checksum );
  return $msb->title if defined $msb;
}

=item B<queryMSBdone>

Query the MSB done table. Query must be supplied as an
C<OMP::MSBDoneQuery> object.

  @results = $db->queryMSBdone( $query, $allcomments );

The C<allcomments> parameter governs whether all the comments
associated with the observed MSBs are returned (regardless of when
they were added) or only those matching the specific query. If the
value is false only the comments matched by the query are returned.

Returns an array of results in list context, or a reference to an
array of results in scalar context.

=cut

sub queryMSBdone {
  my $self = shift;
  my $query = shift;
  my $allcomment = shift;

  # First read the rows from the database table
  # and get the array ref
  my @rows = $self->_fetch_msb_done_info( $query );

  # Now reorganize the data structure to better match
  # our output format
  my $msbs = $self->_reorganize_msb_done( \@rows );

  # If all the comments are required then we now need
  # to loop through this hash and refetch the data
  # using a different query. 
  # The query should tell us whether this is required.
  # Note that there is a possibility of infinite looping
  # since historyMSB calls this routine
  if ($allcomment) {
    foreach my $checksum (keys %$msbs) {
      # over write the previous entry
      $msbs->{$checksum} = $self->historyMSB($checksum,  'data');
    }
  }

  # Create an array from the hash. Sort by projectid
  # and then by target and date of most recent comment
  my @all = map { $msbs->{$_} }
    sort { $msbs->{$a}->projectid cmp $msbs->{$b}->projectid 
      || $msbs->{$a}->target cmp $msbs->{$b}->target 
	|| $msbs->{$a}->comments->[-1]->date <=> $msbs->{$b}->comments->[-1]->date
  } keys %$msbs;

  return (wantarray ? @all : \@all);
}


=back

=head2 Support Functions

=over 4

=item B<status_to_text>

Convert a "done" status to textual form.

  $text = OMP::MSBDoneDB::status_to_text( $status );

=cut

sub status_to_text {
  my $status = shift;
  my %lut = ( 
	     &OMP__DONE_UNDONE => 'Undone',
	     &OMP__DONE_ALLDONE => 'AllDone',
	     &OMP__DONE_COMMENT => 'Commented Upon',
	     &OMP__DONE_ABORTED => 'Aborted',
	     &OMP__DONE_REJECTED => 'Rejected',
	     &OMP__DONE_SUSPENDED => 'Suspended',
	     &OMP__DONE_DONE     => 'Accepted',
	     &OMP__DONE_FETCH    => 'Retrieved'
	    );
  if (exists $lut{$status} ) {
    return $lut{$status};
  } else {
    return "?????";
  }
}

=back

=head2 Internal Methods

=over 4

=item B<_fetch_msb_done_info>

Retrieve the information from the MSB done table using the supplied
query.  Can retrieve the most recent information or all information
associated with the MSB.

In scalar context returns the first match via a reference to a hash.

  $msbinfo = $db->_fetch_msb_done_info( $query );

In list context returns all matches as a list of hash references:

  @allmsbinfo = $db->_fetch_msb_done_info( $query );

=cut

sub _fetch_msb_done_info {
  my $self = shift;
  my $query = shift;

  # Generate the SQL
  my $sql = $query->sql( $MSBDONETABLE );

  # Run the query
  my $ref = $self->_db_retrieve_data_ashash( $sql );

  # If they want all the info just return the ref
  # else return the first entry
  if (wantarray) {
    return @$ref;
  } else {
    my $hashref = (defined $ref->[0] ? $ref->[0] : {});
    return $hashref;
  }
}

=item B<_add_msb_done_info>

Add the supplied information to the MSB done table and mark all previous
entries as old (status = false).

 $db->_add_msb_done_info( $msbinfo, $comment );

The first argument is an C<OMP::Info::MSB> object. The second argument is
an C<OMP::Info::Comment> object. 

All entries with status OMP__DONE_FETCH and the same
checksum are removed prior to uploading this information. This
is because the FETCH information is really just a placeholder
to guarantee that the information is available and is not
the main purpose of the table.

=cut

sub _add_msb_done_info {
  my $self = shift;
  my $msbinfo = shift;
  my $comment = shift;

  # Get the projectid from the MSB object
  # (we know it is defined)
  my $projectid = $msbinfo->projectid;
  my $checksum = $msbinfo->checksum;

  # In the past we have had some spurious null on here. Fix it
  # just in case (should probably mail myself in case I can spot
  # a pattern. At the very least log it
  if (substr($checksum,0,1) eq "\0") {
    $checksum =~ s/^.//;
    OMP::General->log_message("**** Detected leading NUL on checksum $checksum *****");
  }

  # Must force upcase of project ID for now
  $projectid = uc( $projectid );

  # First remove any placeholder observations
  $self->_db_delete_data( $MSBDONETABLE,
			  " checksum = '$checksum' AND " .
			  " projectid = '$projectid' AND " .
			  " status = " . OMP__DONE_FETCH
			);

  # Now insert the information into the table

  # First get the timestamp and format it
  my $t = $comment->date;
  my $date = $t->strftime("%b %e %Y %T");

  # insert rows into table
  # Note that "title" was added at a later date - hence its position
  # at the end of the insert

  # The user ID must be stored if the status is DONE_COMMENT, but always
  # store the user ID if it is available regardless of status.
  my $userid = $comment->author->userid
    unless (! defined $comment->author);

  throw OMP::Error::BadArgs("An OMP user ID is required for making a comment but none was supplied")
    if ($comment->status == OMP__DONE_COMMENT and ! $userid);

  # Truncate the target name. This is done to get around a bizarre
  # Sybase error if the string's too long.
  my $maxlen = 128;
  my $target = ( length($msbinfo->target) > $maxlen ?
                 substr($msbinfo->target, 0, $maxlen ) . "..." :
                 $msbinfo->target );

  $self->_db_insert_data( $MSBDONETABLE,
			  { COLUMN => 'checksum',
			    QUOTE => 1,
			    POSN => 0 },
			  $checksum, $comment->status,
			  $projectid, $date,
			  $target, $msbinfo->instrument,
			  $msbinfo->waveband,
			  {
			   TEXT => $comment->text,
			   COLUMN => 'comment',
			  }, $msbinfo->title,
			  $userid,
			  $comment->tid,
			);
}

=item B<_store_msb_done_comment>

Given an MSB info object and comment update the MSB done table to
contain this information.

If the MSB object contains sufficient information to fill the table
(eg target, waveband, instruments) the information from the info
object will be used. If it is not defined the information will be
retrieved from the done table. Finally, if it is still not defined we
will attempt to read it from the science program (assuming the science
program has not been modified recently).  An exception is triggered if
the information for the table is not available (this is the reason why
the checksum and project ID are required even though, in principal,
this information could be obtained from the MSB object).

  $db->_store_msb_done_comment( $msbinfo, $comment );

If the comment does not contain a status default is for the message to
be treated as a comment.  This allows you to specify that the comment
is associated with an MSB fetch or a "msb done" action. The
OMP__DONE_FETCH is treated as a special case. If that status is used a
row is added to the table only if no previous information exists for
that MSB.  (this prevents lots of entries associated with repeat
fetches but no action).

=cut

sub _store_msb_done_comment {
  my $self = shift;
  my ($msbinfo, $comment ) = @_;

  # default to a normal comment status
  my $status;
  if (defined $comment->status) {
    $status = $comment->status;
  } else {
    $status = OMP__DONE_COMMENT;
    $comment->status( $status );
  }

  # We do not need to write anything if this is a FETCH comment
  # and we already have a comment for this checksum in the database
  # First check status
  if ($status == OMP__DONE_FETCH) {

    # Get checksum and projectid
    my $checksum = $msbinfo->checksum;

    # A very inefficient check on the DB
    # If we get anything here return
    return if $self->historyMSB( $msbinfo->checksum );

  }

  # Need to look for the target, instrument and waveband information
  # If they are not there we need to query the database to configure
  # the object
  my $checksum = $msbinfo->checksum;
  my $project = $msbinfo->projectid;
  for (qw/ target instrument waveband title/) {
    unless ($msbinfo->$_()) {
      # Oops. Not here so we have to query
      $msbinfo = $self->historyMSB( $checksum );
      last;
    }
  }

  # One last ditch effort. Retrieve the actual science program
  # and look for the MSB
  unless ($msbinfo) {
    # Cant use the OMP::MSBDB->fetchMSB method since that
    # will call this class to register the fetch! Just do it
    # in two calls without the associated feedback messages
    # This will have a bit of an overhead.
    # problem with authentication - KLUGE for now
    # Catch any exceptions - we are only interested in whether
    # we can get some information.
    try {
      my $msbdb = new OMP::MSBDB( DB => $self->db, ProjectID => $project,);
      my $sp = $msbdb->fetchSciProgNoAuth(1);
      my $msb = $sp->fetchMSB( $checksum );
      $msbinfo = $msb->info() if $msb;
    };
  }

  # throw an exception if we dont have anything
  throw OMP::Error::MSBMissing("Unable to associate any information with the checksum '$checksum' in project $project") 
    unless $msbinfo;

  # Add this information to the table
  $self->_add_msb_done_info( $msbinfo, $comment );


}

=item B<_reorganize_msb_done>

Given the results from the query (returned as a row per comment)
convert this output to a hash containing one entry per MSB.

  $hashref = $db->_reorganize_msb_done( $query_output );

The resultant data structure is a hash (keyed by checksum)
each pointing to an C<OMP::Info::MSB> object containing the MSB information
and related comments.

Whenever a OMP__DONE_DONE comment is found, the "nrepeat" count of
the info object is incremented by 1 to indicate the number of times
this MSB has been observed.

=cut

sub _reorganize_msb_done {
  my $self = shift;
  my $rows = shift;

  # Now need to go through all the rows forming the
  # data structure (need to organize the data structure
  # before forming the (optional) xml output)
  my %msbs;
  for my $row (@$rows) {

    # Convert the date to a date object
    my $datekey = (exists $row->{longdate} ? "longdate" : "date");
    $row->{$datekey} =  OMP::General->parse_date( $row->{$datekey} );

    # nasty hack since for some reason we have leading null
    # characters on our MSB checksums
    $row->{checksum} =~ s/^.// if substr($row->{checksum},0,1) eq "\0";

    # Prepare comment details
    my %details = (text => $row->{comment},
		   date => $row->{$datekey},
		   status => $row->{status},
		   tid => $row->{msbtid},);

    # Specify comment author if there is one
    ($row->{userid}) and $details{author} = OMP::UserServer->getUser($row->{userid});

    # see if we've met this msb already
    if (exists $msbs{ $row->{checksum} } ) {

      # Add the new comment
      $msbs{ $row->{checksum} }->addComment( new OMP::Info::Comment(%details));

    } else {
      # populate a new entry

      $msbs{ $row->{checksum} } = new OMP::Info::MSB(
				   title => $row->{title},
				   checksum => $row->{checksum},
				   target => $row->{target},
				   waveband => $row->{waveband},
				   instrument => $row->{instrument},
				   projectid => $row->{projectid},
				   nrepeats => 0, # initial value
				   comments => [
					       new OMP::Info::Comment(%details)
					      ],
				  );
    }

    # If we have an OMP__DONE_DONE increment the repeat count
    # it might be more efficient to move this out of the loop
    # so that we only update nrepeats when we know the final answer
    if ($row->{status} == OMP__DONE_DONE) {
      my $rep = $msbs{ $row->{checksum} }->nrepeats;
      $msbs{ $row->{checksum} }->nrepeats( $rep + 1 );
    }


  }

  return \%msbs;

}

=back

=head1 SEE ALSO

This class inherits from C<OMP::BaseDB>.

For related classes see C<OMP::ProjDB> and C<OMP::FeedbackDB>.

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
Copyright (C) 2007 Science and Technology Facilities Council.
All Rights Reserved.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program (see SLA_CONDITIONS); if not, write to the 
Free Software Foundation, Inc., 59 Temple Place, Suite 330, 
Boston, MA  02111-1307  USA


=cut

1;
