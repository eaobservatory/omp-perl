#!/local/perl/bin/perl -XT
use strict;

# Standard initialisation (not much shorter than the previous
# code but no longer has the module path hard-coded)
BEGIN {
  my $retval = do "./omp-cgi-init.pl";
  unless ($retval) {
    warn "couldn't parse omp-cgi-init.pl: $@" if $@;
    warn "couldn't do omp-cgi-init.pl: $!"    unless defined $retval;
    warn "couldn't run omp-cgi-init.pl"       unless $retval;
    exit;
  }
}

# Load OMP modules
use OMP::CGIPage;
use OMP::CGIPage::ObsReport;
use OMP::NetTools;

my $arg = shift @ARGV;

my $q = new CGI;
my $cgi = new OMP::CGIPage( CGI => $q );

$cgi->html_title("Observing Report " . $q->url_param('utdate'));

# If the user is outside the JAC network write the page with
# authentication
if (OMP::NetTools->is_host_local) {
  $cgi->write_page_noauth( \&OMP::CGIPage::ObsReport::night_report,
			   \&OMP::CGIPage::ObsReport::night_report );
} else {
  $cgi->write_page_staff( \&OMP::CGIPage::ObsReport::night_report,
			  \&OMP::CGIPage::ObsReport::night_report,
			  "noauth",);
}


