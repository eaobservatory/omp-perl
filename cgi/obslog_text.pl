#!/local/bin/perl -X

BEGIN {
  use constant OMPLIB => "/jac_sw/omp/msbserver";
  use File::Spec;
  $ENV{'OMP_CFG_DIR'} = File::Spec->catdir( OMPLIB, "cfg" )
    unless exists $ENV{'OMP_CFG_DIR'};
}


use CGI;
use CGI::Carp qw/fatalsToBrowser/;

use lib OMPLIB;

use OMP::CGI;
use OMP::CGIObslog;

use Net::Domain qw/ hostfqdn /;

use strict;

$| = 1; # make output unbuffered

my $query = new CGI;

list_observations_txt( $query );
