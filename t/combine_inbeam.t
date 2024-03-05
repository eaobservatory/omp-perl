use strict;

use Test::More tests => 14;

use JAC::Setup qw/jsa dataverify/;
use OMP::EnterData;

my $dict = './cfg/jcmt/data.dictionary';

my $enter = OMP::EnterData->new(dict => $dict);

isa_ok($enter, 'OMP::EnterData');

is($enter->_combine_inbeam_values(
    'shutter',
    '',
    ''),
undef,
'shutter first only');

is($enter->_combine_inbeam_values(
    'shutter',
    undef),
undef,
'shutter and undef');

is($enter->_combine_inbeam_values(
    undef,
    undef),
undef,
'all undef');

is($enter->_combine_inbeam_values(
    undef,
    'pol',
    undef,
    undef,
    undef),
'pol',
'pol and undef');

is($enter->_combine_inbeam_values(
    'shutter',
    'shutter',
    'shutter'),
'shutter',
'shutter in all');

is($enter->_combine_inbeam_values(
    'shutter',
    'pol',
    'pol'),
'pol',
'shutter first then pol');

is($enter->_combine_inbeam_values(
    'shutter pol',
    'pol',
    'pol'),
'pol',
'shutter first, pol in all');

is($enter->_combine_inbeam_values(
    'shutter pol',
    '',
    ''),
undef,
'shutter and pol in first only');

is($enter->_combine_inbeam_values(
    'shutter',
    'pol',
    'fts2'),
'fts2 pol',
'shutter in first, then pol/fts2');

is($enter->_combine_inbeam_values(
    'shutter a b c',
    'd f h',
    'e g i'),
'd e f g h i',
'shutter in first, then multiple');

is($enter->_combine_inbeam_values(
    'shutter a b c',
    'shutter d f h',
    'shutter e g i'),
'a b c d e f g h i shutter',
'shutter in all with multiple');

is($enter->_combine_inbeam_values(
    'a b c',
    'd f h',
    'e g i'),
'a b c d e f g h i',
'no shutter, multiple values');

is($enter->_combine_inbeam_values(
    'fts2',
    'fts2',
    'fts2'),
'fts2',
'no shutter, fts2 in all');
