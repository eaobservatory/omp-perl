#!/local/perl-5.6/blead/bin/perl5.7.3 -XT

use CGI;
use CGI::Carp qw/fatalsToBrowser/;

BEGIN { $ENV{PATH} = "/usr/bin"; $ENV{SYBASE} = "/local/progs/sybase"; }

use lib qw(/jac_sw/omp_dev/msbserver);

use OMP::CGI;
use OMP::CGIFault;
use strict;
use warnings;

my $arg = shift @ARGV;

my $q = new CGI;
my $cgi = new OMP::CGI( CGI => $q );

# Set our theme
my $theme = new HTML::WWWTheme("/WWW/omp-private/LookAndFeelConfig");
$cgi->theme($theme);

$cgi->html_title("OMP Fault System: File Fault");
$cgi->write_page_fault( \&file_fault, \&file_fault_output);
