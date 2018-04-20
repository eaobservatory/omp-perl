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

use OMP::CGIPage;
use OMP::CGIPage::SourcePlot;

my $q = new CGI();
my $ompcgi = new OMP::CGIPage(CGI => $q);

my $title = $ompcgi->html_title();
$ompcgi->html_title("$title: Source Plot");

$ompcgi->write_page_staff(\&OMP::CGIPage::SourcePlot::view_source_plot,
                          \&OMP::CGIPage::SourcePlot::view_source_plot_output,
                          1);
