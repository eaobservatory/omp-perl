#!/local/perl-5.6/blead/bin/perl5.7.3

use CGI;
use CGI::Carp qw/fatalsToBrowser/;

BEGIN { $ENV{SYBASE} = "/local/progs/sybase"; }

use lib qw(/jac_sw/omp/msbserver);

use OMP::CGI;
use OMP::CGIHelper;

use HTML::WWWTheme;

use strict;
use warnings;

my $arg = shift @ARGV;

my $q = new CGI;
my $cgi = new OMP::CGI( CGI => $q );

# Set our theme
my $theme = new HTML::WWWTheme("/WWW/omp-private/LookAndFeelConfig");
$cgi->theme($theme);

my $title = $cgi->html_title;
$cgi->html_title("$title: List Projects");
$cgi->write_page_noauth( \&list_projects, \&list_projects_output );

