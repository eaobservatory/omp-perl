#!/local/perl-5.6/bin/perl
#
# WWW Observing Remotely Facility (WORF)
#
# http://www.jach.hawaii.edu/JACpublic/UKIRT/software/worf/
#
# Requirements:
# TBD
#
# Authors: Frossie Economou (f.economou@jach.hawaii.edu)
#          Brad Cavanagh (b.cavanagh@jach.hawaii.edu)

use CGI;
use CGI::Carp qw/fatalsToBrowser/;
use PDL::Graphics::LUT;

use lib qw(/jac_sw/omp/msbserver);
use OMP::CGI;
use OMP::WORF::CGI;
use OMP::Info::Obs;
use OMP::ArchiveDB;
use OMP::ObslogDB;
use OMP::BaseDB;

use strict;

# Undefine the orac_warn filehandle
my $Prt = new ORAC::Print;
$Prt->warhdl(undef);

# Set up global variables, system variables, etc.

$| = 1;  # make output unbuffered

my @instruments = ("cgs4", "ircam", "michelle", "ufti", "uist", "scuba");
my $cquery = new CGI;
my $cgi = new OMP::CGI( CGI => $cquery );
$cgi->html_title("obslog: Observation Log Tool");

my $dbconnection = new OMP::DBbackend;

# Set up the UT date
my $current_ut;
  {
    my ($sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdist) = gmtime(time);
#    $current_ut = ($year + 1900) . pad($month + 1, "0", 2) . pad($day, "0", 2);
    $current_ut = '20020710';
  }

# write the page

$cgi->write_page( \&obslog_output, \&obslog_output );

sub obslog_output {
# this subroutine is basically the "main" subroutine for this CGI

# First, pop off the CGI object and the cookie hash

  my $query = shift;
  my %cookie = @_;

  my %verified = ();
  my %params = $query->Vars;

  my $projectid = $cookie{'projectid'};
  my $password = $cookie{'password'};

# Verify the $query->param() hash
  verify_query( \%params, \%verified );

  my %filter;

# Set the desired UT date.
  my $ut = $verified{'ut'} || $current_ut;

# Print out the page
  print_header();

  print "List all raw observations for ";
  my @string;
  foreach my $instrument (@instruments) {
    push @string, (sprintf "<a href=\"obslog.pl?list=yes&ut=%s&instrument=%s\">%s</a>", $ut, $instrument, $instrument);
  }
  print join ", ", @string;
  print " for $ut.<br>\n";
  print "<hr>\n";

  if ( $verified{list} eq 'yes' ) {
    list_observations( $ut, $projectid, $password, \%filter );
  }

  print_footer();

} # end sub worf_output

sub list_observations {
  my $ut = shift;
  my $projectid = shift;
  my $password = shift;
  my $filter = shift;

  my $verified;

  # Verify the project id with password
  my $projdb = new OMP::ProjDB( ProjectID => $projectid,
                                DB => $dbconnection );
  $verified = $projdb->verifyPassword( $password );

  if( !$verified ) {
    print "<br>Could not verify password for project $projectid.<br>\n";
    return;
  }
}
