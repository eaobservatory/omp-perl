package OMP::Translator::JCMT;

=head1 NAME

OMP::Translator::JCMT - Base class for JCMT configure XML translations

=head1 SYNOPSIS

  use OMP::Translator::JCMT;
  $config = OMP::Translator::JCMT->translate( $sp );

=head1 DESCRIPTION

Routines that are shared for all JCMT translations involving configuration
XML suitable for the OCS CONFIGURE action.

=cut

use 5.006;
use strict;
use warnings;
use Carp;

use Data::Dumper;

use Net::Domain;
use File::Spec;
use File::Basename;
use Astro::Coords::Offset;
use IO::Tee;
use Storable;

use JCMT::SMU::Jiggle;
use JAC::OCS::Config;
use JAC::OCS::Config::Error qw/ :try /;

use OMP::Config;
use OMP::Error;
use OMP::General;

use base qw/ OMP::Translator /;

# Default directory for writing configs
our $TRANS_DIR = OMP::Config->getData( 'jcmt_translator.transdir');

# Version number
our $VERSION = sprintf("%d", q$Revision: 14936 $ =~ /(\d+)/);

# Mapping from OMP to OCS frontend names
our %FE_MAP = (
               RXA3 => 'RXA',
               RXWB => 'RXWB',
               RXWD => 'RXWD',
               RXB3 => 'RXB',
               'RXHARP-B' => 'HARPB',
               HARP => 'HARP',
               SCUBA2 => 'SCUBA2',
              );

# Telescope diameter in metres
use constant DIAM => 15;

=head1 METHODS

=over 4

=item B<translate>

Converts a single MSB object to one or many OCS Configs.
It is assumed that this MSB will refer to an OCS observation
(and has been prefiltered by the caller, usually C<OMP::Translator>).
Always returns the configs as an array of C<JAC::OCS::Config> objects.

  @configs = OMP::Translate->translate( $msb );
  @configs = OMP::Translate->translate( $msb, simulate => 1 );

It is the responsibility of the caller to write these objects.

Optional hash arguments can control the specific translation.
Supported arguments are:

  simulate :  Include simulation configuration. Default is false.

=cut

sub translate {
  my $self = shift;
  my $msb = shift;
  my %opts = ( simulate => 0, @_ );

  # Project
  my $projectid = $msb->projectID;

  # OT version
  my $otver = $msb->ot_version;
  print "OTVERS: $otver \n" if $self->debug;

  # The default parser treats waveplate angles as discrete
  # observations per waveplate. This translator treats them as a single
  # observation.
  $self->correct_wplate($msb);

  # Correct Stare observations such that multiple offsets are
  # combined
  # Note that there may be a requirement to convert non-regular offset
  # patterns into individual observations rather than having a very sparse
  # but large grid
  $self->correct_offsets( $msb, "Stare" );

  # Now unroll the MSB into constituent observations details
  my @configs;
  for my $obs ($msb->unroll_obs) {

    # unroll_obs does not do a deep copy of references - we need independence
    # because the translator writes to the structure
    $obs = Storable::dclone( $obs );

    # Translate observing mode information to internal form
    $self->observing_mode( $obs );

    # if there are any special patch ups call them here
    $self->fixup_historical_problems( $obs )
      if $self->can("fixup_historical_problems");

    # We need to patch up POINTING and FOCUS observations so that they have
    # the correct parameters
    $self->handle_special_modes( $obs );

    # Create blank configuration
    my $cfg = new JAC::OCS::Config;

    # Set verbosity and debug level
    $cfg->verbose( $self->verbose );
    $cfg->debug( $self->debug );
    $cfg->outhdl( $self->outhdl ) if $cfg->can("outhdl");

    # Add comment
    $cfg->comment( "Translated on ". gmtime() ."UT on host ".
                   Net::Domain::hostfqdn() . " by $ENV{USER} \n".
                   "using Translator version $VERSION on an MSB created by the OT version $otver\n");

    # Observation summary
    $self->obs_summary( $cfg, %$obs );

    # Instrument config
    $self->instrument_config( $cfg, %$obs );

    # configure the basic TCS parameters
    $self->tcs_config( $cfg, %$obs );

    # call the special routines for this instrument
    $self->frontend_backend_config( $cfg, %$obs );

    # HEADER_CONFIG
    $self->header_config( $cfg, %$obs );

    # Polarimeter
    $self->pol_config( $cfg, %$obs );

    # RTS
    $self->rts_config( $cfg, %$obs );

    # JOS Config
    $self->jos_config( $cfg, %$obs );

    # Slew and rotator need to wait until we can estimate
    # the duration of the configuration
    $self->slew_config( $cfg, %$obs );
    $self->rotator_config( $cfg, %$obs );

    # Simulator
    $self->simulator_config( $cfg, %$obs ) if $opts{simulate};

    # Store the completed config
    push(@configs, $cfg);

    # For debugging we need to see the unrolled information
    # do it late so that we get to see the acsis backend information
    # as calculated by the translator
    print Dumper( $obs ) if $self->debug;

    # and also the translated config itself
    print $cfg if $self->debug;

  }


  # return the config objects
  return @configs;
}

=item B<debug>

Method to enable and disable global debugging state.

  OMP::Translator::JCMT->debug( 1 );

Note that debugging will be enabled for all subclasses.

=cut

{
  my $dbg;
  sub debug {
    my $class = shift;
    if (@_) {
      my $state = shift;
      $dbg = ($state ? 1 : 0 );
    }
    return $dbg;
  }
}

=item B<outhdl>

Output file handles to use for verbose messages.
Defaults to STDOUT.

  OMP::Translator::JCMT->outhdl( \*STDOUT, $fh );

Returns an C<IO::Tee> object.

Pass in undef to reset to the default.

=cut

{
  my $def = new IO::Tee(\*STDOUT);
  my $oh = $def;
  sub outhdl {
    my $class = shift;
    if (@_) {
      if (!defined $_[0]) {
        $oh = $def;             # reset
      } else {
        $oh = new IO::Tee( @_ );
      }
    }
    return $oh;
  }
}

=item B<verbose>

Method to enable and disable global verbosity state.

  OMP::Translator::JCMT->verbose( 1 );

=cut

{
  my $verb;
  sub verbose {
    my $class = shift;
    if (@_) {
      my $state = shift;
      $verb = ($state ? 1 : 0 );
    }
    return $verb;
  }
}


=item B<transdir>

Override the default translation directory.

  OMP::Translator::JCMT->transdir( $dir );

=cut

sub transdir {
  my $class = shift;
  if (@_) {
    my $dir = shift;
    $TRANS_DIR = $dir;
  }
  return $TRANS_DIR;
}

=back

=head1 CONFIG GENERATORS

These routines configure the specific C<JAC::OCS::Config> objects.

=over 4

=item B<obs_summary>

Observation summary.

 $trans->obs_summary( $cfg, %info );

where $cfg is the main C<JAC::OCS::Config> object. Stores a
C<JAC::OCS::Config::ObsSummary> object into the supplied
configuration.

=cut

sub obs_summary {
  my $self = shift;
  my $cfg = shift;
  my %info = @_;

  my $obs = new JAC::OCS::Config::ObsSummary;

  $obs->mapping_mode( $info{mapping_mode} );
  $obs->switching_mode( defined $info{switching_mode} 
                        ? $info{switching_mode} : 'none' );
  $obs->type( $info{obs_type} );
  $obs->inbeam( $info{inbeam} )
    if (exists $info{inbeam} && defined $info{inbeam});

  $cfg->obs_summary( $obs );
}

=item B<tcs_config>

TCS configuration.

  $trans->tcs_config( $cfg, %info );

where $cfg is the main C<JAC::OCS::Config> object.

=cut

sub tcs_config {
  my $self = shift;
  my $cfg = shift;
  my %info = @_;

  # Create the template
  my $tcs = new JAC::OCS::Config::TCS;

  # Pointing, focus and autoTarget observations need to force
  # state rather than using the inherited state

  # Telescope is known
  $tcs->telescope( 'JCMT' );

  # First the base position
  $self->tcs_base( $cfg, $tcs, %info );

  # observing area
  $self->observing_area( $tcs, %info );

  # Then secondary mirror
  $self->secondary_mirror( $tcs, %info );

  # Fix up the REFERENCE position for Jiggle/Chop if we have not been given
  # one explicitly. We need to do this until the JOS recipe can be fixed to
  # go to the chop position for its CAL automatically
  # Only do this if we have a target.
  my %tags = $tcs->getAllTargetInfo;
  if (exists $tags{SCIENCE} && 
      !exists $tags{REFERENCE} && $info{switching_mode} =~ /chop/) {
    # The REFERENCE should be the chop off position for now
    my $ref = new JAC::OCS::Config::TCS::BASE;
    $ref->tag( "REFERENCE" );
    $ref->coords( $tags{SCIENCE}->coords );
    $ref->tracking_system( $tags{SCIENCE}->tracking_system );

    # Chop info
    my $sec = $tcs->getSecondary;
    my %chop = $sec->chop();

    throw OMP::Error::TranslateFail("Chopped mode specified but no chop position angle defined\n") unless exists $chop{PA} && defined $chop{PA};

    # convert this polar coordinate to cartesian
    my $chop_x = $chop{THROW} * sin( $chop{PA}->radians );
    my $chop_y = $chop{THROW} * cos( $chop{PA}->radians );

    # prettyify
    $chop_x = sprintf( "%.2f", $chop_x );
    $chop_y = sprintf( "%.2f", $chop_y );

    # offset
    my $offset = new Astro::Coords::Offset( $chop_x, $chop_y,
                                            system => $chop{SYSTEM} );

    $ref->offset( $offset );

    $tcs->setCoords( "REFERENCE", $ref );

  }


  # Slew and rotator require the duration to be known which can
  # only be calculated when the configuration is complete

  # Store it
  $cfg->tcs( $tcs );
}

=item B<tcs_base>

Calculate the position information (SCIENCE and REFERENCE)
and store in the TCS object.

  $trans->tcs_base( $cfg, $tcs, %info );

where $tcs is a C<JAC::OCS::Config::TCS> object.

Does nothing if autoTarget is true.

=cut

sub tcs_base {
  my $self = shift;
  my $cfg = shift;
  my $tcs = shift;
  my %info = @_;

  # Find out if we have to offset to a particular receptor
  my $instap = $self->tracking_receptor_or_subarray( $cfg, %info );

  if ($self->verbose) {
    print {$self->outhdl} "Tracking: ".(defined $instap ? $instap : "<ORIGIN>")."\n";
  }

  # Store the pixel
  $tcs->aperture_name( $instap ) if defined $instap;

  # if we do not know the position return
  return if $info{autoTarget};

  # First get all the coordinate tags (SCIENCE won't be in there)
  my %tags = %{ $info{coordtags} };

  # check for reference position
  throw OMP::Error::TranslateFail("No reference position defined for position switch observation")
    if (!exists $tags{REFERENCE} && $info{switching_mode} =~ /pssw/);

  # Mandatory for scan/chop too
  throw OMP::Error::TranslateFail("No reference position defined for scan/chop observation (needed for CAL)")
    if (!exists $tags{REFERENCE} && $info{switching_mode} =~ /chop/
        && $info{mapping_mode} =~ /^scan/);


  # and augment with the SCIENCE tag
  # we only needs the Astro::Coords object in this case
  # unless we have an offset pixel
  # Note that OFFSETS are only propogated for non-SCIENCE positions
  $tags{SCIENCE} = { coords => $info{coords} };

  # if we have override velocity information we need to apply it now
  my @vover = $self->velOverride( %info );
  if (@vover) {
    print {$self->outhdl} "Overriding target velocity with (vel,vdef,vfr) = (",join(",",@vover),")\n" if $self->verbose;
    for my $t (keys %tags) {
      my $c = $tags{$t}{coords};
      if ($c->can( "set_vel_pars")) {
        $c->set_vel_pars( @vover );
      }
    }
  }

  # Create some BASE objects
  my %base;
  for my $t ( keys %tags ) {
    my $b = new JAC::OCS::Config::TCS::BASE();
    $b->tag( $t );
    $b->coords( $tags{$t}->{coords} );

    if (exists $tags{$t}->{OFFSET_DX} ||
        exists $tags{$t}->{OFFSET_DY} ) {
      my $off = new Astro::Coords::Offset( ($tags{$t}->{OFFSET_DX} || 0),
                                           ($tags{$t}->{OFFSET_DY} || 0));
      if (exists $tags{$t}->{OFFSET_SYSTEM}) {
        $off->system( $tags{$t}->{OFFSET_SYSTEM} );
      }
      $b->offset( $off );
    }

    # The OT can only specify tracking as the TRACKING system
    $b->tracking_system ( 'TRACKING' );

    $base{$t} = $b;
  }

  # Currently all REFERENCE positions have to be specified as offsets to SCIENCE to enable the TCS
  # to calculate doppler for the same reference position. Otherwise if the REFERENCE position is a
  # long way from SCIENCE the doppler correction can change such that atmospheric lines appear
  # in the spectrum.
  if (exists $base{REFERENCE}) {
    my $ref = $base{REFERENCE};

    # see if we have any offsets in reference
    if (!$ref->offset) {

      # absolute position, so calculate the TAN offset from SCIENCE
      # currently the offset will always be between J2000 coordinates.
      my $sci = $base{SCIENCE};
      my $scicoords = $sci->coords;
      my @offsets = $scicoords->distance( $ref->coords );

      # Now set the coords to SCIENCE and the offset
      $ref->coords( $scicoords );
      my $off = new Astro::Coords::Offset( @offsets, system => "J2000", projection => "TAN" );
      $ref->offset( $off );
      print {$self->outhdl} "Converting absolute REFERENCE position to offset from SCIENCE of (".
        sprintf("%.2f, %.2f", $offsets[0]->arcsec, $offsets[1]->arcsec). ") arcsec\n"
          if $self->verbose;

    }
  }


  $tcs->tags( %base );
}

=item B<tracking_offset>

Returns, if defined, an offset to BASE that has been defined for this
configuration. This is normally needed to correct the gridder so that
it can define the tangent point correctly (the gridder can not understand
offsets in any system other than pixel coordinates).

 $offset = $trans->tracking_offset( $cfg, %info );

Returns an C<Astro::Coords::Offset> object.

=cut

sub tracking_offset {
  my $self = shift;
  my $cfg = shift;
  my %info = @_;

  # Get the tcs_config
  my $tcs = $cfg->tcs;
  throw OMP::Error::FatalError('for some reason TCS configuration is not available. This can not happen')
    unless defined $tcs;

  # Get the name of the aperture name
  my $apname = $tcs->aperture_name;
  return undef unless defined $apname;

  # Get the instrument config
  my $inst = $cfg->instrument_setup;
  throw OMP::Error::FatalError('for some reason Instrument configuration is not available. This can not happen')
    unless defined $inst;

  # Convert this to an offset
  return $inst->receptor_offset( $apname );
}

=item B<observing_area>

Calculate the observing area parameters. Critically depends on
observing mode.

  $trans->observing_area( $tcs, %info );

First argument is C<JAC::OCS::Config::TCS> object.

=cut

sub observing_area {
  my $self = shift;
  my $tcs = shift;
  my %info = @_;

  my $obsmode = $info{mapping_mode};

  my $oa = new JAC::OCS::Config::TCS::obsArea();

  # Offset [needs work in unroll_obs to fix this for stare so that
  # we get a single configuration]. Jiggle needs multiple configurations.

  # There is only one position angle in an observing Area so the
  # offsets have to be in the same frame as the map if we are
  # defining a map area


  if ($obsmode eq 'scan') {

    # Need to know the frontend
    my $frontend = $self->ocs_frontend($info{instrument});
    throw OMP::Error::FatalError("Unable to determine appropriate frontend!")
      unless defined $frontend;

    # Map specification
    $oa->posang( new Astro::Coords::Angle( $info{MAP_PA}, units => 'deg'));
    $oa->maparea( HEIGHT => $info{MAP_HEIGHT},
                  WIDTH => $info{MAP_WIDTH});

    # The scan position angle is either supplied or automatic
    # if it is not supplied we currently have to give the TCS a hint
    my @scanpas;
    if (exists $info{SCAN_PA} && defined $info{SCAN_PA} && @{$info{SCAN_PA}}) {
      @scanpas = @{ $info{SCAN_PA} };
    } else {
      # Choice depends on pixel size. If sampling is equal in DX/DY or for an array
      # receiver then all 4 angles can be used. Else the scan is constrained to the X direction
      my @mults = (1,3); # 0, 2 aligns with height, 1, 3 aligns with width
      if ( $frontend =~ /harp/i || ($info{SCAN_VELOCITY}*$info{sampleTime} == $info{SCAN_DY}) ) {
        @mults = (0..3);
      }
      @scanpas = map { $info{MAP_PA} + ($_*90) } @mults;
    }
    # convert from deg to object
    @scanpas = map { new Astro::Coords::Angle( $_, units => 'deg', range => "2PI" ) } @scanpas;


    # Scan specification
    $oa->scan( VELOCITY => $info{SCAN_VELOCITY},
               DY => $info{SCAN_DY},
               SYSTEM => $info{SCAN_SYSTEM},
               PA => \@scanpas,
             );

    # N.B. The PTCS has now been modified to default to the
    # scan values below as per the DTD spec. so there is no need
    # to hardwire these directly into the translator.
    # REVERSAL => "YES",
    # TYPE => "TAN" 

    # Offset
    my $offx = ($info{OFFSET_DX} || 0);
    my $offy = ($info{OFFSET_DY} || 0);

    # Now rotate to the MAP_PA
    ($offx, $offy) = $self->PosAngRot( $offx, $offy, ( $info{OFFSET_PA} - $info{MAP_PA}));

    my $off = new Astro::Coords::Offset( $offx, $offy, projection => 'TAN',
                                         system => 'TRACKING' );

    $oa->offsets( $off );
  } else {
    # Just insert offsets, either as an offsets array or explicit
    my @offsets;
    if (exists $info{offsets}) {
      @offsets = @{ $info{offsets} };
    } else {
      @offsets = ( { OFFSET_DX => ($info{OFFSET_DX} || 0),
                     OFFSET_DY => ($info{OFFSET_DY} || 0),
                     OFFSET_PA => ($info{OFFSET_PA} || 0),
                   } );
    }

    my $refpa = ($offsets[0]->{OFFSET_PA} || 0);
    $oa->posang( new Astro::Coords::Angle( $refpa, units => 'deg' ) );

    # Rotate them all to the reference frame (this should be a no-op with
    # the current enforcement by the OT)
    @offsets = $self->align_offsets( $refpa, @offsets);

    # Now convert them to Astro::Coords::Offset objects
    my @out = map { new Astro::Coords::Offset( $_->{OFFSET_DX},
                                               $_->{OFFSET_DY},
                                               projection => 'TAN',
                                               system => 'TRACKING'
                                             )
                  } @offsets;

    # store them in the observing area
    $oa->offsets( @out );
  }

  # need to decide on public vs private
  $tcs->_setObsArea( $oa );
}

=item B<secondary_mirror>

Calculate the secondary mirror parameters. Critically depends on
switching mode.

  $trans->secondary_mirror( $tcs, %info );

First argument is C<JAC::OCS::Config::TCS> object.

=cut

sub secondary_mirror {
  my $self = shift;
  my $tcs = shift;
  my %info = @_;

  my $smu = new JAC::OCS::Config::TCS::Secondary();

  my $obsmode = $info{mapping_mode};
  my $sw_mode = $info{switching_mode};

  # Default to GROUP mode
  $smu->motion( "CONTINUOUS" );

  # Configure the chop parameters
  if ($sw_mode eq 'chop') {
    throw OMP::Error::TranslateFail("No chop defined for chopped observation!")
      unless (defined $info{CHOP_THROW} && defined $info{CHOP_PA} && 
              defined $info{CHOP_SYSTEM} );

    $smu->chop( THROW => $info{CHOP_THROW},
                PA => new Astro::Coords::Angle( $info{CHOP_PA}, units => 'deg' ),
                SYSTEM => $info{CHOP_SYSTEM},
              );
  }

  # Jiggling

  my $jig;

  if ($obsmode eq 'jiggle') {

    $jig = $self->jig_info( %info );

    # store the object
    $smu->jiggle( $jig );

  }

  # Since we need access to the jiggle pattern to calculate step time
  # we store what we have so it is available to the step_time object
  $tcs->_setSecondary( $smu );

  # Relative timing required if we are jiggling and chopping
  if ($smu->smu_mode() =~  /(jiggle_chop|chop_jiggle)/) {
    # First get the canonical RTS step time. This controls the time spent on each
    # jiggle position.
    my $rts = $self->step_time( $tcs, %info );

    # total number of points in pattern
    my $npts = $jig->npts;

    # Now the number of jiggles per chop position is dependent on the
    # maximum amount of time we want to spend per chop position and the constraint
    # that n_jigs_on must be divisible into the total number of jiggle positions.

    # Additionally, if we have been asked to use independent offs we have to 
    # do only one step per chop

    # Let's say this is maximum time between chops in seconds
    my $tmax_per_chop = OMP::Config->getData( 'acsis_translator.max_time_between_chops'.
                                              ($info{continuumMode} ? "_cont" :""));

    # Now calculate the number of steps in that time period
    my $maxsteps = int( $tmax_per_chop / $rts );

    if ($maxsteps == 0) {
      throw OMP::Error::TranslateFail("Maximum chop duration is shorter than RTS step time!\n");
    } elsif ($maxsteps == 1 || $info{separateOffs}) {
      # we can only do one step per chop
      $smu->timing( CHOPS_PER_JIG => 1 );

    } else {
      # we can fit in multiple jiggle positions per chop

      # now work out how many evenly spaced jiggles we can fit into this period
      my $njigs;
      if ($npts < $maxsteps) {
        $njigs = $npts;
      } else {
        # start at the maximum allowed and decrement until we get something that
        # divides exactly into the total number of points. Not a very elegant
        # approach
        $njigs = $maxsteps;

        $njigs-- while ($npts % $njigs != 0);
      }

      # the number of steps in the "off" position depends on the number
      # of steps we have just completed in the "on" (but half each side).
      my ($nsteps_total, $steps_per_off) = $self->calc_jiggle_times( $npts, $njigs );
      $smu->timing( N_JIGS_ON => $njigs,
                    N_CYC_OFF => $steps_per_off,
                  );
    }
  }

}


=item B<instrument_config>

Specify the instrument configuration.

 $trans->instrument_config( $cfg, %info );

=cut

sub instrument_config {
  my $self = shift;
  my $cfg = shift;
  my %info = @_;

  # The instrument config is fixed for a specific instrument
  # and is therefore a "wiring file"
  my $inst = lc($self->ocs_frontend($info{instrument}));
  throw OMP::Error::FatalError('No instrument defined so cannot configure!')
    unless defined $inst;
 
  # wiring file name
  my $file = File::Spec->catfile( $self->wiredir, 'frontend',
                                  "instrument_$inst.ent");
  throw OMP::Error::FatalError("$inst instrument configuration XML not found in $file !")
    unless -e $file;

  # Read it
  my $inst_cfg = new JAC::OCS::Config::Instrument( File => $file,
                                                   validation => 0,
                                                 );

  # tweak the wavelength
  $inst_cfg->wavelength( $info{wavelength} );

  $cfg->instrument_setup( $inst_cfg );

}

=item B<slew_config>

Configure the slew parameter. Requires the Config object to be mainly
complete such that the duration can be requested.

 $trans->slew_config( $cfg, %info );

Should be called after C<tcs_config>.

=cut

sub slew_config {
  my $self = shift;
  my $cfg = shift;
  my %info = @_;

  # get the tcs
  my $tcs = $cfg->tcs();
  throw OMP::Error::FatalError('for some reason TCS setup is not available. This can not happen') unless defined $tcs;

  # Get the duration
  my $dur = $cfg->duration();

  # always use track time
  $tcs->slew( TRACK_TIME => $dur );
}

=item B<header_config>

Add header items to configuration object. Reads a template header xml
file. Will replace TRANSLATOR header items with dynamic values.

 $trans->header_config( $cfg, %info );

=cut

sub header_config {
  my $self = shift;
  my $cfg = shift;
  my %info = @_;

  # work out whether we are looking at headers_acsis or headers_scuba2
  my $be = lc($self->backend);
  my $file = File::Spec->catfile( $self->wiredir, 'header',
                                  'headers_'.$be.'.ent' );
  my $hdr = new JAC::OCS::Config::Header( validation => 0,
                                          File => $file );

  # Get all the items that we are to be processed by the translator
  my @items = $hdr->item( sub { 
                            defined $_[0]->source
                              &&  $_[0]->source eq 'DERIVED'
                                && defined $_[0]->task
                                  && $_[0]->task eq 'TRANSLATOR'
                                } );

  # Set verbosity level and handles
  $OMP::Translator::JCMT::Header::VERBOSE = $self->verbose;
  $OMP::Translator::JCMT::Header::HANDLES = $self->outhdl;

  # Now invoke the methods to configure the headers
  my $pkg = "OMP::Translator::JCMT::Header";
  for my $i (@items) {
    my $method = $i->method;
    if ($pkg->can( $method ) ) {
      my $val = $pkg->$method( $cfg, %info );
      if (defined $val) {
        $i->value( $val );
        $i->source( undef );    # clear derived status
      } else {
        throw OMP::Error::FatalError( "Method $method for keyword ". $i->keyword ." resulted in an undefined value");
      }
    } else {
      throw OMP::Error::FatalError( "Method $method can not be invoked in package $pkg for header item ". $i->keyword);
    }
  }

  # clear global handles to allow the file to close at some point
  $OMP::Translator::JCMT::Header::HANDLES = undef;

  # Some observing modes have exclusion files.
  # First build the filename
  my $root;
  if ($info{obs_type} =~ /pointing|focus/) {
    $root = $info{obs_type};
  } else {
    $root = $info{observing_mode};
  }

  my $file = File::Spec->catfile( $self->wiredir, "header", $root . "_exclude");
  if (-e $file) {
    print {$self->outhdl} "Processing header exclusion file '$file'.\n" if $self->verbose;

    # this exclusion file has header cards that should be undeffed
    open (my $fh, '<', $file) || throw OMP::Error::FatalError("Error opening exclusion file '$file': $!");

    while (defined (my $line = <$fh>)) {
      # remove comments
      $line =~ s/\#.*//;
      # and trailing/leading whitespace
      $line =~ s/^\s*//;
      $line =~ s/\s*$//;
      next unless $line =~ /\w/;

      # ask for the header item
      my $item = $hdr->item( $line );

      if (defined $item) {
        # force undef
        $item->undefine;
      } else {
        print {$self->outhdl} "\tAsked to exclude header card '$line' but it is not part of the header\n";
      }

    }

  }

  $cfg->header( $hdr );

}

=item B<rts_config>

Configure the RTS

 $trans->rts_config( $cfg, %info );

=cut

sub rts_config {
  my $self = shift;
  my $cfg = shift;
  my %info = @_;

  # SCUBA-2 uses a single file
  my $root;
  if ($self->backend eq 'SCUBA2') {
    $root = "scuba2";
  } else {

    # Need observing mode
    my $obsmode = $info{observing_mode};

    # POL-ness is not relevant
    $obsmode =~ s/_pol//;

    # For the purposes of the RTS, the observing mode grid_chop (ie beam switch)
    # is actually a jiggle_chop
    $obsmode = "jiggle_chop" if $obsmode eq 'grid_chop';
    $obsmode = 'grid_pssw' if $obsmode eq 'jiggle_pssw';

    $root = $obsmode;
  }

  # the RTS information is read from a wiring file
  # indexed by observing mode
  my $file = File::Spec->catfile( $self->wiredir, 'rts',
                                  $root .".xml");
  throw OMP::Error::TranslateFail("Unable to find RTS wiring file $file")
    unless -e $file;

  my $rts = new JAC::OCS::Config::RTS( File => $file,
                                       validation => 0);

  $cfg->rts( $rts );

}


=item B<pol_config>

Configure the polarimeter.

  $trans->pol_config( $cfg, %info );

=cut

sub pol_config {
  my $self = shift;
  my $cfg = shift;
  my %info = @_;

  # see if we have a polarimeter
  return unless $info{pol};
  print {$self->outhdl} "Polarimeter observation:\n" if $self->verbose;

  # we currently only support grid/pssw observations
  throw OMP::Error::FatalError("Can only use ROVER in grid/pssw mode not '$info{observing_mode}'\n")
    unless $info{observing_mode} =~ /^grid_pssw/;

  # create a blank object
  my $pol = JAC::OCS::Config::POL->new();

  # what mode is this?
  if (exists $info{waveplate}) {
    my @pa = map { Astro::Coords::Angle->new( $_, units => 'deg') } @{$info{waveplate}};

    throw OMP::Error::TranslateFail("No angles found for step-and-integrate")
      unless @pa;

    $pol->discrete_angles( @pa );

    if ($self->verbose) {
      print {$self->outhdl} "\tStep and Integrate\n";
      print {$self->outhdl} "\t ". join(",",map {$_->degrees} @pa)."\n";
    }

  } else {

    # note that pol_spin
    throw OMP::Error::TranslateFail("No spin flag for continuous spin polarimeter observation")
      unless $self->is_pol_spin(%info);

    # Spin speed depends on the step time
    my $step_time = $self->step_time( $cfg, %info );

    # number of steps in a cycle controls the spin speed
    my $nsteps = OMP::Config->getData( 'acsis_translator.steps_per_cycle_pol' );
    my $speed = (360/$nsteps)/$step_time;

    $pol->spin_speed( $speed );
    if ($self->verbose) {
      print {$self->outhdl} "\t$nsteps spectra per cycle\n";
      print {$self->outhdl} "\tContinuous Spin: $speed deg/sec\n";
    }

  }

  # always use TRACKING (since we can and in step-and-integrate mode we need to make
  # sure that we return to the same place)
  $pol->system( "TRACKING" );

  $cfg->pol( $pol );
  return;
}

=item B<observing_mode>

Retrieves the observing mode from the OT observation summary
(not from the OCS configuration) and updates the supplied observation
summary.

 $trans->observing_mode( \%info );

The following keys are filled in:

=over 8

=item observing_mode

A single string describing the observing mode. One of
jiggle_freqsw, jiggle_chop, grid_pssw, scan_pssw.

Note that there is no explicit slow vs fast jiggle switch mode
set from this routine since more subsystems ignore the difference
than care about the difference.

Note also that POINTING or FOCUS are not observing modes in this sense.

If "inbeam" is set it will be appended. eg stare_spin_pol.

If switching mode is "self" or "none" it will not be included in
the observing mode definition.

=item mapping_mode

The underlying mapping mode. One of "jiggle", "scan" and "grid" for ACSIS.
"stare", "scan", "dream" for SCUBA-2.

=item switching_mode

The switching scheme. One of "freqsw", "chop", "pssw" and "none" for ACSIS.
This is a translated form of the input "switchingMode" parameter.
SCUBA-2 does not really need a switching mode (it's implicit in most
cases) but options are "none", "self", "spin" or "scan". The latter
two are for POL-2 and FTS-2 respectively.

=item obs_type

The type of observation. One of "science", "pointing", "focus",
"skydip" or "flatfield".

=item inbeam

Indicates if any additional equipment is to be placed in the beam
for this observation.

=back

=cut

sub observing_mode {
  my $self = shift;
  my $info = shift;

  my $otmode = $info->{MODE};
  my $swmode = $info->{switchingMode};

  # "inbeam" can be handled generically.
  # "obs_type" could be but the tests are already being performed.
  # Mapping and switch modes (Especially for non-science)
  # need special case

  my ($mapping_mode, $switching_mode, $obs_type)
    = $self->determine_map_and_switch_mode($otmode, $swmode);

  # inbeam
  my $inbeam;
  if ($info->{pol}) {
    $inbeam = 'pol';

    # tweak switching mode
    if ($self->is_pol_spin(%$info)) {
      if ($switching_mode =~ /^(none|self)$/) {
        $switching_mode = 'spin';
      } else {
        $switching_mode .= '_spin';
      }
    }
  }

  $info->{obs_type}       = $obs_type;
  $info->{switching_mode} = $switching_mode;
  $info->{mapping_mode}   = $mapping_mode;
  $info->{inbeam}        = $inbeam;

  # observing mode
  my @parts = ($mapping_mode);
  if ($switching_mode !~ /^(none|self)$/) {
    push(@parts, $switching_mode);
  }
  push(@parts, $inbeam) if $inbeam;

  $info->{observing_mode} = join("_",@parts);

  if ($self->verbose) {
    print {$self->outhdl} "\n";
    print {$self->outhdl} "Observing Mode Overview:\n";
    print {$self->outhdl} "\tObserving Mode: $info->{observing_mode}\n";
    print {$self->outhdl} "\tObservation Type: $info->{obs_type}\n";
    print {$self->outhdl} "\tMapping Mode: $info->{mapping_mode}\n";
    print {$self->outhdl} "\tSwitching Mode: $info->{switching_mode}\n";
    print {$self->outhdl} "\tIn Beam: $info->{inbeam}\n"
      if $info->{inbeam};
  }

  return;
}

=item B<is_pol_step_integ>

We are a polarimeter step and integrate observation.

 $ispol = $trans->is_pol_step_integ( %info );

=cut

sub is_pol_step_integ {
  my $self = shift;
  my %info = @_;
  if (exists $info{waveplate} && @{$info{waveplate}}) {
    return 1;
  }
  return;
}

=item B<is_pol_spin>

Is this a continuously spinning polarimeter observation?

  $spin = $trans->is_pol_spin( %info );

=cut

sub is_pol_spin {
  my $self = shift;
  my %info = @_;
  if (exists $info{pol_spin} && $info{pol_spin}) {
    return 1;
  }
  return;
}

=item B<ocs_frontend>

The name of the frontend from the viewpoint of the OCS. In general,
the number is dropped from the end of the instrument name such that
RXA3 becomes RXA.

  $fe = $trans->ocs_frontend( $ompfe );

Takes the OMP instrument name as argument. Returned string is upper cased.
Returns undef if the frontend is not recognized.

If the second argument is true, a version is returned that has the "x" 
in lower case

  $fe = $trans->ocs_frontend( $ompfe, 1);

=cut

sub ocs_frontend {
  my $self = shift;
  my $ompfe = uc( shift );
  my $lc = shift;

  my $answer;
  $answer = $FE_MAP{$ompfe} if exists $FE_MAP{$ompfe};
  $answer =~ tr|X|x| if (defined $answer && $lc);
  return $answer;
}

=item B<calc_jiggle_times>

Calculate the total number of steps in a pattern given a number of
points in the pattern and the size of a chunk and optionally the
number of steps in the off beam.

  $nsteps = $self->calc_jiggle_times( $njigpnts, $jigs_per_on, $steps_per_off ); 

Note the scalar context. If the number of steps per off is not given,
it is calculated and returned along with the total duration.

  ($nsteps, $steps_per_off ) = $self->calc_jiggle_times( $njigpnts, $jigs_per_on );

The steps_per_off calculation assumes sqrt(N) behaviour (shared off)
behaviour.

If only a number of jiggle points is supplied, it is assumed that
there are the same number of points in the off as in the on.

  $nsteps = $self->calc_jiggle_times( $njigpnts );

In scalar context, only returns the number of steps (even if the
number of offs were calculated).

=cut

sub calc_jiggle_times {
  my $self = shift;
  my ($njigpnts, $jigs_per_on, $steps_per_off ) = @_;

  # separate offs
  if (!defined $jigs_per_on) {
    # equal size pattern
    return ( 2 * $njigpnts );
  }

  # shared offs

  # number of chunks in pattern
  my $njig_chunks = $njigpnts / $jigs_per_on;

  my $had_steps = 1;
  if (!defined $steps_per_off) {
    $had_steps = 0;
    # the number of steps in the off is split equally around the on
    # so we half the sqrt(N)
    $steps_per_off = int( (sqrt($jigs_per_on) / 2 ) + 0.5 );
  }

  # calculate the number in the jiggle pattern. The factor of 2 is because the SMU
  # does the OFF repeated each side of the ON.
  my $nsteps = $njig_chunks * ( $jigs_per_on + ( 2 * $steps_per_off ) );

  if (wantarray()) {
    return ($nsteps, (!$had_steps ? $steps_per_off : () ));
  } else {
    return $nsteps;
  }
}

=item B<jig_info>

Return information relating to the selected jiggle pattern as a 
C<JCMT::SMU::Jiggle> object.

  $jig = $trans->jig_info( %info );

Throws an exception if Jiggle mode is defined but the pattern is missing
or if this method is called without jiggle mode selected.

=cut

sub jig_info {
  my $self = shift;
  my %info = @_;

  throw OMP::Error::TranslateFail("Jiggle pattern requested but no jiggle mode selected")
    unless $info{mapping_mode} =~ /jiggle/;

  throw OMP::Error::TranslateFail( "No jiggle pattern specified!" )
    unless exists $info{jigglePattern};

  # Look up table for patterns
  my %jigfiles = (
                  '1x1'  => 'smu_1x1.dat',
                  '3x3'  => 'smu_3x3.dat',
                  '4x4'  => 'smu_4x4.dat',
                  'HARP4'=> 'smu_harp4.dat',
                  'HARP5'=> 'smu_harp5.dat',
                  'HARP4_mc'=> 'smu_harp4_mc.dat',
                  'HARP5_mc'=> 'smu_harp5_mc.dat',
                  '5x5'  => 'smu_5x5.dat',
                  '7x7'  => 'smu_7x7.dat',
                  '9x9'  => 'smu_9x9.dat',
                  '5pt'  => 'smu_5point.dat',
                  '11x11'=> 'smu_11x11.dat',
                 );

  if (!exists $jigfiles{ $info{jigglePattern} }) {
    throw OMP::Error::TranslateFail("Jiggle requested but there is no pattern associated with pattern '$info{jigglePattern}'\n");
  }


  # obtin path to actual file
  my $file = File::Spec->catfile( $self->wiredir,'smu',$jigfiles{$info{jigglePattern}});

  # Need to read the pattern 
  my $jig = new JCMT::SMU::Jiggle( File => $file );

  # set the scale and other parameters
  # Note that the jiggle PA and system depend on whether we are using HARP
  # (or in fact the rotator).
  my $jscal = (defined $info{scaleFactor} ? $info{scaleFactor} : 1);
  $jig->scale( $jscal );

  # Get the instrument we are using
  my $inst = lc($self->ocs_frontend($info{instrument}));
  throw OMP::Error::FatalError('No instrument defined - needed to select calculate jiggle !')
    unless defined $inst;


  my ($jpa, $jsys);
  if ($inst =~ /HARP/i) {
    # Always jiggle in FPLANE with a PA=0 and rely on the rotator to rotate the receptors
    # on the sky
    $jpa = 0;
    $jsys = "FPLANE";

  } else {
    $jpa = $info{jigglePA} || 0;
    $jsys = $info{jiggleSystem} || 'TRACKING';
  }

  # and store them
  $jig->posang( new Astro::Coords::Angle( $jpa, units => 'deg') );
  $jig->system( $jsys );

  return $jig;
}

=item B<get_jiggle>

Convenience wrapper for obtaining the jiggle pattern information from the config object

  $jig_object = $self->get_jiggle( $cfg );

=cut

sub get_jiggle {
  my $self = shift;
  my $cfg = shift;

  # Need the number of points in the jiggle pattern
  my $tcs;
  if ($cfg->isa( "JAC::OCS::Config::TCS")) {
    $tcs = $cfg;
  } else {
    $tcs = $cfg->tcs;
    throw OMP::Error::FatalError('for some reason TCS setup is not available. This can not happen') unless defined $tcs;
  }

  # ... and secondary
  my $secondary = $tcs->getSecondary();
  throw OMP::Error::FatalError('for some reason Secondary configuration is not available. This can not happen') unless defined $secondary;

  # Get the full jigle parameters from the secondary object
  my $jig = $secondary->jiggle;

  return $jig;
}

=item B<nyquist>

Returns the Nyquist sampling value for this observation. Defined as lambda/2D

  $ny = $trans->nyquist( %info );

Returns an Astro::Coords::Angle object

=cut

sub nyquist {
  my $self = shift;
  my %info = @_;
  my $wav = $info{wavelength} * 1E-6; # microns to metres
  my $ny = $wav / ( 2 * DIAM );
  return new Astro::Coords::Angle( $ny, units => 'rad' );
}

=item B<align_offsets>

Given an set of offset hashes with OFFSET_DX, OFFSET_DY and OFFSET_PA
keys and a reference angle. Return a new hash with the offsets all in the
reference angle coordinate frame.

  @new = $trans->align_offsets( $refpa, @input );

=cut

sub align_offsets {
  my $self = shift;
  my $refpa = shift;
  my @input = @_;

  # A Map would work but a for is more redable
  my @out;
  for my $o (@input) {
    my ($x, $y) = $self->PosAngRot( $o->{OFFSET_DX}, $o->{OFFSET_DY},
                                    ( $refpa - $o->{OFFSET_PA})
                                  );
    push( @out, { OFFSET_DX => $x, OFFSET_DY => $y, OFFSET_PA => $refpa });
  }
  return @out;
}


=item B<tracking_receptor_or_subarray>

Returns the receptor ID that should be aligned with the supplied telescope
centre. Returns undef if no special receptor should be aligned with
the tracking centre.

  $recid = $trans->tracking_receptor_or_subarray( $cfg, %info );

This knowledge is especially important for single pixel pointing observations
and stare observartions with HARP where there is no central pixel.

If the "arrayCentred" switch is true, undef will be returned regardless of mode.

=cut

sub tracking_receptor_or_subarray {
  my $self = shift;
  my $cfg = shift;
  my %info = @_;

  # first check to see if offset is needed
  return if !$self->need_offset_tracking( $cfg, %info );

  # Get the config file options
  my @configs = OMP::Config->getData( "jcmt_translator.tracking_receptors_or_subarrays" );

  # Get the actual receptors in use for this observation
  my $inst = $cfg->instrument_setup;
  throw OMP::Error::FatalError('for some reason Instrument configuration is not available. This can not happen') 
    unless defined $inst;

  # Go through the preferred receptors looking for a match
  for my $test (@configs) {
    my $match = $inst->contains_id( $test );
    return $match if $match;
  }

  # If this is a 5pt pointing or a focus observation we need to choose the reference pixel
  # We have the choice of simply throwing an exception
  if (($info{obs_type} eq 'pointing') || $info{obs_type} eq 'focus') {
    return scalar($inst->reference_receptor) if defined $inst->reference_receptor;
  }

  # Still here? We have the choice of returning undef or choosing the
  # reference receptor. For now the consensus is to return undef.
  return;
}

=item B<calc_receptor_or_subarray_mask>

Generic routine to determine the frontend receptor or subarray mask
that should be used. The mask is determined by looking at the instrument
configuration. If a tracking receptor or subarray is required the mask
indicates that this item is NEEDed.  If disableNonTracking is set,
only the tracking receptor or subarray will be enabled.

  %mask = $trans->calc_receptor_or_subarray_mask($cfg, %info );

=cut

sub calc_receptor_or_subarray_mask {
  my $self = shift;
  my $cfg = shift;
  my %info = @_;

  # Need instrument information
  my $inst = $cfg->instrument_setup();
  throw OMP::Error::FatalError('for some reason instrument setup is not available. This can not happen') unless defined $inst;

  # Mask selection depends on observing mode but for now we can just
  # make sure that all available pixels are enabled
  # Set up a default MASK based on the Instrument XML
  my %receptors = $inst->receptors;

  my %mask;
  for my $id ( keys %receptors ) {
    my $status = $receptors{$id}{health};
    # Convert UNSTABLE to ON and OFF to ANY
    if ($status eq 'UNSTABLE') {
      $mask{$id} = 'ON';
    } elsif ($status eq 'OFF') {
      $mask{$id} = 'ANY';
    } else {
      $mask{$id} = $status;
    }
  }

  # If we have a specific tracking receptor in mind, make sure it is working
  my $instap = $self->tracking_receptor_or_subarray($cfg, %info );
  $mask{$instap} = "NEED" if defined $instap;

  # if we are ONLY meant to use this tracking receptor then we turn everything
  # else to OFF
  if (defined $instap && $info{disableNonTracking}) {
    for my $id ( keys %receptors ) {
      next if $id eq $instap;
      $mask{$id} = "OFF";
    }
  }

  return %mask;
}


=item B<_read_file>

Read a file and return the contents as a single string.

 $string = $trans->_read_file( $filename );

Not a method. Could probably use the slurp function.

=cut

sub _read_file {
  my $self = shift;
  my $file = shift;
  open (my $fh, '<', $file) or 
    throw OMP::Error::FatalError( "Unable to open file $file: $!");

  local $/ = undef;
  my $str = <$fh>;

  close($fh) or 
    throw OMP::Error::FatalError( "Unable to close file $file: $!");
  return $str;
}


=back

=head2 Header Configuration

Some header values are determined through the invocation of methods
specified in the header template XML. These methods are flagged by
using the DERIVED specifier with a task name of TRANSLATOR.

The following methods are in the OMP::Translator::JCMT::Header
namespace. They are all given the observation summary hash as argument
and the current Config object, and they return the value that should
be used in the header.

  $value = OMP::Translator::JCMT::Header->getProject( $cfg, %info );

An empty string will be recognized as a true UNDEF header value. Returning
undef is an error.

=cut

package OMP::Translator::JCMT::Header;

our $VERBOSE = 0;
our $HANDLES = undef;

sub getProject {
  my $class = shift;
  my $cfg = shift;
  my %info = @_;

  # if the project ID is not known, we need to use a ACSIS or SCUBA2 project
  if ( defined $info{PROJECTID} && $info{PROJECTID} ne 'UNKNOWN' ) {
    return $info{PROJECTID};
  } else {
    my $sem = OMP::General->determine_semester( tel => 'JCMT' );
    my $pid = "M$sem". "EC19";
    if ($VERBOSE) {
      print $HANDLES "!!! No Project ID assigned. Inserting E&C code: $pid !!!\n";
    }
    return $pid;
  }
  # should not get here
  return undef;
}

sub getMSBID {
  my $class = shift;
  my $cfg = shift;
  my %info = @_;
  return $info{MSBID};
}

sub getRemoteAgent {
  my $class = shift;
  my $cfg = shift;
  my %info = @_;

  if (exists $info{REMOTE_TRIGGER} && ref($info{REMOTE_TRIGGER}) eq 'HASH') {
    my $src = $info{REMOTE_TRIGGER}->{src};
    return (defined $src ? $src : "" );
  }
  return "";
}

sub getAgentID {
  my $class = shift;
  my $cfg = shift;
  my %info = @_;

  if (exists $info{REMOTE_TRIGGER} && ref($info{REMOTE_TRIGGER}) eq 'HASH') {
    my $id = $info{REMOTE_TRIGGER}->{id};
    return (defined $id ? $id : "" );
  }
  return "";
}

sub getScanPattern {
  my $class = shift;
  my $cfg = shift;
  my %info = @_;

  # get the TCS config
  my $tcs = $cfg->tcs;

  # and the observing area
  my $oa = $tcs->getObsArea;

  my $name = $oa->scan_pattern;
  return (defined $name ? $name : "" );
}

sub getStandard {
  my $class = shift;
  my $cfg = shift;
  my %info = @_;
  return $info{standard};
}

# For continuum we need the continuum recipe

sub getDRRecipe {
  my $class = shift;
  my $cfg = shift;
  my %info = @_;

  # This is where we insert an OT override once that override is possible
  # it will need to know which parameters to override

  # if we have been given recipes we should try to select from them
  if (exists $info{data_reduction}) {
    # see if the key is a subset of the mode
    my $found;
    my $firstmatch;
    for my $key (keys %{$info{data_reduction}}) {
      if ($info{MODE} =~ /$key/i) {
        my $recipe = $info{data_reduction}->{$key};
        if (!defined $found) {
          $found = $recipe;
          $firstmatch = $key;
        } else {
          # sanity check
          throw OMP::Error::TranslateFail("Strange error where mode $info{MODE} matched more than one DR key ('$key' and '$firstmatch')");
        }
      }
    }

    if (defined $found) {
      if ($info{continuumMode}) {
        # append continuum mode (if not already appended)
        $found .= "_CONTINUUM" unless $found =~ /_CONTINUUM$/;
      }
      if ($VERBOSE) {
        print $HANDLES "Using DR recipe $found provided by user\n";
      }
      return $found;
    }
  }

  # if there was no DR component we have to guess
  my $recipe;
  if ($info{MODE} =~ /Pointing/) {
    $recipe = 'REDUCE_POINTING';
  } elsif ($info{MODE} =~ /Focus/) {
    $recipe = 'REDUCE_FOCUS';
  } else {
    if ($info{continuumMode}) {
      $recipe = 'REDUCE_SCIENCE_CONTINUUM';
    } else {
      $recipe = 'REDUCE_SCIENCE';
    }
  }

  if ($VERBOSE) {
    print $HANDLES "Using DR recipe $recipe determined from context\n";
  }
  return $recipe;
}

sub getDRGroup {
  my $class = shift;
  my $cfg = shift;

  # Not quite sure how to handle this in the translator since there are no
  # hints from the OT and the DR is probably better at doing this.
  # by default return an empty string indicating undef
  return '';
}

# Need to get survey information from the TOML
# Derive it from the project ID

sub getSurveyName {
  my $class = shift;
  my $cfg = shift;
  my %info = @_;
  my $project = $class->getProject( $cfg, %info );

  if ($project =~ /^MJLS([A-Z]+)\d+$/i) {
    my $short = $1;
    if ($short eq 'G') {
      return "GBS";
    } elsif ($short eq 'A') {
      return "SASSY";
    } elsif ($short eq 'D') {
      return "DDS";
    } elsif ($short eq 'C') {
      return "CLS";
    } elsif ($short eq 'S') {
      return "SLS";
    } elsif ($short eq 'N') {
      return "NGS";
    } elsif ($short eq 'J') {
      return "JPS"; 
    } else {
      throw OMP::Error::TranslateFail( "Unrecognized SURVEY code: '$project' -> '$short'" );
    }
  }
  return '';
}

sub getSurveyID {
  return '';
}

sub getNumIntegrations {
  my $class = shift;
  my $cfg = shift;
  my %info = @_;
  return $info{nintegrations};
}

sub getNumMeasurements {
  my $class = shift;
  my $cfg = shift;
  my %info = @_;

  # do not know what this really means. It may mean the scuba definition
  # Assume this means the number of discrete hardware moves
  if ($info{MODE} =~ /Focus/) {
    return $info{focusStep};
  } else {
    return 1;
  }
}

# Retrieve the molecule associated with the first spectral window
sub getMolecule {
  my $class = shift;
  my $cfg = shift;
  my %info = @_;
  my $freq = $info{freqconfig}->{subsystems};
  my $s = $freq->[0];
  return $s->{species};
}

# Retrieve the transition associated with the first spectral window
sub getTransition {
  my $class = shift;
  my $cfg = shift;
  my %info = @_;
  my $freq = $info{freqconfig}->{subsystems};
  my $s = $freq->[0];
  return $s->{transition};
}

# Receptor aligned with tracking centre
sub getInstAper {
  my $class = shift;
  my $cfg = shift;

  my $tcs = $cfg->tcs;
  throw OMP::Error::FatalError('for some reason TCS configuration is not available. This can not happen')
    unless defined $tcs;
  my $ap = $tcs->aperture_name;
  return ( defined $ap ? $ap : "" );
}

# backwards compatibility
sub getTrkRecep {
  my $self = shift;
  return $self->getInstAper( @_ );
}

# Get the X and Y aperture offsets
sub _getInstapXY {
  my $class = shift;
  my $cfg = shift;
  my $ap = $class->getTrkRecep( $cfg );
  if ($ap) {
    my $inst = $cfg->instrument_setup;
    throw OMP::Error::FatalError('for some reason Instrument configuration is not available. This can not happen') 
      unless defined $inst;

    my %rec = $inst->receptor( $ap );
    throw OMP::Error::FatalError("Thought there was an instrument aperture ($ap) but it is unknown to the instrument")
      if (!keys %rec);

    return @{$rec{xypos}};
  }
  return (0.0,0.0);
}

sub getInstapX {
  my $class = shift;
  my $cfg = shift;
  return ($class->_getInstapXY( $cfg ) )[0];
}

sub getInstapY {
  my $class = shift;
  my $cfg = shift;
  return ($class->_getInstapXY( $cfg ) )[1];
}

# Reference receptor
sub getRefRecep {
  my $class = shift;
  my $cfg = shift;

  my $inst = $cfg->instrument_setup;
  throw OMP::Error::FatalError('for some reason Instrument configuration is not available. This can not happen') 
    unless defined $inst;
  return scalar $inst->reference_receptor;
}

# Reference position as sexagesimal string or offset
sub getReferenceRA {
  my $class = shift;
  my $cfg = shift;

  # Get the TCS
  my $tcs = $cfg->tcs;

  my %allpos = $tcs->getAllTargetInfo;

  # check if SCIENCE == REFERENCE
  if (exists $allpos{REFERENCE}) {

    # Assume that for now since the OT enforces either an absolute position
    # or one relative to BASE as an offset that if we have an offset people
    # are offsetting and if we have just coords that we are using that explicitly
    my $refpos = $allpos{REFERENCE}->coords;
    my $offset = $allpos{REFERENCE}->offset;

    if (defined $offset) {
      my @off = $offset->offsets;
      return "[OFFSET] ". $off[0]->arcsec . " [".$offset->system."]";
    } else {
      if ($refpos->can("ra2000")) {
        return "". $refpos->ra2000;
      } elsif ($refpos->type eq "AZEL") {
        return $refpos->az . " (AZ)";
      }
    }
  }
  # Want this to be an undef header
  return "";
}

# Reference position as sexagesimal string or offset
sub getReferenceDec {
  my $class = shift;
  my $cfg = shift;

  # Get the TCS
  my $tcs = $cfg->tcs;

  my %allpos = $tcs->getAllTargetInfo;

  # check if SCIENCE == REFERENCE
  if (exists $allpos{REFERENCE}) {

    # Assume that for now since the OT enforces either an absolute position
    # or one relative to BASE as an offset that if we have an offset people
    # are offsetting and if we have just coords that we are using that explicitly
    my $refpos = $allpos{REFERENCE}->coords;
    my $offset = $allpos{REFERENCE}->offset;

    if (defined $offset) {
      my @off = $offset->offsets;
      return "[OFFSET] ". $off[1]->arcsec . " [".$offset->system."]";
    } else {
      if ($refpos->can("dec2000")) {
        return "". $refpos->dec2000;
      } elsif ($refpos->type eq "AZEL") {
        return $refpos->el ." (EL)";
      }
    }
  }
  # Want this to be an undef header
  return "";
}


# For jiggle: This is the number of nod sets required to build up the pattern
#             ie  Total number of points / N_JIG_ON

# For grid: returns the number of points in the grid

# For scan: Estimate at the number of scans

sub getNumExposures {
  my $class = shift;
  my $cfg = shift;

  warn "******** Do not calculate Number of exposures correctly\n"
    if OMP::Translator::JCMT->verbose;;
  return 1;
}

# Reduce process recipe requires access to the file name used to read
# the recipe This should be stored in the Cfg object

sub getRPRecipe {
  my $class = shift;
  my $cfg = shift;

  # Get the acsis config
  my $acsis = $cfg->acsis;
  if (defined $acsis) {
    my $red = $acsis->red_config_list;
    if (defined $red) {
      my $file = $red->filename;
      if (defined $file) {
        # just give file name, not path
        return File::Basename::basename($file);
      }
    }
  }
  return '';
}


sub getOCSCFG {
  # this gets written automatically by the OCS Config classes
  return '';
}

sub getBinning {
  my $class = shift;
  my $cfg = shift;
  my %info = @_;

  my $dr = $info{data_reduction};
  if (defined $dr) {
    if (exists $dr->{spectral_binning}) {
      return $dr->{spectral_binning};
    }
  }
  return 1;
}

sub getNumMixers {
  my $class = shift;
  my $cfg = shift;

  # Get the frontend
  my $fe = $cfg->frontend;
  throw OMP::Error::TranslateFail("Asked to determine number of mixers but no Frontend has been specified\n") unless defined $fe;

  my %mask = $fe->mask;
  my $count;
  for my $state (values %mask) {
    $count++ if ($state eq 'ON' || $state eq 'NEED');
  }
  return $count;
}

=head1 NOTES

Usually called indirectly from L<OMP::Translator|OMP::Translator>.

=head1 CONFIGURATION XML

The format of the configuration XML is outlined in JAC document
OCS/ICD/001.

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

Copyright (C) 2007-2008 Science and Technology Facilities Council.
Copyright 2003-2007 Particle Physics and Astronomy Research Council.
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

1;
