package GetCoords;

#package Astro::SourcePlot_new;

=head1 NAME

Astro::GetCoords - Return an array of ASTRO coordinate objects from
                   the OMP, a catalog, or user supplied positions.

=head1 SYNOPSIS

  use Astro::GetCoords qw/ get_coords /;
  my @coords = get_coords ( $method, \@projids, \@objects, %args );

=head1 DESCRIPTION

This module has methods to return an array of coordinate objects from
the OMP science programs, catalog files, or user supplied coordinates.
Results can be filtered by project-ids and/or a list of selective
targets. If planets are (also) requested, their coordinate objects will
be obtained using ephemerides.

=cut

use strict;
use warnings;

use Astro::Coords;
use Astro::Telescope;
use Time::Piece qw/ :override /;

use lib qw( /jac_sw/omp/msbserver );

use OMP::Config;
use OMP::SpServer;
use OMP::SciProg;
use OMP::MSB;
use OMP::Error qw/ :try /;

OMP::Config->cfgdir( "/jac_sw/omp/msbserver/cfg" );

use vars qw/ $VERSION @ISA @EXPORT_OK/;
$VERSION = '1.1';

use Exporter;
@ISA = ('Exporter');
@EXPORT_OK = ( 'get_coords' );

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
be smooth. Defaults to 300 seconds.

=item plot_center

For the time axis, offset of the plot center from local midnight
(in seconds). Defaults to local midnight.

=item plot_int

For the time axis, time interval to plot (in seconds). The plot will
be from -plot_int to plot_int around the plot_center.
Default to 43200 (i.e. 12 hours)

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



sub get_coords  {

#
# Get source coordinates:
#
#      my @coords = get_coords ( $method, \@projids, \@objects, %args )
#
#
#      $method:   [ omp | catalog | user ] Method of obtaining
#                 coordinates: Query OMP DB, read a catalog file,
#                 or use user-supplied values.
#
#      @projids:  Array with projids for which to check objects
#
#      @objects:  Array of hashes with selected object to find:
#                 {'name},[ {'ra'}, {'dec'}, {'coordsys'} ]:
#                 {'ra'} and {'dec'} ':' or space separated sexagesimal:
#                                 hh:mm:ss.s  [-]dd mm ss.s.
#                 {'coordsys'}: B1950, J2000, or galactic. (or their
#                             short-hands RB, RJ, RG, GA). Note: for
#                 galactic coordinates the values porvided with 'ra'
#                 and 'dec' will be interpreted as 'long' and 'lat'.
#
#     %args:      Additional arguments (see also description methods).
#                 Optional for all methods:
#
#                 {'telescope'}: Name of the telescope. If provided the
#                        appropriate telescope object will be added
#                        to the coord object
#                 {'debug'}: 0: Stay quiet; 1: Turn on debug output,
#                        including in called routines.
#
#
# Query OMP DB:
#         @projids is a required parameter. %objects is optional and
#         only the {name} key is used.
#
#         The coord objects from all MSBs of the requested projects are
#         retrieved and returned. If objects{name}s have been specified
#         only the coords of targets for which the name matches exactly
#         will be returned.
#
#         Additional optional keys for %args:
#            {msbmode}:  [ All | Active | Completed ] 
#                        Only process targets for msbs matching the
#                        specified criterium. Default: All.
#
# Read catalog:
#         @projids is an optional parameter. %objects is optional and
#         only the {name} key is used.
#
#         Read the coordinates from a catalog file. The general format
#         of the file is:
#             Name   Long  Lat  Coordsys  ... ...   Projid ...
#         The abbreviations RB, RJ, GA, RG are accepted for B1950, J2000,
#         galactic, respectively. Coord objects will be returned for
#         all selected objects.
#
#         Required: the name of the catalog needs to be supplied through
#            $args{'catalog'}
#
# User supplied:
#         @projids is not used. A fully specified %objects is required
#         with the keys {name}, {ra}, {dec}, and {coorsys}. 
#
#         Return coord objects for all objects specified.

  # Parameters:
  my ($method, $projref, $objref, %args ) = @_;
  my @projids = @{$projref};
  my @objects = @{$objref};

  # 0: stay quiet; 1: turn on debug output
  my $debug = 0;

  # Turn on debug if instructed from above
  $debug = 1 if( exists $args{'debug'} and $args{'debug'} == 1 );
  # Turn on/off debug in subroutines independently
  # $args{'debug'} = 0;

  # Coords array to return:
  my @coords;

  # Handle planets separately
  my %planets = ('sun',     0, 'mercury', 1, 'venus',  2, 'moon',   3,
                 'mars',    4, 'jupiter', 5, 'saturn', 6, 'uranus', 7,
                 'neptune', 8, 'pluto',   9);
  my $nr_planets = 0;
  foreach my $obj (@objects) {

    while ( my ($key, $value) = each(%$obj) ) {
      print "$key => $value\n";
    }

    my $objname = lc ${$obj}{'name'};

    if( exists $planets{$objname} ) {
      push( @coords, new Astro::Coords( planet => "$objname" ) );
      $nr_planets++;

    # User supplied positions
    } elsif( $method =~ /^u/i ) {

      $$obj{ra} =~ s/^\s+//;
      $$obj{ra} =~ s/\s+$//;
      $$obj{ra} =~ s/\s+/:/;

      $$obj{dec} =~ s/^\s+//;
      $$obj{dec} =~ s/\s+$//;
      $$obj{dec} =~ s/\s+/:/;

      $$obj{coordsys} = "J2000" if( $$obj{coordsys} =~ /RJ/i );
      $$obj{coordsys} = "B1950" if( $$obj{coordsys} =~ /RB/i );
      $$obj{coordsys} = "Galactic" if( $$obj{coordsys} =~ /G/i );

      my $coord;
      if( $$obj{'coordsys'} !~ /^g/i ) {
        $coord = new Astro::Coords( 'name' => $$obj{'name'},
                                    'ra'   => $$obj{'ra'},
                                    'dec'  => $$obj{'dec'},
                                    'type' => $$obj{'coordsys'},
                                    'units'=> 'sexagesimal'
                                  );
      } else {
        $coord = new Astro::Coords( 'name' => $$obj{'name'},
                                    'long' => $$obj{'ra'},
                                    'lat'  => $$obj{'dec'},
                                    'type' => $$obj{'coordsys'},
                                    'units'=> 'sexagesimal'
                                  );
      }

      # Add telescope information to coords object if provided!
      $coord->telescope( new Astro::Telescope( $args{'telescope'} ))
            if( $args{'telescope'} ne 'TELUNKNOWN' );

      # Add current target to list
      push( @coords, $coord );

    }
  }

  # Now throw away @objects if only planets specified. The rest of
  # program will proceed as if no objects had been specified: i.e.
  # plot all sources of the projects requested.
  # This is a bit naughty, but the idea is that planets can always
  # be added without changing the basic bahaviour of the routine.

  @objects = () if( $#objects < $nr_planets );

  # Querying omp
  if( $method =~ /^o/i and $#projids > -1 ) {

    # Retrieve Science Project objects
    my @sciprogs;
    foreach my $projid ( @projids ) {
      printf "Retrieve science program for $projid\n" if( $debug );
      my $E;
      try {
        my $sp =  OMP::SpServer->fetchProgram($projid,"PASSWORD",1);
        push( @sciprogs,$sp );
      } catch OMP::Error with {
        # Just catch OMP::Error exceptions
        # Server infrastructure should catch everything else
        $E = shift;
      } otherwise {
        # This is "normal" errors. At the moment treat them like any other
        $E = shift;
      }
    }

    if ($#sciprogs >=  0) {

      # Get coordinates of observations in MSBs
      push( @coords, get_omp_coords( \@sciprogs,
                                   \@objects,
                                   'msbmode' =>   $args{'msbmode'},
                                   'telescope' => $args{'telescope'}
                                 ) );
    }

  }


  # Using catalog file
  if( $method =~ /^c/i ) {

    # Get coordinates of observations in MSBs
    push( @coords, get_catalog_coords( \@projids,
                                       \@objects,
                                       'catalog' => $args{'catalog'},
                                       'telescope' => $args{'telescope'}
                                     ) );
  }

  return @coords ;

}


sub get_omp_coords {


  # Use:  my @coords = get_omp_coords( @sciprogs, @objects, %args );
  #
  # Parameters:
  #    @sciprogs:  array of science project objects
  #    @objects:   array of hashes with names of selective targets
  #                to find (optional)
  #    %args:      hash with optional arguments:
  #                msbmode: select [ "All" | "Active" | "Completed" ]
  #                         msbs. Default "All".
  #                telescope: if provided, will be added to coord object
  #
  # Returned:
  #                array of coord objects with targets.

  # Set up defaults
  my %defaults = (
     'msbmode'   => "all",        # msbs to retrieve:
                                #      [all | active | completed]
     'telescope' => "TELUNKOWN"   # telescope not provided
  );

  # Get parameters
  my $spref = shift;
  my $objref = shift;
  my @sciprogs = @{$spref};
  my @objects = @{$objref};

  
  # Override defaults with remaining arguments
  my %args = ( %defaults, @_ );

  # 0: stay quiet; 1: turn on debug output
  my $debug = 0;

  # Turn on debug if instructed from above
  $debug = 1 if( exists $args{'debug'} and $args{'debug'} == 1 );
  # Turn on/off debug in subroutines independently
  # $args{'debug'} = 0;

  # Now extract (optional) object names into hash
  # Note that we will only use the key from this
  my %selected_targets;
  my $selected_targets_only = 0;
  foreach my $obj (@objects) {
    $selected_targets{lc $$obj{'name'}} = 1;
    $selected_targets_only++;
  }

  if( $debug ) {
    print "nr selected targets: ${selected_targets_only}\n";
    foreach my $key (keys %selected_targets) {
      print "         name: '$key'\n";
    }
  }

  my $nr = 0;
  my @coords;
  my %targets;

  # Loop over the science programs
  foreach my $sp (@sciprogs) {

    printf "Extract MSBs\n" if( $debug );
    my @msbs = $sp->msb;
    printf "%d MSBs returned\n", $#msbs+1 if( $debug );

    # Handle each MSB
    foreach my $msb (@msbs) {

      $nr++;
      printf "MSB %3.3d: %d remaining\n", $nr, $msb->remaining if( $debug );

      if( $args{'msbmode'} =~ /^ac/i ) {

        # Skip MSBs done if retrieving only active
        next if( $msb->remaining <= 0 );

      } elsif( $args{'msbmode'} =~ /^c/i ) {

        # Skip uncompleted MSBs if only retrieving completed
        next if( $msb->remaining > 0 );

      }

      # Get the observations
      my @obss = $msb->obssum;

      printf "Extract each of the %d observations\n", $#obss+1 if( $debug );
      my $noname = 0;
      foreach my $obs (@obss) {

        my $target = $obs->{coords};
        next unless $target;

        next if (not defined $target->name);

        if ( length($target->name) == 0 ) {
          $noname++;
          $target->name("noname${noname}");
        }

        printf "Target: '%s'\n", $target->name if( $debug );

        # Skip un-requested targets: name is used as hash key
        if( $selected_targets_only > 0 ) {
          print "...Skip unrequested targets\n" if( $debug );
          next unless( exists $selected_targets{lc $target->name} );
        }

        # Oops, can not handle other coord systems but equatorial
        print "...Skip un-equatorial and 0,0 coordinates\n" if( $debug );
        next unless( $target->type eq 'RADEC' );
        next if( $target->ra == 0.0 and $target->dec == 0.0 );

        # Handle duplicate sources through the hash key
        my $target_info = $target->name . '_' .
	    $target->ra . '_' . $target->dec;

        # Name and coordinates identical.
        print "...Skip duplicate targets\n" if( $debug );
        if( exists $targets{$target_info} ) {
          next;
        }

        print "...Add new target to hash\n" if( $debug );
        # Add info current target to 'duplicate' hash
        $targets{$target_info} = 1;

        # Add telescope information to coords object if provided!
        $target->telescope( new Astro::Telescope( $args{'telescope'}) )
             if( $args{'telescope'} ne 'TELUNKOWN' );

        # Add current target to list
        push( @coords, $target );

      }

    }
  }

  if( $debug ) {
    foreach my $target (@coords) {
      printf "%16.16s  %12.9f  %12.9f\n", $target->name,
                                          $target->ra, $target->dec;
    }
  }

  return @coords ;

}

sub get_catalog_coords {

  # Use:  my @coords = get_catalog_coords( \@projids,
  #                                        \@objects,
  #                                        catalog => $catalog, %args );
  #
  # Parameters:
  #    @projids:   array with project ids
  #    @objects:   array with names of selective targets find (optional)
  #    {catalog}:  Name of the catalog (can also be given through %args)
  #    %args:      hash with optional arguments:
  #                telescope: if provided, will be added to coord object
  #
  # Returned:
  #                array of coord objects with targets.

  # Set up defaults
  my %defaults = (
     'telescope' => "TELUNKNOWN"   # telescope not provided
  );

  # Get parameters
  my $projref = shift;
  my $objref = shift;
  my @projids = @{$projref};
  my @objects = @{$objref};

  # Override defaults with remaining arguments
  my %args = ( %defaults, @_ );

  # 0: stay quiet; 1: turn on debug output
  my $debug = 0;

  # Turn on debug if instructed from above
  $debug = 1 if( exists $args{'debug'} and $args{'debug'} == 1 );
  # Turn on/off debug in subroutines independently
  # $args{'debug'} = 0;

  # Now extract (optional) object names into hash
  # Note that we will only use the key from this
  my %selected_targets;
  my $selected_targets_only = 0;
  foreach my $obj (@objects) {
    $selected_targets{lc $$obj{'name'}} = 1;
    $selected_targets_only++;
  }

  if( $debug ) {
    print "nr selected targets: ${selected_targets_only}\n";
    foreach my $key (keys %selected_targets) {
      print "         name: '$key'\n";
    }
  }

  my $nr = 0;
  my @coords;
  my %targets;

  die "%%get_catalog_coords: No catalog file specified\n"
      unless( exists $args{'catalog'} );

  # Open and read in file
  open( IN,"<$args{'catalog'}" ) or die "Failed to open catalog: $!";
  my @catlines = <IN>;
  close IN ;

  # Loop over the lines in the catalog
  foreach my $line (@catlines) {

    chop $line;

    next if( $line =~ /^\#|\%|\!|\*/ );             # Skip comment lines

    if( $#projids >= 0 ) {
      # Check if project id is on the line
      my $found = 0;
      foreach my $proj (@projids) {
        if( $line =~ /$proj/i ) {
          $found = 1;
          last;
        }
      }
      next unless( $found );
    }

    # Parse the catalog line: allow for many variations
    my %target = parse_coords( $line );
    unless( $target{'status'} == 0 ) {
      print "Could not parse coordinates for %s\n", $target{'name'};
      next;
    }

    printf "Target: '%s'\n", $target{'name'} if( $debug );

    # Skip un-requested targets: name is used as hash key
    if( $selected_targets_only > 0 ) {
      print "...Skip unrequested targets\n" if( $debug );
      next unless( exists $selected_targets{lc $target{'name'}} );
    }

    # Handle duplicate sources through the hash key
    my $target_info = $target{'name'} . '_' .
                      $target{'ra'} . '_' . $target{'dec'};

    # Name and coordinates identical.
    print "...Skip duplicate targets\n" if( $debug );
    next if( exists $targets{$target_info} );

    print "...Add new target to hash\n" if( $debug );
    # Add info current target to 'duplicate' hash
    $targets{$target_info} = 1;

    # Construct new coord object
    printf "%16.16s  %12.12s  %12.12s %8.8s\n",
           $target{'name'}, $target{'ra'}, $target{'dec'},
           $target{'coordsys'} if( $debug );

    my $coord;
    if( $target{'coordsys'} !~ /^g/i ) {
       $coord = new Astro::Coords( 'name' => $target{'name'},
                                   'ra'   => $target{'ra'},
                                   'dec'  => $target{'dec'},
                                   'type' => $target{'coordsys'},
                                   'units'=> 'sexagesimal'
                                 );
    } else {
       $coord = new Astro::Coords( 'name' => $target{'name'},
                                   'long' => $target{'ra'},
                                   'lat'  => $target{'dec'},
                                   'type' => $target{'coordsys'},
                                   'units'=> 'sexagesimal'
                                 );
    }

    # Add telescope information to coords object if provided!
    $coord->telescope( new Astro::Telescope( $args{'telescope'}) )
          if( $args{'telescope'} ne 'TELUNKNOWN' );

    # Add current target to list
    push( @coords, $coord );

  }


  if( $debug ) {
    foreach my $target (@coords) {
      printf "%16.16s  %12.9f  %12.9f\n", $target->name,
                                          $target->ra, $target->dec;
    }
  }

  return(@coords);

}

# **********************************************************************
#   %target = parse_coords(catalog_line)
#
#   Returned target hash: {name}, {ra}, {dec}, {coordsys}
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

  # split the catalog line
  my ($catalog_line) = @_;
  $catalog_line =~ s/^\s+//;
  my @words = split( /\s+/,$catalog_line );

  # Initialize target with failure to parse status
  my %target = ( 'status' => -1 );

  my ($equinox, $epoch) = ("", 0);
  my ($sign, $isign) = ("", 0);
  my ($inum, $num) = (0, 0);
  my ($ra, $dec) = ("", "");
  my $i = 0;

  $target{'name'} = $words[0];   # Name must be the first word
  my $wid=1;

  # Non-numeric fields at the start must be part of name (yuk!)
  while ($wid <= $#words and $words[$wid]=~ /[a-z]/i) {
    $target{'name'} .= ' ' . $words[$wid];
    $wid++;
  }

  for ($i = $wid; $i <= $#words; $i++) {

      # Any coordinate system terminates the coordinate string
      if( $words[$i] =~ /^R(B|J|G )/i) {
	  $equinox = substr( $words[$i],1,1 );
          last;
      } elsif( $words[$i] =~ /^(B|J|G )/i) {
	  $equinox = substr( $words[$i],0,1 );
          my $fdum = substr( $words[$i],1 );
          # Epoch string attached?
          if( $fdum > 1900.0 && $fdum < 2099.99 ) {
	    $epoch = $fdum;
          # Epoch string following?
          } elsif( $i < $#words && 
              $words[$i+1] > 1900.0 && $words[$i+1] < 2099.99 ) {
            $epoch = $words[$i+1];
	  }
          last;
      # Bare epoch string? Place B to J boundary at 1976.0
      } elsif( $words[$i] > 1900.0 && $words[$i] < 2099.99 ) {
          $epoch = $words[$i];
          if( $equinox eq "" ) {
	    if( $epoch < 1976.0 ) {
	      $equinox = 'B';
            } else {
	      $equinox = 'J';
	    }
	  }
          last;
      # Any sign provides clear split of coordinates field
      } elsif( $words[$i] =~ /^(\+|\-)/ ) {
          $sign = "-" if( substr( $words[$i],0,1) eq '-' );
          $isign = $i;
          # Strip sign
          $words[$i] = substr( $words[$i],1 );
          # Push any numeric value onto Declination string
          if( $words[$i] =~ /^[0-9]/ ) {
            last if( $num == 6 );   # Might as well stop: mystery
            $dec = "$words[$i] ";
            $num++;
	  }
      } elsif( $words[$i] =~ /^[0-9]/ ) {
          last if( $num == 6 );   # Might as well stop: what to do with
          if( $isign == 0 ) {     # another number that is not an epoch?
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

  # Now deal with the situation that no sign was found:
  if( $isign == 0 ) {
    @words = split( /\:/,$ra );
    if( ($#words+1)%2 == 1 ) {
      # Odd number of arguments: 
      # no way to know how to divide between RA and Dec.
      return %target ;
    }
    # Divide the RA string into RA and Dec assuming equal nr. of arguments
    $ra = $dec = "";
    for ($i = 0; $i <= $#words; $i++) {
       if( $i < $#words/2 ) {
         $ra .= "$words[$i]:";
       } else {
         $dec .= "$words[$i]:";
       }
    }
  }

  # Delete trailing ':'
  $ra =~ s/\:$//g;
  $dec =~ s/\:$//g;

  # Set Equinox & Epoch if necessary (Default: J2000)
  $equinox ='J'  if( $equinox eq "" );
  $epoch = 2000  if( $equinox eq 'J' && $epoch == 0 );
  $epoch = 1950  if( $equinox eq 'B' && $epoch == 0 );
  $epoch = 'alactic'  if( $equinox eq 'G' );

  $target{ra}= $ra;
  $target{dec}= $sign . $dec;
  $target{coordsys}= lc $equinox . $epoch;
  $target{'status'} = 0;

  return %target ;
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

