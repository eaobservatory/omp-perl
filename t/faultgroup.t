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

use Test::More tests => 22 + 20;

require_ok('OMP::General');
require_ok('OMP::User');
require_ok('OMP::Fault');
require_ok('OMP::Fault::Response');
require_ok('OMP::Fault::Group');

my $grp = OMP::Fault::Group->new();
isa_ok($grp, 'OMP::Fault::Group');

is($grp->numfaults, 0);
is($grp->getFault('20250101.001'), undef);

# Try setting time lost and categores.
$grp->timelost(41);
$grp->timelostTechnical(16);
$grp->timelostNonTechnical(32);
is($grp->timelost, 41);
is($grp->timelostTechnical, 16);
is($grp->timelostNonTechnical, 32);
isa_ok($grp->timelost, 'Time::Seconds');
isa_ok($grp->timelostTechnical, 'Time::Seconds');
isa_ok($grp->timelostNonTechnical, 'Time::Seconds');

$grp->categories(qw/OMP DR/);
is_deeply([$grp->categories], [qw/OMP DR/]);

# Reset the object and check this information was cleared.
$grp->faults([]);

is($grp->timelost, 0);
is($grp->timelostTechnical, 0);
is($grp->timelostNonTechnical, 0);
isa_ok($grp->timelost, 'Time::Seconds');
isa_ok($grp->timelostTechnical, 'Time::Seconds');
isa_ok($grp->timelostNonTechnical, 'Time::Seconds');

is_deeply([$grp->categories], []);

# Test grouping functions.
$grp->faults([
    dummy_fault('20250101.001', '2025-01-01', 'OTHER'),
    dummy_fault('20250101.002', '2025-01-01', 'DAY'),
    dummy_fault('20250102.001', '2025-01-02', 'DAY'),
    dummy_fault('20250102.002', '2025-01-02'),
]);

is($grp->numfaults, 4);

my $by_shift = $grp->by_shift;
is(ref $by_shift, 'HASH');
is_deeply([sort keys %$by_shift], [qw/DAY OTHER UNKNOWN/]);
foreach my $test (
        ['DAY', 2, [qw/20250101.002 20250102.001/]],
        ['OTHER', 1, [qw/20250101.001/]],
        ['UNKNOWN', 1, [qw/20250102.002/]]) {
    my ($shift, $num, $ids) = @$test;
    my $subgrp = $by_shift->{$shift};
    isa_ok($subgrp, 'OMP::Fault::Group');
    is($subgrp->numfaults, $num);
    is_deeply([map {$_->id} $subgrp->faults], $ids);
}

my $by_date = $grp->by_date;
is(ref $by_date, 'HASH');
is_deeply([sort keys %$by_date], [qw/2025-01-01 2025-01-02/]);
foreach my $test (
        ['2025-01-01', 2, [qw/20250101.001 20250101.002/]],
        ['2025-01-02', 2, [qw/20250102.001 20250102.002/]]) {
    my ($date, $num, $ids) = @$test;
    my $subgrp = $by_date->{$date};
    isa_ok($subgrp, 'OMP::Fault::Group');
    is($subgrp->numfaults, $num);
    is_deeply([map {$_->id} $subgrp->faults], $ids);
}

# Function to generate OMP::Fault objects which we can use to test
# the OMP::Fault::Group class.
my $dummy_author = undef;
sub dummy_fault {
    my ($id, $date, $shift) = @_;
    unless (defined $dummy_author) {
        $dummy_author = OMP::User->new(
            userid => 'XYZ',
            name => 'Zee Xy');
    }
    return OMP::Fault->new(
        id => $id,
        category => 'OMP',
        fault => OMP::Fault::Response->new(
            author => $dummy_author,
            text => 'text',
            date => OMP::DateTools->parse_date($date)),
        shifttype => $shift,
    );
}
