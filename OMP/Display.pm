package OMP::Display;

=head1 NAME

OMP::Display - Prepare OMP related data for display

=head1 SYNOPSIS

  use OMP::Display

  $text = OMP::Display->html2plain($html);

=head1 DESCRIPTION

Routines for preparing OMP related data for display.

=cut

use 5.006;
use warnings;
use strict;
use Carp;

require HTML::TreeBuilder;
require HTML::FormatText;

our $VERSION = (qw$Revision$)[1];

=head1 METHODS

=head2 General Methods

=over 4

=item B<html2plain>

Convert a string that uses HTML formatting to a string that uses plaintext
formatting.  This method also expands hyperlinks so that the URL is displayed.

  $text = OMP::Display->html2plain($html);

=cut

sub html2plain {
  my $self = shift;
  my $text = shift;

  # Expand hyperlinks
  $text =~ s!<a\shref=\W*(\w+://.*?)\W*?>(.*?)</a>!$2 \[$1\]!gis;

  # Create the HTML tree and parse it
  my $tree = HTML::TreeBuilder->new;
  $tree->parse($text);
  $tree->eof;

  # Convert the HTML to text and store it
  my $formatter = HTML::FormatText->new(leftmargin => 0);
  my $plaintext = $formatter->format($tree);

  return $plaintext;
}

=back

=head1 AUTHORS

Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
