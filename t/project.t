#!perl

# Test OMP::Project class

use warnings;
use strict;
use Test;

BEGIN { plan tests => 11 }

use OMP::Project;

# email address
my @coiemail = ( qw/email1 email2 email3 / );

# Project hash
my %project = (
	       password => "atest",
	       projectid => "M01Btj",
	       pi => "Joe Bloggs",
	       piemail => "joe\@jach.hawaii.edu",
	       coi => "name1:name2:name3",
	       coiemail => \@coiemail,
	      );

# Instantiate a Project object
my $proj = new OMP::Project( %project );

ok($proj);

# Projet id should be case insensitive
ok( $proj->projectid, uc($project{projectid}));

# Check the password
ok( $proj->password, $project{password} );
ok( $proj->verify_password );
print "# Password: ", $proj->password, " Encrypted form: ", 
  $proj->encrypted, "\n";

# Check the CoI stuff
# should be 3 names either : delimited or in an array
ok( $proj->coi, $project{coi} );
my @coi = $proj->coi;
ok( scalar(@coi), 3);
ok( join("$OMP::Project::DELIM", @coi), $project{coi});

my @email = $proj->coiemail;

for my $i (0.. $#coiemail) {
  ok( $email[$i], $coiemail[$i]);
}

ok( $proj->coiemail, join("$OMP::Project::DELIM", @coiemail));


