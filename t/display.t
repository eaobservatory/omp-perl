#!perl

# Copyright (C) 2024 East Asian Observatory
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

use Test::More tests => 3;
use strict;
require_ok('OMP::Display');

is(OMP::Display->remove_cr("alpha\r\nbeta\r\ngamma"), "alpha\nbeta\ngamma");

# Test that our formatter subclass (OMP::HTMLFormatText) generates the intended
# 8-character horizontal rule.
is(OMP::Display->html2plain('<p>alpha</p><hr><p>beta</p>'),
    "alpha\n\n--------\n\nbeta\n");
