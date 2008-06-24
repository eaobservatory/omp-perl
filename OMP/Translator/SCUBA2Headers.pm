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

  # if there was no DR component we have to guess
  if ($obstype eq 'pointing') {
    $recipe = 'REDUCE_POINTING';
    $recipe .= "_SCAN" if $mapmode eq 'scan';
  } elsif ($obstype eq 'focus') {
    $recipe = 'REDUCE_FOCUS';
    $recipe .= "_SCAN" if $mapmode eq 'scan';
  } elsif ($obstype eq 'skydip') {
    $recipe = "REDUCE_SKYDIP";
  } elsif ($obstype eq 'flatfield') {
    $recipe = "REDUCE_FLATFIELD";
  } elsif ($mapmode eq 'scan') {
    $recipe = "REDUCE_SCAN";
  } elsif ($mapmode eq 'stare' || $mapmode eq 'dream') {
    $recipe = "REDUCE_DREAMSTARE";
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
