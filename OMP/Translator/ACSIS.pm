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

# Need to find the OCS Config (temporary kluge)
use blib '/home/timj/dev/perlmods/JAC/OCS/Config/blib';

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
  # Now unroll the MSB into constituent observations details
  my @configs;

  for my $obs ($msb->unroll_obs) {

    # Create blank configuration
    my $cfg = new JAC::OCS::Config;

    # Add comment
    $cfg->comment( "Translated on ". gmtime() ."UT on host ".
		   Net::Domain::hostfqdn() . " by $ENV{USER} \n".
		   "using Translator version $VERSION on an MSB created by the OT version $otver\n");

    # First, configure the basic TCS parameters
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

=item B<tcs_config>

TCS configuration.

  $tcsxml = $TRANS->tcs_config( $cfg, %info );

where $cfg is the main C<JAC::OCS::Config> object.

=cut

sub tcs_config {
  my $self = shift;
  my $cfg = shift;
  my %info = @_;

  # Create the template
  my $tcs = new JAC::OCS::Config::TCS;

  # Telescope is known
  $tcs->telescope( 'JCMT' );

  # First the base position
  $self->tcs_base( $tcs, %info );

  # observing area
  $self->observing_area( $tcs, %info );

  # Then secondary mirror

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

  $self->observing_mode(%info);
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

  } else {
    
  }

  # need to decide on public vs private
  $tcs->_setObsArea( $oa );
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
  my $inst = lc($info{instrument});
  throw OMP::Error::FatalError('No instrument defined so cannot configure!')
    unless defined $inst;

  # wiring file name
  my $file = File::Spec->catfile( $WIRE_DIR, 'frontend',
				  "instrument_$inst.ent");
  throw OMP::Error::FatalError("$inst instrument configuration XML not found in $file !")
    unless -e $file;

  # Read it
  my $inst = new JAC::OCS::Config::Instrument( File => $file,
					       validation => 0,
					     );

  # tweak the wavelength
  $inst->wavelength( $info{wavelength} );

  $cfg->instrument_setup( $inst );

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

  $cfg->acsis( $acsis );
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

#  $cfg->header( $hdr );

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
		jiggle_fast_fsw =>  'fast_jiggle_fsw',
		jiggle_slow_fsw => 'slow_jiggle_fsw',
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

=item B<observing_mode>

Retrieves the ACSIS observing mode from the OT observation summary
(not from the OCS configuration).

 $obsmode = $trans->observing_mode( %info );

The standard modes are:

  focus
  pointing
  jiggle_fast_fsw
  jiggle_slow_fsw
  jiggle_chop
  grid_pssw
  raster_pssw

=cut

sub observing_mode {
  my $self = shift;
  my %info = @_;

  use Data::Dumper;
  print Dumper( \%info );


  my $mode = $info{MODE};

  if ($mode eq 'SpIterRasterObs') {
    return 'raster_pssw';
  } elsif ($mode eq 'SpIterPointingObs') {
    return 'pointing';
  } elsif ($mode eq 'SpIterFocusObs' ) {
    return 'focus';
  } elsif ($mode eq 'SpIterJiggleObs' ) {
    # depends on switch mode
    return 'jiggle_chop';
  } else {
    throw OMP::Error::TranslateFail("Unable to determine observing mode from observation of type '$mode'");
  }

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

Copyright 2003-2004 Particle Physics and Astronomy Research Council.
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
