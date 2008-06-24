package OMP::Translator::ACSISHeaders;

=head1 NAME

OMP::Translator::ACSISHeaders - Derived header configuration for SCUBA-2

=head1 SYNOPSIS

  use OMP::Translator::ACSISHeaders;
  $msbid = OMP::Translator::ACSISHeaders->getMSBID($cfg, %info );

=head1 DESCRIPTION

This class contains ACSIS specific header configurations. Class methods
are invoked from the JCMT translator.

Some header values are determined through the invocation of methods
specified in the header template XML. These methods are flagged by
using the DERIVED specifier with a task name of TRANSLATOR.

The following methods are in the OMP::Translator::JCMTHeaders
namespace. They are all given the observation summary hash as argument
and the current Config object, and they return the value that should
be used in the header.

  $value = OMP::Translator::ACSISHeaders->getProject( $cfg, %info );

An empty string will be recognized as a true UNDEF header value. Returning
undef is an error.

=cut

use 5.006;
use strict;
use warnings;
use Carp;
use Data::Dumper;

use base qw/ OMP::Translator::JCMTHeaders /;

=head1 HELPER METHODS

=over 4

=item B<default_project>

Returns default E&C project.

=cut

sub default_project {
  return "EC19";
}

=head1 TRANSLATION METHODS

=over 4

=item B<getDRRecipe>

Default recipe can be supplied by the OT user or determined from context.

Uses the base class for the user supplied value.

=cut

sub getDRRecipe {
  my $class = shift;
  my $cfg = shift;
  my %info = @_;

  # See if the base class knows better
  my $recipe = $class->SUPER::getDRRecipe($cfg, %info );
  return $recipe if defined $recipe;

  # if there was no DR component we have to guess
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



=item B<getNumMixers>

=cut

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

=item B<getReferenceDec>

Reference position as sexagesimal string or offset

=cut

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

=item B<getReferenceRA>

Reference position as sexagesimal string or offset

=cut

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

=item B<getRefRecep>

Get the reference recptor.

=cut

sub getRefRecep {
  my $class = shift;
  my $cfg = shift;

  my $inst = $cfg->instrument_setup;
  throw OMP::Error::FatalError('for some reason Instrument configuration is not available. This can not happen') 
    unless defined $inst;
  return scalar $inst->reference_receptor;
}

=item B<getRPRecipe>

Reduce process recipe requires access to the file name used to read
the recipe This should be stored in the Cfg object.

=cut

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
