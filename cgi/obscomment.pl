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
use OMP::CGIPage::Obslog;

use Net::Domain qw/ hostfqdn /;

$| = 1; # make output unbuffered
my $cquery = new CGI;;
my $cgi = new OMP::CGIPage( CGI => $cquery );

$cgi->html_title( "OMP Observation Log" );

# Check to see if we're at one of the telescopes or not. Do this
# by a hostname lookup, then checking if we're on omp2 (JCMT)
# or omp1 (UKIRT).
my $location;
my $hostname = hostfqdn;
if($hostname =~ /omp2/i) {
  $location = "jcmt";
} elsif ($hostname =~ /omp1/i) {
  $location = "ukirt";
} else {
  $location = "nottelescope";
}

# Write the page, using the proper authentication on whether or
# not we're at one of the telescopes
if(($location eq "jcmt") || ($location eq "ukirt")) {
  $cgi->write_page( \&file_comment, \&file_comment_output, 'no_project_auth' );
} else {
  $cgi->write_page_staff( \&file_comment, \&file_comment_output, 'no_project_auth');
}
