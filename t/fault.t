
# Test OMP::Fault

use Test;
BEGIN { plan tests => 3 }
use strict;
use OMP::Fault;
use OMP::Fault::Response;


# First create the first "response"
my $resp = new OMP::Fault::Response( "AJA",
				     "This is a test of the fault classes");

ok( $resp );


# Now file a fault
my $fault = new OMP::Fault(
			   category => "UKIRT",
			   fault    => $resp,
			  );

ok( $fault );


# Now respond
my $resp2 = new OMP::Fault::Response( "TIMJ",
				      "I respond to you");

$fault->responses( $resp2 );

my @resps = $fault->responses;
ok( scalar(@resps), 2);

print $fault;
