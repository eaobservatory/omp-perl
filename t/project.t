#!perl

# Test OMP::Project class

use warnings;
use strict;
use Test::More tests => 27;
use Data::Dumper;

require_ok( 'OMP::Project' );
require_ok( 'OMP::User' );

# email address
my @coiemail = ( qw/email1@a email2@b email3@c / );

# Project hash
my %project = (
	       password => "atest",
	       projectid => "M01Btj",
	       pi => new OMP::User( userid => "JBLOGGS",
				    name => "Joe Bloggs",
				    email => "joe\@jach.hawaii.edu"),
	       piemail => "joe\@jach.hawaii.edu",
	       coi => "name1:name2:name3",
	       support => [new OMP::User( userid => 'xx',
					 name => 'fem',
					 email => 'xx@jach',
				       ),
	       new OMP::User( userid => 'xy',
					 name => 'bloke',
					 email => 'xy@jach',
				       ),],
	       allocated => 3000,
	      );

# Instantiate a Project object
my $proj = new OMP::Project( %project );

ok($proj, "Instantiate a project object");
isa_ok( $proj, "OMP::Project");

# sned useful class summary
print map { "#$_\n" } split "\n", Dumper($proj);

# Project id should be case insensitive
is( $proj->projectid, uc($project{projectid}),"Check projectid");

# Check the password
is( $proj->password, $project{password}, "Check password" );
ok( $proj->verify_password ,"verify password");
print "# Password: ", $proj->password, " Encrypted form: ", 
  $proj->encrypted, "\n";

# Check the CoI stuff

# First register the email addresses
my @coi = $proj->coi;
for my $i (0..$#coi) {
  $coi[$i]->email( $coiemail[$i]);
}


# should be 3 names either : delimited or in an array
is( $proj->coi, uc($project{coi}), "Check coi scalar" );
is( scalar(@coi), 3, "Count number of cois");
is( join("$OMP::Project::DELIM", map { lc($_->userid) } @coi), $project{coi},
  "Join the cois using the delimiter");

my @email = $proj->coiemail;

for my $i (0.. $#coiemail) {
  is( $email[$i], $coiemail[$i],"Verify coi email addresses");
}

is( $proj->coiemail, join("$OMP::Project::DELIM", @coiemail),
  "Join coi email addresses using delimiter");

# Support email
is( $proj->supportemail, join("$OMP::Project::DELIM", 
			      map { $_->email } @{$project{support}}),
  "test support addresses");

# and investigators
is( $proj->investigators, (1 + @coiemail),
  "Count investigators");

# Contact lists
$proj->contactable( name1 => 1);

# should now be 4 contacts for the project
is( $proj->contacts, (1 + 1 + scalar(@{$project{support}})),
  "number of contacts");

# Check the time allocation
print "# Time allocation\n";
is( $proj->allocated, $project{allocated},"Check allocated time");
is( $proj->remaining, $proj->allocated, "Check time remaining" );
is( $proj->used, 0.0 , "Check time used");

# Set some time pending
my $used = 360;
$proj->incPending( $used );
is( $proj->pending, $used, "Check pending time" );
is( $proj->used, $used, "Check time used" );

is( $proj->allRemaining, ($project{allocated} - $used),
  "Check time remaining");

$proj->consolidateTimeRemaining;
is( $proj->used, $used, "Check time used" );
is( $proj->remaining, ($project{allocated} - $used), "Check time remaining");
is( $proj->pending, 0.0, "Check time pending");

isa_ok( $proj->remaining, "Time::Seconds");
