#!perl

# Test the behaviour of OMP::Config objects.

# Copyright (C) 2002-2005 Particle Physics and Astronomy Research Council.
# All Rights Reserved.

# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation; either version 2 of the License, or (at your option) any later
# version.

# This program is distributed in the hope that it will be useful,but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
# PARTICULAR PURPOSE. See the GNU General Public License for more details.

# You should have received a copy of the GNU General Public License along with
# this program; if not, write to the Free Software Foundation, Inc., 59 Temple
# Place,Suite 330, Boston, MA  02111-1307, USA

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

