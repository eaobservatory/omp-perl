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

use Test::More tests => 15
    + 5   # Suffix combinations
    + 5;  # getDataSearchSuffixes

use File::Spec;

BEGIN {
    # location of test configurations
    $ENV{'OMP_CFG_DIR'} = File::Spec->rel2abs(File::Spec->catdir(
        File::Spec->curdir, 't', 'configs'));

    # Make sure hosts and domains are predictable
    $ENV{'OMP_NOGETHOST'} = 1;

    # Unset the OMP_SITE_CONFIG variable to prevent it overriding our settings.
    delete $ENV{'OMP_SITE_CONFIG'} if exists $ENV{'OMP_SITE_CONFIG'};
}

use OMP::Config;
use OMP::Error qw/:try/;
my $c = 'OMP::Config';

is($c->getData('scalar'), 'default', 'Test scalar key');

my @array = $c->getData('array');
is($array[2], 3, 'Test array entry');

is($c->getData('domain'), 'my', 'Test domain alias');
is($c->getData('host'), 'myh', 'Test host alias');

is($c->getData('dover'), 'fromdom', 'Override from domain');
is($c->getData('hover'), 'fromh', 'Override from host');

is($c->getData('password'), 'xxx', 'domain password');

is($c->getData('hierarch.eso'), 'test', 'hierarchical keyword');

is($c->getData('over'), 'fromsite', 'Site config override');
is($c->getData('database.server'), 'SYB', 'Site config override hierarchical');

is($c->getData('some_section.some_parameter'), '20', 'Direct query of some_parameter');

my $threw = 0;
try {
    $c->getDataSearch(
        'some_section.some_parameter_zzz',
        'some_section.some_parameter_www');
}
catch OMP::Error::BadCfgKey with {
    $threw = 1;
};
ok($threw, 'getDataSearch threw error for non-existent keys');

is($c->getDataSearch(
        'some_section.some_parameter_xxx',
        'some_section.some_parameter'),
    '40', 'getDataSearch first value');

is($c->getDataSearch(
        'some_section.some_parameter_zzz',
        'some_section.some_parameter'),
    '20', 'getDataSearch last value');

is($c->getDataSearch(
        'some_section.some_parameter_zzz',
        'some_section.some_parameter_yyy',
        'some_section.some_parameter_xxx',
        'some_section.some_parameter'),
    '10', 'getDataSearch second value');

# Test construction of suffix lists for use with getDataSearchSuffixes.
is_deeply(OMP::Config::_search_suffix_combinations([]), [
    [],
], 'Suffix combinations 0');

is_deeply(OMP::Config::_search_suffix_combinations([qw/a/]), [
    [qw/a/],
    [],
], 'Suffix combinations 1');

is_deeply(OMP::Config::_search_suffix_combinations([qw/a b/]), [
    [qw/a b/],
    [qw/b a/],
    [qw/a/],
    [qw/b/],
    [],
], 'Suffix combinations 2');

is_deeply(OMP::Config::_search_suffix_combinations([qw/a b c/]), [
    [qw/a b c/],
    [qw/a c b/],
    [qw/b a c/],
    [qw/b c a/],
    [qw/c a b/],
    [qw/c b a/],
    [qw/a b/],
    [qw/b a/],
    [qw/a c/],
    [qw/c a/],
    [qw/b c/],
    [qw/c b/],
    [qw/a/],
    [qw/b/],
    [qw/c/],
    [],
], 'Suffix combinations 3');

is_deeply(OMP::Config::_search_suffix_combinations([qw/a b c d/]), [
    [qw/a b c d/],
    [qw/a b d c/],
    [qw/a c b d/],
    [qw/a c d b/],
    [qw/a d b c/],
    [qw/a d c b/],
    [qw/b a c d/],
    [qw/b a d c/],
    [qw/b c a d/],
    [qw/b c d a/],
    [qw/b d a c/],
    [qw/b d c a/],
    [qw/c a b d/],
    [qw/c a d b/],
    [qw/c b a d/],
    [qw/c b d a/],
    [qw/c d a b/],
    [qw/c d b a/],
    [qw/d a b c/],
    [qw/d a c b/],
    [qw/d b a c/],
    [qw/d b c a/],
    [qw/d c a b/],
    [qw/d c b a/],
    [qw/a b c/],
    [qw/a c b/],
    [qw/b a c/],
    [qw/b c a/],
    [qw/c a b/],
    [qw/c b a/],
    [qw/a b d/],
    [qw/a d b/],
    [qw/b a d/],
    [qw/b d a/],
    [qw/d a b/],
    [qw/d b a/],
    [qw/a c d/],
    [qw/a d c/],
    [qw/c a d/],
    [qw/c d a/],
    [qw/d a c/],
    [qw/d c a/],
    [qw/b c d/],
    [qw/b d c/],
    [qw/c b d/],
    [qw/c d b/],
    [qw/d b c/],
    [qw/d c b/],
    [qw/a b/],
    [qw/b a/],
    [qw/a c/],
    [qw/c a/],
    [qw/a d/],
    [qw/d a/],
    [qw/b c/],
    [qw/c b/],
    [qw/b d/],
    [qw/d b/],
    [qw/c d/],
    [qw/d c/],
    [qw/a/],
    [qw/b/],
    [qw/c/],
    [qw/d/],
    [],
], 'Suffix combinations 4');

# Test getDataSearchSuffixes itself.
is($c->getDataSearchSuffixes('some_section.some_parameter'),
    '20', 'getDataSearchSuffixes no suffixes');

is($c->getDataSearchSuffixes('some_section.some_parameter', 'zzz', 'www'),
    '20', 'getDataSearchSuffixes none matching');

is($c->getDataSearchSuffixes('some_section.some_parameter', 'zzz', 'xxx', 'yyy'),
    '40', 'getDataSearchSuffixes first of those matching');

is($c->getDataSearchSuffixes('some_section.some_parameter', 'ttt', 'xxx', 'yyy'),
    '50', 'getDataSearchSuffixes two matching (most specific)');

is($c->getDataSearchSuffixes('some_section.some_parameter', 'ttt', 'zzz', 'yyy'),
    '60', 'getDataSearchSuffixes one matching');
