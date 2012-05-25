package OMP::CGIPage::WORF;

=head1 NAME

OMP::CGIPage::WORF - Display WORF web pages

=head1 SYNOPSIS

  use OMP::CGIPage::WORF;

=head1 DESCRIPTION

This module provides routines for the display of complete
WORF web pages.

=cut

use strict;
use warnings;

use CGI;
use CGI::Carp qw/ fatalsToBrowser /;
use Net::Domain qw/ hostfqdn /;

use OMP::CGIComponent::Obslog qw/ obs_table /;
use OMP::CGIComponent::WORF;
use OMP::Error qw/ :try /;
use OMP::General;
use OMP::Info::Obs;
use OMP::WORF;

our $VERSION = (qw$Revision$ )[1];

require Exporter;

our @ISA = qw/Exporter/;

our %EXPORT_TAGS = (
    'all' => [qw/display_page thumbnails_page/]
  );

Exporter::export_tags(qw/ all /);

=head1 Routines

All routines are exported by default.

=cut

sub display_page {
  my $cgi = shift;
  my %cookie = @_;
  my $qv = $cgi->Vars;

  # Filter out CGI variables.
  my $inst;
  if( exists( $qv->{'inst'} ) && defined( $qv->{'inst'} ) ) {
    $qv->{'inst'} =~ /([\-\w\d]+)/;
    $inst = $1;
  }
  my $runnr;
  if( exists( $qv->{'runnr'} ) && defined( $qv->{'runnr'} ) ) {
    $qv->{'runnr'} =~ /(\d+)/;
    $runnr = $1;
  }
  my $ut;
  my $utdatetime;
  if( exists( $qv->{'ut'} ) && defined( $qv->{'ut'} ) ) {
    $qv->{'ut'} =~ /^(\d{4}-\d\d-\d\d)/;
    $ut = $1;
    $qv->{'ut'} =~ /^(\d{4}-\d\d-\d\d-\d\d?-\d\d?-\d\d?)/;
    $utdatetime = $1;
  }

  my $xstart;
  if( exists( $qv->{'xstart'} ) && defined( $qv->{'xstart'} ) ) {
    $qv->{'xstart'} =~ /(\d+)/;
    $xstart = $1;
  }
  my $xend;
  if( exists( $qv->{'xend'} ) && defined( $qv->{'xend'} ) ) {
    $qv->{'xend'} =~ /(\d+)/;
    $xend = $1;
  }
  my $ystart;
  if( exists( $qv->{'ystart'} ) && defined( $qv->{'ystart'} ) ) {
    $qv->{'ystart'} =~ /(\d+)/;
    $ystart = $1;
  }
  my $yend;
  if( exists( $qv->{'yend'} ) && defined( $qv->{'yend'} ) ) {
    $qv->{'yend'} =~ /(\d+)/;
    $yend = $1;
  }
  my $zmin;
  if( exists( $qv->{'zmin'} ) && defined( $qv->{'zmin'} ) ) {
    $qv->{'zmin'} =~ /([\d\.\-eE]+)/;
    $zmin = $1;
  }
  my $zmax;
  if( exists( $qv->{'zmax'} ) && defined( $qv->{'zmax'} ) ) {
    $qv->{'zmax'} =~ /([\d\.\-eE]+)/;
    $zmax = $1;
  }
  my $autocut;
  if( exists( $qv->{'autocut'} ) && defined( $qv->{'autocut'} ) ) {
    $qv->{'autocut'} =~ /(\d+)/;
    $autocut = $1;
  }
  my $cgi_group;
  if( exists( $qv->{'group'} ) && defined( $qv->{'group'} ) ) {
    $qv->{'group'} =~ /(\d+)/;
    $cgi_group = $1;
  }

  my $lut;
  if( exists( $qv->{'lut'} ) && defined( $qv->{'lut'} ) ) {
    $qv->{'lut'} =~ /([\w\d]+)/;
    $lut = $1;
  }

  my $size;
  if( exists( $qv->{'size'} ) && defined( $qv->{'size'} ) ) {
    $qv->{'size'} =~ /(\w+)/;
    $size = $1;
  }
  my $type;
  if( exists( $qv->{'type'} ) && defined( $qv->{'type'} ) ) {
    $qv->{'type'} =~ /(\w+)/;
    $type = $1;
  }
  my $cut;
  if( exists( $qv->{'cut'} ) && defined( $qv->{'cut'} ) ) {
    $qv->{'cut'} =~ /(\w+)/;
    $cut = $1;
  }
  my $suffix;
  if( exists( $qv->{'suffix'} ) && defined( $qv->{'suffix'} ) ) {
    $qv->{'suffix'} =~ /([\d\w_]+)/;
    $suffix = $1;
  }

  my $projectid;
  my $password;

  if( exists( $cookie{projectid} ) && defined( $cookie{projectid} ) ) {
    $projectid = $cookie{projectid};
    $password = $cookie{password};
  } else {
    $projectid = 'staff';
  }

  my $project;
  if( $projectid ne 'staff' ) {
    $project = OMP::ProjServer->projectDetails( $projectid,
                                                $password,
                                                'object' );
  }

  my $adb = new OMP::ArchiveDB( );
  my $obs = $adb->getObs( instrument => $inst,
                          ut => $ut,
                          runnr => $runnr, );

  if( $projectid ne 'staff' && lc( $obs->projectid ) ne lc( $projectid ) &&
      $obs->isScience ) {
    print "Observation does not match project $projectid.\n";
    return;
  }

  my @obs;
  push @obs, $obs;
  my $group = new OMP::Info::ObsGroup( obs => \@obs );
  $group->commentScan;
  obs_table( $group );

# Display the observation.
  print "<br>\n";
  print "<img src=\"worf_image.pl?";
  print "runnr=$runnr";
  print "&ut=$utdatetime";
  print "&inst=$inst";
  print ( defined( $xstart ) ? "&xstart=$xstart" : '' );
  print ( defined( $xend ) ? "&xend=$xend" : '' );
  print ( defined( $ystart ) ? "&ystart=$ystart" : '' );
  print ( defined( $yend ) ? "&yend=$yend" : '' );
  print ( defined( $zmin ) ? "&zmin=$zmin" : '' );
  print ( defined( $zmax ) ? "&zmax=$zmax" : '' );
  print ( defined( $autocut ) ? "&autocut=$autocut" : '' );
  print ( defined( $lut ) ? "&lut=$lut" : '' );
  print ( defined( $size ) ? "&size=$size" : '' );
  print ( defined( $type ) ? "&type=$type" : '' );
  print ( defined( $cut ) ? "&cut=$cut" : '' );
  print ( defined( $suffix ) ? "&suffix=$suffix" : '' );
  print ( defined( $cgi_group ) ? "&group=$cgi_group" : '' );
  print "\"><br><br>\n";

# Print a link to download the FITS file.
  print "<a href=\"worf_fits.pl?";
  print "runnr=$runnr";
  print "&ut=$utdatetime";
  print "&inst=$inst";
  print ( defined( $suffix ) ? "&suffix=$suffix" : '' );
  print ( defined( $cgi_group ) ? "&group=$cgi_group" : '' );
  print "\">Download FITS file</a> (right-click and Save As)<br>\n";

# Print a link to download the NDF file.
  print "<a href=\"worf_ndf.pl?";
  print "runnr=$runnr";
  print "&ut=$utdatetime";
  print "&inst=$inst";
  print ( defined( $suffix ) ? "&suffix=$suffix" : '' );
  print ( defined( $cgi_group ) ? "&group=$cgi_group" : '' );
  print "\">Download NDF file</a> (right-click and Save As)<br>\n";

# Print a link to load the image using Aladin.
  print "<a href=\"http://vizier.hia.nrc.ca/viz-bin/nph-aladin.pl?frame=launching&script=get+Local%28http:%2f%2fomp.jach.hawaii.edu%2fcgi-bin%2fworf_fits.pl%3f";
  print "runnr%3d$runnr";
  print "%26ut%3d$utdatetime";
  print "%26inst%3d$inst";
  print ( defined( $suffix ) ? "%26suffix%3d$suffix" : '' );
  print ( defined( $cgi_group ) ? "%26group%3d$cgi_group" : '' );
  print "%29%3b\">Open with Aladin Java applet</a> (imaging mode only)<br><br>\n";

  OMP::CGIComponent::WORF::options_form( $cgi );

#  print_worf_footer();

}

sub thumbnails_page {
  my $cgi = shift;
  my %cookie = @_;
  my $qv = $cgi->Vars;

  my $projectid;
  my $password;

  if( exists( $cookie{projectid} ) && defined( $cookie{projectid} ) ) {
    $projectid = $cookie{projectid};
    $password = $cookie{password};
  } else {
    $projectid = 'staff';
  }

  my $project;
  my $worflink;
  if( $projectid ne 'staff' ) {
    $project = OMP::ProjServer->projectDetails( $projectid,
                                                $password,
                                                'object' );
    $worflink = "fbworf.pl";
  } else {
    $worflink = "staffworf.pl";
  }

  # Figure out which telescope we're doing.
  my $telescope;
  if( exists($qv->{'telescope'}) && defined( $qv->{'telescope'} ) ) {
    $telescope = $qv->{'telescope'};
  } else {

    # Try to determine the telescope from the project details.
    if( defined( $project ) ) {
      $telescope = $project->telescope;
    }

    if( !defined( $telescope ) ) {

      # Use the hostname of the computer we're running on.
      my $hostname = hostfqdn;
      if($hostname =~ /ulili/i) {
        $telescope = "JCMT";
      } elsif ($hostname =~ /mauiola/i) {
        $telescope = "UKIRT";
      } else {

        throw OMP::Error::BadArgs("Must include telescope when attempting to view thumbnail page.\n");
      }
    }
  }

  # Grab the UT date.
  my $ut;
  if( exists( $qv->{'ut'}) && defined( $qv->{'ut'} ) ) {
    ( $ut = $qv->{'ut'} ) =~ s/-//g;
  } else {
    # Default to today's UT date.
    ( $ut = OMP::DateTools->today() ) =~ s/-//g;
  }

  # Get the list of instruments for that telescope.
  my @instruments = OMP::Config->getData( 'instruments',
                                          telescope => $telescope );

  # Print a header table.
  print "<table class=\"sum_table\" border=\"0\">\n<tr class=\"sum_table_head\">";
  print "<td><strong class=\"small_title\">WORF Thumbnails for $ut</strong></td></tr></table>\n";

  # For each instrument, we're going to get the directory listing for
  # the appropriate night. If the instrument name begins with "rx", skip
  # it (since all heterodyne instruments will be gobbled up by the
  # "heterodyne" instrument, and they all write to the same directory).

  foreach my $instrument ( @instruments ) {

    next if $instrument =~ /^rx/i;

    # Get the directory.
    my $directory;
    if( $instrument =~ /heterodyne/i ) {
      $directory = OMP::Config->getData('rawdatadir',
                                        telescope => $telescope,
                                        instrument => $instrument,
                                        utdate => $ut,
                                       );
      $directory =~ s/\/dem$//;
    } else {
      $directory = OMP::Config->getData('reducedgroupdir',
                                        telescope => $telescope,
                                        instrument => $instrument,
                                        utdate => $ut,
                                       );
    }

    # Get a directory listing.
    my $dir_h;
    next if ( ! -d $directory );
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
    my @matchfiles = grep /$groupregex/, @files;

    # Sort them just in case they're not sorted.
    @matchfiles = sort OMP::CGIComponent::WORF::obsnumsort @matchfiles;

    # Now we have a list of all the group files for the telescope
    # that match the group format.

    print "<table class=\"sum_table\" border=\"0\">\n";
    my $rowclass="row_b";
    print "<tr class=\"$rowclass\">";

    my %displayed;
    my $curgrp;
    # Create Info::Obs objects for each file.
    FILELOOP: foreach my $file ( @matchfiles ) {

      if( $file =~ /_0_/ ) { next FILELOOP; }

      my $obs;
      try {
        $obs = readfile OMP::Info::Obs( $directory . "/" . $file );
      }
      catch OMP::Error with {
        # Errors are already logged in OMP::Info::Obs::readfile, so just
        # skip to the next file.
        next FILELOOP;
      }
      otherwise {
        # Errors are already logged in OMP::Info::Obs::readfile, so just
        # skip to the next file.
        next FILELOOP;
      };

      # If necessary, let's filter them for project ID.
      if( $projectid ne 'staff' &&
          uc( $obs->projectid ) ne uc( $projectid ) &&
          ! $obs->isScience ) {
        next FILELOOP;
      }

      next FILELOOP if ! defined $obs;

      # Create a WORF object.
      my $worf;
      try {
        $worf = new OMP::WORF( obs => $obs );
      }
      catch OMP::Error with {
        my $Error = shift;
        my $errortext = $Error->{'-text'};
        print STDERR "Unable to form WORF object: $errortext\n";
        next FILELOOP;
      }
      otherwise {
        my $Error = shift;
        my $errortext = $Error->{'-text'};
        print STDERR "Unable to form WORF object: $errortext\n";
        next FILELOOP;
      };

      # Get a list of suffices.
      my @suffices = $worf->suffices( 1 );
      if( $instrument =~ /heterodyne/ ) {
        @suffices = $worf->suffices( 0 );
      }

      # Format the observation start time so WORF can understand it.
      my $obsut = $obs->startobs->ymd . "-" . $obs->startobs->hour;
      $obsut .= "-" . $obs->startobs->minute . "-" . $obs->startobs->second;

      # If this file's suffix is either blank or matches one of the
      # suffices in @suffices, write the HTML that will display
      # the thumbnail along with a link to the fullsized WORF page
      # for that observation.
      if( $file =~ /\d\.sdf$/ ) {
        if( defined( $curgrp ) ) {
          my $runnr;
          if( !defined( $obs->runnr ) ) {
            $file =~ /_(\d{4})_/;
            $runnr = int( $1 );
          } else {
            $runnr = $obs->runnr;
          }
          if( $runnr != $curgrp ) {
            $rowclass = ( $rowclass eq 'row_a' ) ? 'row_b' : 'row_a';
            print "</tr><tr class=\"$rowclass\">";
            $curgrp = $obs->runnr;
            if( ! defined( $obs->runnr ) ) {
              # SCUBA rebinned image hack
              $file =~ /_(\d{4})_/;
              $curgrp = int( $1 );
            }
          }
        } else {
          $curgrp = $obs->runnr;
          if( ! defined( $obs->runnr ) ) {
            # SCUBA rebinned image hack
            $file =~ /_(\d{4})_/;
            $curgrp = int( $1 );
          }
        }
        my $key = $instrument . $curgrp;
        if( $displayed{$key} ) { next FILELOOP; }
        print "<td>";
        print "<a href=\"$worflink?ut=$obsut&runnr=";
        print $curgrp . "&inst=" . $obs->instrument;
        if( $instrument !~ /heterodyne/ ) { print "&group=1"; }
        print "\">";
        print "<img src=\"worf_image.pl?";
        print "runnr=" . $curgrp;
        print "&ut=" . $obsut;
        print "&inst=" . $obs->instrument;
        if( $instrument !~ /heterodyne/ ) { print "&group=1"; }
        print "&size=thumb\"></a>";
        print "</td><td>";
        print "Instrument:&nbsp;" . $obs->instrument . "<br>\n";
        print "Group&nbsp;number:&nbsp;" . $curgrp . "<br>\n";
        print "Target:&nbsp;" . ( defined( $obs->target ) ? $obs->target : '' ) . "<br>\n";
        print "Project:&nbsp;" . ( defined( $obs->projectid ) ? $obs->projectid : '' ) . "<br>\n";
        print "Exposure time:&nbsp;" . ( defined( $obs->duration ) ? $obs->duration : '' ) . "<br>\n";
        print "Suffix:&nbsp;none\n</td>";
        $displayed{$key}++;
        next FILELOOP;
      } else {
        foreach my $suffix ( @suffices ) {
          if( ( ( uc($telescope) eq 'UKIRT') && ($file =~ /$suffix\./ ) ) ||
              ( ( uc($telescope) eq 'JCMT')  && ($file =~ /$suffix/   ) ) ) {
            if( defined( $curgrp ) ) {
              my $runnr;
              if( !defined( $obs->runnr ) ) {
                $file =~ /_(\d{4})_/;
                $runnr = int( $1 );
              } else {
                $runnr = $obs->runnr;
              }
              if( $runnr != $curgrp ) {
                $rowclass = ( $rowclass eq 'row_a' ) ? 'row_b' : 'row_a';
                print "</tr>\n<tr class=\"$rowclass\">";
                $curgrp = $obs->runnr;
                if( ! defined( $obs->runnr ) ) {
                  # SCUBA rebinned image hack
                  $file =~ /_(\d{4})_/;
                  $curgrp = int( $1 );
                }
              }
            } else {
              $curgrp = $obs->runnr;
              if( !defined( $obs->runnr ) ) {
                # SCUBA rebinned image hack
                $file =~ /_(\d{4})_/;
                $curgrp = int( $1 );
              }
            }
            my $key = $instrument . $curgrp . $suffix;
            if( $displayed{$key} ) { next FILELOOP; }
            print "<td>";
            print "<a href=\"$worflink?ut=$obsut&runnr=";
            print $curgrp . "&inst=" . $obs->instrument;
            print "&suffix=$suffix";
            if( $instrument !~ /heterodyne/ ) { print "&group=1"; }
            print "\">";
            print "<img src=\"worf_image.pl?";
            print "runnr=" . $curgrp;
            print "&ut=" . $obsut;
            print "&inst=" . $obs->instrument;
            if( $instrument !~ /heterodyne/ ) { print "&group=1"; }
            print "&size=thumb";
            print "&suffix=$suffix\"></a>";
            print "</td><td>";
            print "Instrument:&nbsp;" . $obs->instrument . "<br>\n";
            print "Group&nbsp;number:&nbsp;" . $curgrp . "<br>\n";
            print "Target:&nbsp;" . ( defined( $obs->target ) ? $obs->target : '' ) . "<br>\n";
        print "Project:&nbsp;" . ( defined( $obs->projectid ) ? $obs->projectid : '' ) . "<br>\n";
        print "Exposure time:&nbsp;" . ( defined( $obs->duration ) ? $obs->duration : '' ) . "<br>\n";
            print "Suffix:&nbsp;" . $suffix . "\n</td>";
            $displayed{$key}++;
            next FILELOOP;
          }
        }
      }
    }

    # End the table.
    print "</table>\n";

  }

}

=head1 SEE ALSO

C<OMP::CGIComponent::WORF>, C<OMP::CGIComponent::Obslog>

=head1 AUTHOR

Brad Cavanagh E<lt>b.cavanagh@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2004 Particle Physics and Astronomy Research Council.
All Rights Reserved.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program (see SLA_CONDITIONS); if not, write to the
Free Software Foundation, Inc., 59 Temple Place, Suite 330,
Boston, MA  02111-1307  USA

=cut

1;
