package OMP::CGIComponent::ITCLink;

=head1 NAME

OMP::CGIComponent::ITCLink - Generate links to the ITCs

=head1 SYNOPSIS

    use OMP::CGIComponent::ITCLink;

=head1 DESCRIPTION

Contains methods to generate links to the online ITCs.

=cut

use strict;
use warnings;

use Astro::PAL;
use Data::MessagePack;
use Data::MessagePack::Boolean;
use Math::Trig qw/acos/;
use MIME::Base64 qw/encode_base64url/;

use OMP::Config;

use base qw/OMP::CGIComponent/;

# ITC definitions written by misc/maint/get_itc_params.pl
our $ITC_SCUBA2 = {
    'calculator' => 'scuba2',
    'inputs' => {
        'map' => undef,
        'pix450' => undef,
        'pix850' => undef,
        'pos' => undef,
        'pos_type' => undef,
        'samp' => undef,
        'tau' => undef,
        'time' => undef
    },
    'mode' => 'rms',
    'version' => 2
};
our $ITC_HETERODYNE = {
    'calculator' => 'heterodyne',
    'inputs' => {
        'basket' => undef,
        'cont' => undef,
        'dim_x' => undef,
        'dim_y' => undef,
        'dx' => undef,
        'dy' => undef,
        'elapsed' => undef,
        'freq' => undef,
        'if' => undef,
        'mm' => undef,
        'n_pt' => undef,
        'pos' => undef,
        'pos_type' => undef,
        'res' => undef,
        'res_unit' => undef,
        'rv' => undef,
        'rv_sys' => undef,
        'rx' => undef,
        'sb' => undef,
        'sep_off' => undef,
        'sep_pol' => undef,
        'side' => undef,
        'species' => undef,
        'sw' => undef,
        'tau' => undef,
        'trans' => undef
    },
    'instruments' => {
        'ALAIHI' => {
            'if_option' => 0,
            'name' => "\x{2bb}Ala\x{2bb}ihi"
        },
        'AWEOWEO' => {
            'if_option' => 1,
            'name' => "\x{2bb}\x{100}weoweo"
        },
        'HARP' => {
            'if_option' => 0,
            'name' => 'HARP'
        },
        'KUNTUR' => {
            'if_option' => 1,
            'name' => 'Kuntur'
        },
        'UU' => {
            'if_option' => 1,
            'name' => "\x{2bb}\x{16a}\x{2bb}\x{16b}"
        }
    },
    'mode' => 'rms_el',
    'version' => 3
};
# End of generated ITC definitions.

=head1 METHODS

=over 4

=item B<observation_itc_link>

Given an C<OMP::Info::Obs> object, attempt to construct a query URL
for the relevant ITC with parameters filled in (as far as possible)
for the given observation.

    $url = $comp->observation_itc_link($obs);

Returns C<undef> if unable to generate a suitable URL.

=cut

sub observation_itc_link {
    my $self = shift;
    my $obs = shift;

    my $itc = undef;
    my %values = ();
    my $mode = $obs->mode;
    my $type = $obs->type;
    my $backend = $obs->backend;

    if ($backend eq 'SCUBA-2' and $mode eq 'scan') {
        $itc = $ITC_SCUBA2;
        %values = %{$itc->{'inputs'}};

        $values{'samp'} = 'map';
        $values{'time'} = $obs->calculate_duration('hours');

        my $pattern = $obs->scan_pattern;
        if ($pattern =~ /daisy/i) {
            $values{'map'} = $obs->pol_in ? 'poldaisy' : 'daisy';
        }
        elsif ($pattern =~ /pong/i) {
            my $width = $obs->map_width;
            my $height = $obs->map_height;
            return undef unless (defined $width) && (defined $height);

            my $size = ($width + $height) / 2;
            if ($size <= 1200) {
                $values{'map'} = 'pong900';
            }
            elsif ($size <= 2200) {
                $values{'map'} = 'pong1800';
            }
            elsif ($size <= 3000) {
                $values{'map'} = 'pong2700';
            }
            elsif ($size <= 4800) {
                $values{'map'} = 'pong3600';
            }
            else {
                $values{'map'} = 'pong7200';
            }
        }
        else {
            return undef;
        }
    }
    elsif ($backend eq 'ACSIS') {
        $itc = $ITC_HETERODYNE;
        %values = %{$itc->{'inputs'}};

        $values{'freq'} = $obs->rest_frequency / 1.0e9;
        $values{'elapsed'} = $obs->calculate_duration('hours');

        $values{'cont'} = $Data::MessagePack::Boolean::false;
        $values{'sep_off'} = $Data::MessagePack::Boolean::false;
        $values{'sep_pol'} = $Data::MessagePack::Boolean::false;

        $values{'rv'} = 0.0 + $obs->velocity;
        my $velsys = $obs->velsys;
        if ($velsys =~ /^red/i) {
            $values{'rv_sys'} = 'z';
        }
        elsif ($velsys =~ /^rad/i) {
            $values{'rv_sys'} = 'rad';
        }
        elsif ($velsys =~ /^opt/i) {
            $values{'rv_sys'} = 'opt';
        }
        else {
            return undef;
        }

        $values{'sb'} = ($obs->sideband_mode eq 'DSB')
            ? 'dsb' : 'ssb';

        my $instrument_name = uc $obs->instrument;
        my $instrument = $itc->{'instruments'}->{$instrument_name};
        return undef unless defined $instrument;

        $values{'rx'} = $instrument->{'name'};

        if ($instrument->{'if_option'}) {
            $values{'if'} = 0.0 + $obs->intermediate_frequency;

            $values{'side'} = ($obs->sideband eq 'LSB')
                ? 'lsb' : 'usb';
        }

        if ($obs->bandwidth_mode =~ /^(\d+)(M|G)Hzx(\d+)$/) {
            $values{'res_unit'} = 'MHz';
            $values{'res'} = $1 * ($2 eq 'G' ? 1000.0 : 1.0) / $3;
        }
        else {
            return undef;
        }

        if ($type eq 'raster' or $type eq 'scan') {
            $values{'mm'} = 'raster';
            $values{'basket'} = $Data::MessagePack::Boolean::false;

            # Determine whether "along width" or "along height".
            my $map_pa = $obs->map_angle * Astro::PAL::DD2R;
            my $scan_pa = $obs->scan_angle * Astro::PAL::DD2R;
            if ((sin($map_pa) * sin($scan_pa) + cos($map_pa) * cos($scan_pa)) < 0.7) {
                $values{'dim_x'} = 0.0 + $obs->map_width;
                $values{'dim_y'} = 0.0 + $obs->map_height;
            }
            else {
                $values{'dim_x'} = 0.0 + $obs->map_height;
                $values{'dim_y'} = 0.0 + $obs->map_width;
            }

            my $increment = $obs->scan_increment;
            return undef unless defined $increment;

            if ($instrument_name eq 'HARP') {
                # Fixed size for HARP.
                $values{'dx'} = 7.27;
                # Increment is HARP scan spacing.
                $values{'dy'} = 0.0 + sprintf '%.1f', $increment;
            }
            else {
                # Assume square pixels?
                $values{'dx'} = 0.0 + $increment;
                $values{'dy'} = 0.0 + $increment;
            }
        }
        elsif ($type eq 'grid') {
            $values{'mm'} = 'grid';
            # Older data have no header for number of points - assume 1 if undefined?
            $values{'n_pt'} = ($obs->scan_positions // 1);
        }
        elsif ($type eq 'jiggle') {
            my $positions = $obs->scan_positions;
            return undef unless defined $positions;

            $values{'mm'} = 'jiggle';
            $values{'n_pt'} = 0 + $positions;
        }
        else {
            return undef;
        }

        my $switch = $obs->switch_mode;
        if ($switch eq 'pssw') {
            $values{'sw'} = 'pssw';
        }
        elsif ($switch eq 'chop') {
            $values{'sw'} = 'bmsw';
        }
        elsif ($switch eq 'freqsw') {
            $values{'sw'} = 'frsw';
        }
        else {
            return undef;
        }
    }

    return undef unless defined $itc;

    my $airmass = $obs->airmass;

    return undef unless $airmass;

    $values{'tau'} = 0.0 + sprintf '%.3f', $obs->tau;
    $values{'pos'} = 90.0 - Astro::PAL::DR2D * acos(1.0 / $airmass);
    $values{'pos_type'} = 'el';

    return $self->_query_url(
        $itc->{'calculator'},
        $itc->{'mode'},
        $self->_encode_query(
            $itc->{'version'},
            \%values));
}

sub _query_url {
    my $self = shift;
    my $calculator = shift;
    my $mode = shift;
    my $query = shift;

    my $base_url = OMP::Config->getData('calculator-base-url');

    return sprintf '%s/%s/%s?query=%s',
        $base_url, $calculator, $mode, $query;
}

sub _encode_query {
    my $self = shift;
    my $version = shift;
    my $query = shift;

    my $message = [
        $version,
        map {$query->{$_}} sort keys $query];

    my $mp = Data::MessagePack->new();
    $mp->utf8(1);
    $mp->prefer_integer();

    # Hedwig uses prefix 'M' to identify MessagePack format.
    return 'M' . encode_base64url($mp->pack($message));
}

1;

__END__

=back

=head1 COPYRIGHT

Copyright (C) 2025 East Asian Observatory
All Rights Reserved.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful,but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc.,51 Franklin
Street, Fifth Floor, Boston, MA  02110-1301, USA

=cut
