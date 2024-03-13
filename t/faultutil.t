#!perl

# Copyright (C) 2022 East Asian Observatory
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

use Test::More tests => 13;
use strict;
require_ok('OMP::User');
require_ok('OMP::DateTools');
require_ok('OMP::Fault');
require_ok('OMP::FaultUtil');
require_ok('OMP::Fault::Response');

my $author = OMP::User->new(
    userid => 'TEST',
    name => 'Test User',
);

my $resp = OMP::Fault::Response->new(
    author => $author,
    text => 'This is a test of OMP::FaultUtil',
);

my %details = (
    category => 'JCMT',
    fault => $resp,
    subject => 'Subject',
    faultdate => OMP::DateTools->parse_date('2022-04-01T10:30'),
    timelost => 2.0,
    system => OMP::Fault->faultSystems('JCMT')->{'Back End - ACSIS'},
    type => OMP::Fault->faultTypes('JCMT')->{'Hardware'},
    status => {OMP::Fault->faultStatus()}->{'Open'},
    shifttype => 'OTHER',
    remote => 1,
);

my $fault = OMP::Fault->new(
    %details,
);

isa_ok($fault, 'OMP::Fault');

my $fault2 = OMP::Fault->new(
    %details,
    subject => 'Another fault',
);

isa_ok($fault2, 'OMP::Fault');

is_deeply([OMP::FaultUtil->compare($fault, $fault2)], ['subject']);

my $fault3 = OMP::Fault->new(
    %details,
    shifttype => 'EO',
);

isa_ok($fault3, 'OMP::Fault');

is_deeply([OMP::FaultUtil->compare($fault, $fault3)], ['shifttype']);

my $fault4 = OMP::Fault->new(
    %details,
    type => OMP::Fault->faultTypes('JCMT')->{'Software'},
    status => {OMP::Fault->faultStatus()}->{'Closed'},
);

isa_ok($fault4, 'OMP::Fault');

is_deeply([OMP::FaultUtil->compare($fault, $fault4)], ['type', 'status']);

my $resp2 = OMP::Fault::Response->new(
    author => $author,
    text => '<pre>Preformatted text</pre>',
    preformatted => 1);

is_deeply([OMP::FaultUtil->compare($resp, $resp2)], ['text', 'preformatted']);
