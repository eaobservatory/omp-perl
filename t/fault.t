#!perl

# Test OMP::Fault

# Copyright (C) 2002-2005 Particle Physics and Astronomy Research Council.
# Copyright (C) 2017 East Asian Observatory.
# All Rights Reserved.

# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation; either version 2 of the License, or (at your option) any later
# version.

# This program is distributed in the hope that it will be useful,but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
# PARTICULAR PURPOSE. See the GNU General Public License for more details.

# You should have received a copy of the GNU General Public License along with
# this program; if not, write to the Free Software Foundation, Inc., 59 Temple
# Place,Suite 330, Boston, MA  02111-1307, USA


use Test::More tests => 17 + 9 + 6;
use strict;
require_ok('OMP::User');
require_ok('OMP::Fault');
require_ok('OMP::Fault::Response');


# First create the first "response"
my $author = OMP::User->new(
    userid => 'AJA',
    name => 'Andy Adamson'
);
isa_ok($author, 'OMP::User');

my $resp = OMP::Fault::Response->new(
    author => $author,
    text => 'This is a test of the fault classes'
);
ok($resp, 'response object created');
isa_ok($resp, 'OMP::Fault::Response');

# Now file a fault
my $fault = OMP::Fault->new(
    category => 'UKIRT',
    fault => $resp,
);
ok($fault, 'Fault object created');
isa_ok($fault, 'OMP::Fault');

# Now respond
my $author2 = OMP::User->new(
    userid => 'TIMJ',
    name => 'Tim Jenness'
);
my $resp2 = OMP::Fault::Response->new(
    author => $author2,
    text => 'I respond to you'
);

$fault->responses($resp2);

my @resps = $fault->responses;
is(scalar(@resps), 2, 'Count responses');

# Check isfault flags
ok($resps[0]->isfault, 'check first is a fault');
ok(! $resps[1]->isfault, 'second response is not a fault');


# Print the stringified fault for info
# Need to prepend #
my $string = "$fault";
my @lines = split "\n", $string;
$string = join '', map {"#$_\n"} @lines;
print $string;

# Test safety fault locations.  By default we should now hide "JAC".
is_deeply({OMP::Fault->faultLocation_Safety(include_hidden => 1)}, {
    'In transit' => 4000,
    JAC => 4001,
    HP => 4002,
    JCMT => 4003,
    UKIRT => 4004,
    EAO => 4005,
});

is_deeply({OMP::Fault->faultLocation_Safety()}, {
    'In transit' => 4000,
    HP => 4002,
    JCMT => 4003,
    UKIRT => 4004,
    EAO => 4005,
});

# Test fault systems.
is_deeply(OMP::Fault->faultSystems('JCMT', include_hidden => 1), {
    Telescope => 1016,
    'Back End - DAS' => 1044,
    'Back End - ACSIS' => 1045,
    'Back End - CBE' => 1046,
    'Back End - IFD' => 1047,
    'Front End - Namakanui' => 2008,
    'Front End - HARP' => 2001,
    'Front End - RxA' => 1048,
    'Front End - RxB' => 1049,
    'Front End - RxW' => 1050,
    'Front End - RxH3' => 1054,
    Surface => 1055,
    SCUBA   => 1051,
    'SCUBA-2' => 1065,
    IFS => 1053,
    'Water Vapor Rad.' => 1052,
    'Weather Station' => 2009,
    'Visitor Instruments' => 1042,
    Instrument => 1043,
    Computer => 1011,
    Carousel => 1012,
    'Other/Unknown' => -1,
});

is_deeply(OMP::Fault->faultSystems('JCMT'), {
    Telescope => 1016,
    'Back End - ACSIS' => 1045,
    'Front End - Namakanui' => 2008,
    'Front End - HARP' => 2001,
    'Front End - RxA' => 1048,
    'Front End - RxH3' => 1054,
    Surface => 1055,
    'SCUBA-2' => 1065,
    IFS => 1053,
    'Water Vapor Rad.' => 1052,
    'Weather Station' => 2009,
    'Visitor Instruments' => 1042,
    Instrument => 1043,
    Computer => 1011,
    Carousel => 1012,
    'Other/Unknown' => -1,
});

is_deeply(OMP::Fault->faultSystems('SAFETY'), {
    'Severe injury or death' => 3004,
    'Major injury' => 3003,
    'Minor injury' => 3002,
    'Equipment damage' => 3001,
    'Clarification' => 3000,
    'Environmental issue' => 3005,
    'Environmental incident' => 3006,
});

is_deeply(OMP::Fault->faultSystems('VEHICLE_INCIDENT'), {
    '1'  => 6501,
    '2'  => 6502,
    '3'  => 6503,
    '4'  => 6504,
    '5'  => 6505,
    '6'  => 6506,
    '7'  => 6507,
    '9'  => 6509,
    '10' => 6510,
    '11' => 6511,
    '13' => 6513,
    '14' => 6514,
});

# Test mail_list method.
my %mail_list_expect = (
    csg => ['csg-faults@eaobservatory.org'],
    dr => ['dr-faults@eaobservatory.org'],
    facility => ['facility-faults@eaobservatory.org'],
    jcmt => ['jcmt-faults@eaobservatory.org'],
    jcmt_events => ['jcmt_event_log@eao.hawaii.edu'],
    omp => ['omp-faults@eaobservatory.org'],
    safety => ['safety-faults@eaobservatory.org'],
    ukirt => ['ukirt_faults@eao.hawaii.edu'],
    vehicle_incident => ['vehicle@eao.hawaii.edu'],
);

foreach my $cat (sort keys %mail_list_expect) {
    is_deeply(
        OMP::Fault->new(
            category => $cat,
            fault => OMP::Fault::Response->new(
                author => $author,
                text => 'text'),
        )->mail_list(),
        $mail_list_expect{$cat});
}

# Test option methods.
is(OMP::Fault->faultCanAssocProjects('JCMT'), 1);
is(OMP::Fault->faultCanAssocProjects('CSG'), 0);

is(OMP::Fault->faultCanLoseTime('JCMT'), 1);
is(OMP::Fault->faultCanLoseTime('DR'), 0);

is(OMP::Fault->faultIsTelescope('JCMT'), 1);
is(OMP::Fault->faultIsTelescope('OMP'), 0);
