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
use OMP::DBServer;
use OMP::FaultDB;
use OMP::FaultServer;
use OMP::CGIFault;
use OMP::MSB;
use OMP::MSBServer;
use OMP::FBServer;
use OMP::General;
use OMP::Error qw(:try);
use OMP::Constants qw(:fb :done :msb);

use vars qw/@ISA %EXPORT_TAGS @EXPORT_OK/;

require Exporter;

$| = 1;

@ISA = qw/Exporter/;

@EXPORT_OK = (qw/fb_output fb_msb_content fb_msb_output add_comment_content add_comment_output fb_logout msb_hist_content msb_hist_output observed observed_output fb_proj_summary list_projects list_projects_output fb_fault_content fb_fault_output issuepwd project_home/);

%EXPORT_TAGS = (
		'all' =>[ @EXPORT_OK ],
	       );

Exporter::export_tags(qw/ all /);

# A default width for HTML tables
our $TABLEWIDTH = 720;

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

  print "<table border='0' cellspacing=1 cellpadding=2 width='100%' bgcolor='#bcbee3'><tr>",
	"<td colspan=3><font size=+2><b>Current project status</b></font></td>",
	"<tr bgcolor=#7979aa>",
	"<td><b>PI:</b>" . $project->pi->html . "</a></td>",
	"<td><b>Title:</b> " . $project->title . "</td>",
	"<td> $case_href </td>",
	"<tr bgcolor='#7979aa'><td colspan='2'><b>CoI:</b> $coiemail</td>",
	"<td><b>Staff Contact:</b> $supportemail</td>",
        "<tr bgcolor='#7979aa'><td><b>Time allocated:</b> " . $project->allocated->pretty_print . "</td>",
	"<td><b>Time Remaining:</b> " . $project->allRemaining->pretty_print . "</td>",
	"<td><b>Country:</b>" . $project->country . "</td>",
        "</table><p>";
}

=item B<fb_fault_content>

Display a fault along with a list of faults associated with the project.  Also
provide a link to the feedback comment addition page for responding to the fault.

  fb_fault_content($cgi, %cookie);

=cut

sub fb_fault_content {
  my $q = shift;
  my %cookie = @_;

  my $faultdb = new OMP::FaultDB( DB => OMP::DBServer->dbConnection, );
  my @faults = $faultdb->getAssociations(lc($cookie{projectid}),0);

  print $q->h2("Feedback: Project $cookie{projectid}: View Faults");

  proj_status_table($q, %cookie);

  print "<font size=+1><b>Faults</b></font><br>";
  # Display the first fault if a faultid isnt specified in the URL
  my $showfault;
  if ($q->url_param('id')) {
    my %faults = map {$_->faultid, $_} @faults;
    my $faultid = $q->url_param('id');
    $showfault = $faults{$faultid};
  } else {
    $showfault = $faults[0];
  }

  &show_faults($q, \@faults);
  print "<hr>";
  print "<font size=+1><b>ID: " . $showfault->faultid . "</b></font><br>";
  print "<font size=+1><b>Subject: " . $showfault->subject . "</b></font><br>";
  &fault_table($q, $showfault);
  print "<br>You may comment on this fault by clicking <a href='fbcomment.pl?subject=Fault%20ID:%20". $showfault->faultid ."'>here</a>";
}

=item B<fb_fault_output>

Parse the fault response form, submit the fault and redisplay the faults.

  fb_fault_output($cgi, %cookie);

=cut

sub fb_fault_output {
  my $q = shift;
  my %cookie = @_;
  my $title;

  my $faultid = $q->param('faultid');
  my $author = $q->param('user');
  my $text = $q->param('text');

  my $fault = OMP::FaultServer->getFault($faultid);

  my $user = new OMP::User(userid => $author,);

  try {
    my $resp = new OMP::Fault::Response(author => $user,
				        text => $text);
    OMP::FaultServer->respondFault($fault->id, $resp);
    $title = "Fault response successfully submitted";
  } otherwise {
    my $E = shift;
    $title = "An error has prevented your response from being filed: $E";
  };

  print $q->h2($title);

  proj_status_table($q, %cookie);

  print "<font size=+1><b>Faults</b></font><br>";

  my $faultdb = new OMP::FaultDB( DB => OMP::DBServer->dbConnection, );
  my @faults = $faultdb->getAssociations(lc($cookie{projectid}),0);

  my %faults = map {$_->faultid, $_} @faults;
  my $showfault = $faults{$faultid};

  &show_faults($q, \@faults);
  print "<hr>";
  print "<font size=+1><b>ID: " . $showfault->faultid . "</b></font><br>";
  print "<font size=+1><b>Subject: " . $showfault->subject . "</b></font><br>";

  fault_table($q, $showfault);
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
					     'htmlcgi');

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

    print "<font size=+1>Entry $row->{'entrynum'} (on $row->{'date'} by $row->{'author'})</b></font><br>",
          "<b>Subject: $row->{'subject'}</b><br>",
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

=item B<fb_msb_content>

Creates the page showing the project summary (lists MSBs).
Also provides buttons for adding an MSB comment.
Hides feedback entries.

  fb_msb_content($cgi, %cookie)

=cut

sub fb_msb_content {
  my $q = shift;
  my %cookie = @_;

  print $q->h1("Feedback for project $cookie{projectid}");

  proj_status_table($q, %cookie);
  fb_entries_hidden($q, %cookie);
  msb_sum($q, %cookie);
}

=item B<fb_msb_output>

Creates the page showing the project summary (lists MSBs).
Also creates and parses form for adding an MSB comment.
Hides feedback entries.

  fb_msb_output($cgi, %cookie);

=cut

sub fb_msb_output {
  my $q = shift;
  my %cookie = @_;

  print $q->h1("Feedback for project $cookie{projectid}");

  proj_status_table($q, %cookie);
  fb_entries_hidden($q, %cookie);

  ($q->param("Add Comment")) and msb_comment_form($q);

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

  # Set up our xml query
  my $xml = "<MSBDoneQuery>" .
    "<status>". OMP__DONE_DONE ."</status>" .
      "<projectid>$projectid</projectid>".
	    "</MSBDoneQuery>";

  # Now get back the observed MSBs
  my $observed = OMP::MSBServer->queryMSBdone($xml, 0, 'data');

  # Generate the HTML table
  (@$observed) and msb_table($q, $observed);
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
					    'objects');

    # First go through the array quickly to make sure we have
    # some valid entries
    my @remaining = grep { $_->remaining > 0 } @$active;
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

Second argument should be an array of 
C<OMP::Info::MSB> objects.

=cut

sub msb_table {
  my $q = shift;
  my $program = shift;

  print "<table width=100%>";
  print "<tr bgcolor=#bcbee3><td><b>MSB</b></td>";
  print "<td><b>Target:</b></td>";
  print "<td><b>Waveband:</b></td>";
  print "<td><b>Instrument:</b></td>";

  # Only bother with a remaining column if we have remaining
  # information
  print "<td><b>Remaining:</b></td>"
    if ($program->[0]->remaining);

  # And let's have an N Repeats column if that's available
  print "<td><b>N Repeats:</b></td>"
    if ($program->[0]->nrepeats);

  # Note that this doesnt really work as code shared for MSB and
  # MSB Done summaries
  my $i;
  foreach my $msb (@$program) {
    # skip if we have a remaining field and it is 0 or less
    # dont skip if the remaining field is simply undefined
    # since that may be a valid case
    next if defined $msb->remaining && $msb->remaining <= 0;

    # Skip if this is only a fetch comment
    next if (scalar @{$msb->comments} && 
	     $msb->comments->[0]->status == &OMP__DONE_FETCH);

    # Create a summary table
    $i++;
    print "<tr><td>$i</td>";

    print "<td>" . $msb->target . "</td>";
    print "<td>" . $msb->waveband . "</td>";
    print "<td>" . $msb->instrument . "</td>";
    print "<td>" . $msb->remaining . "</td>"
      if ($msb->remaining);
    print "<td>" . $msb->nrepeats . "</td>"
      if ($msb->nrepeats);

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

    if ($q->param("Remove")) {
      try {
	OMP::MSBServer->alldoneMSB( $q->param('projectid'), $q->param('checksum'));
	print $q->h2("MSB removed from consideration");
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
  print $q->hidden(-name=>'show_output',
		   -default=>1,);
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
  my %cookie = @_;

  my $semester = $q->param('semester');
  my $status = $q->param('status');
  my $support = $q->param('support');
  my $country = $q->param('country');

  ($support eq 'dontcare') and $support = undef;
  ($country =~ /any/i) and $country = undef;
  my $xmlquery;
  if ($status eq 'all') {
    $xmlquery = "<ProjQuery><semester>$semester</semester><support>$support</support><country>$country</country></ProjQuery>";
  } else {
    $xmlquery = "<ProjQuery><status>$status</status><semester>$semester</semester><support>$support</support><country>$country</country></ProjQuery>";
  }

  OMP::General->log_message("Projects list retrieved by user $cookie{userid}");

  my $projects = OMP::ProjServer->listProjects($xmlquery, 'object');

  if (@$projects) {
    # Display a list of projects if any were returned
    print $q->h2("Projects for semester $semester");

    list_projects_form($q);

    print $q->hr;

    foreach my $project (@$projects) {
      print "<a href='projecthome.pl?urlprojid=" . $project->projectid . "'>";
      print $q->h2('Project ' . $project->projectid);
      print "</a>";
      my %details = (projectid=>$project->projectid, password=>$cookie{password});
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

  my $db = new OMP::ProjDB( DB => OMP::DBServer->dbConnection, );

  my $sem = OMP::General->determine_semester;
  my @sem = $db->listSemesters;

  # Make sure the current semester is a selectable option
  my @a = grep {$_ =~ /$sem/i} @sem;
  (!@a) and unshift @sem, $sem;

  my @support = $db->listSupport;
  my @sorted = sort {$a->userid cmp $b->userid} @support;
  my @values = map {$_->userid} @sorted;

  my %labels = map {$_->userid, $_} @support;
  $labels{dontcare} = "Any";
  unshift @values, 'dontcare';

  my @c = $db->listCountries;

  # Take serv and jac out of the countries list
  my @countries = grep {$_ !~ /^serv$|^jac$/i} @c;
  unshift @countries, 'Any';

  print "<table border=0><tr><td align=right>Semester: </td><td>";
  print $q->startform;
  print $q->hidden(-name=>'show_output',
		   -default=>1,);
  print $q->popup_menu(-name=>'semester',
		       -values=>\@sem,
		       -default=>$sem,);
  print "</td><tr><td align='right'>Show: </td><td>";
  print $q->radio_group(-name=>'status',
		        -values=>['active', 'inactive', 'all'],
			-labels=>{active=>'Active',
				  inactive=>'Inactive',
				  all=>'All',},
		        -default=>'active',);
  print "</td><tr><td align='right'>Support: </td><td>";
  print $q->popup_menu(-name=>'support',
		       -values=>\@values,
		       -labels=>\%labels,
		       -default=>'dontcare',);
  print "</td><tr><td align='right'>Country: </td><td>";
  print $q->popup_menu(-name=>'country',
		       -values=>\@countries,
		       -default=>'Any',);
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
  print $q->hidden(-name=>'show_output',
		   -default=>1,);
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

  my $sp = OMP::SpServer->fetchProgram($cookie{projectid}, $cookie{password}, 1);

  proj_status_table($q, %cookie);

  # If they clicked the "Add Comment" button bring up a comment form
  if ($q->param("Add Comment")) {
    print $q->h2("Add a comment to MSB");
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

    # If they click the "Mark as Done" button mark it as done
  } elsif ($q->param("Remove")) {
    try {
      OMP::MSBServer->alldoneMSB( $q->param('projectid'), $q->param('checksum'));
      print $q->h2("MSB removed from consideration");
    } catch OMP::Error::MSBMissing with {
      print "MSB not found in database";
    } otherwise {
      my $Error = shift;
      print "An error occurred while attempting to mark the MSB as Done: $Error";
    };

    # If they clicked "Undo" unmark it as done
  } elsif ($q->param("Undo")) {
    try {
      OMP::MSBServer->undoMSB( $q->param('projectid'), $q->param('checksum'));
      print $q->h2("MSB done mark removed");
    } catch OMP::Error::MSBMissing with {
      print "MSB not found in database";
    } otherwise {
      my $Error = shift;
      print "An error occurred while attempting to remove the MSB Done mark: $Error";
    };

  }

  # Redisplay MSB comments
  my $commentref = OMP::MSBServer->historyMSB($q->param('projectid'), '', 'data');
  msb_comments($q, $commentref, $sp);

}

=item B<msb_hist_content>

Create a page with a summary of MSBs and their associated comments

  msb_hist_content($cgi, %cookie);

=cut

sub msb_hist_content {
  my $q = shift;
  my %cookie = @_;

  my $commentref;
  if (! $q->param('show')) {
    # show all
    $commentref = OMP::MSBServer->historyMSB($cookie{projectid}, '', 'data');
  } elsif ($q->param('show') =~ /observed/) {
    # show observed
    my $xml = "<MSBDoneQuery><projectid>$cookie{projectid}</projectid><status>" . OMP__DONE_DONE . "</status></MSBDoneQuery>";

    $commentref = OMP::MSBServer->queryMSBdone($xml, 1, 'data');
  } else {
    # show current
    $commentref = OMP::MSBServer->historyMSB($cookie{projectid}, '', 'data');
  }

  my $sp = OMP::SpServer->fetchProgram($cookie{projectid}, $cookie{password}, 1);

  print $q->h2("MSB History for project $cookie{projectid}");

  ### put code for not displaying non-existant msbs here? ###
  proj_status_table($q, %cookie);
  print $q->hr;

  print "<SCRIPT LANGUAGE='javascript'> ";
  print "function mysubmit() ";
  print "{document.sortform.submit()}";
  print "</SCRIPT>";


  print $q->startform(-name=>'sortform'),
        "<b>Show </b>",

	# we want to show this page again, not the output page, so
	# we'll include this hidden param
	$q->hidden(-name=>'show_content',
		   -default=>'show_content'),

	$q->popup_menu(-name=>'show',
		       -values=>[qw/all observed/],
		       -default=>'all',
		       -onChange=>'mysubmit()'),
        "&nbsp;&nbsp;&nbsp;",
        $q->submit("Refresh"),
        $q->endform,
	$q->p;

  msb_comments($q, $commentref, $sp);
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

  msb_comments($cgi, $msbcomments, $sp);

Takes a reference to an array of C<OMP::Info::MSB> objects as the second argument.
Last argument is an optional Sp object.

=cut

sub msb_comments {
  my $q = shift;
  my $commentref = shift;
  my $sp = shift;

  my @output;
  if ($q->param('show') =~ /observed/) {
    @output = grep {$_->comments->[0]->status != OMP__DONE_FETCH} @$commentref;
  } elsif ($q->param('show') =~ /current/) {
    @output = grep {$sp->existsMSB($_->checksum)} @$commentref;
  } else {
    @output = @$commentref;
  }

  print "<table border=0 cellspacing=1 cellpadding=2 bgcolor=#5b5b7c width=100%>";

  my $i = 0;
  my $bgcolor;
  foreach my $msb (@output) {
    $i++;

    # If the MSB exists in the science program we'll provide a "Remove" button and we'll
    # be able to display the number of remaining observations.
    my $exists = ($sp and $sp->existsMSB($msb->checksum) ? 1 : 0 );
    my $remstatus;
    if ($exists) {
      my $remaining = $sp->fetchMSB($msb->checksum)->remaining;
      if ($remaining == OMP__MSB_REMOVED) {
	$remstatus = "REMOVED";
      } elsif ($remaining == 0) {
	$remstatus = "COMPLETE";
      } else {
	$remstatus = "Remaining: $remaining";
      }
    }

    # Get the MSB title
    my $msbtitle = $msb->title;
    (!$msbtitle) and $msbtitle = "[NONE]";

    print "<tr valign=top><td><b>MSB $i</b></td>";
    print "<td>";
    print "<b>$remstatus</b>"
      if ($remstatus);
    print "</td>";
    print "<td><b>Target:</b> ".$msb->target ."</td>";
    print "<td><b>Waveband:</b>". $msb->waveband ."</td>";
    print "<td><b>Instrument:</b>". $msb->instrument ."</td>";
    print "<tr><td colspan=5><b>Title: $msbtitle</b></td>";

    foreach my $comment ($msb->comments) {
      my $status = $comment->status;
      ($status == OMP__DONE_FETCH)   and $bgcolor = '#c9d5ea';
      ($status == OMP__DONE_DONE)    and $bgcolor = '#c6bee0';
      ($status == OMP__DONE_ALLDONE) and $bgcolor = '#8075a5';
      ($status == OMP__DONE_COMMENT) and $bgcolor = '#9f93c9';
      ($status == OMP__DONE_UNDONE) and $bgcolor = '#ffd8a3';
      print "<tr><td colspan=5 bgcolor=$bgcolor><b>Date (UT):</b> " .
	$comment->date ."<br>";
      print $comment->text ."</td>";
    }

    print "<tr bgcolor='#d3d3dd'><td align=right colspan=5>";
    print $q->startform;

    # Some hidden params to pass
    ($q->param('utdate')) and print $q->hidden(-name=>'utdate',
					       -default=>$q->param('utdate'));

    print $q->hidden(-name=>'show_output',
		     -default=>1,);
    print $q->hidden(-name=>'checksum',
		     -default=>$msb->checksum);
    print $q->hidden(-name=>'projectid',
		     -default=>$msb->projectid);

    # Make "Remove" and "undo" buttons if the MSB exists in the 
    # science program
    if ($exists) {
      print $q->submit("Remove");
      print " ";
      print $q->submit("Undo");
      print " ";
    }

    print $q->submit("Add Comment");
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
  print "You may see feedback for a project by clicking <a href='projecthome.pl'>here</a>.";
}

=item B<issuepwd>

Create a page with a form for requesting a password.

  issuepwd($cgi);

=cut

sub issuepwd {
  my $q = shift;

  print "<H1>OMP Password Request Page</h1>";
  print "You can use this page to request an updated password for your project.";
  print "The password will be mailed to your registered email address.";

  print $q->startform;
  print $q->hidden(-name=>'show_output',
		   -default=>1,);
  print "Project ID: ",$q->textfield('projectid','',8,20);
  print "<P>", $q->submit( '  Request password  ');
  print $q->endform;

  if ($q->param) {
    my $projectid = $q->param("projectid");
    try {
      OMP::ProjServer->issuePassword( $projectid );
      print "<P>Password has been mailed to your registered address</p>\n";
    } catch OMP::Error::UnknownProject with {
      print "<P>Unable to process your request because this project ID does not exist in our database<p>\n";
    } otherwise {
      my $E = shift;
      print "<p>Unfortunately an error occurred whilst processing your request<p>\n";
      print "$E\n";
    }
  }
}

=item B<project_home>

Create a page which has a simple simmary of the project and links to the rest of the system that are easy to follow.

  project_home($cgi, %cookie);

=cut

sub project_home {
  my $q = shift;
  my %cookie = @_;

  # Get the project details
  my $project = OMP::ProjServer->projectDetails( $cookie{projectid},
						 $cookie{password},
						 'object' );

  # Store the details we want to display later
  my $country = $project->country;
  my $title = $project->title;
  my $semester = $project->semester;
  my $allocated = $project->allocated->pretty_print;
  my $remaining = $project->allRemaining->pretty_print;
  my $pi = $project->pi->html;
  my $taurange = $project->taurange;

  # Store coi and support html emails
  my $coi = join(", ",map{$_->html} $project->coi);
  my $support = join(", ",map{$_->html} $project->support);

  # Make a big header for the page with the project ID and title
  print "<table width=100%><tr><td>";
  print "<h2>$cookie{projectid}: $title</h2>";
  print "</td><td align=right valign=top>";

  # We'll display a flag icon representing the country if we have
  # one for it
  if ($country =~ /(UK|INT|CA|NL|UH|JAC)/) {
    my $country = lc($country);
    print "<img src='http://www.jach.hawaii.edu/JACpublic/JAC/software/omp/flag_$country.gif'>";
  }
  print "</td></table>";

  # The project info (but in a different format than what is
  # generated by proj_status_table)
  print "<table>";
  print "<tr><td><b>Principal Investigator:</b></td><td>$pi</td>";
  print "<tr><td><b>Co-investigators:</b></td><td>$coi</td>";
  print "<tr><td><b>Support:</b></td><td>$support</td>";
  print "<tr><td><b>Country:</b></td><td>$country</td>";
  print "<tr><td><b>Semester:</b></td><td>$semester</td>";
  print "</table>";

  # Time allocated/remaining along with tau range
  print "<br>";
  print "<table>";
  print "<tr><td><b>Time allocated to project:</b></td><td>$allocated ";

  # If range is from 0 to infinity dont bother displaying it
  print "in tau range $taurange"
    unless ($taurange->min == 0 and ! $taurange->max);
  print "</td>";
  print "<tr><td><b>Time remaining on project:</b></td><td>$remaining</td>";
  print "</table>";

  # Get nights for which data was taken
  my $nights = OMP::MSBServer->observedDates($project->projectid);

  # Display nights where data was taken
  if (@$nights) {
    print "<h3>Observations were acquired on the following dates:</h3>";
    for (@$nights) {
      print "$_<br>";
    }
  } else {
    print "<h3>No data has been acquired for this project</h3>";
  }

  # Display observed MSBs if any data has been taken for this project
  if (@$nights) {
    print "<h3>The following MSBs have been observed:</h3>";
    fb_msb_observed($q, $cookie{projectid});
    print "<br>";
  } else {
    print "<h3>No MSBs have been observed</h3>";
  }

  # Link to the MSB history page
  print "Click <a href='/msbhist.pl'>here</a> for more details on the observing history of each MSB.";
  
  # Display remaining MSBs
  print "<h3>Observations remaining to be observed:</h3>";
  fb_msb_active($q, $cookie{projectid});

  # Link to the program details page
  print "<br>Click <a href='fbmsb.pl'>here</a> for more details on the science program.";

  # Get the "important" feedback comments
  my $comments = OMP::FBServer->getComments($cookie{projectid},
					    $cookie{password},
					    [OMP__FB_IMPORTANT],);

  # Link to feedback comments page (if there are any important
  # comments)
  if (@$comments) {
    if (scalar(@$comments) == 1) {
      print "<h3>There is 1 important comment";
    } else {
      print "<h3>There are " . scalar(@$comments) . " important comments";
    }
    print " for this project.</h3>";
    print "Click <a href='feedback.pl'>here</a> to see them.";
  } else {
    print "<h3>There are no important comments for this project</h3>";
  }

  # The "end of run" report goes somewhere in here
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
