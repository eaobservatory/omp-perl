#!/local/perl/bin/perl -XT

use CGI;
use CGI::Carp qw/fatalsToBrowser/;

BEGIN { $ENV{PATH} = "/usr/bin";
	$ENV{SYBASE} = "/local/progs/sybase";
	$ENV{OMP_CFG_DIR} = "/jac_sw/omp/msbserver/cfg"
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
my $theme = new HTML::WWWTheme("/WWW/omp/LookAndFeelConfig");
$cgi->theme($theme);

$cgi->html_title("OMP Fault System: Update response");

my @domain = OMP::General->determine_host;

# If the user is outside the JAC network write the page with
# authentication
if ($domain[1] and $domain[1] !~ /\./) {
  $cgi->write_page_fault( \&update_resp_content, \&update_resp_output);
} else {
  $cgi->write_page_fault_auth( \&update_resp_content, \&update_resp_output);
}
