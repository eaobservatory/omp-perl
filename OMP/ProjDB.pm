package OMP::ProjDB;

=head1 NAME

OMP::ProjDB - Manipulate the project database

=head1 SYNOPSIS

  $projdb = new OMP::ProjDB( ProjectID => $projectid,
			     DB => $dbconnection );

  $projdb->issuePassword();

  $projdb->verifyPassword( $password );
  $projdb->verifyProject();

=head1 DESCRIPTION

This class manipulates information in the project database.  It is the
only interface to the database tables. The tables should not be
accessed directly to avoid loss of data integrity.


=cut

use 5.006;
use strict;
use warnings;
use Carp;
our $VERSION = (qw$ Revision: 1.2 $ )[1];

use OMP::Error qw/ :try /;
use OMP::Project;
use OMP::FeedbackDB;
use OMP::Constants qw/ :fb /;

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

Inherits from C<OMP::BaseDB>.

=cut

# Use base class constructor

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
  OMP::General->verify_administrator_password( $self->password );

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

=item B<verifyProject>

Verify that the current project is valid (i.e. it has active entries
in the database tables).

  $exists = $db->verifyProject();

Returns true if the project exists or false if it does not.

=cut

sub verifyProject {
  my $self = shift;

  # Use a try block since we know that _get_project_row raises
  # an exception
  my $there;
  try {
    $self->_get_project_row();
    $there = 1;
  } catch OMP::Error::UnknownProject with {
    $there = 0;
  };

  return $there
}

=item B<issuePassword>

Generate a new password for the current project and email it to
the Principal Investigator. The password in the project database
is updated.

  $db->issuePassword( $addr );

The argument can be used to specify the internet address (and if known
the uesr name in email address format) of the remote system requesting
the password. Designed specifically for use by CGI scripts. If the
value is not defined it will be assumed that we are running this
routine from the host computer (using the REMOTE_ADDR environment
variable if it is set).

Note that there are no return values. It either succeeds or fails.

=cut

sub issuePassword {
  my $self = shift;
  my $ip = shift;

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
  $self->_mail_password( $project, $ip );

  # End transaction
  $self->_dbunlock;
  $self->_db_commit_trans;

  return;
}

=item B<decrementTimeRemaining>

Provisionally decrement the time remaining for the project. 
This simply adds the supplied value to the pending column in the
table. The confirm this value use C<confirmTimeRemaining>

  $db->decrementTimeRemaining( $time );

Units are in seconds.

The optional second argument can be used to disable the transaction
handling (if we are already in one).

=cut

sub decrementTimeRemaining {
  my $self = shift;
  my $time = shift;
  my $notrans = shift;

  throw OMP::Error::BadArgs("Time must be supplied and must be positive")
    unless defined $time and $time > 0;

  # First thing to do is to retrieve the table row
  # for this project
  my $project = $self->_get_project_row;

  # Transaction start
  unless ($notrans) {
    $self->_db_begin_trans;
    $self->_dblock;
  }

  # Modify the project
  $project->incPending( $time );

  # Update the contents in the table
  $self->_update_project_row( $project );

  # Notify the feedback system
  my $projectid = $self->projectid;
  $self->_notify_feedback_system(
				 subject => "Decrement time remaining",
				 text => "$time seconds has been provisionally decremented from project <b>$projectid</b>",
				 status => OMP__FB_INFO,
				);

  # Transaction end
  unless ($notrans) {
    $self->_dbunlock;
    $self->_db_commit_trans;
  }

}

=item B<confirmTimeRemaining>

Confirm that the time remaining in the project is correct. This
is achieved by transferring any pending values to the remaining
column.

  $db->confirmTimeRemaining;

=cut

sub confirmTimeRemaining {
  my $self = shift;

  # First thing to do is to retrieve the table row
  # for this project
  my $project = $self->_get_project_row;

  # Transaction start
  $self->_db_begin_trans;
  $self->_dblock;

  # Modify the project
  $project->consolidateTimeRemaining();

  # Update the contents in the table
  $self->_update_project_row( $project );

  # Notify the feedback system
  my $projectid = $self->projectid;
  $self->_notify_feedback_system(
				 subject => "Consolidate time remaining",
				 text => "Pending time has been subtracted from the time remaining for project <b>$projectid</b>",
				 status => OMP__FB_IMPORTANT,
				);

  # Transaction end
  $self->_dbunlock;
  $self->_db_commit_trans;

}

=item B<rescindTimePending}>

Back out of any observing time specified as pending. This will
set the value of pending in the table to 0.

  $db->rescindTimePending;

=cut

sub rescindTimePending {
  my $self = shift;

  # First thing to do is to retrieve the table row
  # for this project
  my $project = $self->_get_project_row;

  # Transaction start
  $self->_db_begin_trans;
  $self->_dblock;

  # Modify the project to reset pending to zero
  $project->pending( 0 );

  # Update the contents in the table
  $self->_update_project_row( $project );

  # Notify the feedback system
  my $projectid = $self->projectid;
  $self->_notify_feedback_system(
				 subject => "Reset pending time",
				 text => "Pending time has been reset without decrementing time remaining for project <b>$projectid</b>",
				);

  # Transaction end
  $self->_dbunlock;
  $self->_db_commit_trans;

}


=item B<projectDetails>

Retrieve a summary of the current project. This is returned in either
XML format, as a reference to a hash, as an C<OMP::Project> object or
as a hash and is specified using the optional argument.

  $xml = $proj->projectDetails( 'xml' );
  $href = $proj->projectDetails( 'data' );
  $obj  = $proj->projectDetails( 'object' );
  %hash = $proj->projectDetails;

The XML is in the format described in C<OMP::Project>.

If the mode is not specified XML is returned in scalar context and
a hash (not a reference) is returned in list context.

Password verification is performed.

=cut

sub projectDetails {
  my $self = shift;
  my $mode = lc(shift);

  throw OMP::Error::Authentication("Incorrect password for project ".
				  $self->projectid ."\n")
    unless $self->verifyPassword;

  # First thing to do is to retrieve the table row
  # for this project
  my $project = $self->_get_project_row;

  if (wantarray) {
    $mode ||= "xml";
  } else {
    # An internal mode
    $mode ||= "hash";
  }

  if ($mode eq 'xml') {
    my $xml = $project->summary;
    return $xml;
  } elsif ($mode eq 'object') {
    return $project;
  } elsif ($mode eq 'data') {
    my %hash = $project->summary;
    return \%hash;
  } elsif ($mode eq 'hash') {
    my %hash = $project->summary;
    return \%hash;
  } else {
    throw OMP::Error::BadArgs("Unrecognized summary option: $mode\n");
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
  my $statement = "SELECT * FROM $PROJTABLE WHERE projectid = '$projectid' ";
  my $ref = $dbh->selectall_arrayref( $statement, { Columns=>{} })
    or throw OMP::Error::DBError("Error retrieving project $projectid:".
				$dbh->errstr);

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

  my $dbh = $self->_dbhandle;
  throw OMP::Error::DBError("Database handle not valid") unless defined $dbh;

  # Insert the contents into the table. The project ID is the
  # unique ID for the row.
  $dbh->do("INSERT INTO $PROJTABLE VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
	   undef,
	   $proj->projectid, $proj->pi, $proj->piemail,
	   scalar($proj->coi), scalar($proj->coiemail),
	   scalar($proj->support), scalar($proj->supportemail),
	   $proj->title, $proj->tagpriority,
	   $proj->country, $proj->semester, $proj->encrypted,
	   $proj->allocated, $proj->remaining, $proj->pending
	  ) or throw OMP::Error::SpStoreFail("Error inserting project:".
					     $dbh->errstr ."\n");

}

=item B<_mail_password>

Mail the password associated with the supplied project to the
principal investigator of the project.

  $db->_mail_password( $project, $addr );

The first argument should be of type C<OMP::Project>. The second
(optional) argument can be used to specify the internet address of the
computer (and if available the user) requesting the password.  If it
is not supplied the routine will assume the current user and host, or
use the REMOTE_ADDR and REMOTE_USER environment variables if they are
set (they are usually only set when running in a web environment).

=cut

sub _mail_password {
  my $self = shift;
  my $proj = shift;

  if (UNIVERSAL::isa( $proj, "OMP::Project")) {

    # Get projectid
    my $projectid = $proj->projectid;

    throw OMP::Error::BadArgs("Unable to obtain project id to mail\n")
      unless defined $projectid;

    # Get the plain text password
    my $password = $proj->password;

    throw OMP::Error::BadArgs("Unable to obtain plain text password to mail\n")
      unless defined $password;

    # Try and work out who is making the request
    my ($user, $ip, $addr) = OMP::General->determine_host;

    # List of recipients of mail
    my @addr = $proj->investigators;

    throw OMP::Error::BadArgs("No email address defined for sending password\n") unless @addr;


    # First thing to do is to register this action with
    # the feedback system
    my $fbmsg = "New password issued for project <b>$projectid</b> at the request of $addr and mailed to: ".
      join(",", map {"<a href=\"mailto:$_\">$_</a>"} @addr)."\n";

    # Disable transactions since we can only have a single
    # transaction at any given time with a single handle
    $self->_notify_feedback_system(
				   subject => "Password change for $projectid",
				   text => $fbmsg,
				   status => OMP__FB_INFO,
				   );

    # Now set up the mail

    # Mail message content
    my $msg = "\nNew password for project $projectid: $password\n\n" .
      "This password was generated automatically at the request\nof $addr.\n".
	  "\nPlease do not reply to this email message directly.\n";

    $self->_mail_information(
			     message => $msg,
			     to => \@addr,
			     from => "omp-auto-reply",
			     subject => "OMP reissue of password for $projectid",
			     headers => ["Reply-To: omp_group\@jach.hawaii.edu" ],
			    );


  } else {

    throw OMP::Error::BadArgs("Argument to _mail_password must be of type OMP::Project\n");


  }

}


=back

=head1 SEE ALSO

This class inherits from C<OMP::BaseDB>.

For related classes see C<OMP::MSBDB> and C<OMP::FeedbackDB>.

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research
Council.  All Rights Reserved.

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=cut

1;
