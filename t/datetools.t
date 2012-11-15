#!perl

# Test OMP::General

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

use strict;
use Test::More tests => 74;
use Test::Warn qw/warning_like/;

use Time::Piece qw/ :override /;
use Time::Seconds;

require_ok('OMP::DateTools');

my $year = 1999;
my $mon  = 1;
my $mon_str = "Jan";
my $day  = 5;
my $hh   = 5;
my $mm   = 15;
my $sec  = 0.0;

# Create two input dates. One in ISO format, the other in
# Sybase style
my @dateinput;

# ISO
push(@dateinput,  sprintf("%04d-%02d-%02dT%02d:%02d",
	   	     $year, $mon, $day, $hh, $mm));

# Sybase
push(@dateinput,  sprintf("$mon_str %02d %04d  %d:%02dAM",
		      $day, $year, $hh, $mm));

print "# parse_date\n";

print "# Input date: $dateinput[0]\n";

my $date;
for my $in (@dateinput) {

  $date = OMP::DateTools->parse_date( $in );

  ok( $date, "Instantiate a Time::Piece object" );
  isa_ok($date, "Time::Piece");

  unless (defined $date) {
    print "# Skipping tests since we returned undef\n";
    for (1..7) { ok(0) };
    next;
  }

  print "# Output date: $date\n";

  # Compare
  is( $date->year, $year, "Check year");
  is( $date->mon, $mon, "Check month");
  is( $date->mday, $day, "Check day");
  is( $date->hour, $hh, "Check hour");
  is( $date->min, $mm, "Check minute");
  is( $date->sec, $sec, "Check second");

  # Check that the object is UTC by using undocumented internal hack
  ok( ! $date->[Time::Piece::c_islocal], "Check we have utc date");
}

# Check that we get a UT date from a localtime object
print "# Parse a Time::Piece object that is a local time\n";
my $local = localtime( $date->epoch );
my $newdate = OMP::DateTools->parse_date( $local );
print "# Input local: ".$local->datetime. " Output UTC: ". $newdate->datetime.
  "\n";
# Compare
is( $newdate->year, $year, "Check year");
is( $newdate->mon, $mon, "Check month");
is( $newdate->mday, $day, "Check day");
is( $newdate->hour, $hh, "Check hour");
is( $newdate->min, $mm, "Check minute");
is( $newdate->sec, $sec, "Check second");

# Check that the object is UTC by using undocumented internal hack
ok( ! $newdate->[Time::Piece::c_islocal], "Check we have utc date");

# Generate a local time and verify we get back the correct UT
print "# Parse a local time\n";
my $localiso = $local->datetime;
ok( $local->[Time::Piece::c_islocal], "Check we have local date");
$newdate = OMP::DateTools->parse_date( $localiso, 1);
print "# Parse local time $localiso and get UT ".$newdate->datetime."\n";
# Compare
ok( $localiso ne $newdate->datetime, "Date ISO formats must differ");
is( $newdate->year, $year, "Check year");
is( $newdate->mon, $mon, "Check month");
is( $newdate->mday, $day, "Check day");
is( $newdate->hour, $hh, "Check hour");
is( $newdate->min, $mm, "Check minute");
is( $newdate->sec, $sec, "Check second");

# Check that the object is UTC by using undocumented internal hack
ok( ! $newdate->[Time::Piece::c_islocal], "Check we have utc date");


print "# today() and yesterday\n";

my $today = OMP::DateTools->today;
like( $today, qr/^\d\d\d\d-\d\d-\d\d$/, "Test that date is ISO format" );

# And yesterday
my $yesterday = OMP::DateTools->yesterday;
like( $yesterday, qr/^\d\d\d\d-\d\d-\d\d$/, "Test that date is ISO format" );

# Now using objects
$today = OMP::DateTools->today(1);
isa_ok( $today, "Time::Piece" );
$yesterday = OMP::DateTools->yesterday(1);
isa_ok( $yesterday, "Time::Piece" );

# Check that we have 0 hms
is($today->hour,0,"Zero hours");
is($today->min,0,"Zero minutes");
is($today->sec,0,"Zero seconds");
is($yesterday->hour,0,"Zero hours");
is($yesterday->min,0,"Zero minutes");
is($yesterday->sec,0,"Zero seconds");

# And we have one day between them
my $diff = $today - $yesterday;
isa_ok($diff, "Time::Seconds");
is($diff, ONE_DAY, "Check time difference");

print "# UT date determination\n";

# See if we get today
my $detut = OMP::DateTools->determine_utdate();
is($detut->epoch, $today->epoch, "Blank should be today");

$detut = undef;
warning_like {$detut = OMP::DateTools->determine_utdate("blah");}
  qr/Unable to parse UT date blah. Using today's date\./,
  q/Warning about date blah/;
is($detut->epoch, $today->epoch, "Unparsable should be today");

# Now force a parse
$detut = OMP::DateTools->determine_utdate( $yesterday->ymd );
is($detut->epoch, $yesterday->epoch, "Parse a Y-M-D");

# and include hms
$detut = OMP::DateTools->determine_utdate( $yesterday->ymd ."T04:40:34" );
is($detut->epoch, $yesterday->epoch, "Parse a Y-M-DTH:M:S");



print "# Semester\n";

my $refdate = OMP::DateTools->parse_date($dateinput[0]);
my $sem = OMP::DateTools->determine_semester( date => $refdate );
is($sem, "98B","Check semester 98B");

$date = gmtime(1014756003); # 2002-02-26
isa_ok( $date, "Time::Piece");
is( OMP::DateTools->determine_semester(date => $date), "02A", "Check semester 02A");

$date = gmtime(1028986003); # 2002-08-10
is( OMP::DateTools->determine_semester(date => $date), "02B","Check semesters 02B");

# Strange UKIRT boundary
$date = gmtime(1075186003); # 2004-01-27
is( OMP::DateTools->determine_semester(date => $date, tel => 'UKIRT'),
    "04A","Check UKIRT semesters 04A");

$date = gmtime(1095892304); # 2004-09-22
is( OMP::DateTools->determine_semester(date => $date, tel => 'UKIRT'),
    "04A","Check UKIRT semesters 04A lateness");

$date = gmtime(1099947233); # 2004-11-08
is( OMP::DateTools->determine_semester(date => $date, tel => 'JCMT'),
    "04B","Check JCMT semesters 04B");

$date = gmtime(1170401154); # 2007-02-02
is( OMP::DateTools->determine_semester(date => $date, tel => 'JCMT'),
    "06B","Check JCMT semesters 06B");



# Run semester determination in reverse
# These are time piece objects

my (@bound) = OMP::DateTools->semester_boundary( tel => 'JCMT', semester => '04A');

is($bound[0]->ymd, '2004-02-02', "JCMT 04A start");
is($bound[1]->ymd, '2004-08-01', "JCMT 04A end");

@bound = OMP::DateTools->semester_boundary( tel => 'JCMT', semester => '04B');
is($bound[0]->ymd, '2004-08-02', "JCMT 04B start");
is($bound[1]->ymd, '2005-02-01', "JCMT 04B end");

@bound = OMP::DateTools->semester_boundary( tel => 'JCMT', semester => '03B');
is($bound[0]->ymd, '2003-08-02', "JCMT 03B start");
is($bound[1]->ymd, '2004-02-01', "JCMT 03B end");

@bound = OMP::DateTools->semester_boundary( tel => 'UKIRT', semester => '04A');
is($bound[0]->ymd, '2004-01-17', "UKIRT 04A start");
is($bound[1]->ymd, '2004-10-01', "UKIRT 04A end");

@bound = OMP::DateTools->semester_boundary( tel => 'UKIRT', semester => 'Y');
is($bound[0]->ymd, '1993-08-02', "UKIRT Semester Y start");
is($bound[1]->ymd, '1994-02-01', "UKIRT Semester Y end");

@bound = OMP::DateTools->semester_boundary( tel => 'UKIRT', semester => [qw/03A 03B/]);
is($bound[0]->ymd, '2003-02-02', "UKIRT 03A start (2 semesters)");
is($bound[1]->ymd, '2004-01-16', "UKIRT 03B end (2 semesters)");

@bound = OMP::DateTools->semester_boundary( tel => 'JCMT', semester => [qw/06B/]);
is($bound[0]->ymd, '2006-08-02', "JCMT 06B");
is($bound[1]->ymd, '2007-03-01', "JCMT 06B");

