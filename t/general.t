
# Test OMP::General

use Test;
BEGIN { plan tests => 27 }

use OMP::General;

my $year = 1999;
my $mon  = 1;
my $mon_str = "Jan";
my $day  = 5;
my $hh   = 5;
my $mm   = 15;
my $sec  = 0.0;

# Create two input dates. One in ISO format, the other in
# Sybase style
my @input;

# ISO
push(@input,  sprintf("%04d-%02d-%02dT%02d:%02d",
		     $year, $mon, $day, $hh, $mm));

# Sybase
push(@input,  sprintf("$mon_str %02d %04d  %d:%02dAM",
		      $day, $year, $hh, $mm));

print "# parse_date\n";

print "# Input date: $input[0]\n";

for my $in (@input) {

  $date = OMP::General->parse_date( $in );

  ok( $date );

  unless (defined $date) {
    print "# Skipping tests since we returned undef\n";
    for (1..7) { ok(0) };
    next;
  }

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
}

print "# today()\n";

my $today = OMP::General->today;
ok( $today =~ /^\d\d\d\d-\d\d-\d\d$/ );

print "# Verification\n";

# At least test that we fail to match the admin password
# (after always matching for some time!)
ok( ! OMP::General->verify_administrator_password( "blah", 1 ) );

print "# Semester\n";

my $refdate = OMP::General->parse_date($input[0]);
my $sem = OMP::General->determine_semester( $refdate );
ok($sem, "98b");

$date = gmtime(1014756003); # 2002-02-26
ok( OMP::General->determine_semester($date), "02a");

$date = gmtime(1028986003); # 2002-08-10
ok( OMP::General->determine_semester($date), "02b");

print "# Project ID\n";

my @input = (
	     {
	      semester => "01b",
	      projectid => "3",
	      result => "u/01b/03",
	     },
	     {
	      projectid => "u04",
	      semester => "02a",
	      result => "m02au04",
	     },
	     {
	      projectid => "h01",
	      semester => "02a",
	      telescope => "jcmt",
	      result => "m02ah01",
	     },
	     {
	      projectid => "h01",
	      semester => "02a",
	      telescope => "ukirt",
	      result => "u/02a/h01",
	     },
	     {
	      projectid => "H1",
	      semester => "02a",
	      telescope => "ukirt",
	      result => "u/02a/H01",
	     },
	     {
	      projectid => "22",
	      semester => "99a",
	      result => "u/99a/22",
	     },
	     {
	      projectid => "m01bu52",
	      result => "m01bu52",
	     },
	     {
	      projectid => "u/01b/52",
	      result => "u/01b/52",
	     },
	     {
	      projectid => "u/serv/52",
	      result => "u/serv/52",
	     },
	     {
	      projectid => "s1",
	      result => "u/serv/01",
	     },
	     {
	      projectid => "s4565",
	      result => "u/serv/4565",
	     },
	     {
	      projectid => "thk1",
	      result => "thk01",
	     },
	     {
	      projectid => "tj125",
	      result => "tj125",
	     }



	    );

for my $input (@input) {
  ok( OMP::General->infer_projectid(%$input), $input->{result});
}

# Test the failure when we cant decide which telescope
eval {
  OMP::General->infer_projectid( projectid => "h01"  );
};
ok( $@ =~ /Unable to determine telescope from supplied project ID/ );
