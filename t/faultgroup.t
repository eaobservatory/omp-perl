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

use Test::More tests => 10;

require_ok('OMP::Fault::Group');

my $grp = OMP::Fault::Group->new();
isa_ok($grp, 'OMP::Fault::Group');

# Try setting time lost and categores.
$grp->timelost(41);
$grp->timelostTechnical(16);
$grp->timelostNonTechnical(32);
is($grp->timelost, 41);
is($grp->timelostTechnical, 16);
is($grp->timelostNonTechnical, 32);

$grp->categories(qw/OMP DR/);
is_deeply([$grp->categories], [qw/OMP DR/]);

# Reset the object and check this information was cleared.
$grp->faults([]);

is($grp->timelost, 0);
is($grp->timelostTechnical, 0);
is($grp->timelostNonTechnical, 0);

is_deeply([$grp->categories], []);
