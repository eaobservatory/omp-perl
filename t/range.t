use strict;
use warnings;
use Test;
BEGIN { plan tests => 98 }

use OMP::Range;

my $r = new OMP::Range( Min => 5, Max => 20 );

# Easy
ok($r->min, 5);
ok($r->max, 20);
ok("$r","5-20");
ok(!$r->isinverted);

# Test an accessor
my @range = $r->minmax;
ok($range[0], 5);
ok($range[1], 20);
$r->minmax(10,30);
ok($r->min, 10);
ok($r->max, 30);
$r->minmax(@range);
ok($range[0], 5);
ok($range[1], 20);

# Specify some test particles
my @inside = (6,19.5,10);
my @outside = (-1,0,35,60);
for (@inside) {
  #print "# Testing contains: $_\n";
  ok($r->contains($_));
}
for (@outside) {
  #print "# Testing does not contain: $_\n";
  ok(!$r->contains($_));
}

# change range
$r->min( 30 );

ok("$r","<=20 and >=30" );
ok($r->isinverted);

# Test arrays
@inside = (0,-5,31,2406);
@outside = (21,29.56);

# inverted
for (@inside) {
  #print "# Testing contains: $_\n";
  ok($r->contains($_));
}
for (@outside) {
  #print "# Testing does not contain: $_\n";
  ok(!$r->contains($_));
}


# Unbound range
$r = new OMP::Range( Min => 5 );
ok($r->contains( 6 ));
ok(!$r->contains( 4 ));

$r = new OMP::Range( Max => 5 );
ok(!$r->contains( 6 ));
ok($r->contains( 4 ));


# Merging

print "# Merge 2 unbound ranges\n";
my $r1 = new OMP::Range( Max => 4 );
my $r2 = new OMP::Range( Min => 1 );

ok($r1->intersection($r2));
ok($r1->max, 4);
ok($r1->min, 1);

$r1 = new OMP::Range( Max => 4 );
$r2 = new OMP::Range( Min => 6 );

ok(!$r1->intersection($r2));
ok($r1->max, 4);
ok($r1->min, undef);

$r1 = new OMP::Range( Max => 4 );
$r2 = new OMP::Range( Max => 6 );

ok($r1->intersection($r2));
ok($r1->max, 6);
ok($r1->min, undef);

$r1 = new OMP::Range( Min => 1 );
$r2 = new OMP::Range( Max => 4 );

ok($r1->intersection($r2));
ok($r1->max, 4);
ok($r1->min, 1);

print "# Merge 2 bound ranges\n";
$r1 = new OMP::Range( Min => 1, Max => 5);
$r2 = new OMP::Range( Min => 2, Max => 4 );

ok($r1->intersection($r2));
ok($r1->max, 4);
ok($r1->min, 2);

$r1 = new OMP::Range( Min => 1, Max => 5);
$r2 = new OMP::Range( Min => 6, Max => 20 );

ok(!$r1->intersection($r2));
ok($r1->max, 5);
ok($r1->min, 1);

print "# Merge 1 bound and 1 unbound\n";
$r1 = new OMP::Range( Min => 1, Max => 5);
$r2 = new OMP::Range( Min => 2 );

ok($r1->intersection($r2));
ok($r1->max, 5);
ok($r1->min, 2);

$r1 = new OMP::Range( Min => 1, Max => 5);
$r2 = new OMP::Range( Min => 0 );

ok($r1->intersection($r2));
ok($r1->max, 5);
ok($r1->min, 1);

$r1 = new OMP::Range( Min => 1, Max => 5);
$r2 = new OMP::Range( Max => 3 );

ok($r1->intersection($r2));
ok($r1->max, 3);
ok($r1->min, 1);

$r1 = new OMP::Range( Min => 1, Max => 5);
$r2 = new OMP::Range( Max => 6 );

ok($r1->intersection($r2));
ok($r1->max, 5);
ok($r1->min, 1);

$r1 = new OMP::Range( Min => 1, Max => 5);
$r2 = new OMP::Range( Min => 6 );

ok(!$r1->intersection($r2));
ok($r1->max, 5);
ok($r1->min, 1);

# and finally reverse the inputs
$r2 = new OMP::Range( Min => 1, Max => 5);
$r1 = new OMP::Range( Max => 6 );

ok($r1->intersection($r2));
ok($r1->max, 5);
ok($r1->min, 1);

print "# 2 inverted ranges\n";

$r2 = new OMP::Range( Max => 1, Min => 5);
$r1 = new OMP::Range( Max => 6, Min => 8 );

ok($r1->intersection($r2));
ok($r1->max, 1);
ok($r1->min, 8);

print "# 1 inverted and 1 bound\n";

$r1 = new OMP::Range( Max => 1, Min => 5);
$r2 = new OMP::Range( Min => 2, Max => 3 );

ok(!$r1->intersection($r2));
ok($r1->max, 1);
ok($r1->min, 5);

$r1 = new OMP::Range( Max => 1, Min => 5);
$r2 = new OMP::Range( Min => -4, Max => -3 );

ok($r1->intersection($r2));
ok($r1->max, -3);
ok($r1->min, -4);

$r1 = new OMP::Range( Max => 1, Min => 5);
$r2 = new OMP::Range( Min => -4, Max => 3 );

ok($r1->intersection($r2));
ok($r1->max, 1);
ok($r1->min, -4);

$r1 = new OMP::Range( Max => 1, Min => 5);
$r2 = new OMP::Range( Min => -4, Max => 7 );

eval { $r1->intersection($r2)};
ok($@ =~ /two/);

$r1 = new OMP::Range( Max => 1, Min => 5);
$r2 = new OMP::Range( Min => 3, Max => 7 );

ok($r1->intersection($r2));
ok($r1->max, 7);
ok($r1->min, 5);

$r1 = new OMP::Range( Max => 1, Min => 5);
$r2 = new OMP::Range( Min => 6, Max => 7 );

ok($r1->intersection($r2));
ok($r1->max, 7);
ok($r1->min, 6);


print "# 1 inverted and 1 unbound\n";


# Need to test both upper and lower limits
# Test max
$r1 = new OMP::Range( Max => 1, Min => 5);
$r2 = new OMP::Range( Max => 6 );

eval { $r1->intersection($r2) };
ok( $@ =~ /two/ );

$r1 = new OMP::Range( Max => 1, Min => 5);
$r2 = new OMP::Range( Max => -5 );

ok($r1->intersection($r2));
ok($r1->max, -5);
ok($r1->min, 5);

$r1 = new OMP::Range( Max => 1, Min => 5);
$r2 = new OMP::Range( Max => 3.6 );

ok($r1->intersection($r2));
ok($r1->max, 1);
ok($r1->min, 5);

# Test Min
$r1 = new OMP::Range( Max => 1, Min => 5);
$r2 = new OMP::Range( Min => 6 );

ok($r1->intersection($r2));
ok($r1->max, 1);
ok($r1->min, 6);

$r1 = new OMP::Range( Max => 1, Min => 5);
$r2 = new OMP::Range( Min => -5 );

eval { $r1->intersection($r2) };
ok( $@ =~ /two/ );

$r1 = new OMP::Range( Max => 1, Min => 5);
$r2 = new OMP::Range( Min => 3.6 );

ok($r1->intersection($r2));
ok($r1->max, 1);
ok($r1->min, 5);


