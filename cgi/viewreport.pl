#!/local/perl-5.6/blead/bin/perl5.7.3 -XT

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

# Set our theme
my $theme = new HTML::WWWTheme("/WWW/omp/LookAndFeelConfig");
$cgi->theme($theme);

$cgi->html_title("OMP: View Report: ". $q->url_param("id"));
$cgi->write_page_report("OMP", \&view_fault_content, \&view_fault_output);
