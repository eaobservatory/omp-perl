package OMP::CGI::WORF;

=head1 NAME

OMP::CGIKKWORF - CGI functions for WORF, the WWW Observing Remotely Facility.

=head1 SYNOPSIS

  use OMP::CGI::WORF;

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

use OMP::Info::Obs;
use OMP::WORF;
use OMP::CGI::Obslog qw/ cgi_to_obs /;
use OMP::Error qw/ :try /;

our $VERSION = (qw$Revision$ )[1];

require Exporter;

our @ISA = qw/Exporter/;
our @EXPORT = qw( display_graphic display_observation
                  options_form obsnumsort );

our %EXPORT_TAGS = (
                    'all' => [ @EXPORT ]
                    );

Exporter::export_tags(qw/ all /);

=head1 Routines

All routines are exported by default.

=cut

sub display_graphic {
  my $cgi = shift;
  my $qv = $cgi->Vars;

  my $ut;
  if( exists( $qv->{'ut'} ) && defined( $qv->{'ut'} ) ) {
    $qv->{'ut'} =~ /^(\d{4}-\d\d-\d\d)/;
    $ut = $1;
  }

  my $suffix;
  if( exists( $qv->{'suffix'} ) && defined( $qv->{'suffix'} ) ) {
    $qv->{'suffix'} =~ /^(\w+)$/;
    $suffix = $1;
  } else {
    $suffix = '';
  }

  my $runnr;
  if( exists( $qv->{'runnr'} ) && defined( $qv->{'runnr'} ) ) {
    $qv->{'runnr'} =~ /^(\d+)$/;
    $runnr = $1;
  }

  my $inst;
  if( exists( $qv->{'inst'} ) && defined( $qv->{'inst'} ) ) {
    $qv->{'inst'} =~ /^([\w\d]+)$/;
    $inst = $1;
  }

  my $size;
  if( exists( $qv->{'size'} ) && defined( $qv->{'size'} ) ) {
    $qv->{'inst'} =~ /^(thumb|regular)$/;
    $size = $1;
  } else {
    $size = '';
  }

  if( defined( $ut ) && defined( $runnr ) && defined( $inst ) &&
      defined( $size ) && $size =~ /^thumb$/ ) {

    # See if the cache file exists. It will be of the form
    # $ut . $inst . $runnr . $suffix . ".gif"
    my $cachefile = "/tmp/worfthumbs/" . $ut . $inst . $runnr . $suffix . ".gif";

    if( -e $cachefile ) {

      open( CACHE, "< $cachefile" ) or throw OMP::Error("Cannot open cached thumbnail for display: $!");
      binmode( CACHE );
      binmode( STDOUT );

      while( read( CACHE, my $buff, 8 * 2 ** 10 ) ) { print STDOUT $buff; }

      close( CACHE );

      return;
    }

  }

  my $obs = cgi_to_obs( $cgi );

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

sub obsnumsort {

# Sorting routine to sort files by observation number, numerically instead of alphabetically
# (so that 19 comes before 143)

        $a =~ /_(\d+)(_)?/;
        my $a_obsnum = $1;
        my $a_nosuffix = $2;
        $b =~ /_(\d+)(_)?/;
        my $b_obsnum = $1;
        my $b_nosuffix = $2;
        if( $a_obsnum == $b_obsnum ) {
          return 1 if defined $a_nosuffix;
          return -1 if defined $b_nosuffix;
          return 0;
        }
        $a_obsnum <=> $b_obsnum;

}

=head1 SEE ALSO

C<OMP::CGI::WORFPage>

=head1 AUTHOR

Brad Cavanagh E<lt>b.cavanagh@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2004 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
