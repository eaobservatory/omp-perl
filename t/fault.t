
# Test OMP::Fault

use Test::More tests => 11;
use strict;
require_ok("OMP::User");
require_ok("OMP::Fault");
require_ok("OMP::Fault::Response");


# First create the first "response"
my $author = new OMP::User( userid => "AJA",
	                    name   => "Andy Adamson");
isa_ok($author, "OMP::User");

my $resp = new OMP::Fault::Response( author => $author,
				     text => "This is a test of the fault classes");

ok( $resp, "response object created" );
isa_ok( $resp,"OMP::Fault::Response");

# Now file a fault
my $fault = new OMP::Fault(
			   category => "UKIRT",
			   fault    => $resp,
			  );

ok( $fault, "Fault object created" );
isa_ok($fault, "OMP::Fault");

# Now respond
my $author2 = new OMP::User( userid => "TIMJ",
	                     name   => "Tim Jenness");
my $resp2 = new OMP::Fault::Response( author => $author2,
				      text => "I respond to you");

$fault->responses( $resp2 );

my @resps = $fault->responses;
is( scalar(@resps), 2, "Count responses");

# Check isfault flags
ok( $resps[0]->isfault, "check first is a fault" );
ok( ! $resps[1]->isfault, "second response is not a fault" );


# Print the stringified fault for info
# Need to prepend #
my $string = "$fault";
my @lines = split("\n", $string);
$string = join("", map { "#$_\n"} @lines);
print $string;
