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
use OMP::CGI;
use OMP::CGIObslog;
use OMP::General;

my $cquery = new CGI;
my $cgi = new OMP::CGI( CGI => $cquery );
$cgi->html_title( "OMP Observation Log" );

# Write the page, using the proper authentication on whether or
# not we're at one of the telescopes
if(OMP::General->is_host_local) {
  $cgi->write_page_noauth( \&list_observations, \&list_observations );
} else {
  $cgi->write_page( \&list_observations, \&list_observations );
}

