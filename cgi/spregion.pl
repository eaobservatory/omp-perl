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

use OMP::CGIPage::SpRegion;

OMP::CGIPage::SpRegion->new(cgi => new CGI)->write_page(
    \&OMP::CGIPage::SpRegion::view_region,
    \&OMP::CGIPage::SpRegion::view_region_output,
    'project',
    no_header => 1,
    title => 'Science Program Regions');
