#!perl

use strict;
use Test::More tests => 2;

use OMP::DB::Auth;

is(OMP::DB::Auth::_duration_description('remember'), '+7d', 'Duration: remember');
is(OMP::DB::Auth::_duration_description('default'), '+8h', 'Duration: default');
