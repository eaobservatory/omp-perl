#!/local/perl-5.6/bin/perl

use CGI;
use CGI::Carp qw/fatalsToBrowser/;

use lib qw(/jac_sw/omp/test/omp/msbserver);

use OMP::CGI;
use OMP::CGIHelper;
use strict;
use warnings;

my $arg = shift @ARGV;

my $q = new CGI;
my $ompcgi = new OMP::CGI( CGI => $q );

$ompcgi->write_page_logout( \&fb_logout );
