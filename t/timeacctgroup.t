#!perl

# Copyright (C) 2002-2005 Particle Physics and Astronomy Research Council.
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

use Test::More tests => 10 + 43;
use Time::Piece qw/:override/;

require_ok('OMP::Project::TimeAcct');
require_ok('OMP::Project::TimeAcct::Group');

my $date = scalar gmtime;
my $tg = OMP::Project::TimeAcct::Group->new(
    accounts => [
        OMP::Project::TimeAcct->new(
            date => $date,
            projectid => 'M25AP777',
            timespent => 3600,
            confirmed => 1,
        ),
        OMP::Project::TimeAcct->new(
            date => $date,
            projectid => 'M25AP888',
            timespent => 7200,
            confirmed => 0,
        ),
    ]);

isa_ok($tg, 'OMP::Project::TimeAcct::Group');

is($tg->totaltime->hours, 3.0, 'total time');
is($tg->confirmed_time->hours, 1.0, 'confirmed time');
is($tg->unconfirmed_time->hours, 2.0, 'unconfirmed time');
isa_ok($tg->{'TotalTime'}, 'Time::Seconds');
isa_ok($tg->{'ConfirmedTime'}, 'Time::Seconds');

# Time attributes should be cleared when we set a new list of objects.
$tg->accounts([]);
is($tg->{'TotalTime'}, undef, 'TotalTime cleared');
is($tg->{'ConfirmedTime'}, undef, 'ConfirmedTime cleared');

# Test summary method.
my @input = (
    {
        timespent => 15,
        confirmed => 1,
        projectid => 'blah2',
        date => '2002-08-15',
    },
    {
        timespent => 10,
        confirmed => 0,
        projectid => 'blah1',
        date => '2002-08-15',
    },
    {
        timespent => 5,
        confirmed => 0,
        projectid => 'blah3',
        date => '2002-08-15',
    },
    {
        timespent => 20,
        confirmed => 1,
        projectid => 'blah1',
        date => '2002-08-16',
    },
    {
        timespent => 30,
        confirmed => 1,
        projectid => 'blah1',
        date => '2002-07-15',
    },
);

# now create the objects
my @acct = map {OMP::Project::TimeAcct->new(
        confirmed => $_->{confirmed},
        timespent => $_->{timespent},
        projectid => $_->{projectid},
        date => OMP::DateTools->parse_date($_->{date}),
)} @input;

is(scalar(@acct), scalar(@input), 'make sure we have equal in and out');
for (@acct) {
    isa_ok($_, 'OMP::Project::TimeAcct');
}

$tg = OMP::Project::TimeAcct::Group->new(
    accounts => \@acct,
);
isa_ok($tg, 'OMP::Project::TimeAcct::Group');

my $results = $tg->summary('all');
is($results->{pending},   15, 'all : pending');
is($results->{confirmed}, 65, 'all : confirmed');
is($results->{total},     80, 'all : total');

$results = $tg->summary('bydate');
is($results->{'2002-08-15'}{pending},   15, 'bydate 2002-08-15: pending');
is($results->{'2002-08-15'}{confirmed}, 15, 'bydate 2002-08-15: confirmed');
is($results->{'2002-08-15'}{total},     30, 'bydate 2002-08-15: total');

is($results->{'2002-08-16'}{pending},    0, 'bydate 2002-08-16: pending');
is($results->{'2002-08-16'}{confirmed}, 20, 'bydate 2002-08-16: confirmed');
is($results->{'2002-08-16'}{total},     20, 'bydate 2002-08-16: total');

is($results->{'2002-07-15'}{pending},    0, 'bydate 2002-07-15: pending');
is($results->{'2002-07-15'}{confirmed}, 30, 'bydate 2002-07-15: confirmed');
is($results->{'2002-07-15'}{total},     30, 'bydate 2002-07-15: total');

$results = $tg->summary('byproject');
is($results->{'BLAH1'}{pending},   10, 'byproj blah1: pending');
is($results->{'BLAH1'}{confirmed}, 50, 'byproj blah1: confirmed');
is($results->{'BLAH1'}{total},     60, 'byproj blah1: total');

is($results->{'BLAH2'}{pending},    0, 'byproj blah2: pending');
is($results->{'BLAH2'}{confirmed}, 15, 'byproj blah2: confirmed');
is($results->{'BLAH2'}{total},     15, 'byproj blah2: total');

is($results->{'BLAH3'}{pending},    5, 'byproj blah3: pending');
is($results->{'BLAH3'}{confirmed},  0, 'byproj blah3: confirmed');
is($results->{'BLAH3'}{total},      5, 'byproj blah3: total');

$results = $tg->summary('byprojdate');
is($results->{'BLAH1'}{'2002-08-15'}{pending},   10, 'byproj-date blah1/2002-08-15: pending');
is($results->{'BLAH1'}{'2002-08-15'}{confirmed},  0, 'byproj-date blah1/2002-08-15: confirmed');
is($results->{'BLAH1'}{'2002-08-15'}{total},     10, 'byproj-date blah1/2002-08-15: total');

is($results->{'BLAH1'}{'2002-08-16'}{pending},    0, 'byproj-date blah1/2002-08-16: pending');
is($results->{'BLAH1'}{'2002-08-16'}{confirmed}, 20, 'byproj-date blah1/2002-08-16: confirmed');
is($results->{'BLAH1'}{'2002-08-16'}{total},     20, 'byproj-date blah1/2002-08-16: total');

is($results->{'BLAH1'}{'2002-07-15'}{pending},    0, 'byproj-date blah1/2002-07-15: pending');
is($results->{'BLAH1'}{'2002-07-15'}{confirmed}, 30, 'byproj-date blah1/2002-07-15: confirmed');
is($results->{'BLAH1'}{'2002-07-15'}{total},     30, 'byproj-date blah1/2002-07-15: total');

is($results->{'BLAH2'}{'2002-08-15'}{pending},    0, 'byproj-date blah2/2002-08-15: pending');
is($results->{'BLAH2'}{'2002-08-15'}{confirmed}, 15, 'byproj-date blah2/2002-08-15: confirmed');
is($results->{'BLAH2'}{'2002-08-15'}{total},     15, 'byproj-date blah2/2002-08-15: total');

is($results->{'BLAH3'}{'2002-08-15'}{pending},    5, 'byproj-date blah3/2002-08-15: pending');
is($results->{'BLAH3'}{'2002-08-15'}{confirmed},  0, 'byproj-date blah3/2002-08-15: confirmed');
is($results->{'BLAH3'}{'2002-08-15'}{total},      5, 'byproj-date blah3/2002-08-15: total');
