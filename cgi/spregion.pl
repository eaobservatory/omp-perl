#!/local/perl/bin/perl -XT
use strict;

# Standard initialisation (not much shorter than the previous
# code but no longer has the module path hard-coded)
BEGIN {
  # Set this directory path because
  # PGPLOT needs to find its font file.
  $ENV{PGPLOT_DIR} = "/star/bin";

  my $retval = do "./omp-cgi-init.pl";
  unless ($retval) {
    warn "couldn't parse omp-cgi-init.pl: $@" if $@;
    warn "couldn't do omp-cgi-init.pl: $!"    unless defined $retval;
    warn "couldn't run omp-cgi-init.pl"       unless $retval;
    exit;
  }
}

use OMP::CGIPage;
use OMP::CGIPage::SpRegion;

my $q = new CGI;
my $ompcgi = new OMP::CGIPage( CGI => $q );

my $title = $ompcgi->html_title;
$ompcgi->html_title("$title: Science Program Regions");

# Use the 'proposals' page template so that we can set an appropriate
# content type for the region files and plot.
$ompcgi->write_page(\&OMP::CGIPage::SpRegion::view_region,
                    \&OMP::CGIPage::SpRegion::view_region_output,
                    0, 1);
