package OMP::UserServer;

=head1 NAME

OMP::UserServer - OMP user information server class

=head1 SYNOPSIS

  OMP::UserServer->addUser( $user );
  OMP::UserServer->getUser( $userid );

=head1 DESCRIPTION

This class provides the public server interface for the OMP user
database system.

This class is intended for use as a stateless server. State is
maintained in external databases. All methods are class methods.

=cut

use strict;
use warnings;
use Carp;

# OMP dependencies
use OMP::UserDB;
use OMP::User;
use OMP::UserQuery;
use OMP::Error qw/ :try /;

# Inherit server specific class
use base qw/OMP::SOAPServer OMP::DBServer/;

our $VERSION = (qw$Revision$)[1];

=head1 METHODS

=over 4

=item B<addUser>

  OMP::UserServer->addUser( $user );

For now the argument is an C<OMP::User> object.

=cut

sub addUser {
  my $class = shift;
  my $user = shift;

  my $E;
  try {

    my $db = new OMP::UserDB(
			     DB => $class->dbConnection,
			    );

    $db->addUser($user);

  } catch OMP::Error with {
    # Just catch OMP::Error exceptions
    # Server infrastructure should catch everything else
    $E = shift;

  } otherwise {
    # This is "normal" errors. At the moment treat them like any other
    $E = shift;

  };

  # This has to be outside the catch block else we get
  # a problem where we cant use die (it becomes throw)
  $class->throwException( $E ) if defined $E;

  return;
}

=item updateUser

Update user details.

  OMP::UserServer->updateUser( $user );

For now accepts a C<OMP::User> object.

=cut

sub updateUser {
  my $class = shift;
  my $user = shift;

  my $E;
  try {

    my $db = new OMP::UserDB(
			     DB => $class->dbConnection,
			    );

    $db->updateUser( $user );

  } catch OMP::Error with {
    # Just catch OMP::Error exceptions
    # Server infrastructure should catch everything else
    $E = shift;

  } otherwise {
    # This is "normal" errors. At the moment treat them like any other
    $E = shift;

  };

  # This has to be outside the catch block else we get
  # a problem where we cant use die (it becomes throw)
  $class->throwException( $E ) if defined $E;

  return;
}

=item B<verifyUser>

Verify the specified user exists on the system.

  $isthere = OMP::UserServer->verifyUser($userid);

=cut

sub verifyUser {
  my $class = shift;
  my $userid = shift;

  my $status;
  my $E;
  try {

    my $db = new OMP::UserDB(
			     DB => $class->dbConnection,
			    );

    $status = $db->verifyUser($userid);

  } catch OMP::Error with {
    # Just catch OMP::Error exceptions
    # Server infrastructure should catch everything else
    $E = shift;

  } otherwise {
    # This is "normal" errors. At the moment treat them like any other
    $E = shift;

  };

  # This has to be outside the catch block else we get
  # a problem where we cant use die (it becomes throw)
  $class->throwException( $E ) if defined $E;

  return $status;
}

=item B<getUser>

Get the specified user information.

  $user = OMP::UserServer->getUser($userid);

This is not SOAP friendly. The user information is returned as an C<OMP::User>
object.

=cut

sub getUser {
  my $class = shift;
  my $userid = shift;

  my $user;
  my $E;
  try {

    my $db = new OMP::UserDB(
			     DB => $class->dbConnection,
			    );

    $user = $db->getUser($userid);

  } catch OMP::Error with {
    # Just catch OMP::Error exceptions
    # Server infrastructure should catch everything else
    $E = shift;

  } otherwise {
    # This is "normal" errors. At the moment treat them like any other
    $E = shift;

  };

  # This has to be outside the catch block else we get
  # a problem where we cant use die (it becomes throw)
  $class->throwException( $E ) if defined $E;

  return $user;
}

=item B<queryUsers>

Query the user database using an XML representation of the query.

  $users = OMP::UserServer->queryUsers($userid,
                                       $format );

See C<OMP::UserQuery> for more details on the format of the XML query.
A typical query could be:

  <UserQuery>
    <userid>AJA</userid>
    <userid>TIMJ</userid>
  </UserQuery>

This would return the user information for TIMJ and AJA.

The format of the returned data is controlled by the last argument.
This can either be "object" (a reference to an array containing
C<OMP::User> objects), "hash" (reference to an array of hashes), or
"xml" (return data as XML document). 

I<Currently only "object" is implemented>.

=cut

sub queryUsers {
  my $class = shift;
  my $xmlquery = shift;
  my $mode = lc( shift );
  $mode = "object" unless $mode;

  my @users;
  my $E;
  try {

    my $query = new OMP::UserQuery( XML => $xmlquery );

    my $db = new OMP::UserDB(
			     DB => $class->dbConnection,
			    );

    @users = $db->queryUsers( $query );

  } catch OMP::Error with {
    # Just catch OMP::Error exceptions
    # Server infrastructure should catch everything else
    $E = shift;

  } otherwise {
    # This is "normal" errors. At the moment treat them like any other
    $E = shift;

  };

  # This has to be outside the catch block else we get
  # a problem where we cant use die (it becomes throw)
  $class->throwException( $E ) if defined $E;

  return \@users;
}


=back

=head1 SEE ALSO

L<OMP::ProjServer>, L<OMP::User>, L<OMP::UserDB>.

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=cut

1;
