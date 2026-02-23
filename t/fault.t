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


use Test::More tests => 76
    + 4  # General information
    + (9 * 5)  # Mailing lists
    + 23  # Options
    + 15  # Status lists
    + (16 * 2);  # Open/closed methods
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
    category => 'JCMT',
    fault => $resp,
    system => OMP::Fault::FRONT_END_HARP(),
);
ok($fault, 'Fault object created');
isa_ok($fault, 'OMP::Fault');
is($fault->systemText, 'Front End - HARP');
is($fault->systemTextAbbr, 'HARP');
is($fault->faultCanAssocProjects, 1);
is($fault->faultCanLoseTime, 1);
is($fault->faultHasLocation, 0);
is($fault->faultHasTimeOccurred, 1);
is($fault->faultIsTelescope, 1);
is($fault->getCategorySystemLabel, 'System');
is($fault->getCategoryName, 'JCMT');
is($fault->getCategoryFullName, 'JCMT Faults');
is($fault->getCategoryEntryNameQualified, 'JCMT fault');
is($fault->urgency, OMP::Fault::URGENCY_NORMAL());
is($fault->urgencyText, 'Normal');
ok(not $fault->isUrgent);
is($fault->condition, OMP::Fault::CONDITION_NORMAL());
is($fault->conditionText, 'Normal');
ok(not $fault->isChronic);
is($fault->statusText, 'Open');

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
$fault->status(OMP::Fault::CLOSED());

my @resps = $fault->responses;
is(scalar(@resps), 2, 'Count responses');

# Check isfault flags
ok($resps[0]->isfault, 'check first is a fault');
ok(! $resps[1]->isfault, 'second response is not a fault');

is($fault->statusText, 'Closed');

# Print the stringified fault for info
# Need to prepend #
my $string = "$fault";
my @lines = split "\n", $string;
$string = join '', map {"#$_\n"} @lines;
print $string;

# Test faults in other categories.
$fault = OMP::Fault->new(
    category => 'VEHICLE_INCIDENT',
    fault => OMP::Fault::Response->new(
        author => $author,
        text => 'text',
    ),
    system => OMP::Fault::VEHICLE_04(),
    type => OMP::Fault::VEHICLE_WARNING_LIGHTS(),
    urgency => OMP::Fault::URGENCY_URGENT(),
    condition => OMP::Fault::CONDITION_CHRONIC(),
    status => OMP::Fault::KNOWN_FAULT(),
);
isa_ok($fault, 'OMP::Fault');
is($fault->systemText, '4');
is($fault->systemTextAbbr, '4');
is($fault->faultCanAssocProjects, 0);
is($fault->faultCanLoseTime, 0);
is($fault->faultHasLocation, 0);
is($fault->faultHasTimeOccurred, 0);
is($fault->faultIsTelescope, 0);
is($fault->getCategorySystemLabel, 'Vehicle');
is($fault->getCategoryName, 'Vehicle Incident');
is($fault->getCategoryAbbrName, 'Veh. Inc.');
is($fault->getCategoryFullName, 'Vehicle Incident Reporting');
is($fault->typeText, 'Warning lights');
is($fault->typeTextAbbr, 'Warnings');
is($fault->urgency, OMP::Fault::URGENCY_URGENT());
is($fault->urgencyText, 'Urgent');
ok($fault->isUrgent);
is($fault->condition, OMP::Fault::CONDITION_CHRONIC());
is($fault->conditionText, 'Chronic');
ok($fault->isChronic);
is($fault->statusText, 'Known fault');

$fault = OMP::Fault->new(
    category => 'SAFETY',
    fault => OMP::Fault::Response->new(
        author => $author,
        text => 'text',
    ),
    system => OMP::Fault::EQUIP_DAMAGE(),
    type => OMP::Fault::INCIDENT(),
    location => OMP::Fault::IN_TRANSIT(),
    status => OMP::Fault::FOLLOW_UP(),
);
isa_ok($fault, 'OMP::Fault');
is($fault->systemText, 'Equipment damage');
is($fault->systemTextAbbr, 'Equipment damage');
is($fault->faultCanAssocProjects, 0);
is($fault->faultCanLoseTime, 0);
is($fault->faultHasLocation, 1);
is($fault->faultHasTimeOccurred, 0);
is($fault->faultIsTelescope, 0);
is($fault->getCategorySystemLabel, 'Severity');
is($fault->getCategoryName, 'Safety');
is($fault->getCategoryAbbrName, 'Safety');
is($fault->getCategoryFullName, 'Safety Reporting');
is($fault->typeText, 'Incident');
is($fault->typeTextAbbr, 'Incident');
is($fault->locationText, 'In transit');
is($fault->statusText, 'Follow up required');

$fault->status(OMP::Fault::NO_ACTION());
is($fault->statusText, 'No further action');

$fault = OMP::Fault->new(
    category => 'JCMT_EVENTS',
    fault => OMP::Fault::Response->new(
        author => $author,
        text => 'text',
    ),
    system => OMP::Fault::POINTING(),
    status => OMP::Fault::COMMISSIONING(),
);
isa_ok($fault, 'OMP::Fault');
is($fault->statusText, 'Commissioning');

# Test safety fault locations.  By default we should now hide "JAC".
is_deeply(OMP::Fault->faultLocation('SAFETY', include_hidden => 1), {
    4000 => 'In transit',
    4001 => 'JAC',
    4002 => 'HP',
    4003 => 'JCMT',
    4004 => 'UKIRT',
    4005 => 'EAO',
});

is_deeply(OMP::Fault->faultLocation('SAFETY'), {
    4000 => 'In transit',
    4002 => 'HP',
    4003 => 'JCMT',
    4004 => 'UKIRT',
    4005 => 'EAO',
});

# Test fault systems.
is_deeply(OMP::Fault->faultSystems('JCMT', include_hidden => 1), {
    1016 => 'Telescope',
    1044 => 'Back End - DAS',
    1045 => 'Back End - ACSIS',
    1046 => 'Back End - CBE',
    1047 => 'Back End - IFD',
    1071 => 'Back End - VLBI',
    2008 => "Front End - N\x{101}makanui",
    2010 => "Front End - \x{2bb}\x{16a}\x{2bb}\x{16b}",
    2011 => "Front End - \x{2bb}\x{100}weoweo",
    2012 => "Front End - \x{2bb}Ala\x{2bb}ihi",
    2013 => "Front End - Kuntur",
    2001 => 'Front End - HARP',
    1048 => 'Front End - RxA',
    1049 => 'Front End - RxB',
    1050 => 'Front End - RxW',
    1054 => 'Front End - RxH3',
    1055 => 'Surface',
    1051 => 'SCUBA' ,
    1065 => 'SCUBA-2',
    1053 => 'IFS',
    1052 => 'Water Vapor Monitor',
    2009 => 'Weather Station',
    1042 => 'Visitor Instruments',
    1043 => 'Instrument',
    1011 => 'Computer',
    1012 => 'Carousel',
    -1 => 'Other/Unknown',
});

is_deeply(OMP::Fault->faultSystems('JCMT'), {
    1016 => 'Telescope',
    1045 => 'Back End - ACSIS',
    1071 => 'Back End - VLBI',
    2008 => "Front End - N\x{101}makanui",
    2010 => "Front End - \x{2bb}\x{16a}\x{2bb}\x{16b}",
    2011 => "Front End - \x{2bb}\x{100}weoweo",
    2012 => "Front End - \x{2bb}Ala\x{2bb}ihi",
    2013 => "Front End - Kuntur",
    2001 => 'Front End - HARP',
    1054 => 'Front End - RxH3',
    1055 => 'Surface',
    1065 => 'SCUBA-2',
    1052 => 'Water Vapor Monitor',
    2009 => 'Weather Station',
    1042 => 'Visitor Instruments',
    1011 => 'Computer',
    1012 => 'Carousel',
    -1 => 'Other/Unknown',
});

is_deeply(OMP::Fault->faultSystems('SAFETY'), {
    3004 => 'Severe injury or death',
    3003 => 'Major injury',
    3002 => 'Minor injury',
    3001 => 'Equipment damage',
    3000 => 'Clarification',
    3005 => 'Environmental issue',
    3006 => 'Environmental incident',
});

is_deeply(OMP::Fault->faultSystems('VEHICLE_INCIDENT'), {
    6501 => '1',
    6502 => '2',
    6503 => '3',
    6504 => '4',
    6505 => '5',
    6506 => '6',
    6507 => '7',
    6509 => '9',
    6510 => '10',
    6511 => '11',
    6513 => '13',
    6514 => '14',
});

# Test general information.
is_deeply([sort OMP::Fault->faultCategories], [qw/
    CSG
    DR
    FACILITY
    JCMT
    JCMT_EVENTS
    OMP
    SAFETY
    UKIRT
    VEHICLE_INCIDENT
/]);

is_deeply(OMP::Fault->faultTypes('JCMT'), {
    1013 => 'Mechanical',
    1014 => 'Electronic',
    1005 => 'Hardware',
    1006 => 'Software',
    1015 => 'Cryogenic',
    -1 => 'Other/Unknown',
    0 => 'Human',
    1007 => 'Network',
});

is_deeply(OMP::Fault->faultUrgency(), {
    0 => 'Urgent',
    1 => 'Normal',
    2 => 'Info',
});

is_deeply(OMP::Fault->faultCondition(), {
    0 => 'Chronic',
    1 => 'Normal',
});

# Test mail_list method.
my %mail_list_expect = (
    csg => {
        address => ['csg-faults@eaobservatory.org'],
        name => 'CSG Faults',
    },
    dr => {
        address => ['dr-faults@eaobservatory.org'],
        name => 'DR Faults',
    },
    facility => {
        address => ['facility-faults@eaobservatory.org'],
        name => 'Facility Faults',
    },
    jcmt => {
        address => ['jcmt-faults@eaobservatory.org'],
        name => 'JCMT Faults',
    },
    jcmt_events => {
        address => ['jcmt_event_log@eao.hawaii.edu'],
        name => 'JCMT Events',
    },
    omp => {
        address => ['omp-faults@eaobservatory.org'],
        name => 'OMP Faults',
    },
    safety => {
        address => ['safety-faults@eaobservatory.org'],
        name => 'Safety Reporting',
    },
    ukirt => {
        address => ['ukirt_faults@eao.hawaii.edu'],
        name => 'UKIRT Faults',
    },
    vehicle_incident => {
        address => ['vehicle@eao.hawaii.edu'],
        name => 'Vehicle Incident Reporting',
    },
);

foreach my $cat (sort keys %mail_list_expect) {
    my $expect = $mail_list_expect{$cat};
    my $f = OMP::Fault->new(
        category => $cat,
        fault => OMP::Fault::Response->new(
            author => $author,
            text => 'text'),
    );
    is_deeply($f->mail_list(), $expect->{'address'});

    # Test construction of user objects -- this part assumes just
    # one address per list.
    my @users = $f->mail_list_users;
    is(1, length @users);
    my $user = $users[0];
    isa_ok($user, 'OMP::User');
    is($user->email, $expect->{'address'}->[0]);
    is($user->name, $expect->{'name'});
}

# Test option methods.
is(OMP::Fault->faultCanAssocProjects('JCMT'), 1);
is(OMP::Fault->faultCanAssocProjects('CSG'), 0);

is(OMP::Fault->faultCanLoseTime('JCMT'), 1);
is(OMP::Fault->faultCanLoseTime('DR'), 0);

is(OMP::Fault->faultHasLocation('JCMT'), 0);
is(OMP::Fault->faultHasLocation('SAFETY'), 1);

is(OMP::Fault->faultHasTimeOccurred('SAFETY'), 0);
is(OMP::Fault->faultHasTimeOccurred('JCMT'), 1);
is(OMP::Fault->faultHasTimeOccurred('JCMT_EVENTS'), 1);

is(OMP::Fault->faultInitialStatus('JCMT'), OMP::Fault::OPEN());
is(OMP::Fault->faultInitialStatus('JCMT_EVENTS'), OMP::Fault::ONGOING());
is(OMP::Fault->faultInitialStatus('SAFETY'), OMP::Fault::FOLLOW_UP());

is(OMP::Fault->faultIsTelescope('JCMT'), 1);
is(OMP::Fault->faultIsTelescope('OMP'), 0);

is(OMP::Fault->getCategoryEntryName('JCMT'), 'Fault');
is(OMP::Fault->getCategoryEntryName('JCMT_EVENTS'), 'Event');
is(OMP::Fault->getCategoryEntryNameQualified('JCMT'), 'JCMT fault');
is(OMP::Fault->getCategoryEntryNameQualified('JCMT_EVENTS'), 'JCMT event');

is(OMP::Fault->getCategorySystemLabel('OMP'), 'System');
is(OMP::Fault->getCategorySystemLabel('VEHICLE_INCIDENT'), 'Vehicle');
is(OMP::Fault->getCategorySystemLabel('SAFETY'), 'Severity');

is(OMP::Fault->getCategoryFullName('OMP'), 'OMP Faults');
is(OMP::Fault->getCategoryFullName('JCMT_EVENTS'), 'JCMT Events');

# Test "status" list methods.
is_deeply([sort values %{OMP::Fault->faultStatus()}], [
    'Closed',
    'Commissioning',
    'Complete',
    'Duplicate',
    'Follow up required',
    'Immediate action required',
    'Known fault',
    'No further action',
    'Not a fault',
    'Ongoing',
    'Open',
    'Open - Will be fixed',
    'Refer to safety committee',
    'Suspended',
    'Won\'t be fixed',
    'Works for me',
]);

is_deeply([sort values %{OMP::Fault->faultStatusOpen()}], [
    'Commissioning',
    'Follow up required',
    'Immediate action required',
    'Known fault',
    'Ongoing',
    'Open',
    'Open - Will be fixed',
    'Refer to safety committee',
    'Suspended',
]);

is_deeply([sort values %{OMP::Fault->faultStatusClosed()}], [
    'Closed',
    'Complete',
    'Duplicate',
    'No further action',
    'Not a fault',
    'Won\'t be fixed',
    'Works for me',
]);

is_deeply([sort values %{OMP::Fault->faultStatus('JCMT')}], [
    'Closed',
    'Duplicate',
    'Not a fault',
    'Open',
    'Open - Will be fixed',
    'Suspended',
    'Won\'t be fixed',
    'Works for me',
]);

is_deeply([sort values %{OMP::Fault->faultStatusOpen('JCMT')}], [
    'Open',
    'Open - Will be fixed',
    'Suspended',
]);

is_deeply([sort values %{OMP::Fault->faultStatusClosed('JCMT')}], [
    'Closed',
    'Duplicate',
    'Not a fault',
    'Won\'t be fixed',
    'Works for me',
]);

is_deeply([sort values %{OMP::Fault->faultStatus('SAFETY')}], [
    'Closed',
    'Follow up required',
    'Immediate action required',
    'No further action',
    'Refer to safety committee',
]);

is_deeply([sort values %{OMP::Fault->faultStatusOpen('SAFETY')}], [
    'Follow up required',
    'Immediate action required',
    'Refer to safety committee',
]);

is_deeply([sort values %{OMP::Fault->faultStatusClosed('SAFETY')}], [
    'Closed',
    'No further action',
]);

is_deeply([sort values %{OMP::Fault->faultStatus('JCMT_EVENTS')}], [
    'Commissioning',
    'Complete',
    'Ongoing',
]);

is_deeply([sort values %{OMP::Fault->faultStatusOpen('JCMT_EVENTS')}], [
    'Commissioning',
    'Ongoing',
]);

is_deeply([sort values %{OMP::Fault->faultStatusClosed('JCMT_EVENTS')}], [
    'Complete',
]);

is_deeply([sort values %{OMP::Fault->faultStatus('VEHICLE_INCIDENT')}], [
    'Closed',
    'Duplicate',
    'Known fault',
    'Open',
    'Open - Will be fixed',
    'Won\'t be fixed',
]);

is_deeply([sort values %{OMP::Fault->faultStatusOpen('VEHICLE_INCIDENT')}], [
    'Known fault',
    'Open',
    'Open - Will be fixed',
]);

is_deeply([sort values %{OMP::Fault->faultStatusClosed('VEHICLE_INCIDENT')}], [
    'Closed',
    'Duplicate',
    'Won\'t be fixed',
]);

# Check that the "isOpen", "faultStatusOpen" and "faultStatusClosed" methods agree.
my $status = OMP::Fault->faultStatus;
my %status_open = map {$_ => 1} keys %{OMP::Fault->faultStatusOpen};
my %status_closed = map {$_ => 1} keys %{OMP::Fault->faultStatusClosed};
while (my ($status_value, $status_text) = each %$status) {
    my $f = OMP::Fault->new(
        category => 'OMP',
        fault => OMP::Fault::Response->new(
            author => $author,
            text => 'text'),
        status => $status_value,
    );
    if ($f->isOpen) {
        ok(exists $status_open{$status_value},
            "open status $status_text in open list");
        ok(! exists $status_closed{$status_value},
            "open status $status_text not in closed list");
    }
    else {
        ok(! exists $status_open{$status_value},
            "closed status $status_text not in open list");
        ok(exists $status_closed{$status_value},
            "closed status $status_text in closed list");
    }
}
