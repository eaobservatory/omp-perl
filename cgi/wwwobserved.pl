#!/local/perl-5.6/bin/perl

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

# Set our theme
my $theme = new HTML::WWWTheme("/WWW/omp-private/LookAndFeelConfig");
$cgi->theme($theme);

$cgi->write_page_noauth( \&observed, \&observed_output );

