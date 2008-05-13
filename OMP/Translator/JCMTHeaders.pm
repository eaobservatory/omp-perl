package OMP::Translator::JCMTHeaders;

=head1 NAME

OMP::Translator::JCMTHeaders - Header configuration for JCMT instruments

=head1 SYNOPSIS

  use OMP::Translator::JCMTHeaders;
  $msbid = OMP::Translator::JCMTHeaders->getMSBID($cfg, %info );

=head1 DESCRIPTION

This is a base class for shared JCMT header determinations. Class methods
are invoked from the JCMT translator, usually via a translator specific
subclass.

Some header values are determined through the invocation of methods
specified in the header template XML. These methods are flagged by
using the DERIVED specifier with a task name of TRANSLATOR.

The following methods are in the OMP::Translator::JCMTHeaders
namespace. They are all given the observation summary hash as argument
and the current Config object, and they return the value that should
be used in the header.

  $value = OMP::Translator::JCMTHeaders->getProject( $cfg, %info );

An empty string will be recognized as a true UNDEF header value. Returning
undef is an error.

=cut

use 5.006;
use strict;
use warnings;
use Carp;
use Data::Dumper;

=head1 HELPER METHODS

Set global variables to control verbosity and other generic items.

=over 4

=item B<VERBOSE>

Enable or disable verbose mode.

  $verbose = $class->VERBOSE;
  $class->VERBOSE( 1 );

=cut

{
  my $VERBOSE = 0;
  sub VERBOSE {
    my $class = shift;
    if (@_) { $VERBOSE = shift; }
    return $VERBOSE;
  }
}

=item B<HANDLES>

Output handle for verbose messages. Defaults to STDOUT.

  $handle = $class->HANDLES;
  $class->HANDLES( $handles );

=cut

{
  my $HANDLES = \*STDOUT;
  sub HANDLES {
    my $class = shift;
    if (@_) { $HANDLES = shift; }
    return $HANDLES;
  }
}

=item B<default_project>

Returns the default project code (eg EC19) if a project is not known.

=cut

sub default_project {
  croak "Must subclass default project";
}

=back

=head1 TRANSLATION METHODS

=over 4

=item B<getProject>

=cut

sub getProject {
  my $class = shift;
  my $cfg = shift;
  my %info = @_;

  # if the project ID is not known, we need to use a ACSIS or SCUBA2 project
  if ( defined $info{PROJECTID} && $info{PROJECTID} ne 'UNKNOWN' ) {
    return $info{PROJECTID};
  } else {
    my $sem = OMP::General->determine_semester( tel => 'JCMT' );
    my $pid = "M$sem" . $class->default_project();
    if ($class->VERBOSE) {
      print {$class->HANDLES} "!!! No Project ID assigned. Inserting E&C code: $pid !!!\n";
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
      if ($class->VERBOSE) {
        print {$class->HANDLES} "Using DR recipe $found provided by user\n";
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

  if ($class->VERBOSE) {
    print {$class->HANDLES} "Using DR recipe $recipe determined from context\n";
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

=back

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
