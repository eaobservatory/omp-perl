#!/local/perl/bin/perl -XT

use CGI;
use CGI::Carp qw/fatalsToBrowser/;

BEGIN { $ENV{SYBASE} = "/local/progs/sybase";
	$ENV{OMP_CFG_DIR} = "/jac_sw/omp/msbserver/cfg"
	  unless exists $ENV{OMP_CFG_DIR};
      }

use lib qw(/jac_sw/omp/msbserver);

use OMP::CGI;
use OMP::CGIUser;
use OMP::General;
use OMP::UserServer;
use OMP::Error qw(:try);

use strict;
use warnings;

my $arg = shift @ARGV;

my $q = new CGI;
my $cgi = new OMP::CGI( CGI => $q );

my $title = $cgi->html_title;

my $user;
try {
  $user = OMP::UserServer->getUser($q->url_param('user'));
} otherwise {
  $user = "Unknown User";
};

(! $user) and $user = "Uknown User";

$cgi->html_title("$title: User Details for $user");

# Do project authentication if the user is not local
if (OMP::General->is_host_local) {
  $cgi->write_page_noauth( \&OMP::CGIUser::details, \&OMP::CGIUser::details );
} else {
  $cgi->write_page( \&OMP::CGIUser::details, \&OMP::CGIUser::details );
}
