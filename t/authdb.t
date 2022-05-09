#!perl

use strict;
use Test::More tests => 2;

use OMP::AuthDB;

is(OMP::AuthDB::_duration_description('remember'), '+7d', 'Duration: remember');
is(OMP::AuthDB::_duration_description('default'), '+8h', 'Duration: default');
