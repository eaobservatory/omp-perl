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

use OMP::Error;
use OMP::General;
use DBI;

our $VERSION = '2.000';
our $DEBUG = 0;

=head1 METHODS

=head2 Connections Details

=over 4

=item B<loginhash>

This class method returns the information required to connect to a
database. The details are returned in a hash with the following
keys:

  driver  =>  DBI driver to use for database connection [mysql]
  server  =>  Database server (e.g. omp4)
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
                 driver   => OMP::Config->getData("database.driver"),
                 server   => OMP::Config->getData("database.server"),
                 database => OMP::Config->getData("database.database"),
                 user     => OMP::Config->getData("database.user"),
                 password => OMP::Config->getData("database.password"),
                );

  $details{server} = $ENV{OMP_DBSERVER}
    if (exists $ENV{OMP_DBSERVER} and defined $ENV{OMP_DBSERVER});

  return %details;
}

=back

=head2 Constructor

=over 4

=item B<new>

Instantiate a new object.

  $db = new OMP::DBbackend();
  $db = new OMP::DBbackend(1);

The connection to the database backend is made immediately.

By default the connection object is cached. A true argument forces a
brand new connection. The cache can be cleared using the <clear_cache>
class method. The class should not guarantee to return the same
database connection each time although it probably will. This is so
that connection pooling and automated expiry can be implemented at a
later date.

Caching of subclasses will work so long as the sub class constructor
calls the base class constructor.

=cut

my %CACHE;
sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $nocache = shift;

  if (!$nocache && defined $CACHE{$class}) {
    return $CACHE{$class};
  }

  my $db = bless {
                  TransCount => 0,
                  Handle => undef,
                  IsConnected => 0,
                 }, $class;

  # Store object in the cache
  $CACHE{$class} = $db;

  return $db;
}

=back

=head2 Accessor Methods

=over 4

=item B<_connected>

Set or retrieve the connection status of the database object.

  $db->_connected( 1 );
  $connected = $db->_connected;

When setting the status, this method takes one boolean parameter. It
returns a boolean when called in scalar context, and returns false
by default.

=cut

sub _connected {
  my $self = shift;

  if (@_) { $self->{IsConnected} = shift; }
  return $self->{IsConnected};
}

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
  if (@_) {
    $self->{Handle} = shift;
  } elsif (!defined $self->{Handle} && !$self->_connected) {

    # Only do the connect when we're asked what the handle is. We
    # only do this here so that we don't run into an infinite loop
    # if we are supplied with a handle.
    $self->connect;

  }
  return $self->{Handle};
}

=item B<handle_checked>

Check the database connection by attempting to "ping" the database.  If
we are no longer connected, then reconnect.

    my $dbh = $db->handle_checked();

=cut

sub handle_checked {
    my $self = shift;

    my $handle = $self->handle();
    return $handle if $handle->ping();

    $self->connect();
    return $self->handle();
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
  my %details    = $self->loginhash;
  my $DBIdriver  = $details{driver};
  my $DBserver   = $details{server};
  my $DBuser     = $details{user};
  my $DBpwd      = $details{password};
  my $DBdatabase = $details{database};

  my $dboptions = "";

  if ($DBIdriver eq 'mysql') {
    $dboptions = ":database=$DBdatabase;host=$DBserver;mysql_connect_timeout=10";
  } else {
    throw OMP::Error::DBConnection("DBI driver $DBIdriver not recognized");
  }

  print "DBI DRIVER: $DBIdriver; SERVER: $DBserver DATABASE: $DBdatabase USER: $DBuser\n"
    if $DEBUG;

  OMP::General->log_message( "------------> Login to DB $DBIdriver server $DBserver, database $DBdatabase, as $DBuser <-----");

  my $dbh = DBI->connect("dbi:$DBIdriver".$dboptions, $DBuser, $DBpwd, {
      PrintError => 0,
      mysql_auto_reconnect => 1,
      mysql_enable_utf8 => 1,
    })
    or throw OMP::Error::DBConnection("Cannot connect to database $DBserver: $DBI::errstr");

  # Disable newly-default SQL_MODE options until the OMP code can be updated
  # to comply with the new strict requirements.
  $dbh->do('SET @@SQL_MODE = REPLACE(@@SQL_MODE, "STRICT_TRANS_TABLES", "")');
  $dbh->do('SET @@SQL_MODE = REPLACE(@@SQL_MODE, "ERROR_FOR_DIVISION_BY_ZERO", "")');

  # Indicate that we have connected
  $self->_connected(1);

  # Store the handle
  $self->handle( $dbh );

}

=item B<disconnect>

Disconnect from the database. This method undefines the C<handle> object and
sets the C<_connected> status to disconnected.

=cut

sub disconnect {
  my $self = shift;
  $self->handle->disconnect;
  $self->handle( undef );
  $self->_connected( 0 );
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
  if ($self->_connected) {
    my $dbh = $self->handle();
    if (defined $dbh) {
      $self->rollback_trans;
      $self->disconnect;
    }
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

Copyright (C) 2001-2003 Particle Physics and Astronomy Research Council.
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
along with this program; if not, write to the
Free Software Foundation, Inc., 59 Temple Place, Suite 330,
Boston, MA  02111-1307  USA


=cut

1;
