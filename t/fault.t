
# Test OMP::Fault

use Test;
BEGIN { plan tests => 5 }
use strict;
use OMP::User;
use OMP::Fault;
use OMP::Fault::Response;


# First create the first "response"
my $author = new OMP::User( userid => "AJA",
	                    name   => "Andy Adamson");
my $resp = new OMP::Fault::Response( author => $author,
				     text => "This is a test of the fault classes");

ok( $resp );


# Now file a fault
my $fault = new OMP::Fault(
			   category => "UKIRT",
			   fault    => $resp,
			  );

ok( $fault );


# Now respond
my $author2 = new OMP::User( userid => "TIMJ",
	                     name   => "Tim Jenness");
my $resp2 = new OMP::Fault::Response( author => $author2,
				      text => "I respond to you");

$fault->responses( $resp2 );

my @resps = $fault->responses;
ok( scalar(@resps), 2);

# Check isfault flags
ok( $resps[0]->isfault );
ok( ! $resps[1]->isfault );


# Print the stringified fault for info
# Need to prepend #
my $string = "$fault";
my @lines = split("\n", $string);
$string = join("", map { "#$_\n"} @lines);
print $string;
