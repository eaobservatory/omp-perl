package OMP::DBbackend;

=head1 NAME

OMP::DBbackend - Connect and disconnect from specific database backend

=head1 SYNOPSIS

  use OMP::DBbackend;

  # Set up connection to database
  my $db = new OMP::DBbackend;

  # Get the connection handle
  $dbh = $db->handle;

  # disconnect (automatic when goes out of scope)
  $db->disconnect;

=head1 DESCRIPTION

Since the OMP interacts with many database tables but only
requires a single database connection we separate out the connection
management from the database interaction. This will allow us to optimize
connections for servers that are running continuously without having
to use the overhead of connecting for each transaction.

We use a HAS-A relationship with the OMP servers rather than an IS-A
relationship because we do not want to initiate a new connection each
time we instantiate a new low-level database object.

=cut

use 5.006;
use strict;
use warnings;
use Carp;

# OMP

BEGIN { $ENV{SYBASE} = "/local/progs/sybase" unless exists $ENV{SYBASE} }

use OMP::Error;
use OMP::General;
use DBI;
use DBD::Sybase; # This triggers immediate failure if $SYBASE not right

our $VERSION = (qw$Revision$)[1];
our $DEBUG = 0;

=head1 METHODS

=head2 Connections Details

=over 4

=item B<loginhash>

This class method returns the information required to connect to a
database. The details are returned in a hash with the following
keys:

  server  =>  Database server (e.g. SYB_*)
  database=>  The database to use for the transaction
  user    =>  database login name
  password=>  password for user

This is a class method so that it can easily be subclassed.

  %details = OMP::DBbackend->loginhash;

The following environment variables are recognised to override
these values:

  OMP_DBSERVER - the server to use

In the future this method may well read the details from a config
file rather than hard-wiring the values in the module.

=cut

sub loginhash {
  my $class = shift;
  my %details = (
		 server   => "SYB_TMP",
		 database => "omp",
		 user     => "omp",
		 password => "***REMOVED***",
		);

  # possible override
  $details{server} = $ENV{OMP_DBSERVER}
    if (exists $ENV{OMP_DBSERVER} and defined $ENV{OMP_DBSERVER});

  # If we are now switching to SYB_UKIRT we have to change
  # the database field [this is only for development]
  $details{database} = 'archive'
    if $details{server} eq 'SYB_UKIRT';

  return %details;
}

=back

=head2 Constructor

=over 4

=item B<new>

Instantiate a new object.

  $db = new OMP::DBbackend;

The connection to the database backend is made immediately.

=cut

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;

  my $db = bless {
		  TransCount => 0,
		  Handle => undef,
		 }, $class;

  $db->connect;

  return $db;
}

=back

=head2 Accessor Methods

=over 4

=item B<handle>

The database connection handle associated with this object.

  $dbh = $db->handle;
  $db->handle( $dbh );

If this object is around for a long time it is possible that the
connection may fail (maybe if the database has been rebooted). If that
happens we may want to check the connection each time we return this
object.

=cut

sub handle {
  my $self = shift;
  if (@_) { $self->{Handle} = shift; }
  return $self->{Handle};
}

=item B<trans_count>

Indicate whether we are in a transaction or not.

  $intrans = $db->trans_count();
  $db->trans_count(1);

The number returned by this method indicates the number of
transactions that we have been asked to begin. A transaction
is only ended when this number hits zero [note that a transaction
is not committed automatically when this hits zero - the method
committing the transaction checks this number]

The method is usually called via the transaction handling methods
(e.g. C<begin_trans>, C<_inctrans>).

The number can not be negative (forced to zero if it is).

=cut

sub trans_count {
  my $self = shift;
  if (@_) { 
    my $c = shift;
    $c = 0 if $c < 0;
    $self->{TransCount} = $c;
  }
  return $self->{TransCount};
}

=back

=head2 General Methods

=over 4

=item B<connect>

Connect to the database. Automatically called by the
constructor.

An C<OMP::Error::DBConnection> exception is thrown if the connection
does not succeed.

=cut

sub connect {
  my $self = shift;

  # Database details
  my %details   = $self->loginhash;
  my $DBserver   = $details{server};
  my $DBuser     = $details{user};
  my $DBpwd      = $details{password};
  my $DBdatabase = $details{database};

  print "SERVER: $DBserver DATABASE: $DBdatabase USER: $DBuser\n"
    if $DEBUG;

  OMP::General->log_message( "------------> Login to DB server $DBserver as $DBuser <-----");

  # We are using sybase
  my $dbh = DBI->connect("dbi:Sybase:server=${DBserver};database=${DBdatabase};timeout=120", $DBuser, $DBpwd, { PrintError => 0 })
    or throw OMP::Error::DBConnection("Cannot connect to database: $DBI::errstr");

  # Store the handle
  $self->handle( $dbh );

}

=item B<disconnect>

Disconnect from the database.

=cut

sub disconnect {
  my $self = shift;
  $self->handle->disconnect;
  $self->handle( undef );
}

=item B<begin_trans>

Begin a database transaction. This is defined as something that has
to happen in one go or trigger a rollback to reverse it.

If a transaction is already in progress this method increments the 
transaction counter and returns without attempting to start a new
transaction.

Each transaction begun must be finished with a commit. If you start
two transactions the changes are only committed on the second commit.

=cut

sub begin_trans {
  my $self = shift;

  # Get the current count
  my $transcount = $self->trans_count;

  # If we are not in a transaction start one
  if ($transcount == 0) {

    my $dbh = $self->handle or
      throw OMP::Error::DBError("Database handle not valid");

    # Begin a transaction
    $dbh->begin_work
      or throw OMP::Error::DBError("Error in begin_work: $DBI::errstr\n");

  }

  # increment the counter
  $self->_inctrans;

}

=item B<commit_trans>

Commit the transaction. This informs the database that everthing
is okay and that the actions should be finalised.

Note that if we have started multiple nested transactions we only 
commit when the last transaction is committed.

=cut

sub commit_trans {
  my $self = shift;

  # Get the current count and return if it is zero
  my $transcount = $self->trans_count;
  return unless $transcount;

  if ($transcount == 1) {
    # This is the last transaction so commit
    my $dbh = $self->handle
      or throw OMP::Error::DBError("Database handle not valid");

    $dbh->commit
      or throw OMP::Error::DBError("Error committing transaction: $DBI::errstr");

  }

  # Decrement the counter
  $self->_dectrans;

}

=item B<rollback_trans>

Rollback (ie reverse) the transaction. This should be called if
we detect an error during our transaction.

I<All transactions are rolled back since the database itself can not
handle nested transactions we must abort from all transactions.>

=cut

sub rollback_trans {
  my $self = shift;

  # Check that we are in a transaction
  if ($self->trans_count) {

    # Okay rollback the transaction
    my $dbh = $self->handle
      or throw OMP::Error::DBError("Database handle not valid");

    # Reset the counter
    $self->trans_count(0);

    $dbh->rollback
      or throw OMP::Error::DBError("Error rolling back transaction (ironically): $DBI::errstr");

  }
}

=item B<lockdb>

Lock the database. NOT YET IMPLEMENTED.

The API may change since we have not decided whether this should
lock all OMP tables or the tables supplied as arguments.

=cut

sub lockdb {
  my $self = shift;
  return;
}

=item B<unlockdb>

Unlock the database. NOT YET IMPLEMENTED.

The API may change since we have not decided whether this should
unlock all OMP tables or the tables supplied as arguments.

=cut

sub unlockdb {
  my $self = shift;
  return;
}

=item B<DESTROY>

Automatic destructor. Guarantees that we will try to disconnect
even if an exception has been thrown. Also forces a rollback if we
are in a transaction.

=cut

sub DESTROY {
  my $self = shift;
  my $dbh = $self->handle;
  if (defined $dbh) {
    $self->rollback_trans;
    $self->disconnect;
  }
}

=back

=head2 Private Methods

=over 4

=item B<_inctrans>

Increment the transaction count by one.

=cut

sub _inctrans {
  my $self = shift;
  my $transcount = $self->trans_count;
  $self->trans_count( ++$transcount );
}

=item B<_dectrans>

Decrement the transaction count by one. Can not go lower than zero.

=cut

sub _dectrans {
  my $self = shift;
  my $transcount = $self->trans_count;
  $self->trans_count( --$transcount );
}

=back

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
