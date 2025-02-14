#!perl

# Test OMP::Project class

# Copyright (C) 2002-2005 Particle Physics and Astronomy Research Council.
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


use warnings;
use strict;
use Test::More tests => 54;
use Data::Dumper;

require_ok('OMP::Project');
require_ok('OMP::User');

# email address
my @coiemail = (qw/email1@a email2@b email3@c /);

# Project hash
my %project = (
    # country => ['UK','CA'],
    tagpriority => 5,
    projectid => "M01Btj",
    pi => OMP::User->new(
        userid => "JBLOGGS",
        name => "Joe Bloggs",
        email => "joe\@jach.hawaii.edu"
    ),
    piemail => "joe\@jach.hawaii.edu",
    coi => "name1:name2:name3",
    support => [
        OMP::User->new(
            userid => 'xx',
            name => 'fem',
            email => 'xx@jach',
        ),
        OMP::User->new(
            userid => 'xy',
            name => 'bloke',
            email => 'xy@jach',
        ),
    ],
    allocated => 3000,
);

my $dup_support = OMP::User->new(
    userid => 'xy',
    name => 'bloke',
    email => 'xy-2@jach',
);

my $dup_coi = 'name3';

# Instantiate a Project object
my $proj = OMP::Project->new(%project);

# and check it
ok($proj, 'Instantiate a project object');
isa_ok( $proj, 'OMP::Project');

# and check we can actually specify a country after a tag priority
my @countries = sort qw/ UK CA/;
$proj->country(\@countries);

# send useful class summary
print map {"#$_\n"} split "\n", Dumper($proj);

# Project id should be case insensitive
is($proj->projectid, uc($project{projectid}), 'Check projectid');

# Check tagpriority and queue
is($proj->tagpriority('UK'), $project{tagpriority}, 'Check UK priority');
my @pri = $proj->tagpriority;
is(@pri, @countries, 'Check number of priorities matches number of countries');
is($proj->primaryqueue, $countries[0], 'Check primary queue');


is($proj->tagpriority($countries[1]), $project{tagpriority},
    'Priority by country');
is($proj->country, $countries[0],
    'Country list in scalar context');
is($proj->tagpriority, $project{tagpriority},
    'check that we have the right number of priorities in scalar context');

my @outcountries = $proj->country;
my @outpri = $proj->tagpriority;
for my $i (0 .. $#countries) {
    is($outpri[$i], $project{tagpriority}, "Check TAG $i");
    is($outcountries[$i], $countries[$i], "Check country $i");
}

$proj->tagpriority(UK => 4);
is($proj->tagpriority('UK'), 4, 'Check new UK priority');

# Now fiddle with a TAG adjustment
$proj->tagadjustment(UK => -2);
is($proj->queue('UK'), 4, 'combined priority unchanged');
is($proj->tagpriority('UK'), 6, 'check adjusted UK priority');

# T-O-O
ok(! $proj->isTOO, 'IS this not a T-O-O?');
$proj->tagpriority(UK => -1);
ok($proj->isTOO, 'IS this a T-O-O?');

# Check the CoI stuff

# First register the email addresses
my @coi = $proj->coi;
for my $i (0 .. $#coi) {
    $coi[$i]->email($coiemail[$i]);
}


# should be 3 names either : delimited or in an array
is($proj->coi, uc($project{coi}), 'Check coi scalar');
is(scalar(@coi), 3, 'Count number of cois');
is(join("$OMP::Project::DELIM", map {lc($_->userid)} @coi),
    $project{coi}, 'Join the cois using the delimiter');

my @email = $proj->coiemail;

for my $i (0 .. $#coiemail) {
    is($email[$i], $coiemail[$i], 'Verify coi email addresses');
}

is($proj->coiemail,
    join("$OMP::Project::DELIM", @coiemail),
    'Join coi email addresses using delimiter'
);

# Support email
is($proj->supportemail,
    join("$OMP::Project::DELIM", map {$_->email} @{$project{support}}),
    'test support addresses'
);

# and investigators
is($proj->investigators, (1 + @coiemail),
    'Count investigators');

# Contact lists
$proj->contactable(name1 => 1);

# should now be 4 contacts for the project
is($proj->contacts,
    (1 + 1 + scalar(@{$project{support}})),
    'number of contacts'
);

# No duplication.
my $old_supp_mail = $proj->supportemail();

push @{$project{support}}, $dup_support;
$proj->support($proj->support(), $dup_support);
print map {"#$_\n"} split "\n",
    Dumper({
        'all old support email' => $old_supp_mail,
        'new support user' => $dup_support,
        'all new support email: $project{support}' =>
            join($OMP::Project::DELIM, map {$_->email} @{$project{support}}),
        'new support: $proj->support()' => [$proj->support()]
    });
is($old_supp_mail, $proj->supportemail(),
    'no duplicate support user id: new should be same as old');
isnt($old_supp_mail,
    join($OMP::Project::DELIM, map {$_->email} @{$project{support}}),
    'no duplicate support user id: only adding via $proj->support() counts');


my $old_coi_list = $proj->coi();
my $new_coi_list = join $OMP::Project::DELIM, $old_coi_list, $dup_coi;
$proj->coi($new_coi_list);

is($old_coi_list, $proj->coi(),
    'no duplicate coi user id: new should be same as old');
isnt($old_coi_list, $new_coi_list,
    'no duplicate coi user id: only adding via $proj->coi() counts');

# Check the time allocation
print "# Time allocation\n";
is($proj->allocated, $project{allocated}, 'Check allocated time');
is($proj->remaining, $proj->allocated, 'Check time remaining');
is($proj->used, 0.0, 'Check time used');

# Set some time pending
my $used = 360;
$proj->incPending($used);
is($proj->pending, $used, 'Check pending time');
is($proj->used, $used, 'Check time used');

is($proj->allRemaining, ($project{allocated} - $used), 'Check time remaining');

$proj->consolidateTimeRemaining;
is($proj->used, $used, 'Check time used');
is($proj->remaining, ($project{allocated} - $used), 'Check time remaining');
is($proj->pending, 0.0, 'Check time pending');

isa_ok($proj->remaining, 'Time::Seconds');


# site quality constraints

$proj->cloudrange(OMP::Range->new(Min => 0, Max => 100));
is($proj->cloudtxt, 'any', 'Cloud text representation for 0 - 100 %');

$proj->cloudrange(OMP::Range->new(Min => 30, Max => 100));
is($proj->cloudtxt, 'thick', 'Cloud text representation for 30 - 100 %');

$proj->cloudrange(OMP::Range->new(Min => 0, Max => 20));
is($proj->cloudtxt,
    'cirrus or photometric',
    'Cloud text representation for 0 - 20 %');

$proj->cloudrange(OMP::Range->new(Min => 0, Max => 0));
is($proj->cloudtxt,
    'photometric',
    'Cloud text representation for 0 %');

$proj->cloudrange(OMP::Range->new(Min => 0, Max => 1));
is($proj->cloudtxt,
    'cirrus or photometric',
    'Cloud text representation for 0 - 1 %');

$proj->cloudrange(OMP::Range->new(Min => 1, Max => 20));
is($proj->cloudtxt,
    'cirrus',
    'Cloud text representation for 1 - 20 %');

$proj->cloudrange(OMP::Range->new(Min => 1, Max => 21));
is($proj->cloudtxt,
    'thick or cirrus',
    'Cloud text representation for 1 - 21 %');

$proj->cloudrange(OMP::Range->new(Min => 20, Max => 100));
is($proj->cloudtxt,
    'thick or cirrus',
    'Cloud text representation for 20 - 100 %');

$proj->cloudrange(OMP::Range->new(Min => 21, Max => 100));
is($proj->cloudtxt,
    'thick',
    'Cloud text representation for 21 - 100 %');

$proj->cloudrange(OMP::Range->new(Min => 0, Max => 21));
is($proj->cloudtxt,
    'any',
    'Cloud text representation for 0 - 21 %');
