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
my $cquery = new CGI;
my $cgi = new OMP::CGI( CGI => $cquery );
$cgi->html_title( "OMP Observation Log" );

$cgi->write_page( \&file_comment, \&file_comment_output );

