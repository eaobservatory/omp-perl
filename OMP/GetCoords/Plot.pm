=head1 NAME

OMP::GetCoords::Plot - Source plotting module

=head1 SUBROUTINES

=over 4

=cut

package OMP::GetCoords::Plot;

use strict;

use Astro::SourcePlot qw/sourceplot/;
use Time::Piece qw/ :override /;

use OMP::Config;
use OMP::GetCoords qw/get_coords/;
use OMP::MSB;
use OMP::SpServer;
use OMP::SciProg;

use base qw/Exporter/;

our @EXPORT_OK = qw/plot_sources/;

# Environment settings for PGPLOT.
$ENV{PGPLOT_DIR} = "/star/bin" unless exists $ENV{PGPLOT_DIR};
$ENV{PGPLOT_FONT} = "/star/etc/grfont.dat" unless exists $ENV{PGPLOT_FONT};

our $debug = 0;

=item plot_sources

This routine plots the EL of sources as a function of Time.

    plot_sources(%opt);

Options:

=over 4

=item proj

Project to plot (no default)

=item ut

Utdate to plot for (YYYYMMDD)

=item tel

Telescope name [MKO]

=item mode

Sources to plot: [active] | completed | all

=item ptype

[TIMEEL]/AZEL/TIMEAZ/TIMEPA/TIMENA

=item tzone

[10 = HAWAII]

=item agrid

[0] EL grid; 1: airmass grid

=item label

[curve] along track; list: on the side

=item output

Output file (passed on to Astro::SourcePlot::sourceplot).

=item hdevice

PGPLOT device (passed on to Astro::SourcePlot::sourceplot).

=back

A project name is required.

=cut


sub plot_sources {
    my %opt = @_;

    my $prj = $opt{'proj'};
    my $pld = $opt{'ut'};
    my $tel = $opt{'tel'};
    my $mod = $opt{'mode'};
    my $ptype = $opt{'ptype'};
    my $objs = $opt{'obj'};
    my $tzone = $opt{'tzone'};
    my $agrid = $opt{'agrid'};
    my $labpos = $opt{'label'};
    my $output = $opt{'output'} || '';
    my $hdevice = $opt{'hdevice'} || '/XW';

    # Make all parameters trusted

    # Project:
    my $projlis;
    unless (defined $prj) {
        die 'You must specify a science program';
    }
    $prj =~ /^([\w\@\/\$\.\_]+)$/ && ($projlis = $1) || ($projlis = "");

    my $objlis;
    if (defined $objs) {
        $objs =~ /^([\w\@\/\$\.\_\s]+)$/ && ($objlis = $1) || ($objlis = "");
    }

    # UT date
    my $utdate;
    if (defined $pld) {
        $pld =~ /^(\d{8})$/ && ($utdate = $1) || ($utdate = "");
        if ($utdate !~ /^\d{8}$/) {
            die "UTDATE '$pld' must have format YYYYMMDD";
        }
    } else {
        my ($us, $um, $uh, $md, $mo, $yr, $wd, $yd, $isdst) = gmtime(time);
        $yr += 1900;
        $mo += 1;
        $utdate = 10000 * $yr + 100 * $mo + $md;
    }

    # Telescope:
    my $telescope;
    if (defined $tel) {
        $tel =~ /^([\w\+\-\.\_]+)$/ && ($telescope = $1) || ($telescope = "");
        if ($telescope eq "") {
            die "Telescope '$tel' should be regular text string";
        }
    } else {
         $telescope = 'JCMT';
         $telescope = 'UKIRT' if ($projlis =~ /^u\//i);
    }

    # Mode:
    my $plmode;
    if (defined $mod) {
        $mod =~ /^([\w\+\-\.\_]+)$/ && ($plmode = $1) || ($plmode = "");
        if ($plmode !~ /^all$/i && $plmode !~ /^active$/i && $plmode !~ /^completed$/i) {
            die "MODE must be [ all | active | completed ]";
        }
    } else {
        $plmode = "Active";
    }

    #----------------------------------------------------------------------
    # Hash with regular sourceplot arguments being passed through directly
    my %sargs = (
        output => $output,
        hdevice => $hdevice,
    );

    # Debug: pipe debug request down to Sourceplot
    if ($debug) {
        $sargs{'debug'} = 1;
    }

    # Format:
    if (defined $ptype && $ptype ne "TIMEEL") {
        $ptype =~ /^([\w\+\-\.\_]+)$/ && ($sargs{'format'} = "$1");
    }

    # Timezone:
    if (defined $tzone && $tzone != 10) {
        $tzone =~ /^([\w\+\-\.\_]+)$/ && ($sargs{'ut0hr'} = "$1");
    }

    # Airmassgrid:
    if (defined $agrid && $agrid != 0) {
        $agrid =~ /^([\w\+\-\.\_]+)$/ && ($sargs{'airmassgrid'} = 1);
    }

    # Label position:
    if (defined $labpos && $labpos ne "curve") {
        $labpos =~ /^([\w\+\-\.\_]+)$/ && ($sargs{'objlabel'} = "$1");
    }

    if ($utdate =~ /^\d{8}$/) {
        $sargs{'start'} = Time::Piece->strptime( "${utdate}T00:00:00", "%Y%m%dT%T");
        $sargs{'end'}   = Time::Piece->strptime( "${utdate}T23:59:59", "%Y%m%dT%T");

        if ($tel =~ /jcmt/i or $projlis =~ /^m\d/i) {
            # Plot around shift change
            $sargs{'plot_center'} = 1.5*3600.0;
        }
        if ($tel =~ /ukirt/i or $projlis =~ /^u\//i) {
            # Plot smaller time window for UKIRT
            $sargs{'plot_int'} = 7 * 3600;
            # Also stop tracks outside time window in AZEL plot
            $sargs{'start'} = Time::Piece->strptime( "${utdate}T03:00:00", "%Y%m%dT%T");
            $sargs{'end'}   = Time::Piece->strptime( "${utdate}T16:59:59", "%Y%m%dT%T");
        }
    }
    else {
        die "Invalid UTDATE: '$utdate'";
    }


    # Project array
    my @projids = split( /\@/, $projlis );

    # Array of hashes
    my @objects;
    if ( $objlis ne "" ) {

        my @solar = ('mars', 'jupiter', 'saturn', 'uranus', 'neptune',
                     'mercury', 'venus', 'sun', 'moon');

        foreach my $obj (split( /\@/, $objlis )){

            if ( $obj ne "planets" && $obj ne "5planets" &&
                 $obj ne "solar" ) {

                my %ref;
                $ref{'name'} = "$obj";
                push @objects, \%ref;

            } else {

                my $nrplanets = 7;
                $nrplanets = 9 if ($obj eq "solar");
                $nrplanets = 5 if ($obj eq "5planets");
                for (my $i = 0; $i < $nrplanets; $i++) {
                    my %ref;
                    $ref{'name'} = $solar[$i];
                    push @objects, \%ref;
                }
            }
        }
    }

    $sargs{'telescope'} = $telescope;
    $sargs{'msbmode'} = $plmode;

    print "Projid: $projlis $utdate $telescope $plmode $output $hdevice\n" if ($debug);

    my @coords = get_coords( 'omp', \@projids, \@objects, %sargs );
    printf "Nr of objects found: %d\n", $#coords+1 if ($debug);

    # Call plot subtroutine
    my $plot;

    if ($#coords >= 0) {
      print "Calling sourceplot...\n" if ($debug);
      $plot = sourceplot( coords => \@coords, %sargs );
      print "Output saved to: ${plot}\n" if ($debug and $hdevice ne "xw");
    } else {
      die "No objects found";
    }
}


1;

__END__

=back

=head1 COPYRIGHT

Copyright (C) 2004 Particle Physics and Astronomy Research Council.
Copyright (C) 2015 East Asian Observatory.
All Rights Reserved.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful,but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc., 59 Temple
Place,Suite 330, Boston, MA  02111-1307, USA

=cut
