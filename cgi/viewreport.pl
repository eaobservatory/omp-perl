#!/local/perl/bin/perl -XT
use strict;

# Standard initialisation (not much shorter than the previous
# code but no longer has the module path hard-coded)
BEGIN {
  my $retval = do "./cgi-init.pl";
  unless ($retval) {
    warn "couldn't parse cgi-init.pl: $@" if $@;
    warn "couldn't do cgi-init.pl: $!"    unless defined $retval;
    warn "couldn't run cgi-init.pl"       unless $retval;
    exit;
  }
}

# Load OMP modules
use OMP::CGI;
use OMP::CGIFault;

my $arg = shift @ARGV;

my $q = new CGI;
my $cgi = new OMP::CGI( CGI => $q );

# Set our theme
my $theme = new HTML::WWWTheme("/WWW/omp/LookAndFeelConfig");
$cgi->theme($theme);

$cgi->html_title("OMP: View Report: ". $q->url_param("id"));
$cgi->write_page_report("OMP", \&view_fault_content, \&view_fault_output);
