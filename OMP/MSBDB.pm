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

# External dependencies
use File::Spec;

our $VERSION = (qw$Revision$)[1];

# Directory in which to store our XML files
our $XMLDIR = "/jac_sw/omp/dbxml";

# Name of the table containing the MSB data
our $MSBTABLE = "ompmsb";
our $PROJTABLE = "ompproj";
our $OBSTABLE = "ompobs";

# Default number of results to return from a query
our $DEFAULT_RESULT_COUNT = 10;

# Debug messages
our $DEBUG = 0;

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

Create a new instance of an C<OMP::MSBDB> object.

  $db = new OMP::MSBDB( ProjectID => $project,
			Password  => $passwd
			DB => $connection,
		      );

The arguments are required for Science Program access.
Some MSB-based methods are not instance methods.

If supplied, the database connection object must be of type
C<OMP::DBbackend>.  It is not accepted if that is not the case.
(but no error is raised - this is probably a bug).

=cut

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;

  # Read the arguments
  my %args;
  %args = @_ if @_;

  my $db = {
	    InTrans => 0,
	    Locked => 0,
	    Password => undef,
	    ProjectID => undef,
	    DB => undef,
	   };

  # Populate the hash
  for (qw/Password ProjectID/) {
    $db->{$_} = $args{$_} if exists $args{$_};
  }

  # and create the object
  my $object = bless $db, $class;

  # Check the DB handle
  $object->_dbhandle( $args{DB} ) if exists $args{DB};

  return $object;
}

=back

=head2 Accessor Methods

=over 4

=item B<projectid>

The project ID associated with this object.

  $pid = $db->projectid;
  $db->projectid( "M01BU53" );

=cut

sub projectid {
  my $self = shift;
  if (@_) { $self->{ProjectID} = shift; }
  return $self->{ProjectID};
}

=item B<password>

The password associated with this object.

 $passwd = $db->password;
 $db->password( $passwd );

=cut

sub password {
  my $self = shift;
  if (@_) { $self->{Password} = shift; }
  return $self->{Password};
}

=item B<_sciprog_filename>

Retrieve the filename to use for storing the Science Program XML.

The string argument is used to control its behaviour:

  "FULL" (or none) return the full path to the file

  "BACKUP" - return the full path to the backup file

  "FILE" - just return the filename without the path

 $file = $db->_sciprog_filename( "FULL" );

If an option is not recognized the full path is returned.

=cut

sub _sciprog_filename {
  my $self = shift;
  my $opt;
  $opt = shift if @_;
  $opt = "FULL" unless defined $opt;

  # Get simple filename
  my $pid = $self->projectid;
  return '' unless defined $pid;
  my $file = $pid . ".sp";

  if ($opt eq "FILE") {
    return $file;
  } elsif ($opt eq "BACKUP") {
    return File::Spec->catfile($XMLDIR, "bck_$file");
  } elsif ($opt eq "BACKUPi") {
    return File::Spec->catfile($XMLDIR, "bcki_$file");
  } else {
    return File::Spec->catfile($XMLDIR, $file);
  }
}

=item B<_locked>

Indicate whether the system is currently locked.

  $locked = $db->_locked();
  $db->_locked(1);

=cut

sub _locked {
  my $self = shift;
  if (@_) { $self->{Locked} = shift; }
  return $self->{Locked};
}

=item B<_intrans>

Indicate whether we are in a transaction or not.

  $intrans = $db->_intrans();
  $db->_intrans(1);

=cut

sub _intrans {
  my $self = shift;
  if (@_) { $self->{InTrans} = shift; }
  return $self->{InTrans};
}


=item B<_dbhandle>

Returns database handle associated with this object (the thing used by
C<DBI>).  Returns C<undef> if no connection object is present.

  $dbh = $db->_dbhandle();

Takes a database connection object (C<OMP::DBbackend> as argument in
order to set the state.

  $db->_dbhandle( new OMP::DBbackend );

If the argument is C<undef> the database handle is cleared.

If the method argument is not of the correct type an exception
is thrown.

=cut

sub _dbhandle {
  my $self = shift;
  if (@_) { 
    my $db = shift;
    if (UNIVERSAL::isa($db, "OMP::DBbackend")) {
      $self->{DB} = $db;
    } elsif (!defined $db) {
      $self->{DB} = undef;
    } else {
      throw OMP::Error::FatalError("Attempt to set database handle in OMP::MSBDB using incorrect class");
    }
  }
  my $db = $self->{DB};
  if (defined $db) {
    return $db->handle;
  } else {
    return undef;
  }
}

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
the external checking (e.g. marking an MSB as being observed).

  $status = $db->storeSciProg( SciProg => $sp,
                               FreezeTimeStamp => 1);

Returns true on success and C<undef> on error (this may be
modified to raise an exception).

=cut

sub storeSciProg {
  my $self = shift;

  # Get the arguments
  my %args = @_;

  # Check them
  return undef unless exists $args{SciProg};
  return undef unless UNIVERSAL::isa($args{SciProg}, "OMP::SciProg");

  # Before we do anything else we connect to the database
  # begin a transaction and lock out the tables.
  # This has the side effect of locking out the tables until
  # we have finished with them (else it will block waiting for
  # access). This allows us to use the DB lock to control when we
  # can write a science program to disk)
  $self->_db_begin_trans;
  $self->_dblock;

  # Write the Science Program to disk
  $self->_write_sci_prog( $args{SciProg}, $args{FreezeTimeStamp} ) 
    or return undef;

  # We need to remove the existing rows associated with this
  # project id
  $self->_clear_old_rows;

  # And store the science program MSB summary into the database
  for my $msb ($args{SciProg}->msb) {
    my %summary = $msb->summary;

    # Add the contents to the database
    $self->_insert_row( %summary );

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

=cut

sub fetchSciProg {
  my $self = shift;

  # Test to see if the file exists first so that we can
  # raise a special UnknownProject exception.
  # There is no race condition with -e. If the file doesnt exist
  # the caller can try again later or store it. If the file does exist
  # then it will not disappear again since there is no method to delete
  # a science program.
  my $pid = $self->projectid;
  $pid = '' unless defined $pid;
  throw OMP::Error::UnknownProject("Project \"$pid\" unknown")
    unless -e $self->_sciprog_filename();

  # Instantiate a new Science Program object
  # The file name is derived automatically
  my $sp = new OMP::SciProg( FILE => $self->_sciprog_filename())
    or throw OMP::Error::SpRetrieveFail("Unable to fetch science program\n");

  return $sp;
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

  # The important result is the checksum
  my $checksum;

  # If we are querying the database by MSB ID...
  if (exists $args{msbid} && defined $args{msbid}) {

    # Call method to do search on database. This assumes that we
    # can map projectid, checksum and id to valid column names
    # Returns a hash with the row entries
    my %details = $self->_fetch_row(%args);

    # We could not find anything
    throw OMP::Error::MSBMissing("Could not locate requested MSB in database")
      unless %details;

    # Get the checksum
    $checksum = $details{checksum};

    # And the project ID
    $self->projectid( $details{projectid} );

  } elsif (exists $args{checksum}) {
    $checksum = $args{checksum};
  } else {
    throw OMP::Error::BadArgs("No checksum or MSBid provided. Unable to retrieve MSB.");
  }

  # Retrieve the relevant science program
  my $sp = $self->fetchSciProg();

  # Get the MSB
  my $msb = $sp->fetchMSB( $checksum );

  return $msb;
}

=item B<queryMSB>

Query the database for the MSBs that match the supplied query.

  @results = $db->queryMSB( $query );

The query is represented by an C<OMP::MSBQuery> object. 

The results are actually summaries of the table entries rather than
direct summaries of MSBs. It is assumed that the table contains
all the necessary information from the MSB itself so that there is
no need to open each science program to obtain more information.

=cut

sub queryMSB {
  my $self = shift;
  my $query = shift;

  # Run the query and obtain an array of hashes in order up to
  # the maximum number
  my @results = $self->_run_query($query);

  # Now go through the hash and translate it to an XML string
  # This assumes that the database table contains everything
  # we need for a summary (ie we don't want to have to open
  # up the science programs to get extra information)
  # We also will need to fix the order at some point since the
  # QT will probably be relying on it for display
  # Use the OMP::MSB code to generate an MSBSummary
  # (since that is the code used to generate the table entry)

  my @xml = map { scalar(OMP::MSB->summary($_))  } @results;

  return @xml;
}

=item B<doneMSB>

Mark the specified MSB as having been observed.

  $db->doneMSB( $checksum );

The MSB is located using the Project identifier (stored in the object)
and the checksum.  If an MSB can not be located it is likely that the
science program has been reorganized.

This method locks the database since we are modifying the file on disk
and the database tables.

=cut

sub doneMSB {
  my $self = shift;
  my $checksum = shift;

  # Connect to the DB (and lock it out)
  $self->_db_begin_trans;
  $self->_dblock;

  # We could use the MSBDB::fetchMSB method if we didn't need the science
  # program object. Unfortauntely, since we intend to modify the
  # science program we need to get access to the object here
  # Retrieve the relevant science program
  my $sp = $self->fetchSciProg();

  # Get the MSB
  my $msb = $sp->fetchMSB( $checksum );

  # Give up if we dont have a match
  return unless defined $msb;

  $msb->hasBeenObserved();

  # Now need to store the MSB back to disk again
  # since this has the advantage of updating the database table
  # and making sure reorganized Science Program is stored.
  # This will require a back door password and the ability to
  # indicate that the timestamp is not to be modified
  $self->storeSciProg( SciProg => $sp, FreezeTimeStamp => 1 );

  # Disconnect
  $self->_dbunlock;
  $self->_db_commit_trans;

}


=back

=head2 Internal Methods

=over 4

=item B<_write_sci_prog>

Write the science program to disk.

  $db->_write_sci_prog( $sp );

If the science program already exists on disk it is moved to
a backup file before saving the new version. Additionally,
the timestamp on the old file is compared to that stored in the
science program (the C<timestamp> attribute of the SpProg) and if they
differ the new file is not written (the new science program should
have the timestamp of the old file).

A timestamp is added to the science program automatically just
before it is written to disk.

There is possibly an overhead associated with this (since on comparing
with the old timestamp a file must be opened) but this is better
since it allows us to modify the "remaining" attributes without
worrying about a file system timestamp.

If the optional second argument is present and true, timestamp checking
is disabled and the timestamp is not modified. This is to allow internal
reorganizations to use this routine without affecting external checking.
If this option is selected the backup file is written with a different
name to prevent a clash with an externally modified program.

=cut

sub _write_sci_prog {
  my $self = shift;
  throw OMP::Error::BadArgs('Usage: $db->_write_sci_prog( $sp )') unless @_;
  my $sp = shift;

  my $freeze = shift;

  # Get the filename
  my $fullpath = $self->_sciprog_filename();

  # If we already have a file of that name we have to
  # check the timestamp and rename it.
  if (-e $fullpath) {

    # Disable timestamp checks if freeze is set
    unless ($freeze) {
      # Get the timestamps
      my $tstamp = $self->_get_old_sciprog_timestamp;
      my $spstamp = $sp->timestamp;
      if (defined $spstamp) {
	throw OMP::Error::SpStoreFail("Science Program has changed on disk\n")
	  unless $tstamp == $spstamp;
      }
    }

    # Move the old version of the file to back up
    my $key = ($freeze ? "BACKUPi" : "BACKUP");
    my $backup = $self->_sciprog_filename("BACKUP");
    rename $fullpath, $backup 
      or throw OMP::Error::SpStoreFail("error renaming $fullpath to $backup: $!\n");
  }

  # Put a new timestamp into the science program prior to writing
  $sp->timestamp( time() ) unless $freeze;

  # open a new file
  open( my $fh, ">$fullpath") 
    or throw OMP::Error::SpStoreFail("Error writing SciProg to $fullpath: $!\n");

  # write the Science Program to disk
  print $fh "$sp";

  close($fh) or throw OMP::Error::SpStoreFail("Error closing new sci prog file: $!\n");
}


=item B<_get_old_sciprog_timestamp>

This retrieves the timestamp of a science program as stored on
disk in the database.

Currently, the timestamp is determined by opening the old science
program and reading the timestamp from it. If this is too slow
we may simply write the timestamp to a separate file.

=cut

sub _get_old_sciprog_timestamp {
  my $self = shift;

  my $fullpath = $self->_sciprog_filename();
  my $sp = new OMP::SciProg( FILE => $fullpath );
  my $tstamp = $sp->timestamp;
  return $tstamp;
}

=item B<_get_next_index>

Return the primary index to use for each row in the database. This
number is determined to be unique for all entries ever made.

The current index is obtained by reading it from a text file
and then incrementing it. This is more robust than simply making
sure that it is the next highest in the database (since it would
then not guarantee that we would choose a unique value).

=cut

sub _get_next_index {
  my $self = shift;

  my $indexfile = File::Spec->catfile($XMLDIR,"index.dat");
  my $highest;
  if (-e $indexfile) {
    open(my $fh, "<$indexfile") 
      or throw OMP::Error::FatalError("Could not read indexfile $indexfile: $!\n");
    $highest = <$fh>;
  }

  # increment to get the next one
  $highest++;

  # Now update the file
  open(my $fh, ">$indexfile") 
    or throw OMP::Error::FatalError("Could not open indexfile $indexfile: $!\n");
  print $fh "$highest";

  return $highest;
}


=back

=head2 DB Connectivity

These methods connect directly to the database. If the database is changed
(for example to move to DB_File or even Storable) then these are the
only routines that need to be modified.

=over 4

=item B<_db_begin_trans>

Begin a database transaction. This is defined as something that has
to happen in one go or trigger a rollback to reverse it.

If a transaction is already in progress this method returns
immediately.

=cut

sub _db_begin_trans {
  my $self = shift;
  return if $self->_intrans;

  my $dbh = $self->_dbhandle;
  $dbh->do("BEGIN TRANSACTION")
    or throw OMP::Error::DBError("Error beginning transaction: $DBI::errstr");
  $self->_intrans(1);
}

=item B<_db_commit_trans>

Commit the transaction. This informs the database that everthing
is okay and that the actions should be finalised.

=cut

sub _db_commit_trans {
  my $self = shift;
  my $dbh = $self->_dbhandle;

  if ($self->_intrans) {
    $self->_intrans(0);
    $dbh->do("COMMIT TRANSACTION")
      or throw OMP::Error::DBError("Error committing transaction: $DBI::errstr");
  }
}

=item B<_db_rollback_trans>

Rollback (ie reverse) the transaction. This should be called if
we detect an error during our transaction.

When called it should probably correct any work completed on the
XML data file.

=cut

sub _db_rollback_trans {
  my $self = shift;

  my $dbh = $self->_dbhandle;
  if ($self->_intrans) {
    $self->_intrans(0);
    $dbh->do("ROLLBACK TRANSACTION")
      or throw OMP::Error::DBError("Error rolling back transaction (ironically): $DBI::errstr");
  }
}


=item B<_dblock>

Lock the MSB database tables (ompobs and ompmsb but not the project table)
so that they can not be accessed by other processes.

=cut

sub _dblock {
  my $self = shift;
  # Wait for infinite amount of time for lock
  # Needs Sybase 12
#  $dbh->do("LOCK TABLE $MSBTABLE IN EXCLUSIVE MODE WAIT")
#    or throw OMP::Error::DBError("Error locking database: $DBI::errstr");
  $self->_locked(1);
  return;
}

=item B<_dbunlock>

Unlock the system. This will allow access to the database tables and
file system.

For a transaction based database this is a nullop since the lock
is automatically released when the transaction is committed.

=cut

sub _dbunlock {
  my $self = shift;
  if ($self->_locked()) {
    $self->_locked(0);
  }
}

=item B<_insert_row>

Insert a row into the database using the information provided in the hash.

  $db->_insert_row( %data );

The contents of the hash are usually defined by the C<OMP::MSB> class
and its C<summary()> method.

This method inserts MSB data into the MSB table and the observation
summaries into the observation table.

=cut

sub _insert_row {
  my $self = shift;
  my %data = @_;

  # Get the next index (we do this ourselves)
  my $index = $self->_get_next_index();

  # Get the DB handle
  my $dbh = $self->_dbhandle;

  # Store the data
  my $proj = $self->projectid;
  print "Inserting row as index $index\n" if $DEBUG;
  $dbh->do("INSERT INTO $MSBTABLE VALUES (?,?,?,?,?,?,?,?,?,?,?,?)", undef,
	   $index, $proj, $data{remaining}, $data{checksum}, $data{obscount},
	   $data{tauband}, $data{seeing}, $data{priority}, $data{moon},
	   $data{timeest}, $self->_sciprog_filename, $data{title}) 
    or throw OMP::Error::DBError("Error inserting new rows: ".$DBI::errstr);

  # Now the observations
  my $count;
  for my $obs (@{ $data{obs} }) {

    $count++;

    # Get the obs id (based on the msb id)
    my $obsid = sprintf( "%d%03d", $index, $count);

    my @coords = $obs->{coords}->array;

    # Wavelength must be a number (just check for presence of any number)
    $obs->{wavelength} = -1 unless $obs->{wavelength} =~ /\d/;

    print "Inserting row: ",Dumper($obs) if $DEBUG;

    $dbh->do("INSERT INTO $OBSTABLE VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)"
	     , undef,
	     $obsid, $index, $proj, $obs->{instrument}, $obs->{wavelength},
	     $obs->{coordstype}, $obs->{target},
	     @coords[1..10]
	    )
      or throw OMP::Error::DBError("Error inserting new rows: ".$DBI::errstr);

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
  my $dbh = $self->_dbhandle;
  my $proj = $self->projectid;

  # Remove the old data
  print "Clearing old msb rows for project ID $proj\n" if $DEBUG;
 $dbh->do("DELETE FROM $MSBTABLE WHERE projectid = '$proj'")
    or throw OMP::Error::DBError("Error removing old msb rows: ".$DBI::errstr);

  print "Clearing old obs rows for project ID $proj\n" if $DEBUG;
  $dbh->do("DELETE FROM $OBSTABLE WHERE projectid = '$proj'")
    or throw OMP::Error::DBError("Error removing old obs rows: ".$DBI::errstr);

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
  my @substrings = map { " $_ = '$query{$_}' " } keys %query;

  # and construct the SQL command
  my $statement = "SELECT * FROM $MSBTABLE WHERE" .
    join("AND", @substrings);

  # prepare and execute
  my $dbh = $self->_dbhandle;
  my $ref = $dbh->selectall_hashref( $statement );

  throw OMP::Error::DBError("Error fetching specified row:".$DBI::errstr)
    unless defined $ref;

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
  my $sql = $query->sql( $MSBTABLE );

  # prepare and execute
  my $dbh = $self->_dbhandle;
  my $ref = $dbh->selectall_hashref( $sql );
  throw OMP::Error::DBError("Error executing query:".$DBI::errstr)
    unless defined $ref;

  # Return the results (as a slice if necessary)
  my $max = $query->maxCount;

  if (defined $max) {
    $max--; # convert to index
    $max = ( $max < $#$ref ? $max : $#$ref);
  } else {
    $max = $#$ref;
  }

  return @$ref[0..$max];
}


=item B<DESTROY>

We rollback any transactions that have failed (this only works
if the exceptions thrown by this module are caught in such a way
that the object will go out of scope).

=cut

sub DESTROY {
  my $self = shift;
  $self->_db_rollback_trans;
}

=back

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
