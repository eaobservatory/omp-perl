#!/local/perl/bin/perl

use strict; use warnings;

BEGIN
{
  our $lib = '/jac_sw/omp/msbserver';
  $ENV{'OMP_CFG_DIR'} = $lib . '/cfg';
}
our $lib;
use lib $lib;

use OMP::ProjServer;

my @proj = @ARGV
  or die "Give list of projects for which to issue passwords.\n";

OMP::ProjServer->issuePassword( $_ ) for @proj;

