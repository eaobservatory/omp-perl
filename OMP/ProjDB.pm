package OMP::ProjDB;

=head1 NAME

OMP::ProjDB - Manipulate the project database

=head1 SYNOPSIS

  $projdb = new OMP::ProjDB( ProjectID => $projectid,
			     DB => $dbconnection );

  $projdb->issuePassword();


=head1 DESCRIPTION

This class manipulates information in the project database.  It is the
only interface to the database tables. The tables should not be
accessed by directly to avoid loss of data integrity.


=cut

use 5.006;
use strict;
use warnings;
use Carp;
our $VERSION = (qw$ Revision: 1.2 $ )[1];

use OMP::Error;
use OMP::Project;

use Crypt::PassGen qw/passgen/;

use base qw/ OMP::BaseDB /;

# This is picked up by OMP::MSBDB
our $PROJTABLE = "ompproj";

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

Create a new instance of an C<OMP::ProjDB> object.

  $db = new OMP::ProjDB( ProjectID => $project,
                         DB => $connection);

If supplied, the database connection object must be of type
C<OMP::DBbackend>.  It is not accepted if that is not the case.
(but no error is raised - this is probably a bug).

=cut

# Use base class constructor

=back

=head2 Accessor Methods

=over 4



=back

=head2 General Methods

=over 4

=item B<verifyPassword>

Verify that the supplied plain text password matches the password
stored in the project database.

  $verified = 1 if $db->verifyPassword( $plain_password );

Returns true if the passwords match.

=cut

sub verifyPassword {
  my $self = shift;
  my $password = shift;

  # Retrieve the contents of the table
  my $project = $self->_get_project_row();

  # Now verify the passwords
  return $self->_verify_password( $password, $project->password);

}

=item B<issuePassword>

Generate a new password for the current project and email it to
the Principal Investigator. The password in the project database
is updated.

  $db->issuePassword();

Note that there are no arguments and no return values. It either
succeeds or fails.

=cut

sub issuePassword {
  my $self = shift;

  # First thing to do is to retrieve the table row
  # for this project
  my $project = $self->_get_project_row;

  # We need to think carefully about transaction management
  # since we do not want to send out the email only for the
  # transaction to be backed out because of an error that occurred
  # just after the email was sent. The safest approach, I think,
  # is to send the email as the very last thing. If the email
  # fails to send the password will not be changed. We need to
  # finish the transaction immediately after sending the email.

  # Begin transaction
  $self->_db_begin_trans;
  $self->_dblock;

  # Generate a new plain text password
  my $newpassword = $self->_generate_password;

  # Store the encrypted password in the project object
  # and in the database
  $self->_store_password( $project, $newpassword );

  # Mail the password to the right people
  $self->_mail_password( $project );

  # End transaction
  $self->_dbunlock;
  $self->_db_commit_trans;

  return;
}


=back

=head2 Internal Methods

=over 4

=item B<_generate_password>

Generate a password suitable for use with a project.

  $password = $db->_generate_password;

=cut

sub _generate_password {
  my $self = shift;

  my ($password) = passgen( NLETT => 8, NWORDS => 1);

  print "Password: $password\n";

  return $password;

}

=item B<_store_password>

Store the password (provided in plain text) in the database table.

  $db->_store_password( $password );

The password is encrypted prior to storing it.

=cut

sub _store_password {
  my $self = shift;
  my $password = shift;

  my $encrypt = $self->_encrypt_password( $password );


}

=item B<_encrypt_password>

Given a plain text password, return the encrypted form.

  $encrypted = $db->_encrypt_password( $password );

=cut

# Yes, _encrypt_password and _generate_password could be
# placed in a OMP::Password class. I have not done this
# because they will only be used by this class and 
# OMP::ProjDB will still be the thing that updates the table.

sub _encrypt_password {
  my $self = shift;
  my $password = shift;

  # Generate the salt from a random set
  # See the crypt entry in perlfunc
  my $salt = join '', ('.', '/', 0..9, 'A'..'Z', 'a'..'z')[rand 64, rand 64];

  # Return it
  return crypt( $password, $salt );
}


=item B<_verify_password>

Given a plain text password and an encrypted password, verify that
the encrypted password was generated from the plain text version.

  $the_same = 1 if $db->_verify_password( $plain, $crypt );

=cut

sub _verify_password {
  my $self = shift;
  my $plain = shift;
  my $crypt = shift;

  # The encrypted password includes the salt as the first
  # two letters. Therefore we encrypt the plain text password
  # using the encrypted password as salt
  return ( crypt($plain, $crypt) eq $crypt );

}


=item B<_get_project_row>

Retrieve the contents of the project table relating to the current
project.

  %info  = $db->_get_project_row;

=cut

sub _get_project_row {
  my $self = shift;

  

}


=back

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research
Council.  All Rights Reserved.

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=cut

1;
