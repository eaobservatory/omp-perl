package OMP::CGIHelper;

=head1 NAME

OMP::CGIHelper - Helper for the OMP feedback system CGI scripts

=head1 SYNOPSIS

  use OMP::CGIHelper;
  use OMP::CGIHelper qw/proj_status_table/;

=head1 DESCRIPTION

Provide functions to generate commonly displayed items for the feedback
system CGI scripts, such as a table containing information on the current
status of a project.

=cut

use 5.006;
use strict;
use warnings;
use Carp;
our $VERSION = (qw$ Revision: 1.2 $ )[1];

use lib qw(/jac_sw/omp/msbserver);
use OMP::ProjServer;
use OMP::SpServer;
use OMP::MSBServer;
use OMP::FBServer;
use OMP::Constants qw(:fb :done);

use vars qw/@ISA %EXPORT_TAGS @EXPORT_OK/;

require Exporter;

@ISA = qw/Exporter/;

@EXPORT_OK = (qw/fb_output fb_msb_output add_comment_content add_comment_output fb_logout msb_hist_content msb_hist_output/);

%EXPORT_TAGS = (
		'all' =>[ @EXPORT_OK ],
	       );

Exporter::export_tags(qw/ all /);

=head1 Routines

=over 4

=item B<proj_status_table>

Creates an HTML table containing information relevant to the status of
a project.

  proj_status_table( $cgi, %cookie);

First argument should be the C<CGI> object.  The second argument
should be a hash containing the contents of the C<OMP::Cookie> cookie
object.

=cut

sub proj_status_table {
  my $q = shift;
  my %cookie = @_;

  # Get the project details
  my $project = OMP::ProjServer->projectDetails( $cookie{projectid},
						 $cookie{password},
						 'object' );

  # Get URL for the science case. If it is not defined we
  # write nothing
  my $case_url = $project->science_case_url;
  my $case_href = (defined $case_url ?
		   "<a href=\"$case_url\">Science Case</a>" :
		   "<b>Science Case</b>" );

  my %summary;
  foreach (qw/pi piemail title projectid coi coiemail allocated remaining country/) {
    $summary{$_} = $project->$_;
  }

  print $q->h2("Current project status"),
        "<table border='1' width='100%'><tr bgcolor='#7979aa'>",
	"<td><b>PI:</b> <a href='mailto:$summary{piemail}'>$summary{pi}</a></td>",
	"<td colspan=2><b>Title:</b> $summary{title}</td>",
	"<td> $case_href </td>",
	"<tr bgcolor='#7979aa'><td><b>CoI: </b> <a href='mailto:$summary{coiemail}'>$summary{coi}</a></td>",
        "<td><b>Time allocated:</b> " . int($summary{allocated}/60) . " min </td>",
	"<td><b>Time Remaining:</b> " . int($summary{remaining}/60) . " min </td>",
	"<td><b>Country:</b> $summary{country} </td>",
        "</table><p>";
}

=item B<msb_sum>

Displays the project details (lists all MSBs)

  msb_sum($cgi, %cookie);

=cut

sub msb_sum {
  my $q = shift;
  my %cookie = @_;

  my $msbsum = OMP::SpServer->programDetails($cookie{projectid},
					     $cookie{password},
					     'ascii');

  print $q->h2("MSB summary"),
        $q->pre("$msbsum");

}

=item B<msb_sum_hidden>

Creates text showing current number of msbs, but not actually display the
program details.

  msb_sum_hidden($cgi, %cookie);

=cut

sub msb_sum_hidden {
  my $q = shift;
  my %cookie = @_;

  my $sp;
  eval {
    $sp = OMP::SpServer->programDetails($cookie{projectid},
					$cookie{password},
					'data' );
  };

  if ($@) {
    print "Error obtaining science program details<$@>";
    $sp = [];
  }

  print $q->h2("Current MSB status"),
        scalar(@$sp). " MSBs currently stored in database.";
  print " Click <a href='fbmsb.pl'>here</a> to list them all."
    unless (@$sp == 0);
  print $q->hr;

}

=item B<fb_entries>

Get the feedback entries and display them

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
    $status{&OMP__FB_HIDDEN} = [OMP__FB_IMPORTANT, OMP__FB_INFO, OMP__FB_HIDDEN];

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

  my $i = 1;

  foreach my $row (@$comments) {
    # make the date more readable here
    # make the author a mailto link here

    print "<font size=+1>Entry $i (on $row->{'date'} by $row->{'author'})</b></font><br>",
          "$row->{'text'}",
	  "<p>";

    $i++;
  }

}

=item B<fb_entries_hidden>

Generate text showing number of comments, but not actually displaying them.

  fb_entries_hidden($cgi, %cookie);

=cut

sub fb_entries_hidden {
  my $q = shift;
  my %cookie = @_;

  my $comments = OMP::FBServer->getComments($cookie{projectid},
					    $cookie{password});
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

Create a comment submission form.

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

        $q->hidden(-name=>'password',
		   -default=>$cookie{password}),
        $q->hidden(-name=>'projectid',
		   -default=>$cookie{projectid}),
        $q->br,
	"Email Address: </td><td>",
	$q->textfield(-name=>'author',
		      -size=>30,
		      -maxlength=>60),
        "</td><tr><td align='right'>Subject: </td><td>",
	$q->textfield(-name=>'subject',
		      -size=>50,
		      -maxlength=>70),
	"</td><tr><td></td><td>",
	$q->textarea(-name=>'text',
		     -rows=>10,
		     -columns=>50),
	"</td><tr><td></td><td align='right'>",
	$q->submit("Submit"),
	$q->endform;
  print "</td></table>";

}

=item B<fb_output>

Creates the page showing feedback entries.

  fb_output($cgi, %cookie);

=cut

sub fb_output {
  my $q = shift;
  my %cookie = @_;

  print $q->h1("Feedback for project $cookie{projectid}");

  proj_status_table($q, %cookie);
  msb_sum_hidden($q, %cookie);
  fb_entries($q, %cookie);
}

=item B<fb_msb_output>

Creates the page showing the project summary (lists MSBs).
Hides feedback entries.

  fb_msb_output($cgi, %cookie);

=cut

sub fb_msb_output {
  my $q = shift;
  my %cookie = @_;

  print $q->h1("Feedback for project $cookie{projectid}");

  proj_status_table($q, %cookie);
  fb_entries_hidden($q, %cookie);
  msb_sum($q, %cookie);
}

=item B<msb_hist_output>

Create a page with a comment submission form or a message saying the comment was submitted.

  msb_hist_output($cgi, %cookie);

=cut

sub msb_hist_output {
  my $q = shift;
  my %cookie = @_;

  # If they clicked the "Add Comment" button bring up a comment form
  if ($q->param("Add Comment")) {

    my $checksum = $q->param('checksum');

    print $q->h2("Add a comment to MSB");

    proj_status_table($q, %cookie);

    print $q->hr;
    print "<table border=0><tr><td valign=top>Comment: </td><td>";
    print $q->startform;
    print $q->hidden(-name=>'msbid',
		     -default=>$checksum);
    print $q->textarea(-name=>'comment',
		       -rows=>5,
		       -columns=>50);
    print "</td><tr><td colspan=2 align=right>";
    print $q->submit("Submit");
    print $q->endform;
    print "</td></table>";
  }

  # If they've just submitted a comment show some comforting output
  if ($q->param("Submit")) {
    OMP::MSBServer->addMSBcomment( $cookie{projectid}, $q->param('msbid'), $q->param('comment'));

    print $q->h2("MSB comment submitted");

    proj_status_table($q, %cookie);
    msb_comments($q, %cookie);
  }

  # If they click the "Mark as Done" button mark it as done
  if ($q->param("Mark as Done")) {
    my $checksum = $q->param('checksum');

    OMP::MSBServer->alldoneMSB( $cookie{projectid}, $checksum);

    print $q->h2("MSB marked as Done");

    proj_status_table($q, %cookie);
    msb_comments($q, %cookie);
  }

}

=item B<msb_hist_content>

Create a page with a summary of MSBs and their associated comments

  msb_hist_content($cgi, %cookie);

=cut

sub msb_hist_content {
  my $q = shift;
  my %cookie = @_;

  print $q->h2("MSB History for project $cookie{projectid}");

  proj_status_table($q, %cookie);
  msb_comments($q, %cookie);
}

=item B<msb_comments>

A list of MSBS and their comments

  msb_comments($cgi, %cookie);

=cut

sub msb_comments {
  my $q = shift;
  my %cookie = @_;

  my $commentref = OMP::MSBServer->historyMSB($cookie{projectid}, '', 'data');

  print $q->hr;
  print "<table border=1>";

  my $i = 0;
  my $bgcolor;
  foreach my $msb (@$commentref) {
    $i++;
    print "<tr bgcolor=#7979aa><td><b>MSB $i</b></td>";
    print "<td><b>Target:</b> $msb->{target}</td>";
    print "<td><b>Waveband:</b> $msb->{waveband}</td>";
    print "<td><b>Instrument:</b> $msb->{instrument}</td>";

    foreach my $comment (@{$msb->{comment}}) {
      ($comment->{status} == OMP__DONE_FETCH) and $bgcolor = '#c9d5ea';
      ($comment->{status} == OMP__DONE_DONE) and $bgcolor = '#c6bee0';
      ($comment->{status} == OMP__DONE_ALLDONE) and $bgcolor = '#8075a5';
      ($comment->{status} == OMP__DONE_COMMENT) and $bgcolor = '#9f93c9';
      print "<tr><td colspan=4 bgcolor=$bgcolor><b>Date:</b> $comment->{date}<br>";
      print "$comment->{text}</td>";
    }

    print "<tr><td align=right colspan=4>";
    print $q->startform;
    print $q->hidden(-name=>'checksum',
		     -default=>$msb->{checksum});
    print $q->submit("Add Comment");
    print " ";
    print $q->submit("Mark as Done");
    print $q->endform;
    print "</td>";
  }
  print "</table>";
}

=item B<add_comment_content>

Creates a page with a comment form.

  add_comment_content($cgi, %cookie);

=cut

sub add_comment_content {
  my $q = shift;
  my %cookie = @_;

  print $q->h2("Add feedback comment to project $cookie{projectid}");

  proj_status_table($q, %cookie);
  fb_entries_hidden($q, %cookie);
  comment_form($q, %cookie);
}

=item B<add_comment_output>

Submits comment and creates a page saying it has done so.

  add_comment_output($cgi, %cookie);

=cut

sub add_comment_output {
  my $q = shift;
  my %cookie = @_;

  my $comment = { author => $q->param('author'),
		  subject => $q->param('subject'),
		  text => $q->param('text'),
		  program => $q->url(-relative=>1), # the name of the cgi script
		  status => OMP__FB_IMPORTANT, };

  # Strip out ^M
  foreach (keys %$comment) {
    $comment->{$_} =~ s/\015//g;
  }

  OMP::FBServer->addComment( $cookie{projectid}, $comment )
      or throw OMP::Error::FatalError("An error occured while attempting to add this comment");

  print $q->h2("Your comment has been submitted");

  proj_status_table($q, %cookie);
  fb_entries_hidden($q, %cookie);
}

=item B<fb_logout>

Gives the user a cookie with an expiration date in the past, effectively deleting the cookie.

  fb_logout($cgi);

=cut

sub fb_logout {
  my $q = shift;

  print $q->h2("You are now logged out of the feedback system.");
  print "You may see feedback for a project by clicking <a href='feedback.pl'>here</a>.";
}


=back

=head1 AUTHORS

Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>,
Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=cut

1;
