package OMP::ProjServer;

=head1 NAME

OMP::ProjServer - Project information Server class

=head1 SYNOPSIS

  OMP::ProjServer->issuePassword( $projectid );
  $xmlsummary = OMP::ProjServer->summary( "open" );

=head1 DESCRIPTION

This class provides the public server interface for the OMP Project
information database server. The interface is specified in document
OMP/SN/005.

This class is intended for use as a stateless server. State is
maintained in external databases. All methods are class methods.

=cut

use strict;
use warnings;
use Carp;

# OMP dependencies
use OMP::ProjDB;
use OMP::Project;
use OMP::Error qw/ :try /;

# Inherit server specific class
use base qw/OMP::SOAPServer OMP::DBServer/;

our $VERSION = (qw$Revision$)[1];

=head1 METHODS

=over 4

=item B<issuePassword>

Generate a new password for the specified project and mail the
resulting plain text password to the PI (or the person
designated to recieve it in the project database).

  OMP::ProjServer->issuePassword( $projectid );

There is no return value. Throws an C<OMP::Error::UnknownProject>
if the requested project is not in the system.

=cut

sub issuePassword {
  my $class = shift;
  my $projectid = shift;

  OMP::General->log_message("issuePassword: $projectid\n");

  my $E;
  try {

    my $db = new OMP::ProjDB(
			     ProjectID => $projectid,
			     DB => $class->dbConnection,
			    );

    $db->issuePassword();

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

=item B<listProjects>

Return all the projects in the database table
that match supplied criteria.

  $projects = OMP::ProjServer->listProjects( $xmlquery,
                                             $format);

The database query must be supplied in XML form. See C<OMP::ProjQuery>
for more details on the format of an XML query. A typical query could
be:

 <ProjQuery>
  <status>active</status>
  <semester>SERV</semester>
 </ProjQuery>

The format of the returned data is controlled by the last argument.
This can either be "object" (a reference to an array containing
C<OMP::Project> objects), "hash" (reference to an array of hashes), or
"xml" (return data as XML document). The format of the XML is the same
as for C<projectDetails> except that a wrapper element of
C<E<lt>OMPProjectsE<gt>> surrounds the core data.

=cut

sub listProjects {
  my $class = shift;
  my $xmlquery = shift;
  my $mode = lc( shift );
  $mode = "xml" unless $mode;

  OMP::General->log_message("ProjServer::listProjects: \n".
			    "Query: $xmlquery\n" .
			    "Output format: $mode\n");


  my @projects;
  my $E;
  try {

    # Triggers an exception on fatal errors
    my $query = new OMP::ProjQuery( XML => $xmlquery,
                                 );

    my $db = new OMP::ProjDB(
			     DB => $class->dbConnection,
			    );

    @projects = $db->listProjects( $query );

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

  if ($mode eq "xml") {
    return "<OMPProjects>\n" . join("\n", map { scalar($_->summary) } @projects)
      . "\n</OMPProjects>\n";
  } elsif ($mode eq "hash") {
    return [ map { {$_->summary} } @projects  ];
  } else {
    return \@projects;
  }

}

=item B<projectDetails>

Return the details of a single project. The summary is returned as a
data structure (a reference to a hash), as an C<OMP::Project> object
or as XML.

  $href = OMP::ProjServer->projectDetails( $project, $password, "data" );
  $xml = OMP::ProjServer->projectDetails( $project,$password, "xml" );
  $obj = OMP::ProjServer->projectDetails( $project,$password, "object" );

Note that this may cause problems for a strongly typed language.

The default is to return XML since that is a simple string.

=cut

sub projectDetails {
  my $class = shift;
  my $projectid = shift;
  my $password = shift;
  my $mode = lc(shift);
  $mode ||= 'xml';

  OMP::General->log_message("ProjServer::projectDetails: $projectid\n");

  my $E;
  my $summary;
  try {

    my $db = new OMP::ProjDB(
			     ProjectID => $projectid,
			     DB => $class->dbConnection,
			     Password => $password,
			    );

    $summary = $db->projectDetails( $mode );

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

  return $summary;
}

=item B<verifyProject>

Verify that the specified project is active and present in the
database.

  $result = OMP::ProjServer->verifyProject( $projectid );

Returns true or false.

=cut

sub verifyProject {
  my $class = shift;

  my $projectid = shift;
  OMP::General->log_message("ProjServer::verifyProject: $projectid\n");

  my $there;
  my $E;
  try {

    my $db = new OMP::ProjDB(
			     ProjectID => $projectid,
			     DB => $class->dbConnection,
			    );

    $there = $db->verifyProject();

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

  return $there;

}

=item B<addProject>

Add details of a project to the database.

  OMP::ProjServer->addProject($password, $force, $projectid, $pi,
			      $coi, $support,
			     $title, $tagpriority, $country,
			     $semester, $proj_password, $allocated
                             $telescope, $taumin, $taumax);

The first password is used to verify that you are allowed to modify
the project table. The second password is for the project itself.
Both should be supplied as plain text. The second argument indicates
whether it is desirable to overwrite an existing project. An exception
will be thrown if this value is false and the project in question
already exists.

taumin and taumax are optional (assume minimum of zero and
no upper limit).

We may not want to have this as a public method on a SOAP Server!

People are supplied as OMP User IDs. CoI and Support can be colon or comma
separated.

=cut

sub addProject {
  my $class = shift;
  my $password = shift;
  my $force = shift;
  my @project = @_;
  OMP::General->log_message("ProjServer::addProject: $project[0]\n");

  my $E;
  try {

    throw OMP::Error::BadArgs("Should be at least 11 elements in project array. Found ".scalar(@project)) unless scalar(@project) >= 11;

    my $userdb = new OMP::UserDB( DB => $class->dbConnection );

    # Split CoI and Support on colon
    my @coi;
    if ($project[2]) {
      @coi = map { $userdb->getUser($_) 
		     or throw OMP::Error::FatalError("User ID $_ not recognized by OMP system [project=$project[0]]")}
        split /[:,]/, $project[2];
    }
    my @support;
    if ($project[3]) {
      @support = map { $userdb->getUser($_) or throw OMP::Error::FatalError("User ID $_ not recognized by OMP system [project=$project[0]]") } split /[:,]/, $project[3];
    }

    # Create range object for tau (defaulting to lower bound of zero
    $project[11] = 0 unless defined $project[11];
    my $taurange = new OMP::Range(Min => $project[11], Max => $project[12]);

    # Instantiate OMP::Project object
    my $proj = new OMP::Project(
				projectid => $project[0],
    				pi => $userdb->getUser($project[1]),
				coi => \@coi,
				support => \@support,
				title => $project[4],
				tagpriority => $project[5],
				country => $project[6],
				semester => $project[7],
				password => $project[8],
				allocated => $project[9],
				telescope => $project[10],
				taurange => $taurange,
			       );

    my $db = new OMP::ProjDB(
			     Password => $password,
			     DB => $class->dbConnection,
			     ProjectID => $proj->projectid,
			    );

    $db->addProject( $proj, $force );

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

=item B<verifyPassword>

Verify the project ID and password combination. Returns true (1) if
the password is valid and false (0) otherwise.

  $status = OMP::ProjServer->verifyPassword($projectid, $password);

Password is plain text. Project ID is case insensitive.

=cut

sub verifyPassword {
  my $class = shift;
  my $projectid = shift;
  my $password = shift;
  OMP::General->log_message("ProjServer::verifyPassword: $projectid\n");

  my $ok;
  my $E;
  try {

    my $db = new OMP::ProjDB(
			     ProjectID => $projectid,
			     DB => $class->dbConnection,
			     Password => $password,
			    );

    $ok = $db->verifyPassword();

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

  return ($ok ? 1 : 0);

}

=item B<getTelescope>

Obtain the telescope associated with the specified project.

  $tel = OMP::ProjServer->getTelescope( $project );

Returns null if the project does not exist.

=cut

sub getTelescope {
  my $class = shift;
  my $projectid = shift;

  my $tel;
  my $E;
  try {

    my $db = new OMP::ProjDB(
			     ProjectID => $projectid,
			     DB => $class->dbConnection,
			    );

    $tel = $db->getTelescope();

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

  return $tel;

}

=item B<verifyTelescope>

Given a telescope and a project ID, returns true if the telescope
associated with the project matches the supplied telescope, else
returns false. Also returns true if the project ID begins with a
telescope prefix that matches - this removes the need for a database
query.

  $isthistel = OMP::ProjServer->verifyTelescope( $projectid, $tel );

=cut

sub verifyTelescope {
  my $class = shift;
  my $projectid = shift;
  my $tel = shift;

  my $ismatch;
  my $E;
  try {

    my $db = new OMP::ProjDB(
			     ProjectID => $projectid,
			     DB => $class->dbConnection,
			    );

    $ismatch = $db->verifyTelescope($tel);

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

  return $ismatch;
}

=back

=head1 SEE ALSO

OMP document OMP/SN/005.

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=cut

1;
