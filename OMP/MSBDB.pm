package OMP::MSBDB;

=head1 NAME

OMP::MSBDB - A database of MSBs

=head1 SYNOPSIS

  $sp = new OMP::SciProg( XML => $xml );
  $db = new OMP::MSBDB( Password => $passwd, 
                        ProjectID => $sp->projectID );

  $status = $db->store( SciProg => $sp );

  $msb = $db->fetchMSB( DBID => $id,
                        CheckSum => $checksum );
  $sp  = $db->fetchSciProg();

  @match = $db->query( Query => $xml );


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

# External dependencies
use File::Spec;
use DBI;

our $VERSION = (qw$Revision$)[1];

# Directory in which o store our XML files
our $XMLDIR = "/jac_sw/omp/dbxml";

# Name of the table containing the MSB data
our $TABLE = "ompmsb";

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

Create a new instance of an C<OMP::MSBDB> object.

  $db = new OMP::MSBDB( ProjectID => $project,
			Password  => $passwd );

The arguments are required for Science Program access.
Some MSB-based methods are not instance methods.

=cut

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;

  # Read the arguments
  my %args;
  %args = @_ if @_;

  my $db = {
	    Password => undef,
	    ProjectID => undef,
	    DBH => undef,
	    Transaction => undef,
	   };

  # Populate the hash
  for (qw/Password ProjectID/) {
    $db->{$_} = $args{$_} if exists $args{$_};
  }

  # and create the object
  bless $db, $class;

}

=back

=head2 Accessor Methods

=over 4

=item B<projectid>

The project ID associated with this object.

  $pid = $db->projectid;

=cut

sub projectid {
  my $self = shift;
  if (@_) { $self->{ProjectID} = shift; }
  return $self->{ProjectID};
}

=item B<password>

The password associated with this object.

 $passwd = $db->password;

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
  my $file = $self->projectid . ".sp";

  if ($opt eq "FILE") {
    return $file;
  } elsif ($opt eq "BACKUP") {
    return File::Spec->catfile($XMLDIR, "bck_$file");
  } else {
    return File::Spec->catfile($XMLDIR, $file);
  }
}

=item B<_dbhandle>

Database handle associated with this object.
The C<_dbconnect> method is invoked automatically if no handle
is present (this may not be a good thing).

=cut

sub _dbhandle {
  my $self = shift;
  if (@_) { 
    $self->{DBH} = shift; 
  } else {
    unless (defined $self->{DBH}) {
      $self->_dbconnect()
    }
  }
  return $self->{DBH};
}

=item B<_transaction>

Contains the current database transaction. We use this to guarantee
that all SQL statements are executed at the same time (when the
database connection is closed) rather than discovering an error
halfway through the transaction and not being able to revert.

This contains the pending SQL statements. Each time this method
is called with an argument the values are appended to the string.
When the argument is C<undef> the string is emptied.

=cut

sub _transaction {
  my $self = shift;
  if (@_) {
    my $arg = shift;
    if (defined $arg) {
      $self->{Transaction} .= $arg;
    } else {
      $self->{Transaction} = undef;
    }
  }
  return $self->{Transaction};
}

=back

=head2 General Methods

=over 4

=item B<storeSciProg>

Store a science program object into the database.

  $status = OMP::MSBDB->store( SciProg => $sp );

Requires a password and project identifier.

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
  # This has the side effect of locking out the tables until
  # we have finished with them (else it will block waiting for
  # access). This allows us to use the DB lock to control when we
  # can write a science program to disk)
  $self->_dbconnect;

  # Write the Science Program to disk
  $self->_write_sci_prog( $args{SciProg} ) or return undef;

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
  $self->_dbdisconnect;

  return 1;
}

=item B<fetchSciProg>

Retrieve a science program from the database.

  $sp = $db->fetchSciProg()

It is returned as an C<OMP::SciProg> object.
It is assumed that the DB object has already been instantiated
with the relevant project ID and password.

=cut

sub fetchSciProg {
  my $self = shift;

  # Connect to the database and lock the table
  # This is required solely for locking purposes since the
  # Science Program is not retrieved from the database itself
  $self->_dbconnect;

  # Instantiate a new Science Program object
  # The file name is derived automatically
  my $sp = new OMP::SciProg( FILE => $self->_sciprog_filename())
    or return undef;

  # Now disconnect from the database and free the lock
  $self->_dbdisconnect;

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

The OMP will probably always use the index and checksum approach. Since,
assuming an MSB has a unique index, this allows for us to determine
when a science program has been resubmitted since we obtained the
information. This is important since we want to make sure that our
query is still valid.

The checksum approach allows us to always retrieve the same MSB
regardless of whether the science program has been resubmitted since
we last looked.

Just use the index:

   $msb = $db->fetchMSB( id => $index );

Use the index and checksum (both are used for the DB query):

   $msb = $db->fetchMSB( id => $index, checksum => $checksum );

Use the checksum and the project id (available from the object):

   $msb = $db->fetchMSB( checksum => $checksum );

It is an error for multiple MSBs to match the supplied criteria.

=cut

sub fetchMSB {
  my $self = shift;
  my %args = @_;

  # The important result is the checksum
  my $checksum;

  # If we are querying the database by MSB ID...
  if (exists $args{id}) {

    # Connect to the DB
    $self->_dbconnect;

    # Call method to do search on database. This assumes that we
    # can map projectid, checksum and id to valid column names
    # Returns a hash with the row entries
    my %details = $self->_fetch_row(%args);

    $self->_dbdisconnect;

    # Return undef if no match
    return undef unless %details;

    # Get the checksum
    $checksum = $details{checksum};

    # And the project ID
    $self->projectid( $details{projectid} );

  } elsif (exists $args{checksum}) {
    $checksum = $args{checksum};
  } else {
    croak "No checksum or MSBid provided";
  }

  print "Checksum: $checksum\n";
  print "ProjectID: " . $self->projectid,"\n";

  # Retrieve the relevant science program
  my $sp = $self->fetchSciProg();

  # Get the MSB
  my $msb = $sp->fetchMSB( $checksum );

  return $msb;
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

=cut

sub _write_sci_prog {
  my $self = shift;
  croak 'Usage: $db->_write_sci_prog( $sp )' unless @_;
  my $sp = shift;

  # Get the filename
  my $fullpath = $self->_sciprog_filename();

  # If we already have a file of that name we have to
  # check the timestamp and rename it.
  if (-e $fullpath) {
    # Get the timestamps
    my $tstamp = $self->_get_old_sciprog_timestamp;
    my $spstamp = $sp->timestamp;
    if (defined $spstamp) {
      croak "Science Program has changed on disk" 
	unless $tstamp == $spstamp;
    }

    # Move the old version of the file to back up
    my $backup = $self->_sciprog_filename("BACKUP");
    rename $fullpath, $backup 
      or croak "error renaming $fullpath to $backup: $!";
  }

  # Put a new timestamp into the science program prior to writing
  $sp->timestamp( time() );

  # open a new file
  open( my $fh, ">$fullpath") 
    or croak "Error writing SciProg to $fullpath: $!";

  # write the Science Program to disk
  print $fh "$sp";

  close($fh) or croak "Error closing new sci prog file: $!";
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
      or croak "Could not read indexfile $indexfile: $!";
    $highest = <$fh>;
  }

  # increment to get the next one
  $highest++;

  # Now update the file
  open(my $fh, ">$indexfile") 
    or croak "Could not open indexfile $indexfile: $!";
  print $fh "$highest";

  return $highest;
}


=back

=head2 DB Connectivity

These methods connect directly to the database. If the database is changed
(for example to move to DB_File or even Storable) then these are the
only routines that need to be modified.

=over 4

=item B<_dbconnect>

Initiate a connection to the database and store the result in the
object.

Requires a project ID and password.

=cut

sub _dbconnect {
  my $self = shift;

  # Forget about authentication for now

  # We are going to use a CSV DB
  my $filename = File::Spec->catdir($XMLDIR, "csv");
  my $dbh = DBI->connect("DBI:CSV:f_dir=$filename")
    or croak "Cannot connect: ". $DBI::errstr;

  # Store the handle
  $self->_dbhandle( $dbh );

}

=item B<_dbdisconnect>

Disconnect from the database.

=cut

sub _dbdisconnect {
  my $self = shift;
  $self->_dbhandle->disconnect;
}

=item B<_insert_row>

Insert a row into the database using the information provided in the hash.

  $db->_insert_row( %data );

The contents of the hash are usually defined by the C<OMP::MSB> class
and its C<summary()> method.

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
  $dbh->do("INSERT INTO $TABLE VALUES (?, ?, ?, ?, ?)", undef,
	   $index, $data{checksum}, $self->projectid, $data{remaining},
	   $self->_sciprog_filename);

}


=item B<_clear_old_rows>

Remove all rows associated with the current project ID.

This should probably be combined with the insert step
to prevent the case where we remove the old rows and fail to insert the
new ones.

=cut

sub _clear_old_rows {
  my $self = shift;

  # Get the DB handle
  my $dbh = $self->_dbhandle;
  my $proj = $self->projectid;

  # Store the data
  $dbh->do("DELETE FROM $TABLE WHERE projectid = \"$proj\"");

}

=item B<_fetch_row>

Retrieve a row of information from the database table.

  %result = $db->_fetch_row( id => $key );

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
  my @substrings = map { " $_ = $query{$_} " } keys %query;

  # and construct the SQL command
  my $statement = "SELECT * FROM $TABLE WHERE" .
    join("AND", @substrings);

  # prepare and execute
  my $dbh = $self->_dbhandle;
  my $ref = $dbh->selectall_hashref( $statement );

  # The result is now the first entry in @$ref
  my %result;
  %result = %{ $ref->[0] } if @$ref;

  return %result;
}

=back

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
