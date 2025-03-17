#!perl

# Copyright (C) 2020 East Asian Observatory
# All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation; either version 2 of the License, or (at your option) any later
# version.
#
# This program is distributed in the hope that it will be useful,but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
# PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, write to the Free Software Foundation, Inc.,51 Franklin
# Street, Fifth Floor, Boston, MA  02110-1301, USA

use Test::More tests => 5;

use JAC::Setup qw/hdrtrans/;

require_ok('OMP::SpServer');

my $result = OMP::SpServer->getOTVersionInfo();
is((ref $result), 'ARRAY', 'getOTVersionInfo result is an array');

my ($cur, $min) = @$result;
like($cur, qr/^\d{8}$/, 'current matches YYYYMMDD');
like($min, qr/^\d{8}$/, 'minimum matches YYYYMMDD');
ok($min le $cur, 'minimum <= current')
