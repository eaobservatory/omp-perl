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
use OMP::CGI::ObslogPage;

use Net::Domain qw/ hostfqdn /;

use strict;

$| = 1; # make output unbuffered
my $cquery = new CGI;
my $cgi = new OMP::CGI( CGI => $cquery );
$cgi->html_title( "OMP Observation Log" );

# Check to see if we're at one of the telescopes or not. Do this
# by a hostname lookup, then checking if we're on ulili (JCMT)
# or mauiola (UKIRT).
my $location;
my $hostname = hostfqdn;
if($hostname =~ /ulili/i) {
  $location = "jcmt";
} elsif ($hostname =~ /mauiola/i) {
  $location = "ukirt";
} else {
  $location = "nottelescope";
}

# Write the page, using the proper authentication on whether or
# not we're at one of the telescopes
if(($location eq "jcmt") || ($location eq "ukirt")) {
  $cgi->write_page_noauth( \&list_observations, \&list_observations );
} else {
  $cgi->write_page( \&list_observations, \&list_observations );
}

