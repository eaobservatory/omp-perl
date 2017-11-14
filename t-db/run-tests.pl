#!/local/perl/bin/perl

use strict;
use lib '../lib';

use Test::Harness;

runtests(sort <*.t>);
