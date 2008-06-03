package SourcePlot_new;

#package Astro::SourcePlot_new;

=head1 NAME

Astro::SourcePlot - Plot astronomical source tracks

=head1 SYNOPSIS

  use Astro::SourcePlot qw/ sourceplot /;
  sourceplot( coords => \@coords, %options );

=head1 DESCRIPTION

This module provides a function for plotting the position of
astronomical targets on the sky during a 24 hour period. Plots can be
constructed from two of azimuth, elevation, parallactic angle, time or
nasmyth angle.

=cut

use strict;
use warnings;
use Math::Trig;
use Astro::SLA;
use Astro::Coords;
use Astro::Telescope;
use Time::Piece qw/ :override /;
use PGPLOT;

use vars qw/ $VERSION @ISA @EXPORT_OK/;
$VERSION = '1.1';

use Exporter;
@ISA = ('Exporter');
@EXPORT_OK = ( 'sourceplot' );

=head1 FUNCTIONS

=over 4

=item B<sourceplot>

Make AZ-EL or TIME-EL plot for sources provided.  Returns the name of
the GIF file with the image.

  $gif = sourceplot( coords => \@coords, hdevice => '/gif' );

  sourceplot( coords => \@coords, hdevice => '/xw');

Hash arguments:

=over 4

=item start

Start time of the plot as a C<Time::Piece> object. Defaults to current
date at midnight UT.

=item end

End time of the plot as a C<Time::Piece> object. Defaults to end of current day
(UT).

=item coords

Array of coordinate objects to be plotted. Supplied as C<Astro::Coords>
objects.

=item ut0hr

Local time zone offset for plot relative to UT. Positive offset
indicates the time zone is behind UT. Defaults to 10 (Hawaii).

=item format

Format for the plot. Can be C<TIMEEL>, C<TIMEAZ>, C<TIMEPA>
(parallactic angle against time), C<TIMENA> (Nasmyth angle against
time), C<AZEL>. Defaults to C<TIMEEL>.

=item hdevice

Device name. This is usually the PGPLOT device name. Defaults
to '/GIF'.

=item output

Name of output file. Only relevant for hard copy devices.
Defaults to 'sourceplot.gif'. Must set this to an empty string
if using an X device such as '/XW'.

=item increment

Time gap (seconds) between each calculated point. The plots are
generated more rapidly if this number is large but the curves will not
be smooth. Defaults to 600 seconds.

=item plot_center

For the time axis, offset of the plot center from local midnight
(in seconds). Defaults to local midnight.

=item plot_int

For the time axis, time interval to plot (in seconds). The plot will
be from -plot_int to plot_int around the plot_center.
Default to 43200 (i.e. 12 hours)

=item title

Item format will be 'telescope utdate title'

=item titlescale

Size of plot title. Defaults to 1.25.

=item labelscale

Size of labels along axes. Defaults to 1.0.

=item axisscal

Size of numbers along axes. Defaults to 0.75.

=item defcol

Default color as PGPLOT index: white [1].

=item defstyle

Default PGPLOT line style: 1=solid

=item gridcol

Inner grid color as PGPLOT index: default dim grey [14]

=item gridstyle

Inner grid line style: 1=solid, 3=dashed, 4=dotted, -1=no inner grid.
Defaults to 1=solid.

=item airmassgrid

For timeel plot: 1=draw airmass grid instead of EL grid, 0=EL grid
Defaults to EL grid (0)

=item heavylw

Weight for any thick lines (default = 3).

=item annominel

Draw dashed line at a the specified elevation in deg (-1=no line)
Defaults to 30

=item annotrack

For AZEL plots annotate each source track with the current hour.
Default to true.

=item objlabel

Position of source labels on the plot. 'list' labells as list along
left of plot, 'curve' aligns label with each curve. Default to
'curve'.

=item objscale

Size of source name labels (default 0.75).

=item objlw

Line weight for object names. Defaults to 3.

=item objdot

Whether to place a big dot at the current time. Defaults to true.

=item mag

Overall scaling of plot wrt canvas.  Use the factor 'mag' to enlarge
(>1) or shrink (<1) the plot wrt.  to the plot window e.g. to allow
for more annotations.

=back

=cut

sub sourceplot {

  # Default plot for current day (UT).
  my $date = gmtime->ymd;
  my $utnow = gmtime->hour +
              gmtime->minute/60.0 +
              gmtime->second/3600.0;

  # Default source info: Astro::Coords object
  my @defcoords;
  my $c = new Astro::Coords(  name  => 'Default',
			      ra    => '12:00:00.00',
			      dec   => '00:00:00.00',
			      type  => 'J2000',
			      units => 'sexagesimal'
                            );

  my $telescope;
  $c->telescope( new Astro::Telescope( 'JCMT' ));
  push(@defcoords, $c);

  # Set up hash of defaults
  my %defaults = (

    #----------------------- Main Arguments ---------------------------
    # Defaults for main arguments

    debug => 0,

    # Start and end time plot (date end ignored).
    start  => Time::Piece->strptime( "${date}T00:00:00", "%Y-%m-%dT%T"),
    end    => Time::Piece->strptime( "${date}T23:59:59", "%Y-%m-%dT%T"),

    # Astro::Coords objects be plotted, includes observatory name.
    coords => \@defcoords,

    # Timezone info for observatory: can not be found elsewhere!
    telescope => "From_Coord",        # Default: pick up from coord obj
    ut0hr  => 10,                     # UT at midnight local Mauna Kea


    #------------------------- PLOT STYLE -----------------------------
    # Default plot layout to be overwritten by optional arguments

    format      => 'timeel',          # 'TIMEEL', 'TIMEAZ', 'TIMEPA', 
                                      # 'TIMENA', or 'AZEL'
    hdevice     => "/gif",            # GKS plot device ('/' optional)
    output      => "sourceplot.gif",  # Filename for plot
    increment   => 600,               # (secs) Calculate and plot points
                                      # every for 'increment' seconds.
    plot_center => 0.0,               # (secs) Default: local midnight
    plot_int    => 43200,             # (secs) +/-Plot interval
    title       => "",                # Plot title will be 'tel ut title'
    titlescale  => 1.25,              # Size plottitle
    labelscale  => 1.0,               # Size labels along axes
    axisscale   => 0.75,              # Size numbers along axes
    defcol      => 1,                 # Default color: white
    defstyle    => 1,                 # Default line style: 1=solid
    gridcol     => 14,                # Inner grid color: dim grey
    gridstyle   => 1,                 # Inner grid line style:
                                      # 1=solid, 3=dashed, 4=dotted
                                      # -1: no inner grid
    airmassgrid => 0,                 # TIMEEL: 0=EL, 1=airmass grid
    heavylw     => 3,                 # Weight for any thick lines
    annominel   => 30,                # Min elevation in degrees to
                                      # annotate (0 to 90; <0: none)
    annotrack   => 1,                 # Annotate track with time label
    objlabel    => 'curve',           # If 'list' labels as list along
                                      # left of plot, else with 'curve'
    objscale    => 0.75,              # Size source name labels
    objlw       => 3,                 # Line weight for object names
    objdot      => 1,                 # 1: Big dot current Pos, 0: not.

    mag         => 1.0,               # Overall scaling plot wrt. canvas

    # Use the factor 'mag' to enlarge (>1) or shrink (<1) the plot wrt.
    # to the plot window e.g. to allow for more annotations.

    # The standard PGPLOT window is rectangular resulting in ovals.
    # Use polscale to scale the x wrt y to produce circles for 'AZEL'.

  );


  # Override defaults with arguments
  my %args = ( %defaults, @_ );

  # Extract for compacter calculations
  my $debug = 0;
  if ($args{'debug'} == 1) {
    $debug = 1;
  }

  my $coords = $args{'coords'};
  my $ut0hr  = $args{'ut0hr'};
  my $utdate = $args{'start'}->ymd;
  $utdate =~ s/\-//g;                 # yyyymmdd
  $args{'plot_center'} /= 3600.0;

  # PGPLOT device name
  $args{'hdevice'} = '/' . $args{'hdevice'} if( $args{'hdevice'} !~ /^\// );
  my $hdevice = $args{'output'} . $args{'hdevice'};

  # Pick up some required date information from first coords object, unless
  # given as argument.
  if( $args{telescope} eq "From_Coord" ) {
    my $telescopeObj = $coords->[0]->telescope;
    $telescope = (defined $telescopeObj ? $telescopeObj->name : 'TELUNKNOWN');
  } else {
    # Make sure first coord element has correct telesocpe
    $telescope = $args{telescope};
    $coords->[0]->telescope( new Astro::Telescope( $telescope ));
  }

  # Calculate one Time, Az, El, PA, LST point to link UT to LST.
  # Could have used Slalib as well.
  my @dummy = $coords->[0]->calculate(start => $args{'start'},
                                        end => $args{'start'},
                                        inc => 3600,
                                      units => 'radians'
                                     );

  # UT TIME used in calculation of LST. Needed to calculate
  # LST at 0 hrs local.
  my $utref = ($dummy[0]->{'time'}->hour +
               $dummy[0]->{'time'}->minute/60.0 +
	       $dummy[0]->{'time'}->second/3600.0);

  # LST at 0 hrs local time.
  my $st0hr = 12.0/pi*$dummy[0]->{'lst'}-1.0027379093*($utref-$ut0hr);

  #*******************************************************************



  #-------------------------------------------------------------------
  # The plots window is +/-12 hrs around local_time 'plot_center'
  #-------------------------------------------------------------------
  # Calculate the UT start and stop time for the plot window:
  my $utint = $args{'plot_int'}/3600.0;
  my $utleft = $ut0hr - $utint + $args{'plot_center'};
  my $utright  = $utleft + 2*$utint;
  $utleft += 24.0 if( $utleft < -24.0 );
  $utleft -= 24.0 if( $utleft >  12.0 );

  # Calculate LST axis for the same interval.
  # See page B7 of the Almanac for the factor 1.002 737 9093
  my $lstleft  = $st0hr + 1.0027379093*(-1*$utint+$args{'plot_center'});
  my $lstright = $lstleft + 1.0027379093*2*$utint;

  #-------------------------------------------------------------------
  # Pgplot drawing routines: open hardcopy device and setup plot

  print "SOURCEPLOT DEBUG: Opening plot device '$hdevice'.\n" if($debug);
  pgbegin(0,$hdevice,1,1);

  pgpage;                                # Open new page
  pgvstand;                              # Standard view port

  # Polscale is used in AZ-EL to compensate for rectangular view port
  # so that circles will remain true to their nature.
  my ($nx1, $nx2, $ny1, $ny2) = (0,1,0,1);
  my ($vx1, $vx2, $vy1, $vy2);
  # Weird need to inquire after normalized and real both!
  #pgqvp (0, $nx1, $nx2, $ny1, $ny2);    # Inquire about dimensions
  print "SOURCEPLOT DEBUG: Inquire about dimensions.\n" if($debug);
  pgqvp (1, $vx1, $vx2, $vy1, $vy2);     # Inquire about dimensions
  my $polscale = 11/8;
  $polscale = ($nx2-$nx1)/($ny2-$ny1)*($vx2-$vx1)/($vy2-$vy1)
        if( ($ny2-$ny1)*($vy2-$vy1) != 0 );

  my ($lw);
  pgqlw( $lw );                          # Query default line weight device

  # Plot box variables: need to be available outside plot format scope.
  my ($xlo, $xhi, $xint, $xlabel);
  my ($ylo, $yhi, $yint, $ylabel);

  # Arrays to hold curves and labels to be plotted
  my (@x, @y, @xx, @yy, @dotx, @doty, @dotlabel);

  # Set up plot limits, grid spacing and label for X and Y-axis
  # Everything following this block is coded 'scale-free'.
  if( $args{'format'} =~ /azel/i ) {
    ($xlo, $xhi, $xint, $xlabel) = (-90, 90,  15.0, 'AZ');
    ($ylo, $yhi, $yint, $ylabel) = (-90, 90,  10.0, 'EL');

  } else {
    # Set up plot limits, grid spacing and label for X and Y-axis
    ($xlo, $xhi, $xint, $xlabel) = ($utleft, $utright,   4.0, 'UT');
    if( $args{'format'} =~ /timepa/i ) {
      ($ylo, $yhi, $yint, $ylabel) = ( -180.0, 180.0, 60.0, 'PA');
    } elsif( $args{'format'} =~ /timeaz/i ) {
      ($ylo, $yhi, $yint, $ylabel) = (    0.0, 360.0, 60.0, 'AZ');
    } elsif( $args{'format'} =~ /timena/i ) {
      ($ylo, $yhi, $yint, $ylabel) = ( -180.0, 180.0, 60.0, 'NA');
    } else {                #timeel
      ($ylo, $yhi, $yint, $ylabel) = (    0.0, 89.99, 20.0, 'EL');
    }
  }


  # --------------------------------
  # PLOT BOX EITHER AZ-EL OR TIME-xx
  # --------------------------------

  my $xrange = $xhi - $xlo;
  my $yrange = $yhi - $ylo;
  my $min_el;
  my $idot;

  # PLOT AZ-EL Bulls-eye
  print "SOURCEPLOT DEBUG: Setting up plot window.\n" if($debug);
  if( $args{'format'} =~ /azel/i ) {

    pgwindow( $polscale*$args{'mag'}*$xlo,
              $polscale*$args{'mag'}*$xhi,
              $args{'mag'}*$ylo,
              $args{'mag'}*$yhi
            );
    print "SOURCEPLOT DEBUG: AZEL window defined.\n" if($debug);

    pgsci( $args{'defcol'} );

    # Extra large plot label, then conform to desired size
    pgsch( $args{'titlescale'} );
    $x[0] = $xlo;
    $y[0] = $ylo + 1.06*$yrange;
    pgtext( $x[0], $y[0], "$telescope   $utdate" );
    pgsch( $args{'axisscale'} );
    $x[0] = $xlo + 0.7*$xrange;
    $y[0] = $ylo;
    pgtext( $x[0], $y[0], "dots mark local time" );

    # Draw bulls-eye (outline of circles only)
    pgsfs( 2 );

    # Draw concentric circles at 'yint' intervals in elevation
    # Elevation:
    my @eyes;
    if ( $args{'airmassgrid'} != 1 ) {
      for (my $eld=0; $eld < $yhi; $eld += $yint) {
         push @eyes, $eld;
      }
    } else {
      push @eyes, 100;
      foreach my $air ( 1, 1.1, 1.2, 1.3, 1.5, 2, 3 ) {
         push @eyes, $air;
       }
    }

    foreach my $eye (@eyes) {

      my $eld;
      if ( $args{'airmassgrid'} != 1 ) {
        $eld = $eye;
      } else {
        if ($eye > 10) {
          $eld = 0;
	} else {
          $eld = rad2deg(asin(1.0/$eye));
	}
      }
      # Outer circle solid in default frame color, other gridstyle
      if( $eld != 0 && $args{'gridstyle'} >= 0 ) {
        pgsci( $args{'gridcol'} );
        pgsls( $args{'gridstyle'} );
      }
      pgslw( $args{'heavylw'}*$lw )
           if( $eld == 0 or $eld == 30 ); # thicker 0 & 30 circle

      if( $eld == 0 or $args{'gridstyle'} >= 0 ) {
	pgcirc( 0,0,90-$eld );
      }

      pgslw( $lw );                            # Reset default styles
      pgsci( $args{'defcol'} );
      pgsls($args{'defstyle'});
      if( $eld != 0 ) {
        pgtext(-2.5,90-$eld,"$eye")
      }
    }

    # Draw Min elevation in dotted style if requested
    $min_el = $args{'annominel'};
    if( $min_el > 0 and $min_el < 90 ) {
      pgsls( 4 );                             # Dotted line
      pgcirc( 0,0,90-$min_el );               # Draw min EL line
      pgsls( $args{'defstyle'} );
    }

    # Draw radial lines at 'xint' intervals in azimuth
    my $expand = 1.05; # expand scale to create labels around graph
    my $lyoff = -1.0;  # need to move expanded circle down a bit

    pgsls( $args{'gridstyle'} );
    for (my $az = 0; $az < 360; $az += $xint) {
       my $xend = 90.0*sin($az*pi/180.0);
       my $yend = 90.0*cos($az*pi/180.0);
       if( $args{'gridstyle'} >= 0 ) {
         pgsci( $args{'gridcol'} );
         pgmove(0,0);
         pgdraw( $xend,$yend );
         pgsci( $args{'defcol'} );
       }
       if( $az == 0 ) {
         pgptxt( $expand*$xend,$expand*$yend+$lyoff, 0.0, 0.5, "N" );
       } elsif( $az == 90 ) {
         pgptxt( $expand*$xend,$expand*$yend+$lyoff, 0.0, 0.5, "E" );
       } elsif( $az == 180 ) {
         pgptxt( $expand*$xend,$expand*$yend+$lyoff, 0.0, 0.5, "S" );
       } elsif( $az == 270 ) {
         pgptxt( $expand*$xend,$expand*$yend+$lyoff, 0.0, 0.5, "W" );
       } else {
         pgptxt( $expand*$xend,$expand*$yend+$lyoff, 0.0, 0.5, "$az" );
       }
    }

    pgsls( $args{'defstyle'} );
    pgsch( 1.0 );

  # PLOT TIME-X BOX
  } else {                  #time-x

    my $ymag = abs( $yrange/90.0 );    # rel. Y-size wrt. timeel plot; 

    # Shrink the y-plot to create space for extra 'local time' axis
    my $yext = int( $yrange/10+0.5 );

    # Main window includes LST axis along top
    pgwindow( $args{'mag'}*$xlo, $args{'mag'}*$xhi,
              $args{'mag'}*$ylo, $args{'mag'}*($yhi+$yext) );

    # White box and labels, scale labels
    pgsci( $args{'defcol'} );

    # Extra large plot label, then conform to desired size
    pgsch( $args{'titlescale'} );
    $x[0] = $xlo;
    $y[0] = $ylo + 1.06*($yrange+$yext);
    my $title = "$telescope   $utdate   $args{title}";
    pgtext( $x[0], $y[0], "$title" );
    pgsch( $args{'axisscale'} );
    $x[0] = $xlo + 0.87 * $xrange;
    $y[0] = $ylo - 0.075 * $yrange;
    pgtext( $x[0], $y[0], "dots mark LST" );

    # Draw thin grid every 1.0 hour in x 10 deg in y
    # +  regular grid every 4.0 hours. Use the pgbox command
    # which also draws the outer lines, but do this before
    # drawing the main box (next).

    my $ytmp = $yint;
    # Draw horizontals 'by hand' below if airmassgrid wanted
    $ytmp = 100*$ytmp if( $args{'airmassgrid'} == 1 );

    if( $args{'gridstyle'} >= 0 ) {
      pgsci( $args{'gridcol'} );
      pgsls( $args{'gridstyle'} );
      pgbox( 'G',1.0,0,'G',0.5*$ytmp,0 );
      pgslw( $args{'heavylw'}*$lw );
      pgsls( $args{'defstyle'} );
      pgbox( 'G',$xint,0,'G',1.5*$ytmp,0 );
      pgslw( $lw );
      pgsci( $args{'defcol'} );
    }

    # Draw main box (draw OVER any underlying lines sofar)
    pgbox( 'BVST',$xint,0,'BNVST',$yint,0 );    # draw outer box, do
                                                # X-labeling by hand

    # Draw LST axis along top UT axis and AIRMASS axis on right
    pgbox( 'C',$xint,0,'C',$yint,0 );           # No tickmarks etc.

    # Draw UT axis last to ensure it ends on top!

    # Draw heavy vertical 'centre' line at "plot_center" location
    pgslw( $args{'heavylw'}*$lw );
    pgmove( $args{'plot_center'}+$ut0hr,$ylo );
    pgdraw( $args{'plot_center'}+$ut0hr,$yhi );
    pgslw( $lw );

    # Main outside labels
    pgsch( $args{'labelscale'} );
    pglabel( 'Local Time',$ylabel,'LST' );      # Local along bottom, LST
    pgsch( $args{'axisscale'} );                        # along top

    # Labels, tick marks UT and Local Time axes
    my $istart = $xint * int($utleft/$xint);    # Nearest integer inside
    $istart += $xint if( $istart == $xlo );
    for (my $iut = $istart; $iut < $xhi-0.1; $iut += $xint) {
      my $ltime = $iut - $ut0hr;
      $ltime += 24.0 if( $ltime <  0.0 );
      $ltime -= 24.0 if( $ltime > 24.0 );
      my $lt = int($ltime);
      pgsch( .4 );                                     # shorten the |'s
      pgptxt( $iut,$yhi-1.0*$ymag, 0.0, 0.0,'|' );
      pgsch( $args{'axisscale'} );
      pgptxt( $iut,$yhi+1.75*$ymag, 0.0, 0.5, "$iut" );
      pgptxt( $iut,$ylo-3.75*$ymag, 0.0, 0.5, "$lt" );
    }
    pgsch( $args{'labelscale'} );
    pgptxt(  $xlo+0.5*$xrange, $ylo+0.95*($yrange+$yext), 0.0, 0.5,
            'UT' );
    pgsch( $args{'axisscale'} );

    # LST ticks and annotation
    my $ilstart = $xint * int( $lstleft/$xint );   # Nearest integer inside
    $ilstart += $xint if( $ilstart <= $lstleft );
    for (my $ilst = $ilstart; $ilst < $lstright-0.1; $ilst += $xint) {
      my $uttime = $ut0hr + ($ilst-$st0hr)/1.0027379093;
      $uttime += 24.0 if( $uttime < $xlo );
      $uttime -= 24.0 if( $uttime > $xhi );
      pgsch( .4 );                                     # shorten the |'s
      pgptxt( $uttime,$yhi+$yext-1.0*$ymag, 0.0, 0.0,'|' );
      pgsch( $args{'axisscale'} );
      pgptxt( $uttime,$yhi+$yext+1.75*$ymag, 0.0, 0.5, "$ilst" );
    }
    pgsch( $args{'axisscale'} );

    # Airmass ticks along right vertical axis if timeel
    # plus dotted min el line if requested
    if( $args{'format'} =~ /timeel/i ) {
      $x[0] = $xhi + 0.025 * $xrange;
      $y[0] = $ylo + 0.5 * $yrange;
      pgsch( $args{'labelscale'} );
      pgptxt( $x[0]+0.35,$y[0],270.0,0.5,'AIRMASS' );
      pgsch( $args{'axisscale'} );
      $x[0] = $xhi - 0.01 * $xrange;
      $x[1] = $xhi;
      foreach my $i ( 1, 1.1, 1.2, 1.3, 1.5, 1.7, 2, 2.5, 3, 4, 5 ) {
        $y[0] = rad2deg(asin(1.0/$i));
        $y[1] = $y[0];
        #Draw airmassgrid if requested
        if( $args{'gridstyle'} >= 0 and $args{'airmassgrid'} == 1 ) {
          pgsci( $args{'gridcol'} );
          pgsls( $args{'gridstyle'} );
          pgmove( $xlo+0.002*($xhi-$xlo ),$y[0]);
          pgdraw( $xhi,$y[0] );
          pgsci( $args{'defcol'} );
          pgsls( $args{'defstyle'} );
	}
        # tick mark
        pgline( 2,\@x,\@y );
        pgptxt( ($x[1]+0.35),($y[1]-0.5*$ymag),0.0,0.5,"$i" );
      }
      $min_el = $args{'annominel'};
      if( $min_el > 0 and $min_el < 90 ) {
        pgsls( 4 );                                    # Dotted line
        pgmove( $xlo,$min_el );                        # Draw min EL line
        pgdraw( $xhi,$min_el );
      }
    }

    pgsls( $args{'defstyle'} );
    pgsch( 1.0 );

    # Draw UT time axis
    pgmove( $xlo,$yhi );                        # Draw UT time axis line
    pgdraw( $xhi,$yhi );                        # under LST axis at $yhi

  }

  # ------------
  # PLOT SOURCES
  # ------------
  # Now plot objects


  print "SOURCEPLOT DEBUG: Plot objects.\n" if($debug);
  # Scaling and weight for source names
  pgsch( $args{'objscale'} );
  pgslw( $args{'objlw'}*$lw );

  my $iobj = 0;
  foreach my $c (@{$coords}) {

    pgsci( ($iobj )%10+2);              # rotate colors

    # Dots with annotation
    my $dotnr = 0;
    my $dotlint = 3;                    # interval for annotation
    my $dottime;
    my $prev_dottime = 999;
    my $dottxt;

    my $appra = 12.0/pi*$c->ra_app();

    # Make sure correct telescope object in Coord!
    $c->telescope( new Astro::Telescope( $telescope ));

    # Calculate Time, Az, El, PA, LST arrays for given object
    my @points = $c->calculate( start => $args{'start'},
                                  end => $args{'end'},
                                  inc => $args{'increment'},
                                units => 'deg'
                              );

    # Store position of maximum in curve for labeling
    my ($xmax, $ymax) = (999.0, -999.0);

    my $nr = 0;
    my $prev_utt = -999;
    $utnow -= 24.0 if( $utnow > $xhi );
    $utnow += 24.0 if( $utnow < $xlo );

    foreach my $point (@points) {

      my $utt = $point->{'time'}->hour +
  	        $point->{'time'}->minute/60.0 +
	        $point->{'time'}->second/3600.0;
      $utt -= 24.0 if( $utt > $xhi );
      $utt += 24.0 if( $utt < $xlo );

      my $lst = 12.0/pi*$point->{'lst'};
      my $local_time = $lst-$st0hr;

      # Plot current segment if jumping in time from one to other side
      # or EL dropped below 0 previous point
      if(  $nr > 0 && 
           (abs($utt-$prev_utt) > 12) or ($point->{'elevation'} < 0) ) {
	pgline( $nr,\@xx,\@yy );
	pgpt( $dotnr,\@dotx,\@doty,17 );
	for ($idot = 0; $idot < $dotnr; $idot++) {
	  pgtext( 1.05*($dotx[$idot]-2.5), $doty[$idot]-4, $dotlabel[$idot] );
	}
	$nr = 0;
	$dotnr = 0;
	$prev_dottime = 999;
      }
      $prev_utt = $utt;

      # AZ-EL format (Annotate dots with local time)
      if( $args{'format'} =~ /azel/i ) {

	# Map AZ onto regular 0-360 circle CCW starting on X-axis
	# just to keep sin and cos conventional for polar plot.
	my $angle =  90.0-$point->{'azimuth'};
	$angle = 360.0 + $angle if( $angle < 0.0 );

	# Radius polar plot is given by the zenith angle.
	my $zenith = 90.0-$point->{'elevation'};

	$xx[$nr] = $zenith*cos($angle*pi/180.0);
	$yy[$nr] = $zenith*sin($angle*pi/180.0);

	$dottime = $local_time;

      # Time-xx format
      } else {

	$xx[$nr] = $utt;

	if( $args{'format'} =~ /timepa/i ) {
	  $yy[$nr] = $point->{'parang'};
	} elsif( $args{'format'} =~ /timeaz/i ) {
	  $yy[$nr] = $point->{'azimuth'};
	} elsif( $args{'format'} =~ /timena/i ) {
	  $yy[$nr] = $point->{'parang'}-$point->{'elevation'};
          $yy[$nr] += 360 if( $yy[$nr] < $ylo );
          $yy[$nr] -= 360 if( $yy[$nr] > $yhi );
	} else {               #timeel
	  $yy[$nr] = $point->{'elevation'};
	}

	$dottime = $lst;

      }

      # No need for rest if below 0: wrap around to plot segment
      next if( $point->{'elevation'} < 0 );

      # Mark current position source
      if(  $args{'objdot'} &&
           abs($utt-$utnow) < 0.5*$args{'increment'}/3600.0 ) {
         pgslw( $args{'heavylw'}*$lw*6 );
         pgpt( 1,$xx[$nr],$yy[$nr],17 );
         pgslw( $lw );
      }

      # Check if a new dot and annotation needed
      if( abs($dottime-int($dottime )) < $args{'increment'}/3600.0 ) {
#        && abs(int($dottime)-int($prev_dottime)) > 0 ) {
	$prev_dottime = $dottime;
	$dottime -= 24.0 if( $dottime > 24.0 );
	$dottime += 24.0 if( $dottime <  0.0 );
	$dotx[$dotnr] = $xx[$nr];
	$doty[$dotnr] = $yy[$nr];
	$dotlabel[$dotnr] = '';

        # Annotate dot AZEL: others too messy
	$dotlabel[$dotnr] = int($dottime+0.5)
	   if( $args{'format'} =~ /azel/i && 
	       $args{annotrack} &&
	       $dottime%$dotlint == 0 );

	# Object label near max curve
	($xmax, $ymax) = ($xx[$nr], $yy[$nr]) if( $yy[$nr] > $ymax );

	# AZ-EL Object label at left-most (smallest x) dot position
	($xmax, $ymax) = ($xx[$nr], $yy[$nr]) 
               if( $args{'format'} =~ /azel/i && $xx[$nr] < $xmax );

	$dotnr++;
      }

      $nr++;

    }

    # Plot any remaining segment
    if( $nr > 0 ) {
      pgline( $nr,\@xx,\@yy );
      $nr = 0;
      pgpt( $dotnr,\@dotx,\@doty,17 );
      for ($idot = 0; $idot < $dotnr; $idot++) {
	pgtext( 1.05*($dotx[$idot]-2.5),$doty[$idot]-4,$dotlabel[$idot] );
      }
      $dotnr = 0;
      $prev_dottime = 999;
    }

    # label the objects: as list on left, else label near max curve.
    my $object = $c->name;
    $object = '??' unless defined $object;
    if( $args{'objlabel'} eq 'list' ) {
      $x[0] = $xlo + 0.001 * $xrange;
      $x[1] = $xlo + 0.016 * $xrange;
      $y[0] = $yhi - (0.01 + 0.03*($iobj-1)) * $yrange;
      $y[1] = $y[0];
      pgline( 2,\@x,\@y );
      $x[2] = $xlo + 0.024 * $xrange;
      $y[2] = $y[1] - 1.0;
      pgtext($x[2],$y[2],"$object");
    } elsif( $args{'objlabel'} eq 'curve' ) {
      $x[1] = $xmax;
      $y[1] = $ymax + 0.015 * $yrange;
      pgtext( $x[1],$y[1],"$object" );
    }

    $iobj++;
  }

  print "SOURCEPLOT DEBUG: Reset plot options and close plot.\n" if($debug);
  # Reset pgplot (just in case)
  pgsch( 1.0 );
  pgsci( 1 );
  pgsls( 1 );
  pgslw( 1 );

  pgend;

  printf "SOURCEPLOT DEBUG: return '%s' plot name.\n", $args{'output'}
          if($debug);
  return $args{'output'} ;
}

=back

=head1 NOTES

Currently only supports PGPLOT devices.

=head1 TODO

Support Tk widgets.

=head1 SEE ALSO

L<Astro::Coords>

=head1 AUTHOR

Remo P. J. Tilanus E<lt>r.tilanus@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2003 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

