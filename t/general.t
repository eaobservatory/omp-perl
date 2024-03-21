#!perl

# Test OMP::General

# Copyright (C) 2002-2005 Particle Physics and Astronomy Research Council.
# All Rights Reserved.

# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation; either version 2 of the License, or (at your option) any later
# version.

# This program is distributed in the hope that it will be useful,but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
# PARTICULAR PURPOSE. See the GNU General Public License for more details.

# You should have received a copy of the GNU General Public License along with
# this program; if not, write to the Free Software Foundation, Inc., 59 Temple
# Place,Suite 330, Boston, MA  02111-1307, USA

use strict;
use Test::More tests => 2
    + 19 # infer
    + 3
    + 10 # bands
    + 18
    + 35 # project extract
    + 3 # project extract fail
    + 1 # fault extract
    + 1 # fault extract fail
    + 9;

use Time::Piece qw/:override/;
use Time::Seconds;

require_ok('OMP::General');
require_ok('OMP::SiteQuality');

print "# Project ID\n";

my @input = (
    {
        projectid => 'u04',
        semester => '02a',
        result => 'm02au04',
    },
    {
        projectid => 'h01',
        semester => '02a',
        telescope => 'jcmt',
        result => 'm02ah01',
    },
    {
        projectid => 'm01bu52',
        result => 'm01bu52',
    },
    {
        projectid => 'thk1',
        result => 'thk01',
    },
    {
        projectid => 'tj125',
        result => 'tj125',
    },

    # JCMT service
    {
        projectid => 's01bc03',
        result => 's01bc03',
    },
    {
        projectid => 'nls0003',
        result => 'nls0003',
    },
    {
        projectid => 's02au03',
        result => 's02au03',
    },
    {
        projectid => 's02ai03',
        result => 's02ai03',
    },
    {
        projectid => 'si03',
        semester => '02a',
        result => 's02ai03',
    },
    {
        projectid => 'sc22',
        semester => '00b',
        result => 's00bc22',
    },
    {
        projectid => 'su15',
        semester => '02b',
        result => 's02bu15',
    },

    # JCMT calibrations
    {
        projectid => 'MEGACAL',
        result => 'MEGACAL',
    },
    {
        projectid => 'JCMTCAL',
        result => 'JCMTCAL',
    },
    {
        projectid => 'm02bh37a2',
        result => 'm02bh37a2',
    },
    {
        projectid => 'm03ad07b',
        result => 'm03ad07b',
    },
    {
        projectid => 'guaranteed time: m06bgt01 <<',
        result => 'm06bgt01',
    },
    {
        projectid => 'E&C: m06bec01 <<',
        result => 'm06bec01',
    },
    {
        projectid => 'm04bu35a',
        result => 'm04bu35a',
    }
);

for my $input (@input) {
    is(OMP::General->infer_projectid(%$input),
        $input->{result},
        "Verify projectid is '" . $input->{result} . "' from '" . $input->{projectid} . "'");
}

# Test the failure when we cant decide which telescope
eval {
    OMP::General->infer_projectid(projectid => 'h01');
};
like($@,
    qr/Unable to determine telescope from supplied project ID/,
    "Verify ambiguity"
);

# Band allocations
print "# Band determination\n";

# first none
is(OMP::SiteQuality::determine_tauband(), 0, 'Band 0');

# Now UKIRT
is(OMP::SiteQuality::determine_tauband(TELESCOPE => 'UKIRT'), 0, 'Band 0 UKIRT');

# And JCMT
my %bands = (
    0.03 => 1,
    0.05 => 1,
    0.07 => 2,
    0.08 => 2,
    0.1 => 3,
    0.12 => 3,
    0.15 => 4,
    0.2 => 4,
    0.25 => 5,
    0.4 => 6,
);

for my $cso (keys %bands) {
    is(OMP::SiteQuality::determine_tauband(
            TELESCOPE => 'JCMT',
            TAU => $cso
        ),
        $bands{$cso},
        "Verify band for tau $cso"
    );
}

# Test out of range
eval {
    OMP::SiteQuality::determine_tauband(TELESCOPE => 'JCMT', TAU => undef);
};
ok($@, 'Got error ok');
like($@, qr/not defined/, 'not defined');

eval {
    OMP::SiteQuality::determine_tauband(TELESCOPE => 'JCMT', TAU => -0.05);
};
ok($@, 'Got error okay');
like($@, qr/out of range/, 'out of range');


eval {
    OMP::SiteQuality::determine_tauband(TELESCOPE => 'JCMT');
};
ok($@, 'Got error okay');
like($@, qr/without TAU/, 'Without TAU');

# Band ranges
my $range = OMP::SiteQuality::get_tauband_range('JCMT', 2, 3);
isa_ok($range, 'OMP::Range', 'Make sure we get Range object Band 2,3');
is($range->max, 0.12, 'Upper bound');
is($range->min, 0.05, 'Lower bound');

$range = OMP::SiteQuality::get_tauband_range('JCMT', 1);
isa_ok($range, 'OMP::Range', 'Make sure we get Range object Band 1');
is($range->max, 0.05, 'Upper bound');
is($range->min, 0.0, 'Lower bound');

$range = OMP::SiteQuality::get_tauband_range('JCMT', 4, 5, 6);
isa_ok($range, 'OMP::Range', 'Make sure we get range object Band 4,5,6');
is($range->max, undef, 'Upper bound');
is($range->min, 0.12, 'Lower bound');

$range = OMP::SiteQuality::get_tauband_range('JCMT', 1, 2, 3);
isa_ok($range, 'OMP::Range', 'Make sure we get range object Band 1,2,3');
is($range->max, 0.12, 'Upper bound');
is($range->min, 0.0, 'Lower bound');

# Projectid extraction
my %extract = (
    's02ac03' => '[s02ac03]',
    's02au03' => '[s02au03]',
    's02ai03' => '[s02ai03]',
    'm02au52' => '[m02au52]',
    'm02an52' => '[m02an52]',
    'm02ac52' => '[m02ac52]',
    'm02ai52' => '[m02ai52]',
    'm00bh52' => '[m00bh52]',
    'nls0010' => '[nls0010]',
    'LX_68EW_HI' => '[LX_68EW_HI]',
    'SX_44EW_MD' => '[SX_44EW_MD] blah',
    'MEGACAL' => '[MEGACAL]',
    'JCMTCAL' => '[JCMTCAL]',
    'JCMTCALOLD' => '[JCMTCALOLD]',
    'tj03' => 'hello tj03',
    'thk125' => 'this is [thk125]',
    'm02bh37b1' => 'this is uh project m02bh37b1',
    'M02BH07A3' => 'this is uh project M02BH07A3',
    'M00AH06A' => 'this is uh project M00AH06A',
    'm02bec03' => 'this is E&C m02bec03 project',
    'm08bgt01' => 'm08bgt01 is a guaranteed time project',
    'm02bd01' => 'm02bd01 is a DDT project',
    'M15BT001' => 'University of Texas project M15BT001',
    'M16AP001' => 'EAO "PI Science" project M16AP001',
    'M16AL001' => 'EAO "Large Program" project M16AL001',
    'M16AV001' => 'EAO "VLBI" project M16AV001',
    'M16XP001' => 'EAO "extra" project M16XP001',
    'R19BP001' => 'EAO "rapid turnaround" project R19BP001',
    'E21AC001' => 'EAO Canadian supplemental call project E21AC001',
    'E21AK001' => 'EAO South Korean supplemental call project E21AK001',
    'E21AZ001' => 'EAO Chinese supplemental project E21AZ001',
    'M21BF001' => 'EAO I.F. queue project M21BF001',
    'm03au05fb' => 'a fallback project: m03au05fb',
    'm03ad07a' => 'A JCMT DDT project m03ad07a',
    'm03bu135d' => 'A fallback project m03bu135d of a different type',
);

for my $proj (keys %extract) {
    my $output = OMP::General->extract_projectid($extract{$proj});
    is($output, $proj, "Extract $proj from string");
}

# some failures
my @fail = (
    '[su03]',
    '[sc04]',
    '[s06]',
);
for my $string (@fail) {
    is(OMP::General->extract_projectid($string),
        undef,
        "Test failure of project extraction: $string");
}

%extract = (
    '20190401.042' => '[20190401.042] Telescope/Software - Something went wrong',
);

foreach my $faultid (keys %extract) {
    my $output = OMP::General->extract_faultid($extract{$faultid});
    is($output, $faultid, "Extract $faultid from string");
}

@fail = (
    'Re: 20190401.042 and the ...',
);

foreach my $string (@fail) {
    is(OMP::General->extract_faultid($string),
        undef,
        "Test failure of fault extraction: $string");
}

print "# String splitting\n";
my $sstring = 'foo bar baz';
is(OMP::General->split_string($sstring), 3, 'Split simple string');

$sstring = 'foo bar "baz xyz" xyzzy';
is(OMP::General->split_string($sstring), 4, 'Split complicated string');

my @compare_string = (
    'baz xyz',
    'xyz zyx',
    'foo',
    'bar',
    'corgy',
    '"',
    'waldo',
);

$sstring = 'foo bar "baz xyz" corgy "xyz zyx" " waldo';

is_deeply(
    [OMP::General->split_string($sstring)],
    \@compare_string,
    "Split string with odd number of double-quotes");

# ROT-13.
my $in = 'polka.dot';
my $in13 = 'cbyxn.qbg';
is((OMP::General->rot13($in))[0], $in13, 'rot13: string with dot');
is((OMP::General->rot13($in13))[0], $in, 'rot13 reverse: string with dot');

$in = 'a123Z';
$in13 = 'n123M';
is((OMP::General->rot13($in))[0], $in13, 'rto13: alphanum');
is((OMP::General->rot13($in13))[0], $in, 'rto13 reverse: alphanum');


print "# Numerical utilities\n";
is(OMP::General::nint(123.456), 123, 'nint(123.456)');

is(OMP::General::nearest_mult(129, 64), 128, 'nearest_mult(129, 64)');
