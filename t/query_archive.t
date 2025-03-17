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
use Test::More tests => 8;

require_ok('OMP::Query::Archive');

my $q = OMP::Query::Archive->new(HASH => {
    instrument => 'SCUBA-2',
    date => {
        min => '2024-04-01',
        max => '2025-05-01',
    },
});
isa_ok($q, 'OMP::Query::Archive');

my @sql = $q->sql;
is(scalar @sql, 1);

is($sql[0],
    "SELECT *, J.date_obs AS 'date_obs', J.date_end AS 'date_end'"
    . " FROM jcmt.COMMON J JOIN jcmt.SCUBA2 S2 ON J.obsid = S2.obsid"
    . " WHERE ((J.date_obs >= '2024-04-01 00:00:00' AND J.date_obs <= '2025-04-30 23:59:59'))"
    . " AND ((( UPPER( J.instrume ) = UPPER( 'SCUBA-2' ) )))");

@sql = OMP::Query::Archive->new(HASH => {
    instrument => 'HARP',
    date => {
        min => '2024-04-01',
        max => '2025-05-01',
    },
})->sql;
is(scalar @sql, 1);
is($sql[0],
    "SELECT *, J.date_obs AS 'date_obs', J.date_end AS 'date_end'"
    . " FROM jcmt.COMMON J JOIN jcmt.ACSIS A ON J.obsid = A.obsid"
    . " WHERE ((J.date_obs >= '2024-04-01 00:00:00' AND J.date_obs <= '2025-04-30 23:59:59'))"
    . " AND ((( UPPER( J.instrume ) = UPPER( 'HARP' ) )))");

@sql = OMP::Query::Archive->new(HASH => {
    instrument => 'RxH3',
    date => {
        min => '2024-04-01',
        max => '2025-05-01',
    },
})->sql;
is(scalar @sql, 1);
is($sql[0],
    "SELECT *, J.date_obs AS 'date_obs', J.date_end AS 'date_end'"
    . " FROM jcmt.COMMON J JOIN jcmt.RXH3 H3 ON J.obsid = H3.obsid"
    . " WHERE ((J.date_obs >= '2024-04-01 00:00:00' AND J.date_obs <= '2025-04-30 23:59:59'))"
    . " AND ((( UPPER( J.instrume ) = UPPER( 'RXH3' ) )))");
