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
generated (or if there is more than one observation a SCUBA
macro). For DAS heterodyne systems a HTML summary of the
MSB will be generated.

The actually translation is done in a subclass. The top level class
determines the correct class to use for the MSB and delegates the
translation to that class.

=cut

use 5.006;
use strict;
use warnings;

use OMP::Constants qw/ :msb /;
use OMP::SciProg;
use OMP::Error;
use OMP::General;

our $VERSION = (qw$Revision$)[1];

our $TRANS_DIR;

our $DEBUG = 0;

=head1 METHODS

=over 4

=item B<translate>

Convert the science program object (C<OMP::SciProg>) into
a observing sequence understood by the instrument data acquisition
system.

  $odf = OMP::Translate->translate( $sp );
  $data = OMP::Translate->translate( $sp, 1);
  @data = OMP::Translate->translate( $sp, 1);

The actual translation is implemented by the relevant subclass.
Currently Heterodyne and SCUBA data can be translated but a single
Science Program can not include a mixture of Heterodyne and SCUBA MSBs.

If there is more than one MSB to translate, REMOVED MSBs will be ignored.

=cut

sub translate {
  my $self = shift;
  my $thisclass = ref($self) || $self;
  my $sp = shift;
  my $asdata = shift;

  print join("\n",$sp->summary('asciiarray'))."\n" if $DEBUG;

  # See how many MSBs we have (after pruning)
  my @msbs = $self->PruneMSBs($sp->msb);
  print "Number of MSBS to translate: ". scalar(@msbs) ."\n"
    if $DEBUG;

  # Return immediately if we have nothing to translate
  return () if scalar(@msbs) == 0;

  # Translator class associated with each instrument
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
		  );

  # We need to farm off this data to a subclass that knows how to
  # process the instruments in question. For now, throw an error
  # if we are mixing SCUBA with Heterodyne
  my $class;
  for my $msb (@msbs) {
    for my $obs ($msb->obssum) {
      my $inst = $obs->{instrument};
      if (exists $class_lut{$inst}) {
	my $nclass = $class_lut{$inst};
	if (!defined $class) {
	  # first time so we just store it
	  $class = $nclass;
	} elsif ($class ne $nclass) {
	  # Different classes required. Can not yet handle this
	  throw OMP::Error::TranslateFail("We can not currently translate MSBs containing more than one observing system [$class and $nclass in this case]");
	}
	
      } else {
	throw OMP::Error::TranslateFail("Do not know how to translate MSBs for instrument $inst");
      }
    }
  }

  # Sanity check [should not be important]
  throw OMP::Error::TranslateFail("Internal error: Translator Class not set")
    if ! defined $class;

  # Create the full class name
  $class = $thisclass . '::' . $class;
  print "Class is : $class\n" if $DEBUG;

  # And load it on demand
  eval "require $class;";
  if ($@) {
    throw OMP::Error::FatalError("Error loading class '$class': $@\n");
  }

  # Log the translation details
  my $projectid = $sp->projectID;
  my @checksums = map { $_->checksum . "\n" } $sp->msb;
  OMP::General->log_message( "Translate request: Project:$projectid Checksums:\n\t"
			     .join("\t",@checksums)
			   );

  # Set DEBUGGING in the class depending on the debugging state here
  $class->debug( $DEBUG );

  # And set the translation directory if defined
  $class->transdir( $TRANS_DIR ) if defined $TRANS_DIR;

  # Now translate (but being careful to propogate calling context)
  if (wantarray) {
    return $class->translate($sp, $asdata);
  } else {
    return scalar($class->translate($sp,$asdata));
  }

}

=back

=head2 Helper Routines

Routines common to more than one translator.

=over 4

=item <PosAngRot>

Rotate coordinates through a specified position angle.
Position Angle is defined as "East of North". This means
that the rotation angle is a reverse of the normal mathematical defintion
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

=back

=head1 COPYRIGHT

Copyright (C) 2002-2003 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=cut

1;
