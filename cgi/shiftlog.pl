#!/local/bin/perl -X
#
# shiftlog - keep a log throughout a night
#
# Author: Brad Cavanagh (b.cavanagh@jach.hawaii.edu)

BEGIN {
  use constant OMPLIB => "/jac_sw/omp/msbserver";
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

my @domain = OMP::General->determine_host;

# write the page

if( $domain[1] and $domain[1] !~ /\./) {
  $cgi->write_page_noauth( \&shiftlog_page, \&shiftlog_page );
} else {
  $cgi->write_page_staff( \&shiftlog_page, \&shiftlog_page );
}
