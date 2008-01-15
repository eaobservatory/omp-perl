package JcmtIntCalc;

=head1 NAME

 - Calculate integration and elapse times or rms for observations at
   the JCMT.

=head1 SYNOPSIS

  use JcmtIntCalc qw/ jcmtintcalc /;

  $res_ref = jcmtintcalc( %observation );

=head1 DESCRIPTION

This module calculates either the integration & elapse time required
to reach a target rms or the resulting rms based on a specified 
integration or elapse time.

=cut

use strict;
use warnings;
use Math::Trig;

use vars qw/ $VERSION @EXPORT_OK /;
$VERSION = '0.5';

use base qw/ Exporter /;
@EXPORT_OK = qw/ jcmtintcalc /;

=head1 FUNCTIONS

=over 4

=item B<jcmtintcalc>

  Calculates either the integration & elapse time required to reach a 
  target rms or the resulting rms based on a specified integration or 
  elapse time.

  my $res = &jcmtintcalc( %observation );
  if ($res->{ier} != 1) {
    printf "\n%s\n", $res->{errmsg};
    die "\n";
  }

Hash arguments Observation:

=over 4

=item obsmode

Combination of of observation "grid_", "jiggle", or "raster" and the
switch "bmsw", "pssw", "frsw" with an underscore inbetween. Case-insensitive.
E.g. "grid_pssw". [No default]

=item instrument

Receiver used "rxa", "harp", "rxwb", "rxwd", "scuba2" . [No default]

=item rms

Target RMS in Ta* (mK/mJy). If specified and non-zero the inttime and elapse
time are calculated that are required to reach the specified rms.
Note that either rms, inttime or elapse need to be provided and non-zero,
but if none are, the routine uses a target rms of 10 mK (heterodyne) or
10 mJy (continuum)
Default: [10mK/mJy]

=item inttime

"On"-only integration time (sec) per position. If specified and
non-zero the rms and elapse time are calculated resulting from the
requested inttime.  Note that either rms, inttime or elapse need to be
provided and non-zero. [No default]

=item elapse

Approximate elapse time of the observation (min). If specified and non-zero
the rms and inttime are calculated from the specified elapse time.
Note that either rms, inttime or elapse need to be provided and non-zero.
[No default]

=item npoints

Number of points. Used for Grids and Jiggles only.
Default: [1]

=item npshared

Number of points that will have shared offs. Used for Grids and Jiggles only.
By default this will be all points, except that for position-switch the
maximum will be the number of points that fit within time_between_refs.
Npshared can be used to override with an user-set value, but it will
only affect the rms calculation not the duration.
Default: [npoints]

=item xdim, ydim

Width (xdim) and height (ydim) of raster map (arcsecs).
Used for Rasters only.
Default: [300 300]

=item dx, dy

Pixel-size in x and y (arcsecs). Used for Rasters only. If not specified
a Nyquist sampled map is assumed. For array-receivers, such as HARP, 'dx'
defines square pixels and 'dy' defines the step the array makes between
scans.

Default: [Nyquist & Full Array steps]

=item basketweave

Used for Rasters only. If specified and not 'false' or 'no', the mapping
is done as a basketweave. The values reported will be an average of scanning
along the 'long' and scanning along the 'short' dimension of the map.
Default: [false]

=item arrayoverscan

Used for Rasters only. If specified and not 'false' or 'no', the
calculations will add a half-array on each side of the area in the
scan direction. Hence, set this option to true if the specified map
only covers the science area.  If false, the calculation will use the
dimensions as specified. Be aware that if you have basketweave at
'true' and overscanning is happening at the telescope, you need to use
this option at 'true' to make the basketweave calculations come out
correct.
Default: [true]

=item filter

SCUBA2 filter: 450 or 850.
Default (SCUBA2): 850

=item sb

Dual ('dsb') or single ('ssb') single-sidebamd. Only used for RxW. RxA is
'dsb' and HARP is 'ssb' by design.
Default (RxW): [ssb]

=item pol

Dual ('dp') or single ('sp') polarization. Only used for RxW. The others
are 'sp' by design.
Default (RxW): [dp]

=item tsys

The expected system temperature during the observation (K).
Default: [400]

=item freqres

The frequency resolution (MHz)
Default: [1.0] MHz

=item sepoffs

Are OFFs to be shared between multiple 'ONs'. Grids and Jiggles only
(Rasters are shared by definition). If specified and not 'false' or 'no'
OFFs will be separate.
Default: [false]

=item contmode

Are the observations to be done in continuum mode, using a faster switch
and hence more overhead. Grids and Jiggles only. If specified and not
'false' or 'no' continuum mode will be used.
Default: [false]

=item debug

Switch on debug output, showing parameters and values at each step.
Default: [false]

=back

The routine returns a hash reference with keys:

=over 4

=item rms

As above: rms in mK (Ta*)

=item inttime

As above: "ON"-only integration time per position (secs).

=item elapse

As above: total elapse time for the observation (mins).

=item ier

Error return code. 1: Success.

=item errmsg

Error message

=back

=cut

# Possible observation modes (Note: ...-chop is also accepted in place
# of ...-bmsw
my %modes = (
   "grid-pssw" => 1,
   "grid-bmsw" => 1,
   "grid-frsw" => 0,
   "jiggle-pssw" => 1,
   "jiggle-bmsw" => 1,
   "jiggle-frsw" => 0,
   "raster-pssw" => 1,
   "raster-bmsw" => 0,
   "raster-frsw" => 0
);

# Switch on (1) debug output. Can also be set by hash key "debug".
my $debug = 0;

# Set up hash of defaults
my %defaults = (

  obsmode       => "missing",             # Observing mode
  instrument    => "missing",             # Instrument
  npoints       => 1,                     # Number of points
  rows          => 1,                     # Used for rasters
  xdim          => 600,                   # Xdim in arcsecs
  ydim          => 600,                   # Ydim in arcsecs
  dx            => "nyquist",             # X sampling in arcsecs
  dy            => "nyquist",             # Y sampling in arcsecs
  basketweave   => "false",               # Basketweave?
  arrayoverscan => "true",                # Arrayoverscan?
  sb            => "ssb",                 # Single or dual sideband
  pol           => "dp",                  # Single or dual polarization
  tsys          => 400,                   # Tsys (K)
  freqres       => 1.0,                   # Channel spacing (MHz)
  sepoffs       => "false",               # Separate offs?
  contmode      => "false",               # Continuum mode?
  debug         => 0                      # Switch on debug output

);

my $time_between_refs = 30;               # For PSSW: shared forced if
                                          # possible
my $harp_arraysize = 120;                 # harp array size
my $harp_fangle = cos(atan(0.25));        # size factor due to scan angle

sub jcmtintcalc {

  #*******************************************************************
  # This routine uses the subroutine core_rms to calculate the rms
  # in 1s independent of the observing mode. Additional observing
  # mode and number of points dependent factors are then used to
  # calculate the actual rms or inttime:
  #         "rms" = "factors" * "core" / sqrt("inttime")
  #     "inttime" = ( "rms" / ("factors" * "core") ) ** 2
  #
  # For the duration a generalized subroutine is used ($rows>=1): 
  #      "elapse" =  a + $rows * 
  #           [b * "np" * "inttime" + c * sqrt("np") * "inttime" + d]
  # a, b, c, and d are based on emperical fits  d=0 for non-raster
  # observations.
  # (http://www.jach.hawaii.edu/software/jcmtot/het_obsmodes.html)
  #*******************************************************************

  # Override defaults with arguments
  my %obs = (%defaults, @_);

  my %results = ( "ier" => 0 );
  my $prog = "jcmtintcalc";

  # Initialize some parameters used for raster maps
  my $rows = 1;          # Rows (at least 1)
  my $passes = 1;        # Basketweave passes (at least 1)
  my $xoverscan = 0;     # No overscanning for non-harp
  my $yoverscan = 0;     # No overscanning for non-harp

  # Switch on debug output if requested from calling program
  $debug = 1 if (exists $obs{debug} and $obs{debug} =~ /^[ty1]/i);

  # Bail is no obsmode or instrument
  if ($obs{obsmode} =~/missing/i or
      $obs{instrument} =~ /missing/i) {
    $results{errmsg} = "${prog}: (fatal) 'mode' and 'instrument' need to be defined in input observation hash.";
    return (\%results);
  }

  # Make sure obsmode is all lower_case and replace chop by bmsw
  my $obsmode = lc $obs{obsmode};
  $obsmode =~ s/chop/bmsw/;
  $obs{obsmode} = $obsmode;

  #  Bail if obsmode invalid
  unless (exists $modes{$obsmode} and $modes{$obsmode} == 1) {
    $results{errmsg} = "${prog}: (fatal) $obsmode is not a valid or implemented observing mode.";
    return (\%results);
  }

  # Raster specific parameters
  if ($obsmode =~ /raster/i) {

    # Need to make sure shared is turned on

    $obs{sepoffs} = "false";

    # Overscan by half the array-size on each side.
    $xoverscan = 0.5* $harp_arraysize
          if ( $obs{instrument} =~ /harp/i and
               exists $obs{arrayoverscan} and
               $obs{arrayoverscan} =~ /^[ty1]/i );

    # Along scan direction: set default sample size
    if ($obs{dx} =~ /^n/i) {
      if ($obs{instrument} =~ /rxa/i) {
        $obs{dx} = 10.0;
      } elsif ($obs{instrument} =~ /rxwd/i) {
        $obs{dx} = 5.0;
      } else {
        $obs{dx} = 7.5;
        $obs{dx} *= $harp_fangle if ($obs{instrument} =~ /harp/i);
      }
    }

    # Along cross-scan direction: jump by full footprint if HARP.
    if ($obs{dy} =~ /^n/i) {
      if ($obs{instrument} !~ /harp/i) {
        $obs{dy} = $obs{dx};
      } else {
         $obs{dy} = $harp_arraysize * $harp_fangle;
      }
    }

    # Calculate samples and rows. OT rounds up to next integer
    $obs{npoints} = 
            int(($obs{xdim}+2*$xoverscan)/$obs{dx}) + 1;
    $obs{rows} = 
            int(($obs{ydim}+2*$yoverscan)/$obs{dy}) + 1;


    # Basketweave?
    $passes = 2  if ( exists $obs{basketweave} and 
                     ( $obs{basketweave} =~ /^[ty1]/i ) );

  }

  # Start the serious work: find out what we need to calculate
  my $given = "";
  if ( exists $obs{rms} and $obs{rms} != 0 ) {
    $given = "rms";
  } elsif ( exists $obs{inttime} and $obs{inttime} != 0 ) {
    $given = "inttime";
  } elsif ( exists $obs{elapse} and $obs{elapse} != 0 ) {
    $given = "elapse";
  } else {
    $obs{rms} = 10;
    $given = "rms";
  }


  # Initialize results
  my $rms     = 0;
  my $inttime = 0;
  my $elapse  = 0;
  my $ori_elapse = exists $obs{elapse} ? $obs{elapse} : undef;


  if ($debug) {
    printf "\n%16s DEBUG: obsmode: %s, instrument: %s\n",
         $prog, $obsmode, $obs{instrument};
    printf "%16s DEBUG: separate offs: %5s, continuum mode: %5s\n",
            $prog, $obs{sepoffs}, $obs{contmode};
    printf "%16s DEBUG: basketweave: %6s\n", $prog, $obs{basketweave}
            if ( $obsmode =~ /raster/ );
    printf "%16s DEBUG: Calculation based on $given\n", $prog;
    printf "%16s -------------------------------------------------------------\n",
           ' ' ;
  }

  for (my $npass = 1; $npass <= $passes; $npass++) {

     # Switch orientation scan on alternate passes
    if ($npass > 1) {
      $obs{npoints} = 
            int(($obs{ydim}+2*$xoverscan)/$obs{dx}) + 1;
      $obs{rows}    =
            int(($obs{xdim}+2*$yoverscan)/$obs{dy}) + 1;
    }

    printf "%16s DEBUG: [Pass %d raster] %dx%d np = %d rows= %d\n",
           $prog, $npass, $obs{xdim}, $obs{ydim},$obs{npoints},
            $obs{rows} if ($debug);

    if ( $given =~ /rms/ ) {

      # Get the inttime for the requested rms

      $obs{inttime} = &Rms2IntTime( %obs );
      $obs{elapse}  = &IntTime2Elapse( %obs );

    } elsif ( $given =~ /inttime/ ) {

      $obs{rms}     = &IntTime2Rms( %obs );
      $obs{elapse}  = &IntTime2Elapse( %obs );

    } elsif ( $given =~ /elapse/ ) {

      # Make sure working with original elapse time while using
      # basketweave
      $obs{elapse}  = $ori_elapse;

      $obs{inttime} = &Elapse2IntTime( %obs );
      $obs{rms}     = &IntTime2Rms( %obs );

      # Calculate more consistent elapse
      $obs{elapse}  = &IntTime2Elapse( %obs );

    }

    # Store sum for basketweave average
    $rms     += $obs{rms};
    $inttime += $obs{inttime};
    $elapse  += $obs{elapse};

    printf "%16s DEBUG: rms = %5d, inttime = %8.1f, elapse=%5.1f\n",
      $prog, $rms/$npass, $inttime/$npass, $elapse/$npass if ($debug);

  }

  # Average over both orientations of basketweave
  $rms     /= $passes;
  $inttime /= $passes;
  $elapse  /= $passes;

  # Set final result
  $results{rms}     = $rms;
  $results{inttime} = $inttime;
  $results{elapse}  = $elapse;
  $results{ier} = 1;

  if ($debug) {
    printf "%16s -------------------------------------------------------------\n",
           ' ';
    printf "%16s DEBUG: *Result* rms = %5d, inttime = %8.1f, elapse=%5.1f\n", 
        $prog,$rms, $inttime, $elapse;
  }

  return(\%results);

}


# "METHODS" after a fashion
#

sub IntTime2Rms {

  # Calculate the rms from a given inttime accounting for shared or
  # separate offs. It uses the same observation-hash as jcmtintcalc.
  # For rasters the number of points should be set to the number of samples
  # in a row. The routine returns the calcutated rms or an error value
  # of -1.
  #         my $rms = IntTime2Rms ( %obs );

  my $prog = "IntTime2Rms";

  my $het_fudge = 1.04;                    # Unexplained fudge factor
  my $het_dfact = 1.23;                    # Correlator factor
  my $multiscan = 1.00;                    # Arrays: overlap factor

  # Override defaults with arguments
  my %obs = (%defaults, @_);

  my $inttime = 0;
  if (exists $obs{inttime} and $obs{inttime} != 0) {
    $inttime = $obs{inttime};
  } else {
    return (-1);
  }

  my $rms = -1;
  my $instrument = $obs{instrument};
  my $npshared   = $obs{npoints};

  # Just set npshared to 1 if separate offs

  $npshared = 1  if ( exists $obs{sepoffs} and
                      ( $obs{sepoffs} =~ /^[ty1]/i ) );

  # Grid-pssw forces shared if possible
  if ( $obs{obsmode} eq "grid-pssw" ) {
    $npshared = int ( $time_between_refs / $inttime );
    $npshared = 1 if ( $npshared < 1 );
    $npshared = $obs{npoints} if ( $npshared > $obs{npoints} );
  }

  # Override with any user/predefined value:
  $npshared = $obs{npshared}
     if ( exists $obs{npshared} and $obs{npshared} != 0 );

  # Correct rms if dual pol
  my $pol = 1;
  $pol = sqrt(2) if ( ( $instrument =~ /rxw/i and
                      exists $obs{pol} and $obs{pol} !~ /^s/i ) );

  printf "%16s DEBUG: [%-6s %12s] inttime = %8.2f\n",
        $prog, $instrument, $obs{obsmode}, $inttime if ($debug);

  # Scuba
  if ( $instrument =~ /scu/i) {

    printf "%16s DEBUG: needs to be implemented\n", $prog if ($debug);

                                          # Rms will be 1*nefd in 1s.
    $rms = 1;                             # But need to import nefd like
                                          # Tsys as tau dependent quantity

  # Heterodyne
  } else {

    my $tsys    = $obs{tsys};
    my $freqres = $obs{freqres};
    printf "%16s DEBUG: tsys = %6.2f, freqres = %7.4f, np shared = %3d\n",
          $prog, $tsys, $freqres, $npshared if ($debug);

    return (-1) if ($freqres == 0 or $inttime == 0 or $npshared == 0);

    # For arrays, if the dy is less than the footprint, take the
    # overlap into regard when rastering
    $multiscan = 1 / sqrt( $harp_arraysize * $harp_fangle / $obs{dy} )
        if ( $obs{obsmode} =~ /raster/i and $obs{instrument} =~ /harp/i );

    $rms = $multiscan * $het_fudge * 
           $het_dfact * sqrt(1+1/sqrt($npshared)) *
           ${tsys} / sqrt( ${freqres} * 1.0e+06 * $inttime);

    $rms /= $pol;

    # Convert to mK
    $rms *= 1000;

  }

  printf "%16s DEBUG: rms = %6.2f mK, inttime = %6.2f\n", 
         $prog, $rms, $inttime if ($debug);

  return ($rms);

}


sub Rms2IntTime {

  # Calculate the inttime from a given rms accounting for shared
  # or separate offs. It uses the same observation-hash as jcmtintcalc.
  # For rasters the number of points should be set to the number of samples
  # in a row. The routine returns the calculated inttime or an error value
  # of -1.
  #         my $inttime = Rms2IntTime ( %obs );


  my $prog = "Rms2IntTime";

  # Override defaults with arguments
  my %obs = (%defaults, @_);

  my $rms;
  if (exists $obs{rms} and $obs{rms} != 0) {
    $rms = $obs{rms};
  } else {
    return (-1);
  }

  # Calculate rms for 1 second observation
  my $inttime = 1;
  my $instrument = $obs{instrument};
  my $npshared   = $obs{npoints};

  # Just set npshared to 1 if separate offs
  $npshared = 1  if ( exists $obs{sepoffs} and
                      ( $obs{sepoffs} =~ /^[ty1]/i ) );

  # Grid-pssw forces shared if possible
  if ( $obs{obsmode} eq "grid-pssw" ) {
    $npshared = int ( $time_between_refs / $inttime );
    $npshared = 1 if ( $npshared < 1 );
    $npshared = $obs{npoints} if ( $npshared > $obs{npoints} );
  }

  # Need to iterate in case of grid-pssw and calculating inttime
  # because np shared depends on inttime

  my $max_step = 1;
  $max_step = 5 if ($obs{obsmode} eq "grid-pssw");

  # Override with any user/predefined value and don't iterate in that case.
  if ( exists $obs{npshared} and $obs{npshared} != 0 ) {
    $npshared = $obs{npshared};
    $max_step = 1;
  }

  printf "%16s DEBUG: [%-6s %12s] rms = %8.2f\n",
        $prog, $instrument, $obs{obsmode}, $rms if ($debug);

  for ( my $step = 1; $step <= $max_step; $step++ ) {

    printf "%16s DEBUG: step = %d  inttime = %6.2f  np shared= %4d\n",
          $prog, $step, $inttime, $npshared if ($debug);

    $obs{inttime} = $inttime;
    $obs{npshared} = $npshared;

    # Calculate rms
    my $irms = &IntTime2Rms ( %obs );

    # Calculate inttime based on requested rms
    if ($rms != 0) {
      $inttime *= ($irms/$rms)**2;
      $inttime = 0.1 * int (10*$inttime+0.5);
    }

    printf "%16s DEBUG: step = %d inttime = %6.2f rms = %6.2f vs. %6.2f\n",
           $prog, $step, $inttime, $irms, $rms if ($debug);

    # Need to iterate for grid-pssw
    if ( $obs{obsmode} eq "grid-pssw" ) {
       my $np_used = $npshared;
       $npshared = int ( $time_between_refs / $inttime );
       $npshared = 1 if ( $npshared < 1 );
       $npshared = $obs{npoints} if ( $npshared > $obs{npoints} );
       last if ($npshared == $np_used);
    } else {
      last;
    }

  }

  printf "%16s DEBUG: rms = %6.2f mK, inttime = %6.2f\n",
         $prog, $rms, $inttime if ($debug);

  return ($inttime);

}

sub IntTime2Elapse {

  # Calculates the elapse time of an observation. It uses the same
  # observation-hash as jcmtintcalc. Generalized duration function is:
  #       e * [ a + b*np*inttime + c*sqrt(np)*inttime + d * rows ]
  # a,b,c,d, and e are observation mode dependent.
  # Typically c !=0 only for shared offs (including rasters), d is used
  # for rasters only. e is used to account e.g. for continuum_mode.
  # The routine returns the calculated elapse time or an error value of -1.
  #         my $elapse = IntTime2Elapse ( %obs );
  # Note that the elapse time is being returned in minutes.

  my $prog = "IntTime2Elapse";

  # Override defaults with arguments
  my %obs = (%defaults, @_);
  my $obsmode = $obs{obsmode};

  my $inttime = 0;
  if (exists $obs{inttime} and $obs{inttime} != 0) {
    $inttime = $obs{inttime};
  } else {
    return (-1);
  }
  my $np = $obs{npoints};

  printf "%16s DEBUG: [%-6s %12s] inttime = %6.2f, np = %4d\n",
        $prog, $obs{instrument}, $obs{obsmode}, $inttime, $np if ($debug);

  # Make sure rows exists and is 1 for non-rasters
  my $rows = 1;
  $rows = $obs{rows} if ( exists $obs{rows} and $obs{rows} > 0 );

  # Get the obsmode dependent parameters. Note that these parameters
  # are for an elapse time in seconds.
  my ($a, $b, $c, $d, $e) = GetElapseParams ( %obs );

  my $elapse = $a +
               $rows * ($b*$np*$inttime + $c*sqrt($np)*$inttime + $d);

  printf "%16s DEBUG: basic elapse = %5.2f\n", 
         $prog, $elapse/60.0 if ($debug);

  $elapse *= $e;

  # Convert to minutes
  $elapse /= 60.0;

  return ( $elapse );

}

sub Elapse2IntTime {

  # Calculates the inttime of an observation based in the elapse time. 
  # It uses the same observation-hash as jcmtintcalc. Generalized duration
  # function is:
  #       e * [ a + b*np*inttime + c*sqrt(np)*inttime + d * rows ]
  # a,b,c,d, and e are observation mode dependent.
  # Typically c !=0 only for shared offs (including rasters), d is used
  # for rasters only. e is used to account e.g. for continuum_mode.
  # The routine returns the calculated elapse time or an error value of -1.
  #         my $inttime = Elapse2IntTime ( %obs );
  # Note that the elapse time is being returned in minutes.

  my $prog = "Elapse2IntTime";

  # Override defaults with arguments
  my %obs = (%defaults, @_);
  my $obsmode = $obs{obsmode};

  my $elapse = 0;
  if (exists $obs{elapse} and $obs{elapse} != 0) {
    $elapse = $obs{elapse};
  } else {
    return (-1);
  }

  my $np = $obs{npoints};

  printf "%16s DEBUG: [%-6s %12s] elapse = %6.2f, np = %4d\n",
        $prog, $obs{instrument}, $obs{obsmode}, $elapse, $np if ($debug);

  # Make sure rows exists and is 1 for non-rasters
  my $rows = 1;
  $rows = $obs{rows} if ( exists $obs{rows} and $obs{rows} > 0 );

  # Get the obsmode dependent parameters. Note that these parameters
  # are for an elapse time in seconds.
  my ($a, $b, $c, $d, $e) = GetElapseParams ( %obs );

  # Convert to seconds
  $elapse *= 60.0;

  $elapse /= $e;

  printf "%16s DEBUG: basic elapse = %5.2f\n",
         $prog, $elapse/60.0 if ($debug);

  my $inttime = ($elapse - $a - $rows*$d) / ($rows * ($b*$np + $c*sqrt($np)));

  $inttime = 0.1 * int (10*$inttime+0.5);

  return ( $inttime );

}

sub GetElapseParams {

  # Returns a,b,c and d for the generalized duration equation
  # based on the observing mode:
  #
  #    e * [ a + b*np*inttime + c*sqrt(np)*inttime + d * rows ]
  #
  # 'a', 'b' ,'c', 'd', and 'e' are observation mode dependent.
  # Typically c !=0 only for shared offs (including rasters), d is used
  # for rasters only.
  # 'e' is an overall factor stuck in for continuum-mode, because it's 
  # effect has not been measured well presently,
  # The routine returns the calculated or an error value(s)of -1,-1,-1,-1.
  #      my ($a, $b, $c, $d, $e ) = GetElapseParams ( %obs );

  my $prog = "GetElapseParams";

  # Override defaults with arguments
  my %obs = (%defaults, @_);

  my $obsmode = $obs{obsmode};
  my $np = $obs{npoints};

  # Continuum mode factor: pretty much a guess
  my $cont_factor = 1.2;

  # Continuum mode?
  my $continuum_mode = 0;
  $continuum_mode = 1
      if ( exists $obs{contmode} &&  $obs{contmode} =~ /^[ty1]/i );

  # Shared offs?
  my $shared = 1;
  $shared = 0 if ( $np == 1 or 
                   ( exists $obs{sepoffs} and $obs{sepoffs} =~ /^[ty1]/i ) );

  # Set up the mode dependent parameters:
  my ($a, $b, $c, $d, $e);
  $c = 0;             # c is almost always 0
  $d = 0;             # d is almost always 0
  $e = 1;             # e not continuum-mode

  # e: continuum mode factor does not dependent on the obsmode yet.
  $e = $cont_factor if ($continuum_mode);

  printf "%16s DEBUG: np = %4d sepoffs = %5s, continuum mode = %5s\n", 
         $prog, $np, $obs{sepoffs}, $obs{contmode}  if ($debug);

  if ( $obsmode =~ "jiggle-bmsw" ) {
    $a = 100;
    ($shared) ? ( do {$b = 1.27; $c = 1.27;} ) : ( $b = 2.3 );

  } elsif ( $obsmode eq "grid-bmsw" ) {

               # Don't really know this one, but assume its done non-shared
               # and slightly inbetween jiggle-bmsw and jiggle-pssw
    $a = 100; $b = 2.37;

  } elsif ( ( $obsmode eq "jiggle-pssw" ) or
            ( $obsmode eq "grid-pssw"  and $np == 1 ) ) {

    $a = 80;
    ($shared) ? ( $b = 1.75 ) : (  $b = 2.45 );

  } elsif ( $obsmode eq "grid-pssw" and $np != 1 ) {

    # Force shared curve for the calculation since non-shared not allowed.
    #($shared) ? ( do {$a = 80; $b = 2.65;} ) : ( do {$a = 190; $b = 2.0;} );
    $a = 80; $b = 2.65;

  } elsif ( $obsmode eq "raster-pssw" ) {

               # Have not measured this one assume similar to
               # jiggle-pssw for a single row
    $a = 80; $b = 1.05; $c = 1.05 ; $d = 18

  }

  printf "%16s DEBUG: a = %5.2f, b = %5.2f, c =  %5.2f, d = %5.2f e = %5.2f\n",
         $prog, $a, $b, $c, $d,  $e  if ($debug);

  return ($a, $b, $c, $d, $e);

}

=back

=head1 NOTES

Presently, frequency switching is not implemented yet.

=head1 TODO

Add frequency switching. Add SCUBA_2 integration time calculator.

=head1 SEE ALSO

http://www.jach.hawaii.edu/software/jcmtot/ and the documents references
therein for additional information on observing modes in use at the JCMT.

=head1 AUTHOR

Remo P. J. Tilanus E<lt>r.tilanus@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2007 Science and Technology Facilities Council.
All Rights Reserved.

=cut
