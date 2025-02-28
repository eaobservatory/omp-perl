#!perl

# test OMP::Project::TimeAcct

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

use Test::More tests => 6;
use Time::Piece qw/:override/;
require_ok('OMP::Project::TimeAcct');

# try a test object
my $acct = OMP::Project::TimeAcct->new(
    confirmed => 0,
    projectid => 'Blah',
    date => scalar(gmtime),
    timespent => 1800,
    telescope => 'JCMT',
);

isa_ok($acct, 'OMP::Project::TimeAcct');
is($acct->telescope, 'JCMT', 'retrieve telescope from object');

$acct->incTime(1800);
is($acct->timespent->seconds, 3600, 'test incTime with number');

$acct->incTime(Time::Seconds->new(1800));
is($acct->timespent->seconds, 5400, 'test incTime with Time::Seconds');

$acct->incTime(OMP::Project::TimeAcct->new(timespent => 1800));
is($acct->timespent->seconds, 7200, 'test incTime with OMP::Project::TimeAcct');
