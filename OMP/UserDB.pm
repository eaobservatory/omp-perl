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
use OMP::UserQuery;

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

  # Make sure the user is not there already
  $self->verifyUser( $user->userid )
    and throw OMP::Error::FatalError( "This user [". 
				      $user->userid .
				      "] already exists. Use updateUser to modify the information");

  # Add the user
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

=item B<verifyUser>

Verify that the user exists in the database. This is a thin wrapper
around B<getUser>. Returns true if the user exists, else returns false.

  $isthere = $db->verifyUser( $userid );

=cut

sub verifyUser {
  my $self = shift;
  my $userid = shift;
  my $user = $self->getUser( $userid );
  return ($user ? 1 : 0 );
}

=item B<getUser>

Retrieve information on the specified user name.

  $user = $db->getUser( $userid );

Returned as an C<OMP::User> object. Returns C<undef> if the
user can not be found.

=cut

sub getUser {
  my $self = shift;
  my $userid = shift;

  return undef unless $userid;

  # Create a query string
  my $xml = "<UserQuery><userid>$userid</userid></UserQuery>";
  my $query = new OMP::UserQuery( XML => $xml );

  my @result = $self->queryUsers( $query );

  if (scalar(@result) > 1) {
    throw OMP::Error::FatalError( "Multiple users match the supplied id [$userid] - this is not possible [bizarre] }");
  }

  # Guaranteed to be only one match
  return $result[0];

}

=item B<queryUsers>

Query the user database table and retrieve the matching user objects.
Queries must be supplied as C<OMP::UserQuery> objects.

  @users = $db->queryUsers( $query );

=cut

sub queryUsers {
  my $self = shift;
  my $query = shift;

  return $self->_query_userdb( $query );
}

=item B<deleteUser>

Delete the specified user from the system.

  $db->deleteUser( $userid );

=cut

sub deleteUser {
  my $self = shift;
  my $userid = shift;

  # Need to lock the database since we are writing
  $self->_db_begin_trans;
  $self->_dblock;

  # Delete the user
  $self->_db_delete_data( $USERTABLE, "userid = '$userid'");

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

  # In some cases an email address is undefined
  # for now allow this by defining it (eventually we will allow
  # null fields)
  my $email = $user->email;

  $self->_db_insert_data( $USERTABLE,
			  $user->userid,
			  $user->name,
			  $email);

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

=item B<_query_userdb>

Query the user database table.

  @results = $db->_query_userdb( $query );

Query must be an C<OMP::UserQuery> object.

=cut

sub _query_userdb {
  my $self = shift;
  my $query = shift;

  my $sql = $query->sql( $USERTABLE );

  # Fetch
  my $ref = $self->_db_retrieve_data_ashash( $sql );

  # Return the object equivalents
  return map { $_->{email} = undef if (defined $_->{email} && length($_->{email}) eq 0);
		 new OMP::User( %$_ ) } @$ref;
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
