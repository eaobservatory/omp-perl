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

use OMP::Error;
use Astro::Telescope;
use Astro::SLA ();
use File::Spec;
use SrcCatalog::JCMT;

# Unix directory for writing ODFs
our $TRANS_DIR = "/observe/ompodf";

# VAX equivalent
our $VAX_TRANS_DIR = "OBSERVE:[OMPODF]";

# This is the name of the source catalogue
# We write it into $TRANS_DIR
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

  # Project
  my $projectid = $sp->projectID;

  # Need to get the MSBs [which we assume will all be translated by this class]
  my @msbs = $sp->msb;

  # Now loop over MSBs
  # Targets have to be collated and written to a catalog file
  # And additional data files need to be kept [as arrays of lines for now
  # indexed by future file name]
  my $html = '';
  my @targets;
  my %files;

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

    # Fudge Raster observations that have more than one offset
    @obs = map { $self->fudge_raster_offsets($_) } @obs;

    # Ignore suspension for now
    for my $obsinfo ( @obs ) {
      $obscount++;

      # Store the target
      push(@targets, $obsinfo->{coords}) if defined $obsinfo->{coords};

      # What are we going to do about PATTERN files???
      # In general we can not write them to disk in this phase
      # but we also need to make sure we write them with a unique
      # name so that the HTML can track them.
      # The HTML is pretty fixed at this point (unless we insert 
      # A large string and do a replacement)
      # We could generate the text for the file and return it
      # in addition to the HTML, indexed by the name used in the XML??
      # Targets are different because we need to index them by name once
      # we are complete.

      use Data::Dumper;
      print STDERR Dumper($obsinfo);

      # Start new observation
      my $mode = $self->obsMode( %$obsinfo );
      $html .= "<hr><h2>Observation #$obscount: $mode</h2>\n";

      # Quick variable to indicate whether we are a science observation
      my $issci = 0;
      $issci = 1 if ($obsinfo->{MODE} eq 'SpIterStareObs' ||
		    $obsinfo->{MODE} eq 'SpIterRasterObs');

      # Want the target and the frontend in a table
      $html .= "<table>";

      # Target information (assuming we have not already specified it)
      $html .= "<tr valign=\"top\">\n";

      # BE/FE configuration are not required for FOCUS and POINTING
      if ($issci) {

	# Front end configuration (assuming we have not already specified it)
	$html .= "<td>";
	$html .= $self->feConfig( %$obsinfo );

	# Back end
	$html .= $self->beConfig( %$obsinfo );
	$html .= "</td>";
      }

      $html .= "<td>\n";
      $html .= $self->targetConfig( %$obsinfo );
      $html .= "</td>";


      # Switch mode
      $html .= "<td>";
      $html .= $self->switchConfig( %$obsinfo ) if $issci;

      # Actual observing mode (inc cell)
      my $otmode = $obsinfo->{MODE};
      if ($self->can( $otmode )) {
	# Need to return HTML + optional file info
	my ($htmldata, %newfiles) = $self->$otmode( %$obsinfo );

	# Combine with previous data
	$html .= $htmldata;
	for my $newfile (keys %newfiles) {
	  # assume each file name is unique
	  $files{$newfile} = $newfiles{$newfile};
	}

      } else {
	throw OMP::Error::TranslateFail("Do not know how to translate observations in mode: $otmode");
      }

      $html .= "</td>";
      $html .= "</table>\n";

    }

  }

  $html .= $self->fixedFooter();

  # For debugging
  #print $html;

  use Data::Dumper;
  print Dumper({TARGETS=>\@targets, FILES=>\%files});

  if ($asdata) {
    # How do I return the catalogue????
    # Return it as Hash until we can be bothered to develop an object
    return { 
	    HTML => $html,
	    TARGETS => \@targets,
	    FILES => \%files,
	   };

  } else {

    # Write this HTML file to disk along with the patterns and all the
    # target information to a catalogue
    my $file = File::Spec->catfile( $TRANS_DIR, "hettrans.html");
    open my $fh, ">$file" or 
      throw OMP::Error::FatalError("Could not write HTML translation [$file] to disk: $!\n");

    print $fh $html;

    close($fh) 
      or throw OMP::Error::FatalError("Error closing HTML translation [$file]: $!\n");

    # Now the pattern files et al
    for my $f (keys %files) {
      open my $fh, ">$f" or
	throw OMP::Error::FatalError("Could not write translation file [$file] to disk: $!\n");

      for my $l ( @{ $files{$f} } ) {
	chomp($l);
	print $fh "$l\n";
      }

      close($fh) 
	or throw OMP::Error::FatalError("Error closing translation [$file]: $!\n");

    }

    # Now the catalogue file
    my $cat = new SrcCatalog::JCMT('/local/progs/etc/poi.dat');

    # For each of the targets add the projectid
    for (@targets) {
      $_->comment("Project: $projectid");
      print Dumper($_);
    }

    # Insert the new sources at the start
    unshift(@{$cat->sources}, @targets);
    $cat->reset;

    # And write it out
    my $outfile = File::Spec->catfile( $TRANS_DIR, $CATALOGUE);
    $cat->writeCatalog($outfile);

    return $file;
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
    # offset iterator to a single array rather than an array
    # separate positions.

    # Note that this will not do the right thing if you have
    # a Raster and Stare as child of offset iterator because the
    # raster will not unroll correctly
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

      # Need to determine whether this Offset iterator has a child
      # that is a StareObs
      my @children;
      push(@children,$self->_list_children( $this ));

      # Look for Stare
      my $isstare;
      for my $c (@children) {
	if ($c eq 'SpIterStareObs') {
	  $isstare = 1;
	  last;
	}
      }

      if ($isstare) {
	# FIX UP - it does not make any sense to have another
	# offset iterator below this level but we do support it
	my @offsets = @{ $this->{$key}->{ATTR}};

	# and store it back
	$this->{$key}->{ATTR} = [ { offsets => \@offsets } ];
      }
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

# Returns list of children
sub _list_children {
  my $self = shift;
  my $this = shift;

  my @children;
  for my $key (keys %$this) {

    # Store all children
    push(@children,$key);

    if (UNIVERSAL::isa($this->{$key},"HASH") &&
	exists $this->{$key}->{CHILDREN}) {
      # This means we have some children to analyze
      for my $child (@{ $this->{$key}->{CHILDREN} }) {
	push(@children,$self->_list_children( $child ));
      }
    }
  }
  return @children;
}

=item B<fudge_raster_offsets>

Given an unrolled observation, duplicate it for all offsets if we
happen to have a raster with multiple offsets defined.

  @obs = OMP::Translator::DAS->fudge_raster_offsets( $obs );

This is required because it is difficult to correct the sequence
directly if a raster and sample share the same offset iterator.

In most cases simply returns the input argument.

=cut

sub fudge_raster_offsets {
  my $self = shift;
  my $obs = shift;

  my @outobs;
  if ($obs->{MODE} eq 'SpIterRasterObs' && exists $obs->{offsets}) {
    for my $off (@{$obs->{offsets}}) {
      my %newobs = %$obs;
      $newobs{OFFSET_DX} = $off->{OFFSET_DX};
      $newobs{OFFSET_DY} = $off->{OFFSET_DY};
      $newobs{OFFSET_PA} = $off->{OFFSET_PA};
      delete $newobs{offsets};
      push(@outobs, \%newobs);
    }

  } else {
    push(@outobs, $obs);
  }
  return @outobs;
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

  $html .= "<H1>Project: <a href=\"http://omp.jach.hawaii.edu/cgi-bin/projecthome.pl?urlprojid=$project\">$project</a></H1>\n";

  $html .= "<ul>\n";
  $html .= "<li><em>Please remember to set project ID to <em>$project</em> in the acquisition system.</em>\n";
  my $cat = $VAX_TRANS_DIR . $CATALOGUE;
  $html .= "<LI>Target information has been written to catalogue file: <b>$cat</b> when appropriate. The additional target information in this document is for information only (or may be a comet or planet). The catalogue includes pointing targets.\n";
  $html .= "</ul>\n";

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
    # Notes have to be in PRE blocks to preserve formatting
    $html .= "<h2>Note: $ntitle</h2>\n<PRE>\n$note\n</PRE>\n";
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

=item B<obsMode>

Return the observing mode for this observation (as understood by the OCS).

  $mode = OMP::Translator::DAS->obsMode( %summary );

Allowed responses are: SAMPLE, RASTER, GRID, PATTERN, POINTING, FOCUS

=cut

sub obsMode {
  my $self = shift;
  my %summary = @_;

  my $otMode = $summary{MODE};

  my $mode;
  if ($otMode eq 'SpIterStareObs') {
    # Work it out from the offsets
    if (exists $summary{offsets} ) {
      use Data::Dumper;
      print Dumper(\%summary);
      my %data = offsets_to_grid( @{ $summary{offsets} } );
      $mode = $data{TYPE};
    } else {
      $mode = "SAMPLE";
    }

  } elsif ($otMode eq 'SpIterRasterObs' ) {
    $mode = "RASTER";
  } elsif ($otMode eq 'SpIterFocusObs') {
    $mode = "FOCUS";
  } elsif ($otMode eq 'SpIterPointingObs') {
    $mode = "POINTING";
  } else {
    throw OMP::Error::TranslateFail("Unable to translate mode $otMode to heterodyne observation");
  }

  return $mode;
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
  # I *think* it is optical
  if ($freqconfig{velocityDefinition} eq 'redshift') {
    $freqconfig{velocityDefinition} = "optical [derived from redshift]";
  }

  # Velocity units
  my $velunits = "km/s";

  my $html = "<h3>Frontend configuration: <em>".
    $summary{instrument}."</em></h3>\n";
  $html .= "<table>";
  $html .= "<tr><td><b>Molecule:</b></td><td>".
    (defined $freqconfig{molecule} ? $freqconfig{molecule} : "No line")
      ."</td></tr>";
  $html .= "<tr><td><b>Transition:</b></td><td>".
    (defined $freqconfig{transition} ? $freqconfig{transition} : "No line")
      ."</td></tr>";
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

  my $vframe = ((exists $freqconfig{velocityFrame} && 
		defined $freqconfig{velocityFrame}) ? $freqconfig{velocityFrame}
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

  my $html;
  if ($summary{autoTarget})  {
    $html = "<H3>Target information: Please choose a suitable target</H3>\n";

    $html .= "No target has been chosen for this observation. Choice of a suitable target is at your discretion.<br>\n";
    if ($summary{standard}) {
      $html .= "<em>Please note that this observation is inside a calibration block so it might be advisable to choice a calibration source.</em>\n";

    }

  } elsif ($summary{standard}) {
    $html = "<H3>Target information: Please choose a suitable target</H3>\n";

    $html .= "No target has been chosen for this calibration observation. Choice of a suitable calibration target is at your discretion.\n";

  } else {

    my $c = $summary{coords};
    $c->telescope( new Astro::Telescope('JCMT') );

    $html .= "<H3>Target Information: <em>".$summary{target}."</em></H3>\n";
    $html.= "<PRE>". $c->status ."</PRE>\n";
  }

  return $html;

}

=item B<switchConfig>

Return the HTML associated with this particular switch configuration.

  $html .= OMP::Translator::DAS->switchConfig( %summary );

=cut

sub switchConfig {
  my $self = shift;
  my %summary = @_;

  my $html = '';

  # Force PSSW if Raster mode
  $summary{switchingMode} = "Position" if $summary{MODE} eq 'SpIterRasterObs';

  throw OMP::Error::TranslateFail("Switching mode not specified")
    unless exists $summary{switchingMode} && defined $summary{switchingMode};

  # Allowed options are Beam, Position and Frequency
  if ($summary{switchingMode} eq 'Beam') {

    throw OMP::Error::TranslateFail("Can not do a Beam-switched RASTER")
      if $summary{MODE} eq 'SpIterRasterObs';

    $html .= "<h3>Switch mode: Beam switched</h3>\n";

    $html .= "<table>";
    $html .= "<tr><td><b>Chop System:</b></td><td>".
      $summary{CHOP_SYSTEM}." </td></tr>";
    $html .= "<tr><td><b>Chop Throw:</b></td><td>".
      $summary{CHOP_THROW}." arcsec</td></tr>";
    $html .= "<tr><td><b>Chop PA:</b></td><td>".
      $summary{CHOP_PA}." deg</td></tr>";


    $html .= "</table>\n";


  } elsif ($summary{switchingMode} eq 'Position') {

    # First look for a REFERENCE
    throw OMP::Error::TranslateFail("Position switched observation did not specify a REFERENCE") unless exists $summary{coordtags}->{REFERENCE};

    $html .= "<h3>Switch mode: Position switched</h3>";

    my $ref = $summary{coordtags}->{REFERENCE};

    # Position switch positions must be specified as offsets from Base
    # even if we have a real position
    my $refc = $ref->{coords};
    my $refoffx = $ref->{OFFSET_DX};
    my $refoffy = $ref->{OFFSET_DY};

    # if we have some offsets just use them directly
    my ($offx,$offy);
    if (defined $refoffx && defined $refoffy) {
      ($offx,$offy) = ($refoffx, $refoffy);

    } else {
      # The base position
      my $c= $summary{coords};

      # Get the distance to the centre
      my @offsets = $c->distance($refc);

      # Convert to arcseconds
      ($offx, $offy) = map { sprintf("%.1f",$_ * Astro::SLA::DR2AS) } @offsets;
    }

    $html .= "Position switch reference position is at offset (<b>$offx</b>, <b>$offy</b>) arcsec\n [Tangent plane offsets in the tracking coordinate system from the tracking centre]\n";

  } elsif ($summary{switchingMode} =~ /Frequency/) {

    throw OMP::Error::TranslateFail("Can not do a Frequency-switched RASTER")
      if $summary{MODE} eq 'SpIterRasterObs';

    # Sanity check Fast with Slow
    my $fast = ($summary{switchingMode} =~ /fast/i ? 1 : 0);

    $html .= "<h3>Switch mode: Frequency switched</h3>";

    $html .= "<table>";
    $html .= "<tr><td><b>Mode:</b></td><td>".
      ($fast ? "Fast" : "Slow") . " </td></tr>";
    $html .= "<tr><td><b>Offset:</b></td><td>".
      $summary{frequencyOffset}." MHz</td></tr>";
    $html .= "<tr><td><b>Switch rate:</b></td><td>".
      $summary{frequencyRate}." Hz</td></tr>" if $fast;
    $html .= "</table>\n";

  } else {
    throw OMP::Error::TranslateFail("Unrecognized switch mode: $summary{switchingMode}");
  }

  return $html;
}

=item B<offsetConfig>

Return any information concerning the offset position for the observation.

  $html .= OMP::Translator::DAS->offsetConfig( %summary );

For PATTERN observing this will return no offset.

=cut

sub offsetConfig {
  my $self = shift;
  my %summary = @_;

  my $html = '';



  return $html;
}

=item B<SpIterStareObs>

SAMPLE/GRID/PATTERN details.

  ($html, %files) = OMP::Translator::DAS->SpIterStareObs( %summary );

The hash contains the pattern file details (if appropriate).
The keys are the names of the files to be written, the values
are reference to arrays containing the contents of the file.

=cut

sub SpIterStareObs {
  my $self = shift;
  my %summary = @_;

  my $html = '';
  my %extras;

  # Underlying sample details are pretty straightforward
  $html .= "<h3>Sample details:</h3>\n";

  $html .= "<table>";
  $html .= "<tr><td><b>Number of cycles per sample:</b></td><td>".
      $summary{nintegrations} . " </td></tr>";
  $html .= "<tr><td><b>Seconds per cycle:</b></td><td>".
      $summary{secsPerCycle} . " sec</td></tr>";
  $html .= "<tr><td><b>Continuous cal?</b></td><td>".
      $summary{continuousCal} . " </td></tr>";
  $html .= "<tr><td><b>Cycle Reversal?</b></td><td>".
      $summary{cycleReversal} . " </td></tr>";

  $html .= "</table>\n";

  # Now we need to do is get the mode
  my %data = offsets_to_grid( @{ $summary{offsets} } );

  # Offsets
  if ($data{TYPE} eq 'SAMPLE' || $data{TYPE} eq 'GRID') {

    # Map centre (offset and PA)
    # if we had used an offset iterator
    my @offsets = @{ $data{OFFSETS}->[0] };
    if ($offsets[0] != 0.0 && $offsets[1] != 0.0) {
      $html .= "This observation is offset from the tracking centre:\n";

      $html .= "<table>";
      $html .= "<tr><td><b>X offset:</b></td><td>".
	$offsets[0] . " arcsec</td></tr>";
      $html .= "<tr><td><b>Y offset:</b></td><td>".
	$offsets[1] . " arcsec</td></tr>";
      $html .= "<tr><td><b>Position Angle:</b></td><td>".
	$data{PA} . " deg</td></tr>";
      $html .= "</table>\n";
    } else {
      $html .= "This observation is centred on the tracking centre.<BR>\n";
    }

  }

  # Specific parameters
  if ($data{TYPE} eq 'GRID') {
    $html .= "This is a GRID observation. The GRID parameters are:\n";

      $html .= "<table>";
      $html .= "<tr><td><b>Number of samples in X:</b></td><td>".
	$data{GRID_NX} . " </td></tr>";
      $html .= "<tr><td><b>Number of samples in Y:</b></td><td>".
	$data{GRID_NY} . " </td></tr>";
      $html .= "<tr><td><b>X increment:</b></td><td>".
	$data{GRID_DX} . " arcsec</td></tr>";
      $html .= "<tr><td><b>Y increment:</b></td><td>".
	$data{GRID_DY} . " arcsec</td></tr>";
      $html .= "<tr><td><b>GRID Position Angle:</b></td><td>".
	$data{PA} . " deg</td></tr>";
      $html .= "</table>\n";

  } elsif ($data{TYPE} eq 'PATTERN') {

    # Store the offsets in an array
    # where each line is "dx dy"
    # One offset per array element
    my @lines = map { $_->[0] ."," . $_->[1] } @{ $data{OFFSETS} };
    unshift(@lines, "# CENTRE_OFFSET_X,      CENTRE_OFFSET_Y");

    # Determine a filename
    my $pattfile = "pattern" . sprintf("%03d",_get_next_file_number()) .".dat";

    $html .= "This is a PATTERN observation containing ".(scalar(@lines)-1)." offset positions. The coordinates are stored in file <b>$VAX_TRANS_DIR"."$pattfile</b>\n<br>";

    $html .= "Note that the Position Angle of these offsets is non-zero so cell must be set accordingly. The PA is $data{PA} deg.<br>\n" if $data{PA} != 0.0;

    $html .= "The offsets are (in arcsec):\n";
    $html .= "<table>\n";
    $html .= "<tr><td><b>dX</b></td><td><b>dY</b></td></tr>\n";
    for (@{$data{OFFSETS}}) {
      $html .= "<tr><td>".$_->[0]."</td><td>".$_->[1]."</td></tr>\n";
    }
    $html .="</table>\n";

    # Now create the real file name (full path)
    $pattfile = File::Spec->catfile($TRANS_DIR,$pattfile);

    # Store it
    $extras{$pattfile} = \@lines;

  } elsif ($data{TYPE} ne 'SAMPLE') {
    throw OMP::Error::FatalError("Unable to determine sample type");
  }


  return ($html, %extras);
}

=item B<SpIterRasterObs>

Raster details.

  ($html) = OMP::Translator::DAS->SpIterRasterObs( %summary );

=cut

sub SpIterRasterObs {
  my $self = shift;
  my %summary = @_;

  my $html = '';

  $html .= "<H3>Rastering details</H3>\n";

  # Map centre (offset and PA)
  # if we had used an offset iterator
  if (exists $summary{OFFSET_DX} && exists $summary{OFFSET_DY} &&
      exists $summary{OFFSET_PA}) {
    $html .= "This raster map is offset from the tracking centre:\n";

    $html .= "<table>";
    $html .= "<tr><td><b>X offset:</b></td><td>".
      $summary{OFFSET_DX} . " arcsec</td></tr>";
    $html .= "<tr><td><b>Y offset:</b></td><td>".
      $summary{OFFSET_DY} . " arcsec</td></tr>";
    $html .= "<tr><td><b>Position Angle:</b></td><td>".
      $summary{OFFSET_PA} . " deg</td></tr>";
    $html .= "</table>\n";

  }

  # Map size
  $html .= "Map parameters:\n";

  # Need the Delta X and the Number of X 
  my $dx = $summary{SCAN_VELOCITY} * $summary{sampleTime};

  # Make sure the number of positions encompasses the full size
  my $nx = int(($summary{MAP_WIDTH} / $dx) + 0.99);
  my $ny = int(($summary{MAP_HEIGHT} / $summary{SCAN_DY}) +0.99);

  $html .= "<table>";
  $html .= "<tr><td><b>Sample time per point:</b></td><td>".
    $summary{sampleTime} . " sec</td></tr>";
  $html .= "<tr><td><b>Number of rows:</b></td><td>".
    $ny . " </td></tr>";
  $html .= "<tr><td><b>Number of samples per row:</b></td><td>".
    $nx . " </td></tr>";
  $html .= "<tr><td><b>X pixel increment:</b></td><td>".
    $dx." arcsec</td></tr>";
  $html .= "<tr><td><b>Y scan increment:</b></td><td>".
    $summary{SCAN_DY}." arcsec</td></tr>";
  $html .= "<tr><td><b>Map position angle:</b></td><td>".
    $summary{MAP_PA}." deg</td></tr>";
  $html .= "</table>\n";

  return ($html);
}

=item B<SpIterPointingObs>

A simple pointing. No action needed.

=cut

sub SpIterPointingObs {
  return ("");
}

=item B<SpIterFocusObs>

A simple focus. No action needed.

=cut

sub SpIterFocusObs {
  return ("");
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

# Given an array of offsets (OFFSET_DX,OFFSET_DY,PA) determine
# whether they are on a regular grid or random
# If random, return an array offsets that have a fixed PA
# (usually 0.0)
# Note that we can return a PATTERN even if the offsets are gridded.
# This is because the order is important. Filling a grid in a non-standard
# order assumes we do not want to use a GRID

# Note that from the translator point of view this is all crazy. we should
# always return a pattern file since the TSS will not notice the difference.
# It would save a lot of worrying in this routine!

# Returns a hash with keys:
#  TYPE =>  SAMPLE or PATTERN or GRID
#  GRID_DX => X spacing in arcseconds   [GRID]
#  GRID_DY => Y spacing in arcseconds   [GRID]
#  GRID_NX => Number of positions in X  [GRID]
#  GRID_NX => Number of positions in Y  [GRID]
#  PA => Position angle of offsets    [GRID and PATTERN and SAMPLE]
#  OFFSETS => Array of arrays with OFFSET_DX and OFFSET_DY [ALL]
#       for SAMPLE and GRID there will be a single offset (the centre position)

# Note that if the offsetx/y of the GRID is not the centre of the
# grid (ie the grid has even NX or NY) then we return the coordinates
# as a PATTERN because the Heterodyne system can not support an even GRID

sub offsets_to_grid {
  my @offsets = @_;

  # If there is only one offset we have a SAMPLE not PATTERN or GRID
  if (scalar(@offsets) == 1) {
    return (TYPE => 'SAMPLE', 
	    PA => $offsets[0]->{OFFSET_PA},
	    OFFSETS => [ [ $offsets[0]->{OFFSET_DX},
			   $offsets[0]->{OFFSET_DY} ]]);
  } elsif (scalar(@offsets) == 0) {
    # No offsets - just use the origin
    return (TYPE => 'SAMPLE', PA=>0.0, OFFSETS=>[[0.0,0.0]]);
  }

  # All the offsets should be at a single PA (that is what the OT
  # generates) but it does no harm to check this)
  my %pa;
  for my $off (@offsets) {
    $pa{$off->{OFFSET_PA}}++;
  }
  throw OMP::Error::TranslateFail("This offset iterator contained offsets at differing position angles - not supported") 
    if (scalar(keys %pa) > 1);

  # For the results
  my %results;
  $results{PA} = $offsets[0]->{OFFSET_PA};

  # First need to determine whether we are a gridded observation
  # Use hashes at first to remove duplicates
  # And calculate the min and max extent
  my %x;
  my %y;
  for my $off (@offsets) {
   $x{$off->{OFFSET_DX}}++;
   $y{$off->{OFFSET_DY}}++;
  }

  # Sort
  my @xsort = sort { $a <=> $b } keys %x;
  my @ysort = sort { $a <=> $b } keys %y;

  # If we have an even number of X or Y offsets we cannot implement
  # this as a heterodyne GRID - must be a pattern because the grid
  # centre must be inclusive
  if ((scalar(@xsort) % 2) != 1 || (scalar(@ysort) % 2) != 1 ) {
    $results{TYPE} = "PATTERN";
  }

  # Find extent
  my $xmin = $xsort[0];
  my $xmax = $xsort[-1];
  my $ymin = $ysort[0];
  my $ymax = $ysort[-1];

  # This is probably not the most efficient algorithm...

  # Go through all the X+Y coordinates making sure that they increment
  # by a constant amount
  #use Data::Dumper;
  #print Dumper(\@xsort,\@ysort);
  my $contig = 0;

  if (!exists $results{TYPE}) {
    $contig = 1; # Assume gridded until proven otherwise
  XY: for my $xy (\@xsort, \@ysort) {
      my $delta;
      # if we have more than one coordinate in the dimension
      if (scalar(@$xy) > 1) {
	for my $i (1..$#$xy) {
	  my $diff = $xy->[$i] - $xy->[$i-1];
	  if (defined $delta) {
	    # Must compare with previous value
	    if ($diff != $delta) {
	      # non-contiguous
	      $contig=0;
	      print "Delta: $delta  Diff: $diff I: $i\n";
	      last XY;
	    }
	  } else {
	    # First time through can have no error
	    $delta = $diff;
	  }
	}
      }
    }
  }

  # if the numbers were contiguous we can do more investigating
  # into the GRID-ness
  if ($contig) {
    # We know the X and Y deltas are even so use them to generate
    # a best guess grid
    # First make a guess at the dx and dy for the grid
    # We are simply trying to disprove the grid theory and call it a pattern
    my $dx = 0;
    my $dy = 0;

    $dx = $xsort[1] - $xsort[0] if scalar(@xsort) > 1;
    $dy = $ysort[1] - $ysort[0] if scalar(@ysort) > 1;

    # Make a two dimensional array and fill it with zeroes
    # We then go through all the offsets and make sure they correspond
    # with the expected position in a GRID pattern

    # Number in each dimension
    my $nx = scalar(@xsort);
    my $ny = scalar(@ysort);

    print "DX= $dx NX=$nx DY = $dy  NY=$ny\n";

    # Simply calculate the expected offsets and compare with what
    # we got
    my $n = 0; # offset counter
    # Y changes slower than X
    # Assumes you start at xmin,ymin and increment by dx until you need
    # to increment dy (resetting to the start of the row). This means
    # no scan reversal.
    ROW: for my $iy (1..$ny) {
	# Expected Y offset
	my $ey = $ymin + ($dy*($iy-1));
	print "Y offset = $ey\n";
	for my $ix (1.. $nx) {
	  # This is the requested offset
	  my $off = $offsets[$n];

	  # This is the X expected offset
	  my $ex = $xmin + ($dx*($ix-1));
	  print "X offset = $ex [counter= $n]\n";

	  print "Required offset: ". $off->{OFFSET_DX} .",".
	    $off->{OFFSET_DY}."\n";
	  # Compare offsets
	  if ($off->{OFFSET_DX} != $ex ||
	      $off->{OFFSET_DY} != $ey) {
	    # This is not a grid in the expected order
	    $contig = 0;
	    print "NON-CONTIGUOUS: GRID\n";
	    last ROW;
	  }
	
	  # increment the offset index
	  $n++;
	}
      }

    if ($contig) {
      $results{TYPE} = "GRID";

      # Store the parameters
      $results{GRID_DX} = $dx;
      $results{GRID_DY} = $dy;
      $results{GRID_NX} = $nx;
      $results{GRID_NY} = $ny;

      # The reference offset is from the middle of the grid
      # we know that NX and NY are odd
      throw OMP::Error::FatalError("NX and NY must be odd by this point in the code - internal error [got $nx and $ny]")
	if (($nx % 2) != 1 || ($ny % 2) != 1);
      $results{OFFSETS} = [[$xmin + (($nx-1)/2)*$dx, $ymin + (($ny-1)/2)*$dy]];

      print Dumper(\%results);

      return %results;

    } else {
      $results{TYPE} = "PATTERN";
    }
  } else {
    $results{TYPE} = "PATTERN";
  }

  # Now we know where we are going
  if (!exists $results{TYPE}) {
    throw OMP::Error::FatalError("Somehow we did not manage to select a type: GRID, PATTERN or SAMPLE");

  } elsif ($results{TYPE} eq 'PATTERN') {
    # Create array of array offsets
    my @off;
    for my $off (@offsets) {
      push(@off, [ $off->{OFFSET_DX}, $off->{OFFSET_DY}] );
    }

    $results{OFFSETS} = \@off;
    print Dumper(\%results);

  } elsif ($results{TYPE} eq 'GRID') {
    throw OMP::Error::FatalError("Unexpectedly obtained GRID solution");

  } else {
    throw OMP::Error::TranslateFail("Internal error processing offsets. Was neither a GRID nor a PATTERN file");

  }

  return %results;

}

# This is just returns a number that is guaranteed to increase
# by 1 each time it is called
my $start = 0;
sub _get_next_file_number {
  $start++;
  return $start;
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
