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

use strict;

use Test::More tests => 1
    + 4  # Class information methods.
    + 3; # Feedback comment object.

use OMP::Constants qw/:fb/;

use_ok('OMP::Info::Comment');

# Test class information methods.
is_deeply(OMP::Info::Comment->get_fb_status_options, [
    [2, 'Important'],
    [1, 'Info'],
    [3, 'Support'],
    [0, 'Hidden'],
]);

is(OMP::Info::Comment->statusText(OMP__FB_SUPPORT()), 'Support');

is_deeply(OMP::Info::Comment->get_fb_type_options, [
    [63, 'Comment'],
    [65, 'Data requested'],
    [79, 'First MSB of night accepted'],
    [66, 'MSB observed'],
    [74, 'MSB undone'],
    [75, 'MSB removed'],
    [80, 'MSB unremoved'],
    [76, 'MSB suspended'],
    [68, 'Password issued'],
    [78, 'Project enabled'],
    [77, 'Project disabled'],
    [81, 'Project altered'],
    [73, 'Program deleted'],
    [69, 'Program retrieved'],
    [70, 'Program submitted'],
    [71, 'Time adjusted'],
]);

is(OMP::Info::Comment->typeText(OMP__FB_MSG_COMMENT()), 'Comment');

# Test a feedback comment.
my $c = OMP::Info::Comment->new(
    status => OMP__FB_IMPORTANT(),
    type => OMP__FB_MSG_SP_DELETED());

isa_ok($c, 'OMP::Info::Comment');
is($c->statusText, 'Important');
is($c->typeText, 'Program deleted');
