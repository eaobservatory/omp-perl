package OMP::KeyDB;

=head1 NAME

OMP::KeyDB - Generate, store, retrieve and delete keys

=head1 SYNOPSIS

  $db = new OMP::KeyDB( DB => $dbconnection );

  $db->genKey( $timeout );
  $db->verifyKey( $key );
  $db->removeKey( $key );

=head1 DESCRIPTION

This class generates keys and provides an interface to the database for
storing, retrieving (for verification) and deleting keys.

=cut

use 5.006;
use strict;
use warnings;
use Carp;
use OMP::Error;
use Crypt::PassGen;
use Time::Piece;
use Time::Seconds;
use base qw/ OMP::BaseDB /;

# Key table information
our $KEYTABLE = "ompkey";
our $KEYCOLUMN = "keystring";
our $EXPCOLUMN = "expiry";

# Our default timeout for keys
our $KEYTIMEOUT = new Time::Seconds(ONE_DAY);

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

Create a new instance of an C<OMP::KeyDB> object.

  $db = new OMP::KeyDB( DB => $connection );

If supplied, the database connection object must be of type
C<OMP::DBbackend>.  It is not accepted if that is not the case.
(but no error is raised - this is probably a bug).

=cut

# Use base class constructor

=back

=head2 General Methods

=over 4

=item B<genKey>

Generate and return a new key.  Optionally, a C<Time::Seconds> object may
be given as the only argument specifying a timeout for the key.  Default
timeout is 24 hours.

  $key = $db->genKey([$timeout]);

=cut

sub genKey {
  my $self = shift;
  my $timeout = shift;

  # Use the default timeout if none was specified
  if (! $timeout) {
    $timeout = $KEYTIMEOUT;
  } else {
    # Make sure timeout is a Time::Seconds object
    throw OMP::Error::BadArgs("Timeout must be a Time::Seconds object")
      unless UNIVERSAL::isa( $timeout, "Time::Seconds" );
  }

  # Generate key string.  Make sure it is unique by verifying that it
  # does not exist in the database already.
  my $key;
  my $count = 100;  # don't want to attempt to generate a unique key forever
  my $verify = 1;
  while ($verify and $count > 0) {
    $key = $self->_gen_key_string;
    $verify = $self->verifyKey($key);
    $count--;
  }

  # Throw an error if we didn't generate a unique key
  (! $key) and throw OMP::Error::FatalError("Unable to generate a unique key.  How strange.");

  # Get the expiry date
  my $expiry = $self->_get_expiry_date($timeout);

  # Store key and timeout to database
  # Begin trans
  $self->_db_begin_trans;
  $self->_dblock;

  $self->_write_key($key, $expiry);

  # End trans
  $self->_dbunlock;
  $self->_db_commit_trans;

  # Return key
  return $key;
}

=item B<verifyKey>

Verify a key by retrieving it from the database.  Returns 0 if the key
is not retrieved and 1 if it is.

  $verify = $db->verifyKey($key);

=cut

sub verifyKey {
  my $self = shift;
  my $key = shift;

  # Delete expired keys first
  # Begin trans
  $self->_db_begin_trans;
  $self->_dblock;

  $self->_expire_keys;

  # End trans
  $self->_dbunlock;
  $self->_db_commit_trans;

  # Fetch the key, literally (since this is the only way to
  # verify that it exists.  Clearly we are already in possession
  # of the key.
  my $result = $self->_fetch_key($key);

  return ($result ? 1 : 0);
}

=item B<removeKey>

Remove a key (delete it) from the database.

  $db->removeKey($key);

=cut

sub removeKey {
  my $self = shift;
  my $key = shift;

  # First do an expire
  $self->_expire_keys;

  # Now do the remove
  $self->_remove_key($key);
}

=back

=head2 Internal Methods

=over 4

=item B<_gen_key_string>

Generate a string for key.

  $db->_gen_key_string;

=cut

sub _gen_key_string {
  my $self = shift;

  my @key = Crypt::PassGen::passgen( NLETT => 9 );

  return $key[0]
}

=item B<_write_key>

Store a key and the associated expiry date in the database.

  $db->_write_key($key, $expiry);

=cut

sub _write_key {
  my $self = shift;
  my $key = shift;
  my $expiry = shift;

  # Figure out the expiry date

  # Do the insert
  $self->_db_insert_data( $KEYTABLE, $key, $expiry);
}

=item B<_fetch_key>

Attempt to retrieve a key from the database and return it if successful.
Obviously, there is no point in "fetching" the key since we already have it.
By "fetch" we mean get it from the database since thats the only way to
verify that it is actually there.

  $db->_fetch_key($key);

=cut

sub _fetch_key {
  my $self = shift;
  my $key = shift;

  # Our sql statement
  my $sql = "select $KEYCOLUMN from $KEYTABLE where $KEYCOLUMN = \"$key\"";

  # Do the fetch
  my $result = $self->_db_retrieve_data_ashash( $sql );

  # Throw an error if more than one result is returned (that would
  # be very strange)
  throw OMP::Error::DBError("More than one key was returned.  This should not be possible!")
    if ($result->[1]);

  # Return just the key
  return $result->[0]->{keystring};

}

=item B<_expire_keys>

Delete keys from the database that have expired.

  $db->_expire_keys;

=cut

sub _expire_keys {
  my $self = shift;

  my $localtime = localtime;
  $localtime = $localtime->strftime("%Y%m%d %T");

  # Our sql clause for the delete
  my $clause = "$EXPCOLUMN < \"$localtime\"";

  # Do the delete
  $self->_db_delete_data( $KEYTABLE, $clause );
}

=item B<_remove_key>

Delete a specific key in the database.

  $db->_remove_key($key);

=cut

sub _remove_key {
  my $self = shift;
  my $key = shift;

  # Our sql clause for the delete
  my $clause = "$KEYCOLUMN = \"$key\"";

  # Do the delete
  $self->_db_delete_data( $KEYTABLE, $clause );
}

=item B<_get_expiry_date>

Given a keys timeout value return an expiry date value suitable for storage in
the database.

  $db->_get_expiry_date($timeout)

=cut

sub _get_expiry_date {
  my $self = shift;
  my $timeout = shift;

  my $localtime = localtime;
  my $expiry = $localtime + $timeout->seconds;

  return $expiry->strftime("%Y%m%d %T"); # Sybase format
}

=back

=head1 SEE ALSO

This class inherits from C<OMP::BaseDB>.

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research
Council.  All Rights Reserved.

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
