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
use OMP::SciProg;
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

There is no return value. Throws an C<OMP::Error::UnknownProject>
if the requested project is not in the system.

=cut

sub issuePassword {
  my $class = shift;
  my $projectid = shift;

  my $E;
  try {

    my $db = new OMP::ProjDB(
			     ProjectID => $project,
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
			     ProjectID => $project,
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


}


=back

=head1 SEE ALSO

OMP document OMP/SN/005.

=head1 COPYRIGHT

Copyright (C) 2001 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=cut

1;
