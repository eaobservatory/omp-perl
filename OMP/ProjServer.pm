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

=item B<summary>

Return a summary of the projects in the database table.
The contents of the summary depends on the arguments.

Can be used to return a summmary of a single project or
all the active/closed/semester projects.

=cut

sub summary {
  my $class = shift;
  my $projectid = shift;

  my $E;
  try {

    my $db = new OMP::ProjDB(
			     ProjectID => $projectid,
			     DB => $class->dbConnection,
			    );

    throw OMP::Error( "Not yet implemented");

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

  OMP::ProjServer->addProject($password, $projectid, $pi,
			     $piemail, $coi, $coiemail,
			     $title, $tagpriority, $country,
			     $semester, $proj_password, $allocated);

The first password is used to verify that you are allowed to
modify the project table. The second password is for the project itself.
Both should be supplied as plain text.

We may not want to have this as a public method on a SOAP Server!

=cut

sub addProject {
  my $class = shift;
  my $password = shift;
  my @project = @_;

  my $E;
  try {

    throw OMP::Error::BadArgs("Should be 11 elements in project array. Only found ".scalar(@project)) unless scalar(@project) == 11;

    my $db = new OMP::ProjDB(
			     Password => $password,
			     DB => $class->dbConnection,
			    );

    # Instantiate OMP::Project object
    my $proj = new OMP::Project(
				projectid => $project[0],
				pi => $project[1],
				piemail => $project[2],
				coi => $project[3],
				coiemail => $project[4],
				title => $project[5],
				tagpriority => $project[6],
				country => $project[7],
				semester => $project[8],
				password => $project[9],
				allocated => $project[10],
			       );

    $db->addProject( $proj );

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

=head1 SEE ALSO

OMP document OMP/SN/005.

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=cut

1;
