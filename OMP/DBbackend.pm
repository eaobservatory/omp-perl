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
use DBI;
use DBD::Sybase; # This triggers immediate failure if $SYBASE not right

our $VERSION = (qw$Revision$)[1];

=head1 METHODS

=head2 Connections Details

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

  return %details;
}

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

  my $db = bless {}, $class;

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


=item B<DESTROY>

Automatic destructor. Guarantees that we will try to disconnect
even if an exception has been thrown.

=cut

sub DESTROY {
  my $self = shift;
  my $dbh = $self->handle;
  $self->disconnect if defined $dbh;
}

=back

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
