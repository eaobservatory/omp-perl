#!/local/perl/bin/perl

BEGIN { $ENV{SYBASE} = "/local/progs/sybase"; 
	$ENV{OMP_CFG_DIR} = "/jac_sw/omp/msbserver/cfg"
	  unless $ENV{OMP_CFG_DIR};
      }

use lib "/jac_sw/omp/msbserver";
use CGI;
use CGI::Carp qw/fatalsToBrowser/;

use OMP::CGI;
use OMP::CGIHelper;
use strict;
use warnings;

my $q = new CGI;
my $cgi = new OMP::CGI( CGI => $q );

my $title = $cgi->html_title;
$cgi->html_title("$title: Password request page");
$cgi->write_page_noauth( \&issuepwd, \&issuepwd );
