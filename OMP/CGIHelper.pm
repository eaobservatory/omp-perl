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
use OMP::FBServer;
use OMP::Constants;

use vars qw/@ISA %EXPORT_TAGS @EXPORT_OK/;

require Exporter;

@ISA = qw/Exporter/;

@EXPORT_OK = (qw/fb_output fb_msb_output add_comment_content add_comment_output fb_logout/);

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

  my %summary;
  foreach (qw/pi piemail title projectid coi coiemail allocated remaining country/) {
    $summary{$_} = $project->$_;
  }

  print $q->h2("Current project status"),
        "<table border='1' width='100%'><tr bgcolor='#7979aa'>",
	"<td><b>PI:</b> <a href='mailto:$summary{piemail}'>$summary{pi}</a></td>",
	"<td colspan=2><b>Title:</b> $summary{title}</td>",
	"<td><b>Science Case:</b> </td>",
	"<tr bgcolor='#7979aa'><td><b>CoI: </b> <a href='mailto:$summary{coiemail}'>$summary{coi}</a></td>",
        "<td><b>Time allocated:</b> $summary{allocated}</td>",
	"<td><b>Time Remaining:</b> $summary{remaining}",
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

  my $status = [OMP__FB_IMPORTANT, OMP__FB_INFO];
  my $comments = OMP::FBServer->getComments( $cookie{projectid},
					     $cookie{password},
					     $status, 'ascending');

  print $q->h2("Feedback entries"),
        "<a href='fbcomment.pl'>Add a comment</a>",
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
  print $q->h2("Feedback entries"),
        "There are " .scalar(@$comments). " comments for this project. Click <a href='feedback.pl'>here</a> to view them all.",
	$q->hr;
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
