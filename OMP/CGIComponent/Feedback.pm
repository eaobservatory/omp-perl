package OMP::CGIComponent::Feedback;

=head1 NAME

OMP::CGIComponent::Feedback - Web display of feedback system comments

=head1 SYNOPSIS

  use OMP::CGIComponent::Feedback;

  $content_html = OMP::CGIComponent::Feedback::fb_entries;

=head1 DESCRIPTION

Helper methods for creating web pages that display feedback
comments.

=cut

use 5.006;
use strict;
use warnings;
use Carp;

use Text::Wrap;

use OMP::Constants qw(:fb);
use OMP::Error qw(:try);
use OMP::FBServer;
use OMP::General;

$| = 1;

=head1 Routines

=over 4

=item B<fb_entries>

Display feedback comments

  fb_entries($cgi, %cookie);

=cut

sub fb_entries {
  my $q = shift;
  my %cookie = @_;

  my $status = [OMP__FB_IMPORTANT];

  if ($q->param("show") ne undef) {
    my %status;
    $status{&OMP__FB_IMPORTANT} = [OMP__FB_IMPORTANT];
    $status{&OMP__FB_INFO} = [OMP__FB_IMPORTANT, OMP__FB_INFO];
    $status{&OMP__FB_HIDDEN} = [OMP__FB_IMPORTANT, OMP__FB_INFO, OMP__FB_HIDDEN, OMP__FB_SUPPORT];

    $status = $status{$q->param("show")};
  }

  my $order;
  ($q->param("order")) and $order = $q->param("order")
    or $order = 'ascending';

  my $comments = OMP::FBServer->getComments( $cookie{projectid},
					     $cookie{password},
					     $status, $order);

  print "<SCRIPT LANGUAGE='javascript'> ";
  print "function mysubmit() ";
  print "{document.sortform.submit()}";
  print "</SCRIPT>";


  print $q->h2("Feedback entries"),
	$q->startform(-name=>'sortform'),
	"<a href='fbcomment.pl'>Add a comment</a>&nbsp;&nbsp;|&nbsp;&nbsp;",
	"Order: ",
	$q->hidden(-name=>'show_content',
		   -default=>1),
	$q->popup_menu(-name=>'order',
		       -values=>[qw/ascending descending/],
		       -default=>'ascending',
		       -onChange=>'mysubmit()'),
        "&nbsp;&nbsp;&nbsp;",
	"Show: ",

	$q->popup_menu(-name=>'show',
		       -values=>[OMP__FB_IMPORTANT, OMP__FB_INFO, OMP__FB_HIDDEN],
		       -default=>OMP__FB_IMPORTANT,
		       -labels=>{OMP__FB_IMPORTANT, "important", OMP__FB_INFO, "info", OMP__FB_HIDDEN, "hidden"},
		       -onChange=>'mysubmit()'),
        "&nbsp;&nbsp;",
        $q->submit("Refresh"),
        $q->endform,
	$q->p;

  foreach my $row (@$comments) {
    # make the date more readable here
    # make the author a mailto link here

    # Wrap the message text
    my $text = wrap('', '' ,$row->{'text'});

    my $date = OMP::General->display_date($row->{date});

    print "<font size=+1>Entry $row->{entrynum} (on $date by ",

	  # If author is not defined display sourceinfo as the author
          ($row->{author} ? OMP::Display->userhtml($row->{author}, $q) : $row->{sourceinfo}) . " )</font><br>",
	  "<b>Subject: $row->{'subject'}</b><br>",
          "$text",
	  "<p>";
  }

  print "<a href='fbcomment.pl'>Add a comment</a><p>",
}

=item B<fb_entries_hidden>

Generate text showing number of comments, but not actually displaying them.

  fb_entries_hidden($cgi, %cookie);

=cut

sub fb_entries_hidden {
  my $q = shift;
  my %cookie = @_;

  my $comments = OMP::FBServer->getComments($cookie{projectid},
					    $cookie{password},
					    [OMP__FB_IMPORTANT, OMP__FB_INFO, OMP__FB_HIDDEN],);
  print $q->h2("Feedback entries");
    if (scalar(@$comments) == 1) {
      print "There is 1 comment";
    } else {
      print "There are " . scalar(@$comments) . " comments";
    }

  print " for this project.";

  if (scalar(@$comments) > 0) {
    print "  Click <a href='feedback.pl'>here</a> to view the comments marked 'important'.";
  }

  print  $q->hr;
}

=item B<comment_form>

Create a feedback comment submission form.

  comment_form($cgi, %cookie);

=cut

sub comment_form {
  my $q = shift;
  my %cookie = @_;

  print "<table><tr valign='bottom'><td>";
  print $q->startform,

  # Store the cookie values in hidden fields so that they can be retrieved if the
  # cookie expires before the comment is submitted.  Otherwise the comment will be
  # lost and a login form will be popped up.  the addComment method doesn't
  # actually require a password to work, however...

    	$q->hidden(-name=>'show_output',
		   -default=>1),
        $q->hidden(-name=>'projectid',
		   -default=>$cookie{projectid}),
        $q->br,
	"User ID: </td><td>",
	$q->textfield(-name=>'author',
		      -size=>20,
		      -maxlength=>32),
        "</td><tr><td align='right'>Subject: </td><td>",
	$q->textfield(-name=>'subject',
		      -size=>50,
		      -maxlength=>70),
	"</td><tr><td></td><td>",
	$q->textarea(-name=>'text',
		     -rows=>10,
		     -columns=>80),
	"</td><tr><td></td><td align='right'>",
	$q->submit("Submit"),
	$q->endform;
  print "</td></table>";

}

=item B<submit_fb_comment>

Submit a feedback comment

  submit_fb_comment($q, $projectid);

=cut

sub submit_fb_comment {
  my $q = shift;
  my $projectid = shift;

  # Get the address of the machine remotely running this cgi script to be given
  # to the addComment method as the sourceinfo param
  my @host = OMP::General->determine_host;

  # Get the OMP::User object
  my $user = OMP::UserServer->getUser($q->param('author')) or
    throw OMP::Error::BadArgs("Must supply a valid OMP User ID");

  my $comment = { author => $user,
		  subject => $q->param('subject'),
		  sourceinfo => $host[1],
		  text => $q->param('text'),
		  program => $q->url(-relative=>1), # the name of the cgi script
		  status => OMP__FB_IMPORTANT, };

  try {
    OMP::FBServer->addComment( $projectid, $comment );
    print "<h2>Your comment has been submitted.</h2>";
  } otherwise {
    my $E = shift;
    print "<h2>An error has prevented your comment from being submitted</h2>";
    print "<pre>$E</pre>";
  };
}

=back

=head1 SEE ALSO

C<OMP::CGI::FeedbackPage>

=head1 AUTHOR

Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2004 Particle Physics and Astronomy Research Council.
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
along with this program (see SLA_CONDITIONS); if not, write to the
Free Software Foundation, Inc., 59 Temple Place, Suite 330,
Boston, MA  02111-1307  USA

=cut

1;
