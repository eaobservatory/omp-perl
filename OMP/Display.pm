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

use OMP::Config;

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

  my $private = OMP::Config->getData('omp-private');
  my $public = OMP::Config->getData('omp-url');
  my $cgidir = OMP::Config->getData('cgidir');
  my $iconsdir = OMP::Config->getData('iconsdir');

  # Link to private pages if we are currently on a private page
  my $url;
  if ($cgi->url(-base=>1) =~ /^$private/) {
    $url = $private . $cgidir . "/userdetails.pl?user=" . $user->userid;
  } else {
    $url = $public . $cgidir . "/userdetails.pl?user=" . $user->userid;
  }

  my $html = "<a href=$url>$user</a>";

  # Append email status icon
  if (defined $emailstatus) {
    if ($emailstatus) {
      $html .= " <a href=$public$cgidir/projusers.pl?urlprojid=$project>".
	"<img src=$public$iconsdir/mail.gif alt='receives email' border=0></a>"
    } else {
      $html .= " <a href=$public$cgidir/projusers.pl?urlprojid=$project>".
	"<img src=$public$iconsdir/nomail.gif alt='ignores email' border=0></a>";
    }
  }

  return $html;
}

=back

=head1 AUTHORS

Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
