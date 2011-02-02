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

our $VERSION = qw/$REVISION$/[1];

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

A wrapper around L<Term::ReadLine/"readline"> function to ask for
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

  my $term = Term::ReadLine->new( 'Password Entry', *STDERR, *STDERR );

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

=item B<encrypt_password>

Encrypts the supplied plain password, returning the encrypted
value.

 $encrypted = OMP::Password->encrypt_password( $plain );

=cut

sub encrypt_password {
  my $self = shift;
  my $plain = shift;

  # Time to encrypt
  # Generate the salt from a random set
  # See the crypt entry in perlfunc
  my $salt = join '',
    ('.', '/', 0..9, 'A'..'Z', 'a'..'z')[rand 64, rand 64];

  #Encrypt it
  return crypt( $plain, $salt );
}

=item B<verify_password>

Compare the supplied project password and its encrypted version to
decide whether they match. Also verifies it against the administrator
password, the staff password, external pseudo-staff password and, if
queue is defined, the queue password. Queue can be a reference to an
array of multiple queue names.

  OMP::Password->verify_password( $input, $encrypted, $queue );

This will throw an "Authentication" exception is the password
does not verify. Specifying a third parameter with value true
will change the behaviour to return a boolean.

  $isokay = OMP::Password->verify_password( $input, $encrypted,
                                            $queue, 1);

=cut

sub verify_password {
  my $self = shift;
  my $plain = shift;
  my $encrypted = shift;
  my $queue = shift;
  my $retval = shift;

  # Test admin, staff and queue
  return 1 if $self->verify_queman_password( $plain, $queue, 1 );

  # Do tests with exception handling disabled
  # Then throw exception if required at end
  return 1 if $self->_verify_password( $plain, $encrypted, 1 );

  return $self->_handle_bad_status( $retval, "Failed to verify general password" );

}

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

  return $self->_verify_password( $password, $admin, $retval, "Failed to match administrator password" );
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

The password is verified by both looking at the "password.staff"
config file entry (done first) and also the "password.external"
config file entry.

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
  my @trials = ( OMP::Config->getData("password.staff") );

  # we may not have an external available
  try {
    push(@trials, OMP::Config->getData("password.external"));
  } catch OMP::Error::BadCfgKey with {
    # do not worry about a lack of external
  };

  return $self->_verify_password( $password, \@trials, $retval, "Failed to match staff password" );
}

=pod

=item B<verify_queman_password>

Compare the supplied password with the queue manager password. Throw
an exception if the two do not match. This provides access to some
parts of the system normally restricted to queue managers.

  OMP::Password->verify_queueman_password( $input, $queue );

Note that the supplied password is assumed to be unencrypted. The
queue name (usually country name) must be supplied and can be supplied
as a reference to an array of multiple queue names.

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

  # if we do not have an input password we abort
  return $self->_handle_bad_status( $retval, "No queue defined for queue manager verification" )
    if !defined $queue;

  # Expand queues
  my @queues;
  if (defined $queue) {
    @queues = ( ref($queue) ? @$queue : $queue );
  }

  # Assume that the queue password is in the config file
  # indexed by the queue name. This will generate an exception
  # if the queue password is not available so we trap that because
  # we don't require that every queue has a queue manager password
  my @qpass;
  for my $q (@queues) {
    try {
      push(@qpass,OMP::Config->getData( "password." . lc($q) ));
    } catch OMP::Error::BadCfgKey with {
      # ignore
    };
  }

  # if we have no passwords we must be failing verification
  if (!@qpass) {
    return $self->_handle_bad_status( $retval, "No queue manager password defined for queue $queue" );
  };

  return $self->_verify_password( $password, \@qpass, $retval, "Failed to match password for queue $queue" );
}

=back

=begin __INTERNAL

=head2 Verification Support Routines

=over 4

=item B<_verify_password>

Given a plain text value and an encrypted value, see if they
are equivalent and act accordingly.

  $isokay = $class->_verify_password( $plain, $encrypted, $retval );

where the third argument indicates whether a return value is required
or not. If false an OMP::Error::Authentication exception is thrown
rather than returning a boolen. An optional 4th argument contains
the error message that will be included in the exception and is
only used if $retval is false.

  $isokay = $class->_verify_password( $plain, $encrypted, $retval,
                    $errtext );

A reference to an array can be provided containing multiple encrypted
passwords to verify $plain against. If $encrypted is undef the match
fails automatically.

=cut

sub _verify_password {
  my $class = shift;
  my $password = shift;
  my $reference = shift;
  my $retval = shift;
  my $errtext = shift;

  # The reference enrypted passwords can be an array reference so unpack here
  my @to_compare;
  @to_compare = ( ref($reference) ? @$reference : $reference )
    if defined $reference;

  my $matches = 0;
  for my $trial (@to_compare) {
    # Encrypt the supplied password using the encrypted password as salt
    # unless the supplied password is undefined
    my $encrypted = ( defined $password ? crypt($password, $trial) : "fail" );
    if ($encrypted eq $trial) {
      $matches = 1;
      last;
    }
  }

  # handle what to do if we did or did not match
  if ($matches) {
    return 1; # everything is good
  } else {
    return $class->_handle_bad_status( $retval, $errtext );
  }
}

=item B<_handle_bad_status>

Determines whether an exception or bad status should be returned
based on the "use_retval" argument. If use_retval is true the
return value will be returned (always a false values) else you
will get the exception.

  return $class->_handle_bad_status( $use_retval, $errtext );

$errtext is the error message if an exception is required.

=cut

sub _handle_bad_status {
  my $class = shift;
  my $retval = shift;
  my $user_errtext = shift;

  # Throw an exception if required
  if (!$retval) {
    my $errtext = ( defined $user_errtext ? $user_errtext :
                    "Failed to authenticate supplied password");
    chomp $errtext;
    throw OMP::Error::Authentication( $errtext . "\n" );
  }
  return 0;
}

=back

=end __INTERNAL

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>,
Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>,
Anubhav A. E<lt>a.agarwal@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2007, 2010 Science and Technology Facilities Council.
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
