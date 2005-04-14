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

use Net::Domain;
use File::Spec;
use Astro::Coords::Offset;
use List::Util qw/ min max /;

# Need to find the OCS Config (temporary kluge)
#use blib '/home/timj/dev/perlmods/JAC/OCS/Config/blib';

use JAC::OCS::Config;

use OMP::Config;
use OMP::Error;

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
	      );

# Telescope diameter in metres
use constant DIAM => 15;

=head1 METHODS

=over 4

=item B<translate>

Converts a single MSB object to one or many ACSIS Configs.
It is assumed that this MSB will refer to an ACSIS observation
(and has been prefiltered by the caller, usually C<OMP::Translator>).
Always returns the configs as an array of C<JAC::OCS::Config> objects.

  @configs = OMP::Translate->translate( $sp );

It is the responsibility of the caller to write these objects.

=cut

sub translate {
  my $self = shift;
  my $msb = shift;
  my $asdata = shift;

  # Project
  my $projectid = $msb->projectID;

  # OT version
  my $otver = $msb->ot_version;
  print "OTVERS: $otver \n";

  # Correct Stare and Jiggle observations such that multiple offsets are
  # combined
  # Note that there may be a requirement to convert non-regular offset
  # patterns into individual observations rather than having a very sparse
  # but large grid
  $self->correct_offsets( $msb, "Stare", "Jiggle" );

  # Now unroll the MSB into constituent observations details
  my @configs;
  for my $obs ($msb->unroll_obs) {

    # Create blank configuration
    my $cfg = new JAC::OCS::Config;

    # Add comment
    $cfg->comment( "Translated on ". gmtime() ."UT on host ".
		   Net::Domain::hostfqdn() . " by $ENV{USER} \n".
		   "using Translator version $VERSION on an MSB created by the OT version $otver\n");

    # Observation summary
    $self->obs_summary( $cfg, %$obs );

    # configure the basic TCS parameters
    $self->tcs_config( $cfg, %$obs );

    # Instrument config
    $self->instrument_config( $cfg, %$obs );

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

    # Store the completed config
    push(@configs, $cfg);

    print $cfg;

    last;
  }


  # return the config objects
  return @configs;
}

=item B<debug>

Method to enable and disable global debugging state.

  OMP::Translator::DAS->debug( 1 );

=cut

sub debug {
  my $class = shift;
  my $state = shift;

  $DEBUG = ($state ? 1 : 0 );
}

=item B<transdir>

Override the default translation directory.

  OMP::Translator::DAS->transdir( $dir );

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
  my %summary = $self->observing_mode( %info );

  $obs->mapping_mode( $summary{mapping_mode} );
  $obs->switching_mode( defined $summary{switching_mode} ? $summary{switching_mode} : 'none' );
  $obs->type( $summary{obs_type} );

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
  $self->tcs_base( $tcs, %info );

  # observing area
  $self->observing_area( $tcs, %info );

  # Then secondary mirror
  $self->secondary_mirror( $tcs, %info );

  # Slew and rotator require the duration to be known which can
  # only be calculated when the configuration is complete

  # Store it
  $cfg->tcs( $tcs );
}

=item B<tcs_base>

Calculate the position information (SCIENCE and REFERENCE)
and store in the TCS object.

  $trans->tcs_base( $tcs, %info );

where $tcs is a C<JAC::OCS::Config::TCS> object.

=cut

sub tcs_base {
  my $self = shift;
  my $tcs = shift;
  my %info = @_;

  # First get all the coordinate tags
  my %tags = %{ $info{coordtags} };

  # and augment with the SCIENCE tag
  # we only needs the Astro::Coords object in this case
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
      $b->offset( $off );
    }

    # The OT can only specify tracking as the TRACKING system
    $b->tracking_system ( 'TRACKING' );

    $base{$t} = $b;
  }

  $tcs->tags( %base );
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

  my $obsmode = $info{MODE};

  my $oa = new JAC::OCS::Config::TCS::obsArea();

  # Offset [needs work in unroll_obs to fix this for jiggle so that
  # we get a single configuration]

  # There is only one position angle in an observing Area so the
  # offsets have to be in the same frame as the map if we are
  # defining a map area


  if ($obsmode eq 'SpIterRasterObs') {

    # Map specification
    $oa->posang( new Astro::Coords::Angle( $info{MAP_PA}, units => 'deg'));
    $oa->maparea( HEIGHT => $info{MAP_HEIGHT},
		  WIDTH => $info{MAP_WIDTH});

    # Scan specification
    $oa->scan( VELOCITY => $info{SCAN_VELOCITY},
	       DY => $info{SCAN_DY},
	       SYSTEM => $info{SCAN_SYSTEM},
	     );

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

  my $obsmode = $info{MODE};
  my $sw_mode = $info{switchingMode};

  # Default to CONTINUOUS mode
  $smu->motion( "CONTINUOUS" );

  # Configure the chop parameters
  if ($sw_mode eq 'Chop') {
    throw OMP::Error::TranslateFail("No chop defined for chopped observation!")
      unless (defined $info{CHOP_THROW} && defined $info{CHOP_PA} && 
	      defined $info{CHOP_SYSTEM} );

    $smu->chop( THROW => $info{CHOP_THROW},
		PA => new Astro::Coords::Angle( $info{CHOP_PA}, units => 'deg' ),
		SYSTEM => $info{CHOP_SYSTEM},
	      );
  }

  # Jiggling

  # Jiggle pattern name and number of points in the pattern
  my %jig_patterns = (
		      '3x3' => { name => 'smu_3x3.dat',
				 npts => 9 },
		      '5x5' => { name => 'smu_5x5.dat',
				 npts => 25 },
		      '7x7' => { name => 'smu_7x7.dat',
				 npts => 49 },
		      '9x9' => { name => 'smu_9x9.dat',
				 npts => 81 },
		     );

  if ($obsmode eq 'SpIterJiggleObs') {


    if (!exists $jig_patterns{ $info{jigglePattern} }) {
      throw OMP::Error::TranslateFail("Jiggle requested but there is no pattern associated with pattern $info{jigglePattern}\n");
    }

    $smu->jiggle( SYSTEM => $info{jiggleSystem},
		  SCALE => $info{scaleFactor},
		  NAME => $jig_patterns{ $info{jigglePattern} }->{name},
		  PA => new Astro::Coords::Angle( $info{jigglePA}, units => 'deg'),
		);

  }

  # Relative timing required if we are jiggling and chopping
  if ($smu->smu_mode() eq 'jiggle_chop') {
    # First get the canonical RTS step time. This controls the time spent on each
    # jiggle position.
    my $rts = $self->step_time( %info );

    # total number of points in pattern
    my $npts = $jig_patterns{$info{jigglePattern}}->{npts};

    # Now the number of jiggles per chop position is dependent on the
    # maximum amount of time we want to spend per chop position and the constraint
    # that n_jigs_on must be divisible into the total number of jiggle positions.

    # Let's say this is maximum time between chops in seconds
    my $tmax_per_chop = 1.0;

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
      # of steps we have just completed in the "on".
      $smu->timing( N_JIGS_ON => $njigs,
		    N_CYC_OFF => int( sqrt($njigs) + 0.5 ),
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
  $fe->rest_frequency( $fc{restFrequency} );
  $fe->sb_mode( $fc{sideBandMode} );

  # How to handle 'best'?
  $fe->sideband( $fc{sideBand} );

  # doppler mode
  $fe->doppler( ELEC_TUNING => 'GROUP', MECH_TUNING => 'ONCE' );

  # Frequency offset
  $fe->freq_off_scale( 0 );

  # Mask selection depends on observing mode but for now we can just
  # make sure that all available pixels are enabled
  my $inst = $cfg->instrument_setup();
  throw OMP::Error::FatalError('for some reason instrument setup is not available. This can not happen') unless defined $inst;

  my %receptors = $inst->receptors;

  my %mask;
  for my $id ( keys %receptors ) {
    my $status = $receptors{$id}{health};
    $mask{$id} = ($status eq 'UNSTABLE' ? 'ON' : $status);
  }
  $fe->mask( %mask );

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


  # do not know enough about ROTATOR behaviour yet
  $tcs->rotator( SLEW_OPTION => 'TRACK_TIME',
		 SYSTEM => 'TRACKING'
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
      my $val = $pkg->$method( %info );
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

  #$cfg->header( $hdr );

}

=item B<rts_config>

Configure the RTS

 $trans->rts_config( $cfg, %info );

=cut

sub rts_config {
  my $self = shift;
  my $cfg = shift;
  my %info = @_;

  # the RTS information is read from a wiring file
  # indexed by observing mode
  my $mode = $self->observing_mode( %info );

  my $file = File::Spec->catfile( $WIRE_DIR, 'rts',
				  $mode .".xml");
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

  # Get the observing mode
  my $mode = $self->observing_mode( %info );

  # need to determine recipe name
  # use hash indexed by observing mode
  my %JOSREC = (
		focus       => 'focus',
		pointing    => 'pointing',
		jiggle_freqsw => ( $self->is_fast_freqsw(%info) ? 'fast_jiggle_fsw' : 'slow_jiggle_fsw'),
		jiggle_chop => 'jiggle_chop',
		grid_pssw   => 'raster_or_grid_pssw',
		raster_pssw => 'raster_or_grid_pssw',
	       );
  if (exists $JOSREC{$mode}) {
    $jos->recipe( $JOSREC{$mode} );
  } else {
    throw OMP::Error::TranslateFail( "Unable to determine jos recipe from observing mode '$mode'");
  }

  # Now parameters depends on that recipe name

  # Raster

  if (exists $info{rowsPerRef}) {
    # need at least one row
    $info{rowsPerRef} = 1 if $info{rowsPerRef} < 1;
    $jos->rows_per_ref( $info{rowsPerRef} );
  }

  # we have rows per cal but the JOS needs refs_per_cal
  if (exists $info{rowsPerRef} && exists $info{rowsPerCal}) {
    # rows per ref should be > 0
    $jos->refs_per_cal( $info{rowsPerCal} / $info{rowsPerRef} );
  }

  # Tasks can be worked out by seeing which objects are
  # present in the config object. It is hard for the JOS object
  # to work it out itself without having a reference to the parent
  # object
  my %tasks;


  # store it
  $cfg->jos( $jos );

}

=item B<correlator>

Read the relevant correlator information from template files.

  $trans->correlator( $cfg, %info );

=cut

sub correlator {
  my $self = shift;
  my $cfg = shift;
  my %info = @_;

  # get the acsis configuration
  my $acsis = $cfg->acsis;
  throw OMP::Error::FatalError('for some reason ACSIS setup is not available. This can not happen') unless defined $acsis;

  # Get the channel mode
  # Note that only the first subsystem is currently recognized
  my $subsys = $info{freqconfig}->{subsystems}->[0];

  # Create the new machine table
  my $root = $self->ocs_frontend( $info{instrument}, 1 ) . '_correlator_' . 
                                  $subsys->{chanmode} . '.ent';
  my $templ = File::Spec->catfile( $WIRE_DIR, 'acsis', $root);

  # This entity xml file has both ACSIS_corr and ACSIS_IF.
  # We could read this directly into an ACSIS config object and then extract out
  # the bits we need but we would first need to make the ACSIS object less picky
  # when it finds there are missing XML chunks. For now do it in 2 reads.
  my $corr = new JAC::OCS::Config::ACSIS::ACSIS_CORR( EntityFile => $templ, validation => 0 );
  my $if = new JAC::OCS::Config::ACSIS::ACSIS_IF( EntityFile => $templ, validation => 0 );

  $acsis->acsis_corr( $corr );
  $acsis->acsis_if( $if );

  # For now, assume that the ACSIS_map xml can also be read from the template
  # file and that our naming convention for spectral windows matches that used
  # in the template file
  my $map = new JAC::OCS::Config::ACSIS::ACSIS_MAP( EntityFile => $templ, validation => 0 );
  $acsis->acsis_map( $map );

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
    # window object(s)
    my @ifcoords = map {  new JAC::OCS::Config::ACSIS::IFCoord( if_freq => $ss->{if},
						     nchannels => $ss->{nchan_per_sub},
						     channel_width => $ss->{channwidth},
						     ref_channel => $_
						   ) } @{ $ss->{if_ref_channel} };

    # We only calculate baselines for the hybridised spectral windows
    if (defined $frac) {
      # Baseline depends on number of hybridised channels
      my $nchan_full = $ss->{channels};
      my $nchan_bl = int($nchan_full * $frac / 2 );
      @baselines = (
	   new JAC::OCS::Config::Interval( Units => 'channels',
					   Min => 0, Max => $nchan_bl),
	   new JAC::OCS::Config::Interval( Units => 'channels',
					   Min => ($nchan_full - $nchan_bl),
					   Max => $nchan_full),
	  );
    }
    $spw->baseline_region( @baselines ) if @baselines;

    # hybrid or not?
    if ($ss->{nsubbands} == 1) {
      # no hybrid. Just store it
      $spw->window( 'truncate' );
      $spw->align_shift(0);
      $spw->bandwidth_mode( $ss->{bwmode});
      $spw->if_coordinate( $ifcoords[0] );

    } elsif ($ss->{nsubbands} == 2) {
      my %hybrid;
      my $sbcount = 1;
      for my $if (@ifcoords) {
	my $sp = new JAC::OCS::Config::ACSIS::SpectralWindow;
	$sp->bandwidth_mode( $ss->{bwmode} );
	$sp->if_coordinate( $if );
	$sp->fe_sideband( $fe_sign );
	$sp->align_shift(0);
	$sp->rest_freq_ref( $ss->{rest_freq_ref});
	$sp->window( $dr{window_type} );
	$hybrid{"SPW". $spwcount . "." . $sbcount} = $sp;
	$sbcount++;
      }

      # Store the subbands
      $spw->subbands( %hybrid );

      # Create global IF coordinate object for the hybrid. For some reason
      # this does not take overlap into account
      my $if = new JAC::OCS::Config::ACSIS::IFCoord( if_freq => $ss->{if},
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

    $spwcount++;
  }

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

  # Get the observing mode
  my $mode = $self->observing_mode( %info );
  my $root = $mode . '_dr_recipe.ent';
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
  $mode =~ s/_/\//g;
  $acsis->red_obs_mode( $mode );
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

  # get the observing mode
  my $obsmode = $self->observing_mode( %info );

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
    $cube->group_centre( $info{coords} );

    # Calculate Nyquist value for this map
    my $nyq = $self->nyquist( %info );

    # Until HARP comes we use TopHat for all observing modes
    # HARP without image rotator will require Gaussian.
    # This will need support for rotated coordinate frames in the gridder
    my $grid_func = "TopHat";
    $grid_func = "Gaussian" if $obsmode =~ /raster/;
    $cube->grid_function( $grid_func );

    # The size and number of pixels depends on the observing mode.
    # For raster, we have a regular grid but the 
    my ($nx, $ny, $mappa, $xsiz, $ysiz, $offx, $offy);
    if ($obsmode =~ /raster/) {
      # This will be more complicated for HARP since DY will possibly
      # be larger and we will need to take the receptor spacing into account

      # For single pixel instrument define the Y pixel as the spacing
      # between scan rows
      $ysiz = $info{SCAN_DY};

      # The X spacing should be half Nyquist or the Y spacing (whichever is smallest)
      $xsiz = min ($ysiz, $nyq->arcsec / 2 );

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

    } elsif ($obsmode =~ /grid|jiggle/i) {
      # Need to know:
      #  - the extent of the offset grid
      #  - the extent of the jiggle pattern
      #  - the footprint of the array
      # GRID + single pixel is easy since it is just the offset pattern
      my @offsets;
      @offsets = @{$info{offsets}} if (exists $info{offsets} && defined $info{offsets});
      ($nx, $ny, $xsiz, $ysiz, $mappa, $offx, $offy) = $self->calc_grid( $self->nyquist(%info)->arcsec,
									 @offsets );

    } else {
      # pointing is going to be a map based on the jiggle offset
      # and will be different for HARP
      # focus will probably be a single spectrum in continuum mode

      throw OMP::Error::TranslateFail("Do not yet know how to size a cube for mode $obsmode");
    }


    # the gridder can not handle a rotated coordinate frame so we now
    # need to rotate the map dimensions to unrotated frame
    if ($mappa != 0) {
      throw OMP::Error::TranslateFail("Do not yet handle rotated output cubes");
    }

    throw OMP::Error::TranslateFail( "Unable to determine X pixel size")
      unless defined $xsiz;
    throw OMP::Error::TranslateFail( "Unable to determine Y pixel size")
      unless defined $ysiz;

    # Store the parameters
    $cube->pixsize( new Astro::Coords::Angle($xsiz, units => 'arcsec'),
		    new Astro::Coords::Angle($ysiz, units => 'arcsec'));
    $cube->npix( $nx, $ny );

    # offset in pixels
    $cube->offset( $offx / $xsiz, $offy / $ysiz);

    # Decide whether the grid is regridding in sky coordinates or in AZEL
    # Focus and Pointing are AZEL
    if ($obsmode =~ /point|focus/) {
      $cube->tcs_coord( 'AZEL' );
    } else {
      $cube->tcs_coord( 'TRACKING' );
    }

    # Currently always use TAN projection since that is what SCUBA uses
    $cube->projection( "TAN" );

    # Gaussian requires a FWHM and truncation radius
    if ($grid_func eq 'Gaussian') {

      # For an oversampled map, the SCUBA regridder has been analysed empirically 
      # to determine an optimum smoothing gaussian HWHM of lambda / 5d ( 0.4 of Nyquist).
      # This compromises smoothness vs beam size. For ACSIS, we are really limited
      # by the pixel size so our FWHM should be related to the larger value
      # of  lambda/2.5D, Ypix or Xpix

      # Use the SCUBA optimum ratios derived by Claire Chandler of
      # HWHM = lambda / 5D (ie 0.4 of Nyquist) or FWHM = lambda / 2.5D
      # (or 0.8 Nyquist)
      my $fwhm = max ( $nyq->arcsec * 0.8, $xsiz, $ysiz );
      $cube->fwhm( $fwhm );

      # Truncation radius is half the pixel size for TopHat
      # For Gausian we use 3 HWHM (that's what SCUBA used)
      $cube->truncation_radius( $fwhm * 1.5 );
    }

    $cubes{$cubid} = $cube;
    $count++;
  }

  # Store it
  $cl->cubes( %cubes );

  print "Start to stringify...\n";
  print $cl->stringify;
  print "DONE\n";

  $acsis->cube_list( $cl );

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

  # Read the new machine table
  my $machtable_file = File::Spec->catfile( $WIRE_DIR, 'acsis', 'machine_table_xml.ent');
  my $machtable = _read_file( $machtable_file );

  # Read the monitor layout
  my $monlay_file = File::Spec->catfile( $WIRE_DIR, 'acsis', 'monitor_layout.ent');
  my $monlay = _read_file( $monlay_file );

  # Read the template process_layout file
  my $lay_file = File::Spec->catfile( $WIRE_DIR, 'acsis', 'layout.ent');
  my $layout = _read_file( $lay_file );

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
(not from the OCS configuration).

 $obsmode = $trans->observing_mode( %info );

The standard modes are:

  focus
  pointing
  jiggle_freqsw
  jiggle_chop
  grid_pssw
  raster_pssw

Note that there is no explicit slow vs fast jiggle switch mode
returned from this routine since more subsystems ignore the difference
than care about the difference.

In list context the information is returned in a hash with keys
"mapping_mode", "switching_mode" and "obs_type" (see also the
C<obs_summary> method).

 %details = $trans->observing_mode( %info );

=cut

sub observing_mode {
  my $self = shift;
  my %info = @_;

  use Data::Dumper;
  print Dumper( \%info );


  my %summary;

  # assume science
  $summary{obs_type} = 'science';

  my $mode = $info{MODE};
  my $swmode = $info{switchingMode};

  if ($mode eq 'SpIterRasterObs') {
    $summary{mapping_mode} = 'raster';
    if ($swmode eq 'Nod') {
      $summary{switching_mode} = 'pssw';
    } elsif ($swmode eq 'Chop') {
      throw OMP::Error::TranslateFail("raster_chop not yet supported\n");
      $summary{switching_mode} = 'chop';
    } else {
      throw OMP::Error::TranslateFail("Raster with switch mode $swmode not supported\n");
    }
  } elsif ($mode eq 'SpIterPointingObs') {
    $summary{mapping_mode} = 'jiggle';
    $summary{switching_mode} = 'chop';
    $summary{obs_type} = 'pointing';
  } elsif ($mode eq 'SpIterFocusObs' ) {
    $summary{mapping_mode} = 'jiggle';
    $summary{switching_mode} = 'chop';
    $summary{obs_type} = 'focus';
  } elsif ($mode eq 'SpIterStareObs' ) {
    # check switch mode
    if ($swmode eq 'Nod') {
      $summary{mapping_mode} = 'grid';
      $summary{switching_mode} = 'pssw';
    } elsif ($swmode eq 'Chop') {
      $summary{mapping_mode} = 'jiggle';
      $summary{switching_mode} = 'chop';
    } else {
      throw OMP::Error::TranslateFail("Sample with switch mode $swmode not supported\n");
    }
  } elsif ($mode eq 'SpIterJiggleObs' ) {
    # depends on switch mode
    $summary{mapping_mode} = 'jiggle';
    if ($swmode eq 'Chop') {
      $summary{switching_mode} = 'chop';
    } elsif ($swmode =~ /^Frequency-/) {
      $summary{switching_mode} = 'freqsw';
    } elsif ($swmode eq 'Nod') {
      throw OMP::Error::TranslateFail("jiggle_pssw mode not supported\n");
    } else {
      throw OMP::Error::TranslateFail("Jiggle with switch mode $swmode not supported\n");
    }
  } else {
    throw OMP::Error::TranslateFail("Unable to determine observing mode from observation of type '$mode'");
  }

  if (wantarray) {
    return %summary;
  } else {
    my $mode = $summary{mapping_mode} . '_' . $summary{switching_mode};
    return $mode;
  }

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
    # These are the hybridised subsystem parameters
    my $hbw = $s->{bw};
    my $olap = $s->{overlap};
    my $hchan = $s->{channels};

    # Calculate the channel width and store it
    my $chanwid = $hbw / $hchan;
    $s->{channwidth} = $chanwid;

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

    # store the bandwidth in Hz for reference
    $s->{bandwidth} = $mhz * 1E6;

    # Store the bandwidth label
    my $ghz = $mhz / 1000;
    $s->{bwlabel} = ( $mhz < 1000 ? int($mhz) ."MHz" : int($ghz) . "GHz" );

    # Original number of channels before hybridisation
    my $nchan = int( ($bw / $chanwid) + 0.5 );
    $s->{nchannels_full} = $nchan;

    # number of channels per subband
    my $nchan_per_sub = $nchan / $nsubband;
    $s->{nchan_per_sub} = $nchan_per_sub;

    # calculate the bandwidth of each subband
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

    # Now we need to calculate the reference channels for each subband
    # (middle channel if 1 subband)
    my @refchan;
    if ($nsubband == 1) {
      $refchan[0] = int( $nchan / 2 );
    } elsif ($nsubband == 2) {
      # calculate the overlap in channels
      my $nchan_olap = int($olap / $chanwid);

      # the channel offset into the array is half the total
      my $noff = int( $nchan_olap / 2 );

      # First offset is from the end, second is from the start
      push( @refchan, $nchan_per_sub - $noff, $noff );

    } else {
      # This all assumes two subbands
      throw OMP::Error::FatalError("Can only calculate IF ref channel for a 2 subband system not $nsubband");

    }

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

  # eventually this should be from a translator configuration file
  my $mode = $self->observing_mode( %info );

  # quick hack. raster=100ms, all else is 50ms.
  return ( $mode =~ /raster/ ? 0.1 : 0.05 );
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
sub _calc_offset_stats {
  my $nyquist = shift;
  my @off = @_;

  # Now remove duplicates. Order is irrelevant
  my %dummy = map { $_ => undef } @off;

  # and sort
  my @sort = sort { $a <=> $b } keys %dummy;

  # if we only have one position we can return early here
  print "Got to here\n";
  return ($sort[0], $sort[0], $sort[0], 0, 1, $nyquist) if @sort == 1;

  # Then find the extent of the map
  my $max = $sort[-1];
  my $min = $sort[0];
  my $span = $max - $min;
  my $cen = ( $max + $min ) / 2;

  # if we only have two positions, return early
  return ($min, $max, $cen, $span, 2, $span) if @sort == 2;

  # Tolerance is fraction of Nyquist
  my $tol = 0.2 * $nyquist;

  # Now calculate the gaps between each position
  my @gap = map { $sort[$_] - $sort[$_-1] } (1..$#sort);

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

  # Reference "pixel"
  my $refpix = $sort[0];

  # Move to the nearest int if the nearest int is less than the tol
  # away
  my $adj = ( $refpix > 0 ? 0.5 : -0.5 );
  my $nearint = int( $refpix + $adj );
  if (($refpix - $nearint) < $tol) {
    $refpix = $nearint;
  }

  # Store the reference and try to adjust it until we find a match
  # or until the trial is smaller than the tolerance
  my $reftrial = $trial;
  my $mod = 2; # trial modifier
  OUTER: while ($trial > $tol) {

    # see whether the sequence fits with this trial
    for my $t (@sort) {
      my $pixpos = ( $t - $refpix ) / $trial;
      my $pixerr = $t - (int($pixpos) * $trial) + $refpix;
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
  my $npix = int( ($span / $trial) + 0.5);
  return ($min, $max, $cen, $span, $trial, $npix );

}

=item B<_read_file>

Read a file and return the contents as a single string.

 $string = _read_file( $filename );

Not a method. Could probably use the slurp function.

=cut

sub _read_file {
  my $file = shift;
  open my $fh, "< $file" || 
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
namespace. They are all given the observation summary hash
as argument and they return the value that should be used in the
header.

  $value = OMP::Translator::ACSIS::Header->getProject( %info );

=cut

package OMP::Translator::ACSIS::Header;

sub getProject {
  my $class = shift;
  my %info = @_;
  return $info{PROJECTID};
}

sub getMSBID {
  my $class = shift;
  my %info = @_;
  return $info{MSBID};
}

sub getStandard {
  my $class = shift;
  my %info = @_;
  return $info{standard};
}

=head1 NOTES

Usually called indirectly from L<OMP::Translator|OMP::Translator>.

=head1 CONFIGURATION XML

The format of the configuration XML is outlined in JAC document
OCS/ICD/001.

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

Copyright 2003-2005 Particle Physics and Astronomy Research Council.
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
