#!perl

# Test the info classes

use Test;
BEGIN { plan tests => 2 }
use OMP::Info::MSB;
use OMP::Info::Obs;
use OMP::Info::Comment;
use Data::Dumper;

ok(1);

my $obs = new OMP::Info::Obs( instrument => 'CGS4');
my $obs2 = new OMP::Info::Obs( instrument => 'IRCAM');

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

ok($msb->obscount, 2);
