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

=item B<addProject>

Add a new project to the database or replace an existing entry in the
database.

  $db->addProject( $project );

The argument is of class C<OMP::Project>.

No distinction is made between adding a new project or updating a
current project. i.e. This method does not raise an error if the
project is already in the table.

The password stored in the object instance will be verified to
determine if the user is allowed to update project details (this is
effectively the administrator password and this is different from the
individual project passwords and to the password used to log in to
the database).

=cut

sub addProject {
  my $self = shift;
  my $project = shift;

  # Verify that we can update the database
  $self->_verify_administrator_password;

  # Begin transaction
  $self->_db_begin_trans;
  $self->_dblock;

  # Rely on the update method to check the argument
  $self->_update_project_row( $project );

  # End transaction
  $self->_dbunlock;
  $self->_db_commit_trans;

}

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
  $self->_update_project_row( $project );

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


=item B<_update_project_row>

Update the row relating to the supplied project, making sure that a
previous entry is deleted.

  $db->_update_project_row( $proj );

where the argument is an object of type C<OMP::Project>

We DELETE and then INSERT rather than using UPDATE because this way we
simply push the complete set of project information into the table at
once and rely on C<OMP::Project> to handle all the dependencies
without this class having to know which information was changed. If
this is deemed to be inefficient we will simply modify this method so
that the argument can be a hash reference containing the names of the
columns that have been modified and the new values and then do a real
database UPDATE (ie if the argument is of type OMP::Project delete and
insert, if it is just a hash reference do an update on the supplied
keys).

=cut

sub _update_project_row {
  my $self = shift;
  my $proj = shift;

  if (UNIVERSAL::isa( $proj, "OMP::Project")) {

    # First we delete the current contents
    $self->_delete_project_row( $proj->projectid );

    # Then we insert the new values
    $self->_insert_project_row( $proj );

  } else {

    throw OMP::Error::BadArgs("Argument to _update_project_row must be of type OMP::Project\n"); 

  }

}

=item B<_delete_project_row>

Delete the specified project from the database table.

  $db->_delete_project_row( $project_string );

=cut

sub _delete_project_row {
  my $self = shift;
  my $projectid = shift;

  my $dbh = $self->_dbhandle;
  throw OMP::Error::DBError("Database handle not valid") unless defined $dbh;


  $dbh->do("DELETE FROM $PROJTABLE WHERE projectid = '$projectid'")
    or throw OMP::Error::SpStoreFail("Error removing project $projectid: ".$dbh->errstr);

}

=item B<_insert_project_row>

Insert the project information into the database table.

  $db->_insert_project_row( $project );

where C<$project> is an object of type C<OMP::Project>.

=cut

sub _insert_project_row {
  my $self = shift;
  my $proj = shift;

  print "Inserting\n";

  my $dbh = $self->_dbhandle;
  throw OMP::Error::DBError("Database handle not valid") unless defined $dbh;

  # Insert the contents into the table. The project ID is the
  # unique ID for the row.
  use Data::Dumper;
  print Dumper( $proj );

  $dbh->do("INSERT INTO $PROJTABLE VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)", undef,
	   $proj->projectid, $proj->pi, $proj->piemail, scalar($proj->coi),
	   scalar($proj->coiemail), $proj->title, $proj->tagpriority, 
	   $proj->country,
	   $proj->semester, $proj->encrypted,
	   $proj->allocated, $proj->remaining, $proj->pending
	  ) or throw OMP::Error::SpStoreFail("Error inserting project:".
					     $dbh->errstr ."\n");

}

=item B<_verify_administrator_password>

Compare the password stored in the object (obtainiable using the
C<password> method) with the administrator password. Throw an
exception if the two do not match. This safeguard is used to prevent
people from modifying the contents of the project database without
having permission.

=cut

sub _verify_administrator_password {
  my $self = shift;
  my $password = $self->password;

  # A bit simplistic at the present time
  throw OMP::Error::Authentication("Failed to match administrator password\n")
    unless ($password eq "***REMOVED***");

  return;
}

=back

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research
Council.  All Rights Reserved.

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=cut

1;
