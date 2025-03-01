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
use Test::More tests => 5;

require_ok('OMP::Query::TimeAcct');
require_ok('OMP::DB::TimeAcct');
require_ok('OMP::DB::Project');

my @tables = (
    $OMP::DB::TimeAcct::ACCTTABLE,
    $OMP::DB::Project::PROJTABLE,
);

my $q = OMP::Query::TimeAcct->new(HASH => {
     date => {
        'value' => '2025-01-01',
        'delta' => 0,
    },
    EXPR__TEL => {or => {
        telescope => 'JCMT',
        projectid => {like => 'JCMT%'},
    }},
});
isa_ok($q, 'OMP::Query::TimeAcct');

my $sql = $q->sql(@tables);

is($sql, "SELECT A.*, P.telescope"
    . " FROM omptimeacct AS A LEFT OUTER JOIN ompproj AS P ON (A.projectid = P.projectid)"
    . " WHERE ((A.projectid like 'JCMT%') OR ((telescope = 'JCMT')))"
    . " AND date >= '2025-01-01 00:00:00' AND date <= '2025-01-01 00:00:00' ");
