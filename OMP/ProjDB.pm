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

If the password is not supplied it is assumed to have been provided
using the object constructor.

  $verified = 1 if $db->verifyPassword( );

Returns true if the passwords match.

=cut

sub verifyPassword {
  my $self = shift;

  my $password;
  if (@_) {
    $password = shift;
  } else {
    $password = $self->password;
  }

  # Retrieve the contents of the table
  my $project = $self->_get_project_row();

  # Now verify the passwords
  return $project->verify_password( $password );

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

  # Store this password in the project object
  # This will automatically encrypt it
  $project->password( $newpassword );

  # Store the encrypted password in the database
  $self->_store_password( $project );

  # Mail the password to the right people
  $self->_mail_password( $project );

  # End transaction
  $self->_dbunlock;
  $self->_db_commit_trans;

  return;
}

=item B<projectSummary>

Retrieve a summary of the current project. This is returned in
XML format:

  $xml = $proj->projectSummary;

The XML is in the format described in C<OMP::Project>. In a list
context returns a hash containing the project details.

=cut

sub projectSummary {
  my $self = shift;

  # First thing to do is to retrieve the table row
  # for this project
  my $project = $self->_get_project_row;

  if (wantarray) {
    return $project->summary;
  } else {
    return scalar( $project->summary );
  }
}

=item B<projectsSummary>

Retrieve a summary of all the projects or all the active projects.

=cut

sub projectsSummary {
  my $self = shift;

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

Store the encrypted password (retrieved from the project object) in
the database table.

  $db->_store_password( $project );

=cut

sub _store_password {
  my $self = shift;
  my $project = shift;

  my $encrypt = $project->encrypted;


}

=item B<_get_project_row>

Retrieve the C<OMP::Project> object constructed from the row
in the database table associated with the current object.

  $proj  = $db->_get_project_row;

=cut

sub _get_project_row {
  my $self = shift;

  # Database
  my $dbh = $self->_dbhandle;
  throw OMP::Error::DBError("Database handle not valid") unless defined $dbh;

  # Project
  my $projectid = $self->projectid;


  # Go and do the database thing
  my $statement = "SELECT * FROM $PROJTABLE WHERE projectid = $projectid ";
  my $ref = $dbh->selectall_arrayref( $statement, { Columns=>{} });

  throw OMP::Error::UnknownProject( "Unable to retrieve details for project $projectid" )
    unless @$ref;

  # Create the project object
  my $proj = new OMP::Project( %{$ref->[0]} );
  throw OMP::Error::FatalError( "Unable to instantiate OMP::Project object")
    unless defined $proj;

  return $proj;
}


=back

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research
Council.  All Rights Reserved.

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=cut

1;
