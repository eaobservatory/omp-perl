#!/local/perl/bin/perl -XT
#
# shiftlog - keep a log throughout a night
#
# Author: Brad Cavanagh (b.cavanagh@jach.hawaii.edu)
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
use OMP::CGIShiftlog;
use OMP::CGI;
use OMP::Config;
use OMP::General;

my $cquery = new CGI;
my $cgi = new OMP::CGI( CGI => $cquery );
$cgi->html_title( "OMP Shiftlog" );

# write the page

if (OMP::General->is_host_local) {
  $cgi->write_page_noauth( \&shiftlog_page, \&shiftlog_page );
} else {
  $cgi->write_page_staff( \&shiftlog_page, \&shiftlog_page );
}
