package OMP::Translator::ACSIS;

=head1 NAME

OMP::Translator::ACSIS - translate ACSIS heterodyne observations to Configure XML

=head1 SYNOPSIS

  use OMP::Translator::ACSIS;
  $config = OMP::Translator::ACSIS->translate( $sp );

=head1 DESCRIPTION

Convert ACSIS MSB into a form suitable for observing. This means
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
use List::Util qw/ min max /;
use Scalar::Util qw/ blessed /;
use POSIX qw/ ceil /;
use Math::Trig / rad2deg /;

use JCMT::ACSIS::HWMap;
use JCMT::SMU::Jiggle;
use JAC::OCS::Config;

use OMP::Config;
use OMP::Error;
use OMP::General;

use base qw/ OMP::Translator /;

# Default directory for writing configs
our $TRANS_DIR = OMP::Config->getData( 'acsis_translator.transdir');

# Location of wiring xml
our $WIRE_DIR = OMP::Config->getData( 'acsis_translator.wiredir' );

# Debugging messages
our $DEBUG = 0;

# Version number
our $VERSION = sprintf("%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/);

# Mapping from OMP to OCS frontend names
our %FE_MAP = (
	       RXA3 => 'RXA',
	       RXWC => 'RXW',
	       RXWD => 'RXW',
	       RXB3 => 'RXB',
               'RXHARP-B' => 'HARPB'
	      );

# Lookup table to calculate the LO2 frequencies.
# Indexed simply by subband bandwidth
our %BWMAP = (
	      '250MHz' => {
			   # Parking frequency, channel 1 (Hz)
			   f_park => 2.5E9,
		       },
	      '1GHz' => {
			 # Parking frequency, channel 1 (to Hz)
			 f_park => 2.0E9,
			},
	     );

# This is the gridder/reducer layout selection
my %ACSIS_Layouts = (
		    RXA => 's1r1g1',
		    RXB => 's2r2g1',
		    RXW => 's2r2g2',
		    HARPB => 's8r8g1',
		    HARPB_raster_pssw => 's8r8g8',
		   );

# LO2 synthesizer step, hard-wired
our $LO2_INCR = 0.2E6;


# Telescope diameter in metres
use constant DIAM => 15;

=head1 METHODS

=over 4

=item B<translate>

Converts a single MSB object to one or many ACSIS Configs.
It is assumed that this MSB will refer to an ACSIS observation
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
  print "OTVERS: $otver \n" if $DEBUG;

  # Correct Stare observations such that multiple offsets are
  # combined
  # Note that there may be a requirement to convert non-regular offset
  # patterns into individual observations rather than having a very sparse
  # but large grid
  $self->correct_offsets( $msb, "Stare" );

  # Now unroll the MSB into constituent observations details
  my @configs;
  for my $obs ($msb->unroll_obs) {

    # Translate observing mode information to internal form
    $self->observing_mode( $obs );

    # We need to patch up DAS observations if we are attempting to translate
    # them as ACSIS observations
    $self->upgrade_das_specification( $obs );

    # We need to patch up POINTING and FOCUS observations so that they have
    # the correct jiggle parameters
    $self->handle_special_modes( $obs );

    # Create blank configuration
    my $cfg = new JAC::OCS::Config;

    # Set verbosity and debug level
    $cfg->verbose( $self->verbose );
    $cfg->debug( $self->debug );

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

    # FRONTEND_CONFIG
    $self->fe_config( $cfg, %$obs );

    # ACSIS_CONFIG
    # SCUBA-2 translator will need to inherit some of these methods
    $self->acsis_config( $cfg, %$obs );

    # HEADER_CONFIG
    $self->header_config( $cfg, %$obs );

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

    last;
  }


  # return the config objects
  return @configs;
}

=item B<debug>

Method to enable and disable global debugging state.

  OMP::Translator::ACSIS->debug( 1 );

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

=item B<verbose>

Method to enable and disable global verbosity state.

  OMP::Translator::ACSIS->verbose( 1 );

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

  OMP::Translator::ACSIS->transdir( $dir );

=cut

sub transdir {
  my $class = shift;
  if (@_) {
    my $dir = shift;
    $TRANS_DIR = $dir;
  }
  return $TRANS_DIR;
}

=item B<upgrade_das_specification>

In order for DAS observations to be translated as ACSIS observations we
need to fill in missing information and translate DAS bandwidth settings
to ACSIS equivalents.

  $cfg->upgrade_das_specification( \%obs );

=cut

sub upgrade_das_specification {
  my $self = shift;
  my $info = shift;

  return if $info->{freqconfig}->{beName} eq 'acsis';

  # Band width mode must translate to ACSIS equivalent
  my %bwmode = (
		# always map 125MHz to 250MHz
		125 => {
			bw => 2.5E8,
			overlap => 0.0,
			channels => 8192,
		       },
		250 => {
			bw => 2.5E8,
			overlap => 0.0,
			channels => 8192,
		       },
		500 => {
			bw => 4.8E8,
			overlap => 1.0E7,
			channels => 7864,
		       },
		760 => {
			bw => 9.5E8,
			overlap => 5.0E7,
			channels => 1945,
		       },
		920 => {
			bw => 9.5E8,
			overlap => 5.0E7,
			channels => 1945,
		       },
		1840 => {
			 bw => 1.9E9,
			 overlap => 5.0E7,
			 channels => 1945,
			},
		);

  # need to add the following
  # freqconfig => overlap
  #               IF

  my $freq = $info->{freqconfig};

  # should only be one subsystem but non-fatal
  for my $ss (@{ $freq->{subsystems} }) {
    # force 4GHz
    $ss->{if} = 4.0E9;

    # calculate the corresponding bw key
    my $bwkey = $ss->{bw} / 1.0E6;

    throw OMP::Error::TranslateFail( "DAS Bandwidth mode not supported by ACSIS translator" ) unless exists $bwmode{$bwkey};

    for my $k (qw/ bw overlap channels / ) {
      $ss->{$k} = $bwmode{$bwkey}->{$k};
    }

  }

  # need to trap DAS special modes
  throw OMP::Error::TranslateFail("DAS special modes not supported by ACSIS translator" ) if defined $freq->{configuration};


  # Need to shift the velocity from freqconfig to coordtags
  my $vfr = $freq->{velocityFrame};
  my $vdef = $freq->{velocityDefinition};
  my $vel = $freq->{velocity};

  $info->{coords}->set_vel_pars( $vel, $vdef, $vfr )
    if $info->{coords}->can( "set_vel_pars" );

  for my $t (keys %{ $info->{coordtags} } ) {
    $info->{coordtags}->{$t}->{coords}->set_vel_pars( $vel, $vdef, $vfr )
      if $info->{coordtags}->{$t}->{coords}->can("set_vel_pars");
  }

  return;
}

=item B<handle_special_modes>

Special modes such as POINTING or FOCUS are normal observations that
are modified to do something in addition to normal behaviour. For a
pointing this simply means fitting an offset.

  $cfg->handle_special_modes( \%obs );

Since the Observing Tool is setup such that pointing and focus
observations do not necessarily inherit observing parameters from the
enclosing observation and they definitely do not include a
specification on chopping scheme.

=cut

sub handle_special_modes {
  my $self = shift;
  my $info = shift;

  # The trick is to fill in the blanks

  # A pointing should translate to
  #  - Jiggle chop
  #  - 5 point or 9x9 jiggle pattern
  #  - 60 arcsec AZ chop

  # Some things depend on the frontend
  my $frontend = $self->ocs_frontend($info->{instrument});
  throw OMP::Error::FatalError("Unable to determine appropriate frontend!")
    unless defined $frontend;

  # Pointing will have been translated into chop already by the
  # observing_mode() method.

  if ($info->{obs_type} eq 'pointing') {
    $info->{CHOP_PA} = 90;
    $info->{CHOP_THROW} = 60;
    $info->{CHOP_SYSTEM} = 'AZEL';
    $info->{secsPerJiggle} = 5;

    if ($frontend eq 'HARPB') {
      $info->{jigglePattern} = 'HARP';
      $info->{scaleFactor} = 1; # HARP jiggle pattern uses arcsec
      $info->{jiggleSystem} = 'FPLANE';
    } else {
      $info->{jigglePattern} = '5x5';
      $info->{jiggleSystem} = 'AZEL';

      # The scale factor should be the larger of half beam or planet limb
      my $half_beam = $self->nyquist( %$info )->arcsec;
      my $plan_rad = 0;
      if ($info->{coords}->type eq 'PLANET') {
	# Currently need to force an apparent ra/dec calculation to get the diameter
	my @discard = $info->{coords}->apparent();
	$plan_rad = $info->{coords}->diam->arcsec / 2;
      }

      $info->{scaleFactor} = max( $half_beam, $plan_rad );
    }

    if ($self->verbose) {
      print "Determining POINTING parameters...\n";
      print "\tJiggle Pattern: $info->{jigglePattern} ($info->{jiggleSystem})\n";
      print "\tSMU Scale factor: $info->{scaleFactor} arcsec\n";
      print "\tChop parameters: $info->{CHOP_THROW} arcsec @ $info->{CHOP_PA} deg ($info->{CHOP_SYSTEM})\n";
      print "\tSeconds per jiggle position: $info->{secsPerJiggle}\n";
    }

    # Kill baseline removal
    if (exists $info->{data_reduction}) {
      my %dr = %{ $info->{data_reduction} };
      delete $dr{baseline};
      $info->{data_reduction} = \%dr;
    }

  } elsif ($info->{obs_type} eq 'focus') {
    # Focus is a 60 arcsec AZ chop observation
    $info->{CHOP_PA} = 90;
    $info->{CHOP_THROW} = 60;
    $info->{CHOP_SYSTEM} = 'AZEL';
    $info->{secsPerCycle} = 5;

    # Kill baseline removal
    if (exists $info->{data_reduction}) {
      my %dr = %{ $info->{data_reduction} };
      delete $dr{baseline};
      $info->{data_reduction} = \%dr;
    }

  } elsif ($info->{mapping_mode} eq 'jiggle' && $frontend eq 'HARPB') {
    # If HARP is the jiggle pattern then we need to set scaleFactor to 1
    if ($info->{jigglePattern} eq 'HARP') {
      $info->{scaleFactor} = 1; # HARP pattern is fully sampled
      $info->{jiggleSystem} = "FPLANE"; # in focal plane coordinates...
    }
  }

  return;
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
  my $refpix = $self->tracking_receptor( $cfg, %info );

  if ($self->verbose) {
    print "Tracking Receptor: ".(defined $refpix ? $refpix : "<ORIGIN>")."\n";
  }

  # Store the pixel
  $tcs->aperture_name( $refpix ) if defined $refpix;

  # if we do not know the position return
  return if $info{autoTarget};

  # First get all the coordinate tags
  my %tags = %{ $info{coordtags} };

  # check for reference position
  throw OMP::Error::TranslateFail("No reference position defined for position switch observation")
    if (!exists $tags{REFERENCE} && $info{switching_mode} =~ /pssw/);

  # and augment with the SCIENCE tag
  # we only needs the Astro::Coords object in this case
  # unless we have an offset pixel
  # Note that OFFSETS are only propogated for non-SCIENCE positions
  $tags{SCIENCE} = { coords => $info{coords} };

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


  if ($obsmode eq 'raster') {

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
      # For single pixel just align with the map - else need arctan(0.25)
      my $adjpa = 0.0;
      if ($frontend eq 'HARPB') {
	$adjpa = rad2deg(atan2(1,4));
      }
      @scanpas = map { $info{MAP_PA} + $adjpa + ($_*90) } (0..3);
    }
    # convert from deg to object
    @scanpas = map { new Astro::Coords::Angle( $_, units => 'deg' ) } @scanpas;


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
  $smu->motion( "GROUP" );

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

  # Relative timing required if we are jiggling and chopping
  if ($smu->smu_mode() eq 'jiggle_chop') {
    # First get the canonical RTS step time. This controls the time spent on each
    # jiggle position.
    my $rts = $self->step_time( %info );

    # total number of points in pattern
    my $npts = $jig->npts;

    # Now the number of jiggles per chop position is dependent on the
    # maximum amount of time we want to spend per chop position and the constraint
    # that n_jigs_on must be divisible into the total number of jiggle positions.

    # Let's say this is maximum time between chops in seconds
    my $tmax_per_chop = OMP::Config->getData( 'acsis_translator.max_time_between_chops');

    # Now calculate the number of steps in that time period
    my $maxsteps = int( $tmax_per_chop / $rts );

    if ($maxsteps == 0) {
      throw OMP::Error::TranslateFail("Maximum chop duration is shorter than RTS step time!\n");
    } elsif ($maxsteps == 1) {
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
      $smu->timing( N_JIGS_ON => $njigs,
		    N_CYC_OFF => int( (sqrt($njigs)/2) + 0.5 ),
		  );
   }
  }

  $tcs->_setSecondary( $smu );
}

=item B<fe_config>

Create the frontend configuration.

 $trans->fe_config( $cfg, %info );

=cut

sub fe_config {
  my $self = shift;
  my $cfg = shift;
  my %info = @_;

  my $fe = new JAC::OCS::Config::Frontend();

  # Get the basic frontend setup from the freqconfig key
  my %fc = %{ $info{freqconfig} };

  # Easy setup
  # FE XML expects rest frequency in GHz
  $fe->rest_frequency( $fc{restFrequency}/1e9 );
  $fe->sb_mode( $fc{sideBandMode} );

  # How to handle 'best'?
  my $sb = ( $fc{sideBand} =~  /BEST/i ? 'USB' : $fc{sideBand} );
  $fe->sideband( $sb );

  # doppler mode
  $fe->doppler( ELEC_TUNING => 'DISCRETE', MECH_TUNING => 'ONCE' );

  # Frequency offset
  my $freq_off = 0.0;
  if ($info{switching_mode} =~ /freqsw/ && defined $info{frequencyOffset}) {
    $freq_off = $info{frequencyOffset};
  }
  $fe->freq_off_scale( $freq_off );

  # Mask selection depends on observing mode but for now we can just
  # make sure that all available pixels are enabled
  my $inst = $cfg->instrument_setup();
  throw OMP::Error::FatalError('for some reason instrument setup is not available. This can not happen') unless defined $inst;

  # store the frontend name in the Frontend config so that we can get the task name
  $fe->frontend( $inst->name );

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
  my $trackrec = $self->tracking_receptor($cfg, %info );
  $mask{$trackrec} = "NEED" if defined $trackrec;

  # Store the mask
  $fe->mask( %mask );

  # store the configuration
  $cfg->frontend( $fe );
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
  my $file = File::Spec->catfile( $WIRE_DIR, 'frontend',
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

=item B<acsis_config>

Configure ACSIS.

  $trans->acsis_config( $cfg, %info );

=cut

sub acsis_config {
  my $self = shift;
  my $cfg = shift;
  my %info = @_;

  my $acsis = new JAC::OCS::Config::ACSIS();

  # Store it in the object
  $cfg->acsis( $acsis );

  # Now configure the individual ACSIS components
  $self->line_list( $cfg, %info );
  $self->spw_list( $cfg, %info );
  $self->correlator( $cfg, %info );
  $self->acsisdr_recipe( $cfg, %info );
  $self->cubes( $cfg, %info );
  $self->interface_list( $cfg, %info );
  $self->acsis_layout( $cfg, %info );
  $self->rtd_config( $cfg, %info );

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

=item B<rotator_config>

Configure the rotator parameter. Requires the Config object to at least have a TCS and Instrument configuration defined.

 $trans->rotator_config( $cfg, %info );

Only relevant for instruments that are on the Nasmyth platform.

=cut

sub rotator_config {
  my $self = shift;
  my $cfg = shift;
  my %info = @_;

  # Get the instrument configuration
  my $inst = $cfg->instrument_setup();
  throw OMP::Error::FatalError('for some reason instrument setup is not available. This can not happen') unless defined $inst;

  return if (defined $inst->focal_station && 
	     $inst->focal_station !~ /NASMYTH/);

  # get the tcs
  my $tcs = $cfg->tcs();
  throw OMP::Error::FatalError('for some reason TCS setup is not available. This can not happen') unless defined $tcs;

  # Need to find out the coordinate frame of the map
  # This will either be AZEL or TRACKING - choose the result from any cube
  my %cubes = $self->getCubeInfo( $cfg );
  my @cubs = values( %cubes );

  # Need to get the map position angle
  my $pa = $cubs[0]->posang;
  $pa = new Astro::Coords::Angle( 0, units => 'radians' ) unless defined $pa;

  # but we do have 90 deg symmetry in all our maps
  my @pas = map { new Astro::Coords::Angle( $pa->degrees + ($_ * 90), units => 'degrees') } (0..3);


  # do not know enough about ROTATOR behaviour yet
  $tcs->rotator( SLEW_OPTION => 'TRACK_TIME',
		 SYSTEM => $cubs[0]->tcs_coord,
		 PA => \@pas,
	       );
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

  my $file = File::Spec->catfile( $WIRE_DIR, 'header','headers.ent' );
  my $hdr = new JAC::OCS::Config::Header( validation => 0,
					  File => $file );

  # Get all the items that we are to be processed by the translator
  my @items = $hdr->item( sub { 
			    defined $_[0]->source
			     &&  $_[0]->source eq 'DERIVED'
			       && defined $_[0]->task
				 && $_[0]->task eq 'TRANSLATOR'
				} );

  # Now invoke the methods to configure the headers
  my $pkg = "OMP::Translator::ACSIS::Header";
  for my $i (@items) {
    my $method = $i->method;
    if ($pkg->can( $method ) ) {
      my $val = $pkg->$method( $cfg, %info );
      if (defined $val) {
	$i->value( $val );
	$i->source( undef ); # clear derived status
      } else {
	throw OMP::Error::FatalError( "Method $method for keyword ". $i->keyword ." resulted in an undefined value");
      }
    } else {
      throw OMP::Error::FatalError( "Method $method can not be invoked in package $pkg for header item ". $i->keyword);
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

  # Need observing mode
  my $obsmode = $info{observing_mode};

  # For the purposes of the RTS, the observing mode grid_chop (ie beam switch)
  # is actually a jiggle_chop
  $obsmode = "jiggle_chop" if $obsmode eq 'grid_chop';

  # the RTS information is read from a wiring file
  # indexed by observing mode
  my $file = File::Spec->catfile( $WIRE_DIR, 'rts',
				  $obsmode .".xml");
  throw OMP::Error::TranslateFail("Unable to find RTS wiring file $file")
    unless -e $file;

  my $rts = new JAC::OCS::Config::RTS( File => $file,
				       validation => 0);

  $cfg->rts( $rts );

}

=item B<jos_config>

Configure the JOS.

  $trans->jos_config( $cfg, %info );

=cut

sub jos_config {
  my $self = shift;
  my $cfg = shift;
  my %info = @_;

  my $jos = new JAC::OCS::Config::JOS();

  # need to determine recipe name
  # use hash indexed by observing mode
  my %JOSREC = (
		focus       => 'focus',
		pointing    => 'pointing',
		jiggle_freqsw => ( $self->is_fast_freqsw(%info) ? 'fast_jiggle_fsw' : 'slow_jiggle_fsw'),
		jiggle_chop => 'jiggle_chop',
		grid_chop   => 'jiggle_chop',
		grid_pssw   => 'grid_pssw',
		raster_pssw => 'raster_pssw',
	       );
  if (exists $JOSREC{$info{obs_type}}) {
    $jos->recipe( $JOSREC{$info{obs_type}} );
  } elsif (exists $JOSREC{$info{observing_mode}}) {
    $jos->recipe( $JOSREC{$info{observing_mode}} );
  } else {
    throw OMP::Error::TranslateFail( "Unable to determine jos recipe from observing mode '$info{observing_mode}'");
  }

  # The number of cycles is simply the number of requested integrations
  $jos->num_cycles( defined $info{nintegrations}  ? $info{nintegrations} :  1);

  # The step time is always present
  $jos->step_time( $self->step_time( %info ) );

  # N_CALSAMPLES depends entirely on the step time and the time from
  # the config file. Number of cal samples. This is hard-wired in
  # seconds but in units of STEP_TIME
  my $caltime = OMP::Config->getData( 'acsis_translator.cal_time' );

  # if caltime is less than step time (eg raster) we still need to do at
  # least 1 cal
  $jos->n_calsamples( max(1, OMP::General::nint( $caltime / $jos->step_time) ) );

  # Now specify the maximum time between cals in steps
  my $calgap = OMP::Config->getData( 'acsis_translator.time_between_cal' );
  $jos->steps_per_cal( max(1, OMP::General::nint( $calgap / $jos->step_time ) ) );

  # Now calculate the maximum time between refs in steps
  my $refgap = OMP::Config->getData( 'acsis_translator.time_between_ref' );
  $jos->steps_per_ref( max( 1, OMP::General::nint( $refgap / $jos->step_time ) ) );

  # Now parameters depends on that recipe name

  # Raster

  if ($info{observing_mode} =~ /raster/) {

    # Start at row 1 by default
    $jos->start_row( 1 );

    # Number of ref samples is the sqrt of the longest row
    # for the first off only. All subsequent refs are calculated by
    # the JOS dynamically

    # we need the cube dimensions
    my %cubes = $self->getCubeInfo( $cfg );

    # need the longest row from all the cubes.
    # For the moment, I don't expect the cubes to be different sizes...
    # Be conservative and choose a diagonal
    my $rlen = 0;
    for my $c (keys %cubes) {
      # number of pixels
      my ($nx, $ny) = $cubes{$c}->npix;

      # size per pixel
      my ($dx,$dy) = map { $_->arcsec } $cubes{$c}->pixsize;

      # length of row in arcsec
      $rlen = max( $rlen, sqrt( ($nx*$dx)**2 + ($ny*$dy)**2 ) );
    }

    # Now convert that to a time
    my $rtime = $rlen / $info{SCAN_VELOCITY};

    # Now convert to steps
    my $nrefs = max( 1, int( 0.5 + sqrt( $rtime / $jos->step_time ) ));

    $jos->n_refsamples( $nrefs );

    # JOS_MIN ??
    $jos->jos_min(1);

    if ($self->verbose) {
      print "Raster JOS parameters:\n";
      print "\tLongest row time (diagonal): $rtime sec\n";
      print "\tNumber of ref samples for first off (estimated): $nrefs\n";
      print "\tStep time for sample: ". $jos->step_time . " sec\n";
    }


  } elsif ($info{observing_mode} =~ /jiggle_chop/) {

    # Jiggle

    # We need to calculate the number of full patterns per nod and the number
    # of nod sets. A nod set is a full A B B A combination so there are at
    # least 4 nods.

    # first get the Secondary object, via the TCS
    my $tcs = $cfg->tcs;
    throw OMP::Error::FatalError('for some reason TCS setup is not available. This can not happen') unless defined $tcs;

    # ... and secondary
    my $secondary = $tcs->getSecondary();
    throw OMP::Error::FatalError('for some reason Secondary configuration is not available. This can not happen') unless defined $secondary;

    # N_JIGS_ON etc
    my %timing = $secondary->timing;

    # Get the full jigle parameters from the secondary object
    my $jig = $secondary->jiggle;

    # Now calculate the total time for 1 full coverage of the jiggle pattern
    # We need the N_JIGS_ON and N_CYC_OFF here because the more we chop the more inefficient
    # we are (the sqrt scaling means that a single pattern is more efficient than breaking it
    # up into smaller chunks

    # Number of chunks
    my $njig_chunks = $jig->npts / $timing{N_JIGS_ON};

    # Calculate number of steps in a jiggle pattern
    # The factor of 2 is because the chop pattern does N_CYC_OFF either side of the ON
    my $nsteps = $njig_chunks * ( $timing{N_JIGS_ON} + ( 2 * $timing{N_CYC_OFF} ) );

    # Time per full jig pattern
    my $timePerJig = $nsteps * $jos->step_time;

    # The number of times we need to go round the jiggle (per cycle) is the total
    # requested time divided by the step time
    my $nrepeats = ceil( $info{secsPerJiggle} / $jos->step_time );

    # These repeats have to spread evenly over 4 nod cycles (a single nod set)
    # This would be JOS_MULT if NUM_NOD_SETS was 1 and time between nods could go
    # very high
    my $total_jos_mult = ceil( $nrepeats / 4 );

    # now get the max time between nods
    my $max_t_nod = OMP::Config->getData( 'acsis_translator.max_time_between_nods' );

    # and convert that to the max number of jiggle repeats per nod
    my $max_jos_mult = int( $max_t_nod / $timePerJig );

    # The actual JOS_MULT and NUM_NOD_SETS can now be calculated
    # If we need less than required we just use that
    my $num_nod_sets;
    my $jos_mult;
    if ($total_jos_mult <  $max_jos_mult) {
      # we can do it all in one go
      $num_nod_sets = 1;
      $jos_mult = $total_jos_mult;
    } else {
      # we need to split the total into equal chunks smaller than max_jos_mult
      $num_nod_sets = int($total_jos_mult / $max_jos_mult);
      $jos_mult = $max_jos_mult;
    }

    $jos->jos_mult( $jos_mult );
    $jos->num_nod_sets( $num_nod_sets );

    if ($self->verbose) {
      print "Jiggle JOS parameters:\n";
      print "\ttimePerJig : $timePerJig\n";
      print "\tRequested integration time per pixel: $info{secsPerJiggle}\n";
      print "\tN repeats of whole jiggle pattern required: $nrepeats\n";
      print "\tRequired total JOS_MULT: $total_jos_mult\n";
      print "\tMax allowed JOS_MULT : $max_jos_mult\n";
      print "\tNumber of nod sets: $num_nod_sets in groups of $jos_mult jiggle repeats\n";
    }

  } elsif ($info{observing_mode} =~ /grid_chop/) {

    # Similar to a jiggle_chop recipe (in fact they are the same) but
    # we are not jiggling (ie a single jiggle point at the origin)

    # Have to do ABBA sequence so JOS_MULT is the secsPerCycle / 4
    # with the max nod time constraint

    # Required Integration time per cycle in STEPS
    my $stepsPerCycle = ceil( $info{secsPerCycle} / $jos->step_time );

    # Total number of steps required per nod
    my $total_jos_mult = ceil( $stepsPerCycle / 4 );

    # Max time between nods
    my $max_t_nod = OMP::Config->getData( 'acsis_translator.max_time_between_nods' );

    # converted to steps
    my $max_steps_nod = ceil( $max_t_nod / $jos->step_time );

    my $num_nod_sets;
    my $jos_mult;
    if ( $max_steps_nod > $total_jos_mult ) {
      # can complete the required integration in a single nod set
      $jos_mult = $total_jos_mult;
      $num_nod_sets = 1;
    } else {
      # Need to spread it out
      $num_nod_sets = int( $total_jos_mult / $max_steps_nod );
      $jos_mult = $max_steps_nod;
    }

    $jos->jos_mult( $jos_mult );
    $jos->num_nod_sets( $num_nod_sets );

    if ($self->verbose) {
      print "Chop JOS parameters:\n";
      print "\tRequested integration time per cycle: $info{secsPerCycle} sec\n";
      print "\tStep time for chop: ". $jos->step_time . " sec\n";
      print "\tRequired total JOS_MULT: $total_jos_mult\n";
      print "\tMax allowed JOS_MULT : $max_steps_nod\n";
      print "\tNumber of nod sets: $num_nod_sets in groups of $jos_mult steps per nod\n";
      print "\tActual integraton time per cycle: ".($num_nod_sets * $jos_mult * 4)." sec\n";
    }

  } elsif ($info{observing_mode} =~ /grid/) {

    # N.B. The NUM_CYCLES has already been set to
    # the number of requested integrations
    # above.

    # First JOS_MIN
    # This is the number of samples on each grid position
    # so = secsPerCycle / STEP_TIME
    my $jos_min = ceil($info{secsPerCycle} / $self->step_time( %info ));
    $jos->jos_min($jos_min);

    # N_REFSAMPLES should be equal
    # to the number of samples on each grid position
    # i.e. $jos_min
    my $nrefs = $jos_min;
    $jos->n_refsamples( $nrefs );

    # NUM_NOD_SETS - set to 1
    my $num_nod_sets = 1;
    $jos->num_nod_sets( $num_nod_sets );

    if ($self->verbose) {
      print "Grid JOS parameters:\n";
      print "N_REFSAMPLES = $nrefs\n";
      print "JOS_MIN = $jos_min\n";
      print "NUM_NOD_SETS =  $num_nod_sets \n";
    }

  } elsif ($info{observing_mode} =~ /freqsw/) {

    # Parameters to calculate 
    # NUM_CYCLES       =>  Number of complete iterations
    # JOS_MULT         => Number of complete jiggle maps per sequence
    # STEP_TIME        => RTS step time during an RTS sequence
    # N_CALSAMPLES     => Number of load samples per cal

    # NUM_CYCLES has already been set above.
    # N_CALSAMPLES has already been set too.
    # STEP_TIME ditto

    # Just need to set JOS_MULT
    my $jos_mult;

    # first get the Secondary object, via the TCS
    my $tcs = $cfg->tcs;
    throw OMP::Error::FatalError('for some reason TCS setup is not available. This can not happen') unless defined $tcs;

    # ... and secondary
    my $secondary = $tcs->getSecondary();
    throw OMP::Error::FatalError('for some reason Secondary configuration is not available. This can not happen') unless defined $secondary;

    # N_JIGS_ON etc
    my %timing = $secondary->timing;
    # Get the full jigle parameters from the secondary object
    my $jig = $secondary->jiggle;
    throw OMP::Error::FatalError('for some reason the Jiggle configuration is not available. This can not happen for a jiggle observation') unless defined $jig;

    # Now calculate JOS_MULT
    # +1 to make sure we get 
    # at least the requested integration time
    $jos_mult = int ( $info{secsPerJiggle} / (2 * $jos->step_time * $jig->npts ) )+1;

    $jos->jos_mult($jos_mult);
    if ($self->verbose) {
      print "JOS_MULT = $jos_mult\n";
  }
      my $iter_per_cal=8;
      $jos->iter_per_cal($iter_per_cal);
    if ($self->verbose) {
      print "ITER_PER_CAL = $iter_per_cal\n";
  }

  } else {
    throw OMP::Error::TranslateFail("Unrecognized observing mode for JOS configuration '$info{observing_mode}'");
  }

  # Non science observing types
  if ($info{obs_type} =~ /focus/ ) {
    $jos->num_focus_steps( $info{focusPoints} );
    $jos->focus_step( $info{focusStep} );
    $jos->focus_axis( $info{focusAxis} );
  }

  # Tasks can be worked out by seeing which objects are configured.
  # This is done automatically on stringification of the config object
  # so we do not need to do it here


  # store it
  $cfg->jos( $jos );

}

=item B<correlator>

Calculate the hardware correlator mapping from the receptor to the spectral
window.

  $trans->correlator( $cfg, %info );

=cut

sub correlator {
  my $self = shift;
  my $cfg = shift;
  my %info = @_;

  # get the acsis configuration
  my $acsis = $cfg->acsis;
  throw OMP::Error::FatalError('for some reason ACSIS setup is not available. This can not happen') unless defined $acsis;

  # get the spectral window information
  my $spwlist = $acsis->spw_list();
  throw OMP::Error::FatalError('for some reason Spectral Window configuration is not available. This can not happen') unless defined $spwlist;

  # get the hardware map
  my $hw_map = $self->hardware_map;

  # Now get the receptors of interest for this observation
  my $frontend = $cfg->frontend;
  throw OMP::Error::FatalError('for some reason Frontend setup is not available. This can not happen') unless defined $frontend;

  # and only worry about the pixels that are switched on
  my @rec = $frontend->active_receptors;

  # All of the subbands that need to be allocated
  my %subbands = $spwlist->subbands;

  # CM and DCM bandwidth modes
  my @cm_bwmodes;
  my @dcm_bwmodes;
  my @cm_map;
  my @sbmodes;

  # lookup from lo2 id to spectral window
  my @lo2spw;

  # for each receptor, we need to assign all the subbands to the correct
  # hardware

  for my $r (@rec) {

    # Get the number of subbands to allocate for this receptor
    my @spwids = sort keys %subbands;

    # Get the CM mapping for this receptor
    my @hwmap = $hw_map->receptor( $r );
    throw OMP::Error::FatalError("Receptor '$r' is not available in the ACSIS hardware map! This is not supposed to happen") unless @hwmap;

    if (@spwids > @hwmap) {
      throw OMP::Error::TranslateFail("The observation specified " . @spwids . " subbands but there are only ". @hwmap . " slots available for receptor '$r'");
    }

    # now loop over subbands
    for my $i (0..$#spwids) {
      my $hw = $hwmap[$i];
      my $spwid = $spwids[$i];
      my $sb = $subbands{$spwid};

      my $cmid = $hw->{CM_ID};
      my $dcmid = $hw->{DCM_ID};
      my $quadnum = $hw->{QUADRANT};
      my $sbmode = $hw->{SB_MODES}->[0];
      my $lo2id = $hw->{LO2};

      my $bwmode = $sb->bandwidth_mode;

      # Correlator uses the standard bandwidth mode
      $cm_bwmodes[$cmid] = $bwmode;

      # DCM just wants the bandwidth without the channel count
      my $dcmbw = $bwmode;
      $dcmbw =~ s/x.*$//;
      $dcm_bwmodes[$dcmid] = $dcmbw;

      # hardware mapping to spectral window ID
      my %map = (
		 CM_ID => $cmid,
		 DCM_ID => $dcmid,
		 RECEPTOR => $r,
		 SPW_ID => $spwid,
		);

      $cm_map[$cmid] = \%map;

      # Quadrant mapping to subband mode is fixed by the hardware map
      if (defined $sbmodes[$quadnum]) {
	if ($sbmodes[$quadnum] != $sbmode) {
	  throw OMP::Error::FatalError("Subband mode for quadrant $quadnum does not match previous setting\n");
	}
      } else {
	$sbmodes[$quadnum] = $sbmode;
      }

      # Convert lo2id to an array index
      $lo2id--;

      if (defined $lo2spw[$lo2id]) {
	if ($lo2spw[$lo2id] ne $spwid) {
	  throw OMP::Error::FatalError("LO2 #$lo2id is associated with spectral windows $spwid AND $lo2spw[$lo2id]\n");
	}
      } else {
	$lo2spw[$lo2id] = $spwid;
      }

    }

  }

  # Now store the mappings in the corresponding objects
  my $corr = new JAC::OCS::Config::ACSIS::ACSIS_CORR();
  my $if   = new JAC::OCS::Config::ACSIS::ACSIS_IF();
  my $map  = new JAC::OCS::Config::ACSIS::ACSIS_MAP();

  # to decide on CORRTASK mapping
  $map->hw_map( $hw_map );

  # Store the relevant arrays
  $map->cm_map( @cm_map );
  $if->bw_modes( @dcm_bwmodes );
  $if->sb_modes( @sbmodes );
  $corr->bw_modes( @cm_bwmodes );

  # Set the LO2. First we need to check that values are available that were
  # calculated previously
  throw OMP::Error::FatalError("Somehow the LO2 settings were never calculated")
    unless exists $info{freqconfig}->{LO2};

  my @lo2;
  for my $i (0..$#lo2spw) {
    my $spwid = $lo2spw[$i];
    next unless defined $spwid;

    # sanity check never hurts
    throw OMP::Error::FatalError("Spectral window $spwid does not seem to exist in LO2 array")
      unless exists $info{freqconfig}->{LO2}->{$spwid};

    # store it
    $lo2[$i] = $info{freqconfig}->{LO2}->{$spwid};
  }
  $if->lo2freqs( @lo2 );

  # Set the LO3 to a fixed value (all the test files do this)
  # A string since this is meant to be hard-coded to be exactly this by the DTD
  $if->lo3freq( "2000.0" );

  # store in the ACSIS object
  $acsis->acsis_corr( $corr );
  $acsis->acsis_if( $if );
  $acsis->acsis_map( $map );

  return;
}

=item B<line_list>

Configure the line list information.

  $trans->line_list( $cfg, %info );

=cut

sub line_list {
  my $self = shift;
  my $cfg = shift;
  my %info = @_;

  # get the acsis configuration
  my $acsis = $cfg->acsis;
  throw OMP::Error::FatalError('for some reason ACSIS setup is not available. This can not happen') unless defined $acsis;

  # Get the frequency information
  my $freq = $info{freqconfig}->{subsystems};
  my %lines;
  my $counter = 1; # used when a duplicate label is in use
  for my $s ( @$freq ) {
    my $key = JAC::OCS::Config::ACSIS::LineList->moltrans2key( $s->{species},
							       $s->{transition}
							     );
    my $freq = $s->{rest_freq};

    # store the reference key in the hash
    $s->{rest_freq_ref} = $key;

    # have we used this before?
    if (exists $lines{$key}) {
      # if the frequency is the same just skip
      next if $lines{$key} == $freq;

      # Tweak the key
      $key .= "_$counter";
      $counter++;
    }

    # store the new value
    $lines{$key} = $freq;
  }

  # Create the line list object
  my $ll = new JAC::OCS::Config::ACSIS::LineList();
  $ll->lines( %lines );
  $acsis->line_list( $ll );

}

=item B<spw_list>

Add the spectral window information to the configuration.

 $trans->spw_list( $cfg, %info );

=cut

sub spw_list {
  my $self = shift;
  my $cfg = shift;
  my %info = @_;

  # get the acsis configuration
  my $acsis = $cfg->acsis;
  throw OMP::Error::FatalError('for some reason ACSIS setup is not available. This can not happen') unless defined $acsis;

  # Get the frontend object for the sideband
  # Hopefully we will not need to do this if ACSIS can be tweaked to get it from
  # frontend XML itself
  my $fe = $cfg->frontend;
  throw OMP::Error::FatalError('for some reason frontend configuration is not available during spectral window processing. This can not happen') unless defined $fe;

  # Get the sideband and convert it to a sign -1 == LSB +1 == USB
  my $sb = $fe->sideband;
  my $fe_sign;
  if ($sb eq 'LSB') {
    $fe_sign = -1;
  } elsif ($sb eq 'USB') {
    $fe_sign = 1;
  } elsif ($sb eq 'BEST') {
    $fe_sign = 1;
  } else {
    throw OMP::Error::TranslateFail("Sideband is not recognised ($sb)");
  }

  # Get the frequency information for each subsystem
  my $freq = $info{freqconfig}->{subsystems};

  # Force bandwidth calculations
  $self->bandwidth_mode( %info );

  # Default baseline fitting mode will probably depend on observing mode
  my $defaultPoly = 1;

  # Get the DR information
  my %dr;
  %dr = %{ $info{data_reduction} } if exists $info{data_reduction};
  if (!keys %dr) {
    %dr = ( window_type => 'hanning',
	    fit_polynomial_order => $defaultPoly,
	  ); # defaults
  } else {
    $dr{window_type} ||= 'hanning';
    $dr{fit_polynomial_order} ||= $defaultPoly;

    # default to number if DEFAULT.
    $dr{fit_polynomial_order} = $defaultPoly unless $dr{fit_polynomial_order} =~ /\d/;
  }

  # Figure out the baseline fitting. We either have no baseline,
  # fractional baseline or manual baseline
  # Baselines are an array of interval objects
  # empty array is fine
  my $frac; # fraction of bandwidth to use for baseline (depends on subsystem)
  my @baselines;
  if (exists $dr{baseline} && defined $dr{baseline}) {
    if (ref($dr{baseline})) {
      # array of OMP::Range objects
      @baselines = map { new JAC::OCS::Config::Interval( Min => $_->min,
							 Max => $_->max,
							 Units => $_->units); 
		       } @{$dr{baseline}};
    } else {
      # scalar fraction implies two baseline regions
      $frac = $dr{baseline};
    }
  }

  # The LO2 settings indexed by spectral window. We should consider simply adding
  # this to the SpectralWindow object as an accessor or in conjunction with f_park
  # derive it on demand.
  my %lo2spw;

  # Spectral window objects
  my %spws;
  my $spwcount = 1;
  for my $ss (@$freq) {
    my $spw = new JAC::OCS::Config::ACSIS::SpectralWindow;
    $spw->rest_freq_ref( $ss->{rest_freq_ref});
    $spw->fe_sideband( $fe_sign );
    $spw->baseline_fit( function => "polynomial",
			degree => $dr{fit_polynomial_order}
		      ) if exists $dr{fit_polynomial_order};

    # Create an array of IF objects suitable for use in the spectral
    # window object(s). The ref channel and the if freq are per-sideband
    my @ifcoords = map { 
      new JAC::OCS::Config::ACSIS::IFCoord( if_freq => $ss->{if_per_subband}->[$_],
					    nchannels => $ss->{nchan_per_sub},
					    channel_width => $ss->{channwidth},
					    ref_channel => $ss->{if_ref_channel}->[$_],
					  )
    } (0..($ss->{nsubbands}-1));

    # Counting for hybridized spectra still assumes the original number
    # of channels in the units. We assume that the fraction specified
    # is a fraction of the hybrid baseline but we need to correct
    # for the overlap when calculating the actual position of the baseline
    if (defined $frac) {

      # get the full number of channels
      my $nchan_full = $ss->{nchannels_full};

      # Get the hybridized number of channels
      my $nchan_hyb = $ss->{channels};
      my $nchan_bl = int($nchan_hyb * $frac / 2 );

      # number of channels chopped from each end
      my $nchop = int(($nchan_full - $nchan_hyb) / 2);

      # Include a small offset from the very end channel of the spectrum
      # and convert to channels
      my $edge_frac = 0.01;
      my $nedge = int( $nchan_hyb * $edge_frac);

      # Calculate total offset
      my $offset = $nchop + $nedge;

      @baselines = (
	   new JAC::OCS::Config::Interval( Units => 'pixel',
					   Min => $offset, 
					   Max => ($nchan_bl+$offset)),
	   new JAC::OCS::Config::Interval( Units => 'pixel',
					   Min => ($nchan_full 
						   - $offset - $nchan_bl),
					   Max => ($nchan_full-$offset)),
	  );
    }
    $spw->baseline_region( @baselines ) if @baselines;

    # Line region for pointing and focus
    # This will be ignored in subbands
    if ($info{obs_type} ne 'science') {
      $spw->line_region( new JAC::OCS::Config::Interval( Units => 'pixel',
							 Min => 0,
							 Max => ($ss->{nchannels_full}-1 ) ));
    }


    # hybrid or not?
    if ($ss->{nsubbands} == 1) {
      # no hybrid. Just store it
      $spw->window( 'truncate' );
      $spw->align_shift( $ss->{align_shift}->[0] );
      $spw->bandwidth_mode( $ss->{bwmode});
      $spw->if_coordinate( $ifcoords[0] );

    } elsif ($ss->{nsubbands} == 2) {
      my %hybrid;
      my $sbcount = 1;
      for my $i (0..$#ifcoords) {
	my $sp = new JAC::OCS::Config::ACSIS::SpectralWindow;
	$sp->bandwidth_mode( $ss->{bwmode} );
	$sp->if_coordinate( $ifcoords[$i] );
	$sp->fe_sideband( $fe_sign );
	$sp->align_shift( $ss->{align_shift}->[$i] );
	$sp->rest_freq_ref( $ss->{rest_freq_ref});
	$sp->window( $dr{window_type} );
	my $id = "SPW". $spwcount . "." . $sbcount;
	$hybrid{$id} = $sp;
	$lo2spw{$id} = $ss->{lo2}->[$i];
	$sbcount++;
      }

      # Store the subbands
      $spw->subbands( %hybrid );

      # Create global IF coordinate object for the hybrid. For some reason
      # this does not take overlap into account but does take the if of the first subband
      # rather than the centre IF
      my $if = new JAC::OCS::Config::ACSIS::IFCoord( if_freq => $ss->{if_per_subband}->[0],
						     nchannels => $ss->{nchannels_full},
						     channel_width => $ss->{channwidth},
						     ref_channel => ($ss->{nchannels_full}/2));
      $spw->if_coordinate( $if );

    } else {
      throw OMP::Error::FatalError("Do not know how to process more than 2 subbands");
    }

    # Determine the Spectral Window label and store it in the output hash and
    # the subsystem hash
    my $splab = "SPW". $spwcount;
    $spws{$splab} = $spw;
    $ss->{spw} = $splab;

    # store the LO2 for this only if it is not a hybrid
    # Cannot do this earlier since we need the splabel
    $lo2spw{$splab} = $ss->{lo2}->[0] if $ss->{nsubbands} == 1;

    $spwcount++;
  }

  # Store the LO2
  $info{freqconfig}->{LO2} = \%lo2spw;

  # Create the SPWList
  my $spwlist = new JAC::OCS::Config::ACSIS::SPWList;
  $spwlist->spectral_windows( %spws );

  # Store the data fiels. Just assume these are okay but probably need a template 
  # file
  $spwlist->data_fields( spw_id => "SPEC_WINDOW_ID",
			 doppler => 'FE.STATE.DOPPLER',
			 fe_lo => 'FE.STATE.LO_FREQUENCY'
		       );

  # Store it
  $acsis->spw_list( $spwlist );

}

=item B<acsisdr_recipe>

Configure the real time pipeline.

  $trans->acsisdr_recipe( $cfg, %info );

=cut

sub acsisdr_recipe {
  my $self = shift;
  my $cfg = shift;
  my %info = @_;

  # get the acsis configuration
  my $acsis = $cfg->acsis;
  throw OMP::Error::FatalError('for some reason ACSIS setup is not available. This can not happen') unless defined $acsis;

  # Get the observing mode or observation type for the DR recipe
  my $root;
  if ($info{obs_type} eq 'science') {
    # keyed on observing mode
    my $obsmode = $info{observing_mode};
    $obsmode = 'jiggle_chop' if $obsmode eq 'grid_chop';
    $root = $obsmode . '_dr_recipe.ent';
  } else {
    # keyed on observation type
    $root = $info{obs_type} . '_dr_recipe.ent';
  }
  my $filename = File::Spec->catfile( $WIRE_DIR, 'acsis', $root );

  # Read the recipe itself
  my $dr = new JAC::OCS::Config::ACSIS::RedConfigList( EntityFile => $filename,
						       validation => 0);
  $acsis->red_config_list( $dr );

  # and now the mapping that is also recipe specific
  my $sl = new JAC::OCS::Config::ACSIS::SemanticLinks( EntityFile => $filename,
						       validation => 0);
  $acsis->semantic_links( $sl );

  # and the basic gridder configuration
  my $g = new JAC::OCS::Config::ACSIS::GridderConfig( EntityFile => $filename,
						      validation => 0,
						    );
  $acsis->gridder_config( $g );

  # Write the observing mode to the recipe
  my $rmode = $info{observing_mode};
  $rmode =~ s/_/\//g;
  $acsis->red_obs_mode( $rmode );
  $acsis->red_recipe_id( "incorrect. Should be read from file");

}

=item B<cubes>

Configure the output cube(s).

  $trans->cubes( $cfg, %info );

=cut

sub cubes {
  my $self = shift;
  my $cfg = shift;
  my %info = @_;

  # get the acsis configuration
  my $acsis = $cfg->acsis;
  throw OMP::Error::FatalError('for some reason ACSIS setup is not available. This can not happen') unless defined $acsis;

  # Get the instrument footprint
  my $inst = $cfg->instrument_setup;
  throw OMP::Error::FatalError('for some reason Instrument configuration is not available. This can not happen') 
    unless defined $inst;
  my @footprint = $inst->receptor_offsets;

  # Need to correct for any offset that we may be applying to BASE
  my $apoff = $self->tracking_offset( $cfg, %info );

  # And also make it available as "internal hash format"
  my @footprint_h = $self->_to_offhash( @footprint );

  # shift instrument if FPLANE offset
  if (defined $apoff) {
    if ($apoff->system eq 'FPLANE') {
      throw OMP::Error::TranslateFail("Non-zero position angle for focal plane offset is unexpected\n")
	if $apoff->posang->radians != 0.0;

      for my $pos (@footprint_h) {
	$pos->{OFFSET_DX} -= $apoff->xoffset->arcsec;
	$pos->{OFFSET_DY} -= $apoff->yoffset->arcsec;
      }
    } else {
      throw OMP::Error::TranslateFail("Trap for unwritten code when offset is not FPLANE");
    }
  }

  # Can we match position angles of the receiver with the rotated map or not? Use the focal station to decide
  my $matchpa;
  if ( $inst->focal_station eq 'DIRECT' ) {
    $matchpa = 0;
  } else {
    # Assumes image rotator if on the Nasmyth
    $matchpa = 1;
  }

  # Create the cube list
  my $cl = new JAC::OCS::Config::ACSIS::CubeList();

  # Get the subsystem information
  my $freq = $info{freqconfig}->{subsystems};

  # Now loop over subsystems to create cube specifications
  my %cubes;
  my $count = 1;
  for my $ss (@$freq) {

    # Create the cube(s). One cube per subsystem.
    my $cube = new JAC::OCS::Config::ACSIS::Cube;
    my $cubid = "CUBE" . $count;

    # Data source
    throw OMP::Error::FatalError( "Spectral window ID not defined. Internal inconsistency")
       unless defined $ss->{spw};
    $cube->spw_id( $ss->{spw} );

    # Presumably the gridder should not regrid the full spectral dimension
    # if a specific line region has been specified. For now just use full range.
    # The cube example xml seems to start at channel 0
    my $int = new JAC::OCS::Config::Interval( Min => 0,
					      Max => ( $ss->{nchannels_full}-1),
					      Units => 'channel');
    $cube->spw_interval( $int );

    # Tangent point (aka group centre) is the base position without offsets
    # Not used if we are in a moving (eg PLANET) frame
    $cube->group_centre( $info{coords} ) if $info{coords}->type eq 'RADEC';

    # Calculate Nyquist value for this map
    my $nyq = $self->nyquist( %info );

    # Until HARP comes we use TopHat for all observing modes
    # HARP without image rotator will require Gaussian.
    # This will need support for rotated coordinate frames in the gridder
    my $grid_func = "TopHat";
    $grid_func = "Gaussian" if $info{mapping_mode} =~ /raster/;
    $cube->grid_function( $grid_func );

    # Variable to indicate map coord override
    my $grid_coord;

    # The size and number of pixels depends on the observing mode.
    # For raster, we have a regular grid but the 
    my ($nx, $ny, $mappa, $xsiz, $ysiz, $offx, $offy);
    if ($info{mapping_mode} =~ /raster/) {
      # This will be more complicated for HARP since DY will possibly
      # be larger and we will need to take the receptor spacing into account

      # The X spacing depends on the requested sample time per map point
      # and the scan velocity
      $xsiz = $info{SCAN_VELOCITY} * $info{sampleTime};

      # For single pixel instrument define the Y pixel as the spacing
      # between scan rows. For HARP we probably want to be clever but for
      # now choose the pixel size to be the x pixel size.
      if ($inst->name =~ /HARP/) {
	$ysiz = $xsiz;
      } else {
	$ysiz = $info{SCAN_DY};
      }

      # read the map position angle
      $mappa = $info{MAP_PA}; # degrees

      # and the map area in pixels
      $nx = int( ( $info{MAP_WIDTH} / $xsiz ) + 0.5 ) ;
      $ny = int( ( $info{MAP_HEIGHT} / $ysiz ) + 0.5 );

      $offx = ($info{OFFSET_DX} || 0);
      $offy = ($info{OFFSET_DY} || 0);

      # These should be rotated to the MAP_PA coordinate frame
      # if it is meant to be in the coordinate frame of the map
      # for now rotate to ra/dec.
      if ($info{OFFSET_PA} != 0) {
	($offx, $offy) = $self->PosAngRot( $offx, $offy, $info{OFFSET_PA});
      }

    } elsif ($info{mapping_mode} =~ /grid/i) {
      # Get the required offsets. These will always be in tracking coordinates TAN.
      my @offsets;
      @offsets = @{$info{offsets}} if (exists $info{offsets} && defined $info{offsets});

      # Should fix up earlier code to add SYSTEM
      for (@offsets) {
	$_->{SYSTEM} = "TRACKING";
      }

      # Now convolve these offsets with the instrument footprint
      my @convolved = $self->convolve_footprint( $matchpa, \@footprint_h, \@offsets );

      # Now calculate the final grid
      ($nx, $ny, $xsiz, $ysiz, $mappa, $offx, $offy) = $self->calc_grid( $self->nyquist(%info)->arcsec,
									 @convolved );

    } elsif ($info{mapping_mode} =~ /jiggle/i) {
      # Need to know:
      #  - the extent of the jiggle pattern
      #  - the footprint of the array. Assume single pixel

      # first get the Secondary object, via the TCS
      my $tcs = $cfg->tcs;
      throw OMP::Error::FatalError('for some reason TCS setup is not available. This can not happen') unless defined $tcs;

      # ... and secondary
      my $secondary = $tcs->getSecondary();
      throw OMP::Error::FatalError('for some reason Secondary configuration is not available. This can not happen') unless defined $secondary;

      # Get the information
      my $jig = $secondary->jiggle;
      throw OMP::Error::FatalError('for some reason the Jiggle configuration is not available. This can not happen for a jiggle observation') unless defined $jig;

      # Store the grid coordinate frame
      $grid_coord = $jig->system;

      # and the angle
      my $pa = $jig->posang->degrees;

      # Get the map offsets
      my @offsets = map { { OFFSET_DX => $_->[0],
			    OFFSET_DY => $_->[1],
			    OFFSET_PA => $pa,
		        } } $jig->spattern;

      # Convolve them with the instrument footprint
      my @convolved = $self->convolve_footprint( $matchpa, \@footprint_h, \@offsets );

      # calculate the pattern without a global offset
      ($nx, $ny, $xsiz, $ysiz, $mappa, $offx, $offy) = $self->calc_grid( $self->nyquist(%info)->arcsec,
									 @convolved);

      # get the global offset for this observation
      my $global_offx = ($info{OFFSET_DX} || 0);
      my $global_offy = ($info{OFFSET_DY} || 0);

      # rotate those offsets to the mappa
      if ($info{OFFSET_PA} != $mappa) {
	($global_offx, $global_offy) = $self->PosAngRot( $global_offx, $global_offy, ($info{OFFSET_PA}-$mappa));
      }

      # add any offset from the unrolled offset iterator
      $offx += $global_offx;
      $offy += $global_offy;

    } else {
      # pointing is going to be a map based on the jiggle offset
      # and will be different for HARP
      # focus will probably be a single spectrum in continuum mode

      throw OMP::Error::TranslateFail("Do not yet know how to size a cube for mode $info{observing_mode}");
    }


    throw OMP::Error::TranslateFail( "Unable to determine X pixel size")
      unless defined $xsiz;
    throw OMP::Error::TranslateFail( "Unable to determine Y pixel size")
      unless defined $ysiz;

    # Store the parameters
    $cube->pixsize( new Astro::Coords::Angle($xsiz, units => 'arcsec'),
		    new Astro::Coords::Angle($ysiz, units => 'arcsec'));
    $cube->npix( $nx, $ny );

    $cube->posang( new Astro::Coords::Angle( $mappa, units => 'deg'))
      if defined $mappa;

    # Decide whether the grid is regridding in sky coordinates or in AZEL
    # Focus and Pointing are AZEL
    # Assume also that AZEL jiggles want AZEL maps
    if ($info{obs_type} =~ /point|focus/i || (defined $grid_coord && $grid_coord eq 'AZEL') ) {
      $cube->tcs_coord( 'AZEL' );
    } else {
      $cube->tcs_coord( 'TRACKING' );
    }

    # offset in pixels (note that for RA maps positive offset is
    # in opposite direction to grid)
    my $offy_pix = sprintf("%.4f", $offy / $ysiz) * 1.0;
    my $offx_pix = sprintf("%.4f", $offx / $xsiz) * 1.0;
    if ($cube->tcs_coord eq 'TRACKING') {
      $offx_pix *= -1.0;
    }

    $cube->offset( $offx_pix, $offy_pix );

    # Currently always use TAN projection since that is what SCUBA uses
    $cube->projection( "TAN" );

    # Gaussian requires a FWHM and truncation radius
    if ($grid_func eq 'Gaussian') {

      # For an oversampled map, the SCUBA regridder has been analysed empirically 
      # to determine an optimum smoothing gaussian HWHM of lambda / 5d ( 0.4 of Nyquist).
      # This compromises smoothness vs beam size. If the pixels are very large (larger than
      # the beam) we just assume that the user does not want to really smear across
      # pixels that large so we still use the beam. The gaussian convolution will probably
      # not work if you have 80 arcsec pixels and 10 arcsec gaussian

      # Use the SCUBA optimum ratios derived by Claire Chandler of
      # HWHM = lambda / 5D (ie 0.4 of Nyquist) or FWHM = lambda / 2.5D
      # (or 0.8 Nyquist).
      my $fwhm = $nyq->arcsec * 0.8;
      $cube->fwhm( $fwhm );

      # Truncation radius is half the pixel size for TopHat
      # For Gausian we use 3 HWHM (that's what SCUBA used)
      $cube->truncation_radius( $fwhm * 1.5 );
    } else {
      # The gridder needs a non-zero truncation radius even if the gridding
      # technique does not use it! We have two choices. Either set a default
      # value here in the translator or make sure that the Config class
      # always fills in a blank. For now kluge in the translator to make sure
      # we do not exceed the smallest pixel.
      $cube->truncation_radius( min($xsiz,$ysiz)/2 );
    }

    if ($self->verbose) {
      print "Cube parameters [$cubid]:\n";
      print "\tDimensions: $nx x $ny\n";
      print "\tPixel Size: $xsiz x $ysiz arcsec\n";
      print "\tMap frame:  ". $cube->tcs_coord ."\n";
      print "\tMap Offset: $offx, $offy arcsec ($offx_pix, $offy_pix) pixels\n";
      print "\tMap PA:     $mappa deg\n";
      print "\tGrid Function: $grid_func\n";
      if ( $grid_func eq 'Gaussian') {
	print "\t  Gaussian FWHM: " . $cube->fwhm() . " arcsec\n";
      }
      print "\t  Truncation radius: ". $cube->truncation_radius() . " arcsec\n";
    }

    $cubes{$cubid} = $cube;
    $count++;
  }

  # Store it
  $cl->cubes( %cubes );

  $acsis->cube_list( $cl );

}

=item B<rtd_config>

Configure the Real Time Display.

  $trans->rtd_config( $cfg, %info );

Currently this method is dumb, mainly because there is a lot of junk in the
rtd_config element that is machine depenedent rather than translation dependent.
The only information that should be provided by the translator is:

  o  The spectral window of interest
  o  Possibly the coordinate range of the spectral axis

=cut

sub rtd_config {
  my $self = shift;
  my $cfg = shift;
  my %info = @_;

  # get the acsis configuration
  my $acsis = $cfg->acsis;
  throw OMP::Error::FatalError('for some reason ACSIS setup is not available. This can not happen')
    unless defined $acsis;

  # The filename is DR receipe dependent
  my $root;
  if ($info{obs_type} eq 'science') {
    # keyed on observing mode
    my $obsmode = $info{observing_mode};
    $obsmode = 'jiggle_chop' if $obsmode eq 'grid_chop';
    $root = $obsmode . '_rtd.ent';
  } else {
    # keyed on observing type
    $root = $info{obs_type} . '_rtd.ent';
  }

  my $filename = File::Spec->catfile( $WIRE_DIR, 'acsis', $root);

  # Read the entity
  my $il = new JAC::OCS::Config::ACSIS::RTDConfig( EntityFile => $filename,
						   validation => 0);
  $acsis->rtd_config( $il );

}

=item B<simulator_config>

Configure the simulator XML. For ACSIS this actually goes into the
ACSIS xml and there is not a distinct task for simulation (the
simulated CORRTASKs read this simulator data).

=cut

sub simulator_config {
  my $self = shift;
  my $cfg = shift;
  my %info = @_;

  # We may want to get basic values from an entity file on disk and then configure
  # the observation specific elements

  # get the acsis configuration
  my $acsis = $cfg->acsis;
  throw OMP::Error::FatalError('for some reason ACSIS setup is not available. This can not happen')
    unless defined $acsis;

  # Get the cube definition
  my $cl = $acsis->cube_list;
    throw OMP::Error::FatalError('for some reason the ACSIS Cube List is not defined. This can not happen')
    unless defined $cl;

  # Get the spectral window definitions
  my $spwlist = $acsis->spw_list();
  throw OMP::Error::FatalError('for some reason Spectral Window configuration is not available. This can not happen') unless defined $spwlist;

  # We create a cloud per cube definition
  my %cubes = $cl->cubes;

  # loop over all the cubes
  my @clouds;
  for my $cube (values %cubes) {
    my %thiscloud = (
		     position_angle => 0,
		     pos_z_width => 300,
		     neg_z_width => 300,
		     amplitude => 20,
		    );

    # Spectral window is required so that we can choose a channel somewhere
    # in the middle
    my $spwint = $cube->spw_interval;
    throw OMP::Error::FatalError( "Simulation requires channel units but it seems this spectral window was configured differently. Needs fixing.\n") if $spwint->units ne 'channel';
    $thiscloud{z_location} = int (($spwint->min + $spwint->max) / 2);

    # offset centre
    my @offset = $cube->offset;
    # No. of pixels, x and y
    my @npix=$cube->npix;
    # Put cloud in centre to nearest integer
    $thiscloud{x_location} = int($offset[0]+$npix[0]/2);
    $thiscloud{y_location} = int($offset[1]+$npix[1]/2);
    
    # Width of fake source. Is this in pixels or arcsec?
    # +1 to ensure that it always has non-zero width
    $thiscloud{major_width} = int(0.6 * $npix[0])+1;
    $thiscloud{minor_width} = int(0.6 * $npix[1])+1;

    push(@clouds, \%thiscloud);
  }

  # create the simulation
  my $sim = new JAC::OCS::Config::ACSIS::Simulation();

  # write cloud information
  $sim->clouds( @clouds );

  # Now write the non cloud information
  $sim->noise( 1 );
  $sim->refsky_temp( 135.0 );
  $sim->load2_temp( 250.0 );
  $sim->ambient_temp( 300.0 );
  $sim->band_start_pos( 120 );

  # attach simulation to acsis
  $acsis->simulation( $sim );
}

=item B<interface_list>

Configure the interface XML.

  $trans->interface_list( $cfg, %info );

=cut

sub interface_list {
  my $self = shift;
  my $cfg = shift;
  my %info = @_;

  # get the acsis configuration
  my $acsis = $cfg->acsis;
  throw OMP::Error::FatalError('for some reason ACSIS setup is not available. This can not happen') unless defined $acsis;

  my $filename = File::Spec->catfile( $WIRE_DIR, 'acsis', 'interface_list.ent');

  # Read the entity
  my $il = new JAC::OCS::Config::ACSIS::InterfaceList( EntityFile => $filename,
						       validation => 0);
  $acsis->interface_list( $il );
}

=item B<acsis_layout>

Read and configure the ACSIS process layout, process links, machine table
and monitor layout.

=cut

sub acsis_layout {
  my $self = shift;
  my $cfg = shift;
  my %info = @_;

  # get the acsis configuration
  my $acsis = $cfg->acsis;
  throw OMP::Error::FatalError('for some reason ACSIS setup is not available. This can not happen') unless defined $acsis;

  # This code is a bit more involved because in general the process layout
  # template file includes entity references that must be replaced with
  # more template XML prior to parsing.

  # The first thing we need to do is read the machine table and monitor
  # layout files

  # Read the new machine table (no longer in the acsis directory)
  my $machtable_file = File::Spec->catfile( $WIRE_DIR, 'machine_table.xml');
  my $machtable = _read_file( $machtable_file );

  # Read the monitor layout
  my $monlay_file = File::Spec->catfile( $WIRE_DIR, 'acsis', 'monitor_layout.ent');
  my $monlay = _read_file( $monlay_file );

  # make sure we have enclosing tags
  if ($monlay !~ /monitor_layout/) {
    $monlay = "<monitor_layout>\n$monlay\n</monitor_layout>\n";
  }

  # Get the instrument we are using
  my $inst = $self->ocs_frontend($info{instrument});
  throw OMP::Error::FatalError('No instrument defined - needed to select correct layout file !')
    unless defined $inst;

  # Now select the appropriate layout depending on the instrument found (and possibly mode)
  my $appropriate_layout;
  if (exists $ACSIS_Layouts{$inst . "_$info{observing_mode}"}) {
    $appropriate_layout = $ACSIS_Layouts{$inst."_$info{observing_mode}"} . '_layout.ent';
  } elsif (exists $ACSIS_Layouts{$inst}) {
    $appropriate_layout = $ACSIS_Layouts{$inst} . '_layout.ent';
  } else {
    throw OMP::Error::FatalError("Could not find an appropriate layout file for instrument $inst !");
  }

  # Read the template process_layout file
  my $lay_file = File::Spec->catfile( $WIRE_DIR, 'acsis',$appropriate_layout);
  my $layout = _read_file( $lay_file );

  print "Read ACSIS layout $lay_file\n" if $self->verbose;

  # Now we need to replace the entities.
  $layout =~ s/\&machine_table\;/$machtable/g;
  $layout =~ s/\&monitor_layout\;/$monlay/g;

  throw OMP::Error::TranslateFail( "Process layout XML does not seem to include any monitor_process elements!")
    unless $layout =~ /monitor_process/;

  throw OMP::Error::TranslateFail( "Process layout XML does not seem to include any machine_table elements!")
    unless $layout =~ /machine_table/;

  # make sure we have a wrapper element
  $layout = "<abcd>$layout</abcd>\n";

  # Create the process layout object
  my $playout = new JAC::OCS::Config::ACSIS::ProcessLayout( XML => $layout,
							    validation => 0);
  $acsis->process_layout( $playout );

  # and links
  my $plinks = new JAC::OCS::Config::ACSIS::ProcessLinks( XML => $layout,
							  validation => 0);
  $acsis->process_links( $plinks );

}


=item B<observing_mode>

Retrieves the ACSIS observing mode from the OT observation summary
(not from the OCS configuration) and updates the supplied observation
summary.

 $trans->observing_mode( \%info );

The following keys are filled in:

=over 8

=item observing_mode

A single string describing the observing mode. One of
jiggle_freqsw, jiggle_chop, grid_pssw, raster_pssw.

Note that there is no explicit slow vs fast jiggle switch mode
set from this routine since more subsystems ignore the difference
than care about the difference.

Note also that POINTING or FOCUS are not observing modes in this science.

=item mapping_mode

The underlying mapping mode. One of "jiggle", "raster" and "grid".

=item switching_mode

The switching scheme. One of "freqsw", "chop" and "pssw". This is 
a translated form of the input "switchingMode" parameter.

=item obs_type

The type of observation. One of "science", "pointing", "focus".

=back

=cut

sub observing_mode {
  my $self = shift;
  my $info = shift;

  my $mode = $info->{MODE};
  my $swmode = $info->{switchingMode};

  my ($mapping_mode, $switching_mode, $obs_type);

  # assume science
  $obs_type = 'science';

  if ($mode eq 'SpIterRasterObs') {
    $mapping_mode = 'raster';
    if ($swmode eq 'Position') {
      $switching_mode = 'pssw';
    } elsif ($swmode eq 'Chop' || $swmode eq 'Beam' ) {
      throw OMP::Error::TranslateFail("raster_chop not yet supported\n");
      $switching_mode = 'chop';
    } else {
      throw OMP::Error::TranslateFail("Raster with switch mode '$swmode' not supported\n");
    }
  } elsif ($mode eq 'SpIterPointingObs') {
    $mapping_mode = 'jiggle';
    $switching_mode = 'chop';
    $obs_type = 'pointing';
  } elsif ($mode eq 'SpIterFocusObs' ) {
    $mapping_mode = 'grid'; # Just chopping at 0,0
    $switching_mode = 'chop';
    $obs_type = 'focus';
  } elsif ($mode eq 'SpIterStareObs' ) {
    # check switch mode
    if ($swmode eq 'Position') {
      $mapping_mode = 'grid';
      $switching_mode = 'pssw';
    } elsif ($swmode eq 'Chop' || $swmode eq 'Beam' ) {
      $mapping_mode = 'grid'; # No jiggling
      $switching_mode = 'chop';
    } else {
      throw OMP::Error::TranslateFail("Sample with switch mode '$swmode' not supported\n");
    }
  } elsif ($mode eq 'SpIterJiggleObs' ) {
    # depends on switch mode
    $mapping_mode = 'jiggle';
    if ($swmode eq 'Chop' || $swmode eq 'Beam') {
      $switching_mode = 'chop';
    } elsif ($swmode =~ /^Frequency-/) {
      $switching_mode = 'freqsw';
    } elsif ($swmode eq 'Position') {
      throw OMP::Error::TranslateFail("jiggle_pssw mode not supported\n");
    } else {
      throw OMP::Error::TranslateFail("Jiggle with switch mode '$swmode' not supported\n");
    }
  } else {
    throw OMP::Error::TranslateFail("Unable to determine observing mode from observation of type '$mode'");
  }

  $info->{obs_type}       = $obs_type;
  $info->{switching_mode} = $switching_mode;
  $info->{mapping_mode}   = $mapping_mode;
  $info->{observing_mode} = $mapping_mode . '_' . $switching_mode;

  if ($self->verbose) {
    print "Observing Mode Overview:\n";
    print "\tObserving Mode: $info->{observing_mode}\n";
    print "\tObservation Type: $info->{obs_type}\n";
    print "\tMapping Mode: $info->{mapping_mode}\n";
    print "\tSwitching Mode: $info->{switching_mode}\n";
  }

  return;
}

=item B<is_fast_freqsw>

Returns true if the observation if fast frequency switch. Should only be relied
upon if it is known that the observation is frequency switch.

  $isfast = $tran->is_fast_freqsw( %info );

=cut

sub is_fast_freqsw {
  my $self = shift;
  my %info = @_;
  return ( $info{switchingMode} eq 'Frequency-Fast');
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

=item B<bandwidth_mode>

Determine the standard correlator mode for this observation
and store the result in the %info hash within each subsystem.

 $trans->bandwidth_mode( %info );

There are 2 mode designations. The spectral window bandwidth mode
(call "bwmode") is a combination of bandwidth and channel count for a
subband. If the spectral region is a hybrid mode, "bwmode" will refer
to a bandwidth mode for each subband but since this mode is identical
for each subband it is only stored as a scalar value. This method will
add a new header "nsubbands" to indicate whether the mode is
hybridised or not.  This mode is of the form BWxNCHAN. e.g. 1GHzx1024,
250MHzx8192.

The second mode designation, here known as the configuration name or
"configname" is a single string describing the entire spectral region
(hybridised or not) and is of the form BW_NSBxNCHAN, where BW is the
full bandwidth of the subsystem, NSB is the number of subbands in the
subsystem and NCHAN is the total number of channels in the subsystem
(but not the final number of channels in the hybridised spectrum). e.g.
500MHZ_2x4096

For example, configuration 500MHz_2x4096 consists of two spectral
windows each using bandwidth mode 250MHzx4096.

=cut

sub bandwidth_mode {
  my $self = shift;
  my %info = @_;

  # Get the subsystem array
  my @subs = @{ $info{freqconfig}->{subsystems} };

  # loop over each subsystem
  for my $s (@subs) {
    print "Processing subsystem...\n" if $self->verbose;

    # These are the hybridised subsystem parameters
    my $hbw = $s->{bw};
    my $olap = $s->{overlap};
    my $hchan = $s->{channels};

    # Calculate the channel width and store it
    my $chanwid = $hbw / $hchan;

    # Currently, we determine whether we are hybridised from the
    # presence of non-zero overlap
    my $nsubband;
    if ($olap > 0) {
      # assumes only ever have 2 subbands per subsystem
      $nsubband = 2;
    } else {
      $nsubband = 1;
    }

    # Number of overlaps in the hybrisisation
    my $noverlap = $nsubband - 1;

    # calculate the full bandwidth non-hybridised
    # For each overlap region we need to add on twice the overlap
    my $bw = $hbw + ( $noverlap * 2 * $olap );

    # Convert this to nearest 10 MHz to remove rounding errors
    my $mhz = int ( ( $bw / ( 1E6 * 10 ) ) + 0.5 ) * 10;

    print "\tBandwidth: $mhz MHz\n" if $self->verbose;

    # store the bandwidth in Hz for reference
    $s->{bandwidth} = $mhz * 1E6;

    # Store the bandwidth label
    my $ghz = $mhz / 1000;
    $s->{bwlabel} = ( $mhz < 1000 ? int($mhz) ."MHz" : int($ghz) . "GHz" );

    # Original number of channels before hybridisation
    # Because the OT also rounds, we need to take this to the nearest
    # even number
    my $nchan_frac = $bw / $chanwid;
    my $nchan      = OMP::General::nint( $nchan_frac / 2 ) * 2;
    $s->{nchannels_full} = $nchan;

    # and recalculate the channel width (rather than use the OT approximation
    $chanwid = $bw / $nchan;
    $s->{channwidth} = $chanwid;

    print "\tChanwid : $chanwid Hz\n" if $self->verbose;

    print "\tNumber of channels: $nchan\n" if $self->verbose;

    # number of channels per subband
    my $nchan_per_sub = $nchan / $nsubband;
    $s->{nchan_per_sub} = $nchan_per_sub;

    # calculate the bandwidth of each subband in MHz
    my $bw_per_sub = $mhz / $nsubband;

    # subband bandwidth label
    $s->{sbbwlabel} = ( $bw_per_sub < 1000 ? int($bw_per_sub). "MHz" :
			int($bw_per_sub/1000) . "GHz"
		      );

    # Store the number of subbands
    $s->{nsubbands} = $nsubband;

    # bandwidth mode
    $s->{bwmode} = $s->{sbbwlabel} . "x" . $nchan_per_sub;

    # configuration name
    $s->{configname} = $s->{bwlabel} . '_' . $nsubband . 'x' . $nchan_per_sub;

    # channel mode
    $s->{chanmode} = $nsubband . 'x' . $nchan_per_sub;

    # Get the bandwidth mode fixed info
    throw OMP::Error::FatalError("Bandwidth mode [".$s->{sbbwlabel}.
				 "] not in lookup")
      unless exists $BWMAP{$s->{sbbwlabel}};
    my %bwmap = %{ $BWMAP{ $s->{sbbwlabel} } };

    print "\tBW per sub: $bw_per_sub MHz with overlap : $olap Hz\n" if $self->verbose;

    # The usable channels are defined by the overlap
    # Simply using the channel width to calculate the offset
    # Note that the reference channel is half the overlap if we want the
    # reference channel to be aligned with the centre of the hybrid spectrum
    my $olap_in_chan = OMP::General::nint( $olap / ( 2 * $chanwid ) );

    # Note that channel numbers start at 0
    my $nch_lo = $olap_in_chan;
    my $nch_hi = $nchan_per_sub - $olap_in_chan - 1;

    print "\tUsable channel range: $nch_lo to $nch_hi\n" if $self->verbose;

    my $d_nch = $nch_hi - $nch_lo + 1;

    # Now calculate the IF setting for each subband
    # For 1 subband just choose the middle channel.
    # For 2 subbands make sure that the reference channel in each subband
    # is the centre of the overlap region and is the same for each.
    my @refchan; # Reference channel for each subband

    if ($nsubband == 1) {
      # middle usable channel
      my $nch_ref = $nch_lo + OMP::General::nint($d_nch / 2);
      push(@refchan, $nch_ref);

    } elsif ($nsubband == 2) {
      # Subband 1 is referenced to LO channel and subband 2 to HI
      push(@refchan, $nch_lo, $nch_hi );

    } else {
      # THIS ONLY WORKS FOR 2 SUBBANDS
      croak "Only 2 subbands supported not $nsubband!";
    }

    # This is the exact value of the IF and is forced to be the same
    # for all channels ( in one or 2 subband versions).
    my @sbif = map { $s->{if} } (1..$nsubband);
    $s->{if_per_subband} = \@sbif;

    # For the LO2 settings we need to offset the IF by the number of channels
    # from the beginning of the band
    my @chan_offset = map { $sbif[$_] + ($refchan[$_] * $chanwid) } (0..$#sbif);

    # Now calculate the exact LO2 for each IF
    my @lo2exact = map { $_ + $bwmap{f_park} } @chan_offset;
    $s->{lo2exact} = \@lo2exact;

    # LO2 is quantized into multiples of LO2_INCR
    my @lo2true = map {  OMP::General::nint( $_ / $LO2_INCR) * $LO2_INCR } @lo2exact;
    $s->{lo2} = \@lo2true;

    # Now calculate the error and store this for later correction
    # of the subbands in the spectral window  

    my @align_shift = map { $lo2exact[$_] - $lo2true[$_] } (0..$#lo2exact);
    $s->{align_shift} = \@align_shift;

    # Store the reference channel for each subband
    $s->{if_ref_channel} = \@refchan;

  }

}

=item B<step_time>

Returns the recommended RTS step time for this observing mode. Time is
returned in seconds.

 $rts = $trans->step_time( %info );

=cut

sub step_time {
  my $self = shift;
  my %info = @_;

  # In raster_pssw the step time is defined to be the time per 
  # output pixel. Everything else reads from config file
  my $step;
  if ($info{observing_mode} =~ /raster_pssw/ ) {
    $step = $info{sampleTime};
  } elsif ($info{observing_mode} =~ /grid_pssw/) {
    $step = OMP::Config->getData( 'acsis_translator.step_time_grid_pssw');
  } elsif ($info{observing_mode} =~ /grid_chop/) {
    $step = OMP::Config->getData( 'acsis_translator.max_time_between_chops');
  } else {
    $step = OMP::Config->getData( 'acsis_translator.step_time' );
  }

  throw OMP::Error::TranslateFail( "Calculated step time not a positive number [was $step]\n") unless $step > 0;

  return $step;
}

=item B<hardware_map>

Read the ACSIS hardware map into an object.

  $hwmap = $trans->hardware_map();

=cut

sub hardware_map {
  my $self = shift;

  my $path = File::Spec->catfile( $WIRE_DIR, 'acsis', 'cm_wire_file.txt');

  return new JCMT::ACSIS::HWMap( File => $path );
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
		  '1x1' => 'smu_1x1.dat',
		  '3x3' => 'smu_3x3.dat',
		  '4x4' => 'smu_4x4.dat',
		  'HARP'=> 'smu_harp.dat',
		  '5x5' => 'smu_5x5.dat',
		  '7x7' => 'smu_7x7.dat',
		  '9x9' => 'smu_9x9.dat',
		  '5pt' => 'smu_5point.dat',
		 );

  if (!exists $jigfiles{ $info{jigglePattern} }) {
    throw OMP::Error::TranslateFail("Jiggle requested but there is no pattern associated with pattern $info{jigglePattern}\n");
  }


  # obtin path to actual file
  my $file = File::Spec->catfile( $WIRE_DIR,'smu',$jigfiles{$info{jigglePattern}});

  # Need to read the pattern 
  my $jig = new JCMT::SMU::Jiggle( File => $file );

  # set the scale and other parameters
  my $jscal = (defined $info{scaleFactor} ? $info{scaleFactor} : 1);
  $jig->scale( $jscal );
  my $jpa = $info{jigglePA} || 0;
  $jig->posang( new Astro::Coords::Angle( $jpa, units => 'deg') );

  my $jsys = $info{jiggleSystem} || 'TRACKING';
  $jig->system( $jsys );

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

=item B<tracking_receptor>

Returns the receptor ID that should be aligned with the supplied telescope
centre. Returns undef if no special receptor should be aligned with
the tracking centre.

  $recid = $trans->tracking_receptor( $cfg, %info );

This knowledge is especially important for single pixel pointing observations
and stare observartions with HARP where there is no central pixel.

=cut

sub tracking_receptor {
  my $self = shift;
  my $cfg = shift;
  my %info = @_;

  # First decide whether we should be aligning with a specific
  # receptor?

  # Focus:   Yes
  # Stare:   Yes
  # Grid_chop: Yes
  # Jiggle   : Yes (if the jiggle pattern has a 0,0)
  # Pointing : Yes (if 5point)
  # Raster   : No

  return if ($info{observing_mode} =~ /raster/);

  # Get the jiggle pattern
  if ($info{mapping_mode} eq 'jiggle') {
    # Could also ask the configuration for Secondary information
    my $jig = $self->jig_info( %info );

    # If we are using the HARP jiggle pattern we will be wanting
    # a fully sampled map so do not offset
    return if $info{jigglePattern} eq 'HARP';

    # if we have an origin in the pattern we are probably expecting to be
    # centred on a receptor;
    return unless $jig->has_origin;
  }

  # Get the config file options
  my @configs = OMP::Config->getData( "acsis_translator.tracking_receptors" );

  # Get the actual receptors in use for this observation
  my $inst = $cfg->instrument_setup;
  throw OMP::Error::FatalError('for some reason Instrument configuration is not available. This can not happen') 
    unless defined $inst;

  # Go through the preferred receptors looking for a match
  for my $test (@configs) {
    return $test if $inst->contains_id( $test );
  }

  # If this is a 5pt pointing or a focus observation we need to choose the reference pixel
  # We have the choice of simply throwing an exception
  if (($info{obs_type} eq 'pointing') || $info{obs_type} eq 'focus') {
    return scalar($inst->reference_receptor);
  }

  # Still here? We have the choice of returning undef or choosing the
  # reference receptor. For now the consensus is to return undef.
  return;
}

=item B<calc_grid>

Calculate a grid capable of representing the supplied offsets.
Returns the size and spacing of the grid, along with a rotation angle
and centre offset. Offsets are assumed to be regular in this projection
such that distance from tangent plane is not taken into account.

 ($nx, $ny, $xsize, $ysize, $gridpa, $offx, $offy) = $self->calc_grid( $ny, @offsets );

The offsets are provided as an array of hashes with keys OFFSET_DX,
OFFSET_DY and OFFSET_PA. All are in arcsec and position angles are in
degrees. If no offsets are supplied, the grid is assumed to be a single
position at the coordinate origin.

The first argument is the Nyquist value for this wavelength in arcsec
(assuming the offsets are in arcsec). This will be used to calculate
the allowed tolerance when fitting irregular offsets into a regular
grid and also for calculating a default pixel size if only a single
pixel is required in a particular axis.

=cut

sub calc_grid {
  my $self = shift;
  my $nyquist = shift;
  my @offsets = @_;

  # default to single position at the origin
  @offsets = ( { OFFSET_PA => 0,
		 OFFSET_DX => 0,
		 OFFSET_DY => 0,
	       }) unless @offsets;

  # Rotate to fixed coordinate frame
  my $refpa = $offsets[0]->{OFFSET_PA};
  @offsets = $self->align_offsets( $refpa, @offsets);

  # Get the array of x coordinates
  my @x = map { $_->{OFFSET_DX} } @offsets;
  my @y = map { $_->{OFFSET_DY} } @offsets;

  # Calculate stats
  my ($xmin, $xmax, $xcen, $xspan, $nx, $dx) = _calc_offset_stats( $nyquist, @x);
  my ($ymin, $ymax, $ycen, $yspan, $ny, $dy) = _calc_offset_stats( $nyquist, @y);

  return ($nx, $ny, $dx, $dy, $refpa, $xcen, $ycen);
}

# Routine to calculate stats from a sequence relevant for grid making
# Requires Nyquist value in arcsec plus an array of X or Y offset positions
# Returns the min, max, centre, span, number of pixels, pixel width
# Function, not method

# Attempt is made never to use fractional arcsec in results.

sub _calc_offset_stats {
  my $nyquist = shift;
  my @off = @_;

  # Tolerance is fraction of Nyquist
  my $tol = 0.2 * $nyquist;

  # Now remove duplicates. Order is irrelevant
  my %dummy = map { $_ => undef } @off;

  # and sort into order (making sure we format)
  my @sort = sort { $a <=> $b } map { sprintf("%.3f", $_ ) } keys %dummy;

  # if we only have one position we can return early here
  return ($sort[0], $sort[0], $sort[0], 0, 1, $nyquist) if @sort == 1;

  # Then find the extent of the map
  my $max = $sort[-1];
  my $min = $sort[0];

  # Extent of the map
  my $span = $max - $min;
  my $cen = ( $max + $min ) / 2;
  print "Input offset parameters: Span = $span ($min .. $max) Centre = $cen\n" if $DEBUG;

  # if we only have two positions, return early
  return ($min, $max, $cen, $span, 2, $span) if @sort == 2;

  # Now calculate the gaps between each position
  my @gap = map { abs($sort[$_] - $sort[$_-1]) } (1..$#sort);

  # Now we have to work out a pixel scale that will allow these
  # offsets to fall on the same grid within the tolerance
  # start by sorting the gap and picking a value greater than tol
  my @sortgap = sort { $a <=> $b } @gap;
  my $trial;
  for my $g (@sortgap) {
    if ($g > $tol) {
      $trial = $g;
      last;
    }
  }

  # if none of the gaps are greater than the tolerance we actually have a single
  # pixel
  return ($min, $max, $cen, $span, 1, $nyquist) unless defined $trial;

  # Starting position is interesting since we could end up with a 
  # starting offset that is slightly off the "real" grid and with a slight push
  # end up with a regular grid if we had started from some other position.
  # To try to mitigate this we move the reference pixel to the nearest integer
  # pixel if the tolerance allows it

  # Choose a reference pixel in the middle of the sorted range
  # Reference "pixel" is simply the smallest value in the sequence
  my $refpix = $sort[0];

  # Move to the nearest int if the nearest int is less than the tol
  # away
  my $nearint = OMP::General::nint( $refpix );
  if (abs($refpix - $nearint) < $tol) {
    $refpix = $nearint;
  }

  # Store the reference and try to adjust it until we find a match
  # or until the trial is smaller than the tolerance
  my $reftrial = $trial;
  my $mod = 2; # trial modifier
  OUTER: while ($trial > $tol) {

    # Calculate the tolerance in units of trial pixels
    my $tolpix = $tol / $trial;

    # see whether the sequence fits with this trial
    for my $t (@sort) {

      # first calculate the distance between this and the reference
      # in units of $trial pixels. This will always be positive
      # because we always start from the sorted list.
      my $pixpos = ( $t - $refpix ) / $trial;

      # Now in an ideal world we have an integer match. Found the
      # pixel error
      my $pixerr = abs( $pixpos - int($pixpos) );

      # Now compare this with the tolerance in units of pixels
      if ($pixerr > $tol) {
	# This trial did not work. Calculate a new one by dividing
	# original by an increasing factor (which will stop when we hit
	# the tolerance)
	$trial = $reftrial / $mod;
	$mod++;
	next OUTER;
      }
    }

    # if we get to this point, we must have verified all positions
    last;
  }

  # whatever happens we get a pixel value. Either a valid one or one that
  # is smaller than the tolerance (and so guaranteed to be okay).
  # we add one because we are counting fence posts not gaps between fence posts
  my $npix = int( $span / $trial ) + 1;

  # Sometimes the fractional arcsecs pixel sizes can be slightly wrong so 
  # now we are in the ballpark we step through the pixel grid and work out the
  # minimum error for each input pixel whilst adjusting the pixel size in increments
  # of 1 arcsec. This does not use tolerance.

  # Results hash
  my %best;

  # Work out the array of grid points
  my $spacing = $trial;

  # Lowest RMS so far
  my $lowest_rms;

  # Start the grid from the lower end (the only point we know about)
  my $range = 1.0; # arcsec

  # amount to adjust pixel size
  my $pixrange = 1.0; # arcsec

  for (my $pixtweak = -$pixrange; $pixtweak <= $pixrange; $pixtweak += 0.05 ) {

    # restrict to 3 decimal places
    $spacing = sprintf( "%.3f", $trial + $pixtweak);

    for (my $refoffset = -$range; $refoffset <= $range; $refoffset += 0.05) {
      my $trialref = $min + $refoffset;;

      my @grid = map { $trialref + ($_*$spacing) }  (0 .. ($npix-1) );

#      print "Grid: ".join(",",@grid)."\n";

      # Calculate the residual from that grid by comparing with @sort
      # use the fact that we are sorted
#      my $residual = 0.0;
      my $halfpix = $spacing / 2;
      my $i = 0; # grid index (also sorted)
      my @errors;

    CMP: for my $cmp (@sort) {

	# search through the grid until we find a pixel containing this value
	while ( $i <= $#grid ) {
	  my $startpix = $grid[$i] - $halfpix;
	  my $endpix = $grid[$i] + $halfpix;
	  if ($cmp >= $startpix && $cmp <= $endpix ) {
	    # found the pixel abort from loop
	    push(@errors, ( $grid[$i] - $cmp ) );
	    next CMP;
	  } elsif ( $cmp < $startpix ) {
	    if ($i == 0) {
	      #print "Position $cmp lies below pixel $i with bounds $startpix -> $endpix\n";
	      push(@errors, 1E5); # make it highly unlikely
	    } else {
	      # Probably a rounding error
	      if (abs($cmp-$startpix) < 1.0E-10) {
		push(@errors, ( $grid[$i] - $cmp ) );
	      } else {
		croak "Somehow we missed pixel $startpix <= $cmp <= $endpix (grid[$i] = $grid[$i])\n";
	      }
	    }
	    next CMP;
	  }
	
	  # try next grid position
	  $i++;
	}

	if ($i > $#grid) {
	  my $endpix = $grid[$#grid] + $halfpix;
	  #print "Position $cmp lies above pixel $#grid ( > $endpix)\n";
	  push(@errors, 1E5); # Make it highly unlikely
	}

      }

      my $rms = _find_rms( @errors );

      if ($rms < 0.1) {
#	print "Grid: ".join(",",@grid)."\n";
#	print "Sort: ". join(",",@sort). "\n";
#	print "Rms= $rms -  $spacing arcsec from $grid[0] to $grid[$#grid]\n";
      }

      if (!defined $lowest_rms || abs($rms) < $lowest_rms) {
	$lowest_rms = $rms;

	# Recalculate the centre location based on this grid
	# Assume that the reference pixel for "0 1 2 3"   is "2" (acsis assumes we align with "2")
	# Assume that the reference pixel for "0 1 2 3 4" is "2" (middle pixel)
	# ACSIS *always* assumes that the "ref pix" is  int(N/2)+1
	# but we start counting at 0, not 1 so subtract an extra 1
	my $midpoint = int( scalar(@grid) / 2 ) + 1 - 1;

        my $temp_centre; 
        if( scalar(@grid)%2)
         {#print "Odd\n";
          $temp_centre = $grid[$midpoint];
          } 
          else 
          {#print "Even\n";
           #$temp_centre = $grid[$midpoint];
	   $temp_centre=  $grid[$midpoint] - ($grid[$midpoint]-$grid[$midpoint-1])/2.0;
          }

	#print "Temp centre --> $temp_centre \n";
        
	%best = (
		 rms => $lowest_rms,
		 spacing => $spacing,
		 centre => $temp_centre,
		 span => ( $grid[$#grid] - $grid[0] ),
		 min  => $grid[0],
		 max  => $grid[$#grid],
		);
      }
    }
  }


  # Select the best value from the minimization
  $span = $best{span};
  $min  = $best{min};
  $max  = $best{max};
  $trial = $best{spacing};
  $cen  = $best{centre};

  print "Output grid parameters : Span = $span ($min .. $max) Centre = $cen Npix = $npix RMS = $best{rms}\n"
    if $DEBUG;

  return ($min, $max, $cen, $span, $npix, $trial );

}

# Find the rms of the supplied numbers 
sub _find_rms {
  my @num = @_;
  return 0 unless @num;

  # Find the sum of the squares
  my $sumsq = 0;
  for my $n (@num) {
    $sumsq += ($n * $n );
  }

  # Mean of the squares
  my $mean = $sumsq / scalar(@num);

  # square root to get rms
  return sqrt($mean);
}

=item B<_to_acoff>

Convert an array of references to hashes containing keys of OFFSET_DX, OFFSET_DY
and OFFSET_PA to an array of Astro::Coords::Offset objects.

   @offsets = $self->_to_acoff( @input );

If the first argument is already an Astro::Coords::Offset object all
inputs are returned as outputs unchanged.

=cut

sub _to_acoff {
  my $self = shift;

  if (UNIVERSAL::isa($_[0], "Astro::Coords::Offset" )) {
    return @_;
  }

  return map { new Astro::Coords::Offset( $_->{OFFSET_DX},
					  $_->{OFFSET_DY},
					  posang => $_->{OFFSET_PA},
					  system => $_->{SYSTEM},
					) } @_;
}

=item B<_to_offhash>

Convert an array of C<Astro::Coords::Offset> objects to an array of
hash references containing keys OFFSET_DX, OFFSET_DY and OFFSET_PA
(all pointing to scalar non-objects in arcsec and degrees).

   @offsets = $self->_to_offhash( @input );

If the first element looks like an unblessed hash ref all args
will be returned unmodified.

=cut

sub _to_offhash {
  my $self = shift;

  if (!blessed( $_[0] ) && exists $_[0]->{OFFSET_DX} ) {
    return @_;
  }

  return map {
    {
      OFFSET_DX => ($_->offsets)[0]->arcsec,
	OFFSET_DY => ($_->offsets)[1]->arcsec,
	  OFFSET_PA => $_->posang->degrees,
	    SYSTEM => $_->system,
	  }
  } @_;
}

=item B<convolve_footprint>

Return the convolution of the receiver footprint with the supplied
map coordinates to be observed. The receiver footprint is in the
form of a reference to an array of receptor positions.

  @convolved = $trans->convolve_footprint( $matchpa, \@receptors, \@map );

Will not work if the coordinate system of the receiver is different
from the coordinate system of the offsets but the routine assumes that
FPLANE == TRACKING for the purposes of this calculation. This will be
correct for everything except HARP with a broken image rotator. If the
image rotator is broken then this will calculate the positions as
if it was working.

The 'matchpa' parameter controls whether the position angle stored in
the receptor array should be used when calculating the new grid or
whether it is assumed that the instrument PA can be rotated to match
the map PA. If true (eg HARP with image rotator) then the PA of the
first map point will be the chosen PA for all the convolved points.

All positions will be corrected to the position angle of the first
position in the map array.

Offsets can be supplied as an array of references to hashes with
keys OFFSET_X, OFFSET_Y, SYSTEM and OFFSET_PA

=cut

sub convolve_footprint {
  my $self = shift;

  my ($matchpa, $rec, $map) = @_;

  return @$rec if !@$map;

  # Get the reference pa
  my $refpa = $map->[0]->{OFFSET_PA};
  my $refsys = $map->[0]->{SYSTEM};
  $refsys = "TRACKING" if !defined $refsys;

  # Rotate all map coordinates to this position angle
  my @maprot = $self->align_offsets( $refpa, @$map);

  # If we are able to match the coordinate rotation of the
  # map with the receiver we do not have to normalize coordinates
  # to the map frame since that is already done
  my @recrot;
  if ($matchpa) {
    @recrot = @$rec;
  } else {
    @recrot = $self->align_offsets( $refpa, @$rec );
  }

  # Now for each receptor we need to go through each map pixel
  # and add the receptor offset
  my @conv;

  for my $recpixel (@recrot) {
    my $rx = $recpixel->{OFFSET_DX};
    my $ry = $recpixel->{OFFSET_DY};

    for my $mappixel (@maprot) {
      my $mx = $mappixel->{OFFSET_DX};
      my $my = $mappixel->{OFFSET_DY};

      push(@conv, { OFFSET_DX => ( $rx+$mx ),
		    OFFSET_DY => ( $ry+$my ),
		    OFFSET_PA => $refpa,
		    SYSTEM    => $refsys,
		  } );
    }
  }

  return @conv;
}

=item B<getCubeInfo>

Retrieve the hash of cube information from the ACSIS config. Takes a full JAC::Config
object.

 %cubes = $trans->getCubeInfo( $cfg );

=cut

sub getCubeInfo {
  my $self = shift;
  my $cfg = shift;

  # get the acsis configuration
  my $acsis = $cfg->acsis;
  throw OMP::Error::FatalError('for some reason ACSIS setup is not available. This can not happen') unless defined $acsis;

  # get the spectral window information
  my $cubelist = $acsis->cube_list();
  throw OMP::Error::FatalError('for some reason Cube configuration is not available. This can not happen') unless defined $cubelist;

    return $cubelist->cubes;
}

=item B<_read_file>

Read a file and return the contents as a single string.

 $string = _read_file( $filename );

Not a method. Could probably use the slurp function.

=cut

sub _read_file {
  my $file = shift;
  open (my $fh, "< $file") or 
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

The following methods are in the OMP::Translator::ACSIS::Header
namespace. They are all given the observation summary hash as argument
and the current Config object, and they return the value that should
be used in the header.

  $value = OMP::Translator::ACSIS::Header->getProject( $cfg, %info );

=cut

package OMP::Translator::ACSIS::Header;

sub getProject {
  my $class = shift;
  my $cfg = shift;
  my %info = @_;
  return $info{PROJECTID};
}

sub getMSBID {
  my $class = shift;
  my $cfg = shift;
  my %info = @_;
  return $info{MSBID};
}

sub getStandard {
  my $class = shift;
  my $cfg = shift;
  my %info = @_;
  return $info{standard};
}

sub getDRRecipe {
  my $class = shift;
  my $cfg = shift;
  my %info = @_;

  # This is where we insert an OT override once that override is possible
  # it will need to know which parameters to override

  if ($info{MODE} =~ /Pointing/) {
    return 'REDUCE_POINTING';
  } elsif ($info{MODE} =~ /Focus/) {
    return 'REDUCE_FOCUS';
  } else {
    return 'REDUCE_CUBE';
  }

}

sub getDRGroup {
  my $class = shift;
  my $cfg = shift;

  # Not quite sure how to handle this in the translator since there are no
  # hints from the OT and the DR is probably better at doing this.
  return 'UNKNOWN';
}

# Need to get survey information from the TOML

sub getSurveyName {
  my $class = shift;
  my $cfg = shift;
  my %info = @_;
  return 'NONE';
}

sub getSurveyID {
  return 'NONE';
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
sub getTrkRecep {
  my $class = shift;
  my $cfg = shift;

  my $tcs = $cfg->tcs;
  throw OMP::Error::FatalError('for some reason TCS configuration is not available. This can not happen')
    unless defined $tcs;
  my $ap = $tcs->aperture_name;
  return ( defined $ap ? $ap : "" );
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
      return "". $refpos->ra2000;
    }
  }
  return "UNDEFINED";
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
      return "". $refpos->dec2000;
    }
  }
  return "UNDEFINED";
}


# For jiggle: This is the number of nod sets required to build up the pattern
#             ie  Total number of points / N_JIG_ON

# For grid: returns the number of points in the grid

# For scan: Estimate at the number of scans

sub getNumExposures {
  my $class = shift;
  my $cfg = shift;

  warn "******** Do not calculate Number of exposures correctly\n"
    if OMP::Translator::ACSIS->verbose;;
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

Copyright 2003-2006 Particle Physics and Astronomy Research Council.
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
