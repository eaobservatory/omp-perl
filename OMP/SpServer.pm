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

  [$summary, $timestamp] = OMP::SpServer->storeProgram($sciprog, $password);

Returns an array containing the summary of the science program (in
plain text) that can be used to provide feedback to the user as well
as the timestamp attached to the file in the database (for consistency
checking).

There may need to be a force flag to force a store even though the
science program has been modified by a previous session.

=cut

sub storeProgram {
  my $class = shift;

  my $xml = shift;
  my $password = shift;

  my ($string, $timestamp);
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

    # Retrieve the timestamp
    $timestamp = $sp->timestamp;

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

  return [$string, $timestamp];
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

=item B<programDetails>

Return a detailed summary of the science program. The summary is
returned as either pre-formatted text or as a data structure (array of
hashes for each MSB with each hash containing an array of hashes for
each observation).

  $text = OMP::SpServer->programDetails( $project, 'ascii' );
  $array = OMP::SpServer->programDetails( $project, 'data' );

Note that this may cause problems for a strongly typed language.

No password is required. This may change in the future.

=cut

sub programDetails {
  my $class = shift;
  my $projectid = shift;
  my $mode = lc(shift);
  $mode ||= 'ascii';

  my $E;
  my $summary;
  try {

    # Create new DB object
    my $db = new OMP::MSBDB( 
			     ProjectID => $projectid,
			     DB => $class->dbConnection, );

    # Retrieve the Science Program object
    my $sp = $db->fetchSciProg;

    # Create a summary of the science program
    $summary = $sp->summary($mode);

    # Clean the data structure if we are in 'data'
    if ($mode eq 'data') {
      for my $msb (@{$summary}) {
	delete $msb->{_obssum};
	delete $msb->{summary};
	$msb->{latest} = ''.$msb->{latest}; # unbless
	$msb->{earliest} = ''.$msb->{earliest}; # unbless
	for my $obs (@{$msb->{obs}}) {
	  $obs->{waveband} = ''.$obs->{waveband}; # unbless
	  $obs->{coords} = [$obs->{coords}->array];
	}
      }
    }

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
  return $summary;
}


sub returnStruct {
  my $self = shift;

  return {  summary => "hello", timestamp => 52 };

}

sub returnArray {
  my $self = shift;

  return [ "hello", 52 ];

}

sub returnList {
  my $self = shift;
  return ("hello", 52);
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
