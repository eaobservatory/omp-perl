package OMP::User;

=head1 NAME

OMP::User - A User of the OMP system

=head1 SYNOPSIS

  use OMP::User;

  $u = new OMP::User( id => 'xyz',
                      name => 'Mr Z',
                      email => 'xyz@abc.def.com');

  $u->verifyUser;

=head1 DESCRIPTION

This class simply provides details of the name and email address
of an user of the OMP system.

=cut

use 5.006;
use strict;
use warnings;


=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

Create a new C<OMP::User> object.

  $u = new OMP::User( %details );

The initial state of the object can be configured by passing in a hash
with keys: "userid", "email" and "name". See the associated accessor
methods for details.

Returns C<undef> if an object can not be created or configured.

=cut

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;

  # Read the arguments
  my %args = @_;

  # Create and bless
  my $user = bless {
		    UserID => undef,
		    Email => undef,
		    Name => undef,
		   }, $class;

  # Go through the input args invoking relevant methods
  for my $key (keys %args) {
    my $method = lc($key);
    if ($user->can($method)) {
      # Return immediately if an accessor methods
      # returns undef
      return undef unless $user->$method( $args{$key});
    }
  }

}

=back

=head2 Accessors

=over 4

=item B<userid>

The user name. This must be unique.

  $id = $u->userid;
  $u->userid( $id );

The user id is upper cased.

=cut

sub userid {
  my $self = shift;
  if (@_) { $self->{UserID} = uc(shift); }
  return $self->{UserID};
}

=item B<name>

The name of the user.

  $name = $u->name;
  $u->name( $name );

=cut

sub name {
  my $self = shift;
  if (@_) { $self->{Name} = shift; }
  return $self->{Name};
}

=item B<email>

The email address of the user.

  $addr = $u->email;
  $addr->email( $addr );

It must contain a "@". If the email does not look like an email
address the value will not be changed and the method will return
C<undef>.

=cut

sub email {
  my $self = shift;
  if (@_) { 
    my $addr = shift;
    return undef unless $addr =~ /\@/;
    $self->{Email} = $addr; 
  }
  return $self->{Email};
}

=back

=head2 General

=over 4

=item B<verify>

Verify that the user described in this object is a valid
user of the OMP. This requires a query of the OMP database
tables. All entries are compared.

  $u->verify;

Throws an exception if the user details do not match or if the
user does not exist in the system.

=cut

sub verify {
  my $self = shift;

}

=back

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
