package OMP::CGIWORF;

=head1 NAME

OMP::CGIWORF - CGI functions for WORF, the WWW Observing Remotely Facility.

=head1 SYNOPSIS

  use OMP::CGIWORF;

  display_observation( $obs, $cgi );

=head1 DESCRIPTION

This module provides routines for the display of observations over the web.
It also provides the CGI infrastructure for such display.

=cut

use strict;
use warnings;
use Carp;

use CGI;
use CGI::Carp qw/ fatalsToBrowser /;
use Net::Domain qw/ hostfqdn /;

use OMP::CGI;
use OMP::General;
use OMP::Info::Obs;
use OMP::WORF;
use OMP::CGIObslog qw/ cgi_to_obs /;
use OMP::Error qw/ :try /;

our $VERSION = (qw$Revision$ )[1];

require Exporter;

our @ISA = qw/Exporter/;
our @EXPORT = qw( display_page display_graphic display_observation );

our %EXPORT_TAGS = (
                    'all' => [ @EXPORT ]
                    );

Exporter::export_tags(qw/ all /);

=head1 Routines

All routines are exported by default.

=cut

sub display_page {
  my $cgi = shift;
  my $qv = $cgi->Vars;

#  print_worf_header();

  print "<img src=\"worf_image.pl?";
  print "runnr=" . $qv->{'runnr'};
  print "&ut=" . $qv->{'ut'};
  print "&inst=" . $qv->{'inst'};
  print ( defined( $qv->{'xstart'} ) ? "&xstart=" . $qv->{'xstart'} : '' );
  print ( defined( $qv->{'xend'} ) ? "&xend=" . $qv->{'xend'} : '' );
  print ( defined( $qv->{'ystart'} ) ? "&ystart=" . $qv->{'ystart'} : '' );
  print ( defined( $qv->{'yend'} ) ? "&yend=" . $qv->{'yend'} : '' );
  print ( defined( $qv->{'zmin'} ) ? "&zmin=" . $qv->{'zmin'} : '' );
  print ( defined( $qv->{'zmax'} ) ? "&zmax=" . $qv->{'zmax'} : '' );
  print ( defined( $qv->{'autocut'} ) ? "&autocut=" . $qv->{'autocut'} : '' );
  print ( defined( $qv->{'lut'} ) ? "&lut=" . $qv->{'lut'} : '' );
  print ( defined( $qv->{'size'} ) ? "&size=" . $qv->{'size'} : '' );
  print ( defined( $qv->{'type'} ) ? "&type=" . $qv->{'type'} : '' );
  print ( defined( $qv->{'cut'} ) ? "&cut=" . $qv->{'cut'} : '' );
  print ( defined( $qv->{'suffix'} ) ? "&suffix=" . $qv->{'suffix'} : '' );
  print ( defined( $qv->{'group'} ) ? "&group=" . $qv->{'group'} : '' );
  print "><br><br>\n";

#  print_worf_footer();

}

sub thumbnails_page {

}

sub display_graphic {
  my $cgi = shift;

  my $obs = cgi_to_obs( $cgi );

  my $qv = $cgi->Vars;

  my $suffix = ( defined( $qv->{'suffix'} ) ? $qv->{'suffix'} : '' );

  display_observation( $cgi, $obs, $suffix );

}

=item B<display_observation>

  display_observation( $cgi, $obs, $suffix );

=cut

sub display_observation {
  my $cgi = shift;
  my $obs = shift;
  my $suffix = shift;

  my $qv = $cgi->Vars;

  my $worf = new OMP::WORF( obs => $obs,
                            suffix => $suffix,
                          );
  my %parsed = $worf->parse_display_options( $qv );

  print $cgi->header( -type => 'image/gif' );
  $worf->plot( %parsed );
}

1;
