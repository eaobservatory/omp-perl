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

use Astro::Coords::Offset;

# Need to find the OCS Config
use blib '/home/timj/dev/perlmods/JAC/OCS/Config/blib';

use JAC::OCS::Config;

use OMP::Error;

use base qw/ OMP::Translator /;

# Unix directory for writing configs
# Should be in config system
our $TRANS_DIR = "/jcmtdata/orac_data/configs";

# Debugging messages
our $DEBUG = 0;

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

  # Now unroll the MSB into constituent observations details
  my @configs;

  for my $obs ($msb->unroll_obs) {

    # Create blank configuration
    my $cfg = new JAC::OCS::Config;

    # First, configure the basic TCS parameters
    $self->tcs_config( $cfg, %$obs );

    # FRONTEND_CONFIG
    
    # ACSIS_CONFIG

    # HEADER_CONFIG

    # Slew and rotator need to wait until we can estimate
    # the duration of the configuration

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

Override the translation directory.

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

These routines generate the XML for individual config sections of the global configure.

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
	     );

  } else {
    
  }

  # need to decide on public vs private
  $tcs->_setObsArea( $oa );
}

=item B<observing_mode>

Retrieves the OT observing mode from the OT observation summary
(not from the OCS configuration).

 $obsmode = $trans->observing_mode( %info );

=cut

sub observing_mode {
  my $self = shift;
  my %info = @_;

  use Data::Dumper;
  print Dumper( \%info );

  return 'UNKNOWN';
}

=back

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
