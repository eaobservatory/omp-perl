#!perl

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

use Test::More tests => 29;

use JAC::Setup qw/hdrtrans/;

use_ok('OMP::Info::Obs');

# Test a single-subsystem observation.
my $obs = OMP::Info::Obs->new(
    hdrhash => {
        'BACKEND' => 'ACSIS',
        'DATE-END' => '2024-01-30T05:29:54',
        'DATE-OBS' => '2024-01-30T05:26:32',
        'FILE_ID' => [
            'a20240130_00020_01_0001.sdf'
        ],
        'INSTRUME' => 'HARP',
        'MAX_SUBSCAN' => 1,
        'MOLECULE' => 'CO',
        'MSBID' => 'CAL',
        'MSBTID' => undef,
        'NSUBBAND' => 1,
        'OBJECT' => 'CRL618',
        'OBSEND' => 1,
        'OBSID' => 'acsis_00020_20240130T052632',
        'OBSID_SUBSYSNR' => 'acsis_00020_20240130T052632_1',
        'OBSNUM' => 20,
        'OBS_SB' => 'LSB',
        'OBS_TYPE' => 'pointing',
        'OPER_LOC' => 'REMOTE',
        'OPER_SFT' => 'NIGHT',
        'PROJECT' => 'JCMTCAL',
        'RECIPE' => 'REDUCE_POINTING',
        'RESTFREQ' => '345.7959899',
        'SUBBANDS' => '1000MHzx2048',
        'SUBHEADERS' => [
            {}
        ],
        'TELESCOP' => 'JCMT',
        'TRANSITI' => '3 - 2',
    });

isa_ok($obs, 'OMP::Info::Obs');
isa_ok($obs->waveband, 'Astro::WaveBand');
is($obs->waveband->species, 'CO');
is($obs->obsid, 'acsis_00020_20240130T052632');
is_deeply([$obs->obsidss], ['acsis_00020_20240130T052632_1']);

my $subsystems = $obs->subsystems_tiny();
is(ref $subsystems, 'ARRAY');
is(scalar @$subsystems, 1);

my $subsys = $subsystems->[0];
isa_ok($subsys, 'OMP::Info::Obs');
isa_ok($subsys->waveband, 'Astro::WaveBand');
is($subsys->waveband->species, 'CO');
is($subsys->obsid, 'acsis_00020_20240130T052632');
is_deeply([$subsys->obsidss], ['acsis_00020_20240130T052632_1']);

# A dual-subsystem observation.
$obs = OMP::Info::Obs->new(
    hdrhash => {
        'BACKEND' => 'ACSIS',
        'DATE-END' => '2025-03-09T06:24:11',
        'DATE-OBS' => '2025-03-09T06:21:00',
        'INSTRUME' => 'UU',
        'MAX_SUBSCAN' => 1,
        'MSBID' => 'CAL',
        'MSBTID' => undef,
        'NSUBBAND' => 1,
        'OBJECT' => 'CIT6',
        'OBSEND' => 1,
        'OBSID' => 'acsis_00013_20250309T062100',
        'OBSNUM' => 13,
        'OBS_TYPE' => 'pointing',
        'OPER_LOC' => 'REMOTE',
        'OPER_SFT' => 'NIGHT',
        'PROJECT' => 'JCMTCAL',
        'RECIPE' => 'REDUCE_POINTING',
        'SUBBANDS' => '1000MHzx2048',
        'SUBHEADERS' => [
          {
            'FILE_ID' => [
              'a20250309_00013_01_0001.sdf'
            ],
            'MOLECULE' => 'CO',
            'OBSID_SUBSYSNR' => 'acsis_00013_20250309T062100_1',
            'OBS_SB' => 'LSB',
            'RESTFREQ' => '230.538',
            'SPECID' => 1,
            'SUBSYSNR' => 1,
            'TRANSITI' => '2 - 1'
          },
          {
            'FILE_ID' => [
              'a20250309_00013_02_0001.sdf'
            ],
            'MOLECULE' => 'No Line',
            'OBSID_SUBSYSNR' => 'acsis_00013_20250309T062100_2',
            'OBS_SB' => 'USB',
            'RESTFREQ' => '240.538',
            'SPECID' => 2,
            'SUBSYSNR' => 2,
            'TRANSITI' => 'No Line'
          }
        ],
        'TELESCOP' => 'JCMT',
    });

isa_ok($obs, 'OMP::Info::Obs');
isa_ok($obs->waveband, 'Astro::WaveBand');
is($obs->obsid, 'acsis_00013_20250309T062100');
is_deeply([$obs->obsidss], ['acsis_00013_20250309T062100_1', 'acsis_00013_20250309T062100_2']);

$subsystems = $obs->subsystems_tiny();
is(ref $subsystems, 'ARRAY');
is(scalar @$subsystems, 2);

$subsys = $subsystems->[0];
isa_ok($subsys, 'OMP::Info::Obs');
isa_ok($subsys->waveband, 'Astro::WaveBand');
is($subsys->waveband->species, 'CO');
is($subsys->obsid, 'acsis_00013_20250309T062100');
is_deeply([$subsys->obsidss], ['acsis_00013_20250309T062100_1']);

$subsys = $subsystems->[1];
isa_ok($subsys, 'OMP::Info::Obs');
isa_ok($subsys->waveband, 'Astro::WaveBand');
is($subsys->waveband->species, 'No Line');
is($subsys->obsid, 'acsis_00013_20250309T062100');
is_deeply([$subsys->obsidss], ['acsis_00013_20250309T062100_2']);
