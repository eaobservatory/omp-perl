#!perl

use Test::More tests => 10;
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
