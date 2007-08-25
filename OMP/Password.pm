package OMP::Password;

=pod

=head1 NAME

OMP::Password - Password related things.

=head1 SYNOPSIS

  use OMP::Password;
  use OMP::Error qw/ :try /;
  use OMP::Constants qw /:status/;

  #  Single try.
  my $pass =
    OMP::Password->get_password({
      'prompt' => 'Enter staff password: '
    });

  try {
    my $ok = OMP::Password->verify_staff_password( $pass );
  }
  catch OMP::Error::Authentication with {
    my $err = shift;
    throw $err;
  };
  print "password: $pass\n";

  #  Ask 3 times for a staff password, disable exceptions.
  $pass =
    OMP::Password->get_verified_password({
      'tries' => 3,
      'verify' => 'verify_staff_password',
      'exception' => 0
    });
  print "password: $pass\n";


=head1 DESCRIPTION

This module is a collection of password related methods.

=cut

use 5.006;
use strict;
use warnings;

our $VERSION = qw/$REVISION: $/[1];

use Term::ReadLine;

use OMP::Error qw/ :try /;
use OMP::Constants qw/ :status /;
use OMP::Config;

=pod

=head1 METHODS

There are no instance methods, only class (static) methods.

=head2 Acquisition

=over 4

=item B<get_password>

A wrapper around L<&Term::ReadLine::readline> function to ask for
password; the prompt may be highlighted with underline.

It takes an optional hash reference to set behaviour, and returns the
plaintext password string.  Below is the key-value description of the
hash reference ...

=over 4

=item I<prompt>

The prompt text to show.

Default is "Enter password: ".

=item I<err-prompt>

The prompt text to show when password is incorrect.  (Currently this
is unused by this method.)

Default is "Incorrect password, enter again: ".

=back

=back

=cut

sub get_password {

  my ( $self, $opt ) = @_;

  my $config = _default_password_prompt();
  _copy_new_hash_values( $config, $opt );

  my $term = Term::ReadLine->new( 'Password Entry' );

  # Needs Term::ReadLine::Gnu.
  my $attribs = $term->Attribs;
  $attribs->{redisplay_function} = $attribs->{shadow_redisplay};
  my $password = $term->readline( $config->{'prompt'} );
  $attribs->{redisplay_function} = $attribs->{rl_redisplay};

  return $password;
}

sub _default_password_prompt {

  return {
    'prompt' => q/Enter password: /,
    'err-prompt' => q/Incorrect password, enter again: /,
  };
}

sub _copy_new_hash_values {

  my ( $orig, $opt ) = @_;
  for my $k ( keys %{ $orig } ) {

    $orig->{ $k } = $opt->{ $k } if exists $opt->{ $k };
  }
  return;
}

=pod

=head2 Acquisition and Verification

=over 4

=item B<get_verified_password>

Combines above I<get_password> method with one of the verification
methods, listed elsewhere.

It returns the verified password, unless number of tries specified is
zero, in which case password is undefined.

It requires a hash reference of password verification method name; see
I<verify> below.  Other values are optional for prompt behaviour and
exception handling (see below for more on that).

See I<get_password> method for I<prompt> & I<err-prompt> options.
Note that in case of invalid password, I<prompt> is set to
I<err-prompt>.  Other pairs are ...

=over 4

=item I<exception>

If set to a true value, exceptions will be thrown within this method.
Negative of the value (to preserve the existing behaviour of other
methods) is propagated to the specified verification method.

Default is a true value.

=item I<tries>

If initial number of tries is positive, password will be asked that
many times or until password is verified, whichever happens earlier.

If zero, C<OMP::Error::Authentication> exception is thrown (password
will be undefined).

If negative, password will be asked until can be verified.

Default is 4.

=item I<verify>

A method name of I<OMP::Password> class to verify the password.

C<OMP::Error::FatalError> exception is thrown if the given method is
not found.

It must be specified by the caller; there is no default.

=back

=back

=cut

sub get_verified_password {

  my ( $class, $opt ) = @_;

  my $config = _default_password_prompt();
  $config->{'verify'} = undef;
  $config->{'tries'} = 4;
  $config->{'exception'} = 'throw';
  _copy_new_hash_values( $config, $opt );

  my $verify = $config->{'verify'};

  # Do we also need to check for $class->isa( 'OMP::Password' )? (anubhav)
  unless ( defined $verify && $class->can( $verify ) ) {

    throw OMP::Error::FatalError( q/No viable method name given/, OMP__FATAL )
      if $config->{'exception'} ;

    return;
  }

  my ( $pass, $ok );
  #  When the initial number of tries is negative, loop until password is
  #  verified.
  ASK: until ( $ok || $config->{'tries'}-- == 0 ) {

    try {

      $pass = OMP::Password->get_password( $config );
      $ok = $class->$verify( $pass, !$config->{'exception'} );

      $config->{'prompt'} = $config->{'err-prompt'}
        if !$ok && defined $config->{'err-prompt'} ;
    }
    catch OMP::Error::Authentication with {

      my $error = shift;
      throw $error
        if $config->{'exception'}
        # See comment for until().
        && $config->{'tries'} == 0 ;

      $config->{'prompt'} = $config->{'err-prompt'}
        if defined $config->{'err-prompt'} ;
    };
  }

  throw OMP::Error::Authentication( qq/No password given\n/)
    if $config->{'exception'} && !defined $pass ;

  return $pass;
}

=pod

=head2 Verification

=over 4

=item B<verify_administrator_password>

Compare the supplied password with the administrator password. Throw
an exception if the two do not match. This safeguard is used to
prevent people from modifying the contents of the project database
without having permission.

  OMP::Password->verify_administrator_password( $input );

Note that the supplied password is assumed to be unencrypted.

An optional second argument can be used to disable the exception
throwing. If the second argument is true the routine will return
true or false depending on whether the password is verified.

  $isokay = OMP::Password->verify_administrator_password( $input, 1 );

Always fails if the supplied password is undefined.

=cut

sub verify_administrator_password {
  my $self = shift;
  my $password = shift;
  my $retval = shift;

  # The encrypted admin password
  # At some point we'll pick this up from somewhere else.
  my $admin = OMP::Config->getData("password.admin");

  # Encrypt the supplied password using the admin password as salt
  # unless the supplied password is undefined
  my $encrypted = ( defined $password ? crypt($password, $admin) : "fail" );

  # A bit simplistic at the present time
  my $status;
  if ($encrypted eq $admin) {
    $status = 1;
  } else {
    # Throw an exception if required
    if ($retval) {
      $status = 0;
    } else {
      throw OMP::Error::Authentication("Failed to match administrator password\n");
    }
  }
  return $status;
}

=pod

=item B<verify_staff_password>

Compare the supplied password with the staff password. Throw
an exception if the two do not match. This provides access to some
parts of the system normally restricted to principal investigators.

  OMP::Password->verify_staff_password( $input );

Note that the supplied password is assumed to be unencrypted.

An optional second argument can be used to disable the exception
throwing. If the second argument is true the routine will return
true or false depending on whether the password is verified.

  $isokay = OMP::Password->verify_staff_password( $input, 1 );

Always fails if the supplied password is undefined.

The password is always compared with the administrator password
first.

=cut

sub verify_staff_password {
  my $self = shift;
  my $password = shift;
  my $retval = shift;

  # First try admin password
  my $status = OMP::Password->verify_administrator_password( $password,1);

  # Return immediately if all is well
  # Else try against the staff password
  return $status if $status;

  # The encrypted staff password
  # At some point we'll pick this up from somewhere else.
  my $admin = OMP::Config->getData("password.staff");

  # Encrypt the supplied password using the staff password as salt
  # unless the supplied password is undefined
  my $encrypted = ( defined $password ? crypt($password, $admin) : "fail" );

  # A bit simplistic at the present time
  if ($encrypted eq $admin) {
    $status = 1;
  } else {
    # Throw an exception if required
    if ($retval) {
      $status = 0;
    } else {
      throw OMP::Error::Authentication("Failed to match staff password\n");
    }
  }
  return $status;
}

=pod

=item B<verify_queman_password>

Compare the supplied password with the queue manager password. Throw
an exception if the two do not match. This provides access to some
parts of the system normally restricted to queue managers.

  OMP::Password->verify_queueman_password( $input, $queue );

Note that the supplied password is assumed to be unencrypted. The
queue name (usually country name) must be supplied.

An optional third argument can be used to disable the exception
throwing. If the second argument is true the routine will return
true or false depending on whether the password is verified.

  $isokay = OMP::Password->verify_queman_password( $input, $queue, 1 );

Always fails if the supplied password is undefined. The country
must be defined unless the password is either the staff or administrator
password (which is compared first).

=cut

sub verify_queman_password {
  my $self = shift;
  my $password = shift;
  my $queue = shift;
  my $retval = shift;

  # First try staff password
  my $status = OMP::Password->verify_staff_password( $password,1);

  # Return immediately if all is well
  # Else try against the queue password
  return $status if $status;

  # rather than throwing conditional exceptions with complicated
  # repeating if statements just paper over the cracks until the
  # final failure triggers the throwing of exceptions
  $queue = "UNKNOWN" unless $queue;
  $queue = uc($queue);

  # The encrypted passwords
  # At some point we'll pick this up from somewhere else.
  my %passwords = (
                   UH => OMP::Config->getData("password.uh"),
                  );

  my $admin = (exists $passwords{$queue} ? $passwords{$queue} : "noadmin");

  # Encrypt the supplied password using the queue password as salt
  # unless the supplied password is undefined
  my $encrypted = ( defined $password ? crypt($password, $admin)
                    : "fail" );

  # A bit simplistic at the present time
  if ($encrypted eq $admin) {
    $status = 1;
  } else {
    # Throw an exception if required
    if ($retval) {
      $status = 0;
    } else {
      throw OMP::Error::Authentication("Failed to match queue manager password for queue '$queue'\n");
    }
  }
  return $status;
}

=pod

=back

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>,
Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>,
Anubhav A. E<lt>a.agarwal@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
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
along with this program (see SLA_CONDITIONS); if not, write to the
Free Software Foundation, Inc., 59 Temple Place, Suite 330,
Boston, MA  02111-1307  USA

=cut

1;
