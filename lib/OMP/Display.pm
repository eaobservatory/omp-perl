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
C<wrap_text>.

=cut

sub format_text {
    my $self = shift;
    my $text = shift;
    my $preformatted = shift;
    my %opt = @_;

    my $width = $opt{'width'} // 72;
    my $indent = $opt{'indent'} // 0;

    # Due to problems with html2plain's line wrapping (see e.g. fault
    # 20181130.008), convert with a long line length and then wrap.
    $text = $self->html2plain($text, {rightmargin => 2048})
        if $preformatted;

    return $self->wrap_text($text, $width, $indent);
}

=item B<format_html>

Prepare text for display in HTML format.

    $html = OMP::Display->format_html($text, $preformatted);

If C<$preformatted> is true, return the given HTML (wrapped
using C<wrap_text>).  Otherwise the text is wrapped
and then processed with C<preify_text>.

=cut

sub format_html {
    my $self = shift;
    my $text = shift;
    my $preformatted = shift;
    my %opt = @_;

    my $width = $opt{'width'} // 72;

    my $wrapped = $self->wrap_text($text, $width, 0);

    return $wrapped if $preformatted;

    return $self->preify_text($wrapped);
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
    require OMP::HTMLFormatText;
    my $formatter = OMP::HTMLFormatText->new(%margin);
    my $plaintext = $formatter->format($tree);

    return $plaintext;
}

=item B<preify_text>

The text goes inside PRE tags and
HTML characters (such as E<lt>, E<gt> and &) are replaced with their
associated entities.  Also strips out windows ^M characters.

    $escaped = $self->preify_text($text);

=cut

sub preify_text {
    my $self = shift;
    my $string = shift;

    $string = escape_entity($string);
    $string = "<pre>$string</pre>";

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

=item B<remove_cr>

Remove carriage return characters from string.

    $text = OMP::Display->remove_cr($input);

=cut

sub remove_cr {
    my $self = shift;
    my $string = shift;

    $string =~ s/\015//g;

    return $string;
}

=item B<wrap_text>

Wrap text using C<Text::Wrap>.

    $wrapped = OMP::Display->wrap_text($text, $width, $indent);

Locally sets suitable C<Text::Wrap> parameters and then calls
C<wrap>, constructing indent strings using the given number of spaces.

=cut

sub wrap_text {
    my $self = shift;
    my $text = shift;
    my $width = shift;
    my $indent = shift // 0;

    local $Text::Wrap::columns = $width;
    local $Text::Wrap::separator = "\n";
    local $Text::Wrap::huge = 'overflow';
    local $Text::Wrap::unexpand = 0;

    my $indentstr = ' ' x $indent;

    return wrap($indentstr, $indentstr, $text);
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
