package OMP::UserDB;

=head1 NAME

OMP::UserDB - OMP user database manipulation

=head1 SYNOPSIS

  use OMP::UserDB;
  $db = new OMP::UserDB( DB => new OMP::DBbackend );

  $db->addUser( $user );
  $db->updateUser( $user );
  $db->verifyUser( $userid );
  $user = $db->getUser( $userid );
  @users = $db->queryUser( $query );


=head1 DESCRIPTION

The C<UserDB> class is used to manipulate the user database.

=cut

use 5.006;
use warnings;
use strict;
use OMP::User;
use OMP::Error;

use base qw/ OMP::BaseDB /;

our $VERSION = (qw$Revision$)[1];

our $USERTABLE = "ompuser";

=head1 METHODS

=over 4

=item B<addUser>

Add a new user to the database.

  $db->addUser( $user );

The argument must be of class C<OMP::User>.

Throws an exception if the user already exists in the database
(since all user IDs must be unique). Use C<updateUser> if you wish
to change the user details.

=cut

sub addUser {
  my $self = shift;
  my $user = shift;

  # Need to lock the database since we are writing
  $self->_db_begin_trans;
  $self->_dblock;

  $self->_add_user( $user );

  # End transaction
  $self->_dbunlock;
  $self->_db_commit_trans;

  return;
}

=item B<updateUser>

Update the details in the table associated with the
supplied user.

  $db->updateUser( $user );

The argument should be of class C<OMP::User>.

=cut

sub updateUser {
  my $self = shift;
  my $user = shift;

  # Need to lock the database since we are writing
  $self->_db_begin_trans;
  $self->_dblock;

  # Modify
  $self->_update_user( $user );

  # End transaction
  $self->_dbunlock;
  $self->_db_commit_trans;

}

=back

=head2 Internal Methods

=over 4

=item B<_add_user>

Add an C<OMP::User> object to the database (assuming it is
not in there already).

=cut

sub _add_user {
  my $self = shift;
  my $user = shift;

  $self->_db_insert_data( $USERTABLE,
			  $user->userid,
			  $user->name,
			  $user->email);

}

=item B<_update_user>

Update the details of the supplied user. The user
must already exist (else nothing changes).

  $db->_update_user( $user );

The details must be supplied as an C<OMP::User> object.

=cut

sub _update_user {
  my $self = shift;
  my $user = shift;

  # Update the fields
  $self->_db_update_data( $USERTABLE,
			  {
			   email => $user->email,
			   name => $user->name,
			  },
			  " userid = '".$user->userid ."' ");


}

=back

=head1 SEE ALSO

This class inherits from C<OMP::BaseDB>. It stores C<OMP::User>
objects

For related classes see C<OMP::ProjDB> and C<OMP::FeedbackDB>.

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
