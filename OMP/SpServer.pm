package OMP::SpServer;

=head1 NAME

OMP::SpServer - Science Program Server class

=head1 SYNOPSIS

  $xml = OMP::SpServer->fetchProgram($project, $password);
  $summary = OMP::SpServer->storeProgram($xml, $password, 0);

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

An optional third parameter can be used to control the behaviour
if the timestamps do not match. If false an exception will be raised
(of type C<SpChangedOnDisk>) and the store will fail if the timestamp
of the program being stored does not match that already in the database.
If true the timestamp test will be ignored and the program will be
stored. This allows people to force the storing of a science program
and should be used with care.

  [$summary, $timestamp] = OMP::SpServer->storeProgram($sciprog, 
                                                       $password, $force);


=cut

sub storeProgram {
  my $class = shift;

  my $xml = shift;
  my $password = shift;
  my $force = shift;

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
    $db->storeSciProg( SciProg => $sp, Force => $force );

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

  $text = OMP::SpServer->programDetails($project,$password,'ascii' );
  $array = OMP::SpServer->programDetails($project,$password,'data' );

Note that this may cause problems for a strongly typed language.

The project password is required.

=cut

sub programDetails {
  my $class = shift;
  my $projectid = shift;
  my $password = shift;
  my $mode = lc(shift);
  $mode ||= 'ascii';

  my $E;
  my $summary;
  try {

    # Create new DB object
    my $db = new OMP::MSBDB( 
			    ProjectID => $projectid,
			    Password => $password,
			    DB => $class->dbConnection, );

    # Retrieve the Science Program object
    # without sending explicit notification
    my $sp = $db->fetchSciProg(1);

    # Create a summary of the science program
    $summary = $sp->summary($mode);

    # Clean the data structure if we are in 'data'
    if ($mode eq 'data') {
      for my $msb (@{$summary}) {
	delete $msb->{_obssum};
	delete $msb->{summary};
	$msb->{datemax} = ''.$msb->{datemax}; # unbless
	$msb->{datemin} = ''.$msb->{datemin}; # unbless
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

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=cut

1;
