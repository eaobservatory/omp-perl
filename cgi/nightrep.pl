#!/local/perl/bin/perl -XT

use CGI;
use CGI::Carp qw/fatalsToBrowser/;

BEGIN { $ENV{SYBASE} = "/local/progs/sybase";
	$ENV{OMP_CFG_DIR} = "/jac_sw/omp/msbserver/cfg"
	  unless exists $ENV{OMP_CFG_DIR};
      }


use lib qw(/jac_sw/omp/msbserver);

use OMP::CGI;
use OMP::CGIHelper;
use OMP::General;
use strict;
use warnings;

my $arg = shift @ARGV;

my $q = new CGI;
my $cgi = new OMP::CGI( CGI => $q );

$cgi->html_title("Observing Report " . $q->url_param('utdate'));

my @domain = OMP::General->determine_host;

# If the user is outside the JAC network write the page with
# authentication
if ($domain[1] and $domain[1] !~ /\./) {
  $cgi->write_page_noauth( \&night_report, \&night_report );
} else {
  $cgi->write_page_staff( \&night_report, \&night_report );
}


