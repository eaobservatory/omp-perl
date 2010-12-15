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

=item B<islocal>

Returns true if the supplied arguments from the C<caller> function indicate
that the callers method is being invoked from within the header configuratio
package. Used to prevent warning messages being issued when a configuration
method calls another configurtion method.

  $isl = $class->islocal( caller );

=cut

sub islocal {
  my $class = shift;
  my $callpkg = shift;
  if (UNIVERSAL::isa($callpkg, __PACKAGE__)) {
    return 1;
  }
  return 0;
}

=back

=head1 TRANSLATION METHODS

=over 4

=item B<getProject>

Return the project ID that should be used. We use a calibration
project if the observation is marked a STANDARD or if is not
a science observation.

=cut

sub getProject {
  my $class = shift;
  my $cfg = shift;
  my %info = @_;

  my $obs_type = lc($info{obs_type});
  my $standard = $class->getStandard($cfg, %info);

  if ($standard || $obs_type ne 'science' || $info{autoTarget} ) {
    if ($class->VERBOSE) {
      # only warn if we are called from outside this package
      if (!$class->islocal(caller)) {
        print {$class->HANDLES} "Using calibration project ID\n";
      }
    }
    return "JCMTCAL";
  } elsif ( defined $info{PROJECTID} && $info{PROJECTID} ne 'UNKNOWN' ) {
    # if the project ID is not known, we need to use a ACSIS or SCUBA2 project
    return $info{PROJECTID};
  } else {
    my $sem = OMP::General->determine_semester( tel => 'JCMT' );
    my $pid = "M$sem" . $class->default_project();
    if ($class->VERBOSE) {
      # only warn if we are called from outside this package
      if (!$class->islocal(caller)) {
        print {$class->HANDLES} "!!! No Project ID assigned. Inserting E&C code: $pid !!!\n";
      }
    }
    return $pid;
  }
  # should not get here
  return undef;
}

=item B<getMSBID>

=cut

sub getMSBID {
  my $class = shift;
  my $cfg = shift;
  my %info = @_;
  return $info{MSBID};
}

=item B<getRemoteAgent>

=cut

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

=item B<getAgentID>

=cut

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

=item B<getScanPattern>

=cut

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

=item B<getStandard>

=cut

sub getStandard {
  my $class = shift;
  my $cfg = shift;
  my %info = @_;
  return $info{standard};
}

# For continuum we need the continuum recipe

=item B<getDRRecipe>

For continuum we need the continuum recipe.

BASE class implementation simply parses the supplied data_reduction information from the OT.
Subclasses can additionally determine defaults if this method returns undef.

=cut

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
        # append continuum mode (if not already appended). Only works if default
        # recipe is REDUCE_SCIENCE. So this clause is really an ACSIS clause.
        $found .= "_CONTINUUM" if $found eq 'REDUCE_SCIENCE';
      }
      if ($class->VERBOSE) {
        print {$class->HANDLES} "Using DR recipe $found provided by user\n";
      }
      return $found;
    }
  }

  # Leave it to subclasses to handle special cases
  return;
}

=item B<getDRGroup>

=cut

sub getDRGroup {
  my $class = shift;
  my $cfg = shift;

  # Not quite sure how to handle this in the translator since there are no
  # hints from the OT and the DR is probably better at doing this.
  # by default return an empty string indicating undef
  return '';
}

=item B<getSurveyName>

Need to get survey information from the TOML.
Derive it from the project ID

=cut

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

=item B<getInstAper>

Receptor aligned with tracking centre

=cut

sub getInstAper {
  my $class = shift;
  my $cfg = shift;

  my $tcs = $cfg->tcs;
  throw OMP::Error::FatalError('for some reason TCS configuration is not available. This can not happen')
    unless defined $tcs;
  my $ap = $tcs->aperture_name;
  return ( defined $ap ? $ap : "" );
}

sub getTrkRecep {
  my $class = shift;
  return $class->getInstAper( @_ );
}

=item B<getOCSCFG>

This gets written automatically by the OCS Config classes. This is a dummy configuration
method.

=cut

sub getOCSCFG {
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
