#!/local/perl-5.6/bin/perl -XT

use 5.006;
use strict;

use FindBin;
#use lib "$FindBin::RealBin/../";
use lib "/jac_sw/omp/msbserver";

BEGIN { $ENV{OMP_CFG_DIR} = "/jac_sw/omp/msbserver/cfg"; }

use CGI;
use CGI::Carp qw/fatalsToBrowser/;
use OMP::CGIPage;
use OMP::CGIPage::PkgData;


# unbuffered
$| = 1;


# Create the new object for this transaction
my $cquery = new CGI;
my $cgi = new OMP::CGIPage( CGI => $cquery );
$cgi->html_title( "OMP Data retrieval" );

# Now write the page
$cgi->write_page( \&OMP::CGIPage::PkgData::request_data,
		  \&OMP::CGIPage::PkgData::request_data
		);
