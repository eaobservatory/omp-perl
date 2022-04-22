#!/local/perl/bin/perl -XT

use 5.006;
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

use OMP::CGIPage::PkgData;

OMP::CGIPage::PkgData->new(cgi => new CGI())->write_page(
    \&OMP::CGIPage::PkgData::request_data,
    'project',
    title =>  'Data Retrieval',
    template => 'retrieve_data.html');
