#!/local/perl-5.6/bin/perl

use CGI;
use CGI::Carp qw/fatalsToBrowser/;

BEGIN { $ENV{SYBASE} = "/local/progs/sybase"; }

use lib qw(/jac_sw/omp/msbserver);

use OMP::CGI;
use OMP::CGIFault;
use strict;
use warnings;

my $arg = shift @ARGV;

my $q = new CGI;
my $cgi = new OMP::CGI( CGI => $q );

$cgi->html_title("OMP Fault System: File Fault");
$cgi->write_page_noauth( \&file_fault, \&file_fault_output);
