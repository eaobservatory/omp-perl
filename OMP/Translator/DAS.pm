package OMP::Translator::DAS;

=head1 NAME

OMP::Translator::DAS - translate DAS heterodyne observations to HTML

=head1 SYNOPSIS

  use OMP::Translator::DAS;

  $htmlfile = OMP::Translator::DAS->translate( $sp );


=head1 DESCRIPTION

Convert DAS MSBs into a form suitable for observing. For the classic
observing system this simply means an HTML summary of the MSB
where the information is sufficient for the TSS to type in the
ICL commands manually.

=cut

use 5.006;
use strict;
use warnings;

use OMP::SciProg;
use OMP::Error;
use Astro::Telescope;

# Unix directory for writing ODFs
our $TRANS_DIR = "/observe/ompodf";

our $CATALOGUE = "omp.cat";

# Debugging
our $DEBUG = 0;

=head1 METHODS

=over 4

=item B<translate>

Convert the science program object (C<OMP::SciProg>) into
a observing sequence understood by the instrument data acquisition
system (an ODF).

  $odf = OMP::Translate->translate( $sp );
  $data = OMP::Translate->translate( $sp, 1);
  @data = OMP::Translate->translate( $sp, 1);

By default returns the name of a HTML file. If the optional
second argument is true, returns the contents of the HTML as a single
string.

=cut

sub translate {
  my $self = shift;
  my $sp = shift;
  my $asdata = shift;

  # Need to get the MSBs [which we assume will all be translated by this class]
  my @msbs = $sp->msb;

  # Now loop over MSBs
  # Targets have to be collated and written to a catalog file
  my $html = '';
  my @targets;

  # Process standard information
  $html .= $self->fixedHeader( $sp );
  my $obscount = 0;
  for my $msb (@msbs) {

    # If we are going to do this by unrolling the sequence
    # we have to be aware of two things:
    #  1. The unrolled sequence will include repeats of
    #     frontend/backend configuration and target information
    #     So we will have to spot when things change
    #  2. Waveplates must not be unrolled (they are by default)
    #   Although I am not sure about this yet
    #  3. Offset iterators must be converted back into grids
    #     and patterns when used in conjunction with a Sample

    # With this in mind it may well be easier to deal with each
    # observation separately and then unroll the sequence
    # in the translator

    # From a TSS perspective it makes sense to provide information
    # as it changes rather than repeat it for each "observe"
    # ie
    #   - Configure Frontend
    #   - Move to target1
    #   - Pointing [choose your own target]
    #   - Move to target1
    #   - Configure backend
    #   - Configure "cell"
    #   - Do raster
    #   - New target
    #   - Configure Cell
    #   - Do sample

    # Offset grids need some checking to distinguish "pattern"
    # from "GRID" observation. A "PATTERN" will also require that
    # we write the pattern file to disk.

    # Catalogue files will need to include the velocity information
    # This has ramifications for the SrcCatalog class (and also
    # for Astro::Coords).

    # Astro::Coords may have to include offset information as well
    # in order to support REFERENCE positions
    # For the DAS all REFERENCE positions must be supplied as an
    # offset (ie need to be able to subtract two coordinates
    # and convert to tangent plane)

    # MSB header information
    $html .= $self->msbHeader( $msb );

    # Correct offset issues
    $self->correct_offsets( $msb );

    # Unroll the observations
    my @obs = $msb->unroll_obs();

    # Ignore suspension for now
    for my $obsinfo ( @obs ) {
      $obscount++;

      # Store the target
      push(@targets, $obsinfo->{coords}) if defined $obsinfo->{coords};

      use Data::Dumper;
      print STDERR Dumper($obsinfo);

      # Start new observation
      $html .= "<h2>Observation #$obscount</h2>\n";

      # Target information (assuming we have not already specified it)
      $html .= $self->targetConfig( %$obsinfo );

      # Front end configuration (assuming we have not already specified it)
      $html .= $self->feConfig( %$obsinfo );

      # Back end
      $html .= $self->beConfig( %$obsinfo );

      # Actual observing mode (inc cell)

    }

  }

  $html .= $self->fixedFooter();

  print $html;

  if ($asdata) {
    # How do I return the catalogue????
    return $html;
  } else {
    # Write this file to disk and all the target information
    # to a catalogue

  }
}

=back

=head1 INTERNAL METHODS

=head2 MSB manipulation

=over 4

=item B<correct_offsets>

For DAS samples offsets can be dealt with simply by using a GRID or
PATTERN observing mode rather than a simple SAMPLE. For this to happen
during unrolling we need to go through an correct SpIterOffsets so
that they do not generate a new observation per iteration. For RASTER
observing an offset must generate a new file each time.

  OMP::Translator->correct_offsets( $msb );

If we have both a SAMPLE and RASTER observe as a child of a single
offset iterator we would need to clone it into two different
iterators.  Since this is unusual in practice and extremely difficult
to get correct (since you have to account for all structures below the
iterator) we should croak in this situation. Currently we let it go.

=cut

sub correct_offsets {
  my $self = shift;
  my $msb = shift;

  # Note that this returns references to each observation summary.
  # We can modify this hash in place without putting the structure
  # back into the object. This will trigger a nice bug if the obssum
  # method is changed to return a copy.
  my @obs = $msb->obssum;

  # loop over each observation
  for my $obs (@obs) {

    my %modes = map { $_ => undef } @{$obs->{obstype}};

    # skip to next observation unless we have a Stare
    next unless exists $modes{Stare};

    # Now need to recurse through the data structure changing
    # waveplate iterator to a single array rather than an array
    # separate positions.
    for my $child (@{ $obs->{SpIter}->{CHILDREN} }) {
      $self->_fix_offset_recurse( $child );
    }

  }

}

# When we hit SpIterOffset we correct the ATTR array
# This modifies it in-place. No need to re-register.

sub _fix_offset_recurse {
  my $self = shift;
  my $this = shift;

  # Loop over keys in children [the iterators]
  for my $key (keys %$this) {

    if ($key eq 'SpIterOffset') {
      # FIX UP - it does not make any sense to have another
      # offset iterator below this level but we do support it
      my @offsets = @{ $this->{$key}->{ATTR}};

      # and store it back
      $this->{$key}->{ATTR} = [ { offsets => \@offsets } ];

    }

    # Now need to go deeper if need be
    # We also need to worry about sanity checks
    # with the possibility of encountering a Raster
    if (UNIVERSAL::isa($this->{$key},"HASH") &&
	exists $this->{$key}->{CHILDREN}) {
      # This means we have some children to analyze

      for my $child (@{ $this->{$key}->{CHILDREN} }) {
	$self->_fix_offset_recurse( $child );
      }

    }

  }

}


=head1 INTERNAL METHODS

=head2 HTML output

=over 4

=item <fixedHeader>

Return the fixed header information. This is just the project ID for now.
Only information that can be extracted from the science program.

  $html = OMP::Translator::DAS->fixedHeader( $sp );

=cut

sub fixedHeader {
  my $self = shift;
  my $sp = shift;

  my $html = '';

  # Project
  my $project = $sp->projectID;

  $html .= "<HTML><HEAD><TITLE>Project $project</TITLE></HEAD><BODY>\n";

  $html .= "<H1>$project</H1>\n";

  $html .= "<em>Please remember to set project ID to <em>$project</em> in the acquisition system.</em><br><br>\n";

  return $html;
}

=item <msbHeader>

Return the fixed MSB header information. This includes the MSB title,
the project ID and any observer notes.

  $html = OMP::Translator::DAS->msbHeader( $msb );

=cut

sub msbHeader {
  my $self = shift;
  my $msb = shift;

  my $html = '';

  # title
  my $title   = $msb->msbtitle;

  # Observer note if any
  my ($ntitle, $note) = $msb->getObserverNote;

  $html .= "<H1>MSB: $title</H1>\n";
  $html .= '<!-- MSBID: '. $msb->checksum . " -->\n";

  if (defined $note) {
    $html .= "<h2>Note: $ntitle</h2>\n$note\n";
  } else {
    $html .= "<h2>No note supplied</h2>";
  }

  return $html;
}

=item B<fixedFooter>

Standard footer to close the HTML associated with this translation.

  $html = OMP::Translator::DAS->fixedFooter;

=cut

sub fixedFooter {
  my $self = shift;

  my $html = "<hr><em>Translated on ".gmtime(time)."UTC\n</BODY></HTML>";
  return $html;
}

=item B<feConfig>

Create HTML for the Frontend configuration.

  $html = OMP::Translator::DAS->feConfig( %summary );

=cut

sub feConfig {
  my $self = shift;
  my %summary = @_;

  # Need te freqconfig entry
  my %freqconfig = %{ $summary{freqconfig} };

  # probably should abort if we are "redshift"
  # The OT converts redshift to velocity so this is not a problem
  # so long as I can work out the velocityDefinition
#  throw OMP::Error::TranslateFail("Can not translate redshifts at this time")
#    if $freqconfig{velocityDefinition} eq 'redshift';

  # Velocity units
  my $velunits = "km/s";

  my $html = "<h3>Frontend configuration: <em>Rx".
    $summary{instrument}."</em></h3>\n";
  $html .= "<table>";
  $html .= "<tr><td><b>Molecule:</b></td><td>".
    $freqconfig{molecule}."</td></tr>";
  $html .= "<tr><td><b>Transition:</b></td><td>".
    $freqconfig{transition}."</td></tr>";
  $html .= "<tr><td><b>Rest Frequency:</b></td><td>".
    _HztoGHz($freqconfig{restFrequency})." GHz</td></tr>";

  $html .= "<tr><td><b>Preferred Sideband:</b></td><td>".
    uc($freqconfig{sideBand})."</td></tr>";
  $html .= "<tr><td><b>Side band mode:</b></td><td>".
    uc($freqconfig{sideBandMode})."</td></tr>"
      unless $summary{instrument} eq "A3";

  $html .= "<tr><td><b>Velocity:</b></td><td>".
    sprintf("%.3f",$freqconfig{velocity})." $velunits</td></tr>";
  $html .= "<tr><td><b>Velocity definition:</b></td><td>".
    $freqconfig{velocityDefinition}." </td></tr>";

  my $vframe = (exists $freqconfig{velocityFrame} ? $freqconfig{velocityFrame}
		: '<i>UNKNOWN</i>');
  $html .= "<tr><td><b>Velocity Frame:</b></td><td>".
    $vframe." </td></tr>";

  # Probably should not show this information for RxA
  $html .= "<tr><td><b># mixers:</b></td><td>".
    $freqconfig{mixers} ."</td></tr>" unless $summary{instrument} eq 'A3';

  $html .= "</table>\n";
  return $html;
}

=item B<beconfig>

Backend configuration.

  $html = OMP::Translator::DAS->beconfig( %summary );

=cut

sub beConfig {
  my $self = shift;
  my %summary = @_;

  # Need te freqconfig entry
  my %freqconfig = %{ $summary{freqconfig} };

  my $html = "<h3>DAS configuration</h3>\n";
  $html .= "<table>";
  $html .= "<tr><td><b>Bandwidth:</b></td><td>".
    int(_HztoMHz($freqconfig{bandWidth}))." MHz</td></tr>";

  $html .= "</table>\n";
  return $html;
}

=item B<targetConfig>

Describe the target information. Currently we do not handle comets
very well. Also, this information really needs to be stored in a catalog.
That will be done by the caller.

  $html = OMP::Translator::DAS->targetConfig( %summary );

=cut

sub targetConfig {
  my $self = shift;
  my %summary = @_;

  my $c = $summary{coords};
  $c->telescope( new Astro::Telescope('JCMT') );

  my $html;
  $html .= "<H3>Target Information: <em>".$summary{target}."</em></H3>\n";
  $html.= "<PRE>". $c->status ."</PRE>\n";
  return $html;

}


# Real internal helper routines that are not even class methods

# Convert Hz to GHz
sub _HztoGHz {
  my $hz = shift;
  $hz /= 1E9;
  return $hz;
}

# Convert Hz to GHz
sub _HztoMHz {
  my $hz = shift;
  $hz /= 1E6;
  return $hz;
}

# Given an array of offsets (dx,dy,PA) determine
# whether they are on a regular grid or random
# If random, return an array offsets that have a fixed PA
# (usually 0.0)

# Returns a hash with keys:
#  TYPE =>  PATTERN or GRID
#  GRIDDX => X spacing in arcseconds   [GRID]
#  GRIDDY => Y spacing in arcseconds   [GRID]
#  GRIDNX => Number of positions in X  [GRID]
#  GRIDPA => Position angle of grid    [GRID]
#  OFFSETX => X Centre of grid pattern [GRID]
#  OFFSETY => Y centre of grid pattern [GRID]
#  OFFSETS => Array of hashes with OFFSET_DX and OFFSET_DY [PATTERN]

# Note that if the offsetx/y of the GRID is not the centre of the
# grid (ie the grid has even NX or NY) then we return the coordinates
# as a PATTERN because the Heterodyne system can not support an even GRID

sub offsets_to_grid {


}


=back

=head1 NOTES

Usually called indirectly from L<OMP::Translator|OMP::Translator>.

=head1 COPYRIGHT

Copyright (C) 2002-2003 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=cut

1;
