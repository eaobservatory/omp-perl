
# Test OMP::General

use Test::More tests => 173;

use Time::Piece qw/ :override /;
use Time::Seconds;

require_ok('OMP::General');

my $year = 1999;
my $mon  = 1;
my $mon_str = "Jan";
my $day  = 5;
my $hh   = 5;
my $mm   = 15;
my $sec  = 0.0;

# Create two input dates. One in ISO format, the other in
# Sybase style
my @dateinput;

# ISO
push(@dateinput,  sprintf("%04d-%02d-%02dT%02d:%02d",
	   	     $year, $mon, $day, $hh, $mm));

# Sybase
push(@dateinput,  sprintf("$mon_str %02d %04d  %d:%02dAM",
		      $day, $year, $hh, $mm));

print "# parse_date\n";

print "# Input date: $dateinput[0]\n";

for my $in (@dateinput) {

  $date = OMP::General->parse_date( $in );

  ok( $date, "Instantiate a Time::Piece object" );
  isa_ok($date, "Time::Piece");

  unless (defined $date) {
    print "# Skipping tests since we returned undef\n";
    for (1..7) { ok(0) };
    next;
  }

  print "# Output date: $date\n";

  # Compare
  is( $date->year, $year, "Check year");
  is( $date->mon, $mon, "Check month");
  is( $date->mday, $day, "Check day");
  is( $date->hour, $hh, "Check hour");
  is( $date->min, $mm, "Check minute");
  is( $date->sec, $sec, "Check second");

  # Check that the object is UTC by using undocumented internal hack
  ok( ! $date->[Time::Piece::c_islocal], "Check we have utc date");
}

# Check that we get a UT date from a localtime object
print "# Parse a Time::Piece object that is a local time\n";
my $local = localtime( $date->epoch );
my $newdate = OMP::General->parse_date( $local );
# Compare
is( $newdate->year, $year, "Check year");
is( $newdate->mon, $mon, "Check month");
is( $newdate->mday, $day, "Check day");
is( $newdate->hour, $hh, "Check hour");
is( $newdate->min, $mm, "Check minute");
is( $newdate->sec, $sec, "Check second");

# Check that the object is UTC by using undocumented internal hack
ok( ! $newdate->[Time::Piece::c_islocal], "Check we have utc date");

# Generate a local time and verify we get back the correct UT
print "# Parse a local time\n";
my $localiso = $local->datetime;
ok( $local->[Time::Piece::c_islocal], "Check we have local date");
$newdate = OMP::General->parse_date( $localiso, 1);
# Compare
is( $newdate->year, $year, "Check year");
is( $newdate->mon, $mon, "Check month");
is( $newdate->mday, $day, "Check day");
is( $newdate->hour, $hh, "Check hour");
is( $newdate->min, $mm, "Check minute");
is( $newdate->sec, $sec, "Check second");

# Check that the object is UTC by using undocumented internal hack
ok( ! $newdate->[Time::Piece::c_islocal], "Check we have utc date");


print "# today() and yesterday\n";

my $today = OMP::General->today;
like( $today, qr/^\d\d\d\d-\d\d-\d\d$/, "Test that date is ISO format" );

# And yesterday
my $yesterday = OMP::General->yesterday;
like( $yesterday, qr/^\d\d\d\d-\d\d-\d\d$/, "Test that date is ISO format" );

# Now using objects
$today = OMP::General->today(1);
isa_ok( $today, "Time::Piece" );
$yesterday = OMP::General->yesterday(1);
isa_ok( $yesterday, "Time::Piece" );

# Check that we have 0 hms
is($today->hour,0,"Zero hours");
is($today->min,0,"Zero minutes");
is($today->sec,0,"Zero seconds");
is($yesterday->hour,0,"Zero hours");
is($yesterday->min,0,"Zero minutes");
is($yesterday->sec,0,"Zero seconds");

# And we have one day between them
my $diff = $today - $yesterday;
isa_ok($diff, "Time::Seconds");
is($diff, ONE_DAY, "Check time difference");

print "# UT date determination\n";

# See if we get today
my $detut = OMP::General->determine_utdate();
is($detut->epoch, $today->epoch, "Blank should be today");

$detut = OMP::General->determine_utdate("blah");
is($detut->epoch, $today->epoch, "Unparsable should be today");

# Now force a parse
$detut = OMP::General->determine_utdate( $yesterday->ymd );
is($detut->epoch, $yesterday->epoch, "Parse a Y-M-D");

# and include hms
$detut = OMP::General->determine_utdate( $yesterday->ymd ."T04:40:34" );
is($detut->epoch, $yesterday->epoch, "Parse a Y-M-DTH:M:S");


print "# Verification\n";

# At least test that we fail to match the admin password
# (after always matching for some time!)
ok( ! OMP::General->verify_administrator_password( "blah", 1 ),
  "Check that we fail to verify the admin password");

print "# Semester\n";

my $refdate = OMP::General->parse_date($dateinput[0]);
my $sem = OMP::General->determine_semester( $refdate );
is($sem, "98b","Check semester 98b");

$date = gmtime(1014756003); # 2002-02-26
isa_ok( $date, "Time::Piece");
is( OMP::General->determine_semester($date), "02a", "Check semester 02a");

$date = gmtime(1028986003); # 2002-08-10
is( OMP::General->determine_semester($date), "02b","Check semesters 02b");

print "# Project ID\n";

my @input = (
	     {
	      semester => "01b",
	      projectid => "03",
	      result => "u/01b/3",
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
	      result => "u/02a/h1",
	     },
	     {
	      projectid => "H1",
	      semester => "02a",
	      telescope => "ukirt",
	      result => "u/02a/H1",
	     },
	     {
	      projectid => "j28",
	      semester => "02a",
	      telescope => "ukirt",
	      result => "u/02a/j28",
	     },
	     {
	      projectid => "j4",
	      semester => "02a",
	      telescope => "ukirt",
	      result => "u/02a/j4",
	     },
	     {
	      projectid => "j04",
	      semester => "03b",
	      telescope => "ukirt",
	      result => "u/03b/j4",
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
	      result => "u/serv/1",
	     },
	     {
	      projectid => "s04",
	      result => "u/serv/4",
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
	     },
	     {
	      projectid => "UKIRTCAL",
	      result => "UKIRTCAL",
	     },
	     {
	      # MEGA survey
	      projectid => "SX_30EW_LO",
	      result => "SX_30EW_LO",
	     },
	     {
	      # MEGA survey
	      projectid => "LX_30EW_LO",
	      result => "LX_30EW_LO",
	     },
	     # JCMT service
	     {
	      projectid => "s01bc03",
	      result => "s01bc03",
	     },
	     {
	      projectid => 'nls0003',
	      result    => 'nls0003',
	     },
	     {
	      projectid => "s02au03",
	      result => "s02au03",
	     },
	     {
	      projectid => "s02ai03",
	      result => "s02ai03",
	     },
	     {
	      projectid => "si03",
	      semester => '02a',
	      result => "s02ai03",
	     },
	     {
	      projectid => "sc22",
	      semester => '00b',
	      result => "s00bc22",
	     },
	     {
	      projectid => "su15",
	      semester => '02b',
	      result => "s02bu15",
	     },

	     # JCMT calibrations
	     {
	      projectid => "MEGACAL",
	      result => "MEGACAL",
	     },
	     {
	      projectid => "JCMTCAL",
	      result => "JCMTCAL",
	     },
	     {
	      projectid => 'm02bh37a2',
	      result => 'm02bh37a2',
	     },
	     {
	      projectid => 'm03ad07b',
	      result => 'm03ad07b',
	     },
	     {
	      projectid => 'm04bu35a',
	      result=>'m04bu35a',
	     }
	    );

for my $input (@input) {
  is( OMP::General->infer_projectid(%$input), $input->{result},
    "Verify projectid is " . $input->{result} . " from ".
    $input->{projectid});
}

# Test the failure when we cant decide which telescope
eval {
  OMP::General->infer_projectid( projectid => "h01"  );
};
like( $@, qr/Unable to determine telescope from supplied project ID/,
    "Verify ambiguity");


# Band allocations
print "# Band determination\n";

# first none
is(OMP::General->determine_band, 0, "Band 0");

# Now UKIRT
is(OMP::General->determine_band(TELESCOPE => 'UKIRT'), 0, "Band 0 UKIRT");

# And JCMT
my %bands = (
	     0.03 => 1,
	     0.05 => 1,
	     0.07 => 2,
	     0.08 => 2,
	     0.1  => 3,
	     0.12 => 3,
	     0.15 => 4,
	     0.2  => 4,
	     0.25 => 5,
	     0.4  => 5,
	    );

for my $cso (keys %bands) {
  is(OMP::General->determine_band(TELESCOPE => 'JCMT',
				  TAU => $cso), $bands{$cso},
    "Verify band for tau $cso");
}

# Test out of range
eval { OMP::General->determine_band(TELESCOPE=>'JCMT',TAU=> undef) };
ok($@,"Got error ok");
like($@, qr/not defined/,"not defined");

eval { OMP::General->determine_band(TELESCOPE=>'JCMT',TAU=>-0.05) };
ok($@, "Got error okay");
like($@, qr/out of range/,"out of range");


eval { OMP::General->determine_band(TELESCOPE=>'JCMT') };
ok($@,"Got error okay");
like($@, qr/without TAU/,"Without TAU");

# Band ranges
my $range = OMP::General->get_band_range('JCMT', 2,3);
isa_ok($range, "OMP::Range","Make sure we get Range object Band 2,3");
is($range->max,0.12);
is($range->min,0.05);

$range = OMP::General->get_band_range('JCMT',1);
isa_ok($range, "OMP::Range","Make sure we get Range object Band 1");
is($range->max,0.05);
is($range->min,0.0);

$range = OMP::General->get_band_range( 'JCMT', 4,5);
isa_ok($range, "OMP::Range","Make sure we get range object Band 4,5");
is($range->max,undef);
is($range->min,0.12);

# Projectid extraction
my %extract = (
	       'u/SERV/192' => 'project u/SERV/192 is complete',
	       'u/02a/55'   => '[u/02a/55]',
	       'u/03b/h6a'  => '[u/03b/h6a]',
	       'u/02b/h55'  => 'MAIL: [u/02b/h55] is complete',
	       'U/03A/J4'   => 'a Japanese ukirt project U/03A/J4',
	       's02ac03'    => '[s02ac03]',
	       's02au03'    => '[s02au03]',
	       's02ai03'    => '[s02ai03]',
	       'm02au52'    => '[m02au52]',
	       'm02an52'    => '[m02an52]',
	       'm02ac52'    => '[m02ac52]',
	       'm02ai52'    => '[m02ai52]',
	       'm00bh52'    => '[m00bh52]',
	       'nls0010'    => '[nls0010]',
	       'LX_68EW_HI' => '[LX_68EW_HI]',
	       'SX_44EW_MD' => '[SX_44EW_MD] blah',
	       'MEGACAL'    => '[MEGACAL]',
	       'JCMTCAL'    => '[JCMTCAL]',
	       'ukirtcal'   => '[ukirtcal] blah di blah',
	       'tj03'       => 'hello tj03',
	       'thk125'     => 'this is [thk125]',
	       'm02bh37b1'  => 'this is uh project m02bh37b1',
	       'M02BH07A3'  => 'this is uh project M02BH07A3',
	       'M00AH06A'  => 'this is uh project M00AH06A',
               'm02bec03'  => 'this is E&C m02bec03 project',
               'm02bd01'   => 'm02bd01 is a DDT project',
               'u/02b/d03' => 'u/02b/d03 is a UKIRT DDT project',
	       'm03au05fb' => 'a fallback project: m03au05fb',
	       'u/ec/1'    => 'A UKIRT E&C project u/ec/1',
               'm03ad07a'  => 'A JCMT DDT project m03ad07a',
	       'm03bu135d' => 'A fallback project m03bu135d of a different type',
	      );

for my $proj (keys %extract) {
  my $output = OMP::General->extract_projectid($extract{$proj});
  is($output, $proj, "Extract $proj from string");
}

# some failures
my @fail = (qw/ [su03] [sc04] [s06] /);
for my $string (@fail) {
  is(OMP::General->extract_projectid($string), undef, "Test failure of project extraction");
}

print "# String splitting\n";
my $sstring = 'foo bar baz';
is(OMP::General->split_string($sstring), 3, 'Split simple string');

$sstring = 'foo bar "baz xyz" xyzzy';
is(OMP::General->split_string($sstring), 4, 'Split complicated string');

my @compare_string = ('baz xyz',
		      'xyz zyx',
		      'foo',
                      'bar',
                      'corgy',
		      '"',
		      'waldo',);

$sstring = 'foo bar "baz xyz" corgy "xyz zyx" " waldo';

is_deeply([OMP::General->split_string($sstring)],
	  \@compare_string,
	  "Split string with odd number of double-quotes");

print "# HTML entity replacement\n";
$sstring = '&quot;foo &amp; bar&quot;';
is(OMP::General->replace_entity($sstring),'"foo & bar"', 'Replace entities in simple string');

my @compare_ent = ('<','>','"','&',);
is_deeply([split(/\s+/,OMP::General->replace_entity('&lt; &gt; &quot; &amp;'))],
	  \@compare_ent,
	  "Replace all known entities");

print "# Extended time\n";

my ($projtime,$extend) = OMP::General->determine_extended( 
							  tel => 'JCMT',
							  start => '2002-12-10T03:20',
							  duration => 1800,
							  freetimeut => ['03:30','19:30'],
							 );
is($projtime->seconds, 1200, "Check project time");
is($extend->seconds, 600, "Check extended time");

($projtime,$extend) = OMP::General->determine_extended( 
							  tel => 'JCMT',
							  start => '2002-12-10T02:20',
							  duration => 1800,
							  freetimeut => ['03:30','19:30'],
							 );
is($projtime->seconds, 0, "Check project time");
is($extend->seconds, 1800, "Check extended time");

($projtime,$extend) = OMP::General->determine_extended( 
							  tel => 'JCMT',
							  start => '2002-12-10T05:20',
							  duration => 1800,
							  freetimeut => ['03:30','19:30'],
							 );
is($projtime->seconds, 1800, "Check project time");
is($extend->seconds, 0, "Check extended time");

($projtime,$extend) = OMP::General->determine_extended( 
							  tel => 'JCMT',
							  start => '2002-12-10T19:20',
							  duration => 1800,
							  freetimeut => ['03:30','19:30'],
							 );
is($projtime->seconds, 600, "Check project time");
is($extend->seconds, 1200, "Check extended time");

($projtime,$extend) = OMP::General->determine_extended( 
							  tel => 'JCMT',
							  start => '2002-12-10T20:20',
							  duration => 1800,
							  freetimeut => ['03:30','19:30'],
							 );
is($projtime->seconds, 0, "Check project time");
is($extend->seconds, 1800, "Check extended time");

# Now test the alternative options
($projtime,$extend) = OMP::General->determine_extended( 
							  tel => 'JCMT',
							  start => '2002-12-10T03:20',
							  end => '2002-12-10T03:50',
							  freetimeut => ['03:30','19:30'],
							 );
is($projtime->seconds, 1200, "Check project time");
is($extend->seconds, 600, "Check extended time");

($projtime,$extend) = OMP::General->determine_extended( 
							  tel => 'JCMT',
							  end => '2002-12-10T03:50',
							  duration => 1800,
							  freetimeut => ['03:30','19:30'],
							 );
is($projtime->seconds, 1200, "Check project time");
is($extend->seconds, 600, "Check extended time");

print "# Convert text to HTML format\n";
my $pstring = "<foo bar=\"baz\"><&>";
is(OMP::General->preify_text($pstring),'<pre>&lt;foo bar=&quot;baz&quot;&gt;&lt;&amp;&gt;</pre>', 'Escape HTML in string');

my @compare_pre = ('<pre>&lt;','&gt;','&amp;</pre>');
is_deeply([split(/\s+/,OMP::General->preify_text("< > &"))],
	  \@compare_pre,
	  "Make sure that ampersands in escape sequences aren't escaped");

$pstring = "<htMl>html formatted string";
is(OMP::General->preify_text($pstring),'html formatted string','Strip out beginning <html> string');

print "# HTML to plaintext\n";
my $html = "<strong>Hello<br>there</strong>";
is(OMP::General->html_to_plain($html),"Hello\nthere\n", "Convert BR to newline");

$html = "<a href='ftp://ftp.jach.hawaii.edu/'>FTP link</a>";
is(OMP::General->html_to_plain($html),"FTP link [ftp://ftp.jach.hawaii.edu/]\n", "Display hyperlink URL");

#$html = "<a href='http://www.jach.hawaii.edu/index.html' class='biglink'>Home</a>";
#is(OMP::General->html_to_plain($html),"Home [http://www.jach.hawaii.edu/index.html]\n", "Display hyperlink URL but not other hyperlink attributes");
