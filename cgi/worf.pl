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

# Set up the environment for PGPLOT

BEGIN {
  $ENV{'PGPLOT_DIR'} = '/star/bin';
  $ENV{'PGPLOT_FONT'} = '/star/bin/grfont.dat';
  $ENV{'PGPLOT_GIF_WIDTH'} = 600;
  $ENV{'PGPLOT_GIF_HEIGHT'} = 450;
  $ENV{'PGPLOT_BACKGROUND'} = 'white';
  $ENV{'PGPLOT_FOREGROUND'} = 'black';
  $ENV{'HDS_SCRATCH'} = "/tmp";
}

# Bring in all the required modules

use CGI;
use CGI::Carp qw/fatalsToBrowser/;
use PDL::Graphics::LUT;

# we need to point to a different directory to see ORAC and OMP modules

use lib qw(/ukirt_sw/oracdr/lib/perl5);
use ORAC::Frame::NDF;
use ORAC::Inst::Defn qw(orac_configure_for_instrument);

use lib qw(/jac_sw/omp/msbserver);
use OMP::CGI;
#use lib qw(/home/bradc/development/omp/msbserver);
use OMP::WORF;
use OMP::WORF::CGI;

use strict;

# Turn off warning of redefining orac_warn
no warnings qw/ redefine /;
sub ORAC::Print::orac_warn {};

# Set up global variables, system variables, etc.

$| = 1;  # make output unbuffered

my @instruments = ("cgs4", "ircam", "michelle", "ufti");
my $query = new CGI;
my $cgi = new OMP::CGI( CGI => $query );
$cgi->html_title("WORF: UKIRT WWW Observing Remotely Facility");

# Set up the UT date
my $ut;
  {
    my ($sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdist) = gmtime(time);
    $ut = ($year + 1900) . pad($month + 1, "0", 2) . pad($day, "0", 2);

# for demo purposes
#    $ut = "20020310";
  }

# write the page

$cgi->write_page( \&worf_output, \&worf_output );

sub worf_output {
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

# Print out the page

  print_header();

  foreach my $instrument (@instruments) {
    print_summary( $instrument, $ut, $projectid );
  }

  print "<hr>List all reduced group observations for ";
  my @string;
  foreach my $instrument (@instruments) {
    push @string, (sprintf "<a href=\"worf.pl?all=yes&obstype=reduced&instrument=%s\">%s</a>", $instrument, $instrument);
  }
  print join ", ", @string;
  print " for $ut.<br>\n";
  print "List all raw observations for ";
  my @string2;
  foreach my $instrument (@instruments) {
    push @string2, (sprintf "<a href=\"worf.pl?all=yes&obstype=raw&instrument=%s\">%s</a>", $instrument, $instrument);
  }
  print join ", ", @string2;
  print " for $ut.<br>\n";
  print "<hr>\n";

  if( $verified{view} eq 'yes' ) {
    print_display_properties( $verified{instrument}, $verified{file}, $verified{obstype} );
    display_observation( \%verified );
  }
  if ( $verified{all} eq 'yes' ) {
    if ( $verified{obstype} eq 'raw' ) {
      list_raw_observations( $verified{instrument}, $ut, $projectid );
    } else {
      list_reduced_observations( $verified{instrument}, $ut, $projectid );
    }
  }

  print_footer;

} # end sub worf_output
