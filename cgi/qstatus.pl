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
use OMP::CGIPage::QStatus;

my $q = new CGI();
my $ompcgi = new OMP::CGIPage(CGI => $q);

my $title = $ompcgi->html_title();
$ompcgi->html_title("$title: Queue Status");

$ompcgi->write_page_staff(\&OMP::CGIPage::QStatus::view_queue_status,
                          \&OMP::CGIPage::QStatus::view_queue_status_output,
                          1);
