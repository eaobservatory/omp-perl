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

use OMP::ProjServer;
use OMP::SpServer;
use OMP::MSB;
use OMP::MSBServer;
use OMP::FBServer;
use OMP::General;
use OMP::Error qw(:try);
use OMP::Constants qw(:fb :done);

use vars qw/@ISA %EXPORT_TAGS @EXPORT_OK/;

require Exporter;

$| = 1;

@ISA = qw/Exporter/;

@EXPORT_OK = (qw/fb_output fb_msb_output add_comment_content add_comment_output fb_logout msb_hist_content msb_hist_output observed observed_output fb_proj_summary list_projects list_projects_output/);

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


  # Get the CoI email(s)
  my $coiemail = join(", ",map{$_->html} $project->coi);
  my $supportemail = join(", ",map{$_->html} $project->support);

  print $q->h2("Current project status"),
        "<table border='1' width='100%'><tr bgcolor='#7979aa'>",
	"<td><b>PI:</b>" . $project->pi->html . "</a></td>",
	"<td><b>Title:</b> " . $project->title . "</td>",
	"<td> $case_href </td>",
	"<tr bgcolor='#7979aa'><td colspan='2'><b>CoI:</b> $coiemail</td>",
	"<td><b>Staff Contact:</b> $supportemail</td>",
        "<tr bgcolor='#7979aa'><td><b>Time allocated:</b> " . int($project->allocated/60) . " min </td>",
	"<td><b>Time Remaining:</b> " . int($project->allRemaining/60) . " min </td>",
	"<td><b>Country:</b>" . $project->country . "</td>",
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
					     'html');

  print $q->h2("MSB summary"), $msbsum;
#        $q->pre("$msbsum");

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
  my $projectid = $cookie{projectid};
  try {
    $sp = OMP::SpServer->programDetails($projectid,
					$cookie{password},
					'data' );

  } catch OMP::Error::UnknownProject with {
    print "Science program for $projectid not present in database";
    $sp = [];

  } otherwise {
    my $E = shift;
    print "Error obtaining science program details for project $projectid [$E]";
    $sp = [];

  };


  print $q->h2("Current MSB status");
  if (@$sp == 1) {
    print "1 MSB currently stored in the database.";
    print " Click <a href='fbmsb.pl'>here</a> to list its contents.";
  } else {
    print scalar(@$sp) . " MSBs currently stored in the database.";
    print " Click <a href='fbmsb.pl'>here</a> to list them all."
      unless @$sp == 0;
  }
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

  foreach my $row (@$comments) {
    # make the date more readable here
    # make the author a mailto link here

    print "<font size=+1>Entry $row->{'entrynum'} (on $row->{'date'} by $row->{'author'})</b></font><br>",
          "$row->{'text'}",
	  "<p>";
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

=item B<fb_proj_summary>

Show project status, MSB done summary (no comments), and active MSB summary

  fb_proj_summary($cgi, %cookie);

%cookie should contain a projectid and password key.

=cut

sub fb_proj_summary {
  my $q = shift;
  my %cookie = @_;

  print $q->h2("Project $cookie{projectid}");

  # Project status table
  proj_status_table($q, %cookie);
  print $q->hr;
  print $q->h2("MSBs observed");

  # Observed MSB table
  fb_msb_observed($q, $cookie{projectid});

  print $q->hr;
  print $q->h2("MSBs to be observed");

  # MSBs to be observed table
  fb_msb_active($q, $cookie{projectid});

  print $q->hr;
}

=item B<fb_msb_observed>

Create a table of observed MSBs for a given project

  fb_msb_observed($cgi, $projectid);

=cut

sub fb_msb_observed {
  my $q = shift;
  my $projectid = shift;

  my $history = OMP::MSBServer->historyMSB($projectid, '', 'data');

  (@$history) and msb_table($q, $history);
}

=item B<fb_msb_active>

Create a table of active MSBs for a given project

  fb_msb_active($cgi, $projectid);

=cut

sub fb_msb_active {
  my $q = shift;
  my $projectid = shift;

  my $active;
  try {
    $active = OMP::SpServer->programDetails($projectid,
					    '***REMOVED***',
					    'data');

    # First go through the array quickly to make sure we have
    # some valid entries
    my @remaining = grep { $_->{remaining} > 0 } @$active;
    my $total = @$active;
    my $left = @remaining;
    my $done = $total - $left;
    if ($left == 0) {
      if ($total == 1) {
	print "The MSB present in the science program has been observed.<br>\n";
      } else {
	print "All $total MSBs in the science program have been observed.<br>\n";
      } 

    } else {

      # Nice little message letting us know no of msbs present in the table
      # that have not been observed.
      if ($done > 0) {
	if ($done == 1) {
	  print "$done out of $total MSBs present in the science program has been observed.<br>\n"; 
	} else {
	  print "$done out of $total MSBs present in the science program have been observed.<br>\n"; 
	}
      }

      # Now print the table if we have content
      msb_table($q, $active);

    }

  } catch OMP::Error::UnknownProject with {
    print "Science program for $projectid not present in database";

  } otherwise {
    my $E = shift;
    print "Error obtaining science program details for project $projectid [$E]";

  };

}

=item B<msb_table>

Create a table containing information about given MSBs

  msb_table($cgi, $msbs);

Second argument should be an array of hash references containing MSB information

=cut

sub msb_table {
  my $q = shift;
  my $program = shift;

  print "<table width=100%>";
  print "<tr bgcolor=#7979aa><td><b>MSB</b></td>";
  print "<td><b>Target:</b></td>";
  print "<td><b>Waveband:</b></td>";
  print "<td><b>Instrument:</b></td>";

  # Only bother with a remaining column if we have remaining
  # information
  print "<td><b>Remaining:</b></td>"
    if @$program && exists $program->[0]->{remaining};

  # Note that this doesnt really work as code shared for MSB and
  # MSB Done summaries
  my $i;
  foreach my $msb (@$program) {
    # skip if we have a remaining field and it is 0 or less
    next if (exists $msb->{remaining} and $msb->{remaining} <= 0);

    # Skip if this is only a fetch comment
    next if (exists $msb->{comment} && 
	     $msb->{comment}[0]{status} == &OMP__DONE_FETCH);

    # Create a summary of the observation details and display
    # this in the table cells
    my %msb = OMP::MSB->summary($msb);
    $i++;
    print "<tr><td>$i</td>";

    # This is a kluge - we cant really share the code hear until
    # an OMP::DoneInfo object can be treated the same as a
    # OMP::MSBInfo object
    if (exists $msb{_obssum}) {
      print "<td>" . $msb{_obssum}{target} . "</td>";
      print "<td>" . $msb{_obssum}{waveband} . "</td>";
      print "<td>" . $msb{_obssum}{instrument} . "</td>";
      print "<td>" . $msb->{remaining} . "</td>";
    } else {
      print "<td>" . $msb->{target} . "</td>";
      print "<td>" . $msb->{waveband} . "</td>";
      print "<td>" . $msb->{instrument} . "</td>";
    }

  }

  print "</table>\n";
}

=item B<observed>

Create a page with a list of all the MSBs observed for a given UT sorted by project

  observed($cgi);

=cut

sub observed {
  my $q = shift;

  my $utdate = OMP::General->today;

  my $commentref = OMP::MSBServer->observedMSBs($utdate, 0, 'data');

  (@$commentref) and print $q->h2("MSBs observed on $utdate")
    or print $q->h2("No MSBs observed on $utdate");

  observed_form($q);
  print $q->hr;

  # Create the MSB comment tables
  msb_comments_by_project($q, $commentref);

  (@$commentref) and print observed_form($q);
}

=item B<observed_output>

Create an msb comment page for private use with a comment submission form.

  observed_output($cgi);

=cut

sub observed_output {
  my $q = shift;

  # If they clicked the "Add Comment" button bring up a comment form
  if ($q->param("Add Comment")) {
    print $q->h2("Add a comment to MSB");
    msb_comment_form($q);
  }

  if (!$q->param("Add Comment")) {
    my $utdate = $q->param('utdate');
    my $commentref = OMP::MSBServer->observedMSBs($utdate, 1, 'data');
    msb_comments_by_project($q, $commentref);

    (@$commentref) and print $q->h2("MSBs observed on $utdate")
      or print $q->h2("No MSBs observed on $utdate");

    # If they've just submitted a comment show some comforting output
    # or catch an error
    if ($q->param("Submit")) {
      try {
	OMP::MSBServer->addMSBcomment( $q->param('projectid'), $q->param('msbid'), $q->param('comment'));
	print $q->h2("MSB comment successfully submitted");
      } catch OMP::Error::MSBMissing with {
	print "MSB not found in database";
      } otherwise {
	my $Error = shift;
	print "An error occurred while attempting to submit the comment: $Error";
      };
    }

  # If they click the "Mark as Done" button mark it as done

    if ($q->param("Mark as Done")) {
      try {
	OMP::MSBServer->alldoneMSB( $q->param('projectid'), $q->param('checksum'));
	print $q->h2("MSB marked as Done");
      } catch OMP::Error::MSBMissing with {
	print "MSB not found in database";
      } otherwise {
	my $Error = shift;
	print "An error occurred while attempting to mark the MSB as Done: $Error";
      };
    }

    observed_form($q);
    print $q->hr;

    (@$commentref) and print observed_form($q);
  }
}

=item B<observed_form>

Create a form with a textfield for inputting a UT date and submitting it.

  observed_form($cgi);

=cut

sub observed_form {
  my $q = shift;

  print $q->startform;
  print "Enter a UT Date: ";
  print $q->textfield(-name=>'utdate',
		      -size=>15,
		      -maxlength=>75);
  print "&nbsp;&nbsp;";
  print $q->submit("View Comments");
  print $q->endform;

}

=item B<list_projects>

Create a page with a form prompting for the semester to list projects for.

  list_projects($cgi);

=cut

sub list_projects {
  my $q = shift;

  print $q->h2("List projects");

  list_projects_form($q);

  print $q->hr;
}

=item B<list_projects_output>

Create a page with a project listing for given semester and a form.

  list_projects_output($cgi);

=cut

sub list_projects_output {
  my $q = shift;
  my $semester = $q->param('semester');
  my $status = $q->param('status');

  my $xmlquery;
  if ($status eq 'all') {
    $xmlquery = "<ProjQuery><semester>$semester</semester></ProjQuery>";
  } else {
    $xmlquery = "<ProjQuery><status>$status</status><semester>$semester</semester></ProjQuery>";
  }

  my $projects = OMP::ProjServer->listProjects($xmlquery, 'object');

  if (@$projects) {
    # Display a list of projects if any were returned
    print $q->h2("Projects for semester $semester");

    list_projects_form($q);

    print $q->hr;

    foreach my $project (@$projects) {
      print $q->h2('Project ' . $project->projectid);
      my %details = (projectid=>$project->projectid, password=>'***REMOVED***');
      proj_status_table($q, %details);

      print $q->h3('MSBs observed');
      fb_msb_observed($q, $project->projectid);

      print $q->h3('MSBs to be observed');
      fb_msb_active($q,$project->projectid);

      print $q->hr;
    }

    list_projects_form($q);
  } else {
    # Otherwise just put the form back up
    print $q->h2("No projects for semester $semester");

    list_projects_form($q);

    print $q->hr;
  }
}

=item B<list_project_form>

Create a form for taking the semester parameter

  list_projects_form($cgi);

=cut

sub list_projects_form {
  my $q = shift;
  my $semester = OMP::General->determine_semester();

  print "<table border=0><tr><td>Semester: </td><td>";
  print $q->startform;
  print $q->textfield(-name=>'semester',
		      -default=>$semester,
		      -size=>10,
		      -maxlength=>30,);
  print "</td><tr><td align='right'>Show: </td><td>";
  print $q->radio_group(-name=>'status',
		        -values=>['active', 'inactive', 'all'],
			-labels=>{active=>'Active',
				  inactive=>'Inactive',
				  all=>'All',},
		        -default=>'active',);
  print "</td><td>&nbsp;&nbsp;&nbsp;";
  print $q->submit(-name=>'Submit');
  print $q->endform();
  print "</td></table>";
}

=item B<msb_comment_form>

Create an MSB comment form.

  msb_comment_form($cgi);

=cut

sub msb_comment_form {
  my $q = shift;

  my $checksum = $q->param('checksum');

  print "<table border=0><tr><td valign=top>Comment: </td><td>";
  print $q->startform;
  print $q->hidden(-name=>'msbid',
		   -default=>$checksum);
  ($q->param('projectid')) and print $q->hidden(-name=>'projectid',
						-default=>$q->param('projectid'));

  ($q->param('utdate')) and print $q->hidden(-name=>'utdate',
					     -default=>$q->param('utdate'));
  print $q->textarea(-name=>'comment',
		     -rows=>5,
		     -columns=>50);
  print "</td><tr><td colspan=2 align=right>";
  print $q->submit("Submit");
  print $q->endform;
  print "</td></table>";
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

    print $q->h2("Add a comment to MSB");

    proj_status_table($q, %cookie);
    msb_comment_form($q);
  }

  # If they've just submitted a comment show some comforting output
    if ($q->param("Submit")) {
    try {
      OMP::MSBServer->addMSBcomment( $q->param('projectid'), $q->param('msbid'), $q->param('comment'));
      print $q->h2("MSB comment successfully submitted");
    } catch OMP::Error::MSBMissing with {
      print "MSB not found in database";
    } otherwise {
      my $Error = shift;
      print "An error occurred while attempting to submit the comment: $Error";
    };

    proj_status_table($q, %cookie);

    my $commentref = OMP::MSBServer->historyMSB($q->param('projectid'), '', 'data');
    msb_comments($q, $commentref);
  }

  # If they click the "Mark as Done" button mark it as done
  if ($q->param("Mark as Done")) {
    try {
      OMP::MSBServer->alldoneMSB( $q->param('projectid'), $q->param('checksum'));
      print $q->h2("MSB marked as Done");
    } catch OMP::Error::MSBMissing with {
      print "MSB not found in database";
    } otherwise {
      my $Error = shift;
      print "An error occurred while attempting to mark the MSB as Done: $Error";
    };

    proj_status_table($q, %cookie);

    my $commentref = OMP::MSBServer->historyMSB($q->param('projectid'), '', 'data');
    msb_comments($q, $commentref);

  }

}

=item B<msb_hist_content>

Create a page with a summary of MSBs and their associated comments

  msb_hist_content($cgi, %cookie);

=cut

sub msb_hist_content {
  my $q = shift;
  my %cookie = @_;

  my $commentref = OMP::MSBServer->historyMSB($cookie{projectid}, '', 'data');

  print $q->h2("MSB History for project $cookie{projectid}");

  proj_status_table($q, %cookie);
  print $q->hr;
  msb_comments($q, $commentref);
}

=item B<msb_comments_by_project>

Show MSB comments sorted by project

  msb_comments_by_project($cgi, $msbcomments);

Takes a reference to a data structure containing MSBs and their comments sorted by project.

=cut

sub msb_comments_by_project {
  my $q = shift;
  my $comments = shift;
  my %sorted;

  foreach my $msb (@$comments) {
    my $projectid = $msb->projectid;
    $sorted{$projectid} = [] unless exists $sorted{projectid};
    push(@{ $sorted{$projectid} }, $msb);
  }

  foreach my $projectid (keys %sorted) {
    print $q->h2("Project: $projectid");
    msb_comments($q, \@{$sorted{$projectid}});
    print $q->hr;
  }
}

=item B<msb_comments>

Creates an HTML table of MSB comments.

  msb_comments($cgi, $msbcomments);

Takes a reference to an array of C<OMP::Info::MSB> objects.

=cut

sub msb_comments {
  my $q = shift;
  my $commentref = shift;

  print "<table border=1 width=100%>";

  my $i = 0;
  my $bgcolor;
  foreach my $msb (@$commentref) {
    $i++;
    print "<tr bgcolor=#7979aa><td><b>MSB $i</b></td>";
    print "<td><b>Target:</b> ".$msb->target ."</td>";
    print "<td><b>Waveband:</b>". $msb->waveband ."</td>";
    print "<td><b>Instrument:</b>". $msb->instrument ."</td>";

    foreach my $comment ($msb->comments) {
      my $status = $comment->status;
      ($status == OMP__DONE_FETCH)   and $bgcolor = '#c9d5ea';
      ($status == OMP__DONE_DONE)    and $bgcolor = '#c6bee0';
      ($status == OMP__DONE_ALLDONE) and $bgcolor = '#8075a5';
      ($status == OMP__DONE_COMMENT) and $bgcolor = '#9f93c9';
      print "<tr><td colspan=4 bgcolor=$bgcolor><b>Date:</b> " .
	$comment->date ."<br>";
      print $comment->text ."</td>";
    }

    print "<tr><td align=right colspan=4>";
    print $q->startform;

    # Some hidden params to pass
    ($q->param('utdate')) and print $q->hidden(-name=>'utdate',
					       -default=>$q->param('utdate'));
    print $q->hidden(-name=>'checksum',
		     -default=>$msb->checksum);
    print $q->hidden(-name=>'projectid',
		     -default=>$msb->projectid);
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

  # Get the address of the machine remotely running this cgi script to be given
  # to the addComment method as the sourceinfo param
  my @host = OMP::General->determine_host;

  my $comment = { author => $q->param('author'),
		  subject => $q->param('subject'),
		  sourceinfo => $host[1],
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

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
