#!/local/perl-5.6/blead/bin/perl5.7.3

use CGI;
use CGI::Carp qw/fatalsToBrowser/;

BEGIN { $ENV{SYBASE} = "/opt/sybase-12.5"; }

use lib qw(/jac_sw/omp/msbserver);

use OMP::CGI;
use OMP::CGIHelper;
use strict;
use warnings;

my $arg = shift @ARGV;

my $q = new CGI;
my $cgi = new OMP::CGI( CGI => $q );

$cgi->write_page( \&fb_output, \&fb_output );
