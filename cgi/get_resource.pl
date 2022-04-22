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

use OMP::CGIPage::IncludeFile;

OMP::CGIPage::IncludeFile->new(cgi => new CGI())->write_page(
    \&OMP::CGIPage::IncludeFile::get_resource,
    'local_or_staff_or_project',
);
