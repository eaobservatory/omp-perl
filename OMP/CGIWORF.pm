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
use OMP::CGIObslog qw/ cgi_to_obs obs_table /;
use OMP::Error qw/ :try /;

our $VERSION = (qw$Revision$ )[1];

require Exporter;

our @ISA = qw/Exporter/;
our @EXPORT = qw( display_page display_graphic display_observation
                  options_form thumbnails_page );

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

  $qv->{'ut'} =~ /^(\d{4}-\d\d-\d\d)/;
  my $ut = $1;

  my $adb = new OMP::ArchiveDB( DB => new OMP::DBbackend::Archive );
  my $obs = $adb->getObs( instrument => $qv->{'inst'},
                          ut => $1,
                          runnr => $qv->{'runnr'} );
  my @obs;
  push @obs, $obs;
  my $group = new OMP::Info::ObsGroup( obs => \@obs );
  $group->commentScan;
  obs_table( $group );

  print "<br>\n";
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
  my $cgi = shift;
  my $qv = $cgi->Vars;

  # Figure out which telescope we're doing.
  my $telescope;
  if( exists($qv->{'telescope'}) && defined( $qv->{'telescope'} ) ) {
    $telescope = $qv->{'telescope'};
  } else {
    throw OMP::Error::BadArgs("Must include telescope when attempting to view thumbnail page.\n");
  }

  # Grab the UT date.
  my $ut;
  if( exists( $qv->{'ut'}) && defined( $qv->{'ut'} ) ) {
    ( $ut = $qv->{'ut'} ) =~ s/-//g;
  } else {
    # Default to today's UT date.
    ( $ut = OMP::General->today() ) =~ s/-//g;
  }

  # Get the list of instruments for that telescope.
  my @instruments = OMP::Config->getData( 'instruments',
                                          telescope => $telescope );

  # For each instrument, we're going to get the directory listing for
  # the appropriate night. If the instrument name begins with "rx", skip
  # it (since all heterodyne instruments will be gobbled up by the
  # "heterodyne" instrument, and they all write to the same directory).

  foreach my $instrument ( @instruments ) {

    # Get the directory.
    my $directory = OMP::Config->getData('reducedgroupdir',
                                         telescope => $telescope,
                                         instrument => $instrument,
                                         utdate => $ut,
                                        );

    # Get a directory listing.
    my $dir_h;
    opendir( $dir_h, $directory ) or
      throw OMP::Error( "Could not open directory $directory for WORF thumbnail display: $!\n" );

    my @files = readdir $dir_h or
      throw OMP::Error( "Could not read directory $directory for WORF thumbnail display: $!\n" );

    closedir $dir_h;

    # Filter the files according to the groupregexp config.
    my @grpregex = OMP::Config->getData('groupregexp',
                                        telescope => $telescope
                                       );
    my $groupregex = join ',', @grpregex;
    @grpregex = split /\|\|\|/, $groupregex;
    my @matchfiles;
    foreach my $regex ( @grpregex ) {
      my @tmp = grep /$regex/, @files;
      push @matchfiles, @tmp;
    }

    # Sort them just in case they're not sorted.
    @matchfiles = sort @matchfiles;

    # Now we have a list of all the group files for the telescope
    # that match the group format.

    # Create Info::Obs objects for each file.
    FILELOOP: foreach my $file ( @matchfiles ) {

      if( $file =~ /_0_/ ) { next FILELOOP; }

      my $obs;
      try {
        $obs = readfile OMP::Info::Obs( $directory . "/" . $file );
      }
      catch OMP::Error with {
        next FILELOOP;
      }
      otherwise {
        next FILELOOP;
      };
      # If necessary, let's filter them for project ID.
      if( exists( $qv->{'projid'} ) && defined( $qv->{'projid'} ) &&
          uc( $obs->projectid ) ne uc( $qv->{'projid'} ) ) {
        next FILELOOP;
      }

      # Create a WORF object.
      my $worf = new OMP::WORF( obs => $obs );

      # Get a list of suffices.
      my @grp_suffices = $worf->suffices( 1 );

      # Format the observation start time so WORF can understand it.
      my $obsut = $obs->startobs->ymd . "-" . $obs->startobs->hour;
      $obsut .= "-" . $obs->startobs->minute . "-" . $obs->startobs->second;

      # If this file's suffix is either blank or matches one of the
      # suffices in @grp_suffices, write the HTML that will display
      # the thumbnail along with a link to the fullsized WORF page
      # for that observation.
      if( $file =~ /\d\.sdf$/ ) {
        print "<a href=\"worf.pl?ut=$obsut&runnr=";
        print $obs->runnr . "&inst=" . $obs->instrument;
        print "&group=1\">";
        print "<img src=\"worf_image.pl?";
        print "runnr=" . $obs->runnr;
        print "&ut=" . $obsut;
        print "&inst=" . $obs->instrument;
        print "&group=1";
        print "&size=thumb\"></a> ";
        next FILELOOP;
      } else {
        foreach my $suffix ( @grp_suffices ) {
          if( $file =~ /$suffix\.sdf$/ ) {
            print "<a href=\"worf.pl?ut=$obsut&runnr=";
            print $obs->runnr . "&inst=" . $obs->instrument;
            print "&suffix=$suffix";
            print "&group=1\">";
            print "<img src=\"worf_image.pl?";
            print "runnr=" . $obs->runnr;
            print "&ut=" . $obsut;
            print "&inst=" . $obs->instrument;
            print "&group=1";
            print "&size=thumb";
            print "&suffix=$suffix\"></a> ";
            next FILELOOP;
          }
        }
      }
    }

  }

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
