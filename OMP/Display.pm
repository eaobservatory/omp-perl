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

our $VERSION = (qw$Revision$)[1];

=head1 METHODS

=head2 General Methods

=over 4

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

=item B<make_hidden_fields>

Generates a list of (HTML form) hidden field strings given CGI object
and a hash reference with field names as keys and default values as,
well, values. The keys & values are passed to C<hidden> method of the
given CGI object.

  my @hidden = OMP::Display->make_hidden_fields(
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

  my @non_empty = OMP::Display->make_hidden_fields(
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
  require HTML::TreeBuilder;
  my $tree = HTML::TreeBuilder->new;
  $tree->parse($text);
  $tree->eof;

  # Convert the HTML to text and store it
  require HTML::FormatText;
  my $formatter = HTML::FormatText->new(leftmargin => 0);
  my $plaintext = $formatter->format($tree);

  return $plaintext;
}

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

=item B<userhtml>

Returns html for a hyperlink to the user details page for a user.  Also
displays an icon next to the hyperlink indicating whether or not the user
receieves project emails.

  $html = OMP::Display->userhtml($user, $cgi, $getemails, $projectid);

First argument should be an C<OMP::User> object.  Second argument
should be an C<OMP::CGI> object.  If the optional third
argument is non-zero a "receives email" icon is displayed; if 0 an
"ignores email" icon is displayed.  If undefined no icon is displayed.  Finally,
If the third argument is defined the fourth argument, a project ID, is required.
Thank you and goodnight!

=cut

sub userhtml {
  my $self = shift;
  my $user = shift;
  my $cgi = shift;
  my $emailstatus = shift;
  my $project = shift;
  if (defined $emailstatus and ! defined $project) {
    $emailstatus = undef;
  }

  my $public = OMP::Config->getData('omp-url');
  my $cgidir = OMP::Config->getData('cgidir');
  my $iconsdir = OMP::Config->getData('iconsdir');

  # Link to private pages if we are currently on a private page
  my $url = $public . $cgidir . "/userdetails.pl?user=" . $user->userid;
  my $html = qq(<a href="$url">$user</a>);

  # Append email status icon
  if (defined $emailstatus) {

    my @mail = $emailstatus ? ( 'mail.gif',  'receives email' )
                : ( 'nomail.gif',  'ignores email' ) ;

   $html .=
    sprintf
      qq( <a href="%s/projusers.pl?urlprojid=%s"><img src="%s" alt="%s" border="0"></a>),
      $public . $cgidir,
      $project,
      join( '/', $iconsdir, $mail[0] ),
      $mail[1] ;
  }

  return $html;
}

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

1;
