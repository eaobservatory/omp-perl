#!perl

# Test the OMP::SciProg class
# and the related MSB classes. Does not interact with the database.

use warnings;
use strict;
use Test;

BEGIN { plan tests => 22 }

use OMP::SciProg;

# The MSB summary is indexed by checksum
# This information needs to change if the Science program
# is modified
my %results = (
	       '38dc5ccd06862f24bca0c18257d3b13aA'  => 1,
	       '9d96e30de1b6cb6a2e06f793fa85da49'   => 2 ,
	       'c0add034d39c866fe01f92203d8a470d'   => 2,
	       'dfe282baeba181e3a6e5433711fd7286'   => 1,
	       '09a49ff69bc1facf1741f40690eb9fddOA' => 1,
	       '86fcce791167f6001afbba2c4758a67bOA' => 1,
	       '0ff472509ce854839965add501651718O'  => 1,
	       '210b74070afcc4b6f5e704edcebb033bO'  => 2,
	       'daaf4147b757592f3ebc07b40b48565dO'  => 1,
	      );

# Filename - use the test XML that covers all the bases
my $file = "test.xml";

my $obj = new OMP::SciProg( FILE => $file );

ok($obj);

# Check the project ID
ok($obj->projectID, "M01BTJ");

# Now count the number of MSBs
# Should be 9
my @msbs = $obj->msb;
ok(scalar(@msbs), 9);

# Go through the MSBs to see what we can find out about them
for my $msb ($obj->msb) {
  if (exists $results{$msb->checksum}) {
    ok(1);
    ok( $msb->remaining, $results{$msb->checksum});
  } else {
    ok(0);
    # skip the next few tests
    skip("Pointless testing MSB when checksum does not match",1);
  }
}

# Generate a summary
my @summary = $obj->summary;

# make sure the number of summaries matches the number of msbs
# + header
ok( scalar(@summary), 1+scalar(@msbs));

# For information print them all out
# Need to include the "#"
print map { "#$_\n" } @summary;

exit;
