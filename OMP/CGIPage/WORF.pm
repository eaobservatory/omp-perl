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
use Carp;

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
our @EXPORT = qw( display_page thumbnails_page );

our %EXPORT_TAGS = (
                    'all' => [ @EXPORT ]
                    );

Exporter::export_tags(qw/ all /);

=head1 Routines

All routines are exported by default.

=cut

sub display_page {
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
  if( $projectid ne 'staff' ) {
    $project = OMP::ProjServer->projectDetails( $projectid,
                                                $password,
                                                'object' );
  }

  $qv->{'ut'} =~ /^(\d{4}-\d\d-\d\d)/;
  my $ut = $1;

  my $adb = new OMP::ArchiveDB( DB => new OMP::DBbackend::Archive );
  my $obs = $adb->getObs( instrument => $qv->{'inst'},
                          ut => $1,
                          runnr => $qv->{'runnr'} );

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
    ( $ut = OMP::General->today() ) =~ s/-//g;
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
        my $Error = shift;
        my $errortext = $Error->{'-text'};
        OMP::General->log_message("Unable to read file to form Obs object: $errortext\n");
        next FILELOOP;
      }
      otherwise {
        my $Error = shift;
        my $errortext = $Error->{'-text'};
        OMP::General->log_message("Unable to read file to form Obs object: $errortext\n");
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

=cut

1;
