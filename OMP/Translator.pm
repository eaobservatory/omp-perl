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

=cut

sub translate {
  my $self = shift;
  my $thisclass = ref($self) || $self;
  my $sp = shift;
  my $asdata = shift;

  print join("\n",$sp->summary('asciiarray'))."\n" if $DEBUG;

  # See how many MSBs we have
  my @msbs = $sp->msb;
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
  for my $msb ($sp->msb) {
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

=head1 COPYRIGHT

Copyright (C) 2002-2003 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=cut

1;
