
# Test OMP::Fault

use Test;
BEGIN { plan tests => 5 }
use strict;
use OMP::Fault;
use OMP::Fault::Response;


# First create the first "response"
my $resp = new OMP::Fault::Response( user => "AJA",
				     text => "This is a test of the fault classes");

ok( $resp );


# Now file a fault
my $fault = new OMP::Fault(
			   category => "UKIRT",
			   fault    => $resp,
			  );

ok( $fault );


# Now respond
my $resp2 = new OMP::Fault::Response( user => "TIMJ",
				      text => "I respond to you");

$fault->responses( $resp2 );

my @resps = $fault->responses;
ok( scalar(@resps), 2);

# Check primary flags
ok( $resps[0]->primary );
ok( ! $resps[1]->primary );


# Print the stringified fault for info
# Need to prepend #
my $string = "$fault";
my @lines = split("\n", $string);
$string = join("", map { "#$_\n"} @lines);
print $string;
