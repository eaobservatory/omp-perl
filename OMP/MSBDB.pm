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
use OMP::ProjDB;

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
MSB-based methods do not need to know this information.

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

Additionally, the C<NoNewTrans> key can be used to indicate that
we do not wish to initiate a new database transaction (usually
because one has been started higher up). We do this since the
begin transaction method might well decide to rollback a previous
transaction if it is asked to start a new one.

The scheduling fields (eg tauband and seeing) must be populated.

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

  # If we are already running a transaction and do not want to
  # start a new one (or just dont want to start one) then we need
  # to find out now
  my $nonewtrans = 0;
  if (exists $args{NoNewTrans} && $args{NoNewTrans}) {
    # Do it hear to prevent problems with exists and unless
    $nonewtrans = 1;
  }

  # Before we do anything else we connect to the database
  # begin a transaction and lock out the tables.
  # This has the side effect of locking out the tables until
  # we have finished with them (else it will block waiting for
  # access). This allows us to use the DB lock to control when we
  # can write a science program to disk)
  unless ($nonewtrans) {
    $self->_db_begin_trans;
    $self->_dblock;
  }

  # Write the Science Program to disk
  $self->_store_sci_prog( $args{SciProg}, $args{FreezeTimeStamp} ) 
    or throw OMP::Error::SpStoreFail("Error storing science program into database\n");

  # Get the summaries for each msb
  my @rows = map {
    my $summary = { $_->summary };

    throw OMP::Error::SpBadStructure("No scheduling information in science program. Did you forget to put in a Site Quality component?\n")
      unless (exists $summary->{tauband} or exists $summary->{seeing});

    # Return the reference to the array
    $summary;

  } $args{SciProg}->msb;

  # Insert the summaries into rows of the database
  $self->_insert_rows( @rows );

  # Now disconnect from the database and free the lock
  unless ($nonewtrans) {
    $self->_dbunlock;
    $self->_db_commit_trans;
  }

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
  # There is no race condition with -e. If the XML isn't there
  # the caller can try again later or store it. If the XML does exist
  # then it will not disappear again since the database transaction is
  # locked when a science program is removed.
  my $pid = $self->projectid;
  $pid = '' unless defined $pid;
  throw OMP::Error::UnknownProject("Project \"$pid\" unknown")
    unless $self->_get_old_sciprog_timestamp;

  # Instantiate a new Science Program object
  # The file name is derived automatically
  my $sp = new OMP::SciProg( XML => $self->_db_fetch_sciprog())
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
and the database tables. We do not want to retrieve a science program,
modify it and store it again if someone has modified the science program
between us retrieving and storing it.

=cut

sub doneMSB {
  my $self = shift;
  my $checksum = shift;

  # Connect to the DB (and lock it out)
  $self->_db_begin_trans;
  $self->_dblock;

  # We could use the MSBDB::fetchMSB method if we didn't need the science
  # program object. Unfortunately, since we intend to modify the
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
  $self->storeSciProg( SciProg => $sp, FreezeTimeStamp => 1,
		     NoNewTrans => 1);

  # Disconnect
  $self->_dbunlock;
  $self->_db_commit_trans;

}


=back

=head2 Internal Methods

=over 4

=item B<_store_sci_prog>

Store the science program to the "database"

  $db->_store_sci_prog( $sp );

The XML is stored in the database. Transaction management deals with the
case where the upload fails part way through.

If a entry already exists in the database the timestamp is retrieved
and compared with the current version of the science program.
(using the C<timestamp> attribute of the SpProg). If they
differ the new file is not stored (the new science program should
have the timestamp of the old science program).

A timestamp is added to the science program automatically just
before it is written to the database. The overhead in fetching the timestamp
from the database is minimal compared with having to read the old science
program and instantiate a science program object in order to read the
timestamp.

If the optional second argument is present and true, timestamp
checking is disabled and the timestamp is not modified. This is to
allow internal reorganizations to use this routine without affecting
external checking (for example, when marking the MSB as done).

=cut

sub _store_sci_prog {
  my $self = shift;
  throw OMP::Error::BadArgs('Usage: $db->_write_sci_prog( $sp )') unless @_;
  my $sp = shift;

  my $freeze = shift;

  # Check to see if sci prog exists already (if it does it returns
  # the timestamp else undef)
  my $tstamp = $self->_get_old_sciprog_timestamp;

  # If we have a timestamp we need to compare it with what we
  # have now
  if (defined $tstamp) {

    # Disable timestamp checks if freeze is set
    unless ($freeze) {
      # Get the timestamp from the current file (we have the old one
      # already)
      my $spstamp = $sp->timestamp;
      if (defined $spstamp) {
	throw OMP::Error::SpStoreFail("Science Program has changed on disk\n")
	  unless $tstamp == $spstamp;
      } else {
	throw OMP::Error::SpStoreFail("A science program is already in the database with a timestamp but this science program does not include a timestamp at all.\n")

      }
    }

    # Clear the old science program
    $self->_remove_old_sciprog;

  }

  # Put a new timestamp into the science program prior to writing
  $sp->timestamp( time() ) unless $freeze;

  # and store it
  $self->_db_store_sciprog( $sp );

}


=item B<_remove_old_sciprog>

Remove an existing science program XML from the database.

  $db->_remove_old_sciprog;

Raises SpStoreFail exception on failure.

=cut

sub _remove_old_sciprog {
  my $self = shift;
  my $proj = $self->projectid;
  my $dbh = $self->_dbhandle;
  throw OMP::Error::DBError("Database handle not valid") unless defined $dbh;

  $dbh->do("DELETE FROM $SCITABLE WHERE projectid = '$proj'")
    or throw OMP::Error::SpStoreFail("Error removing old science program: ".$dbh->errstr);

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
  my $dbh = $self->_dbhandle;
  throw OMP::Error::DBError("Database handle not valid") unless defined $dbh;

  my $ref = $dbh->selectall_arrayref("SELECT timestamp FROM $SCITABLE WHERE projectid = '$proj'", { Columns => {}});

  # Assume that no $ref means no entry in db
  return undef unless defined $ref;

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
  my $dbh = $self->_dbhandle;
  throw OMP::Error::DBError("Database handle not valid") unless defined $dbh;
  print "Entering _db_store_sciprog\n" if $DEBUG;
  print "Timestamp: ", $sp->timestamp,"\n" if $DEBUG;
  print "Project:   ", $proj,"\n" if $DEBUG;

  # Insert the timestamp and project ID
  $dbh->do("INSERT INTO $SCITABLE VALUES (?,?,'')", undef,
	  $proj, $sp->timestamp) or
	    throw OMP::Error::SpStoreFail("Error inserting timestamp and project ID into science program database: ". $dbh->errstr);


  # Now insert the text field using writetext
  # Do it this way because a TEXT field will only (seemingly) take
  # a science program of size 65536 bytes using an INSERT before it starts
  # giving really strange syntax error warnings.
  $dbh->do("declare \@val varbinary(16) 
select \@val = textptr(sciprog) from ompsciprog where projectid = \"$proj\" 
writetext ompsciprog.sciprog \@val '$sp'")
    or throw OMP::Error::SpStoreFail("Error inserting science program XML into database: ". $dbh->errstr);


  # Now fetch it back to check for truncation issues
  # This adds quite a bit of overhead. XXXX remove before release
  my $xml = $self->_db_fetch_sciprog();
  if (length($xml) ne length("$sp")) {
    my $orilen = length("$sp");
    my $newlen = length($xml);
    throw OMP::Error::SpStoreFail("Science program was truncated during store (now $newlen rather than $orilen)\n");
  }

  return 1;
}

=item B<_db_fetch_sciprog>

Retrieve the XML from the database and return it.

  $xml = $db->_db_fetch_sciprog();

Note this does not return a science program object (although I cant
think of a good reason why).

=cut

sub _db_fetch_sciprog {
  my $self = shift;
  my $sp = shift;
  my $proj = $self->projectid;
  my $dbh = $self->_dbhandle;
  throw OMP::Error::DBError("Database handle not valid") unless defined $dbh;

  # need to set the textsize to a value large enough to contain
  # the science program itself. I would like to do this by setting
  # it to the length of the current science program but frossie
  # insists that I just pick a large number and be done with it
  # (until the JCMT board is over)
  my $ref = $dbh->selectall_arrayref("SET TEXTSIZE 330000000
(SELECT sciprog FROM $SCITABLE WHERE projectid = '$proj')", { Columns => {}});

  throw OMP::Error::SpRetrieveFail("Error retrieving science program XML from database: ". $dbh->errstr) unless defined $ref;

  return $ref->[0]->{sciprog};
}

=item B<_get_next_msb_index>

Return the primary index to use for each row in the MSB database. This
number is determined to be unique for all entries ever made.

The current index is obtained by reading the highest value from the 
database. For efficiency we only want to do this once per transaction.

In order to guarantee uniqueness it should be obtained before the old
rows are removed. This does not happen currently.

=cut

sub _get_next_index {
  my $self = shift;

  # Return the current index by doing a sort in descending order
  my $dbh = $self->_dbhandle;
  throw OMP::Error::DBError("Database handle not valid") unless defined $dbh;

  my $sth = $dbh->prepare("SELECT msbid FROM $MSBTABLE ORDER BY msbid DESC")
    or throw OMP::Error::DBError("Can not prepare statement for index retrieval: ". $dbh->errstr);

  $sth->execute() or
    throw OMP::Error::DBError("Can not execute SELECT: ". $sth->errstr());

  my $ref = $sth->fetch;

  $sth->finish;

  # Get the next highest
  my $highest = $ref->[0]; 
  $highest++;

  return $highest;
}


=back

=head2 DB Connectivity

These methods connect directly to the database. If the database is changed
(for example to move to DB_File or even Storable) then these are the
only routines that need to be modified.

=over 4

=item B<_insert_rows>

Insert all the rows into the database using the information
provided in the array of hashes:

  $db->_insert_rows( @summaries );

where @summaries contains elements of hash references for
each MSB summary.

=cut

sub _insert_rows {

  my $self = shift;
  my @summaries = @_;

  # We need to remove the existing rows associated with this
  # project id
  $self->_clear_old_rows;

  # Get the next index to use for the MSB table
  my $index = $self->_get_next_index();

  # Get the DB handle
  my $dbh = $self->_dbhandle or
    throw OMP::Error::DBError("Database handle not valid");

  # Now loop over each summary inserting the information 
  for my $summary (@summaries) {

    # Add the contents to the database
    $self->_insert_row( %{$summary},
			_dbh  => $dbh,
			_index=> $index,
		      );

    # increment the index for next pass
    $index++;

  }

}


=item B<_insert_row>

Insert a row into the database using the information provided in the hash.

  $db->_insert_row( %data );

The contents of the hash are usually defined by the C<OMP::MSB> class
and its C<summary()> method.

This method inserts MSB data into the MSB table and the observation
summaries into the observation table.

Usually called from C<_insert_rows>. Expects the hash to include
special keys:

  _index  - index to use for next MSB row
  _dbh    - the database handle
  _msbq   - cached SQL handle for MSB insert

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
  my %data = @_;
  print "Entering _insert_row\n" if $DEBUG;

  # Get the next index
  my $index = $data{_index};

  # Get the database handle from the hash
  my $dbh = $data{_dbh} or
    throw OMP::Error::DBError("Database handle not valid in _insert_row");

  # Throw an exception if we are missing tauband or seeing
  throw OMP::Error::SpBadStructure("There seems to be no site quality information. Unable to schedule MSB.\n")
    unless (defined $data{seeing} and defined $data{tauband});

  # Throw an exception if we are missing observations
  throw OMP::Error::MSBMissingObserve("1 or more of the MSBs is missing an Observe\n") if $data{obscount} == 0;

  # Store the data
  my $proj = $self->projectid;
  print "Inserting row as index $index\n" if $DEBUG;

  # Simply use "do" since there is only a single insert if we
  # can not have multiple statement handles
  $dbh->do("INSERT INTO $MSBTABLE VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)",undef,
	   $index, $proj, $data{remaining}, $data{checksum}, $data{obscount},
	   $data{tauband}, $data{seeing}, $data{priority}, 
	   $data{telescope}, $data{moon},
	   $data{timeest}, $data{title}, 
	   $data{earliest}, $data{latest}) 
    or throw OMP::Error::DBError("Error inserting new MSB rows: $DBI::errstr");

  # Now the observations
  # Get the observation query handle
  my $obsst = $dbh->prepare("INSERT INTO $OBSTABLE VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)")
    or throw OMP::Error::DBError("Error preparing MSBOBS insert SQL: $DBI::errstr\n");

  my $count;
  for my $obs (@{ $data{obs} }) {

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
    $obs->{wavelength} = -1 unless (defined $obs->{wavelength} and 
                                     $obs->{wavelength} =~ /\d/);

    print "Inserting row: ",Dumper($obs) if $DEBUG;

    $obsst->execute(
	     $obsid, $index, $proj, $obs->{instrument}, 
	     $obs->{type}, $obs->{pol}, $obs->{wavelength},
	     $obs->{coordstype}, $obs->{target},
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
  my $dbh = $self->_dbhandle;
  throw OMP::Error::DBError("Database handle not valid") unless defined $dbh;
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
  my @substrings = map { " $_ = ? " } sort keys %query;

  # and construct the SQL command using bind variables so that 
  # we dont have to worry about quoting
  my $statement = "SELECT * FROM $MSBTABLE WHERE" .
    join("AND", @substrings);
  print "STATEMENT: $statement\n" if $DEBUG;

  # prepare and execute
  my $dbh = $self->_dbhandle;
  throw OMP::Error::DBError("Database handle not valid") unless defined $dbh;

  my $ref = $dbh->selectall_arrayref( $statement, { Columns=>{} },
				      map { $query{$_} } sort keys %query
				    );

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
  my $sql = $query->sql( $MSBTABLE, $OBSTABLE, $PROJTABLE );

  # prepare and execute
  my $dbh = $self->_dbhandle;
  throw OMP::Error::DBError("Database handle not valid") unless defined $dbh;

  my $ref = $dbh->selectall_arrayref( $sql, { Columns=>{} } );
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
  @$ref = @$ref[0..$max];

  # Now for each MSB we need to retrieve all of the Observation information
  # and store it in the results hash
  # Convention dictates that this information ...???
  # For speed, do the query in one go and then sort out the result
  my @clauses = map { " msbid = ".$_->{msbid}. ' ' } @$ref;
  $sql = "SELECT * FROM $OBSTABLE WHERE ". join(" OR ", @clauses);
  my $obsref = $dbh->selectall_arrayref( $sql, { Columns=>{} } );
  throw OMP::Error::DBError("Error retrieving matching observations:".
			    $dbh->errstr)
    unless defined $obsref;

  # Now loop over the results and store the observations in the correct
  # place. First need to create the obs arrays by msbid (using msbid as
  # key)
  my %msbs;
  for my $row (@$obsref) {
    my $msb = $row->{msbid};
    if (exists $msbs{$msb}) {
      push(@{$msbs{$msb}}, $row);
    } else {
      $msbs{$msb} = [ $row ];
    }
    delete $row->{msbid}; # not needed

    # Create the coordinate and waveband objects
    $row->{waveband} = new Astro::WaveBand(Instrument => $row->{instrument},
					   Wavelength => $row->{wavelength});

    # Let Astro::Coords work out what we mean by all this :-)
    $row->{coords} = new Astro::Coords(ra => $row->{ra2000},
				       dec => $row->{dec2000},
				       type => 'J2000',
				       planet => $row->{target},
				       elements => {
						    EPOCH => $row->{el1},
						    ORBINC => $row->{el2},
						    ANODE => $row->{el3},
						    PERIH => $row->{el4},
						    AORQ => $row->{el5},
						    E => $row->{el6},
						    AORL => $row->{el7},
						    DM => $row->{el8},
						   },
				      );

  }

  # And now attach it to the relevant MSB
  # If there are no observations this will store undef (will happen
  # if a dummy science program is uploaded)
  for my $row (@$ref) {
    my $msb = $row->{msbid};
    $row->{obs} = $msbs{$msb};
  }

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


  return @$ref;
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
