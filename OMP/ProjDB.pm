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
use OMP::ProjQuery;
use OMP::Constants qw/ :fb /;
use OMP::User;
use OMP::UserDB;
use OMP::NetTools;
use OMP::General;
use OMP::Password;
use OMP::Project::TimeAcct;
use OMP::SiteQuality;

use Crypt::PassGen qw/passgen/;

use Time::Seconds;

use base qw/ OMP::BaseDB /;

# This is picked up by OMP::MSBDB
our $PROJTABLE = "ompproj";
our $PROJUSERTABLE = "ompprojuser";
our $PROJQUEUETABLE = "ompprojqueue";

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

By default, a project is only added if it does not already exist
in the database (this is for safety reasons). An optional second
argument can control whether the project should always force
overwrite. If this is true the old project details will be removed.

  $db->addProject( $project, $force );

Throws an exception of type C<OMP::Error::ProjectExists> if the
project exists and force is not set to true.

The password stored in the object instance will be verified to
determine if the user is allowed to update project details (this is
effectively the administrator password and this is different from the
individual project passwords and to the password used to log in to
the database).

=cut

sub addProject {
  my $self = shift;
  my $project = shift;
  my $force = shift;

  # Verify that we can update the database
  OMP::Password->verify_administrator_password( $self->password );

  # Begin transaction
  $self->_db_begin_trans;
  $self->_dblock;

  # See if we have the project already if we are not forcing
  throw OMP::Error::ProjectExists("This project already exists in the database and you are not forcing overwrite")
    if !$force && $self->verifyProject;

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

Returns true if the passwords match.  Returns false if the project does
not exist.

=cut

sub verifyPassword {
  my $self = shift;

  my $password;
  if (@_) {
    $password = shift;
  } else {
    $password = $self->password;
  }

  # Obviate the need for a db query by checking staff password
  return 1 if OMP::Password->verify_staff_password( $password, 1 );

  # Retrieve the contents of the table
  my $verify;
  my $E;
  try {
    my $project = $self->_get_project_row();

    # Now verify the passwords
    $verify = $project->verify_password( $password );
  } catch OMP::Error::UnknownProject with {
    # Ignore
  } otherwise {
    $E = shift;
  };

  croak "An error has occurred: $E" if defined $E;
  return $verify;

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

=item B<getTelescope>

Simplified access to the telescope related to the specified
project. Does not require a password. Returns the telescope
name or undef if the project does not exist.

  $tel = $proj->getTelescope();

=cut

{
  # Cache project -> telescope mappings
  my %PROJTELESCOPE;

  sub getTelescope {
    my $self = shift;

    my $tel;
    # Try to get the value from our cache, otherwise go
    # to the database
    if (exists $PROJTELESCOPE{$self->projectid}) {
      $tel = $PROJTELESCOPE{$self->projectid};
    } else {
      # Use a try block since we know that _get_project_row raises
      # an exception
      try {
        my $p = $self->_get_project_row();
        $tel = uc($p->telescope);

        # Cache result
        $PROJTELESCOPE{$p->projectid} = $tel;
      } catch OMP::Error::UnknownProject with {
        $tel = undef;
      };
    }
    return $tel;
  }
}

=item B<verifyTelescope>

Determine whether the supplied telescope matches the telescope
associated with the project ID stored in the object. Returns
true if the telescopes match, false otherwise.

For "special" projects generated by the time accounting system,
a project that contains a matching telescope prefix (eg JCMTCAL)
matches without querying the database.

 $telmatches = $db->verifyTelescope( $tel );

Essentially a small wrapper around C<getTelescope>. Returns false
if the project does not exist.

=cut

sub verifyTelescope {
  my $self = shift;
  my $tel = uc(shift);

  my $projectid = $self->projectid;

  if ($projectid =~ /^$tel/) {
    # Project ID starts with the supplied telescope string
    return 1;
  } else {
    # -w protection
    my $projtel = $self->getTelescope;
    if (defined $projtel && $tel eq $projtel) {
      # Have a real telescope and it matches
      return 1;
    }
    return 0;
  }
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

=item B<disableProject>

Remove the project from future queries by setting the project
state to 0 (disabled).

  $db->disableProject();

Requires the staff password.

=cut

sub disableProject {
  my $self = shift;

  # Verify that we can update the database
  OMP::Password->verify_staff_password( $self->password );

  # First thing to do is to retrieve the table row
  # for this project
  my $project = $self->_get_project_row;

  # Transaction start
  $self->_db_begin_trans;
  $self->_dblock;

  # Modify the project
  $project->state( 0 );

  # Update the contents in the table
  $self->_update_project_row( $project );

  # Notify the feedback system
  my $projectid = $self->projectid;
  $self->_notify_feedback_system(
                                 subject => "[$projectid] Project disabled",
                                 text => "<html>project <b>$projectid</b> disabled",
                                 msgtype => OMP__FB_MSG_PROJECT_DISABLED,
                                );

  # Transaction end
  $self->_dbunlock;
  $self->_db_commit_trans;

}

=item B<enableProject>

Re-enable a project so that it will show up in from future queries by
setting the project state to 1 (enabled).

  $db->enableProject();

Requires the staff password.

=cut

sub enableProject {
  my $self = shift;

  # Verify that we can update the database
  OMP::Password->verify_staff_password( $self->password );

  # First thing to do is to retrieve the table row
  # for this project
  my $project = $self->_get_project_row;

  # Transaction start
  $self->_db_begin_trans;
  $self->_dblock;

  # Modify the project
  $project->state( 1 );

  # Update the contents in the table
  $self->_update_project_row( $project );

  # Notify the feedback system
  my $projectid = $self->projectid;
  $self->_notify_feedback_system(
                                 subject => "[$projectid] Project enabled",
                                 text => "<html>project <b>$projectid</b> enabled",
                                 msgtype => OMP__FB_MSG_PROJECT_ENABLED,
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

  # First thing to do is to retrieve the table row
  # for this project
  my $project = $self->_get_project_row;

  # Now that we have it we can verify the project password
  # We dont use verifyPassword since that would involve an
  # additional fetch from the database
  throw OMP::Error::Authentication("Incorrect password for project ".
                                  $self->projectid ."\n")
    unless $project->verify_password( $self->password );

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

=item B<projectDetailsNoAuth>

Retrieve a summary of the current project without performing password
verification. This is returned in either XML format, as a reference to
a hash, as an C<OMP::Project> object or as a hash and is specified
using the optional argument.

  $xml = $proj->projectDetails( 'xml' );
  $href = $proj->projectDetails( 'data' );
  $obj  = $proj->projectDetails( 'object' );
  %hash = $proj->projectDetails;

The XML is in the format described in C<OMP::Project>.

If the mode is not specified XML is returned in scalar context and
a hash (not a reference) is returned in list context.

=cut

sub projectDetailsNoAuth {
  my $self = shift;
  my $mode = lc(shift);

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

=item B<enqueueProject>

Given a C<OMP::Project> object, add it to the queue.

  $db->enqueueProject( $project );

=cut

sub enqueueProject {
  my $self = shift;
  my $proj = shift;

  # pick a random queue as primary if we do not have one
  my %queue = $proj->queue;
  my $primary = $proj->primaryqueue;
  $primary = (values %queue)[0] unless defined $primary;

  for my $c (keys %queue) {

    # The TAG priority is the queue value - the adjustment
    my $adj = $proj->tagadjustment( $c );
    my $prim = ($primary eq uc($c) ? 1 : 0);

    $self->_db_insert_data( $PROJQUEUETABLE,
                            $proj->projectid,
                            uc($c), ($queue{$c} - $adj),
                            $prim, $adj,
                          );
  }

  return;
}

=item B<listProjects>

Return all the projects for the given query.

  @projects = $db->listProjects( $query );

The query is specified as a C<OMP::ProjQuery> object.

Returned as a list of C<OMP::Project> objects.

=cut

sub listProjects {
  my $self = shift;

  # Silly to have nothing in here other than a method call
  return $self->_get_projects( @_ );

}


=item B<listSemesters>

Retrieve all the semesters associated with projects in the database.

  @sem = $projdb->listSemesters()

=cut

sub listSemesters {
  my $self = shift;

  # Kluge. We should not be doing SQL at this level
  # Note that current project table does not know which telescope
  # it belongs to!
  my $semref = $self->_db_retrieve_data_ashash( "SELECT DISTINCT semester FROM $PROJTABLE" );
  return sort map { $_->{semester} } @$semref

}

=item B<listTelescopes>

Retrieve all the telescopes associated with projects in the database.

  @tel = $projdb->listTelescopes()

=cut

sub listTelescopes {
  my $self = shift;

  # Kluge. We should not be doing SQL at this level
  # Note that current project table does not know which telescope
  # it belongs to!
  my $telref = $self->_db_retrieve_data_ashash( "SELECT DISTINCT telescope FROM $PROJTABLE" );
  return sort map { $_->{telescope} } @$telref

}


=item B<listSupport>

Retrieve all the support scientists (as a list of C<OMP::User> objects)
associated with projects in the specified semesters and for the specified
telescope.

  @support = $projdb->listSupport( telescope => $tel,
                                   semester => \@semesters );

Neither C<telescope> nor C<semesters> are mandatory keys.

CURRENTLY THE HASH ARGUMENTS ARE IGNORED. THIS METHOD IS FOR TESTING
ONLY.

=cut

sub listSupport {
  my $self = shift;
  my %args = @_;

  # User table
  my $utable = $OMP::UserDB::USERTABLE;

  # Kluge. We should not be doing SQL at this level
  # Note that current project table does not know which telescope
  # it belongs to!
  my $supref = $self->_db_retrieve_data_ashash( <<"USER_SQL" );
    SELECT DISTINCT S.userid, email, uname as 'name'
    FROM $PROJUSERTABLE S, $utable U
    WHERE S.userid = U.userid AND capacity = 'SUPPORT'
USER_SQL

  map { new OMP::User( %$_ ) } @$supref

}

=item B<listCountries>

Retrieve all the countries associated with projects in the specified
semesters and for the specified telescope.

  @countries = $projdb->listSupport( telescope => $tel,
                                     semester => \@semesters );

Neither C<telescope> nor C<semesters> are mandatory keys.

CURRENTLY THE HASH ARGUMENTS ARE IGNORED. THIS METHOD IS FOR TESTING
ONLY.

=cut

sub listCountries {
  my $self = shift;
  my %args = @_;

  # Kluge. We should not be doing SQL at this level
  # Note that current project table does not know which telescope
  # it belongs to!
  my $cref = $self->_db_retrieve_data_ashash( "SELECT DISTINCT country FROM $PROJQUEUETABLE" );
  return map { $_->{country} } @$cref;
}

=item B<getTotalAlloc>

Return the total TAG allocation for all projects in a given telescope and semester.

  $total = $projdb->getTotalAlloc( $telescope, $semester );

The first argument is a telescope name.  The second argument is a semester name.
Returned as a C<Time::Seconds> object.

=cut

sub getTotalAlloc {
  my $self = shift;
  my $telescope = shift;
  my $semester = shift;

  return Time::Seconds->new( $self->_get_total_alloc($telescope, $semester) );
}

=pod

=item B<updateContactability>

Given a hash reference of user id as keys and and contact-ability
(truth values) as values, updates user & contactabiliy in the database.
It will update only those records which are actually changed.

  $db->updateContactability({ 'USR1' => 1, 'USR2' => 0 });

=cut

sub updateContactability {

  my ( $self, $contact ) = @_;

  throw OMP::Error::FatalError( q/Need a hash of user ids as keys and /
                                . q/truth values to update a user's contactability./
                              )
    unless OMP::General->hashref_keys_size( $contact )
    and ! scalar grep { ! defined $_ } keys %{ $contact } ;

  # Begin transaction
  $self->_db_begin_trans;
  $self->_dblock;

  # Rely on _get_project_row() to validate a project; may throw exceptions.
  my $proj = $self->_get_project_row;

  my %contact = $self->_remove_unchanged_contactability( $proj, $contact );
  # No change in any user or contactability.
  return unless scalar %contact;

  my $id = $proj->projectid;
  for my $user ( keys %contact ) {

    $self->_db_update_data( $PROJUSERTABLE,
                            { 'contactable' => $contact{ $user } ? 1 : 0 },
                              "projectid = '$id' AND userid = '$user'"
                          ) ;
  }
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

  return $password;

}

=item B<_get_total_alloc>

Retrieve the total TAG allocation for all projects in a given semester not
in the E & C queue.

  $total = $projdb->_get_total_alloc( $telescope, $semester );

First argument is a telescope name, second is a semester name.

=cut

sub _get_total_alloc {
  my $self = shift;
  my $telescope = shift;
  my $semester = shift;

  throw OMP::Error::BadArgs("No telescope defined")
    unless (defined $telescope);

  throw OMP::Error::BadArgs("No semester defined")
    unless (defined $semester);

  $telescope = uc($telescope);
  $semester = uc($semester);

  # The SQL query
  my $sql = "SELECT sum(P.allocated)".
    " FROM $PROJTABLE P, $PROJQUEUETABLE Q".
      " WHERE P.projectid = Q.projectid".
        " AND semester = \"$semester\" AND telescope = \"$telescope\"".
          " AND country != \"EC\"";

  # Now run the query
  my $dbh = $self->_dbhandle;
  throw OMP::Error::DBError("Database handle not valid") unless defined $dbh;

  my $sth = $dbh->prepare( $sql )
    or throw OMP::Error::DBError("Error preparing sum allocated SQL statment");

  $sth->execute
    or throw OMP::Error::DBError("DB Error executing sum allocated SQL: $DBI::errstr");

  my $sum = ($sth->fetchrow_array)[0];
  return  ( defined $sum ? $sum : 0 );
}


=item B<_get_project_row>

Retrieve the C<OMP::Project> object constructed from the row
in the database table associated with the current object.

  $proj  = $db->_get_project_row;

=cut

# This could be done by calling _get_projects with an XML
# query of <projectid>$projectid</projectid>

sub _get_project_row {
  my $self = shift;

  # Project
  my $projectid = $self->projectid;
  throw OMP::Error::UnknownProject("No project supplied")
    unless $projectid;

  # check for the odd case of no word characters in the projectid
  # whilst string is still technically "true"
  # This triggers an unknown project error (since we know there is no
  # valid project of that name) but should probably be
  # trapped by the query builder
  throw OMP::Error::UnknownProject("Supplied project ($projectid) has no word characters")
    unless $projectid =~ /\w/;

  # Create the query
  my $xml = "<ProjQuery><projectid>$projectid</projectid></ProjQuery>";
  my $query = new OMP::ProjQuery( XML => $xml );

  my @projects = $self->_get_projects( $query );

  # Throw an exception if we got no results
  throw OMP::Error::UnknownProject( "Unable to retrieve details for project $projectid" )
    unless @projects;

  # Check that we only have one
  throw OMP::Error::FatalError( "More than one project retrieved when requesting project '$projectid'!")
    unless @projects == 1;

  return $projects[0];
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

    # Update the projectid stored in this DB instance
    $self->projectid( $proj->projectid );

    # First we delete the current contents
    $self->_delete_project_row();

    # Then we insert the new values
    $self->_insert_project_row( $proj );

  } else {

    throw OMP::Error::BadArgs("Argument to _update_project_row must be of type OMP::Project\n");

  }

}

=item B<_delete_project_row>

Delete the specified project from the database table.

  $db->_delete_project_row();

The project ID is picked up from the DB object.

=cut

sub _delete_project_row {
  my $self = shift;

  # Must clear out user link tables as well
  $self->_db_delete_project_data( $PROJTABLE, $PROJUSERTABLE, $PROJQUEUETABLE);

}

=item B<_insert_project_row>

Insert the project information into the database table.

  $db->_insert_project_row( $project );

where C<$project> is an object of type C<OMP::Project>.

=cut

sub _insert_project_row {
  my $self = shift;
  my $proj = shift;

  # Get some extra information
  my $pi = $proj->pi->userid;

  my ($taumin, $taumax)     = OMP::SiteQuality::to_db( 'TAU',
                                                       $proj->taurange );
  my ($seemin, $seemax)     = OMP::SiteQuality::to_db( 'SEEING',
                                                       $proj->seeingrange );
  my ($cloudmin, $cloudmax) = OMP::SiteQuality::to_db( 'CLOUD',
                                                       $proj->cloudrange );
  my ($skymin, $skymax)     = OMP::SiteQuality::to_db( 'SKY',
                                                       $proj->skyrange );

  # Insert the generic data into table
  $self->_db_insert_data( $PROJTABLE,
                          $proj->projectid, $pi,
                          $proj->title,
                          $proj->semester, $proj->encrypted,
                          $proj->allocated->seconds,
                          $proj->remaining->seconds, $proj->pending->seconds,
                          $proj->telescope,$taumin,$taumax,$seemin,$seemax,
                          int($cloudmax), $proj->state, int($cloudmin),
                          $skymin, $skymax,
                        );

  # Now insert the queue information
  $self->enqueueProject( $proj );

  # Now insert the user data
  # All users end up in the same table. Contact information for a particular
  # user is available via the contactable method in the OMP::Project.

  # Loop over all the users. Note that this is *not* the output from the
  # contacts method since that will only contain contactable people
  my %contactable = $proj->contactable;

  # Group all the user information
  my %roles = (PI => [$proj->pi],
               COI => [$proj->coi],
               SUPPORT => [$proj->support]
              );

  # Loop over all the different roles
  for my $role (keys %roles) {

    my $order = 1;
    for my $user (@{ $roles{$role} }) {
      $self->_insert_project_user( 'projectid' => $proj->projectid,
                                    'userid' => $user->userid,
                                    'role' => $role,
                                    'contactable' => $contactable{ $user->userid },
                                    'capacity_order' => $order++,
                                  );
    }
  }

}

=item B<_insert_project_user>

Given a hash with keys of projectid, userid, role, contactable, and order per
role per project, add a user to the OMP database table.

  $self->_insert_project_user( 'projectid' => $projectid,
                                'userid' => 'jdove',
                                'role' => 'COI',
                                'contactable' => undef,
                                'capacity_order' => 2
                              );

=cut

sub _insert_project_user {

  my ( $self, %attr ) = @_;

  # Note that we must convert undef to 0 here for the DB
  $attr{'contactable'} = $attr{'contactable'} ? 1 : 0;
  $self->_db_insert_data( $PROJUSERTABLE,
                          map { $attr{$_} }
                              qw( projectid userid role contactable
                                  capacity_order
                                )
                        );
  return;
}

=item B<_get_projects>

Retrieve list of projects that match the supplied query (supplied as a C<OMP::ProjQuery>
object).

  @projects = $db->_get_projects( $query );

Returned as an array of C<OMP::Project> objects.

=cut

sub _get_projects {
  my $self = shift;
  my $query = shift;

  my $sql = $query->sql( $PROJTABLE, $PROJQUEUETABLE, $PROJUSERTABLE );

  # Run the query
  my $ref = $self->_db_retrieve_data_ashash( $sql );

  # Get user and queue information; do a separate query for every
  # N projects, where N is the value of $MAX_ID
  my $MAX_ID = 100;
  my $utable = $OMP::UserDB::USERTABLE; #--- Proj user table ---#
  my $uproj_alias = 'P';
  my $userquery_sql = <<"USER_SQL";
  SELECT $uproj_alias.projectid, $uproj_alias.userid, $uproj_alias.capacity,
         $uproj_alias.contactable,
         U.uname, U.email
    FROM $PROJUSERTABLE $uproj_alias, $utable U
      WHERE $uproj_alias.userid = U.userid AND

USER_SQL

  my $queuequery_sql = "SELECT * FROM $PROJQUEUETABLE WHERE ";

  my %projroles;
  my %projcontactable;
  my %projqueue;
  my %projadj;
  my %projpri_queue;
  my $start_index = 0;
  while ($start_index <= $#$ref) {
    my $end_index = ( $start_index + $MAX_ID < $#$ref ?
                      $start_index + $MAX_ID : $#$ref);
    my $proj_list = join(",", map {"\"".$_->{projectid}."\""}
                         @$ref[$start_index..$end_index]
                        );

    # First do the user info query
    $sql = $userquery_sql . <<"WHERE_ORDER_SQL";
        projectid in ($proj_list)
        ORDER BY $uproj_alias.projectid,
                 $uproj_alias.capacity,
                 $uproj_alias.capacity_order
WHERE_ORDER_SQL

    my $userref = $self->_db_retrieve_data_ashash( $sql );

    # Loop over the results and assign to different roles
    for my $row (@$userref) {
      my $projectid = $row->{projectid};
      my $capacity = $row->{capacity};
      my $userid = $row->{userid};

      # Store the results for assignment to project objects later on
      $projroles{$projectid}->{$capacity} = []
        unless exists $projroles{$projectid}->{$capacity};

      push(@{ $projroles{$projectid}->{$capacity} },
           new OMP::User( userid => $userid,
                          name => $row->{uname},
                          email => $row->{email},
                        ));

      $projcontactable{$projectid}->{$userid} = $row->{contactable};
    }

    # Now do the queue info query
    $sql = $queuequery_sql . "projectid in ($proj_list)";
    my $queueref = $self->_db_retrieve_data_ashash( $sql );

    # Loop over results and store for later assignment to project objects
    for my $row (@$queueref) {
      my $projectid = $row->{projectid};
      $projadj{$projectid}{uc($row->{country})} =
         (defined $row->{tagadj} ? $row->{tagadj} : 0);
      # Queue stores TAG priority + TAG adjustments
      $projqueue{$projectid}{uc($row->{country})} = $row->{tagpriority}
         + $projadj{$projectid}{uc($row->{country})};

      $projpri_queue{$projectid} = uc($row->{country}) if $row->{isprimary};
    }

    $start_index = $end_index + 1;
  }

  # First create a UserDB object
  my $udb = new OMP::UserDB( DB => $self->db );

  # Loop over each project
  my @projects;
  for my $projhash (@$ref) {

    # Remove the user id from PI field
    my $piuserid = $projhash->{pi};
    delete $projhash->{pi};

    # cloud fix up for old usage
    if (exists $projhash->{cloud}) {
      my $crange = OMP::SiteQuality::upgrade_cloud( $projhash->{cloud} );
      $projhash->{cloudmin} = $crange->min;
      $projhash->{cloudmax} = $crange->max;
      delete $projhash->{cloud};
    }

    # convert min/max to ranges
    for my $key (qw/ tau seeing cloud sky / ) {

      # determine the min/max keys
      my $maxkey = $key . "max";
      my $minkey = $key . "min";

      # output key
      my $outkey = $key . "range";

      # convert the min and max into a OMP::Range object
      $projhash->{$outkey} = OMP::SiteQuality::from_db( $key,
                                                        $projhash->{$minkey},
                                                        $projhash->{$maxkey}
                                                      );

      # fix up any NULLs
      OMP::SiteQuality::undef_to_default( $key, $projhash->{$outkey});

      # convert to 2 decimal places because of precision problems
      # with a REAL sybase column
      for my $m (qw/ min max /) {
        my $val = $projhash->{$outkey}->$m();
        next unless defined $val;
        $val = sprintf( '%.2f', $val);
        $projhash->{$outkey}->$m( $val );
      }

      delete $projhash->{$minkey};
      delete $projhash->{$maxkey};
    }

    # Create a new OMP::Project object
    my $proj = new OMP::Project( %$projhash );
    next unless $proj;

    # Project ID
    my $projectid = $proj->projectid;

    # -------- Assign User information ---------
    # This is a kluge for now since we have the PI in two places in the
    # database for historical reasons: once in the ompproj table and once
    # in ompprojuser.
    $proj->pi($projroles{$projectid}{PI}->[0]);

    # Now add other users to the project
    $proj->coi( @{ $projroles{$projectid}{COI} } )
      if exists $projroles{$projectid}{COI};
    $proj->support( @{ $projroles{$projectid}{SUPPORT} } )
      if exists $projroles{$projectid}{SUPPORT};
    $proj->contactable( %{$projcontactable{$projectid}} );

    # -------- Assign Queue information ---------
    # Store new info, but make sure we have cleared the hash first
    $proj->clearqueue;
    $proj->queue($projqueue{$projectid});
    $proj->primaryqueue($projpri_queue{$projectid});
    $proj->tagadjustment( $projadj{$projectid} );

    # And store it
    push(@projects, $proj);
  }

  # Return the results as Project objects
  return @projects;
}

=item B<_get_max_role_order>

Given a project id and a role, returns the maximum capacity order
(integer) assigned for the role.  If nothing is found, 0 is returned.

  my $max_order = $db->_get_max_role_order( $projectid, $role );

=cut

sub _get_max_role_order {

  my ( $self, $projid, $role ) = @_;

  throw OMP::Error::BadArgs('Need both a project id and a role')
    unless $projid && $role;

  my $column = 'max_order';
  my $sql =
    qq[ SELECT MAX( capacity_order ) $column
        FROM $PROJUSERTABLE
        WHERE projectid = '$projid' AND capacity = '$role'
      ];

  my $order = $self->_db_retrieve_data_ashash( $sql );

  return $order->[0]{ $column } || 0;
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
    my ($user, $ip, $addr) = OMP::NetTools->determine_host;

    # List of recipients of mail
    my @addr = $proj->contacts;

    throw OMP::Error::BadArgs("No email address defined for sending password\n") unless @addr;


    # First thing to do is to register this action with
    # the feedback system
    my $fbmsg = "<html>New password issued for project <b>$projectid</b> at the request of $addr and mailed to: ".
      join(",", map {$_->html} @addr)."\n";

    # Disable transactions since we can only have a single
    # transaction at any given time with a single handle
    $self->_notify_feedback_system(
                                   subject => "Password change for $projectid",
                                   text => $fbmsg,
                                   status => OMP__FB_INFO,
                                   msgtype => OMP__FB_MSG_PASSWD_ISSUED,
                                   );

    # Now set up the mail

    # Mail message content
    my $msg = "\nNew password for project $projectid: $password\n\n" .
      "This password was generated automatically at the request\nof $addr.\n".
        "\nPlease do not reply to this email message directly.\n";

    $self->_mail_information(
                             message => $msg,
                             to => \@addr,
                             from => OMP::User->new(name => "omp-auto-reply"),
                             subject => "[$projectid] OMP reissue of password for $projectid",
                             headers => {"Reply-To" => 'flex@jach.hawaii.edu',
                                        },
                            );
  } else {

    throw OMP::Error::BadArgs("Argument to _mail_password must be of type OMP::Project\n");


  }

}

=pod

=item B<_remove_unchanged_contactability>

Given an C<OMP::Project> object and a hash reference of (possibly)
updated user-contactable key-value pairs, returns a new hash reference
of the remaining changed, possibly none, pairs.

  $changed =
    $db->_remove_unchanged_contactability( $project,
                                          { 'USR1' => 1, 'USR2' => 0 }
                                        );

=cut

sub _remove_unchanged_contactability {

  my ( $self, $proj, $updates ) = @_;

  my %old_contact = $proj->contactable;
  my %changed;
  for my $user ( keys %{ $updates } ) {

    my $contactable = $updates->{ $user };

    next if exists $old_contact{ $user }
          && ( ( $contactable && $old_contact{ $user } )
              || ( ! $contactable && ! $old_contact{ $user } )
              ) ;

    $changed{ $user } = $contactable;
  }

  return %changed;
}

=back

=head1 SEE ALSO

This class inherits from C<OMP::BaseDB>.

For related classes see C<OMP::MSBDB> and C<OMP::FeedbackDB>.

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
along with this program; if not, write to the
Free Software Foundation, Inc., 59 Temple Place, Suite 330,
Boston, MA  02111-1307  USA


=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=cut

1;
