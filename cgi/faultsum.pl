#!/local/perl-5.6/bin/perl -XT

use CGI;
use CGI::Carp qw/fatalsToBrowser/;

BEGIN { $ENV{PATH} = "/usr/bin";
	$ENV{SYBASE} = "/local/progs/sybase";
	$ENV{OMP_CFG_DIR} = "/jac_sw/omp_dev/msbserver/cfg"
	  unless exists $ENV{OMP_CFG_DIR};
      }

use lib qw(/jac_sw/omp/msbserver);

use OMP::CGI;
use OMP::CGIFault;
use OMP::General;
use strict;
use warnings;

my $arg = shift @ARGV;

my $q = new CGI;
my $cgi = new OMP::CGI( CGI => $q );

# Set our theme
my $theme = new HTML::WWWTheme("/WWW/omp-private/LookAndFeelConfig");
$cgi->theme($theme);

$cgi->html_title("Fault Summary");

# If the user is outside the JAC network write the page with
# authentication
my @domain = OMP::General->determine_host;

if ($domain[1] and $domain[1] !~ /\./) {
  $cgi->write_page_fault( \&fault_summary_form, \&fault_summary_content);
} else {
  $cgi->write_page_fault_auth( \&fault_summary_form, \&fault_summary_content);
}
