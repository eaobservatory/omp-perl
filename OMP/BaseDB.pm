package OMP::BaseDB;

=head1 NAME

OMP::BaseDB - Base class for OMP database manipulation

=head1 SYNOPSIS

  $db->_begin_trans;

  $db->_commit_trans;


=head1 DESCRIPTION

This class has all the generic methods required by the OMP to
deal with database transactions of all kinds that are shared
between subclasses (ie nothing that is different between science
program database and project database).

=cut


use 5.006;
use strict;
use warnings;
use Carp;

# OMP Dependencies
use OMP::Error;

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

=item B<new>

Base class for constructing a new instance of a OMP DB connectivity
class.


  $db = new OMP::BasDB( ProjectID => $project,
			Password  => $passwd
			DB => $connection,
		      );

See C<OMP::ProjDB> and C<OMP::MSBDB> for more details on the
use of these arguments and for further keys.

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

  # create the object (else we cant use accessor methods)
  my $object = bless $db, $class;

  # Populate the object by invoking the accessor methods
  # Do this so that the values can be processed in a standard
  # manner. Note that the keys are directly related to the accessor
  # method name
  for (qw/Password ProjectID/) {
    my $method = lc($_);
    $object->$method( $args{$_} ) if exists $args{$_};
  }

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

All project IDs are upper-cased automatically.

=cut

sub projectid {
  my $self = shift;
  if (@_) { $self->{ProjectID} = uc(shift); }
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

=head2 DB methods

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

  my $dbh = $self->_dbhandle or
    throw OMP::Error::DBError("Database handle not valid");

  # Begin a transaction
  $dbh->begin_work
    or throw OMP::Error::DBError("Error in begin_work: $DBI::errstr\n");

#  $dbh->do("BEGIN TRANSACTION")
#    or throw OMP::Error::DBError("Error beginning transaction: $DBI::errstr");
  $self->_intrans(1);
}

=item B<_db_commit_trans>

Commit the transaction. This informs the database that everthing
is okay and that the actions should be finalised.

=cut

sub _db_commit_trans {
  my $self = shift;
  my $dbh = $self->_dbhandle;
  throw OMP::Error::DBError("Database handle not valid") unless defined $dbh;

  if ($self->_intrans) {
    $self->_intrans(0);
    $dbh->commit
      or throw OMP::Error::DBError("Error committing transaction: $DBI::errstr");
#    $dbh->do("COMMIT TRANSACTION");

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
  throw OMP::Error::DBError("Database handle not valid") unless defined $dbh;

  if ($self->_intrans) {
    $self->_intrans(0);
    $dbh->rollback
      or throw OMP::Error::DBError("Error rolling back transaction (ironically): $DBI::errstr");
#    $dbh->do("ROLLBACK TRANSACTION");

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

=back

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
