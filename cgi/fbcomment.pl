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
my $ompcgi = new OMP::CGI( CGI => $q );

my $title = $ompcgi->html_title;
$ompcgi->html_title("$title: List Projects");
$ompcgi->write_page( \&add_comment_content, \&add_comment_output );
