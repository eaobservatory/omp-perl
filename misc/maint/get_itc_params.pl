#!/local/perl/bin/perl

# Script to fetch ITC information from Hedwig and generate definitions
# to include in the module OMP::CGIComponent::ITCLink.

# Copyright (C) 2025 East Asian Observatory
# All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation; either version 2 of the License, or (at your option) any later
# version.
#
# This program is distributed in the hope that it will be useful,but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
# details.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, write to the Free Software Foundation, Inc.,51 Franklin
# Street, Fifth Floor, Boston, MA  02110-1301, USA

use strict;

use Alien::Taco;
use Data::Dumper;

my $taco = Alien::Taco->new(lang => 'python');

my $dumper = Data::Dumper->new([
    get_info(
        'hedwig.facility.jcmt.calculator_scuba2',
        'SCUBA2Calculator',
        'CALC_RMS'),
    get_info(
        'hedwig.facility.jcmt.calculator_heterodyne',
        'HeterodyneCalculator',
        'CALC_RMS_FROM_ELAPSED_TIME',
        extra_heterodyne => 1),
], [
    'ITC_SCUBA2',
    'ITC_HETERODYNE',
]);

$dumper->Indent(1);
$dumper->Sortkeys(1);

my $description = $dumper->Dump();
$description =~ s/^\$/our \$/gm;
$description =~ s/^( +)/\1\1/gm;
print "# ITC definitions written by $0\n",
    $description,
    "# End of generated ITC definitions.\n";

sub get_info {
    my $module = shift;
    my $class = shift;
    my $mode_enum = shift;
    my %options = @_;

    $taco->import_module($module);

    my $itc = $taco->construct_object(
        (join '.', $module, $class),
        args => [undef, undef]);

    my $code = $itc->call_method('get_code');
    my $mode = $itc->get_attribute($mode_enum);
    my $version = $itc->get_attribute('version');
    my $mode_code = $itc->call_method('get_mode_info', args => [$mode])->[0];

    my $inputs = $itc->call_method('get_inputs', kwargs => {
        mode => (0 + $mode),
        version => (0 + $version)});

    my %codes = map {$_->[0] => undef} @{$taco->call_function('list', args => [$inputs])};

    my %result = (
        calculator => $code,
        mode => $mode_code,
        version => $version,
        inputs => \%codes);

    if ($options{'extra_heterodyne'}) {
        my $rxclass = 'jcmt_itc_heterodyne.receiver';
        $taco->import_module($rxclass);
        $rxclass = join '.', $rxclass, 'HeterodyneReceiver';
        my $receivers = $taco->call_class_method($rxclass, 'get_all_receivers');
        my $field_list = $taco->get_class_attribute(
            'hedwig.facility.jcmt.calculator_heterodyne.ReceiverInfoID', '_fields');
        my %fields = map {$field_list->[$_] => $_} 0 .. $#$field_list;

        my %instruments;
        foreach my $info (
                [HARP => $taco->get_class_attribute($rxclass, 'HARP')],
                [ALAIHI => $taco->get_class_attribute($rxclass, 'ALAIHI')],
                [UU => $taco->get_class_attribute($rxclass, 'UU')],
                [AWEOWEO => $taco->get_class_attribute($rxclass, 'AWEOWEO')],
                [KUNTUR => $taco->get_class_attribute($rxclass, 'KUNTUR')],
                ) {
            my ($code, $id) = @$info;
            my $rx = $receivers->{$id};

            $instruments{$code} = {
                name => $rx->[$fields{'name'}],
                if_option => ($rx->[$fields{'t_rx_lo'}] ? 1 : 0),
            };
        }

        $result{'instruments'} = \%instruments;
    }

    return \%result;
}
