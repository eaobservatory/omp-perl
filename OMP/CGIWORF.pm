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
our @EXPORT = qw( display_page display_graphic display_observation
                  options_form );

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
  print "\"><br><br>\n";

  options_form( $cgi );

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

=item B<options_form>

Displays a form allowing the user to change display options.

  options_form( $cgi );

The only parameter is the C<CGI> object, and is mandatory.

=cut

sub options_form {
  my $cgi = shift;

  my @autocut_value = qw/ 100 99 98 95 90 80 70 50 /;

  my @type_value = qw/ image spectrum /;

  my @cut_value = qw/ horizontal vertical /;

  my @lut_value = qw/ real heat smooth2 ramp /;

  my $qv = $cgi->Vars;

  if( ! defined( $cgi ) ) {
    throw OMP::Error( "Must supply CGI object to option_form in OMP::CGIWORF" );
  }

  print $cgi->startform;
  print "<table border=\"0\"><tr><td>";
  print "xstart: </td><td>";
  print $cgi->textfield( -name => 'xstart',
                         -size => '16',
                         -maxlength => '5',
                         -default => ( defined($qv->{xstart}) ?
                                       $qv->{xstart} :
                                       '0' ),
                       );
  print "</td><td>ystart: </td><td>";
  print $cgi->textfield( -name => 'ystart',
                         -size => '16',
                         -maxlength => '5',
                         -default => ( defined($qv->{ystart}) ?
                                       $qv->{ystart} :
                                       '0' ),
                       );
  print "</td><td>zmin: </td><td>";
  print $cgi->textfield( -name => 'zmin',
                         -size => '16',
                         -maxlength => '6',
                         -default => ( defined($qv->{zmin}) ?
                                       $qv->{zmin} :
                                       '0' ),
                       );
  print "</td></tr>\n";

  print "<tr><td>xend: </td><td>";
  print $cgi->textfield( -name => 'xend',
                         -size => '16',
                         -maxlength => '5',
                         -default => ( defined($qv->{xend}) ?
                                       $qv->{xend} :
                                       '0' ),
                       );
  print "</td><td>yend: </td><td>";
  print $cgi->textfield( -name => 'yend',
                         -size => '16',
                         -maxlength => '5',
                         -default => ( defined($qv->{yend}) ?
                                       $qv->{yend} :
                                       '0' ),
                       );
  print "</td><td>zmax: </td><td>";
  print $cgi->textfield( -name => 'zmax',
                         -size => '16',
                         -maxlength => '6',
                         -default => ( defined($qv->{zmax}) ?
                                       $qv->{zmax} :
                                       '0' ),
                       );
  print "</td></tr>\n";

  print "<tr><td>autocut: </td>";
  print "<td>";
  print $cgi->popup_menu( -name => 'autocut',
                          -values => \@autocut_value,
                          -default => '99',
                        );

  print "</td><td>type: </td><td>";
  print $cgi->popup_menu( -name => 'type',
                          -values => \@type_value,
                          -default => ( defined( $qv->{type} ) ?
                                        $qv->{type} :
                                        $type_value[0],
                                      ),
                        );

  print "</td><td>cut: </td><td>";
  print $cgi->popup_menu( -name => 'cut',
                          -values => \@cut_value,
                          -default => ( defined( $qv->{cut} ) ?
                                        $qv->{cut} :
                                        $cut_value[0],
                                      ),
                        );
  print "</td></tr>\n";

  print "<tr><td>colormap: </td><td>";
  print $cgi->popup_menu( -name => 'lut',
                          -values => \@lut_value,
                          -default => ( defined( $qv->{lut} ) ?
                                        $qv->{lut} :
                                        $lut_value[0],
                                      ),
                        );

  print "</td></tr></table>\n";

  print $cgi->hidden( -name => 'ut',
                      -value => $qv->{ut},
                    );
  print $cgi->hidden( -name => 'inst',
                      -value => $qv->{inst},
                    );
  print $cgi->hidden( -name => 'suffix',
                      -value => $qv->{suffix},
                    );
  print $cgi->hidden( -name => 'group',
                      -value => $qv->{group},
                    );
  print $cgi->hidden( -name => 'runnr',
                      -value => $qv->{runnr},
                    );

  print $cgi->submit( -name => 'Submit' );

  print $cgi->endform;

}

1;
