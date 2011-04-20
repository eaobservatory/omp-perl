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

my $arg = shift @ARGV;

my $q = new CGI;
my $cgi = new OMP::CGIPage( CGI => $q );

my $title = $cgi->html_title;

$cgi->html_title("$title: OMP Users");

my ( $in, $out ) =
  ( \&OMP::CGIPage::User::list_users,
    \&OMP::CGIPage::User::list_users );

if ( OMP::NetTools->is_host_local ) {
  # Skip inapplicable project authentication.
  $cgi->write_page( $in, $out, 'skip-proj-auth' );
} else {
  # Skip inapplicable project authentication but not staff authentication.
  #
  # In ./viewfault.pl, while calling OMP::CGIPage::Fault::write_page(), there is
  # no need to send a skip-proj-auth like flag as O::C::F::_write_login(),
  # overrides O::C::_write_login(), does not do any project authentication.
  $cgi->write_page_staff( $in, $out, 'skip-proj-auth' );
}
