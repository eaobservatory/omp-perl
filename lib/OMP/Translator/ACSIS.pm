package OMP::Translator::ACSIS;

=head1 NAME

OMP::Translator::ACSIS - translate ACSIS heterodyne observations to Configure XML

=head1 SYNOPSIS

    use OMP::Translator::ACSIS;
    $config = OMP::Translator::ACSIS->new->translate($sp);

=head1 DESCRIPTION

Convert ACSIS MSB into a form suitable for observing. This means
XML suitable for the OCS CONFIGURE action.

=cut

use 5.006;
use strict;
use warnings;
use Carp;

use Data::Dumper;

use File::Spec;
use Astro::Coords::Offset;
use List::Util qw/min max all sum/;
use Scalar::Util qw/blessed/;
use POSIX qw/ceil floor/;
use Math::Trig qw/rad2deg/;
use Storable;

use JCMT::ACSIS::HWMap;
use JAC::OCS::Config;
use JAC::OCS::Config::Error qw/:try/;

use OMP::Config;
use OMP::Error;
use OMP::General;
use OMP::Range;

use OMP::Translator::Headers::ACSIS;

use base qw/OMP::Translator::JCMT/;

# Real debugging messages. Do not confuse with debug() method
our $DEBUG = 0;

# Fast mode: omit calculation of grid, just assume 1x1
our $FAST = 0;

# Version number
our $VERSION = '2.000';

# Maximum size of a cube per gridder (slice) in pixels
my $max_slice_size_in_gb = 0.5;
my $max_slice_size_in_bytes = $max_slice_size_in_gb * 1024 * 1024 * 1024;
my $MAX_SLICE_NPIX = $max_slice_size_in_bytes / 4.0;

# Lookup table to calculate the LO2 frequencies.
# Indexed simply by subband bandwidth
our %BWMAP = (
    '250MHz' => {
        # Parking frequency, first channel (Hz)
        f_park => 2.5E9,
    },
    '1GHz' => {
        # Parking frequency, first channel (Hz)
        f_park => 2.0E9,
    },
);

# This is the gridder/reducer layout selection
my %ACSIS_Layouts = (
    RXA => 's1r1g1',
    RXB => 's2r2g1',
    RXWB => 's2r2g1',
    RXWD => 's2r2g1',

    ALAIHI => 's2r2g1',
    UU => 's4r4g1',
    AWEOWEO => 's4r4g1',
    KUNTUR => 's4r4g1',

    HARP => 's8r8g1',
);

# LO2 synthesizer step, hard-wired
our $LO2_INCR = 0.5E6;

# LO2 tuning range for consistency checks
our $LO2_RANGE = OMP::Range->new(Min => 5.7E9, Max => 10.5E9);

=head1 METHODS

=head2 General Methods

=over 4

=item B<cfgkey>

Returns the config system name for this translator: acsis_translator

    $cfgkey = $trans->cfgkey;

=cut

sub cfgkey {
    return "acsis_translator";
}

=item B<hdrpkg>

Name of the class implementing DERIVED header configuration.

=cut

sub hdrpkg {
    return 'OMP::Translator::Headers::ACSIS';
}

=item B<translate_scan_pattern_lut>

Returns a lookup table (hash) mapping OT scan pattern name (in lower
case) to the corresponding PTCS scan pattern name.

    %lut = $trans->translate_scan_pattern_lut();

ACSIS uses the discrete patterns.

=cut

sub translate_scan_pattern_lut {
    my $self = shift;

    # Get the base class lut and merge it with the local overrides
    return ($self->SUPER::translate_scan_pattern_lut(),
        boustrophedon => "DISCRETE_BOUSTROPHEDON",
    );
}

=item B<header_exclusion_file>

Work out the name of the header exclusion file.

    $xfile = $trans->header_exclusion_file(%info);

Does not check to see if the file is present.

=cut

sub header_exclusion_file {
    my $self = shift;
    my %info = @_;

    my $root;
    if ($info{obs_type} =~ /pointing|focus|skydip/) {
        $root = $info{obs_type};
    }
    else {
        $root = $info{observing_mode};
        # scan_pol and pol are the same thing
        $root =~ s/spin_pol/pol/;
    }

    my $xfile = File::Spec->catfile($self->wiredir, "header", $root . "_exclude");

    return $xfile;
}

=item B<determine_scan_angles>

Given a particular scan area and frontend, determine which angles can be given
to the TCS.

    @angles = $trans->determine_scan_angles($pattern, %info);

Angles are simple numbers in degrees. Not objects.

The scanning system is determined by this routine.

=cut

sub determine_scan_angles {
    my $self = shift;
    my $pattern = shift;
    my %info = @_;

    # only calculate angles for bous or raster
    return ($info{SCAN_SYSTEM}) unless $pattern =~ /BOUS|RASTER/i;

    # Need to know the frontend
    my $frontend = $self->ocs_frontend($info{instrument});
    throw OMP::Error::FatalError("Unable to determine appropriate frontend!")
        unless defined $frontend;

    # Choice depends on pixel size. If sampling is equal in DX/DY or for an array
    # receiver then all 4 angles can be used. Else the scan is constrained to the X direction
    my @mults = (1, 3);    # 0, 2 aligns with height, 1, 3 aligns with width
    if ($frontend =~ /harp/i
            || ($info{SCAN_VELOCITY} * $info{sampleTime} == $info{SCAN_DY})) {
        @mults = (0 .. 3);
    }

    my @scanpas = map {$info{MAP_PA} + ($_ * 90)} @mults;

    return ($info{SCAN_SYSTEM}, @scanpas);
}

=item B<is_private_sequence>

Returns true if the sequence only requires the instrument itself
to be involved. If true, the telescope, SMU and RTS are not involved
and so do not generate configuration XML.

    $trans->is_private_sequence(%info);

For ACSIS always returns false.

=cut

sub is_private_sequence {
    return 0;
}

=item B<get_tracking_receptor_filter_params>

Get tracking subarray filtering parameters.

    my %filter = $self->get_tracking_receptor_filter_params($cfg, %info);

=cut

sub get_tracking_receptor_filter_params {
    my $self = shift;
    my $cfg = shift;
    my %info = @_;

    my $frontend = $cfg->frontend();
    throw OMP::Error::FatalError('frontend setup is not available')
        unless defined $frontend;

    return (
      sideband => $frontend->sideband(),
    );
}

=item B<fixup_historical_problems>

In order for DAS observations to be translated as ACSIS observations we
need to fill in missing information and translate DAS bandwidth settings
to ACSIS equivalents.

    $cfg->fixup_historical_problems(\%obs);

Also set mode to 2SB for dual-sideband receivers in case of using XML
from pre-2SB OT and USB for USB-only receivers.

=cut

sub fixup_historical_problems {
    my $self = shift;
    my $info = shift;

    if ($info->{'ot_version'} lt '20190731') {
        my %twosbrx = map {$_ => 1} qw/UU AWEOWEO/;

        $info->{'freqconfig'}->{'sideBandMode'} = '2sb'
            if exists $twosbrx{uc($info->{'instrument'})};
    }

    # TODO: apply ot_version test once OT supports USB sideband mode.
    if (1) {
        my %usbrx = map {$_ => 1} qw/ALAIHI/;

        $info->{'freqconfig'}->{'sideBandMode'} = 'usb'
            if exists $usbrx{uc $info->{'instrument'}};
    }

    if ($info->{'PROJECTID'} =~ /^(?:JCMT)?CAL$/i
            and 'UU' eq uc $info->{'instrument'}) {
        my $synth_status = _get_lo2_synth_status();
        my $obs_type = uc $info->{'obs_type'};

        # Change Uu 6GHz IF standards to 5GHz to avoid bad LO2. (If using 2x chained mode.)
        if ('SCIENCE' eq $obs_type
                and 'SPITERSTAREOBS' eq uc $info->{'MODE'}
                and 2 == scalar @{$info->{'freqconfig'}->{'subsystems'}}
                and 1.0E6 > abs($info->{'freqconfig'}->{'subsystems'}->[0]->{'if'} - 6.0E9)
                and 1.0E6 > abs($info->{'freqconfig'}->{'subsystems'}->[1]->{'if'} - 6.0E9)
                and 1.0E6 > abs($info->{'freqconfig'}->{'subsystems'}->[0]->{'rest_freq'}
                    - $info->{'freqconfig'}->{'subsystems'}->[1]->{'rest_freq'})
                and ($info->{'freqconfig'}->{'subsystems'}->[0]->{'channels'} == 2048
                    or $info->{'freqconfig'}->{'subsystems'}->[0]->{'channels'} == 8192)
                and ($info->{'freqconfig'}->{'subsystems'}->[1]->{'channels'} == 2048
                    or $info->{'freqconfig'}->{'subsystems'}->[1]->{'channels'} == 8192)
                and (not all {$_} @{$synth_status->{'high'}})) {
            $info->{'freqconfig'}->{'subsystems'}->[0]->{'if'} = 5.0E9;
            $info->{'freqconfig'}->{'subsystems'}->[1]->{'if'} = 5.0E9;
        }
        # Change Uu 6GHz IF pointing/focus to 5GHz to avoid bad LO2. (If using 1x chained mode.)
        elsif (('POINTING' eq $obs_type or 'FOCUS' eq $obs_type)
                and 1 == scalar @{$info->{'freqconfig'}->{'subsystems'}}
                and 1.0E6 > abs($info->{'freqconfig'}->{'subsystems'}->[0]->{'if'} - 6.0E9)
                and ($info->{'freqconfig'}->{'subsystems'}->[0]->{'channels'} == 2048
                    or $info->{'freqconfig'}->{'subsystems'}->[0]->{'channels'} == 8192)
                and not (
                    ($synth_status->{'high'}->[0] and $synth_status->{'high'}->[1])
                    or ($synth_status->{'high'}->[2] and $synth_status->{'high'}->[3])
                )) {
            $info->{'freqconfig'}->{'subsystems'}->[0]->{'if'} = 5.0E9;
        }
    }

    return if $info->{freqconfig}->{beName} eq 'acsis';

    # Band width mode must translate to ACSIS equivalent
    my %bwmode = (
        # always map 125MHz to 250MHz
        125 => {
            bw => 2.5E8,
            overlap => 0.0,
            channels => 8192,
        },
        250 => {
            bw => 2.5E8,
            overlap => 0.0,
            channels => 8192,
        },
        500 => {
            bw => 4.8E8,
            overlap => 1.0E7,
            channels => 7864,
        },
        760 => {
            bw => 9.5E8,
            overlap => 5.0E7,
            channels => 1945,
        },
        920 => {
            bw => 9.5E8,
            overlap => 5.0E7,
            channels => 1945,
        },
        1840 => {
            bw => 1.9E9,
            overlap => 5.0E7,
            channels => 1945,
        },
    );

    # need to add the following
    # freqconfig => overlap
    #               IF

    my $freq = $info->{freqconfig};

    # should only be one subsystem but non-fatal
    for my $ss (@{$freq->{subsystems}}) {
        # force 4GHz
        $ss->{if} = 4.0E9;

        # calculate the corresponding bw key
        my $bwkey = $ss->{bw} / 1.0E6;

        throw OMP::Error::TranslateFail(
            "DAS Bandwidth mode not supported by ACSIS translator")
            unless exists $bwmode{$bwkey};

        for my $k (qw/ bw overlap channels /) {
            $ss->{$k} = $bwmode{$bwkey}->{$k};
        }
    }

    # need to trap DAS special modes
    throw OMP::Error::TranslateFail(
        "DAS special modes not supported by ACSIS translator")
        if defined $freq->{configuration};

    # Need to shift the velocity from freqconfig to coordtags
    my $vfr = $freq->{velocityFrame};
    my $vdef = $freq->{velocityDefinition};
    my $vel = $freq->{velocity};

    $info->{coords}->set_vel_pars($vel, $vdef, $vfr)
        if $info->{coords}->can("set_vel_pars");

    for my $t (keys %{$info->{coordtags}}) {
        $info->{coordtags}->{$t}->{coords}->set_vel_pars($vel, $vdef, $vfr)
            if $info->{coordtags}->{$t}->{coords}->can("set_vel_pars");
    }

    return;
}

=item B<handle_special_modes>

Special modes such as POINTING or FOCUS are normal observations that
are modified to do something in addition to normal behaviour. For a
pointing this simply means fitting an offset.

    $cfg->handle_special_modes(\%obs);

Since the Observing Tool is setup such that pointing and focus
observations do not necessarily inherit observing parameters from the
enclosing observation and they definitely do not include a
specification on chopping scheme.

Also handles point source scan requests.

=cut

sub handle_special_modes {
    my $self = shift;
    my $info = shift;

    # The trick is to fill in the blanks

    # Specify that all jiggle/chop observations are ABBA or AB nods
    if ($info->{observing_mode} =~ /(grid|jiggle)_chop/) {
        $info->{nodSetDefinition} = "ABBA";
    }

    # A pointing should translate to
    #  - Jiggle chop
    #  - 5 point or 9x9 jiggle pattern
    #  - 60 arcsec AZ chop

    # Some things depend on the frontend
    my $frontend = $self->ocs_frontend($info->{instrument});
    throw OMP::Error::FatalError("Unable to determine appropriate frontend!")
        unless defined $frontend;

    # Pointing will have been translated into chop already by the
    # observing_mode() method.

    if ($info->{obs_type} eq 'pointing') {
        $info->{CHOP_PA} = 90;
        $info->{CHOP_THROW} = 60;
        $info->{CHOP_SYSTEM} = 'AZEL';

        # this is configured as an AB nod
        $info->{nodSetDefinition} = "ABBA";

        # read integration time from config system, else default to 2.0 seconds
        my $pointing_secs = 2.0;
        try {
            $pointing_secs = OMP::Config->getData(
                'acsis_translator.secs_per_jiggle_pointing');
        }
        otherwise {
            # no problem, use default
        };
        $info->{secsPerJiggle} = $pointing_secs;

        my $scaleMode;
        if ($frontend =~ /^HARP/) {
            # HARP needs to use single receptor pointing until we sort out relative
            # calibrations. Set disableNonTracking to false and HARP5 jiggle pattern.
            $info->{disableNonTracking} = 0;  # Only use 1 receptor if true

            my $jigsys = "AZEL";
            try {
                $jigsys = OMP::Config->getData(
                    'acsis_translator.harp_pointing_jigsys');
            }
            otherwise {
                # no problem, use default
            };
            $info->{jiggleSystem} = $jigsys;

            # Allow the HARP jiggle pattern to be overridden for commissioning
            # HARP5 and 5x5 are the obvious ones. 5pt or HARP4 are plausible.
            $info->{jigglePattern} = 'HARP5';
            try {
                $info->{jigglePattern} = OMP::Config->getData(
                    'acsis_translator.harp_pointing_pattern');
            }
            otherwise {
                # use default
            };

            # For HARP jiggle pattern use "unity" here
            # For other patterns, be careful. If you are disabling non tracking
            # pixels you must make sure that you have a big enough pattern for the
            # planet. a 3x3 or 5point should always use "planet".
            $scaleMode = "planet";  # Also: unity, planet, nyquist

            # Use a bigger chop to get off the array
            $info->{CHOP_THROW} = 120;
        }
        else {
            $info->{disableNonTracking} = 0;  # If true, Only use 1 receptor
            $info->{jiggleSystem} = 'AZEL';
            $info->{jigglePattern} = '5pt';  # or 5x5
            try {
                $info->{jigglePattern} = OMP::Config->getData(
                    'acsis_translator.pointing_pattern');
            }
            otherwise {
                # use default
            };
            $scaleMode = "planet";    # Allowed: unity, planet, nyquist
        }

        # should we be in continuum mode or spectral line mode.
        # Cont mode can be used for both but spec mode is useless in continuum
        $info->{continuumMode} = 1;    # default to yes
        try {
            $info->{continuumMode} =
                OMP::Config->getData('acsis_translator.cont_pointing');
        }
        otherwise {
            # use default
        };

        # Now we need to determine the scaleFactor for the jiggle. This has been
        # specified above. Options are:
        #   unity  : scale factor is 1. Only used for HARP jiggle patterns
        #   nyquist: use nyquist sampling
        #   planet : use nyquist sampling or if planet use the planet radius, whichever is larger
        #
        if ($info->{jigglePattern} =~ /^HARP/ || $scaleMode eq 'unity') {
            # HARP jiggle pattern is predefined
            $info->{scaleFactor} = 1;
        }
        elsif ($scaleMode eq 'planet' || $scaleMode eq 'nyquist') {
            # The scale factor should be the larger of half beam or planet limb
            my $half_beam = $self->nyquist(%$info)->arcsec;
            my $plan_rad = 0;
            if ($scaleMode eq 'planet'
                    && ! $info->{autoTarget}
                    && $info->{coords}->type eq 'PLANET') {
                # Currently need to force an apparent ra/dec calculation to get the diameter
                my @discard = $info->{coords}->apparent();
                $plan_rad = $info->{coords}->diam->arcsec / 2;
            }

            # Never go smaller than 3.75 arcsec
            $info->{scaleFactor} = max($half_beam, $plan_rad, 3.75);
        }
        else {
            throw OMP::Error::FatalError(
                "Unable to understand scale factor request for pointing");
        }

        $self->output(
            "Determining POINTING parameters...\n",
            "\tJiggle Pattern: $info->{jigglePattern} ($info->{jiggleSystem})\n",
            "\tSMU Scale factor: $info->{scaleFactor} arcsec\n",
            "\tChop parameters: $info->{CHOP_THROW} arcsec @ $info->{CHOP_PA} deg ($info->{CHOP_SYSTEM})\n",
            "\tSeconds per jiggle position: $info->{secsPerJiggle}\n");

        if ($info->{disableNonTracking}) {
            $self->output("\tPointing on a single receptor\n");
        }
        else {
            $self->output("\tAll receptors active\n");
        }
        $self->output("\tOptimizing for "
            . ($info->{continuumMode} ? "continuum" : "spectral line")
            . " mode\n");

        # Kill baseline removal
        if (exists $info->{data_reduction}) {
            my %dr = %{$info->{data_reduction}};
            delete $dr{baseline};
            $info->{data_reduction} = \%dr;
        }
    }
    elsif ($info->{obs_type} eq 'focus') {
        # Focus is a 60 arcsec AZ chop observation
        # This is a GRID_CHOP observation, not a JIGGLE
        $info->{CHOP_PA} = 90;
        $info->{CHOP_THROW} = 60;
        $info->{CHOP_SYSTEM} = 'AZEL';
        $info->{disableNonTracking} = 0;  # If true, Only use 1 receptor

        # this is configured as an AB nod
        $info->{nodSetDefinition} = "AB";

        # should we be in continuum mode or spectral line mode.
        # Cont mode can be used for both but spec mode is useless in continuum
        $info->{continuumMode} = 1;  # default to yes
        try {
            $info->{continuumMode} = OMP::Config->getData(
                'acsis_translator.cont_focus');
        }
        otherwise {
            # use default
        };

        # read integration time from config system, else default to 2.0 seconds
        # note that we are not technically jiggling.
        my $focus_secs = 2.0;
        try {
            $focus_secs = OMP::Config->getData(
                'acsis_translator.secs_per_jiggle_focus');
        }
        otherwise {
            # no problem, use default
        };
        $info->{secsPerCycle} = $focus_secs;

        # if this is harp then we want the K-mirror to be aligned in the same way it is aligned
        # for POINTING observations (since you point and then focus and you do not want the thing to
        # flip between the two if at all possible
        if ($frontend =~ /^HARP/) {
            my $staresys = "AZEL";
            try {
                $staresys = OMP::Config->getData(
                    'acsis_translator.harp_pointing_jigsys');
            }
            otherwise {
                # no problem, use default
            };
            $info->{stareSystem} = $staresys;
        }

        $self->output(
            "Determining FOCUS parameters...\n",
            "\tChop parameters: $info->{CHOP_THROW} arcsec @ $info->{CHOP_PA} deg ($info->{CHOP_SYSTEM})\n",
            "\tSeconds per focus position: $info->{secsPerCycle}\n",
            "\tOptimizing for "
                . ($info->{continuumMode} ? "continuum" : "spectral line")
                . " mode\n");

        # Kill baseline removal
        if (exists $info->{data_reduction}) {
            my %dr = %{$info->{data_reduction}};
            delete $dr{baseline};
            $info->{data_reduction} = \%dr;
        }
    }
    elsif ($info->{mapping_mode} eq 'jiggle' && $frontend =~ /^HARP/) {
        # If HARP is the jiggle pattern then we need to set scaleFactor to 1
        if ($info->{jigglePattern} =~ /^HARP/) {
            $info->{scaleFactor} = 1;  # HARP pattern is fully sampled
            # $info->{jiggleSystem} = "FPLANE"; # in focal plane coordinates...
        }
    }

    # For now we need to morph a grid/freqsw into a 1x1 jiggle/freqsw
    if ($info->{mapping_mode} eq 'grid' && $info->{switching_mode} =~ /freqsw/) {
        $info->{mapping_mode} = 'jiggle';
        $info->{observing_mode} = 'jiggle_freqsw';
        $info->{jigglePattern} = '1x1';
        $info->{scaleFactor} = 1;
        $info->{secsPerJiggle} = $info->{secsPerCycle};
        # Record the fact that this conversion has been made.  This can be
        # important, e.g. when setting the rotator angle, we need to know that
        # we should access the original grid / stare PA parameters.
        $info->{'isConvertedGridFreqSw'} = 1;
        $self->output("Converting grid/freqsw to jiggle/freqsw observation\n");
    }

    if ($info->{mapping_mode} eq 'scan') {
        # fix up point source scanning
        if ($info->{scanPattern} eq 'Point Source') {

            $info->{scanPattern} = OMP::Config->getData($self->cfgkey . ".scan_pntsrc_pattern");
            $info->{MAP_HEIGHT} = OMP::Config->getData($self->cfgkey . ".scan_pntsrc_map_height");
            $info->{MAP_WIDTH} = OMP::Config->getData($self->cfgkey . ".scan_pntsrc_map_width");
            $info->{SCAN_VELOCITY} = OMP::Config->getData($self->cfgkey . ".scan_pntsrc_velocity");
            $info->{SCAN_DY} = OMP::Config->getData($self->cfgkey . ".scan_pntsrc_scan_dy");

            $info->{SCAN_SYSTEM} = "FPLANE";
            $info->{MAP_PA} = 0;

            # to be consistenet we set sampleTime to our required step time
            # and use a new key for the toal time
            $info->{totalIntegrationTime} = $info->{sampleTime};

            # this becomes the step time in scan mode
            $info->{sampleTime} = OMP::Config->getData($self->cfgkey . ".scan_pntsrc_step_time");

            $self->output("Defining point source scan map from config.\n");
        }
    }

    return;
}

=item B<_determine_best_sideband>

Read the sideband wiring file to determine which sideband should be used
when "best" is requested.

Returns undef if the sideband file can not be found, or if no frequencies
lower than the given value are found.

=cut

sub _determine_best_sideband {
    my $instrument = shift;
    my $sky_freq_ghz = shift;
    my $wiredir = shift;

    # File name is derived from instrument name in wireDir
    # The instrument config is fixed for a specific instrument
    # and is therefore a "wiring file"
    throw OMP::Error::FatalError('No instrument defined so cannot configure sideband!')
        unless defined $instrument;

    # wiring file name
    my $file = File::Spec->catfile(
        $wiredir , 'frontend', "sideband_$instrument.txt");

    return undef unless -e $file;

    # can make a guess but make it non-fatal to be missing
    # The file is a simple format of
    #    SkyFreq    Sideband
    # where SkyFreq is the frequency threshold above which that
    # sideband should be used. We read each line until we get a skyfreq
    # that is higher than our required value and then use the value from the previous
    # line
    open my $fh, '<', $file or
        throw OMP::Error::FatalError("Error opening sideband preferences file $file: $!");

    # read the lines, skipping comments and if the current frequency is lower than
    # that of the line store the sideband and continue
    my $sb = undef;
    while (defined (my $line = <$fh>) ) {
        chomp($line);
        $line =~ s/\#.*//;      # remove comments
        $line =~ s/^\s*//;      # remove leading space
        $line =~ s/\s*$//;      # remove trailing space
        next if $line !~ /\S/;  # give up if we only have whitespace
        my ($freq, $refsb) = split(/\s+/, $line);
        if ($freq < $sky_freq_ghz) {
            $sb = uc $refsb;
        }
        else {
            # freq is larger so drop out of loop
            last;
        }
    }

    close($fh) or
        throw OMP::Error::FatalError("Error closing sideband preferences file $file: $!");

    return $sb;
}

=item B<_safe_transition_name>

Prepare "safe" version of transition name, i.e. without special
characters.

B<Note:> current implementation simply replaces lower case greek
alpha, beta, gamma, delta with A, B, G, D respectively.

=cut

sub _safe_transition_name {
    my $self = shift;
    my $transition = shift;

    $transition =~ tr/\x{03b1}\x{03b2}\x{03b3}\x{03b4}/ABGD/;

    return $transition;
}

=back

=head2 Config Generators

These routines configure the specific C<JAC::OCS::Config> objects.

=over 4

=item B<frontend_config>

Create the frontend configuration.

    $trans->frontend_config($cfg, %info);

Also adds additional information to the configured subsystems:

=over 4

=item * sideband

=back

=cut

sub frontend_config {
    my $self = shift;
    my $cfg = shift;
    my %info = @_;

    # Need instrument information
    my $inst = $cfg->instrument_setup();
    throw OMP::Error::FatalError('instrument setup is not available')
        unless defined $inst;

    # Create frontend object for this configuration
    my $fe = JAC::OCS::Config::Frontend->new();

    # Get the basic frontend setup from the freqconfig key
    my %fc = %{$info{freqconfig}};
    my $iffreq = $fc{'otConfigIF'};
    my $iffreq_ghz = $iffreq / 1.0e9;  # to GHz

    # Check whether the instrument configuration matches what
    # the OT thought it was.
    do {
        my $iffreq_conf = $inst->if_center_freq * 1.0E9;  # from GHz

        if ($iffreq_conf != $iffreq) {
            my $message = 'The instrument IF frequency specified in '
                . 'the instrument XML ('
                . $iffreq_conf
                . ') does not match the IF frequency given in the observation ('
                . $iffreq . ').';

            if (OMP::Config->getData('acsis_translator.ignore_if_freq_mismatch')) {
                $self->output('WARNING: ' . $message . "\n");
            }
            else {
                throw OMP::Error::FatalError($message
                    . ' You can force the translation of the observation by enabling '
                    . 'ignore_if_freq_mismatch in the acsis_translator settings.');
            }
        }
    };

    # Sideband mode
    my $sb_mode = uc $fc{sideBandMode};

    # Get sky and rest frequency in GHz
    my $skyFreq = $fc{skyFrequency} / 1.0E9;
    my $restfreq = $fc{restFrequency} / 1.0E9;

    # How to handle 'best'?
    my $sb = uc $fc{sideBand};
    my $sideband_flip = undef;

    # Check side-band restricted observations.
    if (($sb_mode eq 'USB') or ($sb_mode eq 'LSB')) {
        throw OMP::Error::TranslateFail(
            "Specified sideband is '$sb' but the sideband mode is '$sb_mode'")
            unless $sb eq $sb_mode;

        # Treat as 'SSB' hereafter for now.
        $sb_mode = 'SSB';
    }

    $fe->sb_mode($sb_mode);

    if ($sb eq 'BEST') {
        # determine from lookup table
        my $instrument_name = lc($self->ocs_frontend($info{instrument}));

        $sb = _determine_best_sideband(
            $instrument_name, $skyFreq, $self->wiredir());

        if (defined $sb) {
            $self->output(
                "Selected sideband $sb for sky frequency of $skyFreq GHz\n");
        }
        else {
            $sb = 'USB';
            $self->output(
                "No sideband helper file for $instrument_name or frequency $skyFreq GHz out of range so assuming $sb will be acceptable\n");
        }

        # If we have offset subsystems and we have selected LSB, we need to adjust the
        # IFs to take into account the flip. The OT always sends a USB configuration for best
        if ($sb eq 'LSB') {
            # Determine IF frequency about which to mirror when flipping from
            # BEST (as USB) to LSB.  Initially use the configured IF frequency
            # but when the IF bandwidth is asymmetric we must check the subsystems
            # are within the IF band.

            $sideband_flip = $iffreq;

            my @if_freq_limit = ();
            try {
                @if_freq_limit = OMP::Config->getData(
                    'acsis_translator.if_freq_limit_' . $instrument_name);
            }
            catch OMP::Error::BadCfgKey with {
                # Do nothing.
            };

            if (@if_freq_limit) {
                my ($if_freq_low, $if_freq_high) = @if_freq_limit;

                # See what the frequency range will be once flipped -- actual
                # flip performed later once we have checked that the subsystems
                # will fit in the IF band.  Assuming that the subsystems do fit
                # before mirroring, we should only need to nudge in one direction,
                # so there is no need to track +ve and -ve nudges here.

                my $nudge = 0.0;
                my $n_subsystem = 0;

                foreach my $ss (@{$fc{subsystems}}) {
                    $n_subsystem ++;
                    my $half_bw = $ss->{'bw'} / 2.0;
                    my $flipped = (2.0 * $sideband_flip) - $ss->{'if'};

                    my $low_excess = $if_freq_low - ($flipped - $half_bw);
                    if ($low_excess > 0.0 and $low_excess / 2.0 > $nudge) {
                        $nudge = $low_excess / 2.0;
                    }

                    my $high_excess = ($flipped + $half_bw) - $if_freq_high;
                    if ($high_excess > 0.0 and $high_excess / 2.0 > -$nudge) {
                        $nudge = -$high_excess / 2.0;
                    }
                }

                $sideband_flip += $nudge;
            }

            $self->output(
                sprintf "\tIF frequencies will be mirrored about %.3f GHz to change sideband\n",
                    $sideband_flip / 1.0e9);
        }
    }

    $fe->sideband($sb);

    # Compute the redshift factor and use it to find the approximate
    # equivalent frequency of the LO in the source rest frame. We can use
    # this to determine the sideband of each subsystem.
    my $inv_redshift_factor = $restfreq / $skyFreq;
    my $lo_rest = ($skyFreq - _sideband_sign($sb) * $iffreq_ghz) * $inv_redshift_factor;

    $self->output("Checking subsystem sideband configuration...\n");
    $self->output("\tApprox. rest sys. equiv. of LO is: $lo_rest GHz\n");

    # Now iterate over subsystems and check the sideband configuration.
    my $n_subsystem = 0;
    for my $ss (@{$fc{subsystems}}) {
        $n_subsystem ++;

        if (defined $sideband_flip) {
            $ss->{if} = (2.0 * $sideband_flip) - $ss->{if};
        }

        my $ss_rest_freq = $ss->{'rest_freq'} / 1.0E9;

        my $ss_sideband = ($ss_rest_freq > $lo_rest) ? 'USB' : 'LSB';
        $self->output(
            "\tSubsystem $n_subsystem: determined sideband $ss_sideband ($ss_rest_freq GHz)\n");

        if ($ss_sideband ne $sb) {
            if ($n_subsystem == 1) {
                # Since we configured everything based on the first subsystem,
                # it should be in the correct sideband!
                throw OMP::Error::TranslateFail(
                    "First subsystem appears in unexpected sideband");
            }

            if ($sb_mode eq 'SSB') {
                throw OMP::Error::TranslateFail(
                    "Subsystem $n_subsystem is in $ss_sideband but this is an SSB $sb observation");
            }
            elsif (($sb_mode eq 'DSB') or ($sb_mode eq '2SB')) {
                # Retain alternative sideband label.
            }
            else {
                throw OMP::Error::TranslateFail(
                    "Unknown sideband mode '$sb_mode'");
            }
        }

        $ss->{'sideband'} = $ss_sideband;
    }

    # Configure the instrument to use the IF as specified in the first subsystem.
    my $ifsub1 = $fc{subsystems}->[0]->{if} / 1e9;  # to GHz
    my $offset = $ifsub1 - $iffreq_ghz;

    # Apply historical tuning offset for receivers which do not yet support
    # reading their IF frequency from the configure XML.
    my %variable_if_inst = map {$_ => 1} qw/alaihi uu aweoweo kuntur/;
    unless (exists $variable_if_inst{lc($self->ocs_frontend($info{instrument}))}) {
        # Get the IF which the instrument will be using, in GHz.
        my $iffreq_conf_ghz = $inst->if_center_freq();

        # Recompute the offset using this IF in case it differs from OT's.
        $offset = $ifsub1 - $iffreq_conf_ghz;

        if (lc($sb) eq 'usb') {
            $offset *= -1;
        }

        # Apply redshift factor to offset.  (This step not present in original
        # version of the tuning adjustment.)
        $offset *= $inv_redshift_factor;

        $restfreq += $offset;

        $self->output(
            sprintf "Tuning adjusted by %.0f MHz to correct for offset of first subsystem in band\n",
            ($offset * 1e3));
    }
    else {
        $inst->if_center_freq($ifsub1);
        $self->output(
            sprintf "\tUsing IF frequency of %.3f GHz %s\n", $ifsub1, $sb);

        if (abs($offset) > 0.001) {
            $self->output(
                sprintf "\t(Offset from default by %.0f MHz)\n", $offset * 1e3);
        }
    }

    # FE XML expects rest frequency in GHz
    $fe->rest_frequency($restfreq);
    $self->output(
        sprintf "Tuning to a rest frequency of %.3f GHz\n", $restfreq);

    # doppler mode
    $fe->doppler(ELEC_TUNING => 'DISCRETE', MECH_TUNING => 'ONCE');

    # Frequency offset
    my $freq_off = 0.0;
    if ($info{switching_mode} =~ /freqsw/ && defined $info{frequencyOffset}) {
        # want the spacing to be frequencyOffset and not 2xfrequencyOffset (since the
        # observing system goes to -1 and +1 not -0.5 and +0.5
        $freq_off = $info{frequencyOffset} / 2.0;
    }
    $fe->freq_off_scale($freq_off);

    # store the frontend name in the Frontend config so that we can get the
    # task name
    $fe->frontend($inst->name);

    # store the configuration
    $cfg->frontend($fe);

    # Compute the approximate image frequency for each subsystem
    # and store in the frequency config hash.
    for my $ss (@{$fc{'subsystems'}}) {
        $ss->{'image_freq'} = $ss->{'rest_freq'}
            + ($ss->{'sideband'} eq 'LSB' ? 2 : -2) * $ss->{'if'} * $inv_redshift_factor;
    }
}

=item B<backend_config>

Configure ACSIS.

    $trans->backend_config($cfg, %info);

=cut

sub backend_config {
    my $self = shift;
    my $cfg = shift;
    my %info = @_;

    my $acsis = JAC::OCS::Config::ACSIS->new();

    # Store it in the object
    $cfg->acsis($acsis);

    # Prepare image subsystems (if using a 2SB receiver).  Determine the
    # bandwidth mode first to avoid nudging the image IF to make it unique.
    # This is assuming that, for now, automatic subsystems will
    # use the same mode as those of which they are images.
    $self->bandwidth_mode($cfg, %info);
    $self->create_image_subsystems($cfg, %info);

    # Now configure the individual ACSIS components
    $self->line_list($cfg, %info);
    $self->spw_list($cfg, %info);
    $self->correlator($cfg, %info);
    $self->acsisdr_recipe($cfg, %info);
    $self->cubes($cfg, %info);
    $self->interface_list($cfg, %info);
    $self->acsis_layout($cfg, %info);
    $self->rtd_config($cfg, %info);
}

=item B<rotator_config>

Configure the rotator parameter. Requires the Config object to at
least have a TCS and Instrument configuration defined. The second
argument indicates how many science and pointing observations are
related for this SpObs. This information can be used to control the
slew mode. It is a reference to a hash with keys of "science" or
"pointing" and values indicating the number of each in the SpObs.

    $trans->rotator_config($cfg, \%count, %info);

Only relevant for instruments that are on the Nasmyth platform.

=cut

sub rotator_config {
    my $self = shift;
    my $cfg = shift;
    my $nobs = shift;
    my %info = @_;

    # Get the instrument configuration
    my $inst = $cfg->instrument_setup();
    throw OMP::Error::FatalError('instrument setup is not available')
        unless defined $inst;

    return
        if defined $inst->focal_station
        && $inst->focal_station !~ /NASMYTH/;

    # get the tcs
    my $tcs = $cfg->tcs();
    throw OMP::Error::FatalError('TCS setup is not available')
        unless defined $tcs;

    # if we are a sky dip observation then we need a rotator config but it should simply say "FIXED" system.
    # The TCS will then know not to bother asking it to move.
    if ($info{obs_type} eq 'skydip') {
        $tcs->rotator(SYSTEM => "FIXED");
        return;
    }

    # Need to find out the coordinate frame of the map
    # This will either be AZEL or TRACKING - choose the result from any cube
    my %cubes = $self->getCubeInfo($cfg);
    my @cubs = values(%cubes);

    # Assume that the cube definition should probide the defaults for the system and
    # position angle.
    my $pa = $cubs[0]->posang;
    $pa = Astro::Coords::Angle->new(0, units => 'radians')
        unless defined $pa;

    my $system = $cubs[0]->tcs_coord;

    # if we are scanning we need to adjust the position angle of the rotator
    # here to adjust for the harp pixel footprint sampling
    # Also, if we are jiggling we may need to rotate the rotator to the jiggle system
    # for HARP where we always jiggle in FPLANE/PA=0
    # Finally, for some specialist Stare HARP observations we need to rotate the K mirror
    # separately.
    my $scan_adj = 0;
    my @choices = (0 .. 3);    # four fold symmetry
    if ($inst->name =~ /HARP/) {
        $self->output("Selecting K-mirror angles\n");

        # need the TCS information
        my $tcs = $cfg->tcs();
        throw OMP::Error::FatalError('TCS setup is not available')
            unless defined $tcs;

        # get the observing area
        my $oa = $tcs->getObsArea();
        throw OMP::Error::FatalError('TCS observing area is not available')
            unless defined $oa;

        if ($oa->mode eq 'area') {
            # we are scanning with HARP so adjust arctan 1/4. This assumes that the rotator
            # is working and can be aligned with the AZEL/TRACKING system (instead of always
            # forcing FPLANE system)
            $scan_adj = rad2deg(atan2(1, 4));

            # we have to make sure that the k-mirror is rotated relative to the
            # scan angle and not the map angle. For "auto" mode these will be the same
            # but for others they may not be. Problem occurs when multiple scan PAs
            # are specified and they are not at 90 degrees to each other.
            my %scan = $oa->scan();
            if (exists $scan{PA}) {
                my @scanpas = @{$scan{PA}};
                if (@scanpas == 1) {
                    $pa = $scanpas[0];
                }
                else {
                    my $use_scan = 1;
                    for my $i (1 .. $#scanpas) {
                        my $diff = abs($scanpas[$i]->degrees - $scanpas[$i - 1]->degrees);
                        if ($diff % 90.0) {
                            if ($self->verbose) {
                                $self->output(
                                    "\tScan selections do not differ by multiples of 90 degrees.\n",
                                    "\tUsing map PA for K-mirror angle.\n");
                            }
                            $use_scan = 0;
                            last;
                        }
                    }
                    if ($use_scan) {
                        $pa = $scanpas[0];  # scans are at multiples of 90 deg
                    }
                }
                $system = $scan{SYSTEM};
            }
        }
        elsif (($info{mapping_mode} eq 'jiggle')
                and not $info{'isConvertedGridFreqSw'}) {
            # override the system from the jiggle. The PA should be matching the cube
            # but we make sure we use the requested value
            # Note: we don't do this if the observation is a grid/freqsw converted
            # to a 1x1 jiggle because we want to retain the original PA information.
            $system = $info{jiggleSystem} || 'TRACKING';
            $pa = Astro::Coords::Angle->new(
                ($info{jigglePA} || 0),
                units => 'deg');

            # Restrict the rotator choices if we have a jiggle pattern that is not
            # symmetric about all 4 positions
            # Currently use a bit of a hack
            if ($info{jigglePattern} eq '2x1') {
                @choices = (0, 2);
            }
        }
        elsif (($info{mapping_mode} eq 'grid')
                or $info{'isConvertedGridFreqSw'}) {
            if (exists $info{stareSystem}
                    && defined $info{stareSystem}) {
                # override K mirror option
                # For now only allow when there are no offsets (simplifies map making)
                $system = $info{stareSystem} || 'TRACKING';
                $pa = Astro::Coords::Angle->new(
                    ($info{starePA} || 0),
                    units => 'deg');
            }
            else {
                # Might we need to change system to align with the grid?
                my @offsets;
                @offsets = @{$info{'offsets'}}
                    if (exists $info{'offsets'} and defined $info{'offsets'});

                if (@offsets) {
                    my $offsys = undef;
                    $offsys = $offsets[0]->{'OFFSET_SYSTEM'}
                        if exists $offsets[0]->{'OFFSET_SYSTEM'};
                    $system = $offsys if defined $offsys;
                }
            }
        }
    }

    $self->output("\tAligning K-mirror to "
        . $pa->degrees
        . " deg with $scan_adj sampling adjustment ($system)\n");

    # Convert to set of allowed angles and remove duplicates, using the automatic
    # "choices" x 90 degrees unless a set of allowed rotator angles has been
    # specified.
    my @raw_angles = (exists $info{'rotatorAngles'})
        ? @{$info{'rotatorAngles'}}
        : (map {$_ * 90} @choices);
    my @angles = map {$_ + $scan_adj} @raw_angles;
    push(@angles, map {$_ - $scan_adj} @raw_angles);
    my %angles = map {$_, undef} @angles;

    # Sort angles so that the XML produced is stable.  (The hash keys could
    # be in random order.)
    my @pas = sort {$a->radians <=> $b->radians} map {
        Astro::Coords::Angle->new(
            $pa->degrees + $_,
            units => 'degrees',
            range => 'PI')
    } keys %angles;

    # decide on slew option
    my $slew = "LONGEST_TRACK";

    try {
        $slew = OMP::Config->getData($self->cfgkey() . '.harp_rotator_slew');
    }
    otherwise {
        # Keep defaut.
    };

    try {
        $slew = OMP::Config->getData(
            $self->cfgkey() . '.harp_rotator_slew_' . $info{'obs_type'});
    }
    otherwise {
        # Keep defaut or non-mode-specific value.
    };

    $self->output("\tSelected rotator slew option: $slew\n");

    # do not know enough about ROTATOR behaviour yet
    $tcs->rotator(
        SLEW_OPTION => $slew,
        SYSTEM => $system,
        PA => \@pas,
    );
}

=item B<fts2_config>

FTS-2 is not used with ACSIS.

=cut

sub fts2_config {
}


=item B<jos_config>

Configure the JOS.

    $trans->jos_config($cfg, %info);

=cut

sub jos_config {
    my $self = shift;
    my $cfg = shift;
    my %info = @_;

    my $jos = JAC::OCS::Config::JOS->new();

    # need to determine recipe name
    # use hash indexed by observing mode
    my %JOSREC = (
        focus => 'focus',
        pointing => 'pointing',
        skydip => 'raster_pssw',
        jiggle_freqsw => ($self->is_fast_freqsw(%info)
            ? 'fast_jiggle_fsw'
            : 'slow_jiggle_fsw'),
        grid_freqsw => ($self->is_fast_freqsw(%info)
            ? 'fast_jiggle_fsw'
            : 'slow_jiggle_fsw'),
        jiggle_chop => 'jiggle_chop',
        jiggle_pssw => 'grid_pssw',
        grid_chop => 'jiggle_chop',
        grid_pssw_spin_pol => 'grid_pssw',
        grid_pssw_pol => 'grid_pssw_pol_step_integ',
        grid_pssw => 'grid_pssw',
        scan_pssw => 'raster_pssw',
    );

    if (exists $JOSREC{$info{obs_type}}) {
        $jos->recipe($JOSREC{$info{obs_type}});
    }
    elsif (exists $JOSREC{$info{observing_mode}}) {
        $jos->recipe($JOSREC{$info{observing_mode}});
    }
    else {
        throw OMP::Error::TranslateFail(
            "Unable to determine jos recipe from observing mode '$info{observing_mode}'");
    }

    # The number of cycles is simply the number of requested integrations
    # This value is no longer present in the OT and is derived for each mode dynamically
    my $num_cycles = (defined $info{nintegrations} ? $info{nintegrations} : 1);
    $jos->num_cycles($num_cycles);

    # The step time is always present
    $jos->step_time($self->step_time($cfg, %info));

    # Calculate the cal time and time between cals/refs in steps
    my ($calgap, $refgap) = $self->calc_jos_times($jos, %info);

    $self->output(
        "Generic JOS parameters:\n",
        "\tStep Time: " . $jos->step_time . " sec\n",
        "\tSteps between ref: " . $jos->steps_btwn_refs . "\n",
        "\tNumber of Cal samples: " . $jos->n_calsamples . "\n",
        "\tSteps between Cal: " . $jos->steps_btwn_cals . "\n");

    # Always start at the first TCS index (row or offset)
    # - if a science observation
    $jos->start_index(1)
        if $info{obs_type} =~ /science|skydip/;

    # Now parameters depends on that recipe name

    if ($info{obs_type} =~ /^skydip/) {
        $self->output("Skydip JOS parameters:\n");

        if ($info{observing_mode} =~ /^stare/) {
            # need JOS_MIN since we have multiple offsets
            my $integ = OMP::Config->getData('acsis_translator.skydip_integ');
            $jos->jos_min(POSIX::ceil($integ / $jos->step_time));

            $self->output("\tSteps per discrete elevation: " . $jos->jos_min() . "\n");
        }
        else {
            # scan so JOS_MIN is 1
            $jos->jos_min(1);
            $self->output("\tContinuous scanning skydip\n");
        }
    }
    elsif ($info{observing_mode} =~ /^scan/) {
        # Scan map

        # Number of ref samples now calculated by the JOS

        # Since the TCS works in integer times-round-the-map
        # Need to know the map area
        my $tcs = $cfg->tcs;
        throw OMP::Error::FatalError('TCS setup is not available')
            unless defined $tcs;

        my $obsArea = $tcs->getObsArea();
        throw OMP::Error::FatalError('TCS obsArea is not available')
            unless defined $obsArea;

        # need to calculate the length of a pong. Should be in a module somewhere. Code in JAC::OCS::Config.
        my %mapping_info = ($obsArea->scan, $obsArea->maparea);
        my $duration_per_area;
        if ($info{scanPattern} =~ /liss|pong/i) {
            $duration_per_area = JCMT::TCS::Pong::get_pong_dur(%mapping_info);
        }
        else {
            # Assume bous
            my $pixarea = $mapping_info{DY} * $mapping_info{VELOCITY};
            my $maparea = $mapping_info{WIDTH} * $mapping_info{HEIGHT};
            $duration_per_area = ($maparea / $pixarea) * $jos->step_time;
        }

        # JOS_MIN (should always be 1) for normal scanning
        # the integration time if point source
        my $tot_time;
        if (exists $info{totalIntegrationTime}
                && defined $info{totalIntegrationTime}) {
            # steps between darks must be at least the duration_per_area
            # otherwise the num_cycles calculation means that you end up with
            # too many repeats
            my $steps_per_pass = $duration_per_area / $jos->step_time;
            my $tbdark = max($jos->steps_btwn_refs, $steps_per_pass);

            my $nsteps = $info{totalIntegrationTime} / $jos->step_time;
            my $num_cycles = POSIX::ceil($nsteps / $tbdark);
            # this won't handle the TCS splitting things up on integer patterns
            $nsteps = OMP::General::nint($nsteps / $num_cycles);
            $jos->num_cycles($num_cycles);
            $jos->jos_min($nsteps);
            my $npasses = POSIX::ceil($jos->jos_min / $steps_per_pass);
            $tot_time = $jos->num_cycles
                * ($npasses * $steps_per_pass)
                * $jos->step_time;
        }
        else {
            $jos->jos_min(1);
            $tot_time = $duration_per_area;
        }

        $self->output(
            "Scan map JOS parameters:\n",
            "\tDuration of reference calculated by JOS dynamically\n",
            "\tEstimated time to cover the map area once: $duration_per_area sec\n",
            "\tNumber of repeats: " . $jos->num_cycles . "\n",
            "\tTime spent mapping: $tot_time sec\n");
    }
    elsif ($info{observing_mode} =~ /jiggle_chop/) {
        # Jiggle

        throw OMP::Error::TranslateFail(
            "Requested integration time (secsPerJiggle) is 0")
            if ! exists $info{secsPerJiggle}
            || ! defined $info{secsPerJiggle}
            || $info{secsPerJiggle} <= 0;

        # We need to calculate the number of full patterns per nod and the number
        # of nod sets. A nod set can either be an "A B" combination or a full
        # "A B B A" combination. This means that we must group integrations within a cycle
        # in either sets of 2 or 4.
        my $nod_set_size = $self->get_nod_set_size(%info);

        # first get the Secondary object, via the TCS
        my $tcs = $cfg->tcs;
        throw OMP::Error::FatalError('TCS setup is not available')
            unless defined $tcs;

        # ... and secondary
        my $secondary = $tcs->getSecondary();
        throw OMP::Error::FatalError('Secondary configuration is not available')
            unless defined $secondary;

        # N_JIGS_ON etc
        my %timing = $secondary->timing;

        # Get the full jigle parameters from the secondary object
        my $jig = $secondary->jiggle;

        # Now calculate the total time for 1 full coverage of the jiggle pattern
        # We can either jiggle+chop or chop+jiggle. Unfortunately chop_jiggle is not a mode.

        my $njig_chunks = 1;    # Number of chunks to break pattern into
        my $nsteps = 0;         # Number of steps in ON + OFF
        if (defined $timing{N_JIGS_ON}) {

            # We need the N_JIGS_ON and N_CYC_OFF here because the more we chop the more inefficient
            # we are (the sqrt scaling means that a single pattern is more efficient than breaking it
            # up into smaller chunks

            $nsteps = $self->calc_jiggle_times(
                $jig->npts,
                $timing{N_JIGS_ON},
                $timing{N_CYC_OFF});
        }
        elsif (defined $timing{CHOPS_PER_JIG}) {
            $nsteps = $self->calc_jiggle_times($jig->npts);
        }
        else {
            throw OMP::Error::FatalError(
                "Bizarre error whereby jiggle_chop neither defines CHOPS_PER_JIG nor N_JIGS_ON");
        }

        # Time per full jig pattern
        my $timePerJig = $nsteps * $jos->step_time;

        # The number of times we need to go round the jiggle (per cycle) is the total
        # requested time divided by the step time. Do not round this since it is only
        # going to be used to calculate the total required JOS_MULT, and ceil() on this
        # followed by ceil(total_jos_mult) leads to rounding errors.
        my $nrepeats = $info{secsPerJiggle} / $jos->step_time;

        # These repeats have to spread evenly over 2 or 4 nod cycles (a single nod set)
        # This would be JOS_MULT if NUM_NOD_SETS was 1 and time between nods could go
        # very high.
        my $total_jos_mult = ceil($nrepeats / $nod_set_size);

        # now get the max time between nods
        my $max_t_nod = OMP::Config->getData(
            'acsis_translator.max_time_between_nods'
            . ($info{continuumMode} ? "_cont" : ""));

        # and convert that to the max number of jiggle repeats per nod
        my $max_jos_mult = max(1, int($max_t_nod / $timePerJig));

        # The actual JOS_MULT and NUM_NOD_SETS can now be calculated
        # If we need less than required we just use that
        my $num_nod_sets;
        my $jos_mult;
        if ($total_jos_mult <= $max_jos_mult) {
            # we can do it all in one go
            $num_nod_sets = 1;
            $jos_mult = $total_jos_mult;
        }
        else {
            # we need to split the total into equal chunks smaller than max_jos_mult
            $num_nod_sets = ceil($total_jos_mult / $max_jos_mult);
            $jos_mult = ceil($total_jos_mult / $num_nod_sets);
        }

        $jos->jos_mult($jos_mult);
        $jos->num_nod_sets($num_nod_sets);

        $self->output("Jiggle with chop JOS parameters:\n");
        if (defined $timing{CHOPS_PER_JIG}) {
            $self->output("\tChopping then Jiggling\n");
        }
        else {
            $self->output("\tJiggling then Chopping\n");
        }

        $self->output(
            "\t" . ($info{continuumMode} ? "Continuum" : "Spectral Line") . " mode enabled\n",
            "\tOffs are " . ($info{separateOffs} ? "not " : "") . "shared\n",
            "\tDuration of single jiggle pattern: $timePerJig sec ("
                . $jig->npts . " points)\n",
            "\tRequested integration time per pixel: $info{secsPerJiggle} sec\n",
            "\tN repeats of whole jiggle pattern required: $nrepeats\n",
            "\tRequired total JOS_MULT: $total_jos_mult\n",
            "\tMax allowed JOS_MULT : $max_jos_mult\n",
            "\tActual JOS_MULT : $jos_mult\n",
            "\tNumber of nod sets: $num_nod_sets in groups of $jos_mult jiggle repeats (nod set is "
                . ($nod_set_size == 2 ? "AB" : "ABBA") . ")\n",
            "\tActual integration time per jiggle position: "
                . ($num_nod_sets * $nod_set_size * $jos_mult * $jos->step_time)
                . " secs\n");
    }
    elsif ($info{observing_mode} =~ /grid_chop/) {
        throw OMP::Error::TranslateFail(
            "Requested integration time (secsPerCycle) is 0")
            if ! exists $info{secsPerCycle}
            || ! defined $info{secsPerCycle}
            || $info{secsPerCycle} <= 0;

        # Similar to a jiggle_chop recipe (in fact they are the same) but
        # we are not jiggling (ie a single jiggle point at the origin)

        # Have to do AB or ABBA sequence so JOS_MULT is the secsPerCycle / 4
        # or secsPerCycle / 2 with the max nod time constraint
        my $nod_set_size = $self->get_nod_set_size(%info);

        # Required Integration time per cycle in STEPS
        my $stepsPerCycle = ceil($info{secsPerCycle} / $jos->step_time);

        # Total number of steps required per nod
        my $total_jos_mult = ceil($stepsPerCycle / $nod_set_size);

        # Max time between nods
        my $max_t_nod = OMP::Config->getData(
            'acsis_translator.max_time_between_nods'
            . ($info{continuumMode} ? "_cont" : ""));

        # converted to steps
        my $max_steps_nod = ceil($max_t_nod / $jos->step_time);

        my $num_nod_sets;
        my $jos_mult;
        if ($max_steps_nod > $total_jos_mult) {
            # can complete the required integration in a single nod set
            $jos_mult = $total_jos_mult;
            $num_nod_sets = 1;
        }
        else {
            # Need to spread it out
            $num_nod_sets = ceil($total_jos_mult / $max_steps_nod);
            $jos_mult = ceil($total_jos_mult / $num_nod_sets);
        }

        $jos->jos_mult($jos_mult);
        $jos->num_nod_sets($num_nod_sets);

        $self->output(
            "Chop JOS parameters:\n",
            "\t" . ($info{continuumMode} ? "Continuum" : "Spectral Line")
                . " mode enabled\n",
            "\tRequested integration time per grid point: $info{secsPerCycle} sec\n",
            "\tStep time for chop: " . $jos->step_time . " sec\n",
            "\tRequired total JOS_MULT: $total_jos_mult\n",
            "\tMax allowed JOS_MULT : $max_steps_nod\n",
            "\tNumber of nod sets: $num_nod_sets in groups of $jos_mult steps per nod (nod set is "
                . ($nod_set_size == 2 ? "AB" : "ABBA") . ")\n",
            "\tActual integration time per grid point: "
                . ($num_nod_sets * $jos_mult * $nod_set_size * $jos->step_time * $jos->num_cycles)
                . " sec\n");
    }
    elsif ($info{observing_mode} =~ /freqsw/) {
        # Parameters to calculate
        # JOS_MULT         => Number of complete jiggle maps per sequence
        # NUM_CYCLES       => Number of distinct sequences

        # A grid/freqsw will not need a jiggle object, but for jiggle mode we need to know
        # how many distinct points we will be observing. We also need to retrieve
        # the total requested integration time per point
        my $npts = 1;
        my $secs_per_point = 0;
        if ($info{observing_mode} =~ /jiggle/) {
            # first get the Secondary object, via the TCS
            my $tcs = $cfg->tcs;
            throw OMP::Error::FatalError('TCS setup is not available')
                unless defined $tcs;

            # ... and secondary
            my $secondary = $tcs->getSecondary();
            throw OMP::Error::FatalError(
                'Secondary configuration is not available')
                unless defined $secondary;

            # N_JIGS_ON etc
            my %timing = $secondary->timing;
            # Get the full jigle parameters from the secondary object
            my $jig = $secondary->jiggle;
            throw OMP::Error::FatalError(
                'Jiggle configuration is not available')
                unless defined $jig;

            # we need to know how many points are in the pattern
            $npts = $jig->npts;

            # Get the requested integration time per point
            $secs_per_point = $info{secsPerJiggle};
        }
        else {
            $secs_per_point = $info{secsPerCycle};
        }

        # Number of frequency switches
        my $nfreqs = 2;

        # Calculate the duration of a single run round the jiggle pattern
        my $pattern_length = $jos->step_time * $nfreqs * $npts;

        # The total amount of observing time is pretty straightforward
        # (ignoring number of offsets)
        my $total_time = $secs_per_point * $npts;

        # Maximum allowed time per sequence
        # if the step time means that we can not get round the pattern in this
        # time we have no choice but to change that time
        my $max_time_on = max(
            OMP::Config->getData('acsis_translator.freqsw_max_seq_length'),
            $pattern_length);

        # Number of cycles required to observe for the requested total time.
        my $num_cycles = ceil($total_time / $max_time_on);
        $jos->num_cycles($num_cycles);

        # Calculate how many steps per cycle we need at each jiggle position. This
        # is the total number of repeats of the jiggle pattern divided by num_cycles.
        my $jos_mult = ceil($secs_per_point / ($nfreqs * $jos->step_time * $num_cycles));
        $jos->jos_mult($jos_mult);

        # Force steps_btwn_refs to be the steps between cals
        $jos->steps_btwn_refs($jos->steps_btwn_cals);

        $self->output(
            "Frequency Switch JOS parameters:\n",
            "\tRequested integration time (ON+OFF) per sky position: $secs_per_point secs\n",
            "\tTime to complete jiggle pattern once : $pattern_length secs\n",
            "\tNumber of times round the pattern each cycle: $jos_mult\n",
            "\tNumber of frequency switches: $nfreqs\n",
            "\tNumber of cycles calculated: $num_cycles\n",
            "\tActual integration time per sky position:"
                . ($jos_mult * $nfreqs * $num_cycles * $jos->step_time) . "\n");
    }
    elsif ($info{observing_mode} =~ /grid/) {
        # N.B. The NUM_CYCLES has already been set to
        # the number of requested integrations
        # above except that NUM_CYCLES is now overriden in this recipe unless NUM_CYCLES
        # is > 1 (indicating an old program).

        throw OMP::Error::TranslateFail(
            "Requested integration time (secsPerCycle) is 0")
            if ! exists $info{secsPerCycle}
            || ! defined $info{secsPerCycle}
            || $info{secsPerCycle} <= 0;

        # However, we need to re-calculate all to take max_time_between_refs
        # ($refgap) into regard. Basically NUM_CYCLES need to be based on
        # $refgap unless the secsPerCycle is really short.

        # Calculate max_time_on and total integration time requested
        my $total_time = $num_cycles * $info{secsPerCycle};
        my $max_time_on = min($info{secsPerCycle}, $refgap);

        # For pol continuous spin we just need enough time for a single rotation
        # of the waveplate and we know that immediately in terms of the number of steps
        # required
        my $jos_min;
        if ($self->is_pol_spin(%info)) {
            $jos_min = OMP::Config->getData('acsis_translator.steps_per_cycle_pol');
            $max_time_on = $jos_min * $self->step_time($cfg, %info);
        }

        # if we are in pol step and integrate mode we need to scale the requested
        # total time by the number of waveplate positions so that the total
        # number of cycles is calculated correctly.
        my $nwplate = 1;
        if ($self->is_pol_step_integ(%info)) {
            $nwplate = @{$info{waveplate}};
        }

        # Recalculate number of cycles unless we already have num_cycles > 1
        # We do this because historically, the OT allowed people to specify the
        # number of cycles - that is until we realised it was dangerous and wrong
        my $recalc;
        if ($num_cycles == 1) {
            $num_cycles = ceil($total_time / ($nwplate * $max_time_on));
            $jos->num_cycles($num_cycles);
            $recalc = 1;
        }

        # First JOS_MIN
        # This is the number of samples on each grid position
        # so = secsPerCycle / STEP_TIME
        $jos_min = ceil($total_time
                / $nwplate
                / $num_cycles
                / $self->step_time($cfg, %info))
            unless defined $jos_min;  # pol override
        $jos->jos_min($jos_min);

        # Recalculate cal time for pol step and integrate to take into account a new
        # jos min
        my $recalc_cal_gap;
        if ($nwplate > 1) {
            my $new = ($jos_min * 4 * 2) - 1;
            my $old = $jos->steps_btwn_cals;
            $jos->steps_btwn_cals($new);
            $recalc_cal_gap = 1 if $new != $old;
        }

        # Sharing the off?

        # Need to know how many offsets we have (ask the %info hash rather than
        # querying the TCS object and obsArea.
        my $Noffsets = 1;
        $Noffsets = scalar(@{$info{offsets}})
            if (exists $info{offsets}
            && defined $info{offsets});

        # For a simple GRID/PSSW observation we ignore separateOffs from user
        # if there is only one offset position or if the JOS can only observe
        # a single off position before going to reference. Note that the OT
        # tries to default this behaviour but does not itself take into account
        # number of offsets and there are older programs such as the standards
        # that will default to shared offs without updating.
        # Do not override separateOffs flag if we are spinning the polarimeter
        my $separateOffs = $info{separateOffs};
        if (! $self->is_pol_spin(%info)) {
            if ($jos_min > ($jos->steps_btwn_refs() / 2)) {
                # can only fit in a single JOS_MIN in steps_btwn refs so separate offs
                $separateOffs = 1;
            }
            elsif ($Noffsets == 1) {
                # 1 sky position so we prefer not to share so that we can see all the spectra
                $separateOffs = 1;
            }
        }
        $jos->shareoff($separateOffs ? 0 : 1);

        $self->output(
            "Grid JOS parameters:\n",
            "\tRequested integration (ON) time per grid position: $info{secsPerCycle} secs\n",
            "\t" . ($info{continuumMode} ? "Continuum" : "Spectral Line")
                . " mode enabled\n",
            "\tOffs are " . ($jos->shareoff ? "" : "not ") . "shared\n",
            "\tNumber of steps per on: $jos_min\n");

        if ($num_cycles > 1 && $recalc) {
            $self->output("\tNumber of cycles calculated: $num_cycles\n");
        }
        if ($recalc_cal_gap) {
            $self->output("\tSteps between cals recalculated to be "
                    . $jos->steps_btwn_cals
                    . "\n");
        }

        $self->output("\tActual integration time per grid position: "
                . ($jos_min * $num_cycles * $nwplate * $jos->step_time)
                . " secs\n");
    }
    elsif ($info{observing_mode} eq 'jiggle_pssw') {
        # We know the requested time per point
        # we know how many points in the pattern
        # We know if have to break the integration over multiple cycles

        throw OMP::Error::TranslateFail(
            "Requested integration time (secsPerJiggle) is 0")
            if ! exists $info{secsPerJiggle}
            || ! defined $info{secsPerJiggle}
            || $info{secsPerJiggle} <= 0;

        # Get the full jigle parameters from the secondary object
        my $jig = $self->get_jiggle($cfg);

        # The step_time calculation has already taken into account the time between refs

        # How many steps do we need per jiggle position TOTAL
        my $total_steps_per_jigpos = $info{secsPerJiggle} / $jos->step_time;

        # Number of times we can go round in the time between refs
        my $times_round_pattern_per_seq = min(
            $total_steps_per_jigpos,
            max(1, int($jos->steps_btwn_refs / $jig->npts)));

        # number of repeats (cycles)
        my $num_cycles = POSIX::ceil(
            $total_steps_per_jigpos / $times_round_pattern_per_seq);

        # This gives a JOS_MIN and NUM_CYCLES of
        $jos->jos_min($jig->npts * $times_round_pattern_per_seq);
        $jos->num_cycles($num_cycles);

        # Sharing the off?
        $jos->shareoff($info{separateOffs} ? 0 : 1);

        $self->output(
            "Jiggle/PSSW JOS parameters:\n",
            "\tRequested integration (ON) time per position: $info{secsPerJiggle} secs "
                . "($total_steps_per_jigpos steps)\n",
            "\t" . ($info{continuumMode} ? "Continuum" : "Spectral Line")
                . " mode enabled\n",
            "\tOffs are " . ($jos->shareoff ? "" : "not ") . "shared\n",
            "\tNumber of steps per on: " . $jos->jos_min . "\n",
            "\tNumber of points in jiggle pattern: " . $jig->npts . "\n",
            "\tNumber of cycles calculated: $num_cycles\n",
            "\tActual integration time per grid position: "
                . ($times_round_pattern_per_seq * $num_cycles * $jos->step_time)
                . " secs\n");
    }
    else {
        throw OMP::Error::TranslateFail(
            "Unrecognized observing mode for JOS configuration '$info{observing_mode}'");
    }

    # Non science observing types
    if ($info{obs_type} =~ /focus/) {
        $jos->num_focus_steps($info{focusPoints});
        $jos->focus_step($info{focusStep});
        $jos->focus_axis($info{focusAxis});
    }

    # Tasks can be worked out by seeing which objects are configured.
    # This is done automatically on stringification of the config object
    # so we do not need to do it here

    # store it
    $cfg->jos($jos);
}

=item B<correlator>

Calculate the hardware correlator mapping from the receptor to the spectral
window.

    $trans->correlator($cfg, %info);

=cut

sub correlator {
    my $self = shift;
    my $cfg = shift;
    my %info = @_;

    # get the acsis configuration
    my $acsis = $cfg->acsis;
    throw OMP::Error::FatalError('ACSIS setup is not available')
        unless defined $acsis;

    # get the spectral window information
    my $spwlist = $acsis->spw_list();
    throw OMP::Error::FatalError(
        'Spectral Window configuration is not available')
        unless defined $spwlist;

    # get the hardware map
    my $hw_map = $self->hardware_map;

    my $synth_status = _get_lo2_synth_status();

    # Now get the receptors of interest for this observation
    my $frontend = $cfg->frontend;
    throw OMP::Error::FatalError('Frontend setup is not available')
        unless defined $frontend;

    # and only worry about the pixels that are switched on
    my @rec = $frontend->active_receptors;

    # Are we using a sideband-separating receiver?  If so look up the receptor sidebands.
    my $sb_mode = $frontend->sb_mode();
    my $receptor_sideband = undef;
    if ($sb_mode eq '2SB') {
        my $inst = $cfg->instrument_setup();
        throw OMP::Error::FatalError('instrument setup not available')
            unless defined $inst;

        $receptor_sideband = {
            map {
                my $rec_sb = uc $inst->receptor_sideband($_);
                throw OMP::Error::FatalError(
                    "receptor sideband '$rec_sb' missing or not recognized for $sb_mode observation")
                    unless $rec_sb eq 'LSB' || $rec_sb eq 'USB';

                $_ => $rec_sb;
            } @rec };
    }
    elsif ($sb_mode ne 'SSB' and $sb_mode ne 'DSB') {
        throw OMP::Error::FatalError(
            "frontend sideband mode '$sb_mode' not recognized");
    }

    # All of the subbands that need to be allocated
    my %subbands = $spwlist->subbands;

    # Mapping from image to signal spectral windows.
    my $image_spws = $info{'freqconfig'}->{'image_spws'};

    # Determine possible slot orderings.
    my $num_slots;
    my @possible_slot_mappings = (undef);
    do {
        throw OMP::Error::FatalError('No active receptors appear to be available')
            unless scalar @rec;
        my @hwmap = $hw_map->receptor($rec[0]);
        $num_slots = scalar @hwmap;
        throw OMP::Error::FatalError('First receptor is not in the hardware map')
            unless $num_slots;

        my @subband_slots = map {$subbands{$_}->numcm}
            grep {not exists $image_spws->{$_}} sort keys %subbands;
        throw OMP::Error::FatalError(
            "Insufficient slots available - have $num_slots but need " . (sum @subband_slots))
            if $num_slots < sum @subband_slots;

        # Make all combinations of slot numbers and then select those allowable.
        @possible_slot_mappings = grep {
            my @mapping = @$_;
            my $ok = 1;
            my $i = 0;
            foreach my $slots (@subband_slots) {
                # Chained modes ($slots = 2) must start on an even CM (0 or 2)
                # and comprise sequential CMs.
                $ok = 0 if (($slots > 1) && ($mapping[$i] % 2))
                    || ! all {
                        $mapping[$i + $_] == $mapping[$i] + $_
                    } 1 .. ($slots - 1);
                $i += $slots;
            }
            $ok;
        } _make_combinations(0 .. ($num_slots - 1));

        $self->output(
            "Correlator configuration:\n",
            "\tNumber of slots: $num_slots\n",
            "\tSubband slots: [" . (join ', ', @subband_slots) . "]\n",
            "\tPossible orderings: "
                . (join "\n\t\t", map {join ' ', map {'(' . (join ',', @$_) . ')'} @$_}
                _array_in_blocks(6, @possible_slot_mappings)) . "\n",
        );
    };

    # Try each slot mapping to find one where the required
    # LO2 synthesizers are operational.
    foreach my $slot_mapping (@possible_slot_mappings) {
        # CM and DCM bandwidth modes
        my @cm_bwmodes;
        my @dcm_bwmodes;
        my @cm_map;
        my @sbmodes;

        # lookup from lo2 id to spectral window
        my @lo2spw;

        # Record the slot in which each signal SPW starts, so we can use the
        # same slots for the corresponding image SPWs.
        my %slot_start_spw = ();

        # Keep track of the hardware map "slot number" which we are allocating.
        # This will advance every time we allocate a signal spectral window.
        my $n_slot = 0;

        # loop over subbands
        foreach my $spwid (sort keys %subbands) {
            my $sb = $subbands{$spwid};

            my $bwmode = $sb->bandwidth_mode;
            my $sideband = ($sb->fe_sideband > 0) ? 'USB' : 'LSB';
            my $n_cm = $sb->numcm;

            # Determine hardware map slot where this SPW should start -- either our
            # current counter, which is then advanced, or wherever the matching
            # signal SPW started.
            my $slot_start = undef;
            my $image_spw = undef;
            unless (exists $image_spws->{$spwid}) {
                $slot_start = $slot_start_spw{$spwid} = $n_slot;
                $n_slot += $n_cm;
            }
            else {
                $image_spw = $image_spws->{$spwid};

                throw OMP::Error::FatalError(
                    "Spectral window $spwid is the image of $image_spw but that SPW has not yet been allocated")
                    unless exists $slot_start_spw{$image_spw};

                throw OMP::Error::FatalError(
                    "Spectral window $spwid is the image of $image_spw but they use different numbers of slots")
                    unless $n_cm == $subbands{$image_spw}->numcm;

                $slot_start = $slot_start_spw{$image_spw};

                throw OMP::Error::FatalError(
                    "Spectral window $spwid is the image of $image_spw but they use the same sideband ($sideband)")
                    if $sideband eq
                    (($subbands{$image_spw}->fe_sideband > 0) ? 'USB' : 'LSB');
            }

            # for each receptor, we need to assign all the subbands to the correct
            # hardware
            my $n_rec_allocated = 0;
            for my $r (@rec) {
                # If this is a sideband-separating observation, check the receptor sideband.
                if (defined $receptor_sideband) {
                    next unless $receptor_sideband->{$r} eq $sideband;
                }

                # Get the CM mapping for this receptor
                my @hwmap = $hw_map->receptor($r);
                throw OMP::Error::FatalError(
                    "Receptor '$r' is not available in the ACSIS hardware map!")
                    unless @hwmap;

                # Check that the number of slots is consistent with the other receptors.
                throw OMP::Error::FatalError(
                    "Receptor '$r' has different number of slots than the first ($num_slots)")
                    unless $num_slots == scalar @hwmap;

                throw OMP::Error::FatalError(
                    "Slot mapping size does not match the number of slots!")
                    if (defined $slot_mapping and $#hwmap != $#$slot_mapping);

                # Some configurations actually use multiple correlator modules in
                # a single subband so we need to take this into account when
                # calculating the mapping.
                #
                # Additionally it is not possible for a mode that uses
                # 2 correlator modules to start on an odd slot (so a dual CM mode
                # can either start at CM 0 or CM 2, not 1 or 3). The OT should be
                # ensuring that this latter problem never occurs.
                for (my $i = 0; $i < $n_cm; $i ++) {
                    my $slot_i = $slot_start + $i;

                    throw OMP::Error::TranslateFail(
                        "The observation specified "
                        . ($slot_i + 1) . " (or more) subbands but there are only "
                        . @hwmap . " slots available for receptor '$r'")
                        if $slot_i > $#hwmap;

                    my $hw = $hwmap[(defined $slot_mapping)
                        ? $slot_mapping->[$slot_i]
                        : $slot_i];

                    my $cmid = $hw->{CM_ID};
                    my $dcmid = $hw->{DCM_ID};
                    my $quadnum = $hw->{QUADRANT};
                    my $sbmode = $hw->{SB_MODES}->[0];
                    my $lo2id = $hw->{LO2};

                    # Correlator uses the standard bandwidth mode
                    $cm_bwmodes[$cmid] = $bwmode;

                    # DCM just wants the bandwidth without the channel count
                    my $dcmbw = $bwmode;
                    $dcmbw =~ s/x.*$//;
                    $dcm_bwmodes[$dcmid] = $dcmbw;

                    # hardware mapping to spectral window ID
                    my %map = (
                        CM_ID => $cmid,
                        DCM_ID => $dcmid,
                        RECEPTOR => $r,
                        SPW_ID => $spwid,
                    );

                    $cm_map[$cmid] = \%map;

                    # Quadrant mapping to subband mode is fixed by the hardware map
                    if (defined $sbmodes[$quadnum]) {
                        if ($sbmodes[$quadnum] != $sbmode) {
                            throw OMP::Error::FatalError(
                                "Subband mode for quadrant $quadnum does not match previous setting\n");
                        }
                    }
                    else {
                        $sbmodes[$quadnum] = $sbmode;
                    }

                    # Convert lo2id to an array index
                    $lo2id --;

                    if (defined $image_spw) {
                        unless (defined $lo2spw[$lo2id]) {
                            throw OMP::Error::FatalError(
                                "LO2 #$lo2id is being allocated to $spwid (image of $image_spw) but has no existing assignment\n");
                        }
                        elsif ($lo2spw[$lo2id] ne $image_spw) {
                            throw OMP::Error::FatalError(
                                "LO2 #$lo2id is associated with spectral windows $spwid (image of $image_spw) AND $lo2spw[$lo2id]\n");
                        }
                    }
                    elsif (defined $lo2spw[$lo2id]) {
                        if ($lo2spw[$lo2id] ne $spwid) {
                            throw OMP::Error::FatalError(
                                "LO2 #$lo2id is associated with spectral windows $spwid AND $lo2spw[$lo2id]\n");
                        }
                    }
                    else {
                        $lo2spw[$lo2id] = $spwid;
                    }
                }

                $n_rec_allocated ++;
            }

            # Check that we found some receptors matching the requirements for
            # this subband (namely the correct sideband at the moment).
            throw OMP::Error::FatalError(
                "No receptors allocated for $spwid subband ($sideband)")
                unless $n_rec_allocated;
        }

        # Set the LO2. First we need to check that values are available that were
        # calculated previously
        throw OMP::Error::FatalError(
            "Somehow the LO2 settings were never calculated")
            unless exists $info{freqconfig}->{LO2};

        # Supply default LO2 frequency to avoid tuning issues with LO2 synthesizers.
        my @lo2 = map {
            (not $synth_status->{'high'}->[$_])
                ? 7.5e9
                : ((not $synth_status->{'low'}->[$_]) ? 8.5e9 : undef)
        } 0 .. 3;

        for my $i (0 .. $#lo2spw) {
            my $spwid = $lo2spw[$i];
            next unless defined $spwid;

            # sanity check never hurts
            throw OMP::Error::FatalError(
                "Spectral window $spwid does not seem to exist in LO2 array")
                unless exists $info{freqconfig}->{LO2}->{$spwid};

            # store it
            $lo2[$i] = $info{freqconfig}->{LO2}->{$spwid};
        }

        # Check whether desired LO2 synthesizers are inoperative.
        # Note: the acsisIf code uses this test: if (frequency <= 7999.9)
        my $n_synth_err = 0;
        for my $lo2index (0 .. 3) {
            next unless defined $lo2[$lo2index];
            my $synth = ($lo2[$lo2index] > 7.9999e9) ? 'high' : 'low';
            if (not $synth_status->{$synth}->[$lo2index]) {
                $n_synth_err ++;
                $self->output(
                    sprintf "\tFor mapping (%s) LO2 #%i (%i counting from 0) %s synth. unavailable (%.3f GHz requested)\n",
                    ((defined $slot_mapping) ? (join ',', @$slot_mapping) :  'default'),
                    ($lo2index + 1), $lo2index,
                    $synth, $lo2[$lo2index] / 1.0e9);
            }
        }
        next if $n_synth_err;

        $self->output(
            (sprintf "\tSelected slot order: [%s]\n",
                ((defined $slot_mapping) ? (join ', ', @$slot_mapping) :  'default')),
            (sprintf "\tLO2 tuning: [%s]\n",
                (join ', ', map {sprintf '%.3f', $_ / 1.0e9} @lo2)),
            map {sprintf "\tModule %s: %s %s %s\n",
                    $cm_map[$_]->{'CM_ID'}, $cm_map[$_]->{'RECEPTOR'},
                    $cm_map[$_]->{'SPW_ID'}, $cm_bwmodes[$_]
                } grep {defined $cm_map[$_]} 0 .. $#cm_map
        );

        # Now store the mappings in the corresponding objects
        my $corr = JAC::OCS::Config::ACSIS::ACSIS_CORR->new();
        my $if = JAC::OCS::Config::ACSIS::ACSIS_IF->new();
        my $map = JAC::OCS::Config::ACSIS::ACSIS_MAP->new();

        # to decide on CORRTASK mapping
        $map->hw_map($hw_map);

        # Store the relevant arrays
        $map->cm_map(@cm_map);
        $if->bw_modes(@dcm_bwmodes);
        $if->sb_modes(@sbmodes);
        $corr->bw_modes(@cm_bwmodes);

        $if->lo2freqs(@lo2);

        # Set the LO3 to a fixed value (all the test files do this)
        # A string since this is meant to be hard-coded to be exactly this by the DTD
        $if->lo3freq("2000.0");

        # store in the ACSIS object
        $acsis->acsis_corr($corr);
        $acsis->acsis_if($if);
        $acsis->acsis_map($map);

        return;
    }

    throw OMP::Error::FatalError(
        "Unable to find a slot mapping where the required LO2 synthesizers are available.");
}

sub _get_lo2_synth_status {
    return {
        map {
            my @status =
                OMP::Config->getData('acsis_translator.lo2_synth_status_' . $_);
            throw OMP::Error::FatalError(
                'Wrong number of elements in lo2_synth_status config parameter')
                unless 4 == scalar @status;
            $_ => \@status;
        } qw/low high/
    };
}

# Create all possible orderings of the given list of items.
sub _make_combinations {
    return [@_] if 2 > scalar @_;

    return map {
        my $i = $_;
        map {[$_[$i], @$_]} _make_combinations(
            map {$_[$_]} grep {$_ != $i} 0 .. $#_)

    } 0 .. $#_;
}

# Split the given list of items into blocks of the specified size.
sub _array_in_blocks {
    my $size = shift;
    my @blocks = (my $block = []);
    foreach (@_) {
        push @blocks, ($block = []) if $size <= scalar @$block;
        push @$block, $_;
    }
    return @blocks;
}

=item B<create_image_subsystems>

Adds additional subsystem information for the image sideband.

This method only applies to 2SB receivers and if the "auto_image_subsys_2sb"
configuration parameter is enabled.

Note: the image subsystems are added to the end of the subsystems
list -- we may assume later that we will find all non-image subsystems
first.

=cut

sub create_image_subsystems {
    my $self = shift;
    my $cfg = shift;
    my %info = @_;

    my $frontend = $cfg->frontend();
    throw OMP::Error::FatalError('frontend setup is not available')
        unless defined $frontend;

    return unless $frontend->sb_mode() eq '2SB';

    return unless OMP::Config->getData('acsis_translator.auto_image_subsys_2sb');

    my $subsystems = $info{'freqconfig'}->{'subsystems'};
    my $n_subsys = scalar @$subsystems;

    my $max_spectrum_id = max map {$_->{'spectrum_id'}} @$subsystems;

    for (my $i = 0; $i < $n_subsys; $i ++) {
        # Create a copy of the subsystem information hash.
        my $copy = Storable::dclone($subsystems->[$i]);

        $copy->{'spectrum_id'} += $max_spectrum_id;

        # Blank the transition and species information.
        $copy->{'transition'} = 'No Line';
        $copy->{'species'} = 'No Line';

        # Record of which subsystem this is a copy.
        $copy->{'image_of_subsystem'} = $i;

        # Switch to the other sideband.
        $copy->{'sideband'} = ($copy->{'sideband'} eq 'USB') ? 'LSB' : 'USB';

        # Exchange the rest and image frequencies.
        $copy->{'rest_freq'} = $copy->{'image_freq'};
        $copy->{'image_freq'} = $subsystems->[$i]->{'rest_freq'};

        push @$subsystems, $copy;
    }
}

=item B<line_list>

Configure the line list information.

    $trans->line_list($cfg, %info);

=cut

sub line_list {
    my $self = shift;
    my $cfg = shift;
    my %info = @_;

    # get the acsis configuration
    my $acsis = $cfg->acsis;
    throw OMP::Error::FatalError('ACSIS setup is not available')
        unless defined $acsis;

    # Get the frequency information
    my $freq = $info{freqconfig}->{subsystems};
    my %lines;
    for my $s (@$freq) {
        my $transition = $self->_safe_transition_name($s->{transition});
        my $base_key = JAC::OCS::Config::ACSIS::LineList->moltrans2key(
            $s->{species}, $transition);

        my $freq = $s->{rest_freq};

        # have we used this before?
        my $key = $base_key;
        for (my $counter = 1; exists $lines{$key}; $counter ++) {
            # if the frequency is the same we should not register the line list
            # object but we still need to associate with the subsystem. If the rest frequency
            # differs we need to tweak the key to make it unique.
            last if $lines{$key}->restfreq == $freq;

            # Tweak the key
            $key = sprintf('%s_%s', $base_key, $counter);
        }

        # store the reference key in the hash
        $s->{rest_freq_ref} = $key;

        # if the key is identical, we have already stored the details so can skip
        next if exists $lines{$key};

        # store the new value
        $lines{$key} = JAC::OCS::Config::ACSIS::Line->new(
            RestFreq => $freq,
            Molecule => $s->{species},
            Transition => $transition);
    }

    # Create the line list object
    my $ll = JAC::OCS::Config::ACSIS::LineList->new();
    $ll->lines(%lines);
    $acsis->line_list($ll);
}

=item B<spw_list>

Add the spectral window information to the configuration.

    $trans->spw_list($cfg, %info);

=cut

sub spw_list {
    my $self = shift;
    my $cfg = shift;
    my %info = @_;

    # get the acsis configuration
    my $acsis = $cfg->acsis;
    throw OMP::Error::FatalError('ACSIS setup is not available')
        unless defined $acsis;

    # Get the frontend object for the sideband
    # Hopefully we will not need to do this if ACSIS can be tweaked to get it from
    # frontend XML itself
    my $fe = $cfg->frontend;
    throw OMP::Error::FatalError(
        'frontend configuration is not available during spectral window processing')
        unless defined $fe;

    # Get the frequency information for each subsystem
    my $freq = $info{freqconfig}->{subsystems};

    # Default baseline fitting mode will probably depend on observing mode
    my $defaultPoly = 1;

    # Get the DR information
    my %dr;
    %dr = %{$info{data_reduction}} if exists $info{data_reduction};
    if (! keys %dr) {
        %dr = (
            window_type => 'truncate',
            fit_polynomial_order => $defaultPoly,
        ); # defaults
    }
    else {
        $dr{window_type} ||= 'truncate';
        $dr{fit_polynomial_order} ||= $defaultPoly;

        # default to number if DEFAULT.
        $dr{fit_polynomial_order} = $defaultPoly
            unless $dr{fit_polynomial_order} =~ /\d/;
    }

    # Figure out the baseline fitting. We either have no baseline,
    # fractional baseline or manual baseline
    # Baselines are an array of interval objects
    # empty array is fine
    my $frac; # fraction of bandwidth to use for baseline (depends on subsystem)
    my @baselines;
    if (exists $dr{baseline} && defined $dr{baseline}) {
        if (ref($dr{baseline})) {
            # array of OMP::Range objects
            @baselines = map {
                JAC::OCS::Config::Interval->new(
                    Min => $_->min,
                    Max => $_->max,
                    Units => $_->units);
            } @{$dr{baseline}};
        }
        else {
            # scalar fraction implies two baseline regions
            $frac = $dr{baseline};
        }
    }

    # The LO2 settings indexed by spectral window. We should consider simply adding
    # this to the SpectralWindow object as an accessor or in conjunction with f_park
    # derive it on demand.
    my %lo2spw;

    # Create a hash to store the mapping from image spectral windows to the
    # corresponding signal window.
    my $image_spws = $info{'freqconfig'}->{'image_spws'} = {};

    # Spectral window objects
    my %spws;
    my $spwcount = 1;
    for my $ss (@$freq) {
        # Get the sideband and convert it to a sign -1 == LSB +1 == USB
        my $fe_sign = _sideband_sign($ss->{'sideband'});

        my $spw = JAC::OCS::Config::ACSIS::SpectralWindow->new(
            spectrum_id => $ss->{'spectrum_id'});

        $spw->rest_freq_ref($ss->{rest_freq_ref});
        $spw->fe_sideband($fe_sign);
        $spw->baseline_fit(
            function => "polynomial",
            degree => $dr{fit_polynomial_order})
            if exists $dr{fit_polynomial_order};

        # Create an array of IF objects suitable for use in the spectral
        # window object(s). The ref channel and the if freq are per-sideband
        my @ifcoords = map {
            JAC::OCS::Config::ACSIS::IFCoord->new(
                if_freq => $ss->{if_per_subband}->[$_],
                nchannels => $ss->{nchan_per_sub},
                channel_width => $ss->{channwidth},
                ref_channel => $ss->{if_ref_channel}->[$_])
        } (0 .. ($ss->{nsubbands} - 1));

        # Counting for hybridized spectra still assumes the original number
        # of channels in the units. We assume that the fraction specified
        # is a fraction of the hybrid baseline but we need to correct
        # for the overlap when calculating the actual position of the baseline
        if (defined $frac) {
            # get the full number of channels
            my $nchan_full = $ss->{nchannels_full};

            # Get the hybridized number of channels
            my $nchan_hyb = $ss->{channels};
            my $nchan_bl = int($nchan_hyb * $frac / 2);

            # number of channels chopped from each end
            my $nchop = int(($nchan_full - $nchan_hyb) / 2);

            # Include a small offset from the very end channel of the spectrum
            # and convert to channels
            my $edge_frac = 0.01;
            my $nedge = int($nchan_hyb * $edge_frac);

            # Calculate total offset
            my $offset = $nchop + $nedge;

            @baselines = (
                JAC::OCS::Config::Interval->new(
                    Units => 'pixel',
                    Min => $offset,
                    Max => ($nchan_bl + $offset),
                ),
                JAC::OCS::Config::Interval->new(
                    Units => 'pixel',
                    Min => ($nchan_full - $offset - $nchan_bl),
                    Max => ($nchan_full - $offset),
                ),
            );
        }

        $spw->baseline_region(@baselines) if @baselines;

        # Line region for pointing and focus
        # This will be ignored in subbands
        if ($info{obs_type} ne 'science') {
            $spw->line_region(
                JAC::OCS::Config::Interval->new(
                    Units => 'pixel',
                    Min => 0,
                    Max => ($ss->{nchannels_full} - 1)));
        }

        # hybrid or not?
        if ($ss->{nsubbands} == 1) {
            # no hybrid. Just store it
            $spw->window('truncate');
            $spw->align_shift($ss->{align_shift}->[0]);
            $spw->bandwidth_mode($ss->{bwmode});
            $spw->if_coordinate($ifcoords[0]);

        }
        elsif ($ss->{nsubbands} == 2) {
            my %hybrid;
            my $sbcount = 1;
            for my $i (0 .. $#ifcoords) {
                my $sp = JAC::OCS::Config::ACSIS::SpectralWindow->new;
                $sp->bandwidth_mode($ss->{bwmode});
                $sp->if_coordinate($ifcoords[$i]);
                $sp->fe_sideband($fe_sign);
                $sp->align_shift($ss->{align_shift}->[$i]);
                $sp->rest_freq_ref($ss->{rest_freq_ref});
                $sp->window($dr{window_type});
                my $id = "SPW" . $spwcount . "." . $sbcount;
                $hybrid{$id} = $sp;
                $lo2spw{$id} = $ss->{lo2}->[$i];
                $sbcount ++;
            }

            # Store the subbands
            $spw->subbands(%hybrid);

            # Create global IF coordinate object for the hybrid. For some reason
            # this does not take overlap into account but does take the if of the first subband
            # rather than the centre IF
            my $if = JAC::OCS::Config::ACSIS::IFCoord->new(
                if_freq => $ss->{if_per_subband}->[0],
                nchannels => $ss->{nchannels_full},
                channel_width => $ss->{channwidth},
                ref_channel => ($ss->{nchannels_full} / 2));
            $spw->if_coordinate($if);
        }
        else {
            throw OMP::Error::FatalError(
                "Do not know how to process more than 2 subbands");
        }

        # Determine the Spectral Window label and store it in the output hash and
        # the subsystem hash
        my $splab = "SPW" . $spwcount;
        $spws{$splab} = $spw;
        $ss->{spw} = $splab;

        # store the LO2 for this only if it is not a hybrid
        # Cannot do this earlier since we need the splabel
        $lo2spw{$splab} = $ss->{lo2}->[0] if $ss->{nsubbands} == 1;

        # If this is an image subsystem, add the spectral window ID to the hash.
        if (exists $ss->{'image_of_subsystem'}) {
            my $ss_signal = $ss->{'image_of_subsystem'};
            throw OMP::Error::FatalError(
                "Signal SPW corresponding to image missing processed out of order")
                unless exists $freq->[$ss_signal]->{'spw'};
            $image_spws->{$splab} = $freq->[$ss_signal]->{'spw'};
        }

        $spwcount ++;
    }

    # Store the LO2
    $info{freqconfig}->{LO2} = \%lo2spw;

    # Create the SPWList
    my $spwlist = JAC::OCS::Config::ACSIS::SPWList->new;
    $spwlist->spectral_windows(%spws);

    # Store the data fiels. Just assume these are okay but probably need a template
    # file
    $spwlist->data_fields(
        spw_id => "SPEC_WINDOW_ID",
        doppler => 'FE.DOPPLER',
        fe_lo => 'FE.LO_FREQUENCY');

    # Store it
    $acsis->spw_list($spwlist);
}

=item B<_sideband_sign>

Get the sign associated with a sideband.  (+1 for USB and -1 for LSB.)

=cut

sub _sideband_sign {
    my $sb = shift;

    if ($sb eq 'LSB') {
        return -1;
    }

    if ($sb eq 'USB' or $sb eq 'BEST') {
        return 1;
    }

    throw OMP::Error::TranslateFail("Sideband is not recognised ($sb)");
}

=item B<acsisdr_recipe>

Configure the real time pipeline.

    $trans->acsisdr_recipe($cfg, %info);

=cut

sub acsisdr_recipe {
    my $self = shift;
    my $cfg = shift;
    my %info = @_;

    # get the acsis configuration
    my $acsis = $cfg->acsis;
    throw OMP::Error::FatalError('ACSIS setup is not available')
        unless defined $acsis;

    # Get the instrument we are using
    my $inst = lc($self->ocs_frontend($info{'instrument'}));
    throw OMP::Error::FatalError(
        'No instrument defined - needed to select correct dr_recipe file')
        unless defined $inst;

    # Get the observing mode or observation type for the DR recipe
    my $root;
    if ($info{obs_type} eq 'science') {
        # keyed on observing mode
        my $obsmode = $info{observing_mode};

        # POL mode does not have a special recipe
        $obsmode =~ s/_pol$//;

        # Spin is not special recipe
        $obsmode =~ s/_spin//;

        $obsmode = 'jiggle_chop' if $obsmode eq 'grid_chop';
        $obsmode = 'grid_pssw' if $obsmode eq 'jiggle_pssw';
        $obsmode = 'jiggle_freqsw' if $obsmode eq 'grid_freqsw';

        # Need to special case chop and chop-jiggle vs jiggle-chop
        if ($obsmode =~ /jiggle/) {
            # need the secondary configuration
            # first get the Secondary object, via the TCS
            my $tcs = $cfg->tcs;
            throw OMP::Error::FatalError('TCS setup is not available')
                unless defined $tcs;

            # ... and secondary
            my $secondary = $tcs->getSecondary();
            throw OMP::Error::FatalError(
                'Secondary configuration is not available')
                unless defined $secondary;

            # Get the information
            my $smu_mode = $secondary->smu_mode;

            if ($smu_mode eq 'chop' || $smu_mode eq 'chop_jiggle') {
                $obsmode = 'chop_jiggle';
            }
        }

        $root = $obsmode;
    }
    else {
        # keyed on observation type
        $root = $info{obs_type};
    }

    my $filename = undef;
    foreach my $suffix ("_$inst", '') {
        my $tryfile = File::Spec->catfile(
            $self->wiredir, 'acsis', $root . '_dr_recipe' . $suffix . '.ent');

        if (-e $tryfile) {
            $filename = $tryfile;
            last;
        }
    }

    # no files to find
    throw OMP::Error::FatalError(
        "Unable to find dr_recipe entity file with root $root")
        unless defined $filename;

    # Read the recipe itself
    my $dr = JAC::OCS::Config::ACSIS::RedConfigList->new(
        EntityFile => $filename,
        validation => 0);

    $acsis->red_config_list($dr);
    $self->output("Read ACSIS DR recipe from '$filename'\n");
    my $recipe_id = 'unknown version';
    do {
        my @nodes = $dr->_tree->findnodes('.//red_recipe_id');
        if (@nodes) {
            $recipe_id = $nodes[0]->textContent;
            $recipe_id =~ s/^\s*//;
            $recipe_id =~ s/\s*$//;
        }
    };

    # and now the mapping that is also recipe specific
    my $sl = JAC::OCS::Config::ACSIS::SemanticLinks->new(
        EntityFile => $filename,
        validation => 0);
    $acsis->semantic_links($sl);

    # and the basic gridder configuration
    my $g = JAC::OCS::Config::ACSIS::GridderConfig->new(
        EntityFile => $filename,
        validation => 0);
    $acsis->gridder_config($g);

    # and the basic gridder and spectrum writer configuration (optional)
    try {
        my $sw = JAC::OCS::Config::ACSIS::SWriterConfig->new(
            EntityFile => $filename,
            validation => 0);
        $acsis->swriter_config($sw) if defined $sw;
    }
    catch JAC::OCS::Config::Error::XMLConfigMissing with {
        # can be ignored
    };

    # Write the observing mode to the recipe
    my $rmode = $info{observing_mode};
    $rmode =~ s/_/\//g;
    $acsis->red_obs_mode($rmode);
    $acsis->red_recipe_id($recipe_id);
}

=item B<cubes>

Configure the output cube(s).

    $trans->cubes($cfg, %info);

=cut

sub cubes {
    my $self = shift;
    my $cfg = shift;
    my %info = @_;

    # get the acsis configuration
    my $acsis = $cfg->acsis;
    throw OMP::Error::FatalError('ACSIS setup is not available')
        unless defined $acsis;

    # Get the frontend configuration
    my $fe = $cfg->frontend;
    throw OMP::Error::FatalError('Frontend configuration is not available')
        unless defined $fe;

    # Get the instrument footprint
    my $inst = $cfg->instrument_setup;
    throw OMP::Error::FatalError('Instrument configuration is not available')
        unless defined $inst;

    my @footprint = $inst->receptor_offsets($fe->active_receptors);

    # Need to correct for any offset that we may be applying to BASE
    my $apoff = $self->tracking_offset($cfg, %info);

    # And also make it available as "internal hash format"
    my @footprint_h = $self->_to_offhash(@footprint);

    # shift instrument if FPLANE offset
    if (defined $apoff) {
        if ($apoff->system eq 'FPLANE') {
            throw OMP::Error::TranslateFail(
                "Non-zero position angle for focal plane offset is unexpected\n")
                if $apoff->posang->radians != 0.0;

            for my $pos (@footprint_h) {
                $pos->{OFFSET_DX} -= $apoff->xoffset->arcsec;
                $pos->{OFFSET_DY} -= $apoff->yoffset->arcsec;
            }

            if ($inst->name =~ /HARP/) {
                # Now rotate these coordinates by multiples of 90 deg to take
                # into account uncertainty of image rotator orientation and
                # merge them with the original set (duplicate positions don't
                # matter). We need 90 deg for edge receptors and 180 for corner receptors.
                for my $ang (90, 180, 270) {
                    my @rot_h = map {
                        my %temp = %$_;
                        ($temp{OFFSET_DX}, $temp{OFFSET_DY}) =
                            $self->PosAngRot($temp{OFFSET_DX}, $temp{OFFSET_DY}, $ang);
                        \%temp;
                    } @footprint_h;

                    push(@footprint_h, @rot_h);
                }
            }
        }
        else {
            throw OMP::Error::TranslateFail(
                "Trap for unwritten code when offset is not FPLANE");
        }
    }

    # Can we match position angles of the receiver with the rotated map or not? Use the focal station to decide
    my $matchpa;
    if ($inst->focal_station eq 'DIRECT') {
        $matchpa = 0;
    }
    else {
        # Assumes image rotator if on the Nasmyth
        $matchpa = 1;
    }

    # Create the cube list
    my $cl = JAC::OCS::Config::ACSIS::CubeList->new();

    # Get the subsystem information
    my $freq = $info{freqconfig}->{subsystems};

    # Find out the total number of gridders in this observation
    my ($nsync, $nreduc, $ngridder) = $self->determine_acsis_layout(
        $cfg, %info);
    throw OMP::Error::FatalError("Number of gridders unavailable!")
        unless defined $ngridder;

    # and the number of gridders per subsystem
    my $ngrid_per_spw = $ngridder / scalar(@$freq);

    # sanity check
    if ($ngrid_per_spw != int($ngrid_per_spw)) {
        throw OMP::Error::FatalError(
            "The number of gridders in use ($ngridder) does not divide equally by the number of subsystems ("
            . @$freq . ")");
    }

    # Now loop over subsystems to create cube specifications
    my %cubes;
    my $count = 1;
    for my $ss (@$freq) {
        # Create the cube(s). One cube per subsystem.
        my $cube = JAC::OCS::Config::ACSIS::Cube->new;
        my $cubid = "CUBE" . $count;

        # Data source
        throw OMP::Error::FatalError(
            "Spectral window ID not defined. Internal inconsistency")
            unless defined $ss->{spw};
        $cube->spw_id($ss->{spw});

        # Tangent point (aka group centre) is the base position without offsets
        # Not used if we are in a moving (eg PLANET) frame, if we are autoTarget
        # or indeed if we are not science. A case could be made for never bothering
        # since the translator always centres the map on the base position and that
        # is where ACSIS will centre it by default anyhow.
        $cube->group_centre($info{coords})
            if ($info{obs_type} eq "science"
            && $info{coords}->type eq 'RADEC'
            && ! $info{autoTarget});

        # Calculate Nyquist value for this map
        my $nyq = $self->nyquist(%info);

        # Until HARP comes we use TopHat for all observing modes
        # HARP without image rotator will require Gaussian.
        # This will need support for rotated coordinate frames in the gridder
        my $grid_func = "TopHat";
        $grid_func = "Gaussian" if $info{mapping_mode} =~ /^scan/;
        $cube->grid_function($grid_func);

        # Variable to indicate map coord override
        my $grid_coord;

        # The size and number of pixels depends on the observing mode.
        # For scan, we have a regular grid but the
        my ($nx, $ny, $mappa, $xsiz, $ysiz, $offx, $offy);
        if ($info{obs_type} eq 'skydip') {
            # Skydips do not need anything clever for display
            $nx = 1;
            $ny = 1;
            $mappa = 0;
            $xsiz = 1;
            $ysiz = 1;
            $offx = 0;
            $offy = 0;
        }
        elsif ($info{mapping_mode} =~ /^scan/) {
            # This will be more complicated for HARP since DY will possibly
            # be larger and we will need to take the receptor spacing into account

            # The X spacing depends on the requested sample time per map point
            # and the scan velocity
            $xsiz = $info{SCAN_VELOCITY} * $info{sampleTime};

            # For single pixel instrument define the Y pixel as the spacing
            # between scan rows. For HARP we probably want to be clever but for
            # now choose the pixel size to be the x pixel size.
            if ($inst->name =~ /HARP/) {
                $ysiz = $xsiz;
            }
            else {
                $ysiz = $info{SCAN_DY};
            }

            # read the map position angle
            $mappa = $info{MAP_PA};    # degrees

            # Requested map area must include room for overscan from the instrument
            # footprint. Be pessimistic since we can not know how the telescope will
            # overscan. (but we could be cleverer if we assumed a functioning rotator).
            # When we adjust the scanning in the TCS we will probably want to allow
            # a whole array footprint on each end)
            my $rad = $inst->footprint_radius->arcsec;

            # Increase the cube area for scan maps by one pixel in order
            # to use the same convention as the TCS: through the centers of
            # the outer pixels rather than around them.
            $nx = int((($info{MAP_WIDTH} + (2 * $rad)) / $xsiz) + 1.5);
            $ny = int((($info{MAP_HEIGHT} + (2 * $rad)) / $ysiz) + 1.5);

            $offx = ($info{OFFSET_DX} || 0);
            $offy = ($info{OFFSET_DY} || 0);

            # These should be rotated to the MAP_PA coordinate frame
            # if it is meant to be in the coordinate frame of the map
            # for now rotate to ra/dec.
            if ($info{OFFSET_PA} != 0) {
                ($offx, $offy) = $self->PosAngRot($offx, $offy, $info{OFFSET_PA});
            }
        }
        elsif ($info{mapping_mode} =~ /grid/i) {
            # Get the required offsets. These will always be in tracking coordinates TAN.
            my @offsets;
            @offsets = @{$info{offsets}}
                if (exists $info{offsets} && defined $info{offsets});

            # Should fix up earlier code to add SYSTEM
            # NOTE: we do now have this, but it is called OFFSET_SYSTEM, not SYSTEM,
            # so this adds a duplicate, possibly wrong, attribute.
            for (@offsets) {
                $_->{SYSTEM} = "TRACKING";
            }

            # Now convolve these offsets with the instrument footprint
            my @convolved = $self->convolve_footprint(
                $matchpa, \@footprint_h, \@offsets);

            # Now calculate the final grid
            ($nx, $ny, $xsiz, $ysiz, $mappa, $offx, $offy) = $self->calc_grid(
                $self->nyquist(%info)->arcsec, @convolved);
        }
        elsif ($info{mapping_mode} =~ /jiggle/i) {
            # Need to know:
            #  - the extent of the jiggle pattern
            #  - the footprint of the array. Assume single pixel

            # Get the jiggle information
            my $jig = $self->get_jiggle($cfg);
            throw OMP::Error::FatalError(
                'Jiggle configuration is not available')
                unless defined $jig;

            # Store the grid coordinate frame
            $grid_coord = $jig->system;

            # and the angle
            my $pa = $jig->posang->degrees;

            # Get the map offsets
            my @offsets = map {
                {
                    OFFSET_DX => $_->[0],
                    OFFSET_DY => $_->[1],
                    OFFSET_PA => $pa,
                }
            } $jig->spattern;

            # Convolve them with the instrument footprint
            my @convolved = $self->convolve_footprint(
                $matchpa, \@footprint_h, \@offsets);

            # Get the required telescope offsets. These will always be in tracking coordinates TAN.
            my @teloffsets;
            @teloffsets = @{$info{offsets}}
                if (exists $info{offsets} && defined $info{offsets});

            # Should fix up earlier code to add SYSTEM
            # NOTE: we do now have this, but it is called OFFSET_SYSTEM, not SYSTEM,
            # so this adds a duplicate, possibly wrong, attribute.
            for (@teloffsets) {
                $_->{SYSTEM} = "TRACKING";
            }

            # And convolve again
            @convolved = $self->convolve_footprint(
                $matchpa, \@convolved, \@teloffsets);

            # calculate the pattern without a global offset
            ($nx, $ny, $xsiz, $ysiz, $mappa, $offx, $offy) = $self->calc_grid(
                $self->nyquist(%info)->arcsec, @convolved);

            # get the global offset for this observation
            my $global_offx = ($info{OFFSET_DX} || 0);
            my $global_offy = ($info{OFFSET_DY} || 0);

            # rotate those offsets to the mappa
            if ($info{OFFSET_PA} != $mappa) {
                ($global_offx, $global_offy) = $self->PosAngRot(
                    $global_offx, $global_offy,
                    ($info{OFFSET_PA} - $mappa));
            }

            # add any offset from the unrolled offset iterator
            $offx += $global_offx;
            $offy += $global_offy;
        }
        else {
            # pointing is going to be a map based on the jiggle offset
            # and will be different for HARP
            # focus will probably be a single spectrum in continuum mode

            throw OMP::Error::TranslateFail(
                "Do not yet know how to size a cube for mode $info{observing_mode}");
        }

        throw OMP::Error::TranslateFail("Unable to determine X pixel size")
            unless defined $xsiz;
        throw OMP::Error::TranslateFail("Unable to determine Y pixel size")
            unless defined $ysiz;

        # Store the parameters
        $cube->pixsize(
            Astro::Coords::Angle->new($xsiz, units => 'arcsec'),
            Astro::Coords::Angle->new($ysiz, units => 'arcsec'));
        $cube->npix($nx, $ny);

        $cube->posang(Astro::Coords::Angle->new($mappa, units => 'deg'))
            if defined $mappa;

        # Decide whether the grid is regridding in sky coordinates or in AZEL
        # Focus is AZEL
        # Assume also that AZEL jiggles want AZEL maps (this includes POINTINGs)
        if ($info{obs_type} =~ /focus/i) {
            $cube->tcs_coord('AZEL');
        }
        elsif ((defined $info{jiggleSystem} && $info{jiggleSystem} eq 'AZEL')
                || (defined $grid_coord && $grid_coord eq 'AZEL')) {
            # For HARP jiggleSystem is needed because grid_coord will be FPLANE
            $cube->tcs_coord('AZEL');
        }
        else {
            $cube->tcs_coord('TRACKING');
        }

        # offset in pixels (note that for RA maps positive offset is
        # in opposite direction to grid)
        my $offy_pix = sprintf("%.4f", $offy / $ysiz) * 1.0;
        my $offx_pix = sprintf("%.4f", $offx / $xsiz) * 1.0;
        if ($cube->tcs_coord eq 'TRACKING') {
            $offx_pix *= -1.0;
        }

        $cube->offset($offx_pix, $offy_pix);

        # Currently always use TAN projection since that is what SCUBA uses
        $cube->projection("TAN");

        # Gaussian requires a FWHM and truncation radius
        if ($grid_func eq 'Gaussian') {
            # For an oversampled map, the SCUBA regridder has been analysed empirically
            # to determine an optimum smoothing gaussian HWHM of lambda / 5d ( 0.4 of Nyquist).
            # This compromises smoothness vs beam size. If the pixels are very large (larger than
            # the beam) we just assume that the user does not want to really smear across
            # pixels that large so we still use the beam. The gaussian convolution will probably
            # not work if you have 80 arcsec pixels and 10 arcsec gaussian

            # Use the SCUBA optimum ratios derived by Claire Chandler of
            # HWHM = lambda / 5D (ie 0.4 of Nyquist) or FWHM = lambda / 2.5D
            # (or 0.8 Nyquist).
            my $fwhm = $nyq->arcsec * 0.8;
            $cube->fwhm($fwhm);

            # Truncation radius is half the pixel size for TopHat
            # For Gausian we use 3 HWHM (that's what SCUBA used)
            $cube->truncation_radius($fwhm * 1.5);
        }
        else {
            # The gridder needs a non-zero truncation radius even if the gridding
            # technique does not use it! We have two choices. Either set a default
            # value here in the translator or make sure that the Config class
            # always fills in a blank. For now kluge in the translator to make sure
            # we do not exceed the smallest pixel.
            $cube->truncation_radius(min($xsiz, $ysiz) / 2);
        }

        # Work out what part of the spectral axis can be regridded
        # Number of pixels per channel
        my $npix_per_chan = $nx * $ny;

        # Max Number of channels allowed for the gridder
        my $max_nchan_per_gridder = $MAX_SLICE_NPIX / $npix_per_chan;

        # We want to chop off the noisy ends of the spectrum.
        # Currently the best way to do this is to exclude 12.5% on each side
        my $part_to_exclude = 0.125;

        # Number of channels to be gridded (without the noisy ends of the spectrum)
        my $channels_to_grid = $ss->{nchannels_full} * (1 - 2 * $part_to_exclude);

        # Number of channels requested per gridder
        my $nchan_per_gridder = $channels_to_grid / $ngrid_per_spw;

        # So the actual number for this gridder should be the minimum of these
        $nchan_per_gridder = min($nchan_per_gridder, $max_nchan_per_gridder);

        # and now the actual channel range for this subsystem can be calculated
        my $nchan_per_spw = int($nchan_per_gridder) * $ngrid_per_spw;

        my ($minchan, $maxchan);
        if ($nchan_per_spw >= $channels_to_grid) {
            $minchan = int(($ss->{nchannels_full} - 1) * $part_to_exclude);
            $maxchan = int(($ss->{nchannels_full} - 1) * (1 - $part_to_exclude));
        }
        else {
            my $half = int($nchan_per_spw / 2);
            my $midchan = int($ss->{nchannels_full} / 2);
            $maxchan = $midchan + $half - 1;
            $minchan = $midchan - $half;
        }

        my $int = JAC::OCS::Config::Interval->new(
            Min => $minchan,
            Max => $maxchan,
            Units => 'channel');
        $cube->spw_interval($int);

        $self->output(
            "Cube parameters [$cubid/" . $cube->spw_id . "]:\n",
            "\tDimensions: $nx x $ny\n",
            "\tPixel Size: $xsiz x $ysiz arcsec\n",
            "\tMap frame:  " . $cube->tcs_coord . "\n",
            "\tMap Offset: $offx, $offy arcsec ($offx_pix, $offy_pix) pixels\n",
            "\tGroup centre is "
                . (defined $cube->group_centre ? "" : "not ")
                . "defined\n",
            "\tMap PA:     $mappa deg\n",
            "\tSpectral channels: "
                . ($maxchan - $minchan + 1)
                . " as $int (cf "
                . ($ss->{nchannels_full})
                . " total)\n",
            "\tSlice size: "
                . ($nchan_per_gridder * $npix_per_chan * 4 / (1024 * 1024)) . " MB\n",
            "\tGrid Function: $grid_func\n");

        if ($grid_func eq 'Gaussian') {
            $self->output(
                "\t  Gaussian FWHM: " . $cube->fwhm() . " arcsec\n");
        }
        $self->output(
            "\t  Truncation radius: " . $cube->truncation_radius() . " arcsec\n");

        $cubes{$cubid} = $cube;
        $count ++;
    }

    # Store it
    $cl->cubes(%cubes);

    $acsis->cube_list($cl);
}

=item B<rtd_config>

Configure the Real Time Display.

    $trans->rtd_config($cfg, %info);

Currently this method is dumb, mainly because there is a lot of junk in the
rtd_config element that is machine depenedent rather than translation dependent.
The only information that should be provided by the translator is:

=over 4

=item

The spectral window of interest.

=item

Possibly the coordinate range of the spectral axis.

=back

=cut

sub rtd_config {
    my $self = shift;
    my $cfg = shift;
    my %info = @_;

    # get the acsis configuration
    my $acsis = $cfg->acsis;
    throw OMP::Error::FatalError('ACSIS setup is not available')
        unless defined $acsis;

    # Get the instrument we are using
    my $inst = lc($self->ocs_frontend($info{instrument}));
    throw OMP::Error::FatalError(
        'No instrument defined - needed to select correct RTD file !')
        unless defined $inst;

    # The filename is DR recipe dependent and optionally instrument dependent
    my $root;
    if ($info{obs_type} eq 'science') {
        # keyed on observing mode
        my $obsmode = $info{observing_mode};

        # POL is irrelevant
        $obsmode =~ s/_pol$//;

        # Spin is not special recipe
        $obsmode =~ s/_spin//;

        $obsmode = 'jiggle_chop' if $obsmode eq 'grid_chop';
        $obsmode = 'grid_pssw' if $obsmode eq 'jiggle_pssw';
        $obsmode = 'jiggle_freqsw' if $obsmode eq 'grid_freqsw';

        $root = $obsmode;
    }
    else {
        # keyed on observing type
        $root = $info{obs_type};

        # for skydip we do not care
        $root = 'grid_pssw' if $root eq 'skydip';
    }

    # Try with and without the instrument name
    my $filename;
    for my $suffix ($inst, "") {
        my $tryfile = File::Spec->catfile(
            $self->wiredir, 'acsis', $root . "_rtd"
            . ($suffix ? "_$suffix" : "") . ".ent");

        if (-e $tryfile) {
            $filename = $tryfile;
            last;
        }
    }

    # no files to find
    throw OMP::Error::FatalError(
        "Unable to find RTD entity file with root $root\n")
        unless defined $filename;

    $self->output("Read ACSIS RTD configuration $filename\n");

    # Read the entity
    my $il = JAC::OCS::Config::ACSIS::RTDConfig->new(
        EntityFile => $filename,
        validation => 0);

    $acsis->rtd_config($il);
}

=item B<simulator_config>

Configure the simulator XML. For ACSIS this actually goes into the
ACSIS xml and there is not a distinct task for simulation (the
simulated CORRTASKs read this simulator data).

=cut

sub simulator_config {
    my $self = shift;
    my $cfg = shift;
    my %info = @_;

    # We may want to get basic values from an entity file on disk and then configure
    # the observation specific elements

    # get the acsis configuration
    my $acsis = $cfg->acsis;
    throw OMP::Error::FatalError('ACSIS setup is not available')
        unless defined $acsis;

    # Get the cube definition
    my $cl = $acsis->cube_list;
    throw OMP::Error::FatalError('the ACSIS Cube List is not defined')
        unless defined $cl;

    # Get the spectral window definitions
    my $spwlist = $acsis->spw_list();
    throw OMP::Error::FatalError(
        'Spectral Window configuration is not available')
        unless defined $spwlist;

    # We create a cloud per cube definition
    my %cubes = $cl->cubes;

    # loop over all the cubes
    my @clouds;
    for my $cube (values %cubes) {
        my %thiscloud = (
            position_angle => 0,
            pos_z_width => 300,
            neg_z_width => 300,
            amplitude => 20,
        );

        # Spectral window is required so that we can choose a channel somewhere
        # in the middle
        my $spwint = $cube->spw_interval;
        throw OMP::Error::FatalError(
            "Simulation requires channel units but it seems this spectral window was configured differently. Needs fixing.\n")
            if $spwint->units ne 'channel';

        $thiscloud{z_location} = int(($spwint->min + $spwint->max) / 2);

        # Store the spectral window ID
        $thiscloud{spw_id} = $cube->spw_id;

        # offset centre
        my @offset = $cube->offset;

        # No. of pixels, x and y
        my @npix = $cube->npix;
        # Put cloud in centre to nearest integer
        $thiscloud{x_location} = int($offset[0] + $npix[0] / 2);
        $thiscloud{y_location} = int($offset[1] + $npix[1] / 2);

        # Width of fake source. Is this in pixels or arcsec?
        # +1 to ensure that it always has non-zero width
        $thiscloud{major_width} = int(0.6 * $npix[0]) + 1;
        $thiscloud{minor_width} = int(0.6 * $npix[1]) + 1;

        push(@clouds, \%thiscloud);
    }

    # create the simulation
    my $sim = JAC::OCS::Config::ACSIS::Simulation->new();

    # write cloud information
    $sim->clouds(@clouds);

    # Now write the non cloud information
    $sim->noise(1);
    $sim->refsky_temp(135.0);

    # Depends on Receiver
    my $inst = $cfg->instrument_setup;
    throw OMP::Error::FatalError(
        'Instrument configuration is not available for simulation configuration')
        unless defined $inst;

    if ($inst->name =~ /HARP/) {
        $sim->load2_temp(300.0);
        $sim->ambient_temp(250.0);
    }
    else {
        $sim->load2_temp(250.0);
        $sim->ambient_temp(300.0);
    }
    $sim->band_start_pos(120);

    # attach simulation to acsis
    $acsis->simulation($sim);
}

=item B<determine_map_and_switch_mode>

Calculate the mapping mode, switching mode and observation type from the Observing
Tool mode and switching string.

    ($map_mode, $sw_mode) = $trans->determine_observing_summary($mode, $sw);

Called from the C<observing_mode> method.  See
C<OMP::Translator::JCMT::observing_mode> method for more details.

=cut

sub determine_map_and_switch_mode {
    my $self = shift;
    my $mode = shift;
    my $swmode = shift;

    my ($mapping_mode, $switching_mode);

    # assume science
    my $obs_type = 'science';

    if ($mode eq 'SpIterRasterObs') {
        $mapping_mode = 'scan';
        if ($swmode eq 'Position') {
            $switching_mode = 'pssw';
        }
        elsif ($swmode eq 'Chop' || $swmode eq 'Beam') {
            throw OMP::Error::TranslateFail("scan_chop not yet supported\n");
            $switching_mode = 'chop';
        }
        elsif ($swmode =~ /none/i) {
            $switching_mode = "none";
        }
        else {
            throw OMP::Error::TranslateFail(
                "Scan with switch mode '$swmode' not supported\n");
        }
    }
    elsif ($mode eq 'SpIterPointingObs') {
        $mapping_mode = 'jiggle';
        $switching_mode = 'chop';
        $obs_type = 'pointing';
    }
    elsif ($mode eq 'SpIterFocusObs') {
        $mapping_mode = 'grid';  # Just chopping at 0,0
        $switching_mode = 'chop';
        $obs_type = 'focus';
    }
    elsif ($mode eq 'SpIterStareObs') {
        # check switch mode
        $mapping_mode = 'grid';
        if ($swmode eq 'Position') {
            $switching_mode = 'pssw';
        }
        elsif ($swmode eq 'Chop' || $swmode eq 'Beam') {
            # no jiggling
            $switching_mode = 'chop';
        }
        elsif ($swmode =~ /^Frequency-/) {
            $switching_mode = "freqsw";
        }
        else {
            throw OMP::Error::TranslateFail(
                "Sample with switch mode '$swmode' not supported\n");
        }
    }
    elsif ($mode eq 'SpIterJiggleObs') {
        # depends on switch mode
        $mapping_mode = 'jiggle';
        if ($swmode eq 'Chop' || $swmode eq 'Beam') {
            $switching_mode = 'chop';
        }
        elsif ($swmode =~ /^Frequency-/) {
            $switching_mode = 'freqsw';
        }
        elsif ($swmode eq 'Position') {
            $switching_mode = 'pssw';
        }
        else {
            throw OMP::Error::TranslateFail(
                "Jiggle with switch mode '$swmode' not supported\n");
        }
    }
    elsif ($mode eq 'SpIterSkydipObs') {
        $obs_type = 'skydip';
        my $sdip_mode = OMP::Config->getData($self->cfgkey . ".skydip_mode");
        if ($sdip_mode =~ /^cont/) {
            $mapping_mode = 'scan';
        }
        elsif ($sdip_mode =~ /^dis/) {
            $mapping_mode = "stare";
        }
        else {
            OMP::Error::TranslateFail->throw(
                "Skydip mode '$sdip_mode' not recognized");
        }
        $switching_mode = 'none';
    }
    else {
        throw OMP::Error::TranslateFail(
            "Unable to determine observing mode from observation of type '$mode'");
    }

    return ($mapping_mode, $switching_mode, $obs_type);
}

=item B<interface_list>

Configure the interface XML.

    $trans->interface_list($cfg, %info);

=cut

sub interface_list {
    my $self = shift;
    my $cfg = shift;
    my %info = @_;

    # get the acsis configuration
    my $acsis = $cfg->acsis;
    throw OMP::Error::FatalError('ACSIS setup is not available')
        unless defined $acsis;

    my $filename = File::Spec->catfile(
        $self->wiredir, 'acsis', 'interface_list.ent');

    # Read the entity
    my $il = JAC::OCS::Config::ACSIS::InterfaceList->new(
        EntityFile => $filename,
        validation => 0);

    $acsis->interface_list($il);
}

=item B<acsis_layout>

Read and configure the ACSIS process layout, process links, machine table
and monitor layout.

=cut

sub acsis_layout {
    my $self = shift;
    my $cfg = shift;
    my %info = @_;

    # get the acsis configuration
    my $acsis = $cfg->acsis;
    throw OMP::Error::FatalError('ACSIS setup is not available')
        unless defined $acsis;

    # This code is a bit more involved because in general the process layout
    # template file includes entity references that must be replaced with
    # more template XML prior to parsing.

    # The first thing we need to do is read the machine table and monitor
    # layout files

    # Read the new machine table (no longer in the acsis directory)
    my $machtable_file = File::Spec->catfile(
        $self->wiredir, 'machine_table.xml');
    my $machtable = $self->_read_file($machtable_file);

    # Read the monitor layout
    my $monlay_file = File::Spec->catfile(
        $self->wiredir, 'acsis', 'monitor_layout.ent');
    my $monlay = $self->_read_file($monlay_file);

    # make sure we have enclosing tags
    if ($monlay !~ /monitor_layout/) {
        $monlay = "<monitor_layout>\n$monlay\n</monitor_layout>\n";
    }

    # Make a stab at a layout
    my $appropriate_layout = $self->determine_acsis_layout($cfg, %info);

    # append the standard file extension
    $appropriate_layout .= '_layout.ent';

    # Read the template process_layout file
    my $lay_file = File::Spec->catfile(
        $self->wiredir, 'acsis', $appropriate_layout);
    my $layout = $self->_read_file($lay_file);

    $self->output("Read ACSIS layout $lay_file\n");

    # Now we need to replace the entities.
    $layout =~ s/\&machine_table\;/$machtable/g;
    $layout =~ s/\&monitor_layout\;/$monlay/g;

    throw OMP::Error::TranslateFail(
        "Process layout XML does not seem to include any monitor_process elements!")
        unless $layout =~ /monitor_process/;

    throw OMP::Error::TranslateFail(
        "Process layout XML does not seem to include any machine_table elements!")
        unless $layout =~ /machine_table/;

    # make sure we have a wrapper element
    $layout = "<abcd>$layout</abcd>\n";

    # Create the process layout object
    my $playout = JAC::OCS::Config::ACSIS::ProcessLayout->new(
        XML => $layout,
        validation => 0);

    $acsis->process_layout($playout);
}

=item B<need_offset_tracking>

Returns true if we are meant to be tracking an offset position
in the focal plane.

    $need_offset = $trans->need_offset_tracking($cfg, %info);

The caller routine can decide how that position is defined.

Returns true if we need to offset. False if we should track
the focal plane origin.

=cut

sub need_offset_tracking {
    my $self = shift;
    my $cfg = shift;
    my %info = @_;

    # arrayCentred switch trumps everything
    return if (exists $info{arrayCentred} && $info{arrayCentred});

    # First decide whether we should be aligning with a specific
    # receptor?

    # Focus:   Yes
    # Stare:   Yes
    # Grid_chop: Yes
    # Jiggle   : Yes (if the jiggle pattern has a 0,0)
    # Pointing : Yes (if 5point)
    # Scan     : No
    # Skydip   : No

    return if ($info{observing_mode} =~ /^scan/);
    return if $info{obs_type} eq 'skydip';

    # Get the jiggle pattern
    if ($info{mapping_mode} eq 'jiggle') {
        # Could also ask the configuration for Secondary information
        my $jig = $self->jig_info(%info);

        # If we are using the HARP jiggle pattern we will be wanting
        # a fully sampled map so do not offset
        return if $info{jigglePattern} =~ /^HARP/;

        # if this is not a HARP jiggle pattern we simply assume that it
        # will be centred on a specific receptor.
    }

    return 1;
}


=item B<is_fast_freqsw>

Returns true if the observation if fast frequency switch. Should only be relied
upon if it is known that the observation is frequency switch.

    $isfast = $tran->is_fast_freqsw(%info);

=cut

sub is_fast_freqsw {
    my $self = shift;
    my %info = @_;
    return ($info{switchingMode} eq 'Frequency-Fast');
}

=item B<bandwidth_mode>

Determine the standard correlator mode for this observation
and store the result in the %info hash within each subsystem.

    $trans->bandwidth_mode($cfg, %info);

There are 2 mode designations. The spectral window bandwidth mode
(call "bwmode") is a combination of bandwidth and channel count for a
subband. If the spectral region is a hybrid mode, "bwmode" will refer
to a bandwidth mode for each subband but since this mode is identical
for each subband it is only stored as a scalar value. This method will
add a new header "nsubbands" to indicate whether the mode is
hybridised or not.  This mode is of the form BWxNCHAN. e.g. 1GHzx1024,
250MHzx8192.

The second mode designation, here known as the configuration name or
"configname" is a single string describing the entire spectral region
(hybridised or not) and is of the form BW_NSBxNCHAN, where BW is the
full bandwidth of the subsystem, NSB is the number of subbands in the
subsystem and NCHAN is the total number of channels in the subsystem
(but not the final number of channels in the hybridised spectrum). e.g.
500MHZ_2x4096

For example, configuration 500MHz_2x4096 consists of two spectral
windows each using bandwidth mode 250MHzx4096.

=cut

sub bandwidth_mode {
    my $self = shift;
    my $cfg = shift;
    my %info = @_;

    # Get the subsystem array
    my @subs = @{$info{freqconfig}->{subsystems}};

    # Need the IF center frequency from the frontend for information purposes only
    my $inst = $cfg->instrument_setup();
    throw OMP::Error::FatalError('instrument setup is not available')
        unless defined $inst;

    my $if_center_freq = $info{'freqconfig'}->{'otConfigIF'};

    # Keep track of duplicates
    # A subsystem is a dupe if the IF, overlap, channels and  bandwidth are the same
    my %dupe_ss;
    my $allow_duplicate = OMP::Config->getData(
        'acsis_translator.allow_duplicate_subsystem');

    # loop over each subsystem
    my $spectrum_id = 0;
    for my $s (@subs) {
        $s->{'spectrum_id'} = ++ $spectrum_id;
        $self->output("Processing subsystem $spectrum_id ...\n");

        # These are the hybridised subsystem parameters
        my $hbw = $s->{bw};
        my $olap = $s->{overlap};
        my $hchan = $s->{channels};

        if ($hchan == 0) {
            throw OMP::Error::TranslateFail(
                "Number of hybridised channels in subsystem is 0 so unable to calculate channel width");
        }

        # Calculate the channel width and store it
        my $chanwid = $hbw / $hchan;

        if ($chanwid == 0.0) {
            throw OMP::Error::TranslateFail(
                "Channel width 0 Hz from hybridised bandwidth of $hbw and $hchan hybridised channels");
        }

        # if we have a duplicate subsystem we adjust the IF to make it subtly different - since
        # there is no gain to having an identical subsystem we may as well disable the subsystem
        # completel but in the interests of giving people roughly what they asked for we shift
        # the subsystem by a small amount so that CADC indexing will not get confused when it
        # gets two identical subsystem data products.

        # Unique key for duplication tracking
        my $root_uniq = $s->{bw} . $s->{overlap} . $s->{channels};
        my $unique_ss = $root_uniq . $s->{if};

        $dupe_ss{$unique_ss} ++;
        if ($dupe_ss{$unique_ss} > 1) {
            unless ($allow_duplicate) {
                throw OMP::Error::TranslateFail(
                    'Duplicate subsystem in heterodyne setup.'
                    . ' You can force the translation of the observation by enabling'
                    . ' allow_duplicate_subsystem in the acsis_translator settings.');
            }

            my $newkey = $unique_ss;
            my $count = 1;
            while (exists $dupe_ss{$newkey}) {
                my $if = $s->{if};
                $if += ($count * $chanwid);
                $newkey = $root_uniq . $if;

                unless (exists $dupe_ss{$newkey}) {
                    $s->{if} = $if;
                    $dupe_ss{$newkey} ++;  # protect against a subsequent subsystem clashing
                    last;
                }
                $count ++;
            }
            $self->output(
                "\tDuplicate subsystem detected. Shifting by "
                . $count . " channel" . ($count > 1 ? "s" : '')
                . " to make unique.\n");
        }

        # Currently, we determine whether we are hybridised from the
        # presence of non-zero overlap
        my $nsubband;
        if ($olap > 0) {
            if ($info{'instrument'} !~ /HARP/i) {
                # new code to guess number of subbands as required for RXA3M upgrade
                my $subbw = ($hbw >= 1.0E9) ? 1.0E9 : 250.0E6;
                $nsubband = OMP::General::nint($hbw / ($subbw - $olap));
            }
            else {
                # assumes only ever have 2 subbands per subsystem
                $nsubband = 2;
            }
        }
        else {
            $nsubband = 1;
            # ensure overlap is really zero for subsequent calculations
            $olap = 0.0;
        }

        # Calculate the full bandwidth non-hybridised.
        # Calculation has been updated to match that in the OT:
        # if we are using a hybrid mode ($nsubband != 0) then
        # subtract the overlap for each subband, i.e. we're also
        # removing 1/2 of the overlap region at each end of the
        # whole spectrum.
        my $bw = $hbw + ($nsubband * $olap);

        # Convert this to nearest 10 MHz to remove rounding errors
        my $mhz = int(($bw / (1E6 * 10)) + 0.5) * 10;

        $self->output("\tBandwidth: $mhz MHz\n");

        # store the bandwidth in Hz for reference
        $s->{bandwidth} = $mhz * 1E6;

        # Store the bandwidth label
        my $ghz = $mhz / 1000;
        $s->{bwlabel} = ($mhz < 1000 ? int($mhz) . "MHz" : int($ghz) . "GHz");

        # Original number of channels before hybridisation
        # Because the OT also rounds, we need to take this to the nearest
        # even number. We know that the answer has to be a power of 2 and that
        # the rounding will be extremely close to the right answer.
        my $nchan_frac = $bw / $chanwid;

        # hack - divide by 64, nint then multiply by 64
        # 64 is enough to beat down the difference from rounding
        my $nchan = OMP::General::nearest_mult($nchan_frac, 64);
        $s->{nchannels_full} = $nchan;

        # and recalculate the channel width (rather than use the OT approximation
        $chanwid = $bw / $nchan;
        $s->{channwidth} = $chanwid;

        $self->output(
            "\tChanwid : $chanwid Hz\n",
            "\tNumber of channels: $nchan\n");

        # number of channels per subband
        my $nchan_per_sub = $nchan / $nsubband;
        $s->{nchan_per_sub} = $nchan_per_sub;

        # calculate the bandwidth of each subband in MHz
        my $bw_per_sub = $mhz / $nsubband;

        # subband bandwidth label
        $s->{sbbwlabel} = ($bw_per_sub < 1000
            ? int($bw_per_sub) . "MHz"
            : int($bw_per_sub / 1000) . "GHz");

        # Store the number of subbands
        $s->{nsubbands} = $nsubband;

        # bandwidth mode
        $s->{bwmode} = $s->{sbbwlabel} . "x" . $nchan_per_sub;

        # configuration name
        $s->{configname} = $s->{bwlabel} . '_' . $nsubband . 'x' . $nchan_per_sub;

        # channel mode
        $s->{chanmode} = $nsubband . 'x' . $nchan_per_sub;

        # Get the bandwidth mode fixed info
        throw OMP::Error::FatalError(
            "Bandwidth mode [" . $s->{sbbwlabel} . "] not in lookup")
            unless exists $BWMAP{$s->{sbbwlabel}};

        my %bwmap = %{$BWMAP{$s->{sbbwlabel}}};

        $self->output(
            "\tBW per sub: $bw_per_sub MHz with overlap : $olap Hz\n");

        # The usable channels are defined by the overlap
        # Simply using the channel width to calculate the offset
        # Note that the reference channel is half the overlap if we want the
        # reference channel to be aligned with the centre of the hybrid spectrum
        my $olap_in_chan = OMP::General::nint($olap / (2 * $chanwid));

        # Note that channel numbers start at 0
        my $nch_lo = $olap_in_chan;
        my $nch_hi = $nchan_per_sub - $olap_in_chan - 1;

        $self->output("\tUsable channel range: $nch_lo to $nch_hi\n");

        my $d_nch = $nch_hi - $nch_lo + 1;
        my $nch_mid = $nch_lo + OMP::General::nint($d_nch / 2);

        # Now calculate the IF setting for each subband
        # For 1 subband just choose the middle channel.
        # For 2 subbands make sure that the reference channel in each subband
        # is the centre of the overlap region and is the same for each.
        my @refchan;  # Reference channel for each subband

        # This is the exact value of the IF and is forced to be the same
        # for all channels ( in one or 2 subband versions).
        my @sbif;

        # Shift to be used in 3- and 4-subband hybrids.
        my $subband_shift = $nchan_per_sub - 2 * $olap_in_chan;

        # Note: the band sketches below are drawn for USB and assume
        # that the channels are numbered from high IF downwards.

        if ($nsubband == 1) {
            # middle usable channel
            #         [ |  :  | ]
            @refchan = ($nch_mid);
            @sbif = ($s->{'if'});
        }
        elsif ($nsubband == 2) {
            # Subband 1 is referenced to LO channel and subband 2 to HI
            #     [ |     |:]
            #             [:|     | ]
            @refchan = ($nch_lo, $nch_hi);
            @sbif = ($s->{'if'}) x 2;
        }
        elsif ($nsubband == 3) {
            # Subbands all referenced to the centre IF.
            #         [ |  :  | ]
            #              :  [ |     | ]
            # [ |     | ]  :
            @refchan = (
                $nch_mid,
                $nch_mid + $subband_shift,
                $nch_mid - $subband_shift);
            @sbif = ($s->{'if'}) x 3;
        }
        elsif ($nsubband == 4) {
            # Subbands all referenced to the centre IF.
            #         [ |     |:]
            #                 [:|     | ]
            # [ |     | ]      :
            #                  :      [ |     | ]
            @refchan = (
                $nch_lo,
                $nch_hi,
                $nch_lo - $subband_shift,
                $nch_hi + $subband_shift);
            @sbif = ($s->{'if'}) x 4;
        }
        else {
            # THIS ONLY WORKS FOR 4 SUBBANDS
            die "Only 4 subbands supported not $nsubband!";
        }

        # Store the reference frequency and channel for each subband
        $s->{if_per_subband} = \@sbif;
        $s->{if_ref_channel} = \@refchan;

        # Now calculate the offset from the centre for reference
        my @ifoff = map {$_ - $if_center_freq} @sbif;

        $self->output(
            "\tIF within band: " . sprintf("%.6f", $s->{if} / 1E9)
            . " GHz (offset = " . sprintf("%.3f", $ifoff[0] / 1E6) . " MHz)\n");

        # For the LO2 settings we need to offset the IF by the number of channels
        # from the beginning of the band.  (This appears to give the high-IF end of the band.)
        my @chan_offset = map {
            $sbif[$_] + ($refchan[$_] * $chanwid)
        } (0 .. $#sbif);

        # Now calculate the exact LO2 for each IF (parking frequency is for first channel
        # and IF is reported by the OT for the band centre).
        my @lo2exact = map {$_ + $bwmap{f_park}} @chan_offset;
        $s->{lo2exact} = \@lo2exact;

        # LO2 is quantized into multiples of LO2_INCR
        my @lo2true = map {OMP::General::nearest_mult($_, $LO2_INCR)} @lo2exact;
        $s->{lo2} = \@lo2true;

        for my $lo2 (@lo2true) {
            throw OMP::Error::TranslateFail(
                "Internal error in translator. LO2 is out of range ("
                . $LO2_RANGE->min . " < $lo2 < " . $LO2_RANGE->max . ")")
                unless $LO2_RANGE->contains($lo2);
        }

        # Now calculate the error and store this for later correction
        # of the subbands in the spectral window. The correction must
        # be given in channels

        my @align_shift = map {
            ($lo2exact[$_] - $lo2true[$_]) / $chanwid
        } (0 .. $#lo2exact);

        $s->{align_shift} = \@align_shift;

        $self->output(
            "\tRefChan  FirstChanIF (GHz)  LO2 Exact (GHz)  LO2 Quantized (GHz)  Correction (chan)\n",
            map {
                sprintf "\t%7d  %17.6f  %15.6f  %19.6f  %17.3f\n",
                    $refchan[$_],
                    $chan_offset[$_] / 1E9,
                    $lo2exact[$_] / 1E9,
                    $lo2true[$_] / 1E9,
                    $align_shift[$_];
            } (0 .. $#lo2exact)
        );
    }

    # We currently do not want to do hybridisation in the real time DR
    # because it is problematic and not reversible. Split up subbands into multisub
    my @outsubs;
    my $expand;
    for my $s (@subs) {
        if ($s->{nsubbands} == 1) {
            push(@outsubs, $s);
        }
        else {
            $expand = 1;
            for my $i (1 .. $s->{nsubbands}) {
                my %snew = ();
                # copy the data for index $i-1
                my $index = $i - 1;
                for my $k (keys %$s) {
                    if (not ref($s->{$k})) {
                        $snew{$k} = $s->{$k};
                    }
                    else {
                        $snew{$k} = [$s->{$k}->[$index]];
                    }
                }
                # fix ups
                $snew{nchannels_full} /= $s->{nsubbands};
                $snew{nsubbands} = 1;
                push(@outsubs, \%snew);
            }
        }
    }
    if ($expand) {
        @{$info{freqconfig}->{subsystems}} = @outsubs;
    }
    return;
}

=item B<step_time>

Returns the recommended RTS step time for this observing mode. Time is
returned in seconds.

    $rts = $trans->step_time($cfg, %info);

=cut

sub step_time {
    my $self = shift;
    my $cfg = shift;
    my %info = @_;

    # In scan_pssw the step time is defined to be the time per
    # output pixel. Everything else reads from config file
    my $step;
    if ($info{observing_mode} =~ /scan_pssw/) {
        # One spectrum per sample time requested. This assumes that the sample time is
        # reasonably small because we do not break the map up into small step time with
        # more repeats
        $step = $info{sampleTime};
    }
    elsif ($info{observing_mode} =~ /grid_pssw/) {
        if ($self->is_pol_spin(%info)) {
            # we are spinning a polarimeter
            $step = OMP::Config->getData(
                'acsis_translator.step_time_grid_pssw_pol');
        }
        else {
            # Choose a fixed time that will enable us to get a reasonable number of
            # spectra out rather than a single spectrum for the entire "time_between_ref" period.
            $step = OMP::Config->getData('acsis_translator.step_time_grid_pssw');
        }
    }
    elsif ($info{observing_mode} =~ /jiggle_pssw/) {
        # The step time has to be such that we can get round the jiggle
        # pattern in max_time_between_refs seconds.
        # It also has to not exceed the requested integration time per jiggle position.
        # Additionally, we would like to get a reasonable number of spectra out
        # for the observation (for statistics) so probably do not want to exceed 2 seconds per spectrum

        # Need the number of points in the jiggle pattern
        my $jig = $self->get_jiggle($cfg);

        # Need the time between refs
        my $refgap = OMP::Config->getData(
            'acsis_translator.time_between_ref'
            . ($info{continuumMode} ? "_cont" : ""));

        # Calculate the maximum amount of time we can spend per jiggle point in that period
        my $max_time = $refgap / $jig->npts;

        # Now we need to find out how much time has actually been requested
        $step = $self->step_time_reduce($info{secsPerJiggle}, $max_time, 1.0);
    }
    elsif ($info{observing_mode} =~ /jiggle_chop/ && ! $info{continuumMode}) {
        # Continuum mode should be off. In continuum mode we simply go as fast as we can.
        # In all cases we must get round the pattern before max_time_between_nods
        # We will scale the result to be less than 2 seconds for the step time to allow
        # reasonable readout rate for data examination.
        # In this calculation there is no difference between shared and non-shared offs.
        # The difference is in the secondary configuration, whether to chop and jiggle
        # or jiggle then chop.

        # Get the time between chops
        my $time_between_chops = OMP::Config->getData(
            'acsis_translator.max_time_between_chops');

        # and the time between
        my $time_between_nods = OMP::Config->getData(
            'acsis_translator.max_time_between_nods');

        # Minimum step time is read from the config
        my $min_time = OMP::Config->getData('acsis_translator.step_time');

        # or the requirement that the time between nods can fit the pattern
        # Need to know the number of jiggle points
        my $jig = $self->get_jiggle($cfg);

        # For separate Offs we know exactly how many offs there are going to be and that
        # we have to fit the pattern into half the nod time whilst not exceeding
        # the chop time.
        my $max_time;
        if ($info{separateOffs}) {
            # same amount of time in the on and off so divide nod time by 2
            my $max_pattern_time = $time_between_nods / 2.0;

            # max time is now the minimum of the chop time or the time needed to
            # complete the pattern in the nod time
            $max_time = min($time_between_chops, $max_pattern_time / $jig->npts);
        }
        else {
            # if we are sharing offs, the amount of time in the off is sqrt(N) number
            # of ONs in that cycle. BUT there are a number of ways to complete the
            # pattern which must be broken into equal chunks. We need to calculate the
            # most efficient way to break up the pattern in order to maximize integration
            # time whilst minimizing chop time. In practice that means making sure that
            # we use the largest step time we can in order to fill the time_between_chops
            # whilst also being able to complete the pattern in time to nod.

            # first thing to do is factor the number of points into equal chunks
            # Start at half and stop at 2 (since we know that 1 and itself are factors)
            my $npts = $jig->npts;
            my @nchunks = (1);
            for (my $i = 2; $i < POSIX::ceil($npts / 2); $i ++) {
                push(@nchunks, $i) if $npts % $i == 0;
            }

            # Now calculate the chunk size (number of points that need to occur before
            # chopping) from the number of chunks
            my @chunks = map {$npts / $_} @nchunks;

            # The maximum step time from the chop time is derived from the
            # size of that chunk
            my @max_step_from_chop = map {$time_between_chops / $_} @chunks;

            # and now calculate the length of the OFF and the duration of the total pattern
            # including offs
            my @duration = map {$self->calc_jiggle_times($npts, $_)} @chunks;

            # The maximum step time that we can therefore use and still complete the
            # pattern is
            my @max_step_from_nod = map {$time_between_nods / $_} @duration;

            if ($self->debug) {
                print "Chunk size:" . join(",", @chunks) . "\n";
                print "Step times from nod constraint: "
                    . join(",", @max_step_from_nod), "\n";
                print "Step times from chop constraint: "
                    . join(",", @max_step_from_chop), "\n";
            }

            # Need the minimum value of the chop/nod constraint for each pattern
            my @max_time;
            for my $i (0 .. $#chunks) {
                my $value = min(
                    $max_step_from_nod[$i],
                    $max_step_from_chop[$i]);

                # if the value is below our threshold replace it with undef
                $value = undef if $value < $min_time;

                push @max_time, $value;
            }

            # Now choose the time that is smallest and defined
            # Do not use min() because we wish to know which index was chosen
            my $chosen_chunk;
            for my $i (0 .. $#max_time) {
                my $this = $max_time[$i];

                if (! defined $max_time || $max_time[$i] < $max_time) {
                    $max_time = $max_time[$i];
                    $chosen_chunk = $i;
                }
            }

            throw OMP::Error::TranslateFail(
                "Unable to choose a reasonable step time from this jiggle pattern!")
                if ! defined $max_time;

            # We can now tweak the step time to fit into the nod time (since it will not
            # fit exactly without doing this).
            my $duration_of_pattern = $duration[$chosen_chunk] * $max_time;
            my $target_jos_mult = POSIX::ceil($time_between_nods / $duration_of_pattern);

            my $adjusted = $time_between_nods /
                ($target_jos_mult * $duration[$chosen_chunk]);

            print "Duration(steps) = $duration[$chosen_chunk]  Target Mult = $target_jos_mult  Adjusted=$adjusted\n"
                if $self->debug;

            $max_time = $adjusted if $adjusted > $min_time;
        }

        # Actual integration time requested must be scaled by the nod set size
        my $nod_set_size = $self->get_nod_set_size(%info);
        my $time_per_nod = $info{secsPerJiggle} / $nod_set_size;

        if ($self->debug) {
            print "Max time = $max_time seconds\n";
            print "Min time = $min_time\n";
            print "Timepernod = $time_per_nod\n";
        }

        # and calculate a value
        $step = $self->step_time_reduce($time_per_nod, $max_time, $min_time);
    }
    elsif ($info{observing_mode} =~ /grid_chop/) {
        # in continuum mode we simply chop at the requested rate
        if ($info{continuumMode}) {
            $step = OMP::Config->getData(
                'acsis_translator.max_time_between_chops_cont');
        }
        else {
            # we can chop slowly but we have a lower limit
            my $min_step = OMP::Config->getData('acsis_translator.step_time');

            # The required integration time is split over the nod set so our
            # step time must be reduced by the nod set size
            my $time_per_nod =
                $info{secsPerCycle} / $self->get_nod_set_size(%info);

            # the largest value we can use is given by max_time_between_chops
            # although in practice we decide to use a smaller number to generate spectra
            # at a reasonable rate
            my $max_time_per_chop = OMP::Config->getData(
                "acsis_translator.max_time_between_chops");

            # Calculate the step time
            $step = $self->step_time_reduce(
                $time_per_nod, $max_time_per_chop, $min_step);
        }
    }
    elsif ($info{observing_mode} =~ /freqsw/) {
        $step = OMP::Config->getData('acsis_translator.step_time_fast_freqsw');
    }
    else {
        # eg jiggle/chop continuum mode
        $step = OMP::Config->getData('acsis_translator.step_time');
    }

    throw OMP::Error::TranslateFail(
        "Calculated step time not a positive number [was "
        . (defined $step ? $step : "undef") . "]\n")
        unless $step > 0;

    return $step;
}

=item B<step_time_reduce>

Calculate a step time given the requested total time, the maximum step time
and the minimum step time.

    $step = $self->step_time_reduce($requested, $max_time, $min_time);

Step times will be less than 2.0 seconds and greater than min_time.

=cut

sub step_time_reduce {
    my $self = shift;
    my ($requested, $max_time, $min_time) = @_;

    # if the requested time is smaller than the max time we can set the step
    # time to the max time directly - we can divide it up later if we want more
    # spectra
    my $step;
    if ($max_time >= $requested) {
        $step = $requested;
    }
    else {
        # Choose a step time that will be less than max_time but
        # evenly divide requested time since we will have to go round the
        # pattern an integer number of times (ie go to a ref an integer
        # number of times) and step time can't change for the last visit.
        my $nrepeats = POSIX::ceil($requested / $max_time);
        $step = $requested / $nrepeats;
        print "New step= $step  Requested = $requested NRepeats = $nrepeats\n"
            if $self->debug;
    }

    # if the step time is larger than 2 seconds divide it up into
    # smaller chunks that are at least 1 second (2/2)
    my $max_step = 2.0;
    if ($step > $max_step) {
        for my $i (2 .. POSIX::ceil($max_time)) {
            my $new = $step / $i;
            if ($new < $max_step) {
                $step = $new;
                last;
            }
        }
    }

    # make sure we are at least min_time seconds
    $step = $min_time if $step < $min_time;

    return $step;
}

=item B<calc_jos_times>

Calculate the time between refs and cals and the length of a cal.

    ($calgap, $refgap) = $self->calc_jos_times($jos, %info);

Returns the actual cal and ref gaps (as rederived from the step time)

=cut

sub calc_jos_times {
    my $self = shift;
    my $jos = shift;
    my %info = @_;

    # Some parameters may be modified for specific named sources?
    my $config_suffix = undef;
    if ($info{'coords'}->type eq 'PLANET') {
        $config_suffix = $info{'coords'}->planet();
    }

    # N_CALSAMPLES depends entirely on the step time and the time from
    # the config file. Number of cal samples. This is hard-wired in
    # seconds but in units of STEP_TIME
    my $caltime = OMP::Config->getDataSearch(
        (defined $config_suffix
            ? 'acsis_translator.cal_time_' . $config_suffix
            : ()),
        'acsis_translator.cal_time');

    # if caltime is less than step time (eg scan) we still need to do at
    # least 1 cal
    $jos->n_calsamples(max(1, OMP::General::nint($caltime / $jos->step_time)));

    my $calgap = 1;
    my $refgap = 1;

    # For polarimeter observations we need to have a cal each cycle
    if ($self->is_pol_spin(%info)) {
        # effective requirement is to do a sky and cal every sequence so just use a short value
        # so take the default of 1
    }
    elsif ($self->is_pol_step_integ(%info)) {
        # Use special ref for pol
        $refgap = OMP::Config->getData('acsis_translator.time_between_ref_pol');

        # for step and integrate we want to cal every 4 positions
        # 4 position on+off. This assumes that people are sensible in the ordering
        # of their step and integrate angles. Since the JOS_MIN can be calcualted
        # to be smaller than refgap we will probably have to recalculate later
        $calgap = 4 * 2 * $refgap;
    }
    else {
        # Now specify the maximum time between cals in steps
        $calgap = OMP::Config->getDataSearch(
            (defined $config_suffix
                ? 'acsis_translator.time_between_cal_' . $config_suffix
                : ()),
            'acsis_translator.time_between_cal');

        # Now calculate the maximum time between refs in steps
        $refgap = OMP::Config->getData(
            'acsis_translator.time_between_ref'
            . ($info{continuumMode} ? "_cont" : ""));

    }

    my $cal_step_gap = OMP::General::nint($calgap / $jos->step_time);
    my $ref_step_gap = OMP::General::nint($refgap / $jos->step_time);
    $jos->steps_btwn_cals(max(1, $cal_step_gap));
    $jos->steps_btwn_refs(max(1, $ref_step_gap));

    return (
        $jos->steps_btwn_cals * $jos->step_time,
        $jos->steps_btwn_refs * $jos->step_time
    );
}

=item B<calc_jiggle_times>

Calculate the total number of steps in a pattern given a number of points in the pattern
and the size of a chunk and optionally the number of steps in the off beam.

    $nsteps = $self->calc_jiggle_times($njigpnts, $jigs_per_on, $steps_per_off);

Note the scalar context. If the number of steps per off is not given, it
is calculated and returned along with the total duration.

    ($nsteps, $steps_per_off) = $self->calc_jiggle_times($njigpnts, $jigs_per_on);

The steps_per_off calculation assumes sqrt(N) behaviour (shared off) behaviour.

If only a number of jiggle points is supplied, it is assumed that there are the same
number of points in the off as in the on.

    $nsteps = $self->calc_jiggle_times($njigpnts);

In scalar context, only returns the number of steps (even if the number of offs
were calculated).

=cut

sub calc_jiggle_times {
    my $self = shift;
    my ($njigpnts, $jigs_per_on, $steps_per_off) = @_;

    # separate offs
    unless (defined $jigs_per_on) {
        # equal size pattern
        return (2 * $njigpnts);
    }

    # shared offs

    # number of chunks in pattern
    my $njig_chunks = $njigpnts / $jigs_per_on;

    my $had_steps = 1;
    unless (defined $steps_per_off) {
        $had_steps = 0;
        # the number of steps in the off is split equally around the on
        # so we half the sqrt(N)
        $steps_per_off = int((sqrt($jigs_per_on) / 2) + 0.5);
    }

    # calculate the number in the jiggle pattern. The factor of 2 is because the SMU
    # does the OFF repeated each side of the ON.
    my $nsteps = $njig_chunks * ($jigs_per_on + (2 * $steps_per_off));

    if (wantarray()) {
        return ($nsteps, (! $had_steps ? $steps_per_off : ()));
    }
    else {
        return $nsteps;
    }
}

=item B<hardware_map>

Read the ACSIS hardware map into an object.

    $hwmap = $trans->hardware_map();

=cut

sub hardware_map {
    my $self = shift;

    my $path = File::Spec->catfile($self->wiredir, 'acsis', 'cm_wire_file.txt');

    return JCMT::ACSIS::HWMap->new(File => $path);
}

=item B<get_nod_set_size>

Returns the number of nods in a nod set. Can be either 2 for AB or 4 for ABBA.

    $nod_set_size = $trans->get_nod_set_size(%info);

Throws an exception if the nod set definition is not understood.

=cut

sub get_nod_set_size {
    my $self = shift;
    my %info = @_;

    my $nod_set_size;
    unless (defined $info{nodSetDefinition}) {
        $nod_set_size = 4;  #ABBA
    }
    elsif ($info{nodSetDefinition} eq 'AB') {
        $nod_set_size = 2;
    }
    elsif ($info{nodSetDefinition} eq 'ABBA') {
        $nod_set_size = 4;
    }
    else {
        throw OMP::Error::TranslateFail(
            "Unrecognized nod set definition ('$info{nodSetDefinition}'). Can not continue.");
    }

    return $nod_set_size;
}

=item B<determine_acsis_layout>

Return the ACSIS layout name. This is usually of form sNrMgP for
sync tasks, reducers and gridders.

    $layout = $trans->determine_acsis_layout($cfg, %info);

In list context returns the number of syncs, reducers and gridder processes.

    ($nsync, $nreduc, $ngrid) = $trans->determine_acsis_layout($cfg, %info);

This only works if the layout follows standard naming convention.

=cut

sub determine_acsis_layout {
    my $self = shift;
    my $cfg = shift;
    my %info = @_;

    # get the acsis configuration
    my $acsis = $cfg->acsis;
    throw OMP::Error::FatalError('ACSIS setup is not available')
        unless defined $acsis;

    # Get the instrument we are using
    my $inst = $self->ocs_frontend($info{instrument});
    throw OMP::Error::FatalError(
        'No instrument defined - needed to select correct layout!')
        unless defined $inst;

    # Now select the appropriate layout depending on the instrument found (and possibly mode)
    my $appropriate_layout;
    if (exists $ACSIS_Layouts{$inst . "_$info{observing_mode}"}) {
        $appropriate_layout = $ACSIS_Layouts{$inst . "_$info{observing_mode}"};
    }
    elsif (exists $ACSIS_Layouts{$inst}) {
        $appropriate_layout = $ACSIS_Layouts{$inst};
    }
    else {
        throw OMP::Error::FatalError(
            "Could not find an appropriate layout file for instrument $inst !");
    }

    # We now need to fudge the gridder number by correcting for multi-subsystem, multi-receptor
    # and multi-waveplate gridding
    if ($appropriate_layout =~ /g(\d+)$/) {
        my $gnum = $1;

        my $spwlist = $acsis->spw_list;
        unless (defined $spwlist) {
            throw OMP::Error::FatalError(
                "Could not find spectral window configuration");
        }

        my %spw = $spwlist->spectral_windows;
        $gnum *= scalar keys %spw;

        # replace the number
        $appropriate_layout =~ s/g\d+$/g$gnum/;
    }

    if (wantarray) {
        # list context so need to break up the answer
        if ($appropriate_layout =~ /s(\d+)r(\d+)g(\d+)/) {
            return ($1, $2, $3);
        }
        else {
            return ();
        }
    }
    else {
        # scalar context so return the layout name
        return $appropriate_layout;
    }
}

=item B<calc_grid>

Calculate a grid capable of representing the supplied offsets.
Returns the size and spacing of the grid, along with a rotation angle
and centre offset. Offsets are assumed to be regular in this projection
such that distance from tangent plane is not taken into account.

    ($nx, $ny, $xsize, $ysize, $gridpa, $offx, $offy) = $self->calc_grid($ny, @offsets);

The offsets are provided as an array of hashes with keys OFFSET_DX,
OFFSET_DY and OFFSET_PA. All are in arcsec and position angles are in
degrees. If no offsets are supplied, the grid is assumed to be a single
position at the coordinate origin.

The first argument is the Nyquist value for this wavelength in arcsec
(assuming the offsets are in arcsec). This will be used to calculate
the allowed tolerance when fitting irregular offsets into a regular
grid and also for calculating a default pixel size if only a single
pixel is required in a particular axis.

In FAST mode, simply returns a default grid without calculation.

=cut

sub calc_grid {
    my $self = shift;
    my $nyquist = shift;
    my @offsets = @_;

    # default to single position at the origin
    @offsets = (
        {
            OFFSET_PA => 0,
            OFFSET_DX => 0,
            OFFSET_DY => 0,
        }
    ) unless @offsets;

    # Abort if we do not require a proper grid
    return (
        1,
        1,
        $nyquist,
        $nyquist,
        $offsets[0]->{OFFSET_PA},
        $offsets[0]->{OFFSET_DX},
        $offsets[0]->{OFFSET_DY}
    ) if $FAST;

    # Rotate to fixed coordinate frame
    my $refpa = $offsets[0]->{OFFSET_PA};
    @offsets = $self->align_offsets($refpa, @offsets);

    # Get the array of x coordinates
    my @x = map {$_->{OFFSET_DX}} @offsets;
    my @y = map {$_->{OFFSET_DY}} @offsets;

    # Calculate stats
    my ($xmin, $xmax, $xcen, $xspan, $nx, $dx)
        = _calc_offset_stats($nyquist, @x);

    my ($ymin, $ymax, $ycen, $yspan, $ny, $dy)
        = _calc_offset_stats($nyquist, @y);

    return ($nx, $ny, $dx, $dy, $refpa, $xcen, $ycen);
}

# Routine to calculate stats from a sequence relevant for grid making
# Requires Nyquist value in arcsec plus an array of X or Y offset positions
# Returns the min, max, centre, span, number of pixels, pixel width
# Function, not method

# Attempt is made never to use fractional arcsec in results.

sub _calc_offset_stats {
    my $nyquist = shift;
    my @off = @_;

    # Tolerance is fraction of Nyquist
    my $tol = 0.2 * $nyquist;

    # Now remove duplicates. Order is irrelevant
    my %dummy = map {$_ => undef} @off;

    # and sort into order (making sure we format)
    my @sort = sort {$a <=> $b} map {sprintf("%.3f", $_)} keys %dummy;

    # if we only have one position we can return early here
    return ($sort[0], $sort[0], $sort[0], 0, 1, $nyquist) if @sort == 1;

    # Then find the extent of the map
    my $max = $sort[-1];
    my $min = $sort[0];

    # Extent of the map
    my $span = $max - $min;
    my $cen = ($max + $min) / 2;
    print "Input offset parameters: Span = $span ($min .. $max) Centre = $cen\n"
        if $DEBUG;

    # if we only have two positions, return early
    return ($min, $max, $cen, $span, 2, $span) if @sort == 2;

    # Now calculate the gaps between each position
    my @gap = map {abs($sort[$_] - $sort[$_ - 1])} (1 .. $#sort);

    # Now we have to work out a pixel scale that will allow these
    # offsets to fall on the same grid within the tolerance
    # start by sorting the gap and picking a value greater than tol
    my @sortgap = sort {$a <=> $b} @gap;
    my $trial;
    for my $g (@sortgap) {
        if ($g > $tol) {
            $trial = $g;
            last;
        }
    }

    # if none of the gaps are greater than the tolerance we actually have a single
    # pixel
    return ($min, $max, $cen, $span, 1, $nyquist)
        unless defined $trial;

    # Starting position is interesting since we could end up with a
    # starting offset that is slightly off the "real" grid and with a slight push
    # end up with a regular grid if we had started from some other position.
    # To try to mitigate this we move the reference pixel to the nearest integer
    # pixel if the tolerance allows it

    # Choose a reference pixel in the middle of the sorted range
    # Reference "pixel" is simply the smallest value in the sequence
    my $refpix = $sort[0];

    # Move to the nearest int if the nearest int is less than the tol
    # away
    my $nearint = OMP::General::nint($refpix);
    if (abs($refpix - $nearint) < $tol) {
        $refpix = $nearint;
    }

    # Store the reference and try to adjust it until we find a match
    # or until the trial is smaller than the tolerance
    my $reftrial = $trial;
    my $mod = 2;    # trial modifier
    OUTER: while ($trial > $tol) {
        # Calculate the tolerance in units of trial pixels
        my $tolpix = $tol / $trial;

        # see whether the sequence fits with this trial
        for my $t (@sort) {
            # first calculate the distance between this and the reference
            # in units of $trial pixels. This will always be positive
            # because we always start from the sorted list.
            my $pixpos = ($t - $refpix) / $trial;

            # Now in an ideal world we have an integer match. Found the
            # pixel error
            my $pixerr = abs($pixpos - OMP::General::nint($pixpos));

            # Now compare this with the tolerance in units of pixels
            if ($pixerr > $tol) {
                # This trial did not work. Calculate a new one by dividing
                # original by an increasing factor (which will stop when we hit
                # the tolerance)
                $trial = $reftrial / $mod;
                $mod ++;
                next OUTER;
            }
        }

        # if we get to this point, we must have verified all positions
        last;
    }

    # whatever happens we get a pixel value. Either a valid one or one that
    # is smaller than the tolerance (and so guaranteed to be okay).
    # we add one because we are counting fence posts not gaps between fence posts
    my $npix = int($span / $trial) + 1;

    # Sometimes the fractional arcsecs pixel sizes can be slightly wrong so
    # now we are in the ballpark we step through the pixel grid and work out the
    # minimum error for each input pixel whilst adjusting the pixel size in increments
    # of 1 arcsec. This does not use tolerance.

    # Results hash
    my %best;

    # Work out the array of grid points
    my $spacing = $trial;

    # Lowest RMS so far
    my $lowest_rms;

    # Start the grid from the lower end (the only point we know about)
    my $range = 1.0;  # arcsec

    # amount to adjust pixel size
    my $pixrange = 1.0;  # arcsec

    for (my $pixtweak = -$pixrange; $pixtweak <= $pixrange; $pixtweak += 0.05) {
        # restrict to 3 decimal places
        $spacing = sprintf("%.3f", $trial + $pixtweak);

        for (my $refoffset = -$range; $refoffset <= $range; $refoffset += 0.05) {
            my $trialref = $min + $refoffset;

            my @grid = map {$trialref + ($_ * $spacing)} (0 .. ($npix - 1));

            # $self->output("Grid: ".join(",",@grid)."\n");

            # Calculate the residual from that grid by comparing with @sort
            # use the fact that we are sorted
            # my $residual = 0.0;
            my $halfpix = $spacing / 2;
            my $i = 0;  # grid index (also sorted)
            my @errors;

            CMP: for my $cmp (@sort) {
                # search through the grid until we find a pixel containing this value
                while ($i <= $#grid) {
                    my $startpix = $grid[$i] - $halfpix;
                    my $endpix = $grid[$i] + $halfpix;

                    if ($cmp >= $startpix && $cmp <= $endpix) {
                        # found the pixel abort from loop
                        push(@errors, ($grid[$i] - $cmp));
                        next CMP;
                    }
                    elsif ($cmp < $startpix) {
                        if ($i == 0) {
                            #$self->output("Position $cmp lies below pixel $i with bounds $startpix -> $endpix\n");
                            push @errors, 1E5;  # make it highly unlikely
                        }
                        else {
                            # Probably a rounding error
                            if (abs($cmp - $startpix) < 1.0E-10) {
                                push @errors, ($grid[$i] - $cmp);
                            }
                            else {
                                croak "Somehow we missed pixel $startpix <= $cmp <= $endpix (grid[$i] = $grid[$i])\n";
                            }
                        }
                        next CMP;
                    }

                    # try next grid position
                    $i ++;
                }

                if ($i > $#grid) {
                    my $endpix = $grid[$#grid] + $halfpix;
                    #$self->output("Position $cmp lies above pixel $#grid ( > $endpix)\n");
                    push @errors, 1E5;    # Make it highly unlikely
                }
            }

            my $rms = _find_rms(@errors);

            if ($rms < 0.1) {
                # $self->output("Grid: ".join(",",@grid)."\n");
                # $self->output("Sort: ". join(",",@sort). "\n");
                # $self->output("Rms= $rms -  $spacing arcsec from $grid[0] to $grid[$#grid]\n");
            }

            if (! defined $lowest_rms || abs($rms) < $lowest_rms) {
                $lowest_rms = $rms;

                # Recalculate the centre location based on this grid
                # Assume that the reference pixel for "0 1 2 3"   is "2" (acsis assumes we align with "2")
                # Assume that the reference pixel for "0 1 2 3 4" is "2" (middle pixel)
                # ACSIS *always* assumes that the "ref pix" is  int(N/2)+1
                # but we start counting at 0, not 1 so subtract an extra 1
                my $midpoint = int(scalar(@grid) / 2) + 1 - 1;

                my $temp_centre;
                if (scalar(@grid) % 2) {
                    # $self->output("Odd\n");
                    $temp_centre = $grid[$midpoint];
                }
                else {
                    #$self->output("Even\n");
                    #$temp_centre = $grid[$midpoint];
                    $temp_centre = $grid[$midpoint]
                        - ($grid[$midpoint] - $grid[$midpoint - 1]) / 2.0;
                }

                #$self->output("Temp centre --> $temp_centre \n");

                %best = (
                    rms => $lowest_rms,
                    spacing => $spacing,
                    centre => $temp_centre,
                    span => ($grid[$#grid] - $grid[0]),
                    min => $grid[0],
                    max => $grid[$#grid],
                );
            }
        }
    }

    # Select the best value from the minimization
    $span = $best{span};
    $min = $best{min};
    $max = $best{max};
    $trial = $best{spacing};
    $cen = $best{centre};

    print "Output grid parameters : Span = $span ($min .. $max) Centre = $cen Npix = $npix RMS = $best{rms}\n"
        if $DEBUG;

    return ($min, $max, $cen, $span, $npix, $trial);
}

# Find the rms of the supplied numbers
sub _find_rms {
    my @num = @_;
    return 0 unless @num;

    # Find the sum of the squares
    my $sumsq = 0;
    for my $n (@num) {
        $sumsq += ($n * $n);
    }

    # Mean of the squares
    my $mean = $sumsq / scalar(@num);

    # square root to get rms
    return sqrt($mean);
}

=item B<_to_acoff>

Convert an array of references to hashes containing keys of OFFSET_DX, OFFSET_DY
and OFFSET_PA to an array of Astro::Coords::Offset objects.

    @offsets = $self->_to_acoff(@input);

If the first argument is already an Astro::Coords::Offset object all
inputs are returned as outputs unchanged.

=cut

sub _to_acoff {
    my $self = shift;

    if (UNIVERSAL::isa($_[0], "Astro::Coords::Offset")) {
        return @_;
    }

    return map {
        Astro::Coords::Offset->new(
            $_->{OFFSET_DX},
            $_->{OFFSET_DY},
            posang => $_->{OFFSET_PA},
            system => $_->{SYSTEM})
    } @_;
}

=item B<_to_offhash>

Convert an array of C<Astro::Coords::Offset> objects to an array of
hash references containing keys OFFSET_DX, OFFSET_DY and OFFSET_PA
(all pointing to scalar non-objects in arcsec and degrees).

    @offsets = $self->_to_offhash(@input);

If the first element looks like an unblessed hash ref all args
will be returned unmodified.

=cut

sub _to_offhash {
    my $self = shift;

    if (! blessed($_[0]) && exists $_[0]->{OFFSET_DX}) {
        return @_;
    }

    return map {
        {
            OFFSET_DX => ($_->offsets)[0]->arcsec,
            OFFSET_DY => ($_->offsets)[1]->arcsec,
            OFFSET_PA => $_->posang->degrees,
            SYSTEM => $_->system,
        }
    } @_;
}

=item B<convolve_footprint>

Return the convolution of the receiver footprint with the supplied
map coordinates to be observed. The receiver footprint is in the
form of a reference to an array of receptor positions.

    @convolved = $trans->convolve_footprint($matchpa, \@receptors, \@map);

Will not work if the coordinate system of the receiver is different
from the coordinate system of the offsets but the routine assumes that
FPLANE == TRACKING for the purposes of this calculation. This will be
correct for everything except HARP with a broken image rotator. If the
image rotator is broken then this will calculate the positions as
if it was working.

The 'matchpa' parameter controls whether the position angle stored in
the receptor array should be used when calculating the new grid or
whether it is assumed that the instrument PA can be rotated to match
the map PA. If true (eg HARP with image rotator) then the PA of the
first map point will be the chosen PA for all the convolved points.

All positions will be corrected to the position angle of the first
position in the map array.

Offsets can be supplied as an array of references to hashes with
keys OFFSET_X, OFFSET_Y, SYSTEM and OFFSET_PA

=cut

sub convolve_footprint {
    my $self = shift;

    my ($matchpa, $rec, $map) = @_;

    return @$rec if !@$map;

    # Get the reference pa
    my $refpa = $map->[0]->{OFFSET_PA};
    my $refsys = $map->[0]->{SYSTEM};
    $refsys = "TRACKING" if ! defined $refsys;

    # Rotate all map coordinates to this position angle
    my @maprot = $self->align_offsets($refpa, @$map);

    # If we are able to match the coordinate rotation of the
    # map with the receiver we do not have to normalize coordinates
    # to the map frame since that is already done
    my @recrot;
    if ($matchpa) {
        @recrot = @$rec;
    }
    else {
        @recrot = $self->align_offsets($refpa, @$rec);
    }

    # Now for each receptor we need to go through each map pixel
    # and add the receptor offset
    my @conv;

    for my $recpixel (@recrot) {
        my $rx = $recpixel->{OFFSET_DX};
        my $ry = $recpixel->{OFFSET_DY};

        for my $mappixel (@maprot) {
            my $mx = $mappixel->{OFFSET_DX};
            my $my = $mappixel->{OFFSET_DY};

            push @conv, {
                OFFSET_DX => ($rx + $mx),
                OFFSET_DY => ($ry + $my),
                OFFSET_PA => $refpa,
                SYSTEM => $refsys,
            };
        }
    }

    return @conv;
}

=item B<velOverride>

Returns a list of velocity (or redshift), velocity definition and velocity frame
if an override of these items has been specified in the MSB.

    ($vel, $vdef, $vframe) = $trans->velOverride(%info);

Returns empty list if no override is specified.

=cut

sub velOverride {
    my $self = shift;
    my %info = @_;

    my $freq = $info{freqconfig};

    if (defined $freq) {
        my $vfr = $freq->{velocityFrame};
        my $vdef = $freq->{velocityDefinition};
        my $vel = $freq->{velocity};

        if (defined $vfr && defined $vdef && defined $vel) {
            return ($vel, $vdef, $vfr);
        }
    }

    # if we get to here there is no override
    return ();
}


=item B<getCubeInfo>

Retrieve the hash of cube information from the ACSIS config. Takes a full JAC::Config
object.

    %cubes = $trans->getCubeInfo($cfg);

=cut

sub getCubeInfo {
    my $self = shift;
    my $cfg = shift;

    # get the acsis configuration
    my $acsis = $cfg->acsis;
    throw OMP::Error::FatalError('ACSIS setup is not available')
        unless defined $acsis;

    # get the spectral window information
    my $cubelist = $acsis->cube_list();
    throw OMP::Error::FatalError('Cube configuration is not available')
        unless defined $cubelist;

    return $cubelist->cubes;
}

=item B<backend>

Returns the backend name. The name is suitable for use in
filenames that are targetted for a specific translator.
SCUBA2 in this case.

=cut

sub backend {
    return "ACSIS";
}

1;

__END__

=back

=head1 NOTES

Usually called indirectly from L<OMP::Translator|OMP::Translator>.

=head1 CONFIGURATION XML

The format of the configuration XML is outlined in JAC document
OCS/ICD/001.

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

Copyright (C) 2007-2008 Science and Technology Facilities Council.
Copyright 2003-2007 Particle Physics and Astronomy Research Council.
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
