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

# Unix directory for writing ODFs
our $TRANS_DIR = "/observe/ompodf";

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


  return;
}

=head1 NOTES

Usually called indirectly from L<OMP::Translator|OMP::Translator>.

=head1 COPYRIGHT

Copyright (C) 2002-2003 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=cut

1;
