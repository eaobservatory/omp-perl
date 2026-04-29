package OMP::Translator::Heterodyne;

=head1 NAME

OMP::Translator::Heterodyne - Base translator class for heterodyne instruments

=head1 SYNOPSIS

    use parent qw/OMP::Translator::Heterodyne/;

=head1 DESCRIPTION

This is a base class for heterodyne instrument translator classes.

=cut

use 5.006;
use strict;
use warnings;
use Carp;

use Astro::Coords::Offset;
use File::Spec;
use JAC::OCS::Config;
use JAC::OCS::Config::Error qw/:try/;
use List::Util qw/min max all sum/;
use Math::Trig qw/rad2deg/;
use Storable;

use OMP::Error;

use parent qw/OMP::Translator::JCMT/;

=head1 METHODS

=head2 Config Generators

=over 4

=item B<frontend_config>

Create the frontend configuration.

    $trans->frontend_config($cfg, \%info);

Also adds additional information to the configured subsystems:

=over 4

=item * sideband

=back

=cut

sub frontend_config {
    my $self = shift;
    my $cfg = shift;
    my $info = shift;

    # Need instrument information
    my $inst = $cfg->instrument_setup();
    throw OMP::Error::FatalError('instrument setup is not available')
        unless defined $inst;

    # Create frontend object for this configuration
    my $fe = JAC::OCS::Config::Frontend->new();

    # Get the basic frontend setup from the freqconfig key
    my %fc = %{$info->{'freqconfig'}};
    my $iffreq = $fc{'otConfigIF'};
    my $iffreq_ghz = $iffreq / 1.0e9;  # to GHz

    # Check whether the instrument configuration matches what
    # the OT thought it was.
    do {
        my $iffreq_conf = $inst->if_center_freq * 1.0E9;  # from GHz

        if ($iffreq_conf != $iffreq) {
            my $message = sprintf 'The instrument IF frequency specified in'
                . ' the instrument XML (%.6f GHz)'
                . ' does not match the IF frequency given in the'
                . ' observation (%.6f GHz).',
                $iffreq_conf / 1.0E9,
                $iffreq / 1.0E9;

            if (OMP::Config->getData($self->cfgkey . '.ignore_if_freq_mismatch')) {
                $self->output('WARNING: ' . $message . "\n");
            }
            else {
                throw OMP::Error::FatalError(sprintf '%s'
                    . ' You can force the translation of the observation by enabling'
                    . ' ignore_if_freq_mismatch in the %s settings.',
                    $message, $self->cfgkey);
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

    my $instrument_name = lc $self->ocs_frontend($info->{'instrument'});

    if ($sb eq 'BEST') {
        # determine from lookup table

        $sb = $self->_determine_best_sideband(
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

            my $if_freq_limit = undef;
            try {
                $if_freq_limit = $self->get_config_value('if_freq_limit');
            }
            catch OMP::Error::BadCfgKey with {
                # Do nothing.
            };

            if ($if_freq_limit) {
                my ($if_freq_low, $if_freq_high) = @$if_freq_limit;

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
    my $lo_rest = ($skyFreq - $self->_sideband_sign($sb) * $iffreq_ghz) * $inv_redshift_factor;

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
    unless (exists $variable_if_inst{$instrument_name}) {
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
    if ($info->{'switching_mode'} =~ /freqsw/ and defined $info->{'frequencyOffset'}) {
        # want the spacing to be frequencyOffset and not 2xfrequencyOffset (since the
        # observing system goes to -1 and +1 not -0.5 and +0.5
        $freq_off = $info->{'frequencyOffset'} / 2.0;
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

=item B<rotator_config>

Configure the rotator parameter. Requires the Config object to at
least have a TCS and Instrument configuration defined. The second
argument indicates how many science and pointing observations are
related for this SpObs. This information can be used to control the
slew mode. It is a reference to a hash with keys of "science" or
"pointing" and values indicating the number of each in the SpObs.

    $trans->rotator_config($cfg, \%count, \%info);

Only relevant for instruments that are on the Nasmyth platform.

=cut

sub rotator_config {
    my $self = shift;
    my $cfg = shift;
    my $nobs = shift;
    my $info = shift;

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
    if ($info->{'obs_type'} eq 'skydip') {
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
        elsif (($info->{'mapping_mode'} eq 'jiggle')
                and not $info->{'isConvertedGridFreqSw'}) {
            # override the system from the jiggle. The PA should be matching the cube
            # but we make sure we use the requested value
            # Note: we don't do this if the observation is a grid/freqsw converted
            # to a 1x1 jiggle because we want to retain the original PA information.
            $system = $info->{'jiggleSystem'} || 'TRACKING';
            $pa = Astro::Coords::Angle->new(
                ($info->{'jigglePA'} || 0),
                units => 'deg');

            # Restrict the rotator choices if we have a jiggle pattern that is not
            # symmetric about all 4 positions
            # Currently use a bit of a hack
            if ($info->{'jigglePattern'} eq '2x1') {
                @choices = (0, 2);
            }
        }
        elsif (($info->{'mapping_mode'} eq 'grid')
                or $info->{'isConvertedGridFreqSw'}) {
            if (exists $info->{'stareSystem'}
                    && defined $info->{'stareSystem'}) {
                # override K mirror option
                # For now only allow when there are no offsets (simplifies map making)
                $system = $info->{'stareSystem'} || 'TRACKING';
                $pa = Astro::Coords::Angle->new(
                    ($info->{'starePA'} || 0),
                    units => 'deg');
            }
            else {
                # Might we need to change system to align with the grid?
                my @offsets;
                @offsets = @{$info->{'offsets'}}
                    if (exists $info->{'offsets'} and defined $info->{'offsets'});

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
    my @raw_angles = (exists $info->{'rotatorAngles'})
        ? @{$info->{'rotatorAngles'}}
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
            $self->cfgkey() . '.harp_rotator_slew_' . $info->{'obs_type'});
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

=back

=head2 General Methods

=over 4

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

        # read integration time from config system
        $info->{'secsPerJiggle'} = $self->get_config_value('secs_per_jiggle_pointing');

        $info->{'jigglePattern'} = $self->get_config_value('pointing_pattern');
        $info->{'jiggleSystem'} = $self->get_config_value('pointing_jigsys');

        my $scaleMode;
        if ($frontend =~ /^HARP/) {
            # HARP needs to use single receptor pointing until we sort out relative
            # calibrations. Set disableNonTracking to false and HARP5 jiggle pattern.
            $info->{disableNonTracking} = 0;  # Only use 1 receptor if true

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
            $scaleMode = "planet";    # Allowed: unity, planet, nyquist
        }

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
            my $half_beam = $self->nyquist($info)->arcsec;
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

        # read integration time from config system.
        # note that we are not technically jiggling.
        $info->{'secsPerCycle'} = $self->get_config_value('secs_per_jiggle_focus');

        # if this is harp then we want the K-mirror to be aligned in the same way it is aligned
        # for POINTING observations (since you point and then focus and you do not want the thing to
        # flip between the two if at all possible
        if ($frontend =~ /^HARP/) {
            $info->{'stareSystem'} = $self->get_config_value('pointing_jigsys');
        }

        $self->output(
            "Determining FOCUS parameters...\n",
            "\tChop parameters: $info->{CHOP_THROW} arcsec @ $info->{CHOP_PA} deg ($info->{CHOP_SYSTEM})\n",
            "\tSeconds per focus position: $info->{secsPerCycle}\n",
            "\tOptimizing for "
                . ($info->{continuumMode} ? "continuum" : "spectral line")
                . " mode\n");
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
    my $info = shift;

    my $frontend = $cfg->frontend();
    throw OMP::Error::FatalError('frontend setup is not available')
        unless defined $frontend;

    return unless $frontend->sb_mode() eq '2SB';

    return unless OMP::Config->getData($self->cfgkey . '.auto_image_subsys_2sb');

    my $subsystems = $info->{'freqconfig'}->{'subsystems'};
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

=item B<determine_scan_angles>

Given a particular scan area and frontend, determine which angles can be given
to the TCS.

    ($system, @angles) = $trans->determine_scan_angles($pattern, \%info);

Angles are simple numbers in degrees. Not objects.

The scanning system is determined by this routine.

=cut

sub determine_scan_angles {
    my $self = shift;
    my $pattern = shift;
    my $info = shift;

    # only calculate angles for bous or raster
    return ($info->{'SCAN_SYSTEM'}) unless $pattern =~ /BOUS|RASTER/i;

    # Need to know the frontend
    my $frontend = $self->ocs_frontend($info->{'instrument'});
    throw OMP::Error::FatalError("Unable to determine appropriate frontend!")
        unless defined $frontend;

    # Choice depends on pixel size. If sampling is equal in DX/DY or for an array
    # receiver then all 4 angles can be used. Else the scan is constrained to the X direction
    my @mults = (1, 3);    # 0, 2 aligns with height, 1, 3 aligns with width
    if ($frontend =~ /harp/i
            || ($info->{'SCAN_VELOCITY'} * $info->{'sampleTime'} == $info->{'SCAN_DY'})) {
        @mults = (0 .. 3);
    }

    my @scanpas = map {$info->{'MAP_PA'} + ($_ * 90)} @mults;

    return ($info->{'SCAN_SYSTEM'}, @scanpas);
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

=item B<get_nod_set_size>

Returns the number of nods in a nod set. Can be either 2 for AB or 4 for ABBA.

    $nod_set_size = $trans->get_nod_set_size(\%info);

Throws an exception if the nod set definition is not understood.

=cut

sub get_nod_set_size {
    my $self = shift;
    my $info = shift;

    my $nod_set_size;
    unless (defined $info->{'nodSetDefinition'}) {
        $nod_set_size = 4;  #ABBA
    }
    elsif ($info->{'nodSetDefinition'} eq 'AB') {
        $nod_set_size = 2;
    }
    elsif ($info->{'nodSetDefinition'} eq 'ABBA') {
        $nod_set_size = 4;
    }
    else {
        throw OMP::Error::TranslateFail(
            'Unrecognized nod set definition ("'
            . $info->{'nodSetDefinition'} . '"). Can not continue.');
    }

    return $nod_set_size;
}

=item B<get_tracking_receptor_filter_params>

Get tracking subarray filtering parameters.

    my %filter = $self->get_tracking_receptor_filter_params($cfg, \%info);

=cut

sub get_tracking_receptor_filter_params {
    my $self = shift;
    my $cfg = shift;
    my $info = shift;

    my $frontend = $cfg->frontend();
    throw OMP::Error::FatalError('frontend setup is not available')
        unless defined $frontend;

    return (
        sideband => $frontend->sideband(),
    );
}

=item B<need_offset_tracking>

Returns true if we are meant to be tracking an offset position
in the focal plane.

    $need_offset = $trans->need_offset_tracking($cfg, \%info);

The caller routine can decide how that position is defined.

Returns true if we need to offset. False if we should track
the focal plane origin.

=cut

sub need_offset_tracking {
    my $self = shift;
    my $cfg = shift;
    my $info = shift;

    # arrayCentred switch trumps everything
    return if (exists $info->{'arrayCentred'} && $info->{'arrayCentred'});

    # First decide whether we should be aligning with a specific
    # receptor?

    # Focus:   Yes
    # Stare:   Yes
    # Grid_chop: Yes
    # Jiggle   : Yes (if the jiggle pattern has a 0,0)
    # Pointing : Yes (if 5point)
    # Scan     : No
    # Skydip   : No

    return if ($info->{'observing_mode'} =~ /^scan/);
    return if $info->{'obs_type'} eq 'skydip';

    # Get the jiggle pattern
    if ($info->{'mapping_mode'} eq 'jiggle') {
        # If we are using the HARP jiggle pattern we will be wanting
        # a fully sampled map so do not offset
        return if $info->{'jigglePattern'} =~ /^HARP/;

        # if this is not a HARP jiggle pattern we simply assume that it
        # will be centred on a specific receptor.
    }

    return 1;
}

=item B<velOverride>

Returns a list of velocity (or redshift), velocity definition and velocity frame
if an override of these items has been specified in the MSB.

    ($vel, $vdef, $vframe) = $trans->velOverride(\%info);

Returns empty list if no override is specified.

=cut

sub velOverride {
    my $self = shift;
    my $info = shift;

    my $freq = $info->{'freqconfig'};

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

=item B<_sideband_sign>

Get the sign associated with a sideband.  (+1 for USB and -1 for LSB.)

=cut

sub _sideband_sign {
    my $self = shift;
    my $sb = shift;

    if ($sb eq 'LSB') {
        return -1;
    }

    if ($sb eq 'USB' or $sb eq 'BEST') {
        return 1;
    }

    throw OMP::Error::TranslateFail("Sideband is not recognised ($sb)");
}

=item B<_determine_best_sideband>

Read the sideband wiring file to determine which sideband should be used
when "best" is requested.

Returns undef if the sideband file can not be found, or if no frequencies
lower than the given value are found.

=cut

sub _determine_best_sideband {
    my $self = shift;
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

1;

__END__

=back

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
