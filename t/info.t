#!perl

# Test the info classes

use Test::More tests => 42;

require_ok( 'OMP::Info::Base' );
require_ok( 'OMP::Info::Obs' );
require_ok( 'OMP::Info::MSB' );
require_ok( 'OMP::Info::Comment' );

print "# Test base class\n";

my $base = new OMP::Info::Test;
ok( $base, 'Test info');
is($base->scalar(5),5, "test scalar");
eval { $base->scalar({})};
ok( $@, "scalar with ref" );

is($base->anyscalar(5),5, "test anyscalar");
is($base->anyscalar(\$base),\$base, "test anyscalar");
my $href = {};
is($base->anyscalar($href), $href, "test anyscalar");

is($base->downcase("HELLO"), "hello", "downcase");
is($base->upcase("hello"), "HELLO", "upcase");
eval { $base->upcase($href) };
ok($@, "upcase with ref");
eval { $base->downcase($href) };
ok($@, "downcase with ref");

# Array
my @test = (1,2,3,4,5);
ok($base->array(@test),"array as list");
is(scalar(@{$base->array}), scalar(@test), "test count");
is_deeply(scalar($base->array), \@test, "compare array");
ok($base->array(\@test), "array as ref");
is(scalar(@{$base->array}), scalar(@test), "test count");
my @test_out = $base->array;
is(scalar(@test_out), scalar(@test), "test count (list)");
is_deeply(\@test_out, \@test, "compare array");

# Hash
my %htest = ( a => 1, b=> 2);
ok($base->hash(%htest),"hash as list");
is(scalar(%{$base->hash}), scalar(%htest), "test count");
is_deeply(scalar($base->hash), \%htest, "compare hash");
ok($base->hash(\%htest), "hash as ref");
is(scalar(%{$base->hash}), scalar(%htest), "test count");
my %htest_out = $base->hash;
is(scalar(%htest_out), scalar(%htest), "test count (list)");

is_deeply(\%htest_out, \%htest, "compare hash");

# Single object
my $obj = bless {}, "Blah2";
is($base->singleobj($obj),$obj, "Test object");
eval { $base->singleobj("a")};
ok($@, "test with scalar");
my $obj2 = bless {}, "Blah";
eval { $base->singleobj($obj2)};
ok($@, "test with incorrect object");

# Array object
my @blah = map { bless {}, "Blah" } (1..10);
my @blah2 = map { bless {}, "Blah3" } (1..10);

ok( $base->arrayobj(@blah), "array object" );
is_deeply( scalar($base->arrayobj), \@blah, "test contents");

eval {$base->arrayobj(@blah2) };
ok($@, "test with incorrect array object");
eval {$base->arrayobj(1..10) };
ok($@, "test with incorrect array contents");

# Hash object
my %blah2 = map { $_, $blah2[$_] } (0..$#blah2);
ok( $base->hashobj(%blah2), "hash object");
is_deeply( scalar($base->hashobj), \%blah2, "test contents");

eval { $base->hashobj( a => 2 ) };
ok($@, "incorrect hash contents");



print "# Test obs and msb\n";
my $obs = new OMP::Info::Obs( instrument => 'CGS4');
ok($obs, "CGS4 obs");

my $obs2 = new OMP::Info::Obs( instrument => 'IRCAM');
ok($obs2, "IRCAM obs");

my $msb = new OMP::Info::MSB(
			     checksum => 'ffff',
			     cloud => OMP::Range->new(Min=>0,Max=>101),
			     tau => OMP::Range->new(Min=>0.08,Max=>0.15),
			     seeing => OMP::Range->new(Min=>1,Max=>10),
			     priority => 2,
			     projectid => 'SERV01',
			     remaining => 1,
			     telescope => 'UKIRT',
			     timeest => 22.5,
			     title => 'Test suite',
			     observations => [ $obs,$obs2 ],
			     msbid => 23,
			    );

ok($msb, "MSB");
is($msb->obscount, 2, "check obscount");
