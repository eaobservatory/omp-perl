package OMP::Translator;

=head1 NAME

OMP::Translator - translate science program to sequence

=head1 SYNOPSIS

  use OMP::Translator;

  $odf = OMP::Translator->translate( $sp );


=head1 DESCRIPTION

This class converts a science program object (an C<OMP::SciProg>)
into a sequence understood by the data acquisition system.

In the case of SCUBA, an Observation Definition File (ODF) is
generated (or if there is more than one observation a SCUBA
macro).

Presumably at some point this class will be modified to delegate
to an instrument specific subclass. For now just deals with SCUBA.

=cut

use 5.006;
use strict;
use warnings;

use OMP::SciProg;
use OMP::Error;

our $VERSION = (qw$Revision$)[1];

our $TRANS_DIR = "/tmp/omplog";

use constant PI => 3.141592654;

=head1 METHODS

=over 4

=item B<translate>

Convert the science program object (C<OMP::SciProg>) into
a observing sequence understood by the instrument data acquisition
system.

  $odf = OMP::Translate->translate( $sp );
  $data = OMP::Translate->translate( $sp, 1);
  @data = OMP::Translate->translate( $sp, 1);

Currently only understands SCUBA. Eventually will have to understand
ACSIS.

By default returns the name of an observation definition file, or if
more than one observation is generated from the SpObs, the name of a
SCUBA macro file. An optional second parameter can be used to indicate
that no file should be written to disk but that the translated
information is to be returned as a data structure (for scuba and array
of hashes).

=cut

sub translate {
  my $self = shift;
  my $sp = shift;
  my $asdata = shift;

  # See how many MSBs we have
  my @msbs = $sp->msb;

#  throw OMP::Error::TranslateFail("Only one MSB can be translated at a time")
#    if scalar(@msbs) != 1;

  # Now unroll the MSB into constituent observations details
  my $msb = $msbs[0];
  my @obs = $msb->unroll_obs();

  # Treat an ODF as a hash and a macro as an array of hashes
  # until the last moment.
  my @odfs;
  for my $obsinfo ( @obs ) {

    # Determine the mode
    my $mode = $obsinfo->{MODE};
    if ($self->can( $mode )) {
      my %translated = $self->$mode( %$obsinfo );
      push(@odfs, \%translated);
      use Data::Dumper;
      print Dumper(\%translated);
    } else {
      throw OMP::Error::TranslateFail("Unknown observing mode: $mode");
    }

  }

  # Return data or write to disk
  if ($asdata) {
    if (wantarray) {
      return @odfs;
    } else {
      return \@odfs;
    }
  } else {
    # Write

  }

}

=back

=head1 INTERNAL METHODS

=head2 Observing  Modes

Internal methods that understand each observation mode.

=over 4

=item B<SpIterSkydipObs>

Given a high level specification for a skydip, generate a SCUBA
ODF:

  %odf = $trans->SpIterSkydipObs( %info );

=cut

sub SpIterSkydipObs {
  my $self = shift;
  my %info = @_;

  # Template
  my %odf = (
	     OBSERVING_MODE => 'SKYDIP', # This is a skydip
	     ACCEPT => 'YES',            # Always accept
	     CHOP_FREQ => 2.0,
	     MAX_EL => 80.0,
	     MIN_EL => 15.0,
	     SAMPLE_MODE => 'RASTER',
	     N_MEASUREMENTS => 2,        # Forced for raster
	     N_INTEGRATIONS => 10,       # Forced for raster
	    );

  # Only need to add filter
  %odf = ( %odf, $self->getFilter( %info ));
  for (qw/ General Filter / ) {
    my $method = "get$_";
    %odf = ( %odf, $self->$method( %info ) );
  }

  # Override project ID for all calibrations?
  $odf{PROJECT_ID} = 'SCUBA';

  return %odf;
}

=item B<SpIterStareObs>

Given a high level specification for a photometry observation,
generate a SCUBA ODF:

  %odf = $trans->SpIterStareObs( %info );

=cut

sub SpIterStareObs {
  my $self = shift;
  my %info = @_;

  # Template
  my %odf = (
	     # General
	     # Bolometers
	     # Chopping
	     CHOP_FUN => 'SCUBAWAVE',
	     # Filter
	     # GAIN
	     JIGGLE_NAME => 'JCMTDATA_DIR:SQUEASY_9_2P0.JIG',
	     JIGGLE_P_SWITCH => '9',
	     # Offsets
	     # integrations
	     OBSERVING_MODE => 'PHOTOM',
	     SAMPLE_COORDS => 'AZ',
	     SPIKE_REMOVAL => 'YES',
	     SAMPLE_MODE => 'JIGGLE',
	     SWITCH_MODE => 'BMSW',
	     # Target
	    );

  # Populate bits that vary
  for (qw/ General Bols Filter Gain Offsets Ints Target / ) {
    my $method = "get$_";
    %odf = ( %odf, $self->$method( %info ) );
  }

  return %odf;

}

=item B<SpIterPointingObs>

Given a high level specification for a pointing observation,
generate a SCUBA ODF:

  %odf = $trans->SpIterPointingObs( %info );

=cut

sub SpIterPointingObs {
  my $self = shift;
  my %info = @_;

  # Template
  my %odf = (
	     ACCEPT => 'PROMPT',
	     # General
	     # Bolometers
	     # Chopping
	     CHOP_FUN => 'SCUBAWAVE',
	     # Filter
	     # GAIN
	     # Jiggle
	     # Offsets
	     # integrations
	     OBSERVING_MODE => 'POINTING',
	     SAMPLE_COORDS => 'NA',
	     SAMPLE_MODE => 'JIGGLE',
	     SPIKE_REMOVAL => 'YES',
	     SWITCH_MODE => 'BMSW',
	     # Target
	    );

  # If we have an array (primaryBolometer = LONG or SHORT)
  # then we need the following jiggle
  # This is slightly different to normal jiggle maps
  my %jiggle;
  if ($info{primaryBolometer} eq 'LONG' or
      $info{primaryBolometer} eq 'SHORT') {
    # For ARRAY pointing
    %jiggle = (
	       JIGGLE_NAME => 'JCMTDATA_DIR:EASY_16_6P18.JIG',
	       JIGGLE_P_SWITCH => '16'
	      );
  } else {
    %jiggle = (
	       JIGGLE_P_SWITCH => 10,
	       );
  }
  %odf = ( %odf, %jiggle );

  # Populate bits that vary
  for (qw/ General Bols Filter Gain Offsets Ints Target Chop / ) {
    my $method = "get$_";
    %odf = ( %odf, $self->$method( %info ) );
  }

  return %odf;

}

=item B<SpIterJiggleObs>

Given a high level specification for a jiggle map observation,
generate a SCUBA ODF:

  %odf = $trans->SpIterJiggleObs( %info );

=cut

sub SpIterJiggleObs {
  my $self = shift;
  my %info = @_;

  # Template
  my %odf = (
	     # General
	     # Bolometers
	     # Chopping
	     CHOP_FUN => 'SCUBAWAVE',
	     # Filter
	     # GAIN
	     # Jiggle
	     JIGGLE_P_SWITCH => 16,
	     # Offsets
	     # integrations
	     OBSERVING_MODE => 'POINTING',
	     SAMPLE_COORDS => 'NA',
	     SAMPLE_MODE => 'JIGGLE',
	     SPIKE_REMOVAL => 'YES',
	     SWITCH_MODE => 'BMSW',
	     # Target
	     # Pol
	    );

  # All the known jiggle patterns
  # There is no gain in dynmically generating these
  my %PATTERNS = (
		  P1350 => {
			    3x3 => 'JCMTDATA_DIR:SQUARE_1350_3x3.JIG',
			    5x5 => 'JCMTDATA_DIR:SQUARE_1350_5x5.JIG',
			    7x7 => 'JCMTDATA_DIR:SQUARE_1350_7x7.JIG',
			    9x9 => 'JCMTDATA_DIR:SQUARE_1350_9x9.JIG',
			   },
		  P1100 => {
			    3x3 => 'JCMTDATA_DIR:SQUARE_1100_3x3.JIG',
			    5x5 => 'JCMTDATA_DIR:SQUARE_1100_5x5.JIG',
			    7x7 => 'JCMTDATA_DIR:SQUARE_1100_7x7.JIG',
			    9x9 => 'JCMTDATA_DIR:SQUARE_1100_9x9.JIG',
			   },
		  P2000 => {
			    3x3 => 'JCMTDATA_DIR:SQUARE_2000_3x3.JIG',
			    5x5 => 'JCMTDATA_DIR:SQUARE_2000_5x5.JIG',
			    7x7 => 'JCMTDATA_DIR:SQUARE_2000_7x7.JIG',
			    9x9 => 'JCMTDATA_DIR:SQUARE_2000_9x9.JIG',
			   },
		  LONG => {
			    3x3 => 'JCMTDATA_DIR:SQUARE_LONG_3x3.JIG',
			    5x5 => 'JCMTDATA_DIR:SQUARE_LONG_5x5.JIG',
			    7x7 => 'JCMTDATA_DIR:SQUARE_LONG_7x7.JIG',
			    9x9 => 'JCMTDATA_DIR:SQUARE_LONG_9x9.JIG',
			   },
		  SHORT => {
			    3x3 => 'JCMTDATA_DIR:SQUARE_SHORT_3x3.JIG',
			    5x5 => 'JCMTDATA_DIR:SQUARE_SHORT_5x5.JIG',
			    7x7 => 'JCMTDATA_DIR:SQUARE_SHORT_7x7.JIG',
			    9x9 => 'JCMTDATA_DIR:SQUARE_SHORT_9x9.JIG',
			   },

		  );

  # For these patterns the JIGGLE_P_SWITCH values need to be tweaked
  # for efficiency
  my %JIG_P_SWITCH = (
		      3x3 => 9,
		      5x5 => 13,
		      7x7 => 17,
		      9x9 => 21,
		      );

  # If we have an array (primaryBolometer = LONG or SHORT)
  # then we know the jiggle pattern
  my %jiggle;
  if ($info{primaryBolometer} eq 'LONG' or
      $info{primaryBolometer} eq 'SHORT') {

    # Create a hash of all the bolometers selected
    # to make it easier for lookup
    my %bols = map { $_, undef } @{ $info{bolometers} };

    my $jiggle;
    if (exists $bols{LONG} and exists $bols{SHORT} ) {
      $jiggle = "JCMTDATA_DIR:EASY_64_3P09.JIG";
    } elsif (exists $bols{LONG}) {
      $jiggle = "JCMTDATA_DIR:EASY_16_6P18.JIG";
    } elsif (exists $bols{SHORT}) {
      $jiggle = "JCMTDATA_DIR:EASY_16_3P09.JIG";
    } else {
      throw OMP::Error::SpTranslateFail("strange problem with bolometer assignments for jiggle");
    }

    %jiggle = ( JIGGLE_NAME => $jiggle,
		JIGGLE_P_SWITCH => 16);

  } else {

    # Use the specified pattern
    my $pattern = $info{jigglePattern};

    # determine the sub instrument of the primary bolometer
    my $subinst = $self->getSubInst( $info{primaryBolometer}, %info );

    my $jiggle = $PATTERNS{$subinst}{$pattern};
    my $jigpsw = $JIG_P_SWITCH{$pattern};

    %jiggle = ( JIGGLE_NAME => $jiggle,
		JIGGLE_P_SWITCH => $jigpsw );

  }
  %odf = ( %odf, %jiggle );

  # Populate bits that vary
  for (qw/ General Bols Filter Gain Offsets Ints Target Chop Pol / ) {
    my $method = "get$_";
    %odf = ( %odf, $self->$method( %info ) );
  }

  return %odf;

}

=item B<SpIterRasterObs>

Given a high level specification for a scan observation,
generate a SCUBA ODF:

  %odf = $trans->SpIterRasterObs( %info );

=cut

sub SpIterRasterObs {
  my $self = shift;
  my %info = @_;

  # Template
  my %odf = (
	     # Target
	     # General
	     # Bolometers
	     CALIBRATOR => 'NO',
	     CHOP_FREQ => 8.0,  # Integer chops per sample
	     CHOP_FUN => 'SQUARE',
	     # Chop
	     # Gain
	     # Filter
	     # Map area specification
	     # Offsets
	     # Integrations
	     OBSERVING_MODE => 'MAP',
	     # Scan specification
	     SPIKE_REMOVAL => 'NO',
	     SAMPLE_MODE => 'RASTER',
	     # Pol
	    );

  # Populate bits that vary
  for (qw/ General Bols Filter Gain Offsets Ints Target Chop Scan/ ) {
    my $method = "get$_";
    %odf = ( %odf, $self->$method( %info ) );
  }

  return %odf;

}



=back

=head2 ODF Chunks

Used for determining little chunks of an odf that are independent of
observing mode.

=over 4

=item B<getGeneral>

Retrieve general information that should be stored in an ODF but 
which does not change between observations. Usual candidates are
MSBID (checksum), project ID and INSTRUMENT.

  %general = $trans->getGeneral( %info );

=cut

sub getGeneral {
  my $self = shift;
  my %info = @_;

  return ( MSBID => $info{MSBID},
	   PROJECT_ID => $info{PROJECTID},
	   INSTRUMENT => 'SCUBA',
	   DATA_KEPT => 'DEMOD',
	 );
}

=item B<getGain>

Get the instrument GAIN. This depends on the target. For bright planets
it should be 1. For everything else it should be 10.

  %gain = $trans->getGain( %info );

=cut

sub getGain {
  my $self = shift;
  my %info = @_;

  my $target = $info{target};
  my $gain;
  if ($target =~ /^(MARS|SATURN|JUPITER|MOON)$/i) {
    $gain = 1;
  } else {
    $gain = 10;
  }
  return (GAIN => $gain);
}

=item B<getOffsets>

Specify offsets. In general the offsets are in tracking. AZ offsets
are currently not supported (ie LOCAL_COORDS is never used).

  %offset = $trans->getOffsets( %info );

=cut

sub getOffsets {
  my $self = shift;
  my %info = @_;

  my $pa = ( exists $info{OFFSET_PA} ? $info{OFFSET_PA} : 0.0 );;
  my $dx = ( exists $info{OFFSET_DX} ? $info{OFFSET_DX} : 0.0 );;
  my $dy = ( exists $info{OFFSET_DY} ? $info{OFFSET_DY} : 0.0 );;

  # Must remove rotation
  my $rpa = $pa * PI / 180; # radians
  my $xoff = $dx * cos( $pa )  +  $dy * sin( $pa );
  my $yoff = $dx * sin( $pa )  +  $dy * cos( $pa );

  return ( MAP_X => $xoff, MAP_Y => $yoff);
}

=item B<getInts>

Get the number of integrations for the observation.

=cut

sub getInts {
  my $self = shift;
  my %info = @_;

  my $nint = $info{nintegrations};

  return ( N_INTEGRATIONS => $nint );
}

=item B<getChop>

=cut

sub getChop {
  my $self = shift;
  my %info = @_;

  my %chop;
  $chop{CHOP_THROW} = $info{CHOP_THROW};
  $chop{CHOP_PA} = $info{CHOP_PA};

  my $system = $info{CHOP_SYSTEM};
  $chop{CHOP_COORDS} = $self->getOtherCoordSystem($system, %info);

  return %chop;
}

=item B<getTarget>


=cut

sub getTarget {
  my $self = shift;
  my %info = @_;

  return ();
}

=item B<getScan>


=cut

sub getScan {
  my $self = shift;
  my %info = @_;

  my %scan;
  $scan{MAP_PA} = $info{MAP_PA};
  $scan{MAP_HEIGHT} = $info{MAP_HEIGHT};
  $scan{MAP_WIDTH}  = $info{MAP_WIDTH};
  $scan{SAMPLE_DY}  = $info{SCAN_DY};

  # Convert the velocity to a DX using the fact that we always
  # chop at 8 Hz
  use constant SCAN_CHOP_FREQ => 8;
  my $vel = $info{SCAN_VELOCITY};
  $scan{SAMPLE_DX} = $vel / SCAN_CHOP_FREQ;

  # System 
  my $system = $info{SCAN_SYSTEM};
  $scan{SAMPLE_COORDS} = $self->getOtherCoordSystem($system, %info);

  # Sample position angle
  # Need to calculate this if it hasn't been specified.
  # Get the allowed values
  my @scanpas = @{ $info{SCAN_PA}};
  if (@scanpas) {
    # Some have been specified
    # We should really work out which is best and then use that

  } else {
    # Nothing specified
    # We have to make a stab

  }

  # For now - Ha!
  $scan{SAMPLE_PA} = 14.5;

  return %scan;
}

=item B<getBols>

Get the bolometer list suitable for the ODF.

  %bols = $trans->getBols( %info );

=cut

sub getBols {
  my $self = shift;
  my %info = @_;

  # Get the bolometers 
  my @bols = @{$info{bolometers}};

  # primary bolometer must come first in list
  my $primary = $info{primaryBolometer};

  my $bols = join(",", $primary, grep { $_ ne $primary} @bols);

  return (BOLOMETERS => $bols);
}

=item B<getFilter>

Retrieves the ODF chunk relating to filter specification.

  %filter = $trans->getFilter( %info );

=cut

sub getFilter {
  my $self = shift;
  my %info = @_;

  # Simply ask for the filter from the Waveband object
  my $filter = $info{waveband}->filter;
  return ( FILTER => $filter );
}

=item B<getPol>

Get polarimeter details. In general this will return an empty list if
we are not in a polarimeter observation. It will also override the
observing mode and (for phot) the jiggle pattern if we do have a
polarimeter observation.

=cut

sub getPol {
  my $self = shift;
  my %info = @_;

  return () unless $info{pol};

  my %pol;
  if ($info{MODE} eq 'SpIterRasterObs' or
      $info{MODE} eq 'SpIterJiggleObs') {
    $pol{MODE} = "POLMAP";
  } elsif ($info{MODE} eq 'SpIterStareObs') {
    $pol{MODE} = "POLPHOT";
    $pol{JIGGLE_NAME} = "JCMTDATA_DIR:NULL_1P0.JIG";
  } else {
    throw OMP::Error::SpTranslateFail("Pol mode only available for map and phot, not $info{MODE}");
  }

  # Waveplates must be stored in an array
  # pending the writing of the file to disk
  $pol{WPLATE_NAME} = $info{waveplate};

  return %pol;
}



=back

=head2 General SCUBA oddities

=item B<getCentCoordSystem>

Translate a TCS DTD coordinate system into a system understood
by SCUBA. Used for centre_coords not scanning, offsetting or chopping.

  $system = $self->getCentCoordSystem( $tcs, %info );

  FPLANE => NA
  TRACKING => RB, RJ, GA or RD or PLANET
  AZEL => AZ

The additional information is required when multiple translations
are supported.

Note that for RB, RJ and GA we always return RJ since that conversion
can always be performed and OT offsets are always RJ. This may well break
if the OT is "fixed" to allow GA offsets.

=cut

sub getCentCoordSystem {
  my $self = shift;
  my $tcssys = shift;
  my %info = @_;

  return 'NA' if $tcssys eq 'FPLANE';
  return 'AZ' if $tcssys eq 'AZEL';

  if ($tcssys eq 'TRACKING') {

    # If we are RADEC we ALWAYS use J2000
    if ($info{coordstype} eq 'RADEC') {
      return 'RJ';
    } elsif ( $info{coordstype} eq 'ELEMENTS'
	      or $info{coordstype} eq 'PLANET') {
      return 'PLANET';
    } else {
      throw OMP::Error::SpTranslateFail("Unknown tracking coord combination: $info{coordstype}");
    }
  } else {
    throw OMP::Error::SpTranslateFail("Unknown coordinate system :$tcssys");
  }

}

=item B<getOtherCoordSystem>

Translate a TCS specification for coordinate system to something SCUBA
understands. This works for chopping and scanning.

  $scusys = $trans=>getOtherCoordSystem($tcssys, %info);

=cut

sub getOtherCoordSystem {
  my $self = shift;
  my $tcssys = shift;
  my %info = @_;

  my $scusys;
  if ($tcssys eq 'TRACKING') {
    $scusys = "LO";
  } elsif ($tcssys eq 'AZEL') {
    $scusys = "AZ";
  } elsif ($tcssys eq 'FPLANE') {
    $scusys = "NA";
  } else {
    throw OMP::Error::SpTranslateFail("Unknown TCS system: $tcssys");
  }

  return $scusys;
}

=item B<getSubInst>

Retrieve the name of the sub-instrument associated with the supplied
bolometer.

  $subinst = $self->getSubInst( $bol );

=cut

sub getSubInst {
  my $self = shift;
  my $bol = shift;

  my $sub;
  if ($bol eq 'LONG' or $bol eq 'SHORT' or $bol =~ /^P/) {
    # Its already a sub-instrument
    $sub = $bol;
  } else {
    # A bolometer
    # This really needs the flatfield file
    # Read it from an external location but for now read it from
    # the DATA handle
    my @lines = <DATA>;
    my $sub;
    for my $line (@lines) {
      next unless $line =~ /^SETBOL/;
      $line =~ s/^\s+//; # trim leading space
      my @parts = split /\s+/, $line;
      my ($flatbol, $flatsub) = @parts[1,2];
      if ($flatbol eq $bol) {
	$sub = $flatsub;
	next;
      }
    }
    throw OMP::Error::SpTranslateFail("Bolometer $bol not present in any SCUBA sub-instrument")
      unless defined $sub;
  }
  return $sub;
}


=back

=head1 COPYRIGHT

Copyright (C) 2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=cut

1;

__DATA__
proc SET_BOLS
{ flat field data file written by the SURF       task EXTRACT_FLAT 
{ Written on: Thu Jan 17 12:48:28 2002
{ Extracted from file 20010311_dem_0052
{ Original flatfield name: jcmtdata_dir:lwswphot.dat
{      Name Type         dU3         dU4         Calib       Theta       A           B         Qual
 SETBOL A1  SHORT        0.5708E+02 -0.2814E+02  0.1286E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL A2  SHORT        0.4590E+02 -0.3591E+02  0.9311E+00  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL A3  SHORT        0.3615E+02 -0.4146E+02  0.9499E+00  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL A4  SHORT        0.2464E+02 -0.4962E+02  0.1002E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL A5  SHORT        0.1455E+02 -0.5628E+02  0.9585E+00  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL A6  SHORT        0.3620E+01 -0.6315E+02  0.1115E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL A7  SHORT        0.5638E+02 -0.1661E+02  0.1000E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL A8  SHORT        0.4508E+02 -0.2315E+02  0.1126E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL A9  SHORT        0.3495E+02 -0.3012E+02  0.1089E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL A10 SHORT        0.2240E+02 -0.3762E+02  0.1107E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL A11 SHORT        0.1314E+02 -0.4396E+02  0.1203E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL A12 SHORT        0.2812E+01 -0.5070E+02  0.1067E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL A13 SHORT       -0.7590E+01 -0.5808E+02  0.9114E+00  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL A14 SHORT        0.5559E+02 -0.4683E+01  0.9639E+00  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL A15 SHORT        0.4502E+02 -0.1081E+02  0.1068E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL A16 SHORT        0.3296E+02 -0.1807E+02  0.1170E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL B1  SHORT        0.2224E+02 -0.2456E+02  0.1102E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL B2  SHORT        0.1165E+02 -0.3120E+02  0.1157E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL B3  SHORT        0.2000E+01 -0.3855E+02  0.9660E+00  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL B4  SHORT       -0.9089E+01 -0.4490E+02  0.1076E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL B5  SHORT       -0.1951E+02 -0.5160E+02  0.9298E+00  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL B6  SHORT        0.5585E+02  0.7780E+01  0.1088E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL B7  SHORT        0.4489E+02  0.9322E+00  0.1020E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL B8  SHORT        0.3283E+02 -0.5420E+01  0.1112E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL B9  SHORT        0.2169E+02 -0.1181E+02  0.1019E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL B10 SHORT        0.1166E+02 -0.1921E+02  0.1063E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL B11 SHORT        0.7480E+00 -0.2610E+02  0.1017E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL B12 SHORT       -0.1013E+02 -0.3228E+02  0.1085E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL B13 SHORT       -0.2043E+02 -0.3952E+02  0.1112E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL B14 SHORT       -0.2907E+02 -0.4586E+02  0.9829E+00  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL B15 SHORT        0.5681E+02  0.2020E+02  0.9500E+00  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL B16 SHORT        0.4512E+02  0.1323E+02  0.1090E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL C1  SHORT        0.3315E+02  0.7096E+01  0.1004E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL C2  SHORT        0.2194E+02  0.7400E+00  0.1066E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL C3  SHORT        0.1091E+02 -0.6110E+01  0.1044E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL C4  SHORT        0.2756E+00 -0.1215E+02  0.1254E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL C5  SHORT       -0.1075E+02 -0.1977E+02  0.1111E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL C6  SHORT       -0.2075E+02 -0.2666E+02  0.1075E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL C7  SHORT       -0.3146E+02 -0.3298E+02  0.1287E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL C8  SHORT       -0.4124E+02 -0.4042E+02  0.9000E+00  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL C9  SHORT        0.5849E+02  0.3141E+02  0.1326E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL C10 SHORT        0.4631E+02  0.2581E+02  0.1066E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL C11 SHORT        0.3388E+02  0.2000E+02  0.1229E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL C12 SHORT        0.2248E+02  0.1267E+02  0.1401E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL C13 SHORT        0.1116E+02  0.6479E+01  0.1062E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL C14 SHORT        0.0000E+00  0.0000E+00  0.1000E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL C15 SHORT       -0.1116E+02 -0.6479E+01  0.1130E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL C16 SHORT       -0.2215E+02 -0.1332E+02  0.1101E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL D1  SHORT       -0.3139E+02 -0.2045E+02  0.1157E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL D2  SHORT       -0.4220E+02 -0.2734E+02  0.1175E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL D3  SHORT       -0.5298E+02 -0.3271E+02  0.1142E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL D4  SHORT        0.4815E+02  0.3794E+02  0.9828E+00  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL D5  SHORT        0.3558E+02  0.3207E+02  0.1027E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL D6  SHORT        0.2340E+02  0.2565E+02  0.1080E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL D7  SHORT        0.1184E+02  0.1956E+02  0.1258E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL D8  SHORT        0.1100E+01  0.1301E+02  0.1052E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL D9  SHORT       -0.1030E+02  0.6303E+01  0.1011E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL D10 SHORT       -0.2141E+02 -0.4385E+00  0.1088E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL D11 SHORT       -0.3244E+02 -0.6844E+01  0.1173E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL D12 SHORT       -0.4299E+02 -0.1380E+02  0.1172E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL D13 SHORT       -0.5295E+02 -0.2078E+02  0.9500E+00  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL D14 SHORT        0.3682E+02  0.4498E+02  0.9517E+00  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL D15 SHORT        0.2543E+02  0.3744E+02  0.1036E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL D16 SHORT        0.1301E+02  0.3179E+02  0.1248E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL E1  SHORT        0.1499E+01  0.2630E+02  0.1153E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL E2  SHORT       -0.9694E+01  0.1926E+02  0.1098E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL E3  SHORT       -0.2096E+02  0.1302E+02  0.1142E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL E4  SHORT       -0.3153E+02  0.6590E+01  0.1126E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL E5  SHORT       -0.4362E+02 -0.8783E+00  0.1026E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL E6  SHORT       -0.5395E+02 -0.7067E+01  0.1020E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL E7  SHORT        0.2731E+02  0.5184E+02  0.9742E+00  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL E8  SHORT        0.1511E+02  0.4443E+02  0.1204E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL E9  SHORT        0.3500E+01  0.3973E+02  0.1020E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL E10 SHORT       -0.8784E+01  0.3302E+02  0.1197E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL E11 SHORT       -0.1987E+02  0.2656E+02  0.1005E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL E12 SHORT       -0.3045E+02  0.2024E+02  0.1067E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL E13 SHORT       -0.4249E+02  0.1245E+02  0.9850E+00  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL E14 SHORT       -0.5245E+02  0.6274E+01  0.1177E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL E15 SHORT        0.1652E+02  0.5893E+02  0.9800E+00  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL E16 SHORT        0.3524E+01  0.5163E+02  0.1174E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL F1  SHORT       -0.7665E+01  0.4592E+02  0.1168E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL F2  SHORT       -0.1817E+02  0.3963E+02  0.1020E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL F3  SHORT       -0.3008E+02  0.3403E+02  0.1295E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL F4  SHORT       -0.4123E+02  0.2619E+02  0.1244E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL F5  SHORT       -0.5155E+02  0.2029E+02  0.1069E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL F6  SHORT        0.6895E+01  0.6560E+02  0.1245E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL F7  SHORT       -0.4842E+01  0.6013E+02  0.9947E+00  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL F8  SHORT       -0.1690E+02  0.5287E+02  0.1017E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL F9  SHORT       -0.2931E+02  0.4752E+02  0.9485E+00  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL F10 SHORT       -0.4009E+02  0.3977E+02  0.9474E+00  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL F11 SHORT       -0.5045E+02  0.3338E+02  0.1169E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL G1  LONG         0.7830E+01 -0.7610E+02  0.1290E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL G2  LONG         0.2679E+02 -0.6138E+02  0.1086E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL G3  LONG         0.4785E+02 -0.4588E+02  0.1160E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL G4  LONG         0.7119E+02 -0.3377E+02  0.1080E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL G6  P2000        0.1090E+03  0.2375E+01  0.1000E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL G7  LONG        -0.1777E+02 -0.6524E+02  0.1089E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL G8  LONG         0.2193E+01 -0.4958E+02  0.1032E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL G9  LONG         0.2291E+02 -0.3673E+02  0.1194E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL G10 LONG         0.4500E+02 -0.2298E+02  0.1187E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL G11 LONG         0.6850E+02 -0.1106E+02  0.1159E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL G12 P1350       -0.5827E+02 -0.7068E+02  0.1000E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL G13 LONG        -0.3950E+02 -0.5281E+02  0.1039E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL G14 LONG        -0.2157E+02 -0.3796E+02  0.1072E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL G15 LONG         0.5100E-01 -0.2533E+02  0.1150E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL G16 LONG         0.2174E+02 -0.1171E+02  0.9190E+00  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL H1  LONG         0.4506E+02  0.1172E+01  0.1014E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL H2  LONG         0.6772E+02  0.1328E+02  0.9490E+00  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL H4  LONG        -0.6336E+02 -0.3956E+02  0.1003E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL H5  LONG        -0.4256E+02 -0.2631E+02  0.9240E+00  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL H6  LONG        -0.2200E+02 -0.1264E+02  0.9870E+00  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL H7  LONG         0.0000E+00  0.0000E+00  0.1000E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL H8  LONG         0.2262E+02  0.1231E+02  0.9270E+00  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL H9  LONG         0.4633E+02  0.2465E+02  0.1039E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL H10 LONG         0.7049E+02  0.3728E+02  0.1134E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL H11 LONG        -0.6490E+02 -0.1333E+02  0.9580E+00  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL H12 LONG        -0.4228E+02 -0.4700E+00  0.9160E+00  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL H13 LONG        -0.2029E+02  0.1298E+02  0.1068E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL H14 LONG         0.1250E+01  0.2529E+02  0.9650E+00  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL H15 LONG         0.2519E+02  0.3783E+02  0.9380E+00  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL H16 LONG         0.4965E+02  0.4959E+02  0.9280E+00  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL I1  LONG        -0.6385E+02  0.1301E+02  0.9940E+00  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL I2  LONG        -0.4057E+02  0.2669E+02  0.1051E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL I3  LONG        -0.1803E+02  0.3894E+02  0.1135E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL I4  LONG         0.5930E+01  0.5154E+02  0.9620E+00  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL I5  LONG         0.2938E+02  0.6318E+02  0.9410E+00  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL I6  LONG        -0.6020E+02  0.4057E+02  0.9970E+00  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL I7  LONG        -0.3669E+02  0.5404E+02  0.1054E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL I8  LONG        -0.1578E+02  0.6389E+02  0.1065E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL I9  LONG         0.9047E+01  0.7776E+02  0.1045E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL I10 P1100       -0.5465E+02  0.7116E+02  0.1000E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL I11 SHORT_DC     0.0000E+00  0.0000E+00  0.1000E+01  0.0000E+00  0.0000E+00  0.0000E+00  1   0.0 0  UNK
 SETBOL I12 LONG_DC      0.0000E+00  0.0000E+00  0.1000E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL I13 P2000_DC     0.0000E+00  0.0000E+00  0.1000E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL I14 P1350_DC     0.0000E+00  0.0000E+00  0.1000E+01  0.0000E+00  0.0000E+00  0.0000E+00  0   0.0 0  UNK
 SETBOL I15 P1100_DC     0.0000E+00  0.0000E+00  0.1000E+01  0.0000E+00  0.0000E+00  0.0000E+00  1   0.0 0  UNK
end proc
