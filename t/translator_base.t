#!perl

# Copyright (C) 2026 East Asian Observatory
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

use Test::More tests => 2
    + 3; # Configuration key suffixes

require_ok('OMP::Translator::Base');

my $trans= OMP::Translator::Base->new;
isa_ok($trans, 'OMP::Translator::Base');

# Test handling of configuration key suffixes.
is_deeply([$trans->config_suffixes], []);

$trans->config_suffixes(qw/aaa bbb/);
$trans->config_suffixes(qw/ccc ccc/);

is_deeply([$trans->config_suffixes], [qw/aaa bbb ccc/]);

$trans->config_suffixes(qw/bbb ddd/);

is_deeply([$trans->config_suffixes], [qw/aaa bbb ccc ddd/]);
