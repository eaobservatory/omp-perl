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
use Test::More tests => 15;

use Time::Piece qw/ :override /;
use Time::Seconds;

require_ok('OMP::DateSun');

print "# Extended time\n";

my ($projtime,$extend) = OMP::DateSun->determine_extended( 
							  tel => 'JCMT',
							  start => '2002-12-10T03:20',
							  duration => 1800,
							  freetimeut => ['03:30','19:30'],
							 );
is($projtime->seconds, 1200, "Check project time");
is($extend->seconds, 600, "Check extended time");

($projtime,$extend) = OMP::DateSun->determine_extended( 
							  tel => 'JCMT',
							  start => '2002-12-10T02:20',
							  duration => 1800,
							  freetimeut => ['03:30','19:30'],
							 );
is($projtime->seconds, 0, "Check project time");
is($extend->seconds, 1800, "Check extended time");

($projtime,$extend) = OMP::DateSun->determine_extended( 
							  tel => 'JCMT',
							  start => '2002-12-10T05:20',
							  duration => 1800,
							  freetimeut => ['03:30','19:30'],
							 );
is($projtime->seconds, 1800, "Check project time");
is($extend->seconds, 0, "Check extended time");

($projtime,$extend) = OMP::DateSun->determine_extended( 
							  tel => 'JCMT',
							  start => '2002-12-10T19:20',
							  duration => 1800,
							  freetimeut => ['03:30','19:30'],
							 );
is($projtime->seconds, 600, "Check project time");
is($extend->seconds, 1200, "Check extended time");

($projtime,$extend) = OMP::DateSun->determine_extended( 
							  tel => 'JCMT',
							  start => '2002-12-10T20:20',
							  duration => 1800,
							  freetimeut => ['03:30','19:30'],
							 );
is($projtime->seconds, 0, "Check project time");
is($extend->seconds, 1800, "Check extended time");

# Now test the alternative options
($projtime,$extend) = OMP::DateSun->determine_extended( 
							  tel => 'JCMT',
							  start => '2002-12-10T03:20',
							  end => '2002-12-10T03:50',
							  freetimeut => ['03:30','19:30'],
							 );
is($projtime->seconds, 1200, "Check project time");
is($extend->seconds, 600, "Check extended time");

($projtime,$extend) = OMP::DateSun->determine_extended( 
							  tel => 'JCMT',
							  end => '2002-12-10T03:50',
							  duration => 1800,
							  freetimeut => ['03:30','19:30'],
							 );
is($projtime->seconds, 1200, "Check project time");
is($extend->seconds, 600, "Check extended time");

