#!/local/perl-5.6/bin/perl -XT

use CGI;
use CGI::Carp qw/fatalsToBrowser/;

BEGIN { $ENV{SYBASE} = "/local/progs/sybase"; }

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

$cgi->html_title("OMP Fault System: View Fault " . $q->url_param('id'));

my @domain = OMP::General->determine_host;

# If the user is outside the JAC network write the page with
# authentication
if ($domain[1] and $domain[1] !~ /\./) {
  $cgi->write_page_fault( \&view_fault_content, \&view_fault_output);
} else {
  $cgi->write_page_fault_auth( \&view_fault_content, \&view_fault_output);
}
