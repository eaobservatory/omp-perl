#!/local/perl/bin/perl -XT
use strict;

# Standard initialisation (not much shorter than the previous
# code but no longer has the module path hard-coded)
BEGIN {
  my $retval = do "./omp-cgi-init.pl";
  unless ($retval) {
    warn "couldn't parse omp-cgi-init.pl: $@" if $@;
    warn "couldn't do omp-cgi-init.pl: $!"    unless defined $retval;
    warn "couldn't run omp-cgi-init.pl"       unless $retval;
    exit;
  }
}

# Load OMP modules
use OMP::CGIPage;
use OMP::CGIPage::Project;
use OMP::ProjServer;

my $arg = shift @ARGV;

my $q = new CGI;
my $cgi = new OMP::CGIPage( CGI => $q );

my $title = $cgi->html_title . ": Project home";
my $projid = uc($cgi->_get_param('projectid'));
my $password = $cgi->_get_param('password');
my $verify;
if ($projid and $password) {
  $verify = OMP::ProjServer->verifyPassword($projid, $password);
}

if ($verify) {
  my $projobj = OMP::ProjServer->projectDetails($projid, $password, "object");
  my $projpi = $projobj->pi;

  $title = "$projid ($projpi) - ". $cgi->html_title;
}

$cgi->html_title($title);
$cgi->write_page( \&OMP::CGIPage::Project::project_home,
		  \&OMP::CGIPage::Project::project_home );
