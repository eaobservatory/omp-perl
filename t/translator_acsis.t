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

use Test::More tests => 3;

require_ok('OMP::Translator::ACSIS');

my $translator = OMP::Translator::ACSIS->new;
isa_ok($translator, 'OMP::Translator::ACSIS');

is($translator->_safe_transition_name("30\x{03b1}-31\x{03b2}-32\x{03b3}-33\x{03b4}"),
    "30A-31B-32G-33D");
