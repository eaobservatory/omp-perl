package OMP::KeyServer;

=head1 NAME

OMP::KeyServer - Generate and verify keys for validating CGI submissions

=head1 SYNOPSIS

  OMP::KeyServer-genKey( $timeout );
  OMP::KeyServer->verifyKey( $key );
  OMP::KeyServer->removeKey( $key );

=head1 DESCRIPTION

This class provides the public server interface for the OMP key
database.  Keys can be used to verify that a submission of a CGI
form is a valid one.  If you wanted to make sure a form could not
be submitted more than once you would generate a new unique key when the
form is displayed (and embed the key as one of the form paramters).
Once the form is submitted you verify the key (check that it exists
in the key database) and then remove the key once you have completed
the operations associated with the submit.  This way if the user 
attempts to resubmit the form later
on (such as by reposting the parameters by using their browser back/forward
buttons) you could stop any action from being taken by the resulting
submit since the key is no longer valid.  So I lied, you cant
stop them from resubmitting, but you can stop the submit from having
any effect.

When a key is generated it gets an expiry date and will no longer
be valid once that date is reached.

This class is intended for use as a stateless server. State is
maintained in external databases. All methods are class methods.

=cut

use strict;
use warnings;
use Carp;

# OMP dependencies
use OMP::KeyDB;
use Time::Seconds;
use OMP::Error qw/ :try /;

# Inherit server specific class
use base qw/OMP::SOAPServer OMP::DBServer/;

=head1 METHODS

=over 4

=item B<genKey>

Get a new key.  Only argument is the optional timeout given as a
C<Time::Seconds> object.  The default timeout is 24 hours.

  $key = OMP::KeyServer->genKey($timeout);

=cut

sub genKey {
  my $class = shift;
  my $timeout = shift;

  # Get the key (or throw an exception)
  my $key;
  my $E;
  try {
    my $keydb = new OMP::KeyDB( DB => $class->dbConnection );
    $key = $keydb->genKey($timeout);
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

  return $key;
}


=item B<verifyKey>

Verify that given key is valid (exists in the database).  Returns 0 if key
is not valid.  Otherwise returns 1.  A key is invalid either when it expires
or has been explicitly removed.

  $verify = OMP::KeyServer->verifyKey($key);

=cut

sub verifyKey {
  my $class = shift;
  my $key = shift;

  # Throw an error if key is not defined
  (! $key) and throw OMP::Error::BadArgs("Must supply a key");

  # Get the verification result or throw an error
  my $verify;
  my $E;
  try {
    my $keydb = new OMP::KeyDB( DB => $class->dbConnection );
    $verify = $keydb->verifyKey($key);
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

  return $verify;
}

=item B<removeKey>

Remove a key from the key database deleting it thusly.  This should be done
once a "transaction" has been completed using the associated key.  Returns
true if the operation completes (though this doesnt mean the key was
necessarily deleted by this operation since there is a very slight chance
that the key was already expired).

  OMP::KeyServer->removeKey($key);

=cut

sub removeKey {
  my $class = shift;
  my $key = shift;

  # Throw an error if key is not defined
  (! $key) and throw OMP::Error::BadArgs("Must supply a key");

  # Remove the key (throwing an exception if we encounter errors)
  my $verify;
  my $E;
  try {
    my $keydb = new OMP::KeyDB( DB => $class->dbConnection );
    $keydb->removeKey($key);
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

  return 1;
}

=back

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


=head1 AUTHOR

Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>

=cut

1;
