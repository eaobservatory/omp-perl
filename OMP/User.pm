package OMP::User;

=head1 NAME

OMP::User - A User of the OMP system

=head1 SYNOPSIS

  use OMP::User;

  $u = new OMP::User( userid => 'xyz',
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
use Carp;
use OMP::UserServer;

# Overloading
use overload '""' => "stringify";

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
      # returns undef (unless it was given undef)
      my $retval = $user->$method( $args{$key});
      return undef if (!defined $retval && defined $args{$key});
    }
  }

  return $user;
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

An undefined or null string email address is allowed.
A null string is treated as undef.

=cut

sub email {
  my $self = shift;
  if (@_) { 
    my $addr = shift;
    if (defined $addr) {
      # Also translate '' to undef
      if (length($addr) == 0) {
	# Need to do this so that we match our input string
	$self->{Email} = undef;
	return '';
      }
      return undef unless $addr =~ /\@/;
    }
    # undef is okay
    $self->{Email} = $addr;
  }
  return $self->{Email};
}

=back

=head2 General

=over 4

=item B<html>

Generate an HTML representation of the user information.

  $html = $u->html;

Returns a HTML string looking like:

  <a href="mailto:$email">$name</a>

if the email address is defined.

=cut

sub html {
  my $self = shift;
  my $email = $self->email;
  my $name = $self->name;
  my $id = $self->userid;

  my $html;
  if ($email) {
    # We have an email address

    # if no name so use email
    $name = $email unless $name;

    $html = "<A HREF=\"mailto:$email\">$name</A>";

  } elsif ($name) {

    # Just a name
    $html = "<B>$name</B>";

  } elsif ($id) {

    $html = "<B>$id</B>";

  } else {
    # User id

    $html = "<I>No name specified</I>";

  }

  return $html;
}

=item B<text_summary>

[should probably be part of a general summary() method that takes
a "format" as argument]

  $text = $user->text_summary;

=cut

sub text_summary {
  my $self = shift;
  my $email = $self->email;
  my $name = $self->name;
  my $id = $self->userid;

  my $text = "USERID: $id\n";

  $text .=   "NAME:   " .(defined $name ? $name : "UNDEFINED")."\n";
  $text .=   "EMAIL:  " .(defined $email ? $email : "UNDEFINED")."\n";

  return $text;
}

=item B<stringify>

Stringify overload. Returns the name of the user.

=cut

sub stringify {
  my $self = shift;
  return $self->name;
}

=item B<verify>

Verify that the user described in this object is a valid
user of the OMP. This requires a query of the OMP database
tables. All entries are compared.

  $isthere = $u->verify;

Returns true or false.

[simply verifies that the userid exists. Does not yet verify contents]

=cut

sub verify {
  my $self = shift;
  return OMP::UserServer->verifyUser( $self->userid );
}

=item B<infer_userid>

Try to guess the user ID from the name. The name can either
be supplied as an argument or from within the object.

This method can be called either as a class or instance method.

  $guess = OMP::User->infer_userid( 'T Jenness' );
  $guess = $user->infer_userid;

Although the latter is only interesting if used to raise
warnings about inconsistent IDs (which is generally not enforced)
or after creating an object and making an inspired guess from the
name. The userid in the object is not updated.

The guess work assumes that the name is "forname surname" or
alternatively "surname, forname". A simplistic attempt is made
to catch "Jr" and "Sr".

Returns undef if a user ID could not be guessed.

=cut

sub infer_userid {
  my $self = shift;

  my $name;
  if (@_) {
    $name = shift;
  } elsif (UNIVERSAL::can($self,"name")) {
    $name = $self->name
  } else {
    croak "This method must be called with an argument or via a valid user object";
  }

  return undef unless defined $name;
  return undef unless $name =~ /\w/;

  # Remove some common suffixes
  $name =~ s/\b[JS]r\.?\b//g;

  # Clean
  $name =~ s/^\s+//;

  # Get the first name and surname
  my ($forname, $surname);
  if ($name =~ /,/) {
    # surname, initial (no need to worry about middle initials here
    ($surname, $forname) = split(/\s*,\s*/,$name,2);
  } else {
    # We want the last word for surname and the first for forname
    # since we do allow middle names
    my @parts = split(/\s+/,$name);
    return undef if scalar(@parts) < 2;
    $forname = $parts[0];
    $surname = $parts[-1];

    # Note that "le Guin" is surname LEGUIN
    if (scalar(@parts) > 2) {
      if ($parts[-2] =~ /(LE)/i) {
	$surname = $parts[-2] . $surname;
      }
    }

  }

  my $id = $surname . substr($forname,0,1);

  # Remove characters that are not  letter (eg hyphens)
  $id =~ s/\W//g;

  return uc($id);
}

=back

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
