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
use OMP::CGIHelper;

my $arg = shift @ARGV;

my $q = new CGI;

my $cgi = new OMP::CGI( CGI => $q );

my $utdate = $q->url_param('utdate');

my $title = $cgi->html_title;
$cgi->html_title("$title: Night Report - $utdate");
$cgi->write_page_staff( \&nightlog_content, \&nightlog_content );
