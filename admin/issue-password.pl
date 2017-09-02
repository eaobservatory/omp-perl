#!/local/perl/bin/perl

use strict; use warnings;
use FindBin;

use constant OMPLIB => "$FindBin::RealBin/..";

BEGIN
{
  $ENV{'OMP_CFG_DIR'} = $ENV{OMP_CFG_DIR} = File::Spec->catdir(OMPLIB, "cfg")
    unless exists $ENV{OMP_CFG_DIR};
}

use lib OMPLIB;

use OMP::ProjServer;

my @proj = @ARGV
  or die "Give list of projects for which to issue passwords.\n";

OMP::ProjServer->issuePassword( $_ ) for @proj;

