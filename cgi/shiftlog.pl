#!/local/bin/perl -X
#
# shiftlog - keep a log throughout a night
#
# Author: Brad Cavanagh (b.cavanagh@jach.hawaii.edu)

BEGIN {
#  use constant OMPLIB => "/jac_sw/omp/msbserver";
use constant OMPLIB => "/home/bradc/development/omp/msbserver";
  use File::Spec;
  $ENV{'OMP_CFG_DIR'} = File::Spec->catdir( OMPLIB, "cfg" )
    unless exists $ENV{'OMP_CFG_DIR'};
}

use CGI;
use CGI::Carp qw/ fatalsToBrowser /;

use lib OMPLIB;

use OMP::CGIShiftlog;
use OMP::CGI;
use OMP::Config;

use strict;

$| = 1; # make output unbuffered

my $cquery = new CGI;
my $cgi = new OMP::CGI( CGI => $cquery );
$cgi->html_title( "OMP Shiftlog" );

# Find our location. If we get back a single telescope, that means we're
# being run on one of the telescopes. Otherwise we're not, and we need
# authentication.
my $tel = OMP::Config->getData('defaulttel');
if(ref($tel) eq "ARRAY") {

  # We need authentication.
  $cgi->write_page( \&shiftlog_page, \&shiftlog_page );

} else {

  # We don't need authentication.
  $cgi->write_page_noauth( \&shiftlog_page, \&shiftlog_page );

}
