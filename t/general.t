
# Test OMP::General

use Test;
BEGIN { plan tests => 8 }

use OMP::General;

my $year = 1999;
my $mon  = 1;
my $day  = 5;
my $hh   = 5;
my $mm   = 15;
my $sec  = 0.0;

my $input =  sprintf("%04d-%02d-%02dT%02d:%02d",
		     $year, $mon, $day, $hh, $mm);

print "# Input date: $input\n";

my $date = OMP::General->parse_date( $input );

ok( $date );

print "# Output date: $date\n";

# Compare
ok( $date->year, $year);
ok( $date->mon, $mon);
ok( $date->mday, $day);
ok( $date->hour, $hh);
ok( $date->min, $mm);
ok( $date->sec, $sec);

# Check that the object is UTC by using undocumented internal hack
ok( ! $date->[Time::Piece::c_islocal]);
