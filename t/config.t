#!perl

use Test::More tests => 10;
use File::Spec;

BEGIN {
  # location of test configurations
  $ENV{OMP_CFG_DIR} = File::Spec->rel2abs(File::Spec->catdir(File::Spec->curdir,
							     "t","configs"
							    ));

  # Make sure hosts and domains are predictable
  $ENV{OMP_NOGETHOST} = 1;

}

use OMP::Config;
my $c = "OMP::Config";

is($c->getData("scalar"), "default", "Test scalar key");

my @array = $c->getData("array");
is($array[2], 3, "Test array entry");

is($c->getData("domain"), "my", "Test domain alias");
is($c->getData("host"), "myh", "Test host alias");

is($c->getData("dover"),"fromdom","Override from domain");
is($c->getData("hover"),"fromh","Override from host");

is($c->getData("password"),"xxx","domain password");

is($c->getData("hierarch.eso"),"test","hierarchical keyword");

is($c->getData("over"),"fromsite","Site config override");
is($c->getData("database.server"),"SYB","Site config override hierarchical");

