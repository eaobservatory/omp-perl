# Copyright (C) 2015 East Asian Observatory.
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

use Test::More tests => 5;

use JAC::Setup qw/hdrtrans/;

use_ok('OMP::DB::MSB');

my @input = (
    {x => 0.2, y => 4},
    {x => 0.5, y => 6},
    {x => 0.1, y => 5},
    {x => 0.3, y => 3},
    {x => 0.1, y => 2},
    {x => 0.4, y => 6},
    {x => 0.2, y => 8},
    {x => 0.6, y => 3},
    {x => 0.8, y => 4},
);

my @test = @input;
OMP::DB::MSB::stable_fuzzy_sort(sub {$_[0]->{'x'}}, 0, \@test);
my @expected = (
    {x => 0.1, y => 5},
    {x => 0.1, y => 2},
    {x => 0.2, y => 4},
    {x => 0.2, y => 8},
    {x => 0.3, y => 3},
    {x => 0.4, y => 6},
    {x => 0.5, y => 6},
    {x => 0.6, y => 3},
    {x => 0.8, y => 4},
);
is_deeply(\@test, \@expected, 'sort with no tolerance');

@test = @input;
OMP::DB::MSB::stable_fuzzy_sort(sub {$_[0]->{'x'}}, 0.1, \@test);
my @expected = (
    {x => 0.2, y => 4},
    {x => 0.1, y => 5},
    {x => 0.1, y => 2},
    {x => 0.3, y => 3},
    {x => 0.2, y => 8},
    {x => 0.5, y => 6},
    {x => 0.4, y => 6},
    {x => 0.6, y => 3},
    {x => 0.8, y => 4},
);
is_deeply(\@test, \@expected, 'sort with 0.1 tolerance');

@test = @input;
OMP::DB::MSB::stable_fuzzy_sort(sub {$_[0]->{'x'}}, 0.2, \@test);
my @expected = (
    {x => 0.2, y => 4},
    {x => 0.1, y => 5},
    {x => 0.1, y => 2},
    {x => 0.2, y => 8},
    {x => 0.5, y => 6},
    {x => 0.3, y => 3},
    {x => 0.4, y => 6},
    {x => 0.6, y => 3},
    {x => 0.8, y => 4},
);
is_deeply(\@test, \@expected, 'sort with 0.2 tolerance');

do {
    use sort 'stable';
    @test = sort {$a->{'y'} <=> $b->{'y'}} @input;
};
OMP::DB::MSB::stable_fuzzy_sort(sub {$_[0]->{'x'}}, 0.1, \@test);
my @expected = (
    {x => 0.1, y => 2},
    {x => 0.1, y => 5},
    {x => 0.3, y => 3},
    {x => 0.2, y => 4},
    {x => 0.2, y => 8},
    {x => 0.4, y => 6},
    {x => 0.6, y => 3},
    {x => 0.5, y => 6},
    {x => 0.8, y => 4},
);
is_deeply(\@test, \@expected, 'sort with y presort');
