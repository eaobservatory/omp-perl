package OMP::Translator;

=head1 NAME

OMP::Translator - translate science program to sequence

=head1 SYNOPSIS

  use OMP::Translator;

  $results = OMP::Translator->translate( $sp );


=head1 DESCRIPTION

This class converts a science program object (an C<OMP::SciProg>)
into a sequence understood by the data acquisition system.

In the case of SCUBA, an Observation Definition File (ODF) is
generated (or multiple ODFs). For DAS heterodyne systems a HTML
summary of the MSB will be generated. For ACSIS, XML configuration files
are generated.

The actual translation is done in a subclass. The top level class
determines the correct class to use for the MSB and delegates the
translation of each observation within the MSB to that class.

=cut

use 5.006;
use strict;
use warnings;

use File::Spec;
use Scalar::Util qw/ blessed /;
use DateTime;
use File::Path qw/ mkpath /;
use Time::HiRes qw/ gettimeofday /;
use Data::Dumper;

# Path must include the queue classes
use Queue::EntryXMLIO qw/ writeXML /;

use OMP::Constants qw/ :msb /;
use OMP::SciProg;
use OMP::Error qw/ :try /;
use OMP::General;

our $VERSION = (qw$Revision$)[1];
our $DEBUG = 0;
our $VERBOSE = 0;

=head1 METHODS

=over 4

=item B<translate>

Convert the science program object (C<OMP::SciProg>) into
a observing sequence understood by the instrument data acquisition
system.

  $xmlfile = OMP::Translate->translate( $sp );
  $data = OMP::Translate->translate( $sp, asdata => 1 );
  @data = OMP::Translate->translate( $sp, asdata => 1,
                                          simulate => 1);

The actual translation is implemented by the relevant subclass.
Currently JCMT Heterodyne and SCUBA data can be translated.

By default, this method returns the name of an XML file that specifies
the location of each translated configuration using the dialect
understood by the standard JAC observing queue interface.

Optional arguments can be specified using hash technique. Allowed keys
are:

  simulate : Generate a translation suitable for simulate mode (if supported)

  log    : Log verbose messages to file. If the global $VERBOSE is true, then
           messages will also go to stdout. If $VERBOSE is false then
           verbosity will be enabled in the translation class but only to log file.

  asdata : If true, method will return either a list of translated 
            configuration objects (the type of which depends on
            the instrument) or a reference to an array of such objects
            (depending on context).  The expected object classes will be:

  SCUBA -   SCUBA::ODF
  ACSIS -   JAC::OCS::Config
  DAS   -   OMP::Translator::DASHTML

If there is more than one MSB to translate, REMOVED MSBs will be ignored.

=cut

sub translate {
  my $self = shift;
  my $thisclass = ref($self) || $self;
  my $sp = shift;

  my %opts = ( asdata => 0, simulate => 0, log => 0, @_);

  print join("\n",$sp->summary('asciiarray'))."\n" if $DEBUG;

  # See how many MSBs we have (after pruning)
  my @msbs = $self->PruneMSBs($sp->msb);
  print "Number of MSBS to translate: ". scalar(@msbs) ."\n"
    if $DEBUG;

  # Return immediately if we have nothing to translate
  return () if scalar(@msbs) == 0;

  # The high level translator classes must process each MSB in turn
  # and on the basis of the instrument content, delegate the content
  # to an instrument specific translator.
  # The complication is that if an MSB includes multiple Observations
  # each of which is a different instrument, the translator must
  # delegate each Observation to each instrument in turn.

  # What we will end up doing is
  #   1. Unrolling the MSBs into individual observes
  #   2. sending the unrolled information one at a time to each translator
  #   3. hold the translated output in memory
  #   4. write out everything at once

  # Translator class associated with each instrument
  # This should be configuration driven
  #  OMP::Config->getData( 'translator.SCUBA' );
  my %class_lut = ( SCUBA => 'SCUBA',
		    A3 => 'DAS',
		    B3 => 'DAS',
		    WC => 'DAS',
		    WD => 'DAS',
		    RXA3 => 'DAS',
		    RXA3 => 'DAS',
		    RXB3 => 'DAS',
		    RXWC => 'DAS',
		    RXWD => 'DAS',
		    RXW=> 'DAS',
		    HARP => 'ACSIS',
		    # the backend name is the one that counts
		    DAS => 'ACSIS',
		    ACSIS => 'ACSIS',
		  );

  # Array of file handles that we should write verbose messages to
  my @handles = ();
  push(@handles, \*STDOUT) if $VERBOSE;  # we want stdout messages if verbose

  # Decide on low-level verbosity setting. Should be derived from the global
  # class $VERBOSE and also the logging functionality.
  my $verbose = $VERBOSE;
  my $logh;
  if ( $opts{log} ) {
    try {
      # get hi resolution time
      my ($sec, $mic_sec) = gettimeofday();
      my $ut = DateTime->from_epoch( epoch => $sec, time_zone => 'UTC' );

      # need ut date (in eval if logdir does not exist)
      my $logdir = OMP::Config->getData( 'acsis_translator.logdir', utdate => $ut );

      # try to make the directory - which may fail hence the try block
      mkpath( $logdir );

      # filename with date stamp
      my $fname = "translation_". $ut->strftime("%Y%m%d_%H%M%S") . "_" .
	sprintf("%06d", $mic_sec ) . ".log";

      # now try to open a file
      open( $logh, ">", File::Spec->catfile($logdir,$fname))
	|| die "Error opening log file $fname: $!";

      # Have logging so force verbose and store filehandle
      $verbose = 1;
      push(@handles, $logh);
    } otherwise {
      # no logging around
    };
  }

  # Log the translation details with the OMP
  my $projectid = $sp->projectID;
  my @checksums = map { $_->checksum . "\n" } $sp->msb;
  OMP::General->log_message( "Translate request: Project:$projectid Checksums:\n\t"
			     .join("\t",@checksums)
			   );

  # Loop over each MSB
  my @configs; # Somewhere to put the translated output
  for my $msb (@msbs) {

    # Survey Containers in child nodes present a problem since
    # the _get_SpObs method does not return clones for each target
    # that is present in the survey container (maybe it should)
    # That logic is currently contained in the SpSurveyContainer
    # parse and the MSB stringification. MSB stringification also
    # correctly handles the override targets from a parent survey
    # container

    # rather than duplicating container logic in another place
    # we either need to
    # 1. Fix _get_SpObs (or add a new method) to return cloned 
    #    SpObs nodes with the correct target available
    # 2. Reparse from a stringified form

    # 2 is quicker but we also need to solve the suspend problem
    # since survey containers do not currently deal with obs_counters
    # properly when summarising.

    # Force stringify
    my $msbxml = "$msb";

    # regenerate
    my $fullmsb = new OMP::MSB( XML => $msbxml,
				PROJECTID => $msb->projectID,
				OTVERSION => $msb->ot_version,
				TELESCOPE => $msb->telescope,
			      );

    # Get all the component nodes (Sp* is fine 
    # since we want SpInst and SpObsComp)
    # unless this MSB is actually an SpObs
    my @components;
    @components = grep { $_->getName =~ /Sp.*/ && $_->getName ne 'SpObs'} 
      $fullmsb->_tree->findnodes( 'child::*' )
	unless $fullmsb->_tree->getName eq 'SpObs';

    # Need to include all the code for determining whether the MSB
    # was suspended and whether to skip the observation or not
    my $suspend = $msb->isSuspended;

    # by default do not skip observations unless we are suspended
    my $skip = ( defined $suspend ? 1 : 0);

    # Loop over each SpObs separately since that controls the 
    # instrument granularity (each SpObs can only refer to a single instrument)
    for my $spobs ($fullmsb->_get_SpObs) {

      # We need to create a mini MSB object derived from each SpObs
      # For this to work, we need to copy the Component nodes from the
      # main SpMSB into the start of the SpObs itself

      # Get the first child of the SpObs (as an insertion point)
      my $child = $spobs->firstChild;

      # Insert telescope information

      # now insert the component nodes
      for my $node ( @components ) {
	$spobs->insertBefore( $node, $child );
      }

      # Create a dummy MSB object (which will be fine so long as we
      # do not access attributes of an MSB such as isSuspended)
      my $tmpmsb = new OMP::MSB( TREE => $spobs,
				 PROJECTID => $msb->projectID,
				 OTVERSION => $msb->ot_version,
			       );

      # Now we can ask this MSB for its instrument
      # First we need to summarise the observation
      my @sum = $tmpmsb->obssum();

      # And verify that we can load the correct translator
      # by getting the instrument
      my $inst = uc($sum[0]->{instrument});

      # and overriding this with backend if we have one
      $inst = uc($sum[0]->{freqconfig}->{beName})
	if (exists $sum[0]->{freqconfig} && 
	    exists $sum[0]->{freqconfig}->{beName});


      # check we have the class
      throw OMP::Error::TranslateFail("Instrument '$inst' has no corresponding Translator class")
	unless exists $class_lut{$inst};

      # Create the full class name
      my $class = $class_lut{$inst};
      $class = $thisclass . '::' . $class;
      print "Class is : $class\n" if $DEBUG;

      # Load the class
      eval "require $class;";
      if ($@) {
	throw OMP::Error::FatalError("Error loading class '$class': $@\n");
      }

      # Set DEBUGGING in the class depending on the debugging state here
      $class->debug( $DEBUG );

      # enable verbose logging
      $class->verbose( $verbose ) if $class->can("verbose");

      # and register filehandles
      $class->outhdl( @handles ) if $class->can("outhdl");

      if (defined $logh) {
	print $logh "---------------------------------------------\n";
      }

      # And forward to the correct translator
      # We always get objects, sometimes multiple objects
      my @new = $class->translate( $tmpmsb, simulate => $opts{simulate} );

      if (defined $logh) {
	# Basic XML
	print $logh "---------------------------------------------\n";
	print $logh "Input MSB:\n";
	print $logh "$tmpmsb\n";
	print $logh "---------------------------------------------\n";

	# Summary
	my $info = $tmpmsb->info();
	my $summary = $info->summary("hashlong");

	print $logh "Observation Summary:\n";
	print $logh Dumper($summary);
	print $logh "---------------------------------------------\n";
      }

      # Reset handles so that the globals do not hang around
      $class->outhdl( undef ) if $class->can("outhdl");

      # Now force translator directory into config
      # All of the objects returned by translate() support the outputdir() method
      $_->outputdir( $class->transdir ) for @new;

      # Store them in the main config array
      push(@configs, @new);

    }

  }

  # Clear logging handles.
  @handles = ();

  # Now we have an array of translated objects
  # Array of SCUBA::ODF objects
  #   - What do we do about the waveplate files?
  # Array of JAC::OCS::Config objects
  #
  # Now need to either return them or write them to disk
  # If we write them to disk we return the QueueEntry XML to the
  # caller.

  # SCUBA::ODF and JAC::OCS::Config should have the same interface
  # for writing to disk. OMP::Translator::DASHTML also matches.

  # If they want the data we do not write anything
  if ($opts{asdata}) {

    # disable the loggin
    for (@configs) {
      $_->outhdl( undef ) if $_->can("outhdl");
    }

    if (wantarray) {
      return @configs;
    } else {
      return \@configs;
    }
  } else {
    # We write to disk and return the name of the wrapper file
    my $xml = $self->write_configs( \@configs );

    # clear logging
    for (@configs) {
      $_->outhdl( undef ) if $_->can("outhdl");
    }
  }
}


=item B<outputdir>

Set (or retrieve) the default output directory for writing config information.
Initially unset.

  $dir = OMP::Translator->outputdir();
  OMP::Translator->outputdir();

If no output directory has been specified explicitly, the output directory
will depend on the default specified for each translator (which may be
class specific).

=cut

{
  my $OUTPUT_DIR;
  sub outputdir {
    my $self = shift;
    if (@_) {
      $OUTPUT_DIR = shift;
    }
    return $OUTPUT_DIR;
  }
}

=item B<backwards_compatibility_mode>

Controls the global state of the translator when writing output files.
By default, files are written in a format suitable for uploading to
the new OCS queue using an XML format.

If this switch is enabled, the file name returned by the translator
will be instrument specific and multiple instruments can not be
combined within a single translation.

=cut

  {
    my $cmode = 0;
    sub backwards_compatibility_mode {
      my $class = shift;
      if ( @_ ) {
	$cmode = shift;
      }
      return $cmode;
    }
  }


=item B<write_configs>

Write each config object to disk and return the name of an XML
file containing all the information required for loading the OCS queue.

  $qxml = OMP::Translator->write_configs( \@configs );

This method does not care what type of object is passed in so long
as the following methods are supported:

 telescope  - name of telescope
 instrument - name of instrument
 duration   - estimated duration (Time::Seconds)
 write_file - write file to disk and return name of file

An exception is thrown if the telescope is not the same for each
config.

By default the configs are written to the directory suitable for each type of
translation (ie whatever is in each object), unless either an explcit
global C<outputdir> is defined or an explicit directory is provided to this
method through the C<transdir> option.

 $qxml = OMP::Translator->write_configs( \@configs, transdir => $dir);

=cut

sub write_configs {
  my $class = shift;
  my $configs = shift;
  my %opts = @_;

  # Specified outputdir overrides default
  my $outdir;
  if (defined $opts{transdir}) {
    $outdir = $opts{transdir};
  } elsif (defined $class->outputdir) {
    $outdir = $class->outputdir;
  }

  if ( $class->backwards_compatibility_mode) {

    # check our config objects are all the same type
    my $class = blessed( $configs->[0] );
    my $inst = $configs->[0]->instrument;
    for my $c ( @$configs ) {
      if ( blessed($c) ne $class) {
	throw OMP::Error::TranslateFail( "Attempting to write different instrument configurations to incompatible output files. Compatibility mode only supports a single translated instrument/backend [$inst vs ".$c->instrument."]");
      }
    }

    # Now work out the container class
    my $cclass = $configs->[0]->container_class();
    eval "require $cclass;";
    throw OMP::Error::FatalError("Unable to load container class $cclass: $@")
      if $@;

    # And create it blank
    my $container = $cclass->new();

    # Store the configs inside
    $container->push_config( @$configs );

    # Now write the container
    return $container->write_file( (defined $outdir ? $outdir : () ),
				   { chmod => 0666 });

  } else {

    # Arguments
    my %args = ( fprefix => 'translated',
		 chmod => 0666,
	       );
    $args{outputdir} = $outdir if defined $outdir;

    # XML location is required for the queue. This is not instrument
    # dependent but if $outdir is defined we must use it. Else
    # we use the config system
    if (defined $outdir) {
      $args{xmldir} = $outdir;
    } else {
      # specify our default location
      my $qdir;
      eval {
	$qdir = OMP::Config->getData( "translator.queuedir" );
      };
      $qdir = File::Spec->curdir() if !defined $qdir;
      $args{xmldir} = $qdir;
    }

    # Delegate the writing to the XMLIO class
    return Queue::EntryXMLIO::writeXML(\%args,
				       @$configs );
  }

}

=back

=head2 Helper Routines

Routines common to more than one translator.

=over 4

=item <PosAngRot>

Rotate coordinates through a specified position angle.
Position Angle is defined as "East of North". This means
that the rotation angle is a reverse of the normal mathematical definition
of "North of East"

          N
          ^
          |
          |
    E <---+

In the above diagram (usually RA/Dec) the position angle will be
positive anti-clockwise.

  ($x2, $y2) = OMP::Translator->PosAngRot( $x1, $y1, $PA );

where PA is given in degrees and not radians (mainly because
the Science Program rotation angles are all given in degrees).

Note that this routine should really be in some generic Math::
or Coords:: class. Note also that this is a class method to
facilitate use in subclasses.

After rotation, the accuracy is limited to two decimal places.

=cut

use constant DEG2RAD => 3.141592654 / 180.0;

sub PosAngRot {
  my $self = shift;
  my ($x1, $y1, $pa) = @_;

  # New coordinates
  my ($x2,$y2);

  # Do rotation if rotation is nonzero (since in most cases
  # people do not ask for rotated coordinates) - this is 
  # a very minor optimization compared two the multiple sprintfs!!
  if (abs($pa) > 0.0) {

    # Convert to radians
    my $rpa = $pa * DEG2RAD;

    # Precompute the cos and sin since we use it twice
    my $cosrpa = cos( $rpa );
    my $sinrpa = sin( $rpa );

    # Rotate to new frame
    $x2 =   $x1 * $cosrpa  +  $y1 * $sinrpa;
    $y2 = - $x1 * $sinrpa  +  $y1 * $cosrpa;

  } else {
    $x2 = $x1;
    $y2 = $y1;
  }

  # Now format to 2dp
  my $f = '%.2f';
  $x2 = sprintf($f,$x2);
  $y2 = sprintf($f,$y2);

  # trap -0.00 by formatting a negative zero
  # This is more convoluted a check because the format is variable
  $x2 = sprintf($f,0.0) if $x2 eq sprintf($f,-0.0);
  $y2 = sprintf($f,0.0) if $y2 eq sprintf($f,-0.0);

  return ($x2, $y2);
}

=item B<PruneMSBs>

Remove MSBs that should not be translated. Currently, removes
MSBs that are marked as REMOVED unless there is only one MSB
supplied.

  @pruned = OMP::Translator->PruneMSBs( @msbs );

Arguments are C<OMP::MSB> objects.

=cut

sub PruneMSBs {
  my $class = shift;
  my @msbs = @_;

  my @out;
  if (scalar(@msbs) > 1) {
    @out = grep { $_->remaining != OMP__MSB_REMOVED } @msbs;
  } else {
    @out = @msbs;
  }
  return @out;
}

=item B<correct_offsets>

For some observing modes, the offset iterator should not generate a set
of standalone observations, but should generate a single observation
that itself iterates over the offsets.

This routine can be used to correct the structure of the MSB such that
when it is unrolled, the named observing modes will see a set of offsets
rather than a single offset.

The name of the affected observing modes can be specified (the "obstype"
setting, ie drop the SpIter and trailing Obs).

  OMP::Translator->correct_offsets( $msb, "Stare", "Jiggle" );

The MSB is modified inplace.

Problems can be encountered by this routine if there is more than one
observing type below each Offset iterator. Since this is unusual in
practice and extremely difficult to get correct (since you have to
account for all structures below the iterator) we should croak in this
situation. Currently we let it go.

=cut


sub correct_offsets {
  my $self = shift;
  my $msb = shift;
  my @obstypes = @_;

  # Note that this returns references to each observation summary.
  # We can modify this hash in place without putting the structure
  # back into the object. This will trigger a nice bug if the obssum
  # method is changed to return a copy.
  my @obs = $msb->obssum;

  # Pattern match
  my $patt = "SpIter(" . join( "|", @obstypes) . ")Obs";

  # loop over each observation
  for my $obs (@obs) {

    my %modes = map { $_ => undef } @{$obs->{obstype}};

    # skip to next observation unless we have a specified obs type
    my $hastype;
    for my $type (@obstypes) {
      $hastype = 1 if exists $modes{$type};
    }
    next unless $hastype;

    # Now need to recurse through the data structure changing
    # offset iterator to a single array rather than an array
    # separate positions.

    # Note that this will not do the right thing if you have
    # a Raster and Stare as child of offset iterator because the
    # raster will not unroll correctly
    for my $child (@{ $obs->{SpIter}->{CHILDREN} }) {
      $self->_fix_offset_recurse( $child, $patt );
    }

  }

}

# When we hit SpIterOffset we correct the ATTR array
# This modifies it in-place. No need to re-register.

sub _fix_offset_recurse {
  my $self = shift;
  my $this = shift;
  my $types = shift;

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
	if ($c =~ /$types/) {
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
	$self->_fix_offset_recurse( $child, $types );
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

=back

=head1 COPYRIGHT

Copyright (C) 2002-2004 Particle Physics and Astronomy Research Council.
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

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=cut

1;
