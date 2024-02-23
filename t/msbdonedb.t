#!perl

use strict;
use Test::More tests => 1 + 4 + 5 * 4;

use OMP::MSBDoneDB;

my $db = OMP::MSBDoneDB->new();

isa_ok($db, 'OMP::MSBDoneDB');

my $wb;
my %opt = (format => 1, ndp => 0);

$wb = $db->_construct_waveband_objects('HARP', '3.545054759E11');
is(scalar @$wb, 1);
isa_ok($wb->[0], 'Astro::WaveBand');
is($wb->[0]->instrument, 'HARP');
is($wb->[0]->natural_unit, undef);
is($wb->[0]->frequency(\%opt), '355 GHz');

$wb = $db->_construct_waveband_objects('HARP/RXA3', '3.545054759E11/2.6588618E11');
is(scalar @$wb, 2);
isa_ok($wb->[0], 'Astro::WaveBand');
is($wb->[0]->instrument, undef);
is($wb->[0]->natural_unit, 'frequency');
is($wb->[0]->frequency(\%opt), '355 GHz');
isa_ok($wb->[1], 'Astro::WaveBand');
is($wb->[1]->instrument, undef);
is($wb->[1]->natural_unit, 'frequency');
is($wb->[1]->frequency(\%opt), '266 GHz');

$wb = $db->_construct_waveband_objects('SCUBA-2', '850');
is(scalar @$wb, 1);
isa_ok($wb->[0], 'Astro::WaveBand');
is($wb->[0]->instrument, 'SCUBA-2');
is($wb->[0]->natural_unit, undef);
is($wb->[0]->filter(\%opt), '850');

$wb = $db->_construct_waveband_objects('Michelle', '12.7356');
is(scalar @$wb, 1);
isa_ok($wb->[0], 'Astro::WaveBand');
is($wb->[0]->instrument, 'MICHELLE');
is($wb->[0]->natural_unit, undef);
is($wb->[0]->natural(\%opt), '13 mu');
