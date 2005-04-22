package OMP::Translator::SCUBA;

=head1 NAME

OMP::Translator::SCUBA - translate SCUBA MSB to ODF

=head1 SYNOPSIS

  use OMP::Translator::SCUBA;

  $odf = OMP::Translator->translate( $sp );


=head1 DESCRIPTION

This class converts a science program object (an C<OMP::SciProg>)
into a sequence understood by the data acquisition system (in this
case an ODF).

=cut

use 5.006;
use strict;
use warnings;

use OMP::Error;
use OMP::Config;

use Fcntl;
use File::Spec;
use File::Basename qw/basename/;
use Time::Piece ':override';
use Time::Seconds qw/ ONE_HOUR /;
use SCUBA::ODF;
use SCUBA::ODFGroup;
use SCUBA::FlatField;
use Data::Dumper;
use Astro::Telescope;

use base qw/ OMP::Translator /;

our $VERSION = (qw$Revision$)[1];

# Unix directory for writing ODFs
our $TRANS_DIR = OMP::Config->getData( "scuba_translator.transdir" );

# Equivalent path on vax
our $TRANS_DIR_VAX = "OBSERVE:[OMPODF]";

# Debugging
our $DEBUG = 0;

=head1 METHODS

=over 4

=item B<translate>

Convert the Science Program MSB (C<OMP::MSB>) into
a observing sequence understood by the instrument data acquisition
system (an ODF, or multiple ODFs).

  @odfs = OMP::Translate->translate( $msb );

Always returns the translated result as a list of C<SCUBA::ODF> objects.
An exception will be thrown if the MSB is not a SCUBA MSB.

MSBs will be pre-filtered by the caller, assumed to be C<OMP::Translator>.

=cut

sub translate {
  my $self = shift;
  my $msb = shift;

  print "MSB " . $msb->checksum . "\n"
    if $DEBUG;

  # First thing we need to do is correct for the inconsistencies
  # with JIGGLE and SCAN polarimetry. For SCAN we have to iterate
  # over waveplates. For JIGGLE we just put them all in a single ODF
  $self->correct_wplate( $msb );

  my @obs = $msb->unroll_obs();

  # See if the MSB was suspended
  my $suspend = $msb->isSuspended;

  # Treat an ODF as a hash and a macro as an array of hashes
  # until the last moment.
  my @odfs;

  # by default do not skip observations unless we are suspended
  my $skip = ( defined $suspend ? 1 : 0);
  my $obscount = 0;
  for my $obsinfo ( @obs ) {
    $obscount++;
    print "Observation: $obscount\n" if $DEBUG;
    #    print Dumper($obsinfo)
    #      if $DEBUG;

    # if we are suspended and we have not yet found the
    # relevant observation then we need to skip until we do
    # find it. This technique runs into problems if the MSB was
    # suspended in the middle of a calibration that has now been
    # deferred and is not present.
    #print "SKIPPING: $skip\n";
    #print "Current label: " . $obsinfo->{obslabel}."\n";
    if ($skip && defined $suspend) {
      # compare labels
      if ($obsinfo->{obslabel} eq $suspend) {
	$skip = 0; # no longer skip
      } else {
	# Do *not* skip if this is a calibration observation
	# calibration observation is defined by either an unknown
	# target, a standrd or one of Focus, Pointing, Noise, Skydip
	print "MODE: ". $obsinfo->{MODE} ."\n" if $DEBUG;
	print "AUTO: ". $obsinfo->{autoTarget}."\n" if $DEBUG;
	if ($obsinfo->{MODE} !~ /(Focus|Pointing|Noise|Skydip)/i &&
	    !$obsinfo->{autoTarget} && !$obsinfo->{standard}) {
	  next;
	}
      }
    }

    # Determine the mode
    my $mode = $obsinfo->{MODE};
    if ($self->can( $mode )) {
      my %translated = $self->$mode( %$obsinfo );
      my $odf = new SCUBA::ODF( Hash => \%translated );
      $odf->vax_outputdir( $TRANS_DIR_VAX );

      print $odf->summary ."\n" if $DEBUG;
      push(@odfs, $odf);

      # We know that these ODFs will not be sent directly to SCUCD
      $odf->writeSCUCD(0);

      #      use Data::Dumper;
      #      print Dumper(\%translated);
    } else {
      throw OMP::Error::TranslateFail("Unknown observing mode: $mode");
    }

  }

  # Return the translated objects
  return @odfs;

}

=item B<debug>

Method to enable and disable global debugging state.

  OMP::Translator::SCUBA->debug( 1 );

=cut

sub debug {
  my $class = shift;
  my $state = shift;

  $DEBUG = ($state ? 1 : 0 );
}

=item B<transdir>

Override the translation directory.

  OMP::Translator::SCUBA->transdir( $dir );

Note that this does not override the VAX name used for processing
inside files since that can not be determined directly from
this directory name.

=cut

sub transdir {
  my $class = shift;
  if (@_) {
    $TRANS_DIR = shift;
  }
  return $TRANS_DIR;
}

=back

=head1 INTERNAL METHODS

=head2 MSB manipulation

=over 4

=item B<correct_wplate>

For SCUBA, the waveplate iterator behaves differently depending on the
observing mode. For SCAN map the iterator is a file/odf iterator
so we need do nothing extra here. For jiggle the iterator is not
a real iterator (in the sense that we only get one file out regardless
of waveplate iterator) so we must correct the MSB internal structure
before it is unrolled into MSBs.

  OMP::Translator->correct_wplate( $msb );

If we have both a SCAN and JIGGLE observe as a child of a single
waveplate iterator we would need to clone it into two different iterators.
Since this is unusual in practice and extremely difficult to get correct
(since you have to account for all structures below the iterator) we 
croak in this situation.

=cut

sub correct_wplate {
  my $self = shift;
  my $msb = shift;

  # Note that this returns references to each observation summary.
  # We can modify this hash in place without putting the structure
  # back into the object. This will trigger a nice bug if the obssum
  # method is changed to return a copy.
  my @obs = $msb->obssum;

  # loop over each observation
  for my $obs (@obs) {
    # do the cowardly high level test first
    # just assume that a Raster plus Jiggle is bad news if pol is true

    # do not care what happens if this is not polarimetry
    next unless $obs->{pol};

    my %modes = map { $_ => undef } @{$obs->{obstype}};

    if (exists $modes{Raster}) {
      # PHOTOM and MAP/JIGGLE spell bad news
      if (exists $modes{Stare} || exists $modes{Jiggle}) {
	throw OMP::Error::TranslateFail("Can not combine a jiggle map/phot pol and scan map pol observe eye in a single observation. Please use separate observations.");
      }
    }

    # skip to next observation unless we have a Jiggle or Stare
    next unless exists $modes{Stare} or exists $modes{Jiggle};

    # Now need to recurse through the data structure changing
    # waveplate iterator to a single array rather than an array
    # separate positions.
    for my $child (@{ $obs->{SpIter}->{CHILDREN} }) {
      $self->_fix_wplate_recurse( $child );
    }

  }

}

# When we hit SpIterPOL we correct the ATTR array
# This modifies it in-place. No need to re-register.

sub _fix_wplate_recurse {
  my $self = shift;
  my $this = shift;

  # Loop over keys in children [the iterators]
  for my $key (keys %$this) {

    if ($key eq 'SpIterPOL') {
      # FIX UP - it does not make any sense to have another
      # waveplate iterator below this level but we do support it
      my @wplate = map { @{$_->{waveplate}} } @{ $this->{$key}->{ATTR}};

      # and store it back
      $this->{$key}->{ATTR} = [ { waveplate => \@wplate } ];

    }

    # Now need to go deeper if need be
    if (UNIVERSAL::isa($this->{$key},"HASH") &&
	exists $this->{$key}->{CHILDREN}) {
      # This means we have some children to analyze

      for my $child (@{ $this->{$key}->{CHILDREN} }) {
	$self->_fix_wplate_recurse( $child );
      }

    }

  }

}


=back

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
	     ACCEPT => 'NO',             # Never accept
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
  # we do not want to override projectids since we need to
  # know what the project really was in order to doneMSB even
  # if we dont charge. This is because the queue only has access
  # the ODFs and currently only looks in the last entry - if you
  # end at a skydip you wont get a doneMSB unless we do this

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

  # Wide photometry mode uses a different pattern
  if ($info{widePhotom}) {
    $odf{JIGGLE_NAME} = 'OBSERVE:[SCUBA]wide_12_1_7p0.jig';
    $odf{JIGGLE_P_SWITCH} = 12;
  }

  # Populate bits that vary
  for (qw/ General Bols Filter Gain Offsets Ints Target Chop Pol/ ) {
    my $method = "get$_";
    %odf = ( %odf, $self->$method( %info ) );
  }

  return %odf;

}

=item B<SpIterPointingObs>

Given a high level specification for a pointing observation,
generate a SCUBA ODF:

  %odf = $trans->SpIterPointingObs( %info );

Pointing observations are "special" because they do not
inherit items in the same way as science observations.
The only information obtained from the science program is:

  TARGET (unless autoTarget)
  FILTER

Chop settings and choice of bolometer are set regardless
of science program.

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
	     # Jiggle - see below
	     # Offsets - none
	     MAP_X => 0.0,
	     MAP_Y => 0.0,
	     # integrations
	     OBSERVING_MODE => 'POINTING',
	     SAMPLE_COORDS => 'NA',
	     SAMPLE_MODE => 'JIGGLE',
	     SPIKE_REMOVAL => 'YES',
	     SWITCH_MODE => 'BMSW',
	     # Target
	     AZ_RANGE => 'SHORTEST',
	    );


  # The issue of whether to point with the array or single
  # pixel is a configuration file one.
  # if we are array pointing the main issue is whether our
  # filter can support arrays
  my %jiggle;
  if ($info{waveband}->filter =~ /PHOT/i) {
    # must be phot, just use primaryBolometer
    %jiggle = (
	       JIGGLE_P_SWITCH => 10,
	       BOLOMETERS => $info{primaryBolometer},
	      );
  } else {
    if (1) {
      # ARRAY pointing
      %jiggle = (
		 JIGGLE_NAME => 'JCMTDATA_DIR:EASY_16_6P18.JIG',
		 JIGGLE_P_SWITCH => '16',
		 BOLOMETERS => 'LONG',
		);
    } else {
      # Single pixel pointing
      %jiggle = (
		 JIGGLE_P_SWITCH => 10,
		 BOLOMETERS => 'H7',
		);
    }

  }

  %odf = ( %odf, %jiggle );

  # Populate bits that vary
  for (qw/ General Filter CalChop Gain Ints Target / ) {
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
	     OBSERVING_MODE => 'MAP',
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
			    '3X3' => 'OBSERVE:[SCUBA]SQUARE_1350_3X3.JIG',
			    '5X5' => 'OBSERVE:[SCUBA]SQUARE_1350_5X5.JIG',
			    '7X7' => 'OBSERVE:[SCUBA]SQUARE_1350_7X7.JIG',
			    '9X9' => 'OBSERVE:[SCUBA]SQUARE_1350_9X9.JIG',
			   },
		  P1100 => {
			    '3X3' => 'OBSERVE:[SCUBA]SQUARE_1100_3X3.JIG',
			    '5X5' => 'OBSERVE:[SCUBA]SQUARE_1100_5X5.JIG',
			    '7X7' => 'OBSERVE:[SCUBA]SQUARE_1100_7X7.JIG',
			    '9X9' => 'OBSERVE:[SCUBA]SQUARE_1100_9X9.JIG',
			   },
		  P2000 => {
			    '3X3' => 'OBSERVE:[SCUBA]SQUARE_2000_3X3.JIG',
			    '5X5' => 'OBSERVE:[SCUBA]SQUARE_2000_5X5.JIG',
			    '7X7' => 'OBSERVE:[SCUBA]SQUARE_2000_7X7.JIG',
			    '9X9' => 'OBSERVE:[SCUBA]SQUARE_2000_9X9.JIG',
			   },
		  LONG => {
			    '3X3' => 'OBSERVE:[SCUBA]SQUARE_LONG_3X3.JIG',
			    '5X5' => 'OBSERVE:[SCUBA]SQUARE_LONG_5X5.JIG',
			    '7X7' => 'OBSERVE:[SCUBA]SQUARE_LONG_7X7.JIG',
			    '9X9' => 'OBSERVE:[SCUBA]SQUARE_LONG_9X9.JIG',
			   },
		  SHORT => {
			    '3X3' => 'OBSERVE:[SCUBA]SQUARE_SHORT_3X3.JIG',
			    '5X5' => 'OBSERVE:[SCUBA]SQUARE_SHORT_5X5.JIG',
			    '7X7' => 'OBSERVE:[SCUBA]SQUARE_SHORT_7X7.JIG',
			    '9X9' => 'OBSERVE:[SCUBA]SQUARE_SHORT_9X9.JIG',
			   },

		  );

  # For these patterns the JIGGLE_P_SWITCH values need to be tweaked
  # for efficiency
  my %JIG_P_SWITCH = (
		      '3X3' => 9,
		      '5X5' => 13,
		      '7X7' => 17,
		      '9X9' => 21,
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
      throw OMP::Error::TranslateFail("strange problem with bolometer assignments for jiggle");
    }

    %jiggle = ( JIGGLE_NAME => $jiggle,
		JIGGLE_P_SWITCH => 16);

  } else {

    # Use the specified pattern
    my $pattern = $info{jigglePattern};
    $pattern = uc($pattern) if defined $pattern;
    my $patstr = (defined $pattern ? $pattern : '[undefined]');

    throw OMP::Error::TranslateFail("Jiggle pattern $patstr is not recognized. Did you set one?") if ! exists $JIG_P_SWITCH{$pattern};

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

  # If we have asked for LONG but not SHORT give them short anyway
  if ($odf{BOLOMETERS} =~ /^LONG/i && $odf{BOLOMETERS} !~ /SHORT/i) {
    $odf{BOLOMETERS} .= ",SHORT";
  } elsif ($odf{BOLOMETERS} =~ /^SHORT/i && $odf{BOLOMETERS} !~ /LONG/i) {
    # Else we have SHORT but no LONG - add LONG
    $odf{BOLOMETERS} .= ",LONG";
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
  for (qw/ General Bols Filter Gain Offsets Ints Target Chop Scan Pol/ ) {
    my $method = "get$_";
    %odf = ( %odf, $self->$method( %info ) );
  }

  return %odf;

}

=item B<SpIterNoiseObs>

Given a high level specification for a noise observation,
generate a SCUBA ODF:

 %odf = $trans->SpIterNoiseObs( %info );

=cut

sub SpIterNoiseObs {
  my $self = shift;
  my %info = @_;

  # Template
  my %odf = (
	     # Bolometers
	     # General
	     CENTRE_COORDS => 'AZ', # Always in same place
	     CHOP_FUN => 'scubawave',
	     #CHOP_COORDS => 'AZ',
	     #CHOP_PA => 90,
	     #CHOP_THROW => 60.0,
	     # Filter
	     # GAIN
	     N_MEASUREMENTS => '1',
	     # Ints
	     OBSERVING_MODE => 'noise',
	     SAMPLE_COORDS => 'NA',
	     SPIKE_REMOVAL => 'yes',
	    );

  # Populate bits that vary
  for (qw/ General Filter Gain Ints ChopDefault / ) {
    my $method = "get$_";
    %odf = ( %odf, $self->$method( %info ) );
  }

  # bolometer choice purely depends on filter
  if ($odf{FILTER} =~ /PHOT/) {
    $odf{BOLOMETERS} = "P2000,P1350";
  } else {
    $odf{BOLOMETERS} = "LONG,SHORT";
  }


  # Source type is the only noise-specific thing that changes
  my $source = $info{noiseSource};
  if ($source eq 'SKY') {
    $source = "SPACE1";
    delete $odf{EL};
  } elsif ($source eq "ZENITH") {
    $source = "SPACE1";
    $odf{EL} = "80:00:00";
  } elsif ($source eq 'ECCOSORB') {
    $source = "MATT";
    delete $odf{EL};
  } elsif ($source eq 'REFLECTOR') {
    # do nothing - this is okay
    # execept we want this to happen at the current position
    delete $odf{EL};
  } else {
    throw OMP::Error::TranslateFail("Unknown noise source: $source");
  }

  $odf{SOURCE_TYPE} = $source;

  return %odf;
}

=item B<SpIterFocusObs>

Given a high level specification for a focus/align observation,
generate a SCUBA ODF:

 %odf = $trans->SpIterFocusObs( %info );

Pointing observations are "special" because they do not
inherit items in the same way as science observations.
The only information obtained from the science program is:

  TARGET (unless autoTarget)
  FILTER

Chop settings and choice of bolometer are set regardless
of science program.


=cut

sub SpIterFocusObs {
  my $self = shift;
  my %info = @_;

  # THE ALIGN AND FOCUS AXES MUST BE UPPER CASE
  $info{focusAxis} = uc($info{focusAxis});

  my $isFocus = ( $info{focusAxis} =~ /z/i ? 1 : 0);

  # Template
  my %odf = (
	     # General
	     ACCEPT => 'PROMPT',
	     # Bols
	     # Chop
	     CHOP_FUN => 'SCUBAWAVE',
	     # Filter

	     # Gain
	     JIGGLE_P_SWITCH => '8',
	     # Nints
	     N_MEASUREMENTS => $info{focusPoints},
	     OBSERVING_MODE => ($isFocus ? 'FOCUS' : 'ALIGN'),
	     SAMPLE_COORDS => 'NA',
	     SPIKE_REMOVAL => 'YES',
	     SWITCH_MODE => 'BMSW',
	     ($isFocus ? () : (ALIGN_AXIS => $info{focusAxis} ) ),
	     # Target
	     AZ_RANGE => 'SHORTEST',
	    );


  if ($isFocus) {
    $odf{FOCUS_SHIFT} = $info{focusStep};
  } else {
    $odf{ALIGN_SHIFT} = $info{focusStep};
  }

  # override primary bolometer
  $info{primaryBolometer} = "H7" if ((!defined $info{primaryBolometer})  ||
    $info{primaryBolometer} =~ /LONG|SHORT/);

  # and store it in bolometers
  $info{bolometers} = [ $info{primaryBolometer} ];

  # Populate bits that vary
  for (qw/ General Bols Filter Gain Ints CalChop Target/ ) {
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

  # translate generic project IDs into "SCUBA"
  my $projid = uc($info{PROJECTID});
  if ($projid eq 'JCMTCAL' || $projid eq 'CAL') {
    $projid = 'SCUBA';
  } elsif ($projid eq 'UNKNOWN') {
    # if we do not know the project ID we should leave it
    # unknown unless we know that we have a calibration
    # observation
    # calibration observation is defined by either an unknown
    # target or one of Focus, Pointing, Noise, Skydip
    if ($info{MODE} =~ /(Focus|Pointing|Noise|Skydip)/i ||
	$info{autoTarget} || $info{standard}) {
      $projid = 'SCUBA';
    }
  }

  return ( MSBID => $info{MSBID},
	   PROJECT_ID => $projid,
	   INSTRUMENT => 'SCUBA',
	   DATA_KEPT => 'DEMOD',
	   ENG_MODE  => 'FALSE',
	   '_OBSLABEL' => $info{obslabel},
	 );
}

=item B<getGain>

Get the instrument GAIN. This depends on the target. For bright planets
it should be 1. For everything else it should be 10.

  %gain = $trans->getGain( %info );

=cut

# This code is repeated in SCUBA::ODF

sub getGain {
  my $self = shift;
  my %info = @_;

  # If we are too far away from the tracking centre then we
  # are not really observing the bright source
  my $toofar = 0;
  if (exists $info{OFFSET_DX} && exists $info{OFFSET_DY}) {
    my $mapx = $info{OFFSET_DX};
    my $mapy = $info{OFFSET_DY};

    my $dist = ($mapx**2 + $mapy**2);
    my $threshold = 75*75;
    $toofar = 1 if $dist > $threshold;
  }

  my $target = $info{target};
  my $gain;
  if (defined $target && $target =~ /^(MARS|SATURN|JUPITER|MOON|VENUS)$/i
     && !$toofar) {
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
  my ($xoff, $yoff) = __PACKAGE__->PosAngRot( $dx, $dy, $pa);

  return ( MAP_X => $xoff, MAP_Y => $yoff);
}

=item B<getInts>

Get the number of integrations for the observation.

  %ints = $trans->getInts( %info );

=cut

sub getInts {
  my $self = shift;
  my %info = @_;

  my $nint = $info{nintegrations};

  return ( N_INTEGRATIONS => $nint );
}

=item B<getChop>

Get the chop details

 %chop = $trans->getChop( %info );

If we are doing two bolometer photometry then we do not return
any chop information.

=cut

sub getChop {
  my $self = shift;
  my %info = @_;

  # First see if we are stare mode with two bol chop
  # Two Bol chopping will have at least one comma in the bolometer list.
  if ($info{MODE} =~ /Stare/) {
    my %bols = $self->getBols(%info);
    return () if $bols{BOLOMETERS} =~ /,/;
  }

  # Not two bol photom so must work it out from context
  my %chop;
  $chop{CHOP_THROW} = $info{CHOP_THROW};
  $chop{CHOP_PA} = $info{CHOP_PA};

  throw OMP::Error::TranslateFail("This observing mode requires a CHOP iterator") unless defined $chop{CHOP_PA};

  my $system = $info{CHOP_SYSTEM};
  $chop{CHOP_COORDS} = $self->getOtherCoordSystem($system, %info);

  return %chop;
}

=item B<getCalChop>

Return standard chop settings for non-science targets
such as pointing and focus.

  %chop = $trans->getCalChop( %info );

=cut

sub getCalChop {
  my $self = shift;
  my %info = @_;

  return ( CHOP_COORDS => 'AZ',
	   CHOP_THROW =>  60,
	   CHOP_PA    =>  90,
	 );

}

=item B<getChopDefault>

Return I<either> the specified chop (if there is one) or return
the standard calibration chop.

  %chop = $trans->getChopDefault( %info );

=cut

sub getChopDefault {
  my $self = shift;
  my %info = @_;

  # see if we have a chop
  if (exists $info{CHOP_THROW} && defined $info{CHOP_THROW}) {
    return $self->getChop(%info);
  } else {
    return $self->getCalChop(%info);
  }
}

=item B<getTarget>

Generate target specification from an Astro::Coords object. This is
probably the most complicated step since it should handle orbital
elements and the ability to choose a suitable target.

  %scan = $trans->getScan( %info );

Trailing and leading spaces are removed from target names.
Spaces within a target name are replaced by underscores.

This is a duplicate of the C<SCUBA::ODF> method C<setTarget>.

=cut

sub getTarget {
  my $self = shift;
  my %info = @_;

  # First see if we need to choose a target
  # If we are a standard that always means autoTarget too
  if ($info{autoTarget} || $info{standard}) {
    # Do nothing, this is a function of the queue
    return ();

  }

  # Remove leading and trailing space from target name
  $info{target} =~ s/^\s+//;
  $info{target} =~ s/\s+$//;

  # Can not have spaces in source name
  $info{target}  =~ s/\s+/_/g;

  # Switch on coords type
  my %target;
  if ($info{coordstype} eq 'RADEC') {
    # Ask for J2000
    $target{CENTRE_COORDS} = "RJ";

    # Get the coordinate object
    my $c = $info{coords};

    # RA and DEC in J2000
    $target{RA} = $c->ra( format => 's');
    $target{DEC} = $c->dec( format => 's');

    $target{SOURCE_NAME} = $info{target};

  } elsif ($info{coordstype} eq 'PLANET') {

    # For named targets just use SOURCE_NAME
    # Note that the OT does not support named targets
    # in general. Just planets in particular.
    $target{SOURCE_NAME} = $info{coords}->planet;


  } elsif ($info{coordstype} eq 'ELEMENTS') {

    # moving target
    $target{CENTRE_COORDS} = "PLANET";

    $target{SOURCE_NAME} = $info{target};

    # Get the coordinate object
    my $c = $info{coords};

    # initialise for current time
    my $time = gmtime;
    $c->datetime( $time );


    $c->telescope(new Astro::Telescope('JCMT'));
    #print $c->status;

    $target{RA} = $c->ra_app( format => 's');
    $target{DEC} = $c->dec_app( format => 's');
    $target{MJD1} = $c->datetime->mjd;

    # four hours in the future since this MSB shouldn't really
    # be longer than that.
    #print "XXX Old time: $time\n";
    #print "XXX Old MJD: " . $time->mjd . "\n";
    $time += (4 * ONE_HOUR);
    #print "XXX New time: $time\n";
    #print "XXX Ref: " . ref($time) . "\n";
    #print "XXX New MJD: " . $time->mjd . "\n";
    $c->datetime( $time );
    $target{RA2} = $c->ra_app( format => 's');
    $target{DEC2} = $c->dec_app( format => 's');
    $target{MJD2} = $c->datetime->mjd;

  } elsif ($info{coordstype} eq 'FIXED') {

    # Get the coordinate object
    my $c = $info{coords};

    $target{AZ} = $c->az(format => 's');
    $target{EL} = $c->el(format => 's');
    $target{CENTRE_COORDS} = "AZ";
    $target{SOURCE_NAME} = $info{target};

  } else {
    throw OMP::Error::TranslateFail("This observing mode requires a target rather than coordinates of type $info{coordstype}");
  }


  return %target;
}

=item B<getScan>

Return SCAN details. In future this should also be used to generate
the "best" scan angle for SCUBA. Currently always uses 15 degrees
or the first angle specified from the OT.

  %scan = $trans->getScan( %info );

CHOOSING A SCAN ANGLE IS NOW A FUNCTION OF THE QUEUE
SCUBA::ODF OBJECT

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

  # If nothing specified use the SCUBA symmetry
  @scanpas = (14.5,74.5,-45.5) unless @scanpas;

  # If only one, run with it
  if (scalar(@scanpas) == 1) {
    $scan{SAMPLE_PA} = $scanpas[0];

  } else {
    # We have to choose the best one
    # Do the real choosing at ODF submission time. For now
    # just pass on the allowed angles.
    $scan{_SCAN_ANGLES} = \@scanpas;

  }

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
  my $primary = uc($info{primaryBolometer});

  # Get a flatfield
  my $ff = new SCUBA::FlatField;

  # generate a cleaned up bolometer list
  my @clean = $ff->cleanBolList( $primary, @bols);

  my $bols = join(",",@clean);

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
    $pol{OBSERVING_MODE} = "POLMAP";
  } elsif ($info{MODE} eq 'SpIterStareObs') {
    $pol{OBSERVING_MODE} = "POLPHOT";
    $pol{JIGGLE_NAME} = "JCMTDATA_DIR:NULL_1P0.JIG";

    # override the number of jiggles per switch if we are a photom
    # observation
    $pol{JIGGLE_P_SWITCH} = 4;

  } else {
    throw OMP::Error::TranslateFail("Pol mode only available for map and phot, not $info{MODE}");
  }

  # Waveplates must be stored in an array
  # pending the writing of the file to disk
  # For jiggle we just store them straight in WPLATE_NAME
  # For scan we want to calculate the RA/Dec angles at submission
  if ($info{MODE} eq 'SpIterRasterObs') {
    $pol{_WPLATE_ANGLES} = $info{waveplate};
  } else {
    $pol{WPLATE_NAME} = $info{waveplate};
  }


  # number of measurements is just the number
  # of waveplate positions
  $pol{N_MEASUREMENTS} = scalar(@{$info{waveplate}});

  return %pol;
}

=back

=head2 General SCUBA oddities

=over

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
      throw OMP::Error::TranslateFail("Unknown tracking coord combination: $info{coordstype}");
    }
  } else {
    throw OMP::Error::TranslateFail("Unknown coordinate system :$tcssys");
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
  $tcssys = 'undefined value' unless $tcssys;
  if ($tcssys eq 'TRACKING') {
    $scusys = "LO";
  } elsif ($tcssys eq 'AZEL') {
    $scusys = "AZ";
  } elsif ($tcssys eq 'FPLANE') {
    $scusys = "NA";
  } elsif ($tcssys eq 'SCAN') {
    $scusys = 'SC';
  } else {
    print join("--\n",caller);
    throw OMP::Error::TranslateFail("Unknown TCS system: $tcssys");
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
  my $bol = uc(shift);

  my $sub;
  if ($bol eq 'LONG' or $bol eq 'SHORT' or $bol =~ /^P/) {
    # Its already a sub-instrument
    $sub = $bol;
  } else {
    # A bolometer
    # This needs the flatfield file
    my $ff = new SCUBA::FlatField;

    my %lut = $ff->byname;
    $sub = $lut{$bol}->type
      if exists $lut{$bol};

    throw OMP::Error::TranslateFail("Bolometer $bol not present in any SCUBA sub-instrument")
      unless defined $sub;
  }
  print "Associated sub instrument: $sub\n" if $DEBUG;
  return $sub;
}


=back

=head1 NOTES

Usually called indirectly from L<OMP::Translator|OMP::Translator>.

=head1 SEE ALSO

L<SCUBA::ODF>.

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2002-2003 Particle Physics and Astronomy Research Council.
All Rights Reserved.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful,but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc., 59 Temple
Place,Suite 330, Boston, MA  02111-1307, USA

=cut

1;
