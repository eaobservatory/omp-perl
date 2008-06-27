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

use File::Spec;
use JAC::OCS::Config;
use JAC::OCS::Config::Error qw/ :try /;

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
  if ($info{obs_type} =~ /focus|skydip/) {
    $root = $info{obs_type} . "_". $info{mapping_mode};
  } elsif ($info{obs_type} eq 'flatfield' ||
	   $info{obs_type} eq 'array_tests' ) {
    # flatfield and array tests do not use
    # the rest of the observing system so the exclusion files
    # are the same
     $root = "flatfield";
  } else {
    # A pointing is just the mapping mode
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

For SCUBA-2 returns true for Flatfield and Array Tests, false otherwise.

=cut

sub is_private_sequence {
  my $self = shift;
  my %info = @_;
  if ($info{obs_type} eq 'flatfield' ||
      $info{obs_type} eq 'array_tests' ) {
    return 1;
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
      $info->{scanPattern} = 'Point Source';
      $info->{sampleTime} = $exptime;

    } elsif ($info->{mapping_mode} eq 'stare') {
      $info->{secsPerCycle} = $exptime;
    } elsif ($info->{mapping_mode} eq 'dream') {
      $info->{sampleTime} = $exptime;
    }

  } elsif ($info->{obs_type} =~ /array_tests/) {
      $info->{secsPerCycle} = OMP::Config->getData($self->cfgkey.".".
						   "array_tests_integration");
  }

  # fix up point source scanning
  if ($info->{mapping_mode} eq 'scan' && 
      $info->{scanPattern} eq 'Point Source') {

    $info->{scanPattern} = OMP::Config->getData($self->cfgkey.
                                                ".scan_pntsrc_pattern");
    $info->{MAP_HEIGHT} = OMP::Config->getData($self->cfgkey.
                                                ".scan_pntsrc_map_height");
    $info->{MAP_WIDTH} = OMP::Config->getData($self->cfgkey.
                                                ".scan_pntsrc_map_width");
    $info->{SCAN_VELOCITY} = OMP::Config->getData($self->cfgkey.
                                                ".scan_pntsrc_velocity");
    $info->{SCAN_DY} = OMP::Config->getData($self->cfgkey.
                                                ".scan_pntsrc_scan_dy");

    $info->{SCAN_SYSTEM} = "FPLANE";
    $info->{MAP_PA} = 0;

    if ($self->verbose) {
      print {$self->outhdl} "Defining point source scan map from config.\n";
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
  $jos->step_time( $self->step_time );

  # Allowed JOS recipes seem to be
  #   scuba2_scan
  #   scuba2_dream
  #   scuba2_stare
  #   scuba2_skydip
  #   scuba2_flatField
  #   scuba2_noise

  my $recipe = $info{obs_type};
  if ($info{obs_type} eq 'array_tests') {
    $recipe = "stare";
  } elsif ($info{obs_type} eq 'science') {
    $recipe = $info{observing_mode};
  }
  # prepend scuba2
  $recipe = "scuba2_".$recipe;

  # and store it
  $jos->recipe( $recipe );

  # Time between darks depends on observing mode
  my $tbdark = OMP::Config->getData( "scuba2_translator.time_between_dark_".
                                     $info{observing_mode} ) / $jos->step_time;

  $jos->steps_btwn_dark( $tbdark );

  # Length of dark is fixed
  my $darklen = OMP::Config->getData( $self->cfgkey .".dark_time" );
  $jos->n_calsamples( $darklen / $jos->step_time );

  if ($self->verbose) {
    print {$self->outhdl} "Generic JOS parameters:\n";
    print {$self->outhdl} "\tStep time: ".$jos->step_time." secs\n";
    print {$self->outhdl} "\tSteps between darks: ". $jos->steps_btwn_dark().
      "\n";
    print {$self->outhdl} "\tDark duration: ".$jos->n_calsamples(). " steps\n";
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

    } else {
      # scan so JOS_MIN is 1
      $jos->jos_min(1);

      if ($self->verbose) {
        print {$self->outhdl} "\tContinuous scanning skydip\n";
      }
    }

  } elsif ($info{obs_type} =~ /^flatfield/) {

    # need some stuff in here

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

    # Need an obsArea for number of microsteps (except for array tests)
    my $nms = 1;
    if ($info{obs_type} ne 'array_tests') {
      my $tcs = $cfg->tcs;
      throw OMP::Error::FatalError('for some reason TCS setup is not available. This can not happen') unless defined $tcs;
      my $obsArea = $tcs->getObsArea();
      throw OMP::Error::FatalError('for some reason TCS obsArea is not available. This can not happen') unless defined $obsArea;

      # This time should be spread over the number of microsteps
      my @ms = $obsArea->microsteps;
      $nms = (@ms ? @ms : 1);
    }

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
    # in most cases, we set jos_min to 1 and the number of cycles
    # to be the number of map area repeats. The TCS knows when to go to 
    # a dark. If we have an explicit sampleTime though, we use that
    # for JOS_MIN - it indicates that the OT has requested a particular
    # amount of time doing the observation not a particular number of
    # complete map areas. This is assumed to be used in point source mode.

    if ($self->verbose) {
      print {$self->outhdl} "Scan map JOS parameters\n";
    }

    if (exists $info{sampleTime} && defined $info{sampleTime}) {
      my $nsteps = $info{sampleTime} / $jos->step_time;
      my $num_cycles = POSIX::ceil( $nsteps / $tbdark );
      my $jos_min = OMP::General::nint( $nsteps / $num_cycles );
      $jos->jos_min( $jos_min );
      $jos->num_cycles( $num_cycles );

      if ($self->verbose) {
        print {$self->outhdl} "\tScan map executing for a specific time. Not map coverage\n";
        print {$self->outhdl} "\tTotal duration of scan map: $info{sampleTime} secs.\n";
        print {$self->outhdl} "\tNumber of steps in scan map sequence: $jos_min\n";
        print {$self->outhdl} "\tNumber of repeats: $num_cycles\n";
      }
    } else { 

      # jos_min is always 1 and num_cycles is the number of times round
      # the map. The TCS will work out when to do the dark.
      $jos->jos_min(1);
      $jos->num_cycles($info{nintegrations} ? $info{nintegrations} : 1);
      
      if ($self->verbose) {
        print {$self->outhdl} "\tNumber of repeats of map area: ".
          $jos->num_cycles."\n";
      }
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

=cut

sub step_time {
  my $self = shift;
  return OMP::Config->getData( $self->cfgkey . '.step_time' );
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
