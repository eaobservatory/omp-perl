package OMP::Translator::SCUBA2;

=head1 NAME

OMP::Translator::SCUBA2 - translate SCUBA2 observations to configure XML

=head1 SYNOPSIS

    use OMP::Translator::SCUBA2;
    $config = OMP::Translator::SCUBA2->new->translate($sp);

=head1 DESCRIPTION

Convert SCUBA-2 MSB into a form suitable for observing. This means
XML suitable for the OCS CONFIGURE action.

=cut

use 5.006;
use strict;
use warnings;
use Carp;

use Data::Dumper;
use IO::File;
use List::Util qw/max min/;
use File::Spec;
use Math::Trig ':pi';

use JAC::OCS::Config 1.06;
use JAC::OCS::Config::Error qw/:try/;
use JCMT::TCS::Pong;

use OMP::Config;
use OMP::Error;
use OMP::General;
use OMP::MSB;

use OMP::Translator::Headers::SCUBA2;

use base qw/OMP::Translator::JCMT/;

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

Construct SCUBA-2 translator object

    $translator = $class->new;

=cut

sub new {
    my $class = shift;

    my $self = $class->SUPER::new();

    $self->{'extra_apertures'} = undef;

    return $self;
}

=back

=head2 General Methods

=over 4

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
    return 'OMP::Translator::Headers::SCUBA2';
}

=item B<insert_setup_obs>

Given a list of JAC::OCS::Config objects representing a set of SCUBA-2
observations, insert relevant setup observations.

    @withsetup = $trans->insert_setup_obs(@configs);

Optional first argument is a reference to hash of information that
should be passed to the translate() method when creating the setup
config.

    @withsetup = $trans->insert_setup_obs({simulate => 1}, @configs);

Returns empty list if given an empty list.

Note that this works on translated observations.

=cut

sub insert_setup_obs {
    my $self = shift;

    my %transargs;
    if (ref($_[0]) eq 'HASH') {
        my $opts = shift;
        %transargs = %$opts;
    }

    my @configs = @_;
    return () unless @configs;

    # we start from OT XML to make things robust with translator changes

    my $setupxml = q|
    <SpObs msb="true" optional="false" remaining="1" type="ob" subtype="none">
      <meta_gui_collapsed>false</meta_gui_collapsed>
      <estimatedDuration units="seconds">60.0</estimatedDuration>
      <priority>99</priority>
      <standard>false</standard>
      <title>SCUBA-2 Setup</title>
      <totalDuration units="seconds">0.0</totalDuration>
      <SpInstSCUBA2 id="0" type="oc" subtype="inst.SCUBA2">
        <meta_unique>true</meta_unique>
      </SpInstSCUBA2>
      <SpIterFolder type="if" subtype="none">
        <meta_gui_collapsed>false</meta_gui_collapsed>
        <SpIterSetupObs type="ic" subtype="setupObs">
          <useCurrentAz>false</useCurrentAz>
        </SpIterSetupObs>
      </SpIterFolder>
    </SpObs>
|;

    my $setupmsb = OMP::MSB->new(
        XML => $setupxml,
        PROJECTID => "JCMTCAL");

    OMP::Error::TranslateFail->throw("Could not create MSB of setup observation")
        unless defined $setupmsb;

    my @setups = $self->translate($setupmsb, %transargs);

    # Get the MSBID and title from the first config and force the setup
    # to inherit them.
    my $refid = $configs[0]->msbid;
    my $reftitle = $configs[0]->msbtitle();
    for my $stp (@setups) {
        $stp->msbid($refid);
        $stp->msbtitle($reftitle);
    }

    # we do a setup when the previous target is different to the current
    # target. Always put a setup at the front unless the first is an explicit
    # setup.
    my @outconfigs;
    my $prev_was_setup;
    my $prevtarg = '';

    if ($configs[0]->obsmode !~ /setup/i
            and not _not_needing_setup($configs[0])) {
        $prev_was_setup = 1;
        push(@outconfigs, @setups);
    }

    for my $cfg (@configs) {
        # If the observation type does not require a setup, abort here
        # before entering the target tracking code.
        if (_not_needing_setup($cfg)) {
            push @outconfigs, $cfg;
            next;
        }

        # If we had a setup inserted anyhow we can just pass it along
        # NOTE there is the possibility that this setup is for "currentAz"
        # and not for "FollowingAz"...
        my $obsmode = $cfg->obsmode;
        if ($obsmode =~ /setup/i) {
            push @outconfigs, $cfg;
            $prev_was_setup = 1;
            next;
        }

        # get the target name
        my $thistarg = lc($cfg->qtarget);

        # Skydips always move the telescope so we want to make sure we get
        # a setup after one
        $thistarg .= "_skydip" if $obsmode =~ /skydip/i;

        # if we had inserted a setup for this previously
        # then set this as the previous target
        if ($prev_was_setup) {
            $prevtarg = $thistarg;
            $prev_was_setup = 0;
        }

        if ($prevtarg ne $thistarg) {
            # Change of target information. We trap some magic values
            # since some items won't move the telescope
            if ($thistarg eq 'dark' || $thistarg eq "currentaz") {
                # no need for a setup and do not update prevtarg
            }
            else {
                # Change of target so insert a setup
                push(@outconfigs, @setups);
                $prevtarg = $thistarg;
            }
        }

        push(@outconfigs, $cfg);
    }

    return @outconfigs;
}

=item B<_not_needing_setup>

Returns true for observations for which a setup is not
required.

    if (_not_needing_setup($config)) {
        ...
    }

This should not include setup observations themselves
as these are handled specifically by insert_setup_obs.

The JCMT operators have determined that a
setup is not required before focus or pointing, since
that will normally be followed immediately by a setup
on the science target.

=cut

sub _not_needing_setup {
    my $config = shift;

    my $mode = $config->obsmode();

    return ($mode eq 'scan_focus' or $mode eq 'scan_pointing');
}

=item B<translate_scan_pattern_lut>

Returns a lookup table (hash) mapping OT scan pattern name (in lower
case) to the corresponding PTCS scan pattern name.

    %lut = $trans->translate_scan_pattern_lut();

SCUBA-2 uses continuous patterns.

=cut

sub translate_scan_pattern_lut {
    my $self = shift;

    # Get the base class lut and merge it with the local overrides
    return (
        $self->SUPER::translate_scan_pattern_lut(),
        boustrophedon => "CONTINUOUS_BOUSTROPHEDON"
    );
}

=item B<header_exclusion_file>

Work out the name of the header exclusion file.

    $xfile = $trans->header_exclusion_file(%info);

Does not check to see if the file is present.

For SCUBA-2, pointing has no special header exclusion requirements
compared to the underlying scan or stare.

=cut

sub header_exclusion_file {
    my $self = shift;
    my %info = @_;

    my $root;
    if ($self->is_private_sequence(%info)) {
        # flatfield and array tests (and some noise) do not use
        # the rest of the observing system so the exclusion files
        # are the same
        $root = "flatfield";
    }
    elsif ($info{obs_type} =~ /focus|skydip/) {
        $root = $info{obs_type} . "_" . $info{mapping_mode};
    }
    else {
        # A pointing is just the mapping mode
        # A noise will just be the stare mode since dark and blackbody
        # have been filtered out previously.
        $root = $info{mapping_mode};
    }

    my $xfile = File::Spec->catfile(
        $self->wiredir, "header", "scuba2_" . $root . "_exclude");

    return $xfile;
}

=item B<determine_scan_angles>

Given a particular scan area and frontend, determine which angles can be given
to the TCS.

    ($system, @angles) = $trans->determine_scan_angles($pattern, %info);

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
    my @scanpas = map {$basepa + (90 * $_)} (0 .. 3);

    return ("FPLANE", @scanpas);
}

=item B<is_private_sequence>

Returns true if the sequence only requires the instrument itself
to be involved. If true, the telescope, SMU and RTS are not involved
and so do not generate configuration XML.

    $trans->is_private_sequence(%info);

For SCUBA-2 returns true for observations in the dark, using the blackbody,
or a setup at the current telescope location, false otherwise.

=cut

sub is_private_sequence {
    my $self = shift;
    my %info = @_;
    if ($self->is_dark_or_blackbody(%info)) {
        return 1;
    }

    # if this is a setup observation and we have been told to use the current
    # Azimuth then we can just treat this as a private sequence. We do not really
    # need the telescope in setup observations
    if ($info{obs_type} =~ /^setup/i && $info{currentAz}) {
        return 1;
    }

    return 0;
}

=item B<is_with_rts_only>

Returns true if the observation is a sequence that just involves the
instrument and the RTS.

    $trans->is_with_rts_only(%info);

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
    if ($self->is_dark_or_blackbody(%info)) {
        # so now query the config system to see how to handle this
        my $key = $info{obs_type};
        if ($info{obs_type} =~ /^flatfield/) {
            $key = "flatfield";
        }
        $key .= "_use_rts";

        return OMP::Config->getData($self->cfgkey . "." . $key);
    }

    return 0;
}

=item B<is_dark_or_blackbody>

Returns true if this is an observation that is in the dark or
uses a blackbody source but does not involve another component.

    $trans->is_dark_or_blackbody(%info);

=cut

sub is_dark_or_blackbody {
    my $self = shift;
    my %info = @_;
    if ($info{obs_type} =~ /^flatfield/) {
        if ($info{flatSource} =~ /^(dark|blackbody)$/i) {
            return 1;
        }
    }
    elsif ($info{obs_type} eq 'noise') {
        if ($info{noiseSource} =~ /^(dark|blackbody)$/i) {
            return 1;
        }
    }

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
    return ();
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

Array Tests are converted to a special noise observation.

=cut

sub handle_special_modes {
    my $self = shift;
    my $info = shift;
    my $has_fts = scalar grep {$_ eq 'fts2'} @{$info->{'inbeam'}};
    my $has_pol = scalar grep {$_ =~ /^pol/} @{$info->{'inbeam'}};

    # The trick is to fill in the blanks

    # POINTING and FOCUS
    if ($info->{obs_type} =~ /pointing|focus/) {
        # Get the integration time in seconds
        my $exptime = OMP::Config->getData(
            $self->cfgkey . "." . $info->{obs_type}
            . "_integration"
            . ($has_fts ? '_fts' : ''));

        $self->output(
            "Determining " . uc($info->{obs_type}) . " parameters...\n",
            "\tIntegration time: $exptime secs\n");

        if ($info->{mapping_mode} eq 'scan') {
            # do this as a point source
            $info->{scanPattern} = $info->{obs_type};
            $info->{sampleTime} = $exptime;
        }
        elsif ($info->{mapping_mode} eq 'stare') {
            $info->{secsPerCycle} = $exptime;
        }
        elsif ($info->{mapping_mode} eq 'dream') {
            $info->{sampleTime} = $exptime;
        }
    }
    elsif ($info->{obs_type} =~ /array_tests/) {
        $self->output("Array tests implemented as short dark noise.\n");

        $info->{obs_type} = "noise";
        $info->{secsPerCycle} = OMP::Config->getData(
            $self->cfgkey . "." . "array_tests_integration");
        $info->{noiseSource} = "dark";
    }
    elsif ($info->{obs_type} =~ /noise/) {
        $info->{secsPerCycle} = OMP::Config->getData(
            $self->cfgkey . "." . "noise_integration");
    }
    elsif ($info->{obs_type} =~ /flatfield/) {
        $self->output("Setting integration time for " . $info->{obs_type} . " observation\n");

        $info->{secsPerCycle} = OMP::Config->getData(
            $self->cfgkey . "." . "flatfield_integration");
    }

    if ($info->{mapping_mode} eq 'scan') {
        # fix up point source scanning
        if ($info->{scanPattern} eq 'Point Source'
                || $info->{scanPattern} =~ /pointing|focus/) {
            my $smode = $info->{scanPattern};
            if ($info->{scanPattern} =~ /Source/) {
                $smode = 'pntsrc';
            }

            $self->output("Defining " . $info->{scanPattern} . " scan map from config.\n");

            my %scan_parameters = (
                scanPattern => "pattern",
                MAP_HEIGHT => "map_height",
                MAP_WIDTH => "map_width",
                SCAN_VELOCITY => "velocity",
                SCAN_DY => "scan_dy",
            );

            my $key = ".scan_" . $smode . "_";
            my $prefix = $has_fts ? 'fts' : ($has_pol ? 'pol' : undef);

            foreach my $param (keys %scan_parameters) {
                my $name = $scan_parameters{$param};
                $info->{$param} = OMP::Config->getData(
                    $self->cfgkey . $key . $name);

                next unless defined $prefix;

                my $override = eval {
                    OMP::Config->getData(
                        $self->cfgkey . '.' . $prefix
                        . '_' . substr($key, 1) . $name);
                };

                next unless defined $override;

                $self->output('        Overriding ' . $param . ' parameter for ' . $prefix . ".\n");
                $info->{$param} = $override;
            }

            for my $extras (qw/TURN_RADIUS ACCEL XSTART YSTART VX VY/) {
                my $cfgitem = lc($extras);
                my $cfgvalue = eval {
                    OMP::Config->getData($self->cfgkey . $key . $cfgitem);
                };

                $info->{"SCAN_$extras"} = $cfgvalue
                    if (defined $cfgvalue && length($cfgvalue));

                next unless defined $prefix;

                my $override = eval {
                    OMP::Config->getData(
                        $self->cfgkey . '.' . $prefix
                        . '_' . substr($key, 1) . $cfgitem);
                };

                next unless defined $override;

                $self->output('        Overriding ' . $extras . ' extra parameter for ' . $prefix . ".\n");
                $info->{'SCAN_' . $extras} = $override;
            }

            $info->{SCAN_SYSTEM} = "FPLANE";
            $info->{MAP_PA} = 0;

        }
        elsif ($info->{scanPattern} =~ /liss|pong/i) {
            my $pongmode = eval {
                OMP::Config->getData($self->cfgkey . ".scan_pong_mode");
            };
            my $scan_dy = eval {
                OMP::Config->getData($self->cfgkey . ".scan_pong_scan_dy");
            };
            my $scan_vel = eval {
                OMP::Config->getData($self->cfgkey . ".scan_pong_velocity");
            };

            if (defined $pongmode
                    && ($pongmode =~ /^dyn/i || $pongmode =~ /^fine/i)) {
                my $map_width = $info->{MAP_WIDTH};
                my $map_height = $info->{MAP_HEIGHT};
                my $avwidth = ($map_width + $map_height) / 2;

                if ($pongmode =~ /^dyn/i) {
                    ($scan_dy, $scan_vel) = $self->_get_dyn_pong_parameters($avwidth);
                }
                elsif ($pongmode =~ /^fine/i) {
                    # Finely spaced map always has dy of 3
                    $scan_dy = 3.0;
                    if ($avwidth <= 150) {
                        $scan_vel = 60;
                    }
                    elsif ($avwidth <= 400) {
                        $scan_vel = 120;
                    }
                    else {
                        $scan_vel = 240;
                    }
                }
                else {
                    # something has gone wrong
                    throw OMP::Error::FatalError("Unable to understand pong mode $pongmode. Programming error.");
                }

                $self->output(
                    "\tOverriding scan parameters given in the OT based on map size and mode '$pongmode'"
                    . " to use a DY of $scan_dy arcsec and speed of $scan_vel arcsec/sec\n");

                $info->{SCAN_DY} = $scan_dy;
                $info->{SCAN_VELOCITY} = $scan_vel;
            }
            else {
                # pongmode not set or not recognized or set to "ot".
                if (defined $scan_dy) {
                    if (defined $info->{SCAN_DY}) {
                        $self->output(
                            "\tOverriding scan spacing given in the OT."
                            . " Changing $info->{SCAN_DY} to $scan_dy arcsec\n")
                            if $info->{SCAN_DY} != $scan_dy;
                    }
                    $info->{SCAN_DY} = $scan_dy;
                }
                if (defined $scan_vel) {
                    if (defined $info->{SCAN_VELOCITY}) {
                        $self->output(
                            "\tOverriding scan velocity given in the OT."
                            . " Changing $info->{SCAN_VELOCITY} to $scan_vel arcsec/sec\n")
                            if $info->{SCAN_VELOCITY} != $scan_vel;
                    }
                    $info->{SCAN_VELOCITY} = $scan_vel;
                }
            }
        }
    }

    return;
}

=item B<_get_dyn_pong_parameters>

Determine pong parameters for "dynamic" mode, based on the map size.

    my $av_size = ($map_width + $map_height) / 2;
    my ($scan_dy, $scan_vel) = $self->_get_dyn_pong_parameters($av_size);

Works by reading the following configuration file parameters:

    scan_pong_dyn_N_max
    scan_pong_dyn_N_dy
    scan_pong_dyn_N_vel
    scan_pong_dyn_N_duration

where N takes consecutive positive integer values and max specifies
the maximum map size controlled by a given parameter set, or is "END"
to indicate that the last set has been reached.  The duration parameter
is only accessed if the vel paramter is not given for a particular set.

=cut

sub _get_dyn_pong_parameters {
    my $self = shift;
    my $avwidth = shift;

    for (my $i = 1;; $i ++) {
        my $prefix = $self->cfgkey() . sprintf('.scan_pong_dyn_%i_', $i);

        my $max_width = OMP::Config->getData($prefix . 'max');
        next unless (($max_width eq 'END') or ($avwidth <= $max_width));

        my $scan_dy = OMP::Config->getData($prefix . 'dy');
        my $scan_vel = eval {OMP::Config->getData($prefix . 'vel')};

        # If "vel" wasn't defined, calculate it from the "duration".
        unless (defined $scan_vel) {
            my $scan_dur = OMP::Config->getData($prefix . 'duration');
            $scan_vel = $avwidth / (0.0 + $scan_dur);
        }

        return ($scan_dy, $scan_vel);
    }
}

=item B<read_extra_apertures>

Reads the extra apertures file and returns a hashref of name to X, Y pair.

=cut

sub read_extra_apertures {
    my $self = shift;
    unless (defined $self->{'extra_apertures'}) {
        my %hash = ();
        my $file = File::Spec->catfile($self->wiredir(), 'extra_apertures.txt');
        my $fh = IO::File->new($file);
        if ($fh) {
            while (<$fh>) {
                chomp;
                my ($name, $x, $y, undef) = split;
                $hash{$name} = [$x, $y];
            }
        }
        $self->{'extra_apertures'} = \%hash;
    }
    return $self->{'extra_apertures'};
}

=back

=head2 Config Generators

These routine configure the specific C<JAC::OCS::Config> objects.

=over 4

=item B<frontend_config>

Configure the SCUBA-2 specific instrument XML.

    $trans->frontend_config($cfg, %$obs);

=cut

sub frontend_config {
    my $self = shift;
    my $cfg = shift;
    my %info = @_;

    my $sc = JAC::OCS::Config::SCUBA2->new();

    $cfg->scuba2($sc);
}

=item B<backend_config>

This method does nothing for SCUBA-2.

=cut

sub backend_config {
    my $self = shift;
    my $cfg = shift;
    my %info = @_;
}

=item B<jos_config>

The JOS configurations for SCUBA-2 have little in common with the
ACSIS versions so this is an independent implementation.

    $trans->jos_config($cfg, %info);

=cut

sub jos_config {
    my $self = shift;
    my $cfg = shift;
    my %info = @_;

    my $jos = JAC::OCS::Config::JOS->new();

    # Basics
    $jos->step_time($self->step_time($cfg, %info));
    $jos->start_index(1);

    # Calculate the effective step time
    my $steperr = eval {
        OMP::Config->getData($self->cfgkey . ".step_time_error");
    };
    $steperr = 1.0 unless defined $steperr;
    my $eff_step_time = $jos->step_time * $steperr;

    # Allowed JOS recipes seem to be
    #   scuba2_scan
    #   scuba2_dream
    #   scuba2_stare
    #   scuba2_skydip
    #   scuba2_flatField
    #   scuba2_noise
    #   scuba2_setup_subarrays
    #   scuba2_stepAndIntegrate (for FTS-2 or POL-2)
    #   scuba2_constantVelocity (for FTS-2 or POL-2)
    #   scuba2_zpd (for FTS-2)

    my $recipe = $info{obs_type};
    if ($info{obs_type} eq 'science') {
        if ($info{observing_mode} eq 'stare_fts2') {
            my $fts2 = $cfg->fts2();
            OMP::Error::FatalError->throw(
                "Could not determine observing recipe for FTS-2 observation because the FTS-2 configuration object was not present")
                unless defined $fts2;

            my $scan_mode = $fts2->scan_mode();
            if ($scan_mode eq 'RAPID_SCAN') {
                $recipe = 'constantVelocity';
            }
            elsif ($scan_mode eq 'STEP_AND_INTEGRATE') {
                $recipe = 'stepAndIntegrate';
            }
            elsif ($scan_mode eq 'ZPD_MODE') {
                $recipe = 'zpd';
            }
            else {
                OMP::Error::FatalError->throw(
                    "Could not determine observing recipe for FTS-2 observation because the scan mode $scan_mode was not recognised");
            }
        }
        elsif ($info{observing_mode} eq 'stare_spin_pol') {
            $recipe = 'constantVelocity';
        }
        elsif ($info{'observing_mode'} eq 'scan_spin_pol') {
            $recipe = 'scan';
        }
        else {
            $recipe = $info{observing_mode};
        }
    }
    elsif ($info{obs_type} eq 'setup') {
        $recipe = "setup_subarrays";
    }

    # prepend scuba2
    $recipe = "scuba2_" . $recipe;

    # and store it
    $jos->recipe($recipe);

    # Time between darks depends on observing mode (but not _pol, _blackbody)
    my $obsmode_strip = $info{observing_mode};
    $obsmode_strip =~ s/_.*$//;
    my $tbdark = OMP::Config->getData(
        "scuba2_translator.time_between_dark_" . $obsmode_strip) / $eff_step_time;

    $jos->steps_btwn_dark($tbdark);

    my $tbflat = OMP::Config->getData(
        "scuba2_translator.time_between_flat_" . $obsmode_strip) / $eff_step_time;

    $jos->steps_btwn_flat($tbflat);

    # This controls the length of the initial dark if one is used.
    # A DARK noise will use JOS_MIN as for any other observation
    my $darklen = OMP::Config->getData($self->cfgkey . ".dark_time");
    $jos->n_darksamples(OMP::General::nint($darklen / $eff_step_time));

    # Flat ramp
    if ($info{obs_type} !~ /^skydip/) {
        my $flatramplen = OMP::Config->getData($self->cfgkey . ".flatramp_time");
        $jos->n_flatsamples(OMP::General::nint($flatramplen / $eff_step_time));
    }
    else {
        # For now do not do the flat ramp for skydips
        $jos->n_flatsamples(0);
    }

    $self->output(
        "Generic JOS parameters:\n",
        "\tStep time: " . $jos->step_time . " secs (effective: $eff_step_time)\n",
        "\tSteps between darks: " . $jos->steps_btwn_dark() . "\n",
        "\tSteps between flatfields: " . $jos->steps_btwn_flat() . "\n"
    );
    $self->output("\tDark duration: " . $jos->n_darksamples() . " steps\n")
        if $jos->n_darksamples;
    $self->output("\tFlat ramp duration: " . $jos->n_flatsamples() . " steps\n")
        if $jos->n_flatsamples;

    if ($info{obs_type} =~ /^skydip/) {
        $self->output("Skydip JOS parameters:\n");

        if ($info{observing_mode} =~ /^stare/) {
            # need JOS_MIN since we have multiple offsets
            my $integ = OMP::Config->getData($self->cfgkey . '.skydip_integ');
            $jos->jos_min(POSIX::ceil($integ / $eff_step_time));

            $self->output("\tSteps per discrete elevation: " . $jos->jos_min() . "\n");

            # make sure we always do a dark between positions
            $jos->steps_btwn_dark(1);
        }
        else {
            # scan so JOS_MIN is 1
            $jos->jos_min(1);

            $self->output("\tContinuous scanning skydip\n");
        }
    }
    elsif ($info{obs_type} =~ /^setup/) {
        $self->output("Setup JOS parameters:\n");
    }
    elsif ($info{obs_type} =~ /^flatfield/) {
        # This is the integration time directly from the config file
        # and directly corresponds to JOS_MIN
        my $inttime = $info{secsPerCycle};
        my $nsteps = OMP::General::nint($inttime / $eff_step_time);

        $jos->jos_min($nsteps);

        $self->output("\tFlatfield source: $info{flatSource}\n");
    }
    elsif ($info{obs_type} eq 'noise') {
        # Requested duration of noise observation
        my $inttime = $info{secsPerCycle};

        # convert total integration time to steps
        my $nsteps = $inttime / $eff_step_time;

        # The whole point of noise is to have a continuous time series
        # so we never split it up
        my $num_cycles = 1;
        my $jos_min = OMP::General::nint($nsteps / $num_cycles);
        $jos->num_cycles($num_cycles);

        $self->output(
            ucfirst($info{obs_type}) . " JOS parameters:\n",
            "\tNoise source: $info{noiseSource}\n",
            "\tRequested integration time: $inttime secs\n",
            "\tNumber of cycles calculated: $num_cycles\n",
            "\tActual integration time: " . ($jos_min * $num_cycles * $eff_step_time) . " secs\n");

        # Set the duration
        $jos->jos_min($jos_min);
    }
    elsif ($info{observing_mode} eq 'stare_fts2') {
        # Handle FTS-2 before stare/dream as it is a special case
        # of stare.  Probably clearer to have a separate block rather than
        # having the stare/dream case also deal with FTS-2.
        # Also for FTS-2 we do not want to break a scan for darks.

        # For FTS-2 we currently disable some of the sub-arrays which has
        # the knock-on effect of slighly reducing the delays in the system
        # which cause the average step time to exceed the requested
        # step time.  Therefore as requested by Doug Johnstone
        # (by Polycom, 2013-05-22, during FTS-2 E&C run), allow an
        # alternate value of step_time_error to be specified for FTS-2
        # observations.  This should allow us to avoid the problem of
        # FTS-2 scans ending too early because the steps in them end up
        # shorter than expected by giving a smaller error factor.
        my $ftssteperr = eval {
            OMP::Config->getData($self->cfgkey . '.fts_step_time_error');
        };
        if (defined $ftssteperr) {
            $eff_step_time = $jos->step_time() * $ftssteperr;
        }

        my $fts2 = $cfg->fts2();
        throw OMP::Error::FatalError('FTS-2 setup is not available')
            unless defined $fts2;

        my $scan_length = $fts2->scan_length();
        throw OMP::Error::FatalError(
            "Could not determine observing time for FTS-2 observation because the scan length is not specified")
            unless defined $scan_length;

        my $inttime;
        my $inttime_note = undef;
        my $scan_mode = $fts2->scan_mode();
        if ($scan_mode eq 'RAPID_SCAN' or $scan_mode eq 'ZPD_MODE') {
            my $scan_spd = $fts2->scan_spd();
            throw OMP::Error::FatalError(
                "Could not determine observing time for FTS-2 observation because the scan speed is not specified")
                unless defined $scan_spd;
            throw OMP::Error::FatalError(
                "Could not determine observing time for FTS-2 observation because the scan speed is zero")
                if 0 == $scan_spd;

            my $acceleration = OMP::Config->getData(
                $self->cfgkey . '.fts_acceleration');

            # Correct for time spent accelerating.
            # During t_accel = speed / accel
            # at the start of the scan we cover a distance of
            # 1/2 * accel * t_accel^2 = 1/2 * spd * t_accel
            # i.e. half the expected distance.   So including both
            # ends of the scan we need to spend an extra t_accel
            # at full speed to cover the requested scan length.
            $inttime = ($scan_length / $scan_spd) + ($scan_spd / $acceleration);
        }
        elsif ($scan_mode eq 'STEP_AND_INTEGRATE') {
            my $step_dist = $fts2->step_dist();
            throw OMP::Error::FatalError(
                "Could not determine observing time for FTS-2 observation because the step distance is not specified")
                unless defined $step_dist;
            throw OMP::Error::FatalError(
                "Could not determine observing time for FTS-2 observation because the step distance is zero")
                if 0 == $step_dist;

            my $step_integrate_time =
                OMP::Config->getData($self->cfgkey . '.fts_step_and_integrate_time');
            throw OMP::Error::FatalError(
                "Could not determine observing time for FTS-2 observation because the STEP_AND INTEGRATE time was not defined")
                unless defined $step_integrate_time;

            # Unsure how FTS-2 will round the number of steps, so for now
            # use (1 + floor) to ensure we never calculate 0 steps.
            my $n_steps = 1 + POSIX::floor(abs($scan_length / $step_dist));

            $inttime = $step_integrate_time * $n_steps;
            $inttime_note = "($n_steps steps)";
        }

        throw OMP::Error::FatalError(
            "Could not determine cycle time for FTS-2 observation, probably because the scan mode '$scan_mode' was not recognised")
            unless defined $inttime;

        my $sample_time = $info{'sampleTime'};
        throw OMP::Error::FatalError(
            "Could not determine observing time for FTS-2 observation because there was no sampleTime parameter")
            unless defined $sample_time;

        # This time should be spread over the number of microsteps
        # for which we need an obsArea.
        my $tcs = $cfg->tcs();
        throw OMP::Error::FatalError('TCS setup is not available')
            unless defined $tcs;

        my $obsArea = $tcs->getObsArea();
        throw OMP::Error::FatalError('TCS obsArea is not available')
            unless defined $obsArea;

        my @ms = $obsArea->microsteps();
        my $nms = (@ms ? @ms : 1);
        $sample_time /= $nms;

        # Convert total integration time to steps
        # but don't split into chunks.
        # Use sufficient FTS-2 scans to give the desired integration time.
        my $num_cycles = POSIX::ceil($sample_time / $inttime);
        my $jos_min = OMP::General::nint($inttime / $eff_step_time);

        # Continuous scanning in one sequence?
        # For RAPID_SCAN / ZPD_MODE we now plan to scan back and forth within
        # a sequence, so recombine the cycles.
        if ($scan_mode eq 'RAPID_SCAN' or $scan_mode eq 'ZPD_MODE') {
            $jos_min *= $num_cycles;
            $num_cycles = 1;
        }

        # Raise an error if the number of steps exceeeds the maximum
        # which FTS-2 can handle.
        my $jos_max = OMP::Config->getData($self->cfgkey . '.fts_max_steps');
        throw OMP::Error::FatalError(
            "Number of sequence steps ($jos_min) exceeds the maximum permissible ($jos_max) for FTS-2 observations")
            if $jos_max && $jos_min > $jos_max;

        $jos->jos_min($jos_min);
        $jos->num_cycles($num_cycles);

        $self->output(
            "FTS-2 JOS parameters:\n",
            "\tEffective step time: $eff_step_time secs\n",
            "\tRequested integration time: $sample_time secs\n",
            "\tTo be spread over: $nms microsteps\n",
            "\tCalculated time per scan: $inttime secs"
                . (defined $inttime_note ? ' ' . $inttime_note : '')
                . "\n",
            "\tNumber of steps per sequence: $jos_min\n",
            "\tNumber of cycles calculated: $num_cycles\n",
            "\tActual total time: " . ($jos_min * $num_cycles * $eff_step_time) . " secs\n");

    }
    elsif ($info{mapping_mode} eq 'stare'
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
        OMP::Error::FatalError->throw(
            "Could not determine integration time for $info{mapping_mode} observation")
            unless defined $inttime;

        # Need an obsArea for number of microsteps
        my $nms = 1;
        my $tcs = $cfg->tcs;
        throw OMP::Error::FatalError('TCS setup is not available')
            unless defined $tcs;

        my $obsArea = $tcs->getObsArea();
        throw OMP::Error::FatalError('TCS obsArea is not available')
            unless defined $obsArea;

        # This time should be spread over the number of microsteps
        my @ms = $obsArea->microsteps;
        $nms = (@ms ? @ms : 1);

        # convert total integration time to steps
        my $nsteps = $inttime / $eff_step_time;

        # Spread over microsteps
        $nsteps /= $nms;

        # split into chunks
        my $num_cycles = POSIX::ceil($nsteps / $tbdark);
        my $jos_min = OMP::General::nint($nsteps / $num_cycles);

        $jos->jos_min($jos_min);
        $jos->num_cycles($num_cycles);

        $self->output(
            uc($info{mapping_mode}) . " JOS parameters:\n",
            "\tRequested integration time per pixel: $inttime secs\n",
            "\tNumber of steps per microstep/offset: $jos_min\n",
            "\tNumber of cycles calculated: $num_cycles\n",
            "\tActual integration time per stare position: "
                . ($jos_min * $num_cycles * $nms * $eff_step_time)
                . " secs\n");
    }
    elsif ($info{mapping_mode} eq 'scan') {
        # The aim here is to use the minimum number of sequences
        # to get the correct map area. For "point source" it is easy
        # because we assume that the time requested is the length
        # of the sequence. For normal scan maps we are given an area
        # and a number of repeats so we need to know how long that will be.
        # We end up with a JOS_MIN value. In principal we have to ensure
        # that we break at steps_between_darks.
        $self->output("Scan map JOS parameters\n");

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
        elsif ($info{scanPattern} =~ /bous/i) {
            my $pixarea = $mapping_info{DY} * $mapping_info{VELOCITY};
            my $maparea = $mapping_info{WIDTH} * $mapping_info{HEIGHT};

            $duration_per_area = ($maparea / $pixarea) * $eff_step_time;
        }
        elsif ($info{scanPattern} =~ /ell/i) {
            my $rx = $mapping_info{WIDTH};
            my $ry = $mapping_info{HEIGHT};

            # Calculate an approximate "radius" for the ellipse
            my $r = sqrt(($rx * $rx + $ry * $ry) / 2.0);
            my $perimeter = 2.0 * pi * $r;

            $duration_per_area = $perimeter / $mapping_info{VELOCITY};
        }
        elsif ($info{scanPattern} =~ /daisy/i) {
         # Originally from Per Friberg, committed Wed Feb 10 15:32:12 2010 -1000
            my $r0 = ($mapping_info{WIDTH} + $mapping_info{HEIGHT}) / 4;

            # Negative DY values have been used as a hack to adjust the daisy
            # pattern, but they disturb the calculation.  Therefore check
            # if we have a negative value and if so, use the default.
            my $dy = $mapping_info{DY};
            if ($dy < 0) {
                if (OMP::Config->getData($self->cfgkey . '.scan_pntsrc_pattern') == 'cv_daisy') {
                    $dy = OMP::Config->getData(
                        $self->cfgkey . '.scan_pntsrc_scan_dy');
                    $self->output("\tNegative DY: found value DY=$dy for calculation.\n");
                }
                else {
                    # Have to just take the default value...
                    $dy = 0.6;
                    $self->output("\tNegative DY: used default DY=$dy for calculation.\n");
                }
            }
            my $o = $mapping_info{VELOCITY} / $dy / $r0;
            my $O = $o / 10.1;
            $duration_per_area = 2.0 * pi / $O;
        }
        else {
            throw OMP::Error::FatalError(
                "Unrecognized scan pattern: $info{scanPattern}");
        }

        $self->output(
            "\tEstimated time to cover the map area once: $duration_per_area sec\n");

        my $nsteps;
        if (exists $info{sampleTime} && defined $info{sampleTime}) {
            # Specify the length of the sequence
            $nsteps = $info{sampleTime} / $eff_step_time;
            $self->output(
                "\tScan map executing for a specific time. Not map coverage\n",
                "\tTotal duration requested for scan map: $info{sampleTime} secs.\n");
        }
        else {
            my $nrepeats = ($info{nintegrations} ? $info{nintegrations} : 1);

            $self->output(
                "\tNumber of repeats of map area requested: $nrepeats\n");

            $nsteps = ($nrepeats * $duration_per_area) / $eff_step_time;
        }

        # This calculation may well be inefficient given the TCS requirement
        # to use an integer number of scan areas in a sequence. It could be tricky
        # if we want 5 repeats but do them as 2 sets of 3 or 3 sets of 2. We tend
        # to hope that steps_between_darks will be so high that this is irrelevant.

        # steps between darks must be at least the duration_per_area
        # otherwise the num_cycles calculation means that you end up with
        # too many repeats
        my $steps_per_pass = $duration_per_area / $eff_step_time;
        $tbdark = max($tbdark, $steps_per_pass);

        # Maximum length of a sequence
        my $jos_max = OMP::Config->getData($self->cfgkey . ".jos_max");

        # Check whether the scanning pattern has a defined maximum
        # cycle defined.  If it does, use it to lower $jos_max
        # if necessary, so that the scan will be chunked into
        # a number of cycles.
        try {
            my $max_cycle_steps = OMP::Config->getData(
                $self->cfgkey . '.scan_max_cycle_duration_'
                . lc($info{scanPattern})) / $eff_step_time;

            $self->output("\tMax cycle steps: $max_cycle_steps\n");
            $jos_max = min($jos_max, $max_cycle_steps);
        }
        catch OMP::Error::BadCfgKey with {
            # Do nothing -- this key is optional.
            $self->output("\tMax cycle steps: not applied\n");
        };

        # for pointings we need to be able to control the number of repeats
        # dynamically in the JOS so we go for the less optimal solution
        # of causing the map to be split up into chunks
        my $num_cycles;
        my $jos_min;
        my $tot_time;
        if ($info{obs_type} =~ /point|focus/i) {
            my $minlen = OMP::Config->getData(
                $self->cfgkey . "." . $info{obs_type} . "_min_cycle_duration");

            $num_cycles = POSIX::ceil($nsteps / $steps_per_pass);

            my $div = POSIX::ceil(
                min($nsteps * $eff_step_time, $minlen) / $duration_per_area);

            $num_cycles = POSIX::ceil($num_cycles / $div);

            # No point requesting more steps than we wanted originally
            $jos_min = min($nsteps, $div * $steps_per_pass);
        }
        else {
            $num_cycles = POSIX::ceil($nsteps / $tbdark);
            $jos_min = OMP::General::nint($nsteps / $num_cycles);
        }

        if ($jos_min > $jos_max) {
            # We have a problem
            my $mult = POSIX::ceil($jos_min / $jos_max);

            $jos_min /= $mult;
            $num_cycles *= $mult;
            $self->output("\tSequence too long. Scaling down by factor of $mult\n");
        }

        # Force jos_min to be an integer
        $jos_min = OMP::General::nint($jos_min);

        # For some modes we want a change in PA each time round the map so we have to do that
        # now. Used for PONG, LISSAJOUS and BOUSTROPHEDON patterns. Do this if we only have
        # a single position angle or no position angle.
        my @posang = $obsArea->posang;
        if ($obsArea->scan_pattern =~ /pong|liss|bous/i && @posang < 2) {
            # work out how many times round the pattern we are going to go
            my $npatterns = OMP::General::nint(
                ($jos_min * $eff_step_time) / $duration_per_area);

            if ($npatterns > 1) {
                # get the base position angle
                my $ref_pa = $posang[0];
                unless (defined $ref_pa) {
                    $ref_pa = 0;
                }
                else {
                    $ref_pa = $ref_pa->degrees;
                }

                # delta
                my $delta = 90 / $npatterns;
                $self->output("\tRotating map PA by $delta deg each time for $npatterns repeats\n");

                @posang = map {$ref_pa + ($_ * $delta)} (0 .. $npatterns - 1);
                $obsArea->posang(map {
                    Astro::Coords::Angle->new($_, units => 'degrees')
                } @posang);
            }
        }

        # for now set steps between dark to the JOS_MIN, otherwise the JOS
        # will try to get clever and multiply up the NUM_CYCLES
        # For focus we definitely do not want darks between the focus positions though.
        $jos->steps_btwn_dark($jos_min)
            unless $info{obs_type} =~ /focus/;

        $tot_time = $num_cycles * $jos_min * $eff_step_time;
        $jos->jos_min($jos_min);
        $jos->num_cycles($num_cycles);

        $self->output(
            "\tNumber of steps in scan map sequence: $jos_min\n",
            "\tNumber of repeats: $num_cycles\n",
            "\tTime spent mapping: $tot_time sec\n");
    }

    # Non science observing types
    if ($info{obs_type} =~ /focus/) {
        $jos->num_focus_steps($info{focusPoints});

        # Focus step is missing from OT at the moment.
        my $stepsize = $info{focusStep};
        unless (defined $stepsize) {
            if ($info{focusAxis} =~ /z/i) {
                $stepsize = 0.3;
            }
            else {
                $stepsize = 1.0;
            }
        }
        $jos->focus_step($stepsize);
        $jos->focus_axis($info{focusAxis});
    }

    # Craig requested that the translator inform the JOS how many
    # offset indices there are, and how many microstep patterns.
    # The reason for this is that the TCS gets the list of positions
    # and only informs the JOS whether there is another one left
    # or not.  Adding the number will allow the JOS monitor to
    # display how many steps there are along with the current
    # index.
    do {
        my $n_index = 1;
        my $n_ms_index = 1;

        my $tcs = $cfg->tcs();
        if (defined $tcs) {
            my $obsArea = $tcs->getObsArea();
            if (defined $obsArea) {
                my @os = $obsArea->offsets();
                $n_index = scalar @os if @os;
                my @ms = $obsArea->microsteps();
                $n_ms_index = scalar @ms if @ms;
            }
        }
        $jos->n_index($n_index);
        $jos->n_ms_index($n_ms_index);
    };

    # store it
    $cfg->jos($jos);
}

=item B<rotator_config>

There is no rotator for SCUBA-2.

=cut

sub rotator_config {
}

=item B<fts2_config>

Reads the information from OMP::MSB (which should be in a simple hash form from
the unroll_obs method) and creates a JAC::OCS::Config::FTS2 object.

In the case of pointing and focus, it doesn't do that, but it just tweaks
the SCUBA-2 and TCS configurations accordingly.

=cut

sub fts2_config {
    my $self = shift;
    my $cfg = shift;
    my %info = @_;

    if ($info{'MODE'} eq 'SpIterPointingObs'
            or $info{'MODE'} eq 'SpIterFocusObs') {
        # If this is a pointing or focus, check if FTS-2 is in the beam.
        if (grep {$_ eq 'fts2'} @{$info{'inbeam'}}) {
            $self->output("FTS-2 pointing/focus observation\n");

            my $port = OMP::Config->getData(
                $self->cfgkey . '.fts_'
                    . (($info{'MODE'} eq 'SpIterFocusObs') ? 'focus' : 'pointing')
                    . '_port');
            $self->fts2_tcs_config($cfg, $port);
            $self->fts2_scuba2_config($cfg, $port, '');
        }

        # Return now as we do not need to configure FTS-2 itself.
        return;
    }
    elsif ($info{'MODE'} ne 'SpIterFTS2Obs') {
        # Return now if this is not an FTS-2 observation.
        return;
    }

    $self->output("FTS-2 observation:\n");

    my $fts2 = JAC::OCS::Config::FTS2->new();

    my $mode = $info{'SpecialMode'};
    my $centre = OMP::Config->getData($self->cfgkey . '.fts_centre_position');

    # OT includes sampleTime for the FTS-2 observation but it's not
    # part of the FTS2_CONFIG.
    # my $samptime = $info{'sampleTime'};

    # Mapping from standard mode names to config file parameter keys:
    my %standardmodes = (
        # The SED observation mode produces low-resolution double-sided
        # interferograms using the dual-port configuration.
        'SED' => 'sed',
        'SED 450um' => 'sed450',
        'SED 850um' => 'sed850',

        # The Spectral Line mode acquires high-resolution single-sided
        # interferograms using the dual-port configuration.
        'Spectral Line' => 'spectralline',
        'Spectral Line 450um' => 'spectralline450',
        'Spectral Line 850um' => 'spectralline850',
    );

    if (exists $standardmodes{$mode}) {
        my $key = $standardmodes{$mode};

        my $length = OMP::Config->getData($self->cfgkey . '.fts_' . $key . '_length');

        $fts2->scan_mode('RAPID_SCAN');
        $fts2->scan_dir('DIR_ARBITRARY');
        $fts2->scan_origin($centre - $length / 2);
        $fts2->scan_spd(OMP::Config->getData($self->cfgkey . '.fts_' . $key . '_speed'));
        $fts2->scan_length($length);
    }
    elsif ($mode eq 'Spectral Flatfield') {
        # Don't know what this mode is.

        my $length = OMP::Config->getData($self->cfgkey . '.fts_spectralflat_length');

        $fts2->scan_mode('RAPID_SCAN');
        $fts2->scan_dir('DIR_ARBITRARY');
        $fts2->scan_origin($centre - $length / 2);
        $fts2->scan_spd(OMP::Config->getData($self->cfgkey . '.fts_spectralflat_speed'));
        $fts2->scan_length($length);

    }
    elsif ($mode eq 'ZPD') {
        # The ZPD operating mode records a short double-sided interferogram with
        # the FTS configured in the single-port mode and one of the blackbody
        # shutters closed.

        my $length = OMP::Config->getData($self->cfgkey . '.fts_zpd_length');

        $fts2->scan_mode('ZPD_MODE');
        $fts2->scan_dir('DIR_ARBITRARY');
        $fts2->scan_origin($centre - $length / 2);
        $fts2->scan_spd(OMP::Config->getData($self->cfgkey . '.fts_zpd_speed'));
        $fts2->scan_length($length);
    }
    elsif ($mode eq 'Variable Mode') {
        # With this mode selected the OT allows the resolution and scan-speed
        # to be configured.  (It greys these options out in the other modes.)

        my $speed = $info{'ScanSpeed'};
        throw OMP::Error::TranslateFail('Excessive scan speed: ' . $speed)
            if $speed > OMP::Config->getData($self->cfgkey . '.fts_variable_maxspeed');
        throw OMP::Error::TranslateFail('Scan speed too low: ' . $speed)
            if $speed <= 0.0;

        my $resolution = $info{'resolution'};
        throw OMP::Error::TranslateFail('Resolution zero or negative')
            if $resolution <= 0.0;

        my $length = OMP::Config->getData(
            $self->cfgkey . '.fts_variable_resolutionfactor') / $resolution;
        throw OMP::Error::TranslateFail('Excessive scan length: ' . $length)
            if $length > OMP::Config->getData($self->cfgkey . '.fts_variable_maxlength');

        $fts2->scan_mode('RAPID_SCAN');
        $fts2->scan_dir('DIR_ARBITRARY');
        $fts2->scan_origin($centre - $length / 2);
        $fts2->scan_spd($speed);  # OT commit 587fc38 says these are mm/s already.
        $fts2->scan_length($length);
    }
    elsif ($mode eq 'Step and Integrate') {
        # In this mode the OT allows the scan length, origin
        # and step distance (all in mm) to be specified.

        my $step_dist = $info{'StepDistance'};
        throw OMP::Error::TranslateFail('FTS-2 step distance zero or negative')
            if $step_dist <= 0.0;

        # Assume the limits are the same as variable mode so that we can move
        # to +/- 1/2 maxlength from the center.
        my $max_offset = OMP::Config->getData(
            $self->cfgkey . '.fts_variable_maxlength') / 2.0;

        my $scan_origin= $info{'ScanOrigin'};
        throw OMP::Error::TranslateFail(
            "FTS-2 step origin ($scan_origin mm) out of range (+/- $max_offset mm)")
            if $scan_origin < - $max_offset || $scan_origin > $max_offset;

        my $scan_length = $info{'ScanLength'};

        # Calculate the end position to check whether it is in range.
        my $scan_end = $scan_origin + $scan_length;
        throw OMP::Error::TranslateFail(
            "FTS-2 step end ($scan_origin + $scan_length = $scan_end mm) out of range (+/- $max_offset mm)")
            if $scan_end < - $max_offset || $scan_end > $max_offset;

        $fts2->scan_mode('STEP_AND_INTEGRATE');
        $fts2->scan_dir('DIR_ARBITRARY');
        $fts2->scan_origin($centre + $scan_origin);
        $fts2->scan_length($scan_length);
        $fts2->step_dist($step_dist);
    }
    else {
        throw OMP::Error::TranslateFail('Unknown FTS-2 "Special Mode": ' . $mode);
    }

    # Configure shutters based on port selection.

    my $dual = $info{'isDualPort'};    # Boolean
    my $port = $info{'TrackingPort'};  # Name: 8D or 8C.

    if ($dual) {
        # Open both shutters.
        $fts2->shutter_8d('OUTOFBEAM');
        $fts2->shutter_8c('OUTOFBEAM');
    }
    else {
        if (uc($port) eq '8D') {
            # Open shutter 1 and close shutter 2.
            $fts2->shutter_8d('OUTOFBEAM');
            $fts2->shutter_8c('INBEAM');
        }
        elsif (uc($port) eq '8C') {
            # Open shutter 2 and close shutter 1.
            $fts2->shutter_8d('INBEAM');
            $fts2->shutter_8c('OUTOFBEAM');
        }
        else {
            throw OMP::Error::TranslateFail('Unknown FTS-2 Port: ' . $port);
        }
    }

    $cfg->fts2($fts2);

    # Finished configuring FTS-2, now configure TCS.
    $self->fts2_tcs_config($cfg, $port);

    # Adjust SCUBA-2 mask.
    $self->fts2_scuba2_config($cfg, $port, $mode);
}

=item B<fts2_tcs_config>

Adjusts TCS configuration for observations with FTS-2 in the beam.

    $self->fts2_tcs_config($cfg, $port);

The C<$port> should be '8D' or '8C'.

This subroutine looks up the given port in the extra apertures
file and configures the TCS and INSTAP header accordingly.

=cut

sub fts2_tcs_config {
    my $self = shift;
    my $cfg = shift;
    my $port = shift;

    my $tcs = $cfg->tcs();
    my $instap = $cfg->header()->item('INSTAP');
    my $aperture_name;

    if (uc($port) eq '8D') {
        # FTS-2 port 1 is S4A and S8D
        $aperture_name = 'fts8d';
    }
    elsif (uc($port) eq '8C') {
        # FTS-2 port 2 is S4B and S8C
        $aperture_name = 'fts8c';
    }
    else {
        throw OMP::Error::TranslateFail('Unknown FTS-2 Port: ' . $port);
    }

    $tcs->aperture_name($aperture_name);
    $instap->value($aperture_name);

    my $extra_apertures = $self->read_extra_apertures();

    if (exists $extra_apertures->{$aperture_name}) {
        my $coords = $extra_apertures->{$aperture_name};
        throw OMP::Error::TranslateFail(
            'Did not get valid aperture coordinates for: ' . $aperture_name)
            unless ref $coords;
        $tcs->aperture_xy(@$coords);
    }
    else {
        throw OMP::Error::TranslateFail(
            'Could not determine aperture coordinates for: ' . $aperture_name);
    }
}

=item B<fts2_scuba2_config>

Adjusts SCUBA-2 configuration for observations with FTS-2 in the beam.

    $self->fts2_scuba2_config($cfg, $port, $mode);

This subroutine turns off the non-FTS subarrays, and sets the
main subarray corresponding to the given port to NEED.  The
C<$port> value is as for L<fts2_tcs_config>.

The C<$mode> parameter is used to further adjust the subarray
requirements:

=over 4

=item ZPD

The 450um equivalent subarray is set to NEED instead.

=item Contains 850um

The 450um subarrays are disabled.

=back

=cut

sub fts2_scuba2_config {
    my $self = shift;
    my $cfg = shift;
    my $port = shift;
    my $mode = shift;

    my $scuba2 = $cfg->scuba2();
    my %mask = $scuba2->mask();
    my @unused = qw/s4c s4d s8a s8b/;
    my $short_port;

    if (uc($port) eq '8D') {
        # FTS-2 port 1 is S4A and S8D
        $short_port = '4A';
    }
    elsif (uc($port) eq '8C') {
        # FTS-2 port 2 is S4B and S8C
        $short_port = '4B';
    }
    else {
        throw OMP::Error::TranslateFail('Unknown FTS-2 Port: ' . $port);
    }

    push @unused, qw/s4a s4b/ if $mode =~ /850um/;
    $port = $short_port if $mode eq 'ZPD';

    @mask{@unused} = ('OFF') x scalar @unused;
    $mask{'s' . lc($port)} = 'NEED';

    $scuba2->mask(%mask);
}

=item B<need_offset_tracking>

Returns true if we need to use a particular sub array for this
observation.

    $need = $trans->need_offset_tracking($cfg, %info);

=cut

sub need_offset_tracking {
    my $self = shift;
    my $cfg = shift;
    my %info = @_;

    # Never offset track for noise, skydip, flatfield or setup
    if ($info{obs_type} =~ /noise|skydip|flat|setup/i) {
        return 0;
    }

    # with only 2 subarrays we can be sure that we are meant to
    # use them
    return 1;
}

=item B<step_time>

Step time for SCUBA-2 is usually fixed at 200 Hz.

    $rts = $trans->step_time($cfg, %info);

Flatfield and Noise can be configured independently.

=cut

sub step_time {
    my $self = shift;
    my $cfg = shift;
    my %info = @_;

    # Try obs type version first
    my $step;

    if ($info{obs_type} =~ /^(flatfield|noise)$/) {
        my $q = ($info{is_quick} ? "_quick" : "");
        $step = eval {
            OMP::Config->getData($self->cfgkey . ".step_time_" . $info{obs_type} . $q);
        };
    }

    $step = OMP::Config->getData($self->cfgkey . '.step_time')
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

    ($map_mode, $sw_mode) = $trans->determine_observing_summary($mode, $sw);

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
    }
    elsif ($mode eq 'SpIterStareObs') {
        $mapping_mode = 'stare';
    }
    elsif ($mode eq 'SpIterDREAMObs') {
        $mapping_mode = 'dream';
    }
    elsif ($mode eq 'SpIterFTS2Obs') {
        $mapping_mode = 'stare';
        $switching_mode = 'self';
    }
    elsif ($mode eq 'SpIterPointingObs') {
        $mapping_mode = OMP::Config->getData($self->cfgkey . ".pointing_obsmode");
        $obs_type = 'pointing';
    }
    elsif ($mode eq 'SpIterFocusObs') {
        $mapping_mode = OMP::Config->getData($self->cfgkey . ".focus_obsmode");
        $obs_type = 'focus';
    }
    elsif ($mode eq 'SpIterFlatObs') {
        $obs_type = "flatfield";
        $mapping_mode = "stare";
    }
    elsif ($mode eq 'SpIterArrayTestObs') {
        $obs_type = 'array_tests';
        $mapping_mode = 'stare';
    }
    elsif ($mode eq 'SpIterNoiseObs') {
        $obs_type = 'noise';
        $mapping_mode = 'stare';
    }
    elsif ($mode eq 'SpIterSetupObs') {
        $obs_type = 'setup';
        $mapping_mode = 'stare';
    }
    elsif ($mode eq 'SpIterSkydipObs') {
        my $sdip_mode = OMP::Config->getData($self->cfgkey . ".skydip_mode");
        if ($sdip_mode =~ /^cont/) {
            $mapping_mode = 'scan';
        }
        elsif ($sdip_mode =~ /^dis/) {
            $mapping_mode = "stare";
        }
        else {
            OMP::Error::TranslateFail->throw("Skydip mode '$sdip_mode' not recognized");
        }
        $switching_mode = 'none';
        $obs_type = 'skydip';
    }
    else {
        throw OMP::Error::TranslateFail("Unable to determine observing mode from observation of type '$mode'");
    }

    # switch mode
    my %SW = (
        scan => 'self',
        stare => 'none',
        dream => 'self',
    );
    $switching_mode = $SW{$mapping_mode}
        unless defined $switching_mode;

    throw OMP::Error::TranslateFail(
        "Unable to determine switch mode from map mode of $mapping_mode")
        unless defined $switching_mode;

    return ($mapping_mode, $switching_mode, $obs_type);
}

=item B<determine_inbeam>

Decide what should be in the beam. Uses "shutter" for a dark observation.
Blackbody does not allow FTS.

    @inbeam = $trans->determine_inbeam(%info);

=cut

sub determine_inbeam {
    my $self = shift;
    my %info = @_;
    my @inbeam;

    if ($info{obs_type} eq 'setup' || $info{obs_type} eq 'array_tests') {
        # Setup always in dark
        return ("shutter");
    }

    # see if we have a source in the beam
    my $source;
    if ($info{obs_type} =~ /^flatfield/) {
        $source = lc($info{flatSource});
    }
    elsif (exists $info{noiseSource}) {
        $source = lc($info{noiseSource});
    }

    if (defined $source) {
        if ($source =~ /blackbody/i) {
            push @inbeam, "blackbody";
        }
        elsif ($source =~ /dark/i) {
            return ("shutter");
        }
    }

    # Detect FTS2 observations.  Also check for blackbody because
    # of the POD comment above.
    if ($info{'MODE'} eq 'SpIterFTS2Obs'
            and not(defined $source and $source =~ /blackbody/i)) {
        push @inbeam, 'fts2';
    }

    # Read inbeam hash entry for focus and pointing, allowing fts2 and pol2
    # to be in the beam, subject to the constraint mentioned above.
    if (($info{'MODE'} eq 'SpIterFocusObs' or $info{'MODE'} eq 'SpIterPointingObs')
            and (defined $info{'inbeam'} and ref $info{'inbeam'})) {
        push @inbeam, 'fts2'
            if grep {lc($_) eq 'fts2'} @{$info{'point_focus_inbeam'}}
            and not(defined $source and $source =~ /blackbody/i);

        push @inbeam, 'pol'
            if grep {lc($_) eq 'pol2'} @{$info{'point_focus_inbeam'}};
    }

    # get base class values
    push @inbeam, $self->SUPER::determine_inbeam(%info);

    return @inbeam;
}

1;

__END__

=back

=head1 CONFIGURATION XML

The format of the configuration XML is outlined in JAC document
OCS/ICD/001.

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

Copyright (C) 2007-2012 Science and Technology Facilities Council.
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
