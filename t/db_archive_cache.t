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
use Test::More tests => 13;

use JAC::Setup qw/hdrtrans/;

require_ok('OMP::Query::Archive');
require_ok('OMP::DB::Archive::Cache');

my $cache = OMP::DB::Archive::Cache->new;
isa_ok($cache, 'OMP::DB::Archive::Cache');

$cache->_cache_dir('test');
is($cache->_cache_dir, 'test');

my $query = OMP::Query::Archive->new(HASH => {
    telescope => 'JCMT',
    date => {
        min => '2024-04-01',
        max => '2025-05-01',
    },
});

ok($cache->simple_query($query), 'Query is simple');
is($cache->_filename_from_query($query),
    'test/2024-04-01T00:00:002025-04-30T23:59:58JCMT');

$query = OMP::Query::Archive->new(HASH => {
    telescope => 'JCMT',
    instrument => 'UU',
    date => {
        min => '2024-04-01',
        max => '2025-05-01',
    },
});

ok($cache->simple_query($query), 'Query is simple');
is($cache->_filename_from_query($query),
    'test/2024-04-01T00:00:002025-04-30T23:59:58JCMTUU');

$query = OMP::Query::Archive->new(HASH => {
    telescope => 'JCMT',
    projectid => 'M25XX000',
    date => {
        min => '2024-04-01',
        max => '2025-05-01',
    },
});

ok($cache->simple_query($query), 'Query is simple');
is($cache->_filename_from_query($query),
    'test/2024-04-01T00:00:002025-04-30T23:59:58JCMTM25XX000');

$query = OMP::Query::Archive->new(HASH => {
    telescope => 'JCMT',
    projectid => ['M25XX000', 'M25XXX999'],
    date => {
        min => '2024-04-01',
        max => '2025-05-01',
    },
});

ok(! $cache->simple_query($query), 'Query is not simple');

$query = OMP::Query::Archive->new(HASH => {
    telescope => 'JCMT',
    instrument => ['UU', 'AWEOWEO'],
    date => {
        min => '2024-04-01',
        max => '2025-05-01',
    },
});

ok(! $cache->simple_query($query), 'Query is not simple');

$query = OMP::Query::Archive->new(HASH => {
    telescope => 'JCMT',
    runnr => 44,
    date => {
        min => '2024-04-01',
        max => '2025-05-01',
    },
});

ok(! $cache->simple_query($query), 'Query is not simple');
