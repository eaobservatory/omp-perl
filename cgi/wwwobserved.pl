#!/local/perl-5.6/bin/perl

use CGI;
use CGI::Carp qw/fatalsToBrowser/;

BEGIN { $ENV{SYBASE} = "/local/progs/sybase"; }

use lib qw(/jac_sw/omp/msbserver);

use OMP::CGI;
use OMP::CGIHelper;
use strict;
use warnings;

my $arg = shift @ARGV;

my $q = new CGI;
my $cgi = new OMP::CGI( CGI => $q );

my $title = $cgi->html_title;
$cgi->html_title("$title: Observed MSBs");
$cgi->write_page_noauth( \&observed, \&observed_output );

