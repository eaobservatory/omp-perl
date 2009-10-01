package OMP::General::HTML;

=head1 NAME

OMP::General::HTML - General purpose HTML methods.

=head1 SYNOPSIS

  use OMP::General::HTML

  $escaped = OMP::General::HTML->preify_text( $text );

=cut

use 5.006;
use strict;
use warnings;
use warnings::register;

use OMP::Error;

use HTML::TreeBuilder;
use HTML::FormatText;

=head1 METHODS

=over 4

=item B<preify_text>

This method is used to prepare text for storage to the database so
that when it is retrieved it can be displayed properly in HTML format.
If the text is not HTML formatted then it goes inside PRE tags and
HTML characters (such as <, > and &) are replaced with their
associated entities.  Also strips out windows ^M characters.

  $escaped = $self->preify_text($text);

Text is considered to be HTML formatted if it begins with the string
"<html>" (case-insensitive).  This string is stripped off if found.

=cut

sub preify_text {
  my $self = shift;
  my $string = shift;

  if ($string !~ /^<html>/i) {
    $string = escape_entity( $string );
    $string = "<pre>$string</pre>";
  } else {
    $string =~ s!</*html>!!ig;
  }

  # Strip ^M
  $string =~ s/\015//g;

  return $string;
}

=item B<escape_entity>

Replace a & > or < with the corresponding HTML entity.

  $esc = escape_entity( $text );

=cut

sub escape_entity {
  my $text = shift;

  # Escape sequence lookup table
  my %lut = (">" => "&gt;",
             "<" => "&lt;",
             "&" => "&amp;",
             '"' => "&quot;",);

  # Do the search and replace
  # Make sure we replace ampersands first, otherwise we'll end
  # up replacing the ampersands in the escape sequences
  for ("&", ">", "<", '"') {
    $text =~ s/$_/$lut{$_}/g;
  }

  return $text;
}

=item B<replace_entity>

Replace some HTML entity references with their associated characters.

  $text = OMP::General->replace_entity($text);

Returns an empty string if $text is undefined.

=cut

sub replace_entity {
  my $self = shift;
  my $string = shift;
  return '' unless defined $string;

  # Escape sequence lookup table
  my %lut = ("&gt;" => ">",
             "&lt;" => "<",
             "&amp;" => "&",
             "&quot;" => '"',);

  # Do the search and replace
  for (keys %lut) {
    $string =~ s/$_/$lut{$_}/gi;
  }

  return $string;
}

=item B<html_to_plain>

Convert HTML formatted text to plaintext.  Also expands hyperlinks so
that their URL can be seen.

  $plaintext = OMP::General->html_to_plain($html);

=cut

sub html_to_plain {
  my $self = shift;
  my $text = shift;

  # Expand HTML links for our plaintext message
  $text =~ s!<a\s+href=\W*(\w+://.*?/*)\W*?\s*\W*?>(.*?)</a>!$2 \[ $1 \]!gis;

  # Create the HTML tree and parse it
  my $tree = HTML::TreeBuilder->new;
  $tree->parse($text);
  $tree->eof;

  # Convert the HTML to text and store it
  my $formatter = HTML::FormatText->new(leftmargin => 0);
  my $plaintext = $formatter->format($tree);

  return $plaintext;
}

=item B<make_hidden_fields>

Generates a list of (HTML form) hidden field strings given CGI object
and a hash reference with field names as keys and default values as,
well, values. The keys & values are passed to C<hidden> method of the
given CGI object.

  my @hidden = OMP::General->make_hidden_fields(
                  $cgi,
                  { 'fruit' => 'kiwi', 'drink' => 'coconut juice' }
                );

Essentially, it is a wrapper around C<CGI::hidden> method to operate
on multiple key-value pairs.

It optionally takes a code reference as a filter to select only some
of the fields.

=over 4

=item *

If missing, then all the hidden fields will be produced from the hash
reference.

=item *

If given, the reference is passed the values of fields (those listed
in the hash reference) already associated with the CGI object.  Only a
true value returned will allow the production of each associated
hidden field.

  my @non_empty = OMP::Generates->make_hidden_fields(
                    $cgi,
                    { 'fruit' => 'kiwi', 'drink' => 'coconut juice' },
                    sub { length $_[0] }
                  );

=back

Throws C<OMP::Error::BadArgs> error if hash reference isn't one, or
filter isn't a code reference.

=cut

sub make_hidden_fields {

  my ( $self, $cgi, $fields, $filter ) = @_;

  throw OMP::Error::BadArgs(
    'Need hash reference of field names and default values.'
  )
    unless $fields && ref $fields;

  throw OMP::Error::BadArgs( 'Filter is not a code reference.' )
    if $filter && ! ref $filter;

  $filter = sub { 1 } unless $filter;

  return
    map { $filter->( $cgi->param( $_ ) )
          ? $cgi->hidden( '-name' => $_, '-default' => $fields->{ $_ } )
          : ()
        }
        keys %{ $fields } ;
}

=pod

=item B<find_in_post_or_get>

Given a L<CGI> object and an array of parameter names, reutrns a hash
of names as keys and parameter values as, well, values which may be
present either in C<POST> or in C<GET> request.  Only if a paramter is
missing from C<POST> request, a value from C<GET> request will be
returned.

  my %found = OMP::General
              ->find_in_post_or_get( $cgi, qw/fruit drink/ );

=cut

sub find_in_post_or_get {

  my ( $self, $cgi, @names ) = @_;

  my %got;

  NAME:
  for my $key ( @names ) {

    POSITION:
    for my $get qw( param url_param ) {

      my $val = $cgi->$get( $key );
      if ( defined $val ) {

        $got{ $key } = $val;
        last POSITION;
      }
    }
  }

  return %got;
}

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>,
Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>,
Anubhav AgarwalE<lt>a.agarwal@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2007-2009 Science and Technology Facilities Council.
All Rights Reserved.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or (at
your option) any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307
USA

=cut

1;
