#!/local/perl-5.6/bin/perl

use CGI;
use CGI::Carp qw/fatalsToBrowser/;

BEGIN { $ENV{SYBASE} = "/local/progs/sybase"; }

use lib qw(/jac_sw/omp/test/omp/msbserver);

use OMP::CGI;
use OMP::CGIFault;
use strict;
use warnings;

my $arg = shift @ARGV;

my $q = new CGI;
my $cgi = new OMP::CGI( CGI => $q );

$cgi->html_title("OMP Fault System: View Fault " . $q->url_param('id'));
$cgi->write_page_fault( \&view_fault_content, \&view_fault_output);
