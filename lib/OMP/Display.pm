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

use File::Spec;
use OMP::Config;
use OMP::Error;
use Text::Wrap;

our $VERSION = '2.000';

=head1 METHODS

=head2 General Methods

=over 4

=item B<format_text>

Prepare text for display in text format.

    $formatted = OMP::Display->format_text($text, $preformatted);

If C<$preformatted> is true, the given HTML will be converted to text
using C<html2plain>.  Otherwise the text will be wrapped using
C<Text::Wrap>.

=cut

sub format_text {
    my $self = shift;
    my $text = shift;
    my $preformatted = shift;

    my $width = 72;

    return $self->html2plain($text, {rightmargin => $width})
        if $preformatted;

    local $Text::Wrap::columns = $width;
    local $Text::Wrap::separator = "\n";
    local $Text::Wrap::huge = 'overflow';

    return wrap('', '', $text);
}

=item B<escape_entity>

Replace a & E<gt> or E<lt> with the corresponding HTML entity.

    $esc = escape_entity($text);

=cut

sub escape_entity {
    my $text = shift;

    # Escape sequence lookup table
    my %lut = (
        '>' => '&gt;',
        '<' => '&lt;',
        '&' => '&amp;',
        '"' => '&quot;',
    );

    # Do the search and replace
    # Make sure we replace ampersands first, otherwise we'll end
    # up replacing the ampersands in the escape sequences
    for ('&', '>', '<', '"') {
        $text =~ s/$_/$lut{$_}/g;
    }

    return $text;
}

=item B<html2plain>

Convert a string that uses HTML formatting to a string that uses plaintext
formatting.  This method also expands hyperlinks so that the URL is displayed.

    $text = OMP::Display->html2plain($html);

=cut

sub html2plain {
    my $self = shift;
    my $text = shift;
    my $opt = shift || {};

    # Determine margins.
    my %margin = (
        leftmargin => 0,
    );

    if (exists $opt->{'leftmargin'}) {
        $margin{'leftmargin'} = $opt->{'leftmargin'};
    }
    if (exists $opt->{'rightmargin'}) {
        $margin{'rightmargin'} = $opt->{'rightmargin'};
    }

    # Expand hyperlinks
    $text =~ s!<a\shref=\W*(\w+://.*?)\W*?>(.*?)</a>!$2 \[$1\]!gis;

    # Create the HTML tree and parse it
    require HTML::TreeBuilder;
    my $tree = HTML::TreeBuilder->new;
    $tree->parse($text);
    $tree->eof;

    # Convert the HTML to text and store it
    require HTML::FormatText;
    my $formatter = HTML::FormatText->new(%margin);
    my $plaintext = $formatter->format($tree);

    return $plaintext;
}

=item B<preify_text>

This method is used to prepare text for storage to the database so
that when it is retrieved it can be displayed properly in HTML format.
If the text is not HTML formatted then it goes inside PRE tags and
HTML characters (such as E<lt>, E<gt> and &) are replaced with their
associated entities.  Also strips out windows ^M characters.

    $escaped = $self->preify_text($text);

Text is considered to be HTML formatted if it begins with the string
"E<lt>htmlE<gt>" (case-insensitive).  This string is stripped off if found.

=cut

sub preify_text {
    my $self = shift;
    my $string = shift;

    if ($string !~ /^<html>/i) {
        $string = escape_entity($string);
        $string = "<pre>$string</pre>";
    }
    else {
        $string =~ s!</*html>!!ig;
    }

    # Strip ^M
    $string =~ s/\015//g;

    return $string;
}

=item B<replace_entity>

Replace some HTML entity references with their associated characters.

    $text = OMP::Display->replace_entity($text);

Returns an empty string if $text is undefined.

=cut

sub replace_entity {
    my $self = shift;
    my $string = shift;
    return '' unless defined $string;

    # Escape sequence lookup table
    my %lut = (
        '&gt;' => '>',
        '&lt;' => '<',
        '&amp;' => '&',
        '&quot;' => '"',
    );

    # Do the search and replace
    for (keys %lut) {
        $string =~ s/$_/$lut{$_}/gi;
    }

    return $string;
}

1;

__END__

=back

=head1 AUTHORS

Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the
Free Software Foundation, Inc., 59 Temple Place, Suite 330,
Boston, MA  02111-1307  USA

=cut
