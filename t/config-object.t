#!perl

# Test the behaviour of OMP::Config objects.

# Copyright (C) 2008 Science and Technology Facilities Council.
# All Rights Reserved.

# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation; either version 2 of the License, or (at your option) any later
# version.

# This program is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
# PARTICULAR PURPOSE. See the GNU General Public License for more details.

# You should have received a copy of the GNU General Public License along with
# this program; if not, write to the Free Software Foundation, Inc., 59 Temple
# Place, Suite 330, Boston, MA  02111-1307, USA

use Test::More tests => 23;
use File::Spec;

BEGIN {
  # location of test configurations
  $ENV{OMP_CFG_DIR} = File::Spec->rel2abs(File::Spec->catdir(File::Spec->curdir,
                                                             't', 'configs'
                                                            ));

  # Make sure hosts and domains are predictable
  $ENV{OMP_NOGETHOST} = 1;

}

BEGIN { use_ok( 'OMP::Config' ); }

my $class = 'OMP::Config' ;
my $obj = $class->new;

isa_ok( $obj, $class );

# Test compatibility mode of a class method call which is actually now an
# instance method call.
is($class->getData('scalar'), 'default', 'Test scalar key (class method call)');

is($obj->getData('scalar'), 'default', 'Test scalar key');

ok($class->getData('scalar') eq $obj->getData('scalar'),
    "Same scalar value (compatibility mode)"
  );

my @array = $obj->getData( 'array' );
is($array[2], 3, 'Same array entry');
ok( $array[2] == ($class->getData('array'))[2],
    'Same array entry'
  );

is($obj->getData('domain'), 'my', 'Test domain alias');
ok($obj->getData('domain') eq $class->getData('domain'),
    'Same domain alias'
  );

is($obj->getData('host'), 'myh', 'Test host alias');
ok( $obj->getData('host') eq $class->getData('host'),
    'Same host alias'
  );

is($obj->getData('dover'), 'fromdom', 'Override from domain');
ok( $obj->getData('dover') eq $class->getData('dover'),
    'Sam override from domain'
  );

is($obj->getData('hover'), 'fromh', 'Override from host');
ok( $obj->getData('hover') eq $class->getData('hover'),
    'Same override from host'
  );

is($obj->getData('password'), 'xxx', 'domain password');
ok( $obj->getData('password') eq $class->getData('password'),
    'Same domain password'
  );

is($obj->getData('hierarch.eso'), 'test', 'hierarchical keyword');
ok( $obj->getData('hierarch.eso') eq $class->getData('hierarch.eso'),
    'Same hierarchical keyword'
  );

is($obj->getData('over'), 'fromsite', 'Site config override');
ok( $obj->getData('over') eq $class->getData('over'),
    'Same site config override'
  );

is($obj->getData('database.server'), 'SYB', 'Site config override hierarchical');
ok( $obj->getData('database.server') eq $class->getData('database.server'),
    'Same site config override hierarchical'
  );
