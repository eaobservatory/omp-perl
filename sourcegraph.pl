#!/local/bin/perl -X
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
#Non-interactive (sub)routine to create a hardcopy plot of EL-TIME for
#astronomical sources, including planets, as seen from the JCMT.  The
#main purpose of this routine is to generate on-demand plots for
#display on the Web.  (a) multi-objects (up to 50), (very) free-format
#RA, Dec (b) plot EL against UT, LST, and local time (HST) (c) also
#solar system objects i.e. the planets (d) precession (e) read from
#JCMT-style catalog or (JPL) ephemerides Remo Tilanus ** 1-Sep-2000 **
#Joint Astronomy Centre, Hilo, Hawaii Modified from interactive
#FORTRAN program.
#----------------------------------------------------------------------

use strict;
use Getopt::Std;
use Math::Trig;
use Astro::SLA;

$ENV{PGPLOT_DIR} = "/star/bin"
   unless exists $ENV{PGPLOT_DIR};
$ENV{PGPLOT_FONT} = "/star/etc/grfont.dat"
   unless exists $ENV{PGPLOT_FONT};

use PGPLOT;

# Defaults

my $hdevice = "sourcegraph.gif/gif";              # GKS plot device
my $maxobj  = 50;                                 # max. nr. objects
my $nopnt   = 288;                                # nr. point on curve

# Observatory for which to plot.
# Center the plot on local midnight: ut0hr is UT time at local midnight
# which, of course, is the timezone

my $tel=     'JCMT';
my $ut0hr =  10.0;                                 # Timezone

# Find the longitude of and latitude of the telescope and convert 
# longitude to west negative.
# Note: long and lat are in radians!
my ($long, $lat, $height, $tname);
slaObs(-1, $tel, $tname, $long, $lat, $height);
$long *= -1.0;

# Centre plot on Midnight or Change of shift (JCMT: 1:30 HST)

my $plot_center = 0.0;
$plot_center = 1.5 if ($tel eq 'JCMT');

my ($i, $j) = (0, 0);

my (@lst, @el, @az, @pa);
#----------------------------------------------------------------------
# Get command-line parameters.

my $cmd_line = join(' ', @ARGV);
unless(getopts('d:c:p:s:h')) {
    &usage();
    die "Incorrect option in '$0 $cmd_line'\n";
}

(defined $Getopt::Std::opt_h) && do {
  print "\n-------------------------------------------------------------\n";
  print " This routine plots the  EL of sources as a function of Time.\n";
  print " At most $maxobj sources can be plotted or printed.\n\n";
  print " Sourceplot [-h] [-d utdate] [-c catalog_file] [-p proj_id]\n";
  print "            [-s source]\n";
  print "\t\t-h\tThis help\n";
  print "\t\t-d\tUtdate to plot for (YYYYMMDD)\n";
  print "\t\t-p\tProject to plot (ALL)\n";
  print "\t\t-p\tSource to plot(ALL)\n";
  print "\t\t-c\tCatalog file: path and name of catalog file to use\n\n";
  print "-------------------------------------------------------------\n\n";
  exit;
};

# UT date:
my $pld = "";
$pld = $Getopt::Std::opt_d if (defined $Getopt::Std::opt_d);
if ($pld != "" && $pld !~ /^\d{8}$/) {
  print "-------------------------------------------------------------\n";
  print " Error:       UTDATE must have format YYYYMMDD\n";
  print "-------------------------------------------------------------\n";
  exit;
}

# Make trusted
my $pldate;
$pld =~ /^(\d{8})$/ && ($pldate = $1) || ($pldate = "");

# Catalog:
my $cat = "";
$cat = $Getopt::Std::opt_c if (defined $Getopt::Std::opt_c);

# Make trusted
my $catalog;
$cat =~ /^([\w\/\$\.\_]+)$/ && ($catalog = $1) || ($catalog = "");

# Project:
my $prj = "";
$prj = $Getopt::Std::opt_p if (defined $Getopt::Std::opt_p);

# Make trusted
my $projid;
$prj =~ /^([\w\/\$\.\_]+)$/ && ($projid = $1) || ($projid = "");

# Source:
my $src = "";
$src = $Getopt::Std::opt_s if (defined $Getopt::Std::opt_s);

# Make trusted
my $source;
$src =~ /^([\w\+\-\.\_]+)$/ && ($source = $1) || ($source = "");

#----------------------------------------------------------------------

# Date for which to plot. MJD (Modified Julian Date), ST0HR
# Apparent Local Sidereal Time, and DEPOCH (epoch) are for 0 HR LOCAL TIME.

#print "Date: $pldate\t\tCatalog: $catalog\n";
my ($utdate, $uttime, $st0hr, $mjd, $depoch) = get_datim($pldate);

# Ctime, icuthr, clst are current times
# Ut hour

my $icuthr = int($uttime);

my $ctime = $uttime - $ut0hr;
$ctime += 24.0 if ($ctime <   0);
$ctime -= 24.0 if ($ctime >= 24);

my $clst  = $st0hr + 1.0027390930 * $ctime;
$clst += 24.0 if ($clst <   0.0);
$clst -= 24.0 if ($clst >= 24.0);

# Split to hr, min, sec fields for printing
my @time = ();
my $sign;
slaDd2tf (0, ($ctime/24.0), $sign, @time) ;
my @lsthms = ();
slaDd2tf (0, ($clst/24.0), $sign, @lsthms);

my $time_msg = sprintf
 "Local time: %2.2d:%2.2d:%2.2d          UT: %2.2d:%2.2d:%2.2d          LST: %2.2d:%2.2d:%2.2d\n",
    $time[0],$time[1],$time[2],$icuthr,$time[1],$time[2], 
    $lsthms[0], $lsthms[1], $lsthms[2];

# Setup LST array:

my $offset = 0.0;
$offset = -24.0 if (($st0hr+$plot_center) > 12.0);
my $rpnt = 24.0 / (1.0027390930 * ($nopnt-1));
for ( $i = 0; $i < $nopnt; $i++ ) {
   $lst[$i] = ($i*$rpnt-12.00)*1.00273790930 + $st0hr + $plot_center + $offset;
}

# ======================================================================
#
#  plot box:  For the X-axis (UT) the plot runs from ut0hr-12 to ut0hr+12. 
#  However, the time coordinate has switched to LST (not UT!) upon return
#  from the routine. Any LST interval is 1.002 737 9093 times the UT interval
#  (B7, Astronomical Almanac). 
#  Be careful not do do more than 24 hrs in LST.

# Pgplot drawing routines: open hardcopy device

pgbegin(0,$hdevice,1,1);

my @box = plot_box($tel, $ut0hr, $utdate, $st0hr, $plot_center);

#----------------------------------------------------------------------
# Get object names and positions

my @name = ();
my @cepoch = ();
my @cra = ();
my @cdec = ();
my @ra = ();
my @dec = ();
my ($equinox, $istat);

if ($source ne "") {
  $name[0] = "$source";
} else {
  #Pre-fill search array for maxobj
  for ($j = 1; $j < $maxobj; $j++) {
    $name[$j-1] = "\#${j}";
  }
}

$j = 0;
while ($j < $maxobj) {                   # Get maxobj sources or less

  # get coordinates for source

  ($name[$j], $cra[$j], $cdec[$j], $equinox, $cepoch[$j], 
   $ra[$j], $dec[$j], $istat) =
     get_pos($catalog, $projid, $name[$j], $depoch, $mjd, $long, $lat);

   #(for now only operate in list full catalog mode, thus temrinate once
   # the catalog is exhausted (returns -1)
  if ($istat == -1) {
    last;
    print " ***WARNING*** Source not in catalog or Ephemerides.\n";
    $j++;
  } elsif ($istat == -2) {
    print " ***ERROR*** reading Ephemerides.\n";
    $j++;
    next;
  } elsif ($istat == -3) {
    print " ***ERROR*** reading catalog.\n";
    $j++;
    next;
  } elsif ($istat == -4) {
    print " ***ERROR*** parsing coordinate line.\n";
    $j++;
    next;
  } elsif ($istat == -5) {
    $j++;
    print " ***ERROR*** Catalog RA, or DEC out of limits.\n";
  } elsif ($istat == -6) {
    $j++;
    print " ***ERROR*** RA, or DEC of date out of limits.\n";
  } elsif ($istat == -10) {
    print " EARTH: skipped.\n";
    $j++;
    next;
  }

  # Print catalog or ephemeris coordinates

  my ($sign);
  my @idum = ();
  my @jdum = ();
  slaDr2tf( 2, $cra[$j], $sign, @idum );
  $idum[0] = $idum[0] + 24 if ($sign eq '-') ;
  slaDr2af( 3, $cdec[$j], $sign, @jdum );
  print 
    "-----------------------------------------------------------------\n";
  printf 
    "%2d %15s  %2.2d:%2.2d:%2.2d.%2.2d  %s%2.2d:%2.2d:%2.2d.%3.3d   %s%8.3f\n",
      ($j+1), $name[$j],$idum[0],$idum[1],$idum[2],$idum[3], $sign, 
      $jdum[0],$jdum[1],$jdum[2],$jdum[3], $equinox, $cepoch[$j];
  if ($istat == -5 || $istat == -6) {
    next;
  }

  # Print precessed coordinates or (if using ephemeris) rate of movement
  
  slaDr2tf( 2, $ra[$j], $sign, @idum );
  $idum[0] = $idum[0] + 24 if ($sign eq '-');
  slaDr2af( 3, $dec[$j], $sign, @jdum );
	 
  printf 
     "                    %2.2d:%2.2d:%2.2d.%2.2d  %s%2.2d:%2.2d:%2.2d.%3.3d   %s%8.3f\n",
      $idum[0],$idum[1],$idum[2],$idum[3], $sign, 
      $jdum[0],$jdum[1],$jdum[2],$jdum[3], 'J', $depoch;

  # calculate AZ, EL, Parallactic Angle for source
  
  for ($i = 0; $i < $nopnt; $i++) {
#    my $rra  = $ra[$j]  + ($lst[$i] - $st0hr) * $dra[$j];
#    my $rdec = $dec[$j] + ($lst[$i] - $st0hr) * $ddec[$j];
    my $rra  = $ra[$j];
    my $rdec = $dec[$j];
    my $ha = ($lst[$i] * pi/12.0) - $rra;
    $ha = $ha + 2.0*pi if ($ha < 0.0);
    $ha = $ha - 2.0*pi if ($ha > (2.0*pi));
	     
    my ($azz, $ell);
    slaDe2h($ha,$rdec,$lat,$azz,$ell);
    $az[$j][$i] = $azz;
    $el[$j][$i] = $ell;
    $pa[$j][$i] = slaPa($ha,$rdec,$lat);

    #  convert back to degrees.........

    $el[$j][$i] = rad2deg($el[$j][$i]);
    $az[$j][$i] = rad2deg($az[$j][$i]);
    $az[$j][$i] = $az[$j][$i] + 360.0 if ($az[$j][$i] < 0.0);
    $pa[$j][$i] = rad2deg($pa[$j][$i]);
  }

  $j++;
}

plot_obj(0, $j, \@name, \@lst, \@el, \@az, \@pa, \@box);

print "-----------------------------------------------------------------\n";

print " ***Sorry $maxobj objects maximum*** \n" if ($j == $maxobj);

pgend;

#   ROUTINE NAME : GET_DATIM
# **********************************************************************
#
#   PURPOSE : get date and return the Modified Julian Date and the
#   apparent LST, both for LOCAL midnight
#
# **********************************************************************

sub get_datim {

   my ($pldate) = @_;
   my $istat;

   my ($utdate, $uttime);
   my ($us, $um, $uh, $md, $mo, $yr, $wd, $yd, $isdst);
   if ($pldate =~ /^\d{8}/) {
     $yr = substr($pldate,0,4);
     $mo = substr($pldate,4,2);
     $md = substr($pldate,6,2);
     $utdate = $pldate;
     $uttime = 0.0;
   } else {
     # Current ut time
     ($us, $um, $uh, $md, $mo, $yr, $wd, $yd, $isdst) = gmtime(time);
     $yr += 1900;
     $mo += 1;
     $utdate= 10000*$yr+100*$mo+($md);
     $uttime= $uh + $um/60.0 + $us/3600.0;
   }

   # Calculate MJD and Apparent ST at the UT which corresponds
   # to local midnight.
   # st0hr is the Local Apparent Sidereal Time at Local Midnight!

#-------
   my ($st0hr, $mjd) = my_ut2lst_tel($yr,$mo,$md,10.0,0.0,0.0,'JCMT');
#-------

   # Epoch at midnight local time
   my $mjd0;
   slaCldj ($yr, 1, 1, $mjd0, $istat);
   if ($istat != 0) {
     print "***ERROR*** (slaCldj) converting year to MJD\n";
     exit(-1);
   }

   my $depoch = $yr + (($mjd-$mjd0)/365.25);

   return ($utdate, $uttime, $st0hr, $mjd, $depoch);

}


#   ROUTINE NAME : PLOT_BOX
# **********************************************************************
#
#   PURPOSE : Plot box + annotations. This routine switches the X-axis
#             variable in the plot from UT to LST upon exit.
#       
# **********************************************************************

sub plot_box {


  my ($tel, $ut0hr, $utdate, $st0hr, $plot_center) = @_;

  # Calculate Start and End UT axis centered around above point

  my $utstart = -12.0 + $ut0hr + $plot_center;
  $utstart = $utstart+24.0 if ($utstart < -24.0);
  $utstart = $utstart-24.0 if ($utstart >  12.0);
  my $utstop  = $utstart+24.0;

  # Set up plot limits for X and Y-axis

  my ($xlo, $xhi, $xint, $xlabel) = ($utstart, $utstop,   4.0, 'UT');
  my ($ylo, $yhi, $yint, $ylabel) = ($    0.0,   89.99,  20.0, 'EL');

  # Allow for extra 'local time' axis

  my $yext = 0.0;
  $yext = int(($yhi-$ylo)/10.+0.5);

  # Set up plot 

  pgpage;
  pgvstand;
  pgwindow($xlo, $xhi, $ylo, $yhi+$yext);

  # White box and labels

  pgsci(1);

  # Airmass ticks

  my (@x, @y);
  $x[0] = $xhi + 0.025 * ($xhi - $xlo);
  $y[0] = $yhi / 2.0;
  pgptxt($x[0],$y[0],270.0,0.5,'AIRMASS');
  $x[0] = $xhi - 0.0125 * ($xhi - $xlo);
  $x[1] = $xhi;
  for ($i = 1; $i < 6; $i++) {
    $y[0] = rad2deg(asin(1.0/$i));
    $y[1] = $y[0];
    pgline(2,\@x,\@y);
    pgptxt(($x[1]+0.2),($y[1]-0.5),0.0,0.5,"$i")
  }

  # Draw vertical 'centre' line

  my $lw;
  pgqlw($lw);
  pgslw((3*$lw));
  pgsci(14);
  pgmove(($ut0hr+$plot_center),$ylo); 
  pgdraw(($ut0hr+$plot_center),$yhi);
  pgslw($lw);
     
  # Draw fancy dotted grid every 1.0 hour in x 10 deg in y
  # + regular grid every 4.0 hours

  pgsci(14);
  pgsls(4);
  pgbox('G',1.0,0,'G',10.0,0);
  pgsls(1);
  pgbox('G',4.0,0,'G',30.0,0);
  pgsci(1);

  # Draw box
    
  pgbox('BNVST',$xint,0,'BNVST',$yint,0);     # draw half of box:;
                                              # UT TIME
  $x[0] = $xlo;
  $y[0] = 1.06 * ($yhi + $yext - $ylo);
  pgtext($x[0], $y[0], "$tel   $utdate");
  pglabel($xlabel,$ylabel,'LST');

  # Draw Local time axis

  pgmove($xlo,$yhi);                          # Draw local time axis line
  pgdraw($xhi,$yhi);
     
  pgsch(1.2);
  my $istart = $xint * int($utstart/$xint);
  $istart += $xint if ($istart == $xlo);
  pgtext(($xlo+0.45*($xhi-$xlo)),(0.95*($yhi+$yext)),'Local Time');
  for ($i = $istart; $i < $xhi-0.1; $i += 4) {       # Draw the tick marks
    my $ri = $i;
    my $ltime = $i - $ut0hr;
    $ltime = $ltime + 24.0 if ($ltime <  0.0);
    $ltime = $ltime - 24.0 if ($ltime > 24.0);
    pgsch(.4);                                       # shorten the |'s
    pgtext(($ri-0.05),(0.985*$yhi),'|');
    pgsch(1.);
    my $lt = int($ltime);
    $lt = " $lt" if ($lt < 10);
    pgtext(($ri-0.45),(1.012*$yhi),"$lt");
  }

  # Draw LST axis and SWITCH TO LST COORDINATES FROM NOW ON.
  # See page B7 of the Almanac for the factor 1.002 737 9093

  my $offset = 0.0;
  $offset = -24.0 if (($st0hr+$plot_center) > 12.0);
  $xlo = $st0hr + $plot_center - 12.0 * 1.0027379093 + $offset;
  $xhi = $st0hr + $plot_center + 12.0 * 1.0027379093 + $offset;
  pgwindow($xlo,$xhi,0.0,$yhi+$yext);
  pgbox('CMVST',$xint,0,'C',$yint,0);

  return($xlo,$xhi,$ylo,$yhi);
}


#   ROUTINE NAME : PLOT_OBJ
# **********************************************************************
#
#   PURPOSE : plot object
#       
# **********************************************************************

sub plot_obj {


  my ($i, $j, $nopnt);
  my (@x, @y, @xx, @yy);

  my ($iobj, $nobj, $name, $lst, $el, $az, $pa, $box) = @_;

  $nopnt = $#$lst;
  my ($xlo, $xhi, $ylo, $yhi) = ($$box[0], $$box[1], $$box[2], $$box[3]);

  #  write labels with following scaling
  pgsch(0.75);
		
  for ($j = $iobj; $j < ($iobj+$nobj); $j++) {

    for ($i = 0; $i < $nopnt; $i++) {
      $xx[$i] = $$lst[$i];
    }
   
    my $ymax = -999.0;
    my $imax = 0;
    for ($i = 0; $i < $nopnt; $i++) {
      if ($$el[$j][$i] > $ymax) {
	$imax = $i;
	$ymax = $$el[$j][$i];
      }
      $yy[$i] = $$el[$j][$i];
    }

    #  plot the objects

    pgsci(($j)%10+2);
    pgsls(($j)%5+1);
    pgline($nopnt,\@xx,\@yy);

    # label the objects: ymax = -999 label as list on right,
    #                    else label near max curve.

    my $object = $$name[$j];
    if ($ymax < -998.99) {
      $x[1] = $xhi - 0.15 * ($xhi-$xlo);
      $x[2] = $xhi - 0.10 * ($xhi-$xlo);
      $y[1] = $yhi - (0.04 + 0.03*($j-1)) * ($yhi-$ylo);
      $y[2] = $y[1];
      pgline(2,\@x,\@y);
      pgsls(1);
      $x[2] = $xhi - 0.09 * ($xhi-$xlo);
      pgtext($x[2],$y[1],"$object");
    } else {
      pgsls(1);
      $x[1] = $xx[$imax];
      $y[1] = $yy[$imax] + 0.01 * ($yhi-$ylo);
      pgtext($x[1],$y[1],"$object");
    }

  }

  pgsch(1.0);
  pgsci(1);
  pgsls(1);

  return(0);
}


sub my_ut2lst_tel {

  my ($yy,$mn,$dd,$hh,$mm,$ss,$tel) = @_;
 
  # Upper case the telescope
  $tel = uc($tel);

  my ($long, $lat, $height, $name);
  # Find the longitude of this telescope
  slaObs(-1, $tel, $name, $long, $lat, $height);

  # Convert longitude to west negative
  $long *= -1.0;

  my ($rad, $j, $fd, $mjd, $slastatus, $gmst, $eqeqx, $lst);

  # Calculate fraction of day
  slaDtf2r($hh, $mm, $ss, $rad, $j);
  $fd = $rad / D2PI;

  # Calculate modified julian date of UT day
  slaCldj($yy, $mn, $dd, $mjd, $slastatus);
    
  if ($slastatus != 0) {
    die "Error calculating modified Julian date with args: $yy $mn $dd\n";
  }

  # Calculate sidereal time of greenwich
  $gmst = slaGmsta($mjd, $fd);
  
  # Find MJD of current time (not just day)
  $mjd += $fd;
 
  # Equation of the equinoxes
  $eqeqx = slaEqeqx($mjd);

  # Local sidereal time = GMST + EQEQX + Longitude in radians
  $lst = $gmst + $eqeqx + $long;
  $lst += D2PI if $lst < 0.0;

  # Convert back to hours
  $lst *= DR2H;

  return ($lst, $mjd);

}



#   ROUTINE NAME : GET_POS
# **********************************************************************
#
#   PURPOSE : finds the source and coordinates from catalog and returns 
#             the coordinates precessed for epoch specified. It also 
#             returns the unprecessed or catalogued coordinates. In case 
#             the positions are from the Ephemerides there are no 
#             unprecessed (catalogued) coordinates and the rate of
#             movement (rad/hr) is returned instead.
#             Also, in that case, the precessed coordinates are the
#             (linear) average of the positions at MJD +/- 12 hrs.
#
#
#   RETURN:
#              status =  0:  normal return
#                       -1:  source not found in catalog
#                       -3:  error occured in SEARCH_CATALOG routine
#                       -4:  error parsing line with coordinates
#                       -5:  unprecessed coordinates out of limits
#                       -6:  precessed   coordinates out of limits
#                      -10:  EARTH: skipped
#
# **********************************************************************

sub get_pos {

   my %plannr = ('SUN',     0, 'MERCURY', 1, 'VENUS',  2, 'MOON',   3,
                 'MARS',    4, 'JUPITER', 5, 'SATURN', 6, 'URANUS', 7,
                 'NEPTUNE', 8, 'PLUTO',   9);

   my ($catalog, $projid, $name, $depoch, $mjd, $long, $lat) = @_;

   $catalog = "_graphcat.dat" if ($catalog eq "");
   $name = uc($name);

   my $coords = "";
   my $istat = 0;
   my $status = 0;

   my ($cra, $cdec, $ra, $dec, $epoch, $cepoch);
   my $equinox = "";

   if ($name eq 'EARTH') {
     $status = -10;
     return ($name, $cra, $cdec, $equinox, $cepoch, $ra, $dec, $status);
   }

   # If planet get the position from the Ephemerides and return
   if (defined $plannr{"$name"}) {
     my $pnum =  $plannr{"$name"};
     my $mjd1 = $mjd - 0.5;
     my $mjd2 = $mjd + 0.5;
     my ($ra1, $ra2, $dec1, $dec2, $dia1, $dia2);
     slaRdplan( $mjd1, $pnum, $long, $lat, $ra1, $dec1, $dia1);
     slaRdplan( $mjd2, $pnum, $long, $lat, $ra2, $dec2, $dia2);
     $ra   = 0.5*($ra2+$ra1);
     $dec  = 0.5*($dec2+$dec1);
     $cra  = ($ra2-$ra1)/24.0;
     $cdec = ($dec2-$dec1)/24.0;
     $equinox = 'D';
     $cepoch = $depoch;
     return ($name, $cra, $cdec, $equinox, $cepoch, $ra, $dec, $status);
   }

   # Otherwise search the specified catalog
   ($name, $coords, $istat) = search_catalog ($name, $catalog, $projid);
   if ($istat < 0) {
     $status = -3;
     return ($name, $cra, $cdec, $equinox, $cepoch, $ra, $dec, $status);
   } elsif ($istat == 0) {
     $status = -1;
     return ($name, $cra, $cdec, $equinox, $cepoch, $ra, $dec, $status);
   }

   # Parse line for coordinates and other info  
   ($cra, $cdec, $equinox, $epoch, $istat) = parse_coords($coords);
   if ($status < 0) {
     $status = -4;
     return ($name, $cra, $cdec, $equinox, $cepoch, $ra, $dec, $status);
   }

   if ( $equinox ne 'D' ) {
     $cepoch = $epoch;
   } else {
     $cepoch = $depoch;
   }

   # Make sure coordinates are valid

   if ( $cra  <   0.0      || $cra  > (2.0*pi) ||
        $cdec < (-0.5*pi) || $cdec  > (0.5*pi) ||
            $cepoch < 1900.0 || $cepoch > 2099.99 ) {
     $status = -5;
     return ($name, $cra, $cdec, $equinox, $cepoch, $ra, $dec, $status);
   }

   # Precession (returns invalid ra, dec if routine fails)

   my $rep;
   my ($ra, $dec) = ($cra, $cdec);
#   print "'$cra' '$cdec' '$cepoch' '$equinox'\n";
   if ($cepoch != $depoch && $equinox =~ /^(B|J)/i) {

     my $epoch = $cepoch;

     # Precess B1950 (FK4) to J2000 (FK5)
     if ($equinox eq 'B') {
       slaFk45z($cra, $cdec, $cepoch, $ra, $dec);
       $epoch = 2000.0;
     }
     my @pm = ();
     my @v1 = ();
     my @v2 = ();

     # Now Precess to date
     slaPrec ( $epoch, $depoch, @pm );

     # Convert RA,Dec to x,y,z */
     slaDcs2c ( $ra, $dec, @v1 );

     # Precess
     slaDmxv ( @pm, @v1, @v2 );

     # Back to RA, Dec
     slaDcc2s ( @v2, $ra, $dec );
     $ra = slaDranrm ( $ra );
   }
#   print "'$ra' '$dec' '$depoch' 'J'\n";

   if ( $ra  <  0.0       || $ra > (2.0*pi)  ||
        $dec < (-0.5*pi) || $dec > (0.5*pi) ) {
      $status = -6; 
      return ($name, $cra, $cdec, $equinox, $cepoch, $ra, $dec, $status);
   }

   return ($name, $cra, $cdec, $equinox, $cepoch, $ra, $dec, $status);

}



# **********************************************************************
# ($name, $coords, $status) = search_catalog ($name, $catalog, $projid)
#
#   Purpose : Find source in catalog and, if found, return remainder
#             of line with coordinates etc, converted to upper case
#             and any 'blank'-type chars converted to real blanks.
#             If the name has the form '#*' it will pick the source 
#             at line # of the catalog (skipping comments).
#
#   Parameters: 
#             $name:       name of object to be found or #n with n
#                          indicating the line nr of the object
#                          in the catalog (skipping comment lines).
#
#             $catalog:    name of the catalog file (including path).
#
#             $projid:     look only for catalog entries  specified 
#                          project. Strictly speaking any entry
#                          containing the 'projid' string will be searched.
#
#   Returned:
#             $name        name as found in catalog
#
#             $coords      rest of line following the object name in the
#                          catalog
#
#             $status > 0: line at which source found in catalog
#                       0: source not found
#                      -2: could not open/read catalog file
#
# **********************************************************************

sub search_catalog {

   my ($name, $catalog, $projid) = @_;
   chomp($name);
   chomp($catalog);

   # If not real name but line number (name like '#n') get 'n'.

   my $iname = 0;
   if ($name =~ /^\#/) {
     $iname = substr($name,1);
     $name = "";
   }

   my $coords = "";
   my $status = 0;                              # Initialize at 'not found'

   my @entries = ();

   $status = read_catalog($catalog, \@entries);
   return($name, $coords, -2) if ($status < 0);

   my $entry = "";
   my $iline = 0;
   foreach $entry (@entries) {

     next if ($entry =~ /^\#|\%|\!|\*/);             # Skip comment lines

     next if ($projid ne "" and $entry !~ /${projid}/i); # Skip other projects

     $iline++;
     $entry = uc($entry);

     my ($object,$coordfield) = split(/\s+/,$entry,2);

     if ($iline == $iname || $name =~ /^${object}$/i) {
       $name = $object;
       $iname = $iline; 
       $coords = $coordfield;
       $status = $iline;
       last;
     } else {
       next;
     }

   }
   return ($name, $coords, $status);
}


# **********************************************************************
#  ($ra, $dec, $equinox, $epoch, $status) = parse_coords(coord_string)
#
#   Purpose : Parse a relatively free format coordinate line
#       
#   Decode line which is expected to be something like:
#        RA-field(s) [+,-] Dec-field(s) [Epoch]  e.g.
#
#        hr min sec [+,-] deg amin asec [RB]   or
#        hr:min     [+,-] deg:amin:asec J1986 or
#        ra.rrrrr [-]dec.ddddd
#
#   Hence, format of the R.A. and Dec fields is relatively free.
#   The logic is that any [+,-] indicate the start of Dec fields and 
#   any [RB] or [B,J]#### or any number [1900,2099] the start of the 
#   epoch field. Hence there are a maximum 7 numerical items expected on 
#   the line, with nitem (1-7) in the sequence as above.
#   Parsing is helped by explicitly putting a '+' or '-' sign with Dec.
#   In addition to the above it can also use the ":" character to
#   delineate coordinate fields.
#
#   Returned:
#
#      $ra, $dec:    Right Ascention and Declination in radians.
#
#      $equinox, $epoch: 'B' Besselian, 'J' Julian, 'D' of date  and
#                    the epoch. The epoch will be '0' for 'D' and
#                    needs to be determined by the calling routine.
#              
#      $status = -1: Can not decide on split between RA and Dec i.e.
#                    odd number numerical fields preceeding any equinox/
#                    epoch field without a sign indicator.
#
# **********************************************************************

sub parse_coords {

  my ($coords) = @_;
  my @words = split(/\s+/,$coords);

  my $status = -1;              # Initialize at failure to parse.

  my ($equinox, $epoch) = ("", 0);
  my ($sign, $isign) = (1, 0);
  my ($inum, $num) = (0, 0);   
  my ($ra, $dec) = ("", "");
  my $i = 0;
  for ($i = 0; $i <= $#words; $i++) {

      # Ignore non-numeric fields at the start
      if ($i == 0 && $words[$i] =~ /[a-z]/i) {
          next;
      # Any coordinate system terminates the coordinate string
      } elsif ($words[$i] =~ /^R(B|J|D)/i) {
	  $equinox = substr($words[$i],1,1);
          last;
      } elsif ($words[$i] =~ /^(B|J)/i) {
	  $equinox = substr($words[$i],0,1);
          my $fdum = substr($words[$i],1);
          # Epoch string attached?
          if ($fdum > 1900.0 && $fdum < 2099.99) {
	    $epoch = $fdum;
          # Epoch string following?
          } elsif ($i < $#words && 
              $words[$i+1] > 1900.0 && $words[$i+1] < 2099.99) {
            $epoch = $words[$i+1];
	  }
          last;
      # Bare epoch string? Place B to J boundary at 1976.0
      } elsif ($words[$i] > 1900.0 && $words[$i] < 2099.99) {
          $epoch = $words[$i];
          if ($equinox eq "") {
	    if ($epoch < 1976.0) {
	      $equinox = 'B';
            } else {
	      $equinox = 'J';
	    }
	  }
          last;
      # Any sign provides clear split of coordinates field
      } elsif ($words[$i] =~ /^(\+|\-)/) {
          $sign = -1 if (substr($words[$i],0,1) eq '-');
          $isign = $i;
          # Strip sign
          $words[$i] = substr($words[$i],1);
          # Push any numeric value onto Declination string
          if ($words[$i] =~ /^[0-9]/) {
            last if ($num == 6);   # Might as well stop: mystery
            $dec = "$words[$i] ";
            $num++;
	  }
      } elsif ($words[$i] =~ /^[0-9]/) {
          last if ($num == 6);   # Might as well stop: don't know with yet
          if ($isign == 0) {     # another number but not like an epoch.
            $ra .= "$words[$i] ";
	  } else {
            $dec .= "$words[$i] ";
	  }
          $num++;
      }
  }

  # Delete trailing blanks
  $ra =~ s/\s+$//g;
  $dec =~ s/\s+$//g;

  # Separate fields by colons
  $ra =~ s/\s+/:/g;
  $dec =~ s/\s+/:/g;

  # First deal with the situation that no sign has been found: 
  if ($isign == 0) {
    @words = split(/\:/,$ra);
    if (($#words+1)%2 == 1) {
      # Odd number of arguments: 
      # no way to know how to divide between RA and Dec.
      return(0.0, 0.0, "", 0.0, $status);
    }
    # Divide the RA string into RA and Dec assuming equal nr. of arguments
    $ra = $dec = "";
    for ($i = 0; $i <= $#words; $i++) {
       if ($i < $#words/2) {
         $ra .= "$words[$i] ";
       } else {
         $dec .= "$words[$i] ";
       }
    }
  } 

  # Set Equinox & Epoch if necessary (Default: J2000)
  $equinox ='J' if ($equinox eq "");
  $epoch = 2000.0  if ( $equinox eq 'J' && $epoch == 0 );
  $epoch = 1950.0  if ( $equinox eq 'B' && $epoch == 0 );

  # Now change to degrees
  unless ($ra !~ /\:/ && $ra =~ /\./) {
    @words = split(/\:/,$ra);
    $ra = $words[0];
    $ra += $words[1]/60.0   if ($#words >= 1);
    $ra += $words[2]/3600.0 if ($#words >= 2);
    $ra = deg2rad(15.0*$ra);
  }

  unless ($dec !~ /\:/ && $dec =~ /\./) {
    @words = split(/\:/,$dec);
    $dec = $words[0];
    $dec += $words[1]/60.0   if ($#words >= 1);
    $dec += $words[2]/3600.0 if ($#words >= 2);
    $dec = deg2rad($sign*$dec);
  }
 
  $status = 0;
  return($ra, $dec, $equinox, $epoch, $status);
}

sub read_catalog {

   my ($catalog, $entries) = @_;

   my $i = 0;
   if (-e "$catalog") {
    open(IN,"< $catalog") or return(-2);
     while (<IN>) {
       chomp($_);
       $$entries[$i] = "$_";
       $i++;
#       push($entries,$_);
     }
     close(IN);
   } else {
#     return(-2);
     die "Failed to open catalog $catalog: $!";
   }
   return(0);
}

