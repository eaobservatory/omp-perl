package OMP::SpServer;

=head1 NAME

OMP::SpServer - Science Program Server class

=head1 SYNOPSIS

  $xml = OMP::SpServer->fetchProgram($project, $password);
  $summary = OMP::SpServer->storeProgram($xml, $password);

=head1 DESCRIPTION

This class provides the public server interface for the OMP Science
Program database server. The interface is specified in document
OMP/SN/002.

This class is intended for use as a stateless server. State is
maintained in external databases. All methods are class methods.

=cut

use strict;
use warnings;
use Carp;

# OMP dependencies
use OMP::SciProg;
use OMP::MSBDB;
use OMP::Error qw/ :try /;

# Inherit server specific class
use base qw/OMP::SOAPServer OMP::DBServer/;

our $VERSION = (qw$Revision$)[1];

=head1 METHODS

=over 4

=item B<storeProgram>

Store an OMP Science Program (as XML) in the database. The password
must match that associated with the project specified in the science
program.

  $summary = OMP::SpServer->storeProgram($sciprog, $password);

Returns a summary of the science program (in plain text)
that can be used to provide feedback to the user.

There may need to be a force flag to force a store even though the
science program has been modified by a previous session.

=cut

sub storeProgram {
  my $class = shift;

  my $xml = shift;
  my $password = shift;

  my $string;
  my $E;
  try {
    # Create a science program object
    my $sp = new OMP::SciProg( XML => $xml );

    # Create a new DB object
    my $db = new OMP::MSBDB( Password => $password,
			     ProjectID => $sp->projectID,
			     DB => $class->dbConnection,
			   );

    # Store the science program
    $db->storeSciProg( SciProg => $sp );

    # Create a summary of the science program
    $string = join("\n",$sp->summary) . "\n";
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

  return $string;
}

=item B<fetchProgram>

Retrieve a science program from the database.

  $xml = OMP::SpServer->fetchProgram( $project, $password );

The return argument is an XML representation of the science
program.

=cut

sub fetchProgram {
  my $class = shift;
  my $projectid = shift;
  my $password = shift;

  my $sp;
  my $E;
  try {

    # Create new DB object
    my $db = new OMP::MSBDB( Password => $password,
			     ProjectID => $projectid,
			     DB => $class->dbConnection, );

    # Retrieve the Science Program object
    $sp = $db->fetchSciProg;

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

  # Return the stringified form
  return "$sp";
}

=back

=head1 SEE ALSO

OMP document OMP/SN/002.

=head1 COPYRIGHT

Copyright (C) 2001 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=cut

1;
