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
use OMP::CGIComponent::Helper;
use OMP::General;

my $arg = shift @ARGV;

my $q = new CGI;
my $ompcgi = new OMP::CGIPage( CGI => $q );

my $title = $ompcgi->html_title;
$ompcgi->html_title("$title: Flex programme descriptions");
if (OMP::General->is_host_local) {
  $ompcgi->write_page_noauth( \&flex_page, \&flex_page, );
} else {
  $ompcgi->write_page_staff( \&flex_page, \&flex_page, 'no_auth');
}
