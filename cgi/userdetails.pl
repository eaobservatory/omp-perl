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
use OMP::CGIPage::User;
use OMP::NetTools;
use OMP::UserServer;
use OMP::Error qw(:try);

my $arg = shift @ARGV;

my $q = new CGI;
my $cgi = new OMP::CGIPage( CGI => $q );

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
if (OMP::NetTools->is_host_local) {
  $cgi->write_page_noauth( \&OMP::CGIPage::User::details,
                           \&OMP::CGIPage::User::details );
} else {
  $cgi->write_page_noauth( \&OMP::CGIPage::User::details,
                           \&OMP::CGIPage::User::details );
}
