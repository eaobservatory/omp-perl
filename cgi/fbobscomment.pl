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
use OMP::CGIPage::Obslog;

my $cquery = new CGI;
my $cgi = new OMP::CGIPage( CGI => $cquery );
$cgi->html_title( "OMP Observation Log" );

$cgi->write_page( \&file_comment, \&file_comment_output );

