package OMP::Translator::SCUBA2;

=head1 NAME

OMP::Translator::SCUBA2 - translate SCUBA2 observations to configure XML

=head1 SYNOPSIS

  use OMP::Translator::SCUBA2;
  $config = OMP::Translator::SCUBA2->translate( $sp );

=head1 DESCRIPTION

Convert SCUBA-2 MSB into a form suitable for observing. This means
XML suitable for the OCS CONFIGURE action.

=cut

use 5.006;
use strict;
use warnings;
use Carp;

use Data::Dumper;
use List::Util qw/ max min /;
use File::Spec;
use Math::Trig ':pi';

use JAC::OCS::Config;
use JAC::OCS::Config::Error qw/ :try /;
use JCMT::TCS::Pong;

use OMP::Config;
use OMP::Error;
use OMP::General;

use OMP::Translator::SCUBA2Headers;

use base qw/ OMP::Translator::JCMT /;

=head1 METHODS

=over 4

=item B<wiredir>

Returns the wiring directory that should be used for ACSIS.

  $trans->wiredir();

=cut

{
  my $wiredir;
  sub wiredir {
    $wiredir = OMP::Config->getData( 'scuba2_translator.wiredir' )
      unless defined $wiredir;
    return $wiredir;
  }
}

=item B<cfgkey>

Returns the config system name for this translator: scuba2_translator

 $cfgkey = $trans->cfgkey;

=cut

sub cfgkey {
  return "scuba2_translator";
}

=item B<hdrpkg>

Name of the class implementing DERIVED header configuration.

=cut

sub hdrpkg {
  return "OMP::Translator::SCUBA2Headers";
}

=item B<translate_scan_pattern>

Given a requested OT scan pattern, return the pattern name suitable
for use in the TCS.

  $tcspatt = $trans->translate_scan_pattern( $ot_pattern );

SCUBA-2 uses continuous patterns.

=cut

sub translate_scan_pattern {
  my $self = shift;
  my $otpatt = shift;

  # if we do not have a pattern, default to bous
  $otpatt = "boustrophedon" unless defined $otpatt;
  $otpatt = lc($otpatt);

  if ($otpatt eq "raster") {
    return "RASTER";
  } elsif ($otpatt eq "boustrophedon") {
    return "CONTINUOUS_BOUSTROPHEDON";
  } elsif ($otpatt eq "pong") {
    return "CURVY_PONG";
  } elsif ($otpatt eq 'lissajous') {
    return "LISSAJOUS";
  } elsif ($otpatt eq 'ellipse') {
    return "ELLIPSE";
  } else {
    OMP::Error::SpBadStructure->throw("Unrecognized OT scan pattern: '$otpatt'");
  }

}

=item B<header_exclusion_file>

Work out the name of the header exclusion file.

  $xfile = $trans->header_exclusion_file( %info );

Does not check to see if the file is present.

For SCUBA-2, pointing has no special header exclusion requirements
compared to the underlying scan or stare.

=cut

sub header_exclusion_file {
  my $self = shift;
  my %info = @_;

  my $root;
  if ($self->is_private_sequence(%info) ) {
    # flatfield and array tests (and some noise) do not use
    # the rest of the observing system so the exclusion files
    # are the same
    $root = "flatfield";
  } elsif ($info{obs_type} =~ /focus|skydip/) {
    $root = $info{obs_type} . "_". $info{mapping_mode};
  } else {
    # A pointing is just the mapping mode
    # A noise will just be the stare mode since dark and blackbody
    # have been filtered out previously.
    $root = $info{mapping_mode};
  }

  my $xfile = File::Spec->catfile( $self->wiredir,"header","scuba2_". $root . "_exclude");
  return $xfile;
}

=item B<determine_scan_angles>

Given a particular scan area and frontend, determine which angles can be given
to the TCS. 

  ($system,@angles) = $trans->determine_scan_angles( $pattern, %info );

Angles are simple numbers in degrees. Not objects. Returns empty
list if the pattern is not BOUSTROPHEDON or RASTER.

The scanning system is determined by this routine.

=cut

sub determine_scan_angles {
  my $self = shift;
  my $pattern = shift;
  my %info = @_;

  # only calculate angles for bous or raster
  return ($info{SCAN_SYSTEM},) unless $pattern =~ /BOUS|RASTER/i;

  # SCUBA-2 currently needs to be 26.6 deg in NASMYTH.
  my $basepa = 26.6;
  my @scanpas = map { $basepa + (90*$_) } (0..3);

  return ("FPLANE", @scanpas);
}

=item B<is_private_sequence>

Returns true if the sequence only requires the instrument itself
to be involved. If true, the telescope, SMU and RTS are not involved
and so do not generate configuration XML.

  $trans->is_private_sequence( %info );

For SCUBA-2 returns true for observations in the dark or using the blackbody,
false otherwise.

=cut

sub is_private_sequence {
  my $self = shift;
  my %info = @_;
  if ($self->is_dark_or_blackbody(%info)) {
    return 1;
  }
  return 0;
}

=item B<is_with_rts_only>

Returns true if the observation is a sequence that just involves the
instrument and the RTS.

 $trans->is_with_rts_only( %info );

Similar to is_private_sequence except the RTS can be included (but
not the telescope). Used to determine whether tasks other than the
instrument and RTS should be configured.

Returns false if other tasks are required.

Returns false if only the instrument is required.

=cut

sub is_only_with_rts {
  my $self = shift;
  my %info = @_;

  # so we only return true if we are a dark-noise/blackbody or
  # flatfield-dark/blackbody that should use the RTS
  if ( $self->is_dark_or_blackbody(%info) ) {
    # so now query the config system to see how to handle this
    my $key = $info{obs_type};
    if ($info{obs_type} =~ /^flatfield/) {
      $key = "flatfield";
    }
    $key .= "_use_rts";
    return OMP::Config->getData($self->cfgkey.".". $key );
  }
  return 0;
}

=item B<is_dark_or_blackbody>

Returns true if this is an observation that is in the dark or
uses a blackbody source but does not involve another component.

  $trans->is_dark_or_blackbody( %info );

=cut

sub is_dark_or_blackbody {
  my $self = shift;
  my %info = @_;
  if ($info{obs_type} =~ /^flatfield/ ) {
    if ($info{flatSource} =~ /^(dark|blackbody)$/i) {
      return 1;
    }
  } elsif ($info{obs_type} eq 'noise') {
    if ($info{noiseSource} =~ /^(dark|blackbody)$/i) {
      return 1;
    }
  }

  return 0;
}


=item B<handle_special_modes>

Special modes such as POINTING or FOCUS are normal observations that
are modified to do something in addition to normal behaviour. For a
pointing this simply means fitting an offset.

  $cfg->handle_special_modes( \%obs );

Since the Observing Tool is setup such that pointing and focus
observations do not necessarily inherit observing parameters from the
enclosing observation and they definitely do not include a
specification on chopping scheme.

Array Tests are converted to a special flatfield observation.

=cut

sub handle_special_modes {
  my $self = shift;
  my $info = shift;

  # The trick is to fill in the blanks

  # POINTING and FOCUS
  if ($info->{obs_type} =~ /pointing|focus/) {

    # Get the integration time in seconds
    my $exptime = OMP::Config->getData($self->cfgkey.".".
                                       $info->{obs_type}.
                                       "_integration");

    if ($self->verbose) {
      print {$self->outhdl} "Determining ".uc($info->{obs_type}).
        " parameters...\n";
      print {$self->outhdl} "\tIntegration time: $exptime secs\n";
    }

    if ($info->{mapping_mode} eq 'scan') {
      # do this as a point source
      $info->{scanPattern} = $info->{obs_type};
      $info->{sampleTime} = $exptime;

    } elsif ($info->{mapping_mode} eq 'stare') {
      $info->{secsPerCycle} = $exptime;
    } elsif ($info->{mapping_mode} eq 'dream') {
      $info->{sampleTime} = $exptime;
    }

  } elsif ($info->{obs_type} =~ /array_tests/) {
    # Array Tests is currently shorthand for a short flatfield
    if ($self->verbose) {
      print {$self->outhdl} "Array tests implemented as short flatfield.\n";
    }

    $info->{obs_type} = "flatfield";
    $info->{is_quick} = 1;
    $info->{secsPerCycle} = OMP::Config->getData($self->cfgkey.".".
                                                 "flatfield_quick_integration");
    $info->{flatSource} = "DARK";

  } elsif ($info->{obs_type} =~ /noise/) {
    $info->{secsPerCycle} = OMP::Config->getData($self->cfgkey.".".
                                                 "noise_integration");

  } elsif ($info->{obs_type} =~ /flatfield/) {
    if ($self->verbose) {
      print {$self->outhdl} "Setting integration time for ".$info->{obs_type}. " observation\n";
    }
    $info->{secsPerCycle} = OMP::Config->getData($self->cfgkey.".".
                                                 "flatfield_integration");
  }

  if ($info->{mapping_mode} eq 'scan' ) {

    # fix up point source scanning
    if ($info->{scanPattern} eq 'Point Source' ||
       $info->{scanPattern} =~ /pointing|focus/ ) {
      my $smode = $info->{scanPattern};
      if ($info->{scanPattern} =~ /Source/) {
        $smode = 'pntsrc';
      }

      if ($self->verbose) {
        print {$self->outhdl} "Defining ".$info->{scanPattern}." scan map from config.\n";
      }

      my $key = ".scan_". $smode . "_";
      $info->{scanPattern} = OMP::Config->getData($self->cfgkey. $key .
                                                  "pattern");
      $info->{MAP_HEIGHT} = OMP::Config->getData($self->cfgkey. $key .
                                                 "map_height");
      $info->{MAP_WIDTH} = OMP::Config->getData($self->cfgkey. $key .
                                                "map_width");
      $info->{SCAN_VELOCITY} = OMP::Config->getData($self->cfgkey. $key .
                                                    "velocity");
      $info->{SCAN_DY} = OMP::Config->getData($self->cfgkey. $key .
                                              "scan_dy");

      $info->{SCAN_SYSTEM} = "FPLANE";
      $info->{MAP_PA} = 0;

    } elsif ($info->{scanPattern} =~ /liss|pong/i) {

      my $scan_dy = eval { OMP::Config->getData( $self->cfgkey.
                                                 ".scan_pong_scan_dy") };
      my $scan_vel = eval { OMP::Config->getData( $self->cfgkey.
                                                  ".scan_pong_velocity") };

      if (defined $scan_dy) {
        if ($self->verbose && defined $info->{SCAN_DY}) {
          print {$self->outhdl} "\tOverriding scan spacing given in the OT.".
            " Changing $info->{SCAN_DY} to $scan_dy arcsec\n";
        }
        $info->{SCAN_DY} = $scan_dy;
      }
      if (defined $scan_vel) {
        if ($self->verbose && defined $info->{SCAN_VELOCITY} ) {
          print {$self->outhdl} "\tOverriding scan velocity given in the OT.".
            " Changing $info->{SCAN_VELOCITY} to $scan_vel arcsec/sec\n";
        }
        $info->{SCAN_VELOCITY} = $scan_vel;
      }

    }


  }

  return;
}

=back

=head1 CONFIG GENERATORS

These routine configure the specific C<JAC::OCS::Config> objects.

=over 4

=item B<frontend_backend_config>

Configure the SCUBA-2 specific instrument XML.

  $trans->frontend_backend_config( $cfg, %$obs );

=cut

sub frontend_backend_config {
  my $self = shift;
  my $cfg = shift;
  my %info = @_;

  my $sc = JAC::OCS::Config::SCUBA2->new();

  # start with just a mask
  my %mask = $self->calc_receptor_or_subarray_mask( $cfg, %info );
  $sc->mask(%mask);
  $cfg->scuba2( $sc );
}

=item B<jos_config>

The JOS configurations for SCUBA-2 have little in common with the
ACSIS versions so this is an independent implementation.

  $trans->jos_config( $cfg, %info );

=cut

sub jos_config {
  my $self = shift;
  my $cfg = shift;
  my %info = @_;

  my $jos = new JAC::OCS::Config::JOS();

  # Basics
  $jos->step_time( $self->step_time($cfg, %info) );
  $jos->start_index( 1 );

  # Allowed JOS recipes seem to be
  #   scuba2_scan
  #   scuba2_dream
  #   scuba2_stare
  #   scuba2_skydip
  #   scuba2_flatField
  #   scuba2_noise

  my $recipe = $info{obs_type};
  if ($info{obs_type} eq 'science') {
    $recipe = $info{observing_mode};
  }
  # prepend scuba2
  $recipe = "scuba2_".$recipe;

  # and store it
  $jos->recipe( $recipe );

  # Time between darks depends on observing mode (but not _pol, _blackbody)
  my $obsmode_strip = $info{observing_mode};
  $obsmode_strip =~ s/_.*$//;
  my $tbdark = OMP::Config->getData( "scuba2_translator.time_between_dark_".
                                     $obsmode_strip ) / $jos->step_time;

  $jos->steps_btwn_dark( $tbdark );

  # Length of dark is fixed for all except observations that 
  # have a noiseSource of "DARK" or flatsource of "DARK"
  if ( (exists $info{noiseSource} && $info{noiseSource} =~ /dark/i) ||
       (exists $info{flatSource} && $info{flatSource} =~ /dark/i) ) {
    # want to set n_calsamples ourselves
  } else {
    my $darklen = OMP::Config->getData( $self->cfgkey .".dark_time" );
    $jos->n_calsamples( $darklen / $jos->step_time );
  }

  if ($self->verbose) {
    print {$self->outhdl} "Generic JOS parameters:\n";
    print {$self->outhdl} "\tStep time: ".$jos->step_time." secs\n";
    print {$self->outhdl} "\tSteps between darks: ". $jos->steps_btwn_dark().
      "\n";
    print {$self->outhdl} "\tDark duration: ".$jos->n_calsamples(). " steps\n"
      if $jos->n_calsamples;
  }

  if ($info{obs_type} =~ /^skydip/) {

    if ($self->verbose) {
      print {$self->outhdl} "Skydip JOS parameters:\n";
    }

    if ($info{observing_mode} =~ /^stare/) {
      # need JOS_MIN since we have multiple offsets
      my $integ = OMP::Config->getData( $self->cfgkey.'.skydip_integ' );
      $jos->jos_min( POSIX::ceil($integ / $jos->step_time));

      if ($self->verbose) {
        print {$self->outhdl} "\tSteps per discrete elevation: ". $jos->jos_min()."\n";
      }

      # make sure we always do a dark between positions
      $jos->steps_btwn_dark( 1 );

    } else {
      # scan so JOS_MIN is 1
      $jos->jos_min(1);

      if ($self->verbose) {
        print {$self->outhdl} "\tContinuous scanning skydip\n";
      }
    }

  } elsif ($info{obs_type} =~ /^flatfield/) {

    # Sort out prefix into config system
    my $pre = ".". $info{obs_type} . ($info{is_quick} ? "_quick" : "") . "_";

    # This is the integration time directly from the config file
    # use it for N_CALSAMPLES if we are dark else use it for JOS_MIN
    my $inttime = $info{secsPerCycle};
    my $nsteps = OMP::General::nint( $inttime / $jos->step_time );

    if ( $info{flatSource} =~ /dark/i) {
      $jos->n_calsamples( $nsteps );
      $jos->jos_min( 0 );
    } else {
      $jos->jos_min( $nsteps );
    }
    $jos->num_cycles( OMP::Config->getData($self->cfgkey. $pre .
                                           "num_cycles"));

    # next set depends on flatfield mode
    my @keys;
    if ($info{flatSource} =~ /^blackbody$/i) {
      @keys = (qw/ bb_temp_start bb_temp_step bb_temp_wait shut_frac /);
    } elsif ($info{flatSource} =~ /^(dark|zenith|sky)$/i) {
      @keys = (qw/ heat_cur_step /);

      # Shutter location is hard-coded
      if ($info{flatSource} =~ /^dark$/i) {
        $jos->shut_frac( 0.0 );
      } else {
        $jos->shut_frac( 1.0 );
      }

    } else {
      throw OMP::Error::FatalError("Unrecognized flatfield source: $info{flatSource}");
    }

    # read the values from the config file
    for my $k (@keys) {
      my $value = OMP::Config->getData($self->cfgkey. $pre .
                                       $k);
      $jos->$k( $value );
    }

    if ($self->verbose) {
      print {$self->outhdl} "\tFlatfield source: $info{flatSource}\n";
    }

  } elsif ($info{obs_type} eq 'noise') {

    # see if the blackbody is needed
    if ($info{noiseSource} =~ /^blackbody$/i) {
      my $bbtemp = OMP::Config->getData($self->cfgkey .".noise_bbtemp");
      $jos->bb_temp_start( $bbtemp );
    }

    # Requested duration of noise observation
    my $inttime = $info{secsPerCycle};

    # convert total integration time to steps
    my $nsteps = $inttime / $jos->step_time;

    # The whole point of noise is to have a continuous time series
    # so we never split it up
    my $num_cycles = 1;
    my $jos_min = OMP::General::nint( $nsteps / $num_cycles );
    $jos->num_cycles($num_cycles);

    if ($self->verbose) {
      print {$self->outhdl} ucfirst($info{obs_type})." JOS parameters:\n";
      print {$self->outhdl} "\tNoise source: $info{noiseSource}\n";
      print {$self->outhdl} "\tRequested integration time: $inttime secs\n";
      print {$self->outhdl} "\tNumber of cycles calculated: $num_cycles\n";
      print {$self->outhdl} "\tActual integration time: ".
        ($jos_min * $num_cycles * $jos->step_time)." secs\n";
    }

    # The DARK mode is special since we never open the shutter
    if ($info{noiseSource} eq 'DARK') {
      $jos->jos_min(0);
      $jos->n_calsamples( $jos_min );
      $jos->shut_frac( 0.0 );
    } else {
      $jos->jos_min($jos_min);
      $jos->shut_frac( 1.0 );
    }

  } elsif ($info{mapping_mode} eq 'stare'
          || $info{mapping_mode} eq 'dream') {
    # STARE and DREAM have the same calculations because the
    # array is fully sampled at 850 microns so the exposure
    # time per pixel is the same even though the SMU is moving.
    # The only difference is that the key for integration time
    # is secsPerCycle (for historical reasons) for STARE and
    # sampleTime for DREAM.
    my $inttime;
    for my $key (qw/ secsPerCycle sampleTime/) {
      if (exists $info{$key}) {
        $inttime = $info{$key};
        last;
      }
    }
    OMP::Error::FatalError->throw("Could not determine integration time for $info{mapping_mode} observation") unless defined $inttime;

    # Need an obsArea for number of microsteps
    my $nms = 1;
    my $tcs = $cfg->tcs;
    throw OMP::Error::FatalError('for some reason TCS setup is not available. This can not happen') unless defined $tcs;
    my $obsArea = $tcs->getObsArea();
    throw OMP::Error::FatalError('for some reason TCS obsArea is not available. This can not happen') unless defined $obsArea;

    # This time should be spread over the number of microsteps
    my @ms = $obsArea->microsteps;
    $nms = (@ms ? @ms : 1);

    # convert total integration time to steps
    my $nsteps = $inttime / $jos->step_time;

    # Spread over microsteps
    $nsteps /= $nms;

    # split into chunks
    my $num_cycles = POSIX::ceil( $nsteps / $tbdark );
    my $jos_min = OMP::General::nint( $nsteps / $num_cycles );

    $jos->jos_min($jos_min);
    $jos->num_cycles($num_cycles);

    if ($self->verbose) {
      print {$self->outhdl} uc($info{mapping_mode})." JOS parameters:\n";
      print {$self->outhdl} "\tRequested integration time per pixel: $inttime secs\n";
      print {$self->outhdl} "\tNumber of steps per microstep/offset: $jos_min\n";
      print {$self->outhdl} "\tNumber of cycles calculated: $num_cycles\n";
      print {$self->outhdl} "\tActual integration time per stare position: ".
        ($jos_min * $num_cycles * $nms * $jos->step_time)." secs\n";
    }
  } elsif ($info{mapping_mode} eq 'scan') {
    # The aim here is to use the minimum number of sequences
    # to get the correct map area. For "point source" it is easy
    # because we assume that the time requested is the length
    # of the sequence. For normal scan maps we are given an area
    # and a number of repeats so we need to know how long that will be.
    # We end up with a JOS_MIN value. In principal we have to ensure
    # that we break at steps_between_darks.

    if ($self->verbose) {
      print {$self->outhdl} "Scan map JOS parameters\n";
    }

    # Since the TCS works in integer times-round-the-map
    # Need to know the map area
    my $tcs = $cfg->tcs;
    throw OMP::Error::FatalError('for some reason TCS setup is not available. This can not happen')
      unless defined $tcs;
    my $obsArea = $tcs->getObsArea();
    throw OMP::Error::FatalError('for some reason TCS obsArea is not available. This can not happen')
      unless defined $obsArea;

    # need to calculate the length of a pong. Should be in a module somewhere. Code in JAC::OCS::Config.
    my %mapping_info = ($obsArea->scan, $obsArea->maparea );
    my $duration_per_area;
    if ($info{scanPattern} =~ /liss|pong/i) {
      $duration_per_area = JCMT::TCS::Pong::get_pong_dur( %mapping_info );
    } elsif ($info{scanPattern} =~ /bous/i) {
      my $pixarea = $mapping_info{DY} * $mapping_info{VELOCITY};
      my $maparea = $mapping_info{WIDTH} * $mapping_info{HEIGHT};
      $duration_per_area = ($maparea / $pixarea) * $jos->step_time;
    } elsif ($info{scanPattern} =~ /ell/i) {
      my $rx = $mapping_info{WIDTH};
      my $ry = $mapping_info{HEIGHT};
      # Calculate an approximate "radius" for the ellipse
      my $r = sqrt( ( $rx*$rx + $ry*$ry ) / 2.0 );
      my $perimeter = 2.0 * pi * $r;
      $duration_per_area = $perimeter / $mapping_info{VELOCITY};
    } else {
      throw OMP::Error::FatalError("Unrecognized scan pattern: $info{scanPattern}");
    }

    if ($self->verbose) {
      print {$self->outhdl} "\tEstimated time to cover the map area once: $duration_per_area sec\n";
    }

    my $nsteps;
    if (exists $info{sampleTime} && defined $info{sampleTime}) {
      # Specify the length of the sequence
      $nsteps = $info{sampleTime} / $jos->step_time;
      if ($self->verbose) {
        print {$self->outhdl} "\tScan map executing for a specific time. Not map coverage\n";
        print {$self->outhdl} "\tTotal duration requested for scan map: $info{sampleTime} secs.\n";
      }

    } else {
      my $nrepeats = ($info{nintegrations} ? $info{nintegrations} : 1 );

      if ($self->verbose) {
        print "\tNumber of repeats of map area requested: $nrepeats\n";
      }
      $nsteps = ($nrepeats * $duration_per_area) / $jos->step_time;
    }

    # This calculation may well be inefficient given the TCS requirement
    # to use an integer number of scan areas in a sequence. It could be tricky
    # if we want 5 repeats but do them as 2 sets of 3 or 3 sets of 2. We tend
    # to hope that steps_between_darks will be so high that this is irrelevant.

    # steps between darks must be at least the duration_per_area
    # otherwise the num_cycles calculation means that you end up with
    # too many repeats
    my $steps_per_pass = $duration_per_area / $jos->step_time;
    $tbdark = max( $tbdark, $steps_per_pass );

    # Maximum length of a sequence
    my $jos_max = OMP::Config->getData($self->cfgkey . ".jos_max" );

    # for pointings we need to be able to control the number of repeats
    # dynamically in the JOS so we go for the less optimal solution
    # of causing the map to be split up into chunks
    my $num_cycles;
    my $jos_min;
    my $tot_time;
    if ($info{obs_type} =~ /point|focus/i) {
      my $minlen = OMP::Config->getData($self->cfgkey .".".$info{obs_type}."_min_cycle_duration");
      $num_cycles = POSIX::ceil( $nsteps / $steps_per_pass );

      my $div = POSIX::ceil( min( $nsteps*$jos->step_time, $minlen) / $duration_per_area);
      $num_cycles = POSIX::ceil( $num_cycles / $div );

      # No point requesting more steps than we wanted originally
      $jos_min = min( $nsteps, $div * $steps_per_pass);
    } else {
      $num_cycles = POSIX::ceil( $nsteps / $tbdark );
      $jos_min = OMP::General::nint( $nsteps / $num_cycles );
    }

    if ($jos_min > $jos_max) {
      # We have a problem
      my $mult = POSIX::ceil( $jos_min / $jos_max );
      $jos_min /= $mult;
      $num_cycles *= $mult;
      if ($self->verbose) {
        print {$self->outhdl} "\tSequence too long. Scaling down by factor of $mult\n";
      }
    }

    # for now set steps between dark to the JOS_MIN, otherwise the JOS
    # will try to get clever and multiply up the NUM_CYCLES
    # For focus we definitely do not want darks between the focus positions though.
    $jos->steps_btwn_dark( $jos_min )
      unless $info{obs_type} =~ /focus/;

    $tot_time = $num_cycles * $jos_min * $jos->step_time;
    $jos->jos_min( $jos_min );
    $jos->num_cycles( $num_cycles );

    if ($self->verbose) {
      print {$self->outhdl} "\tNumber of steps in scan map sequence: $jos_min\n";
      print {$self->outhdl} "\tNumber of repeats: $num_cycles\n";
      print {$self->outhdl} "\tTime spent mapping: $tot_time sec\n";
    }

  }

  # Non science observing types
  if ($info{obs_type} =~ /focus/ ) {
    $jos->num_focus_steps( $info{focusPoints} );
    # Focus step is missing from OT at the moment.
    my $stepsize = $info{focusStep};
    if (!defined $stepsize) {
      if ($info{focusAxis} =~ /z/i) {
        $stepsize = 0.3;
      } else {
        $stepsize = 1.0;
      }
    }
    $jos->focus_step( $stepsize );
    $jos->focus_axis( $info{focusAxis} );
  }

  # store it
  $cfg->jos( $jos );

}

=item B<rotator_config>

There is no rotator for SCUBA-2.

=cut

sub rotator_config {
}

=item B<need_offset_tracking>

Returns true if we need to use a particular sub array for this
observation.

  $need = $trans->need_offset_tracking( $cfg, %info );

=cut

sub need_offset_tracking {
  # with only 2 subarrays we can be sure that we are meant to
  # use them
  return 1;
}

=item B<step_time>

Step time for SCUBA-2 is usually fixed at 200 Hz.

 $rts = $trans->step_time( $cfg, %info );

Flatfield and Noise can be configured independently.

=cut

sub step_time {
  my $self = shift;
  my $cfg = shift;
  my %info = @_;

  # Try obs type version first
  my $step;
  if ($info{obs_type} =~ /^(flatfield|noise)$/) {
    my $q = ($info{is_quick} ? "_quick" : "" );
    $step = eval { OMP::Config->getData( $self->cfgkey . ".step_time_".
                                         $info{obs_type} . $q) };
  }
  $step = OMP::Config->getData( $self->cfgkey . '.step_time' )
    unless defined $step;
  return $step;
}

=item B<velOverride>

SCUBA-2 has no requirement for velocity information so return
empty list.

=cut

sub velOverride {
  return ();
}

=item B<backend>

Returns the backend name. The name is suitable for use in
filenames that are targetted for a specific translator.
SCUBA2 in this case.

=cut

sub backend {
  return "SCUBA2";
}

=item B<determine_map_and_switch_mode>

Calculate the mapping mode, switching mode and observation type from
the Observing Tool mode and switching string.

  ($map_mode, $sw_mode) = $trans->determine_observing_summary( $mode, $sw );

Called from the C<observing_mode> method.  See
C<OMP::Translator::JCMT::observing_mode> method for more details.

=cut

sub determine_map_and_switch_mode {
  my $self = shift;
  my $mode = shift;
  my $swmode = shift;

  my ($mapping_mode, $switching_mode);

  my $obs_type = 'science';

  # Supplied switch mode is not important for scuba-2
  if ($mode eq 'SpIterRasterObs') {
    $mapping_mode = 'scan';
  } elsif ($mode eq 'SpIterStareObs') {
    $mapping_mode = 'stare';
  } elsif ($mode eq 'SpIterDREAMObs') {
    $mapping_mode = 'dream';
  } elsif ($mode eq 'SpIterPointingObs') {
    $mapping_mode = OMP::Config->getData($self->cfgkey.".pointing_obsmode");
    $obs_type = 'pointing';
  } elsif ($mode eq 'SpIterFocusObs') {
    $mapping_mode = OMP::Config->getData($self->cfgkey.".focus_obsmode");
    $obs_type = 'focus';
  } elsif ($mode eq 'SpIterFlatObs') {
    $obs_type = "flatfield";
    $mapping_mode = "stare";
  } elsif ($mode eq 'SpIterArrayTestObs') {
    $obs_type = 'array_tests';
    $mapping_mode = 'stare';
  } elsif ($mode eq 'SpIterNoiseObs') {
    $obs_type = 'noise';
    $mapping_mode = 'stare';
  } elsif ($mode eq 'SpIterSkydipObs') {
    my $sdip_mode = OMP::Config->getData( $self->cfgkey . ".skydip_mode" );
    if ($sdip_mode =~ /^cont/) {
      $mapping_mode = 'scan';
    } elsif ($sdip_mode =~ /^dis/) {
      $mapping_mode = "stare";
    } else {
      OMP::Error::TranslateFail->throw("Skydip mode '$sdip_mode' not recognized");
    }
    $switching_mode = 'none';
    $obs_type = 'skydip';
  } else {
    throw OMP::Error::TranslateFail("Unable to determine observing mode from observation of type '$mode'");
  }

  # switch mode
  my %SW = ( scan => 'self',
             stare => 'none',
             dream => 'self',);
  $switching_mode = $SW{$mapping_mode}
    unless defined $switching_mode;

  throw OMP::Error::TranslateFail("Unable to determine switch mode from map mode of $mapping_mode")
    unless defined $switching_mode;

  return ($mapping_mode, $switching_mode, $obs_type);
}

=item B<determine_inbeam>

Decide what should be in the beam. Empty if "DARK", blackbody does not
allow FTS.

  @inbeam = $trans->determine_inbeam( %info );

=cut

sub determine_inbeam {
  my $self = shift;
  my %info = @_;
  my @inbeam;

  # see if we have a source in the beam
  my $source;
  if ($info{obs_type} =~ /^flatfield/) {
    $source = lc($info{flatSource});
  } elsif (exists $info{noiseSource}) {
    $source = lc($info{noiseSource});
  }

  if (defined $source) {
    if ($source =~ /blackbody/i) {
      push(@inbeam, "blackbody");
    } elsif ($source =~ /dark/i) {
      # can not be anything in the beam for a dark
      return ();
    }
  }

  # get base class values
  push(@inbeam, $self->SUPER::determine_inbeam(%info));
  
  return @inbeam;
}

=back

=head1 CONFIGURATION XML

The format of the configuration XML is outlined in JAC document
OCS/ICD/001.

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

Copyright (C) 2007-2008 Science and Technology Facilities Council.
Copyright (C) 2003-2007 Particle Physics and Astronomy Research Council.
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
