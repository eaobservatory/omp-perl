#!/local/perl/bin/perl

use strict;
use lib '..';

use Test::Harness;

runtests(sort <*.t>);
