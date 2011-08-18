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
use Test::More tests => 107;

use Time::Piece qw/ :override /;
use Time::Seconds;

require_ok('OMP::General');

print "# Verification\n";

# At least test that we fail to match the admin password
# (after always matching for some time!)
#ok( ! OMP::General->verify_administrator_password( "blah", 1 ),
#  "Check that we fail to verify the admin password");

print "# Project ID\n";

my @input = (
	     {
	      semester => "01b",
	      projectid => "03",
	      result => "u/01b/3",
	     },
	     {
	      projectid => "u04",
	      semester => "02a",
	      result => "m02au04",
	     },
	     {
	      projectid => "h01",
	      semester => "02a",
	      telescope => "jcmt",
	      result => "m02ah01",
	     },
	     {
	      projectid => "h01",
	      semester => "02a",
	      telescope => "ukirt",
	      result => "u/02a/h1",
	     },
	     {
	      projectid => "H1",
	      semester => "02a",
	      telescope => "ukirt",
	      result => "u/02a/H1",
	     },
	     {
	      projectid => "j28",
	      semester => "02a",
	      telescope => "ukirt",
	      result => "u/02a/j28",
	     },
	     {
	      projectid => "j4",
	      semester => "02a",
	      telescope => "ukirt",
	      result => "u/02a/j4",
	     },
	     {
	      projectid => "j04",
	      semester => "03b",
	      telescope => "ukirt",
	      result => "u/03b/j4",
	     },
	     {
	      projectid => "22",
	      semester => "99a",
	      result => "u/99a/22",
	     },
	     {
	      projectid => "m01bu52",
	      result => "m01bu52",
	     },
	     {
	      projectid => "u/01b/52",
	      result => "u/01b/52",
	     },
	     {
	      projectid => "u/serv/52",
	      result => "u/serv/52",
	     },
	     {
	      projectid => "s1",
	      result => "u/serv/1",
	     },
	     {
	      projectid => "s04",
	      result => "u/serv/4",
	     },
	     {
	      projectid => "s4565",
	      result => "u/serv/4565",
	     },
	     {
	      projectid => "thk1",
	      result => "thk01",
	     },
	     {
	      projectid => "tj125",
	      result => "tj125",
	     },
	     {
	      projectid => "UKIRTCAL",
	      result => "UKIRTCAL",
	     },
	     {
	      # Special project for email use
	      projectid => 'U/UKIDSS/0',
	      result => 'U/UKIDSS/0',
	     },
	     {
	      # MEGA survey
	      projectid => "SX_30EW_LO",
	      result => "SX_30EW_LO",
	     },
	     {
	      # MEGA survey
	      projectid => "LX_30EW_LO",
	      result => "LX_30EW_LO",
	     },
	     # JCMT service
	     {
	      projectid => "s01bc03",
	      result => "s01bc03",
	     },
	     {
	      projectid => 'nls0003',
	      result    => 'nls0003',
	     },
	     {
	      projectid => "s02au03",
	      result => "s02au03",
	     },
	     {
	      projectid => "s02ai03",
	      result => "s02ai03",
	     },
	     {
	      projectid => "si03",
	      semester => '02a',
	      result => "s02ai03",
	     },
	     {
	      projectid => "sc22",
	      semester => '00b',
	      result => "s00bc22",
	     },
	     {
	      projectid => "su15",
	      semester => '02b',
	      result => "s02bu15",
	     },

	     # JCMT calibrations
	     {
	      projectid => "MEGACAL",
	      result => "MEGACAL",
	     },
	     {
	      projectid => "JCMTCAL",
	      result => "JCMTCAL",
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
	      result=>'m04bu35a',
	     }
	    );

for my $input (@input) {
  is( OMP::General->infer_projectid(%$input), $input->{result},
    "Verify projectid is '" . $input->{result} . "' from '".
    $input->{projectid} ."'");
}

# Test the failure when we cant decide which telescope
eval {
  OMP::General->infer_projectid( projectid => "h01"  );
};
like( $@, qr/Unable to determine telescope from supplied project ID/,
    "Verify ambiguity");


# Band allocations
print "# Band determination\n";

# first none
is(OMP::General->determine_band, 0, "Band 0");

# Now UKIRT
is(OMP::General->determine_band(TELESCOPE => 'UKIRT'), 0, "Band 0 UKIRT");

# And JCMT
my %bands = (
	     0.03 => 1,
	     0.05 => 1,
	     0.07 => 2,
	     0.08 => 2,
	     0.1  => 3,
	     0.12 => 3,
	     0.15 => 4,
	     0.2  => 4,
	     0.25 => 5,
	     0.4  => 6,
	    );

for my $cso (keys %bands) {
  is(OMP::General->determine_band(TELESCOPE => 'JCMT',
				  TAU => $cso), $bands{$cso},
    "Verify band for tau $cso");
}

# Test out of range
eval { OMP::General->determine_band(TELESCOPE=>'JCMT',TAU=> undef) };
ok($@,"Got error ok");
like($@, qr/not defined/,"not defined");

eval { OMP::General->determine_band(TELESCOPE=>'JCMT',TAU=>-0.05) };
ok($@, "Got error okay");
like($@, qr/out of range/,"out of range");


eval { OMP::General->determine_band(TELESCOPE=>'JCMT') };
ok($@,"Got error okay");
like($@, qr/without TAU/,"Without TAU");

# Band ranges
my $range = OMP::General->get_band_range('JCMT', 2,3);
isa_ok($range, "OMP::Range","Make sure we get Range object Band 2,3");
is($range->max,0.12,"Upper bound");
is($range->min,0.05,"Lower bound");

$range = OMP::General->get_band_range('JCMT',1);
isa_ok($range, "OMP::Range","Make sure we get Range object Band 1");
is($range->max,0.05,"Upper bound");
is($range->min,0.0,"Lower bound");

$range = OMP::General->get_band_range( 'JCMT', 4,5,6);
isa_ok($range, "OMP::Range","Make sure we get range object Band 4,5,6");
is($range->max,undef,"Upper bound");
is($range->min,0.12, "Lower bound");

$range = OMP::General->get_band_range( 'JCMT', 1,2,3);
isa_ok($range, "OMP::Range","Make sure we get range object Band 1,2,3");
is($range->max,0.12, "Upper bound");
is($range->min,0.0, "Lower bound");



# Projectid extraction
my %extract = (
	       'u/SERV/192' => 'project u/SERV/192 is complete',
	       'u/02a/55'   => '[u/02a/55]',
	       'u/03b/h6a'  => '[u/03b/h6a]',
	       'u/02b/h55'  => 'MAIL: [u/02b/h55] is complete',
	       'U/03A/J4'   => 'a Japanese ukirt project U/03A/J4',
	       's02ac03'    => '[s02ac03]',
	       's02au03'    => '[s02au03]',
	       's02ai03'    => '[s02ai03]',
	       'm02au52'    => '[m02au52]',
	       'm02an52'    => '[m02an52]',
	       'm02ac52'    => '[m02ac52]',
	       'm02ai52'    => '[m02ai52]',
	       'm00bh52'    => '[m00bh52]',
	       'nls0010'    => '[nls0010]',
	       'LX_68EW_HI' => '[LX_68EW_HI]',
	       'SX_44EW_MD' => '[SX_44EW_MD] blah',
	       'MEGACAL'    => '[MEGACAL]',
	       'JCMTCAL'    => '[JCMTCAL]',
	       'ukirtcal'   => '[ukirtcal] blah di blah',
	       'tj03'       => 'hello tj03',
	       'thk125'     => 'this is [thk125]',
	       'm02bh37b1'  => 'this is uh project m02bh37b1',
	       'M02BH07A3'  => 'this is uh project M02BH07A3',
	       'M00AH06A'  => 'this is uh project M00AH06A',
               'm02bec03'  => 'this is E&C m02bec03 project',
	       'm08bgt01'  => 'm08bgt01 is a guaranteed time project',
               'm02bd01'   => 'm02bd01 is a DDT project',
               'u/02b/d03' => 'u/02b/d03 is a UKIRT DDT project',
	       'm03au05fb' => 'a fallback project: m03au05fb',
	       'u/ec/1'    => 'A UKIRT E&C project u/ec/1',
               'm03ad07a'  => 'A JCMT DDT project m03ad07a',
	       'm03bu135d' => 'A fallback project m03bu135d of a different type',
	       'u/ukidss/las15' => '[u/ukidss/las15] Survey time',
               'U/11B/H50C' => '[U/11B/H50C]',
	      );

for my $proj (keys %extract) {
  my $output = OMP::General->extract_projectid($extract{$proj});
  is($output, $proj, "Extract $proj from string");
}

# some failures
my @fail = (qw/ [su03] [sc04] [s06] /);
for my $string (@fail) {
  is(OMP::General->extract_projectid($string), undef, "Test failure of project extraction");
}

print "# String splitting\n";
my $sstring = 'foo bar baz';
is(OMP::General->split_string($sstring), 3, 'Split simple string');

$sstring = 'foo bar "baz xyz" xyzzy';
is(OMP::General->split_string($sstring), 4, 'Split complicated string');

my @compare_string = ('baz xyz',
		      'xyz zyx',
		      'foo',
                      'bar',
                      'corgy',
		      '"',
		      'waldo',);

$sstring = 'foo bar "baz xyz" corgy "xyz zyx" " waldo';

is_deeply([OMP::General->split_string($sstring)],
	  \@compare_string,
	  "Split string with odd number of double-quotes");


