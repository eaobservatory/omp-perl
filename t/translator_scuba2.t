#!perl

# Copyright (C) 2015 East Asian Observatory.
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
# this program; if not, write to the Free Software Foundation, Inc., 59 Temple
# Place,Suite 330, Boston, MA  02111-1307, USA

use strict;

use Test::More tests => 1 + (7 * 2);
use Test::Number::Delta;

require_ok('OMP::Translator::SCUBA2');

# Test "dynamic" pong scan parameters.
my ($dy, $vel);

($dy, $vel) = OMP::Translator::SCUBA2->_get_dyn_pong_parameters(7200.0);
is($dy, 360, 'PONG7200 dy');
is($vel, 600, 'PONG7200 vel');

($dy, $vel) = OMP::Translator::SCUBA2->_get_dyn_pong_parameters(3600.0);
is($dy, 180, 'PONG3600 dy');
is($vel, 600, 'PONG3600 vel');

($dy, $vel) = OMP::Translator::SCUBA2->_get_dyn_pong_parameters(1800.0);
is($dy, 60, 'PONG1800 dy');
is($vel, 400, 'PONG1800 vel');

($dy, $vel) = OMP::Translator::SCUBA2->_get_dyn_pong_parameters(900.0);
is($dy, 30, 'PONG900 dy');
is($vel, 280, 'PONG900 vel');

($dy, $vel) = OMP::Translator::SCUBA2->_get_dyn_pong_parameters(600.0);
is($dy, 30, 'PONG600 dy');
delta_ok($vel, 300.0, 'PONG600 vel');

($dy, $vel) = OMP::Translator::SCUBA2->_get_dyn_pong_parameters(300.0);
is($dy, 30, 'PONG300 dy');
delta_ok($vel, 150.0, 'PONG300 vel');

($dy, $vel) = OMP::Translator::SCUBA2->_get_dyn_pong_parameters(150.0);
is($dy, 30, 'PONG150 dy');
delta_ok($vel, 75.0, 'PONG150 vel');
