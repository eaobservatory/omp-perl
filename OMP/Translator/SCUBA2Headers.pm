package OMP::Translator::SCUBA2Headers;

=head1 NAME

OMP::Translator::SCUBA2Headers - Derived header configuration for SCUBA-2

=head1 SYNOPSIS

  use OMP::Translator::SCUBA2Headers;
  $msbid = OMP::Translator::SCUBA2Headers->getMSBID($cfg, %info );

=head1 DESCRIPTION

This class contains SCUBA-2 specific header configurations. Class methods
are invoked from the JCMT translator.

Some header values are determined through the invocation of methods
specified in the header template XML. These methods are flagged by
using the DERIVED specifier with a task name of TRANSLATOR.

The following methods are in the OMP::Translator::JCMTHeaders
namespace. They are all given the observation summary hash as argument
and the current Config object, and they return the value that should
be used in the header.

  $value = OMP::Translator::SCUBA2Headers->getProject( $cfg, %info );

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
  return "EC30";
}

=item B<override_headers>

In most cases the default translations or entries in the header files are
correct but in a few cases some final mode-dependent tweaking may be
necessary.

 $class->override_headers( $hdrcfg, %info );

This method is called after headers have been excluded and after
translator callbacks have been run. Unlike the translation methods
below that take similar arguments and return the result, this
method works in place on the JAC::OCS::Config::Header object.

For SCUBA-2 the main purpose here is that the OBJECT header will
not be set if the TCS is not involved in the observation. This
can cause difficulties when trying to disambiguate a standard
dark from a DARK-NOISE. Additionally, if the telescope is not
involved in the observation then the telescope coordinates will
not be available (but they are required by CADC even so).

=cut

sub override_headers {
  my $self = shift;
  my $hdr = shift;
  my %info = @_;

  # For the special case of a DARK-NOISE we set the OBJECT
  # to DARK. Otherwise we can't tell a default dark from
  # a useful dark.
  if ($info{obs_type} =~ /noise/i &&
      $info{noiseSource} =~ /dark/i) {

    # Get object and set value. Should have an undef source already
    my $item = $hdr->item( "OBJECT" );
    if (defined $item->source) {
      throw OMP::Error::FatalError( "OBJECT for noise observation unexpectedly has a source defined");
    }
    if ($item->value) {
      throw OMP::Error::FatalError( "OBJECT for noise observation already has a value of ". $item->value );
    }
    $item->value( "DARK" );
  }

  # Coordinates of the telescope can be nulled out for observations that do
  # not involve the TCS. In that case put them back in for CADC. They do not
  # need to be super accurate.
  my %coords = ( "ALT-OBS" => 4120.0,
                 "LAT-OBS" => 19.822838905884,
                 "LONG-OBS" => -155.477027838737,
                 "OBSGEO-X" => -5464589.95643476,
                 "OBSGEO-Y" => -2492998.89278856,
                 "OBSGEO-Z" => 2150652.04160241,
               );
  for my $k (keys %coords) {
    my $item = $hdr->item( $k );
    if ( ! $item->source() && ! $item->value ) {
      $item->value( $coords{$k} );
    }
  }


  return;
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

  # Get the observation type and the mapping mode
  my $obstype = $info{obs_type};
  my $mapmode = $info{mapping_mode};
  my $has_fts = scalar grep {$_ eq 'fts2'} @{$info{'inbeam'}};
  my $has_pol = scalar grep {$_ =~ /^pol/} @{$info{'inbeam'}};

  # if there was no DR component we have to guess
  if ($obstype eq 'pointing') {
    $recipe = $has_fts ? 'REDUCE_FTS_POINTING' : 'REDUCE_POINTING';
  } elsif ($obstype eq 'focus') {
    $recipe = $has_fts ? 'REDUCE_FTS_FOCUS' : 'REDUCE_FOCUS';
  } elsif ($obstype eq 'skydip') {
    $recipe = "REDUCE_SKYDIP";
  } elsif ($obstype eq 'flatfield') {
    $recipe = "REDUCE_FLATFIELD";
  } elsif ($obstype eq 'setup') {
    $recipe = "REDUCE_SETUP";
  } elsif ($obstype eq 'array_tests') {
    $recipe = "ARRAY_TESTS";
  } elsif ($obstype eq 'noise') {
    $recipe = 'REDUCE_NOISE';
  } elsif ($mapmode eq 'scan') {
    $recipe = "REDUCE_SCAN";
  } elsif ($mapmode eq 'stare' || $mapmode eq 'dream') {
    if (ref $info{'inbeam'} and $has_fts) {

      # The superclass fails to find the FTS-2 recipes because
      # the mode doesn't match.
      if (exists $info{'data_reduction'} &&
          exists $info{'data_reduction'}->{'stare'} &&
          defined $info{'data_reduction'}->{'stare'}) {

        $recipe = $info{'data_reduction'}->{'stare'};

        if ($class->VERBOSE) {
          print {$class->HANDLES}
            "Using FTS-2 DR recipe $recipe provided by user\n";
        }

        return $recipe;
      }

      # Check whether this is a ZPD measurement.
      if ((exists $info{'SpecialMode'}) and ($info{'SpecialMode'} eq 'ZPD')) {
        $recipe = "REDUCE_FTS_ZPD";
      }
      else {
        # Otherwise use default FTS recipe.
        $recipe = "REDUCE_FTS_SCAN";
      }
    }
    elsif (ref $info{'inbeam'} and $has_pol) {
      $recipe = "REDUCE_POL_STARE";
    } else {
      $recipe = "REDUCE_DREAMSTARE";
    }
  } else {
    OMP::Error::TranslateFail->throw("Unexpected obs mode ($obstype/$mapmode)".
                                    " when calculating DR recipe");
  }

  if ($class->VERBOSE) {
    print {$class->HANDLES} "Using DR recipe $recipe determined from context\n";
  }
  return $recipe;
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
