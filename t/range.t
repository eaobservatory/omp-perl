use strict;
use warnings;
use Test;
BEGIN { plan tests => 4 }

use OMP::Range;

my $r = new OMP::Range( Min => 5, Max => 20 );

# Easy
ok($r->min, 5);
ok($r->max, 20);
ok("$r","5-20");

# change range
$r->min( 30 );

ok("$r","<=20 and >=30" );

