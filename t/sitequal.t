#!perl

# Test site quality routines

# Copyright (C) 2005 Particle Physics and Astronomy Research Council.
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

use Test::More tests => 31;

require_ok( 'OMP::SiteQuality' );

print "# Tau bands\n";

# first none
is(OMP::SiteQuality::determine_tauband(), 0, "Band 0");

# Now UKIRT
is(OMP::SiteQuality::determine_tauband(TELESCOPE => 'UKIRT'), 0,
   "Band 0 UKIRT");

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
  is(OMP::SiteQuality::determine_tauband(TELESCOPE => 'JCMT',
                                  TAU => $cso), $bands{$cso},
    "Verify band for tau $cso");
}

# Test out of range
eval { OMP::SiteQuality::determine_tauband(TELESCOPE=>'JCMT',TAU=> undef) };
ok($@,"Got error ok");
like($@, qr/not defined/,"not defined");

eval { OMP::SiteQuality::determine_tauband(TELESCOPE=>'JCMT',TAU=>-0.05) };
ok($@, "Got error okay");
like($@, qr/out of range/,"out of range");


eval { OMP::SiteQuality::determine_tauband(TELESCOPE=>'JCMT') };
ok($@,"Got error okay");
like($@, qr/without TAU/,"Without TAU");

# Band ranges
my $range = OMP::SiteQuality::get_tauband_range('JCMT', 2,3);
isa_ok($range, "OMP::Range","Make sure we get Range object Band 2,3");
is($range->max,0.12,"Upper bound");
is($range->min,0.05,"Lower bound");

$range = OMP::SiteQuality::get_tauband_range('JCMT',1);
isa_ok($range, "OMP::Range","Make sure we get Range object Band 1");
is($range->max,0.05,"Upper bound");
is($range->min,0.0,"Lower bound");

$range = OMP::SiteQuality::get_tauband_range( 'JCMT', 4,5,6);
isa_ok($range, "OMP::Range","Make sure we get range object Band 4,5,6");
is($range->max,undef,"Upper bound");
is($range->min,0.12, "Lower bound");

$range = OMP::SiteQuality::get_tauband_range( 'JCMT', 1,2,3);
isa_ok($range, "OMP::Range","Make sure we get range object Band 1,2,3");
is($range->max,0.12, "Upper bound");
is($range->min,0.0, "Lower bound");
