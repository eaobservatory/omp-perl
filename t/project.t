#!perl

# Test OMP::Project class

use warnings;
use strict;
use Test;

BEGIN { plan tests => 21 }

use OMP::Project;
use OMP::User;

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
	       allocated => 3000,
	      );

# Instantiate a Project object
my $proj = new OMP::Project( %project );

ok($proj);

use Data::Dumper;
print Dumper($proj);

# Projet id should be case insensitive
ok( $proj->projectid, uc($project{projectid}));

# Check the password
ok( $proj->password, $project{password} );
ok( $proj->verify_password );
print "# Password: ", $proj->password, " Encrypted form: ", 
  $proj->encrypted, "\n";

# Check the CoI stuff

# First register the email addresses
my @coi = $proj->coi;
for my $i (0..$#coi) {
  $coi[$i]->email( $coiemail[$i]);
}


# should be 3 names either : delimited or in an array
ok( $proj->coi, uc($project{coi}) );
ok( scalar(@coi), 3);
ok( join("$OMP::Project::DELIM", map { lc($_->userid) } @coi), $project{coi});

my @email = $proj->coiemail;

for my $i (0.. $#coiemail) {
  ok( $email[$i], $coiemail[$i]);
}

ok( $proj->coiemail, join("$OMP::Project::DELIM", @coiemail));

# and investigators
ok( $proj->investigators, join("$OMP::Project::DELIM", $project{piemail},
			       @coiemail));

# Check the time allocation
print "# Time allocation\n";
ok( $proj->allocated, $project{allocated});
ok( $proj->remaining, $proj->allocated );
ok( $proj->used, 0.0 );

# Set some time pending
my $used = 360;
$proj->incPending( $used );
ok( $proj->pending, $used );
ok( $proj->used, $used );

ok( $proj->allRemaining, ($project{allocated} - $used));

$proj->consolidateTimeRemaining;
ok( $proj->used, $used );
ok( $proj->remaining, ($project{allocated} - $used));
ok( $proj->pending, 0.0);
