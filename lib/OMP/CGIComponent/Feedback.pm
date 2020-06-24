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

use OMP::CGIComponent::Helper qw/start_form_absolute/;
use OMP::Constants qw(:fb);
use OMP::Error qw(:try);
use OMP::FBServer;
use OMP::NetTools;
use OMP::General;

use base qw/OMP::CGIComponent/;

$| = 1;

=head1 Routines

=over 4

=item B<fb_entries>

Display feedback comments

  $comp->fb_entries($projectid);

=cut

sub fb_entries {
  my $self = shift;
  my $projectid = shift;

  my $q = $self->cgi;

  my $status = [OMP__FB_IMPORTANT];

  if ($q->param("show") ne undef) {
    my %status;
    $status{&OMP__FB_IMPORTANT} = [OMP__FB_IMPORTANT];
    $status{&OMP__FB_INFO} = [OMP__FB_IMPORTANT, OMP__FB_INFO];
    $status{&OMP__FB_SUPPORT} = [OMP__FB_IMPORTANT, OMP__FB_INFO, OMP__FB_SUPPORT];
    $status{&OMP__FB_HIDDEN} = [OMP__FB_IMPORTANT, OMP__FB_INFO, OMP__FB_HIDDEN, OMP__FB_SUPPORT];

    $status = $status{$q->param("show")};
  }

  my $order;
  ($q->param("order")) and $order = $q->param("order")
    or $order = 'ascending';

  my $comments = OMP::FBServer->getComments( $projectid,
                                             $status, $order);

  print "<SCRIPT LANGUAGE='javascript'> ";
  print "function mysubmit() ";
  print "{document.sortform.submit()}";
  print "</SCRIPT>";


  print $q->h2("Feedback entries"),
        start_form_absolute($q, -name=>'sortform'),
        "<a href='fbcomment.pl?project=$projectid'>Add a comment</a>&nbsp;&nbsp;|&nbsp;&nbsp;",
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
                       -values=>[OMP__FB_IMPORTANT, OMP__FB_INFO, OMP__FB_SUPPORT, OMP__FB_HIDDEN],
                       -default=>OMP__FB_IMPORTANT,
                       -labels=>
                          { OMP__FB_IMPORTANT() => 'important',
                            OMP__FB_INFO()      => 'info',
                            OMP__FB_SUPPORT()   => 'support',
                            OMP__FB_HIDDEN()    => 'hidden'
                          },

                       -onChange=>'mysubmit()'),
        "&nbsp;&nbsp;",
        $q->submit("Refresh"),
        $q->end_form,
        $q->p;

  foreach my $row (@$comments) {
    # make the date more readable here
    # make the author a mailto link here

    # Wrap the message text
    my $text = wrap('', '' ,$row->{'text'});

    my $date = OMP::DateTools->display_date($row->{date});

    print "<font size=+1>Entry $row->{entrynum} (on $date by ",

          # If author is not defined display sourceinfo as the author
          ($row->{author} ? OMP::Display->userhtml($row->{author}, $q) : $row->{sourceinfo}) . " )</font><br>",
          "<b>Subject: $row->{'subject'}</b><br>",
          "$text",
          "<p>";
  }

  print "<a href='fbcomment.pl?project=$projectid'>Add a comment</a><p>",
}

=item B<fb_entries_hidden>

Generate text showing number of comments, but not actually displaying them.

  $comp->fb_entries_hidden($projectid);

=cut

sub fb_entries_hidden {
  my $self = shift;
  my $projectid = shift;

  my $q = $self->cgi;

  my $comments = OMP::FBServer->getComments($projectid,
                                            [ OMP__FB_IMPORTANT,
                                              OMP__FB_INFO,
                                              OMP__FB_SUPPORT,
                                              OMP__FB_HIDDEN
                                            ],
                                            );
  print $q->h2("Feedback entries");
    if (scalar(@$comments) == 1) {
      print "There is 1 comment";
    } else {
      print "There are " . scalar(@$comments) . " comments";
    }

  print " for this project.";

  if (scalar(@$comments) > 0) {
    print "  Click <a href='feedback.pl?project=$projectid'>here</a> to view the comments marked 'important'.";
  }

  print  $q->hr;
}

=item B<comment_form>

Create a feedback comment submission form.

  $comp->comment_form($projectid);

=cut

sub comment_form {
  my $self = shift;
  my $projectid = shift;

  my $q = $self->cgi;

  print start_form_absolute($q),
        $q->hidden(-name=>'show_output',
                   -default=>1),
        $q->hidden(-name=>'project',
                   -default=>$projectid),
        "<table><tr><td>",
        "User ID: </td><td>",
        $self->auth->user->userid,
        "</td></tr><tr><td align='right'>Subject: </td><td>",
        $q->textfield(-name=>'subject',
                      -size=>50,
                      -maxlength=>70),
        "</td><tr><td></td><td>",
        $q->textarea(-name=>'text',
                     -rows=>10,
                     -columns=>80),
        "</td><tr><td></td><td align='right'>",
        $q->submit("Submit"),
        "</td></tr></table>",
        $q->end_form;

}

=item B<submit_fb_comment>

Submit a feedback comment

  $comp->submit_fb_comment($projectid);

=cut

sub submit_fb_comment {
  my $self = shift;
  my $projectid = shift;

  my $q = $self->cgi;

  # Get the address of the machine remotely running this cgi script to be given
  # to the addComment method as the sourceinfo param
  (undef, my $host, undef) = OMP::NetTools->determine_host;

  my $comment = { author => $self->auth->user,
                  subject => $q->param('subject'),
                  sourceinfo => $host,
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
along with this program; if not, write to the
Free Software Foundation, Inc., 59 Temple Place, Suite 330,
Boston, MA  02111-1307  USA

=cut

1;
