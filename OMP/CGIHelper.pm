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

use OMP::Config;
use OMP::DBbackend;
use OMP::ProjServer;
use OMP::SpServer;
use OMP::DBServer;
use OMP::Info::ObsGroup;
use OMP::CGIObslog;
use OMP::CGIShiftlog;
use OMP::FaultDB;
use OMP::FaultServer;
use OMP::CGIFault;
use OMP::MSB;
use OMP::MSBServer;
use OMP::MSBDoneQuery;
use OMP::NightRep;
use OMP::TimeAcctDB;
use OMP::FBServer;
use OMP::UserServer;
use OMP::General;
use OMP::Error qw(:try);
use OMP::Constants qw(:fb :done :msb);

use Time::Piece;
use Time::Seconds;

use vars qw/@ISA %EXPORT_TAGS @EXPORT_OK/;

require Exporter;

$| = 1;

@ISA = qw/Exporter/;

@EXPORT_OK = (qw/fb_output fb_msb_content fb_msb_output add_comment_content add_comment_output fb_logout msb_hist_content msb_hist_output observed observed_output fb_proj_summary list_projects list_projects_output fb_fault_content fb_fault_output issuepwd project_home report_output preify_text public_url private_url projlog_content nightlog_content night_report proj_sum_page proposals/);

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

  my $projectid = $cookie{projectid};

  # Link to the science case
  my $case_href = "<a href='props.pl?urlprojid=$projectid'>Science Case</a>";

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

  OMP::CGIFault::show_faults(CGI => $q, 
			     faults => \@faults,
			     descending => 0,
			     URL => "fbfault.pl",);
  print "<hr>";
  print "<font size=+1><b>ID: " . $showfault->faultid . "</b></font><br>";
  print "<font size=+1><b>Subject: " . $showfault->subject . "</b></font><br>";
  OMP::CGIFault::fault_table($q, $showfault, 1);
  print "<br>You may comment on this fault by clicking <a href='fbcomment.pl?subject=Fault%20ID:%20". $showfault->faultid ."'>here</a>";
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

    print "<font size=+1>Entry $row->{'entrynum'} (on $row->{'date'} by ",

      # If author is not defined display sourceinfo as the author
          ($row->{author} ? $row->{author}->html : $row->{sourceinfo}) . " )</font><br>",
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
      # Get the user object
      my $user = OMP::UserServer->getUser($q->param('author')) or
	throw OMP::Error::BadArgs( "Must supply a valid OMP user ID");

      # Create the comment object
      my $comment = new OMP::Info::Comment( author => $user,
					    text => $q->param('comment'),
					    status => OMP__DONE_COMMENT );

      OMP::MSBServer->addMSBcomment( $q->param('projectid'), $q->param('msbid'), $comment);
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

  # Get observed MSBs
  my $observed = OMP::MSBServer->observedMSBs({projectid => $projectid,
					       format => 'data'});

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
    if (defined $program->[0]->remaining);

  # And let's have an N Repeats column if that's available
  print "<td><b>N Repeats:</b></td>"
    if (defined $program->[0]->nrepeats);

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
      if (defined $msb->remaining);
    print "<td>" . $msb->nrepeats . "</td>"
      if (defined $msb->nrepeats);

  }

  print "</table>\n";
}

=item B<observed>

Create a page with a list of all the MSBs observed for a given UT sorted by project

  observed($cgi);

=cut

sub observed {
  my $q = shift;

#  my $utdate = OMP::General->today;

#  my $commentref = OMP::MSBServer->observedMSBs($utdate, 0, 'data');

#  (@$commentref) and print $q->h2("MSBs observed on $utdate")
#    or print $q->h2("No MSBs observed on $utdate");

  observed_form($q);
#  print $q->hr;

  # Create the MSB comment tables
#  msb_comments_by_project($q, $commentref);

#  (@$commentref) and print observed_form($q);
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
    # Just viewing comments
    observed_form($q);
    print $q->hr;

    my $utdate = $q->param('utdate');

    print $utdate;

    my $telescope = $q->param('telescope');

    my $dbconnection = new OMP::DBbackend;

    my $commentref = OMP::MSBServer->observedMSBs({date => $utdate,
						  returnall => 0,
						  format => 'data'});

    # Now keep only the comments that are for the telescope we want
    # to see observed msbs for
    my @msbs;
    for my $msb (@$commentref) {
      my $projdb = new OMP::ProjDB( ProjectID => $msb->projectid,
				    Password => "***REMOVED***",
				    DB => $dbconnection );
      my $proj = $projdb->projectDetails( 'object' );
      if ($proj->telescope eq $telescope) {
	push @msbs, $msb;
      }
    }

    (@msbs) and print $q->h2("MSBs observed on $utdate")
      or print $q->h2("No MSBs observed on $utdate");

    msb_comments_by_project($q, \@msbs);

    # If they've just submitted a comment show some comforting output
    # or catch an error
    if ($q->param("Submit")) {
      try {
	# Get the user object
	my $user = OMP::UserServer->getUser($q->param('author')) or
	  throw OMP::Error::BadArgs( "Must supply a valid OMP user ID");
	
	# Create the comment object
	my $comment = new OMP::Info::Comment( author => $user,
					      text => $q->param('comment'),
					      status => OMP__DONE_COMMENT );
	
	OMP::MSBServer->addMSBcomment( $q->param('projectid'), $q->param('msbid'), $comment);
	
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
    
    (@msbs) and print observed_form($q);
  }
}

=item B<observed_form>

Create a form with a textfield for inputting a UT date and submitting it.

  observed_form($cgi);

=cut

sub observed_form {
  my $q = shift;

  my $db = new OMP::ProjDB( DB => OMP::DBServer->dbConnection, );

  # Get today's date and use that ase the default
  my $utdate = OMP::General->today;

  # Get the telescopes for our popup menu
  my @tel = $db->listTelescopes;

  print "<table><td align='right'><b>";
  print $q->startform;
  print $q->hidden(-name=>'show_output',
		   -default=>1,);
  print "UT Date: </b><td>";
  print $q->textfield(-name=>'utdate',
		      -size=>15,
		      -maxlength=>75,
		      -default=>$utdate,);
  print "</td><td></td><tr><td align='right'><b>Telescope: </b></td><td>";
  print $q->popup_menu(-name=>'telescope',
		       -values=>\@tel,);
  print "</td><td colspan=2>";
  print $q->submit("View Comments");
  print $q->endform;
  print "</td></table>";

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

  # Get the Private and Public cgi-bin URLs
  my $public_url = public_url();
  my $private_url = private_url();

  my $semester = $q->param('semester');
  my $status = $q->param('status');
  my $support = $q->param('support');
  my $country = $q->param('country');
  my $telescope = $q->param('telescope');

  ($support eq 'dontcare') and $support = undef;
  ($country =~ /any/i) and $country = undef;
  ($telescope =~ /any/i) and $telescope = undef;

  my $xmlquery;
  if ($status eq 'all') {
    $xmlquery = "<ProjQuery><semester>$semester</semester><support>$support</support><country>$country</country><telescope>$telescope</telescope></ProjQuery>";
  } else {
    $xmlquery = "<ProjQuery><status>$status</status><semester>$semester</semester><support>$support</support><country>$country</country><telescope>$telescope</telescope></ProjQuery>";
  }

  OMP::General->log_message("Projects list retrieved by user $cookie{userid}");

  my $projects = OMP::ProjServer->listProjects($xmlquery, 'object');

  if (@$projects) {
    # Display a list of projects if any were returned
    print $q->h2("Projects for semester $semester");

    list_projects_form($q);

    print $q->hr;

    if ($q->param('table_format')) {

      proj_sum_table($projects);

     } else {
      foreach my $project (@$projects) {
	print "<a href='$public_url/projecthome.pl?urlprojid=" . $project->projectid . "'>";
	print $q->h2('Project ' . $project->projectid);
	print "</a>";
	my %details = (projectid=>$project->projectid, password=>$cookie{password});
	proj_status_table($q, %details);
	
	print $q->h3('MSBs observed');
	fb_msb_observed($q, $project->projectid);
	
	print $q->h3('MSBs to be observed');
	fb_msb_active($q,$project->projectid);
	
      }

    }

    print $q->hr;

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

  # Get the telescopes for our popup menu
  my @tel = $db->listTelescopes;
  unshift @tel, "Any";

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
		       -default=>uc($sem),);
  print "</td><tr><td align='right'>Telescope: </td><td>";
  print $q->popup_menu(-name=>'telescope',
		       -values=>\@tel,
		       -default=>'Any',);
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
  print "</td><tr><td colspan=2>";
  print $q->checkbox(-name=>'table_format',
		     -value=>1,
		     -label=>'Display using tabular format');
  print "&nbsp;&nbsp;&nbsp;";
  print $q->submit(-name=>'Submit');
  print $q->endform();
  print "</td></table>";
}

=item B<msb_comment_form>

Create a form for submitting an MSB comment.  If any of the values the form
takes are available in the query param list they can be used as defaults.

  msb_comment_form($cgi, 1);

The first argument is a C<CGI> query object.  If the second argument is true
any available params are used as defaults.

=cut

sub msb_comment_form {
  my $q = shift;
  my $defaults = shift;

  my %defaults;
  if ($defaults) {
    # Use query param values as defaults
    %defaults = map {$_, $q->param($_)} qw/author comment msbid/;
  } else {
    %defaults = (author => undef,
		 comment => undef,
		 msbid =>$q->param('checksum'),)
  }

  print "<table border=0><tr><td valign=top>User ID: </td><td>";
  print $q->startform;
  print $q->textfield(-name=>'author',
		      -size=>22,
		      -maxlength=>32,
		      -default=>$defaults{author},);
  print "</td><tr><td valign=top>Comment: </td><td>";
  print $q->hidden(-name=>'submit_msb_comment',
		   -default=>1,);
  print $q->hidden(-name=>'show_output',
		   -default=>1,);
  print $q->hidden(-name=>'msbid',
		   -default=>$defaults{msbid},);
  ($q->param('projectid')) and print $q->hidden(-name=>'projectid',
						-default=>$q->param('projectid'));

  ($q->param('utdate')) and print $q->hidden(-name=>'utdate',
					     -default=>$q->param('utdate'));
  print $q->textarea(-name=>'comment',
		     -rows=>5,
		     -columns=>50,
		     -default=>$defaults{comment},);
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

  # Use the lower-level method to fetch the science program so we
  # can disable the feedback comment associated with this action
  my $db = new OMP::MSBDB( Password => $cookie{password},
			   ProjectID => $cookie{projectid},
			   DB => new OMP::DBbackend, );

  my $sp = $db->fetchSciProg(1);

  proj_status_table($q, %cookie);

  # If they clicked the "Add Comment" button bring up a comment form
  if ($q->param("Add Comment")) {
    print $q->h2("Add a comment to MSB");
    msb_comment_form($q);
  }

  # Perform any actions on the msb?
  msb_action($q);

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

    $commentref = OMP::MSBServer->observedMSBs({projectid => $cookie{projectid},
					       returnall => 1,
					       format => 'data'});
  } else {
    # show current
    $commentref = OMP::MSBServer->historyMSB($cookie{projectid}, '', 'data');
  }

  # Use the lower-level method to fetch the science program so we
  # can disable the feedback comment associated with this action
  my $db = new OMP::MSBDB( Password => $cookie{password},
			   ProjectID => $cookie{projectid},
			   DB => new OMP::DBbackend, );

  my $sp = $db->fetchSciProg(1);
  
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

  # Get the Private and Public cgi-bin URLs
  my $public_url = public_url();
  my $private_url = private_url();

  foreach my $msb (@$comments) {
    my $projectid = $msb->projectid;
    $sorted{$projectid} = [] unless exists $sorted{$projectid};
    push(@{ $sorted{$projectid} }, $msb);
  }

  foreach my $projectid (keys %sorted) {
    print $q->h2("Project: <a href='$public_url/projecthome.pl?urlprojid=$projectid'>$projectid</a>");
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


    # Colors associated with statuses
    my %colors = (&OMP__DONE_FETCH => '#c9d5ea',
		  &OMP__DONE_DONE => '#c6bee0',
		  &OMP__DONE_ALLDONE => '#8075a5',
		  &OMP__DONE_COMMENT => '#9f93c9',
		  &OMP__DONE_UNDONE => '#ffd8a3',
		  &OMP__DONE_ABORTED => '#9573a0',
		  &OMP__DONE_REJECTED => '#bc5a74',
		  &OMP__DONE_SUSPENDED => '#ffb959',);

    foreach my $comment ($msb->comments) {
      my $status = $comment->status;

      # Set the background color for the cell
      $bgcolor = $colors{$comment->status};
      print "<tr bgcolor=$bgcolor valign=top><td><div class='black'><font size =-2>Date (UT):  " .
	$comment->date ."<br>";

      # Show comment author if there is one
      if ($comment->author) {
	print "Author: " . $comment->author->html . "</font></div>";
      }

      print "<td colspan=4>" . $comment->text ."</td>";
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

  proj_status_table($q, %cookie);

  submit_fb_comment($q, $cookie{projectid});

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
  ($project->allRemaining->seconds > 0) and
    my $remaining = $project->allRemaining->pretty_print;
  my $pi = $project->pi->html;
  my $taurange = $project->taurange;
  my $seerange = $project->seerange;
  my $cloud = $project->cloud;

  # Store coi and support html emails
  my $coi = join(", ",map{$_->html} $project->coi);
  my $support = join(", ",map{$_->html} $project->support);

  # Make a big header for the page with the project ID and title
  print "<table width=100%><tr><td>";
  print "<h2>$cookie{projectid}: $title</h2>";
  print "</td><td align=right valign=top>";

  # We'll display a flag icon representing the country if we have
  # one for it
  if ($country =~ /(UK|INT|CA|NL|UH|JAC|JP)/) {
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
  print "<tr><td colspan=2><a href='props.pl?urlprojid=$cookie{projectid}'>Click here to view the science case for this project</a></td>";
  print "</table>";

  # Time allocated/remaining along with tau range
  print "<br>";
  print "<table>";
  print "<tr><td><b>Time allocated to project:</b></td><td>$allocated ";

  # If range is from 0 to infinity dont bother displaying it
  print "in tau range $taurange"
    unless ($taurange->min == 0 and ! defined $taurange->max);

  print " in seeing range $seerange"
    unless ($seerange->min ==0 and ! defined $seerange->max);

  print " with sky " . $project->cloudtxt
    if defined $cloud;

  print "</td>";

  if ($remaining) {
    print "<tr><td><b>Time remaining on project:</b></td><td>$remaining</td>";
  } else {
    print "<tr><td colspan=2><b>There is no time remaining on this project</b></td>";
  }

  print "</table>";

  # Get nights for which data was taken
  my $nights = OMP::MSBServer->observedDates($project->projectid, 1);

  # Since time may have been charged to the project even though no MSBs
  # were observed, check with the accounting DB as well
  my $adb = new OMP::TimeAcctDB( DB => new OMP::DBbackend );
  my @accounts = $adb->getTimeSpent( projectid => $project->projectid );

  # Merge our results
  my %nights = map {$_->date->ymd, undef} @accounts;
  for (@$nights) {
    $nights{$_->ymd} = undef;
  }


  # Display nights where data was taken
  if (%nights) {

    # Sort time spent by night
    my %accounts;
    for (@accounts) {
      $accounts{$_->date->ymd} = $_->timespent;
    }

    print "<h3>Observations were acquired on the following dates:</h3>";

    my $pkg_url = OMP::Config->getData('pkgdata-url');

    for (%nights) {

      # Make a link to the obslog page
      my $ymd = $_;

      print "<a href='utprojlog.pl?urlprojid=$cookie{projectid}&utdate=$ymd'>$ymd</a> ";

      if ($accounts{$ymd}) {
	my $h = sprintf("%.1f", $accounts{$ymd}->hours);
	print "($h hours) ";
      }

      print "<br>";

    }
  } else {
    print "<h3>No data have been acquired for this project</h3>";
  }

  # Display observed MSBs if any data have been taken for this project
  if (@$nights) {
    print "<h3>The following MSBs have been observed:</h3>";
    fb_msb_observed($q, $cookie{projectid});
    print "<br>";
  } else {
    print "<h3>No MSBs have been observed</h3>";
  }

  # Link to the MSB history page
  print "Click <a href='msbhist.pl'>here</a> for more details on the observing history of each MSB.";
  
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

=item B<report_output>

Create a page displaying an observer report.

  report_output($cgi, %cookie);

=cut

sub report_output {
  my $q = shift;
  my %cookie = @_;

  # Get the date, telescope and shift from the URL
  my $date = $q->url_param('date');
  my $shift = $q->url_param('sh')
    unless ($q->url_param('sh') !~ /1|2/);
  my $telescope = $q->url_param('tel');

  my $t = Time::Piece->strptime($date,"%Y%m%d");
#  ($shift eq "1") and $t += 91800          # Set date to end of first shift
#    or $t += 120600;                       # Set date to end of second shift

  # Now get the date in UT
  $t -= $t->tzoffset;

  print "<pre>";
  #  print Dumper($obs);
  print "</pre>";

  print "<h2>Report for $date, $shift shift</h2>";
  print "<h2>Projects Observed</h2>";

  # Get the MSBs observed during this shift sorted by project
  my $xml = "<MSBDoneQuery>".
      "<date delta='-8' units='hours'>". $t->datetime ."</date>".
	# Right now we're specifying the telescope's instruments
	# in the query instead of the telescope since we can't query
	# on telescope yet
	"".
	  "<status>". OMP__DONE_DONE ."</status>".
	    "</MSBDoneQuery>";

  my $commentref = OMP::MSBServer->observedMSBs({});
  msb_comments_by_project($q, $commentref);

  # Get the relative faults

  # Figure out the time lost to faults
}

=item B<projlog_content>

Display information about observations for a project on a particular
night.

  projlog_content($cgi, %cookie);

=cut

sub projlog_content {
  my $q = shift;
  my %cookie = @_;

  my $utdatestr = $q->url_param('utdate');

  my $utdate;
  my $projectid;

  # Untaint the date string
  if ($utdatestr =~ /^(\d{4}-\d{2}-\d{2})$/) {
    $utdate = $1;
  } else {
    croak("UT date string [$utdate] does not match the expect format so we are not allowed to untaint it!");
  }

  # Now untaint the projectid
  $projectid = OMP::General->extract_projectid( $cookie{projectid} );

  (! $projectid) and croak("Project ID string [$cookie{projectid}] does not match the expect format so we are not allowed to untaint it!");

  print "<h2>Project log for " . uc($projectid) . " on $utdate</h2>";

  # Make links for retrieving data
  my $pkgdataurl = OMP::Config->getData('pkgdata-url');
  print "<a href='$pkgdataurl?utdate=$utdate&inccal=1'>Retrieve data with calibrations</a><br>";
  print "<a href='$pkgdataurl?utdate=$utdate&inccal=0'>Retrieve data excluding calibrations</a>";

  # Link to shift comments
  print "<p><a href='#shiftcom'>View shift comments</a><p>";


  # Get code for tau plot display
  my $plot_html = tau_plot_code($utdate);

  # Link to the tau fits image on this page
  if ($plot_html) {
    print"<p><a href='#taufits'>View polynomial fit</a>";
  }

  # Make a form for submitting MSB comments if an 'Add Comment'
  # button was clicked
  if ($q->param("Add Comment")) {
    print $q->h2("Add a comment to MSB");
    msb_comment_form($q);
  }

  # Find out if (and execute) any actions are to be taken on an MSB
  msb_action($q);

  # Display MSBs observed on this date

  # Use the lower-level method to fetch the science program so we
  # can disable the feedback comment associated with this action
  my $db = new OMP::MSBDB( Password => $cookie{password},
			   ProjectID => $cookie{projectid},
			   DB => new OMP::DBbackend, );

  my $sp = $db->fetchSciProg(1);

  my $observed = OMP::MSBServer->observedMSBs({projectid => $projectid,
					       date => $utdate,
					       returnall => 0,
					       format => 'data',});
  print $q->h2("MSB history for $utdate");
  msb_comments($q, $observed, $sp);

  # Display observation log
  try {
    my $grp = new OMP::Info::ObsGroup(projectid => $projectid,
				      date => $utdate,
				      inccal => 1,);

    if ($grp->numobs > 1) {
      print "<h2>Observation log</h2>";

      # Don't want to go to files on disk
      $OMP::ArchiveDB::FallbackToFiles = 0;
      obs_table($grp);
    } else {
      # Don't display the table if no observations are available
      print "<h2>No observations available for this night</h2>";
    }
  } otherwise {
    print "<h2>No observations available for this night</h2>";
  };

  # Get a project object for this project
  my $proj;
  try {
    $proj = OMP::ProjServer->projectDetails($projectid, $cookie{password}, "object");
  } otherwise {
    my $E = shift;
    croak "Unable to retrieve the details of this project:\n$E";
  };

  # Display shift log
  my %shift_args = (date => $utdate,
		    telescope => $proj->telescope,
		    zone => "UT");

  print "<a name='shiftcom'></a>";
  display_shift_comments(\%shift_args, \%cookie);

  # Display polynomial fit image
  if ($plot_html) {
    print "<p>$plot_html";
  }
}

=item B<nightlog_content>

Create a page summarizing the events for a particular night.  This is not
project specific.

  nightlog_content($q);

=cut

sub nightlog_content {
  my $q = shift;
  my %cookie = @_;

  my $utdatestr = $q->url_param('utdate');

  my $utdate;
  # Untaint the date string
  if ($utdatestr =~ /^(\d{4}-\d{2}-\d{2})$/) {
    $utdate = $1;
  } else {
    croak("UT date string [$utdate] does not match the expect format so we are not allowed to untaint it!");
  }

  print "<h2>Nightly report for $utdate</h2>";

  # Disply time accounting info
  print "<h3>Time accounting information</h3>";

  my $public_url = public_url();

  # Get the time accounting information
  my $acctdb = new OMP::TimeAcctDB(DB => new OMP::DBbackend);
  my @timeacct = $acctdb->getTimeSpent(utdate => $utdate);

  # Put the time accounting info in a table
  print "<table><td><strong>Project ID</strong></td><td><strong>Hours</strong></td>";
  for my $account (@timeacct) {
    my $projectid = $account->projectid;
    my $timespent = $account->timespent;
    my $h = sprintf("%.1f", $timespent->hours);
    my $confirmed = $account->confirmed;
    print "<tr><td>";
    print "<a href='$public_url/projecthome.pl?urlprojid=$projectid'>$projectid</a>";
    print "<td>$h";
    (! $confirmed) and print " [estimated]";
    print "</td>";
  }
  print "</table>";
}

=item B<multi_night_report>

Create a page summarizing activity for several nights.

  multi_night_report($cgi, %cookie);

=cut

sub multi_night_report { }

=item B<night_report>

Create a page summarizing activity for a particular night.

  night_report($cgi, %cookie);

=cut

sub night_report {
  my $q = shift;
  my %cookie = @_;

  my $date_format = "%Y-%m-%d";

  my $delta;
  my $utdate;
  my $utdate_end;

  # Get delta and start UT date from multi night form
  if ($q->param('utdate_end')) {
    $utdate = OMP::General->parse_date($q->param('utdate_form'));
    $utdate_end = OMP::General->parse_date($q->param('utdate_end'));

    # Derive delta from start and end UT dates
    $delta = $utdate_end - $utdate;
    $delta = $delta->days + 1;  # Need to add 1 to our delta
                                # to include last day
  } elsif ($q->param('utdate_form')) {
    # Get UT date from single night form
    $utdate = OMP::General->parse_date($q->param('utdate_form'));
  } else {
    # No form params.  Get params from URL

    # Get delta from URL
    if ($q->url_param('delta')) {
      my $deltastr = $q->param('delta');
      if ($deltastr =~ /^(\d+)$/) {
	$delta = $1;
      } else {
	croak("Delta [$deltastr] does not match the expect format so we are not allowed to untaint it!");
      }
    }

    # Get start date from URL
    if ($q->url_param('utdate')) {
      $utdate = OMP::General->parse_date($q->url_param('utdate'));

    } else {
      # No UT date in URL.  Use current date.
      $utdate = OMP::General->today(1);

      # Subtract delta (days) from date if we have a delta
      if ($delta) {
	$utdate -= $delta * ONE_DAY;
      }
    }

    # We need an end date for display purposes
    if ($delta) {
      $utdate_end = $utdate + $delta * ONE_DAY;
      $utdate_end -= ONE_DAY;  # Our delta does not include
                               # the last day
    }
  }

  # Get the telescope from the URL
  my $telstr = $q->url_param('tel');

  # Untaint the telescope string
  my $tel;
  if ($telstr) {
    if ($telstr =~ /^(UKIRT|JCMT)$/i ) {
      $tel = uc($1);
    } else {
      croak("Telescope string [$telstr] does not match the expect format so we are not allowed to untaint it!");
    }
  } else {
    print "Please select a telescope to view observing reports for<br>";
    print "<a href='nightrep.pl?tel=jcmt'>JCMT</a> | <a href='nightrep.pl?tel=ukirt'>UKIRT</a>";
    return;
  }

  # Setup our arguments for retrieving night report
  my %args = (date => $utdate->ymd,
	      telescope => $tel,);
  ($delta) and $args{delta_day} = $delta;

  # Get the night report
  my $nr = new OMP::NightRep(%args);

  if (! $nr) {
    print "<h2>No observing report available for". $utdate->ymd ."at $tel</h2>";
  } else {

    print "<table border=0><td colspan=2>";

    if ($delta) {
      print "<h2 class='title'>Observing Report for ". $utdate->ymd ." to ". $utdate_end->ymd ." at $tel</h2>";
    } else {
      print "<h2 class='title'>Observing Report for ". $utdate->ymd ." at $tel</h2>";
    }

    # Get our current URL
#    my $url = OMP::Config->getData('omp-private') . OMP::Config->getData('cgidir') . "/nightrep.pl";
    my $url = $q->url(-path_info=>1);

    # Display a different form and different links if we are displaying
    # for multiple nights
    if (! $delta) {
      # Get the next and previous UT dates
      my $prevdate = gmtime($utdate->epoch - ONE_DAY);
      my $nextdate = gmtime($utdate->epoch + ONE_DAY);

      # Link to previous and next date reports
      print "</td><tr><td>";

      print "<a href='$url?utdate=".$prevdate->ymd."&tel=$tel'>Go to previous</a>";
      print " | ";
      print "<a href='$url?utdate=".$nextdate->ymd."&tel=$tel'>Go to next</a>";

      print "</td><td align='right'>";

      # Form for viewing another report
      print $q->startform;
      print "View report for ";
      print $q->textfield(-name=>"utdate_form",
			  -size=>10,
			  -default=>substr($utdate->ymd, 0, 8),);
      print "</td><tr><td colspan=2 align=right>";

      print $q->submit(-name=>"view_report",
		       -label=>"Submit",);
      print $q->endform;

      # Link to multi night report
      print "</td><tr><td colspan=2><a href='$url?tel=$tel&delta=8'>Click here to view a report for multiple nights</a>";
      print "</td></table>";
    } else {
      print "</td><tr><td colspan=2>";
     print $q->startform;
      print "View report starting on ";
      print $q->textfield(-name=>"utdate_form",
			  -size=>10,
			  -default=>$utdate->ymd,);
      print " and ending on ";
      print $q->textfield(-name=>"utdate_end",
			  -size=>10,);
      print " UT ";
      print $q->submit(-name=>"view_report",
		       -label=>"Submit",);
      print $q->endform;

      # Link to single night report
      print "</td><tr><td colspan=2><a href='$url?tel=$tel'>Click here to view a single night report</a>";
      print "</td></table>";
    }

    print "<p>";


    # Link to CSO fits tau plot
    my $plot_html = tau_plot_code($utdate);
    ($plot_html) and print "<a href='#taufits'>View tau plot</a><br>";

    # Link to WVM graph
    print "<a href='#wvm'>View WVM graph</a><br>";

    $nr->ashtml;

    # Display tau plot
    ($plot_html) and print "<p>$plot_html</p>";

    # Display WVM graph
    my $wvmend;
   ($utdate_end) and $wvmend = $utdate_end or $wvmend = $utdate;
    my $wvmformat = "%d/%m/%y"; # Date format for wvm graph URL
    print "<a name='wvm'></a>";
    print "<br>";
    print "<strong class='small_title'>WVM graph</strong><p>";
    print "<div align=left>";
    print "<img src='http://www.ukirt.jach.hawaii.edu/JCMT/cgi-bin/wvm_graph.pl?datestart=". $utdate->strftime($wvmformat) ."&timestart=00:00:00&dateend=". $wvmend->strftime($wvmformat) ."&timeend=23:59:59'><br><br></div>";

  }
}

=item B<proj_sum_page>

Generate a page showing details for a project and allowing for the
submission of feedback comments

  proj_sum_page($q, %cookie);

=cut

sub proj_sum_page {
  my $q = shift;

  my %cookie;

  # Get project ID from form or display form
  if ($q->param('projectid')) {
    $cookie{projectid} = $q->param('projectid');
    $cookie{password} = '***REMOVED***';

    # Display project details
    proj_status_table($q, %cookie);

    # Submit feedback comment or display form
    if ($q->param('Submit')) {
      submit_fb_comment($q, $cookie{projectid});
      print "<P>";

      # Link back to start page
      print "<a href='". $q ->url(-relative=>1) ."'>View details for another project</a>";

    } else {
      # Form for adding feedback comment
      print "<strong>Add a feedback comment</strong><br>";
      comment_form($q, %cookie);
    }

  } else {
    print $q->startform;
    print "Project ID: ";
    print $q->textfield(-name=>"projectid",
			1-size=>12,
		        -maxlength=>32,);
    print "&nbsp;";
    print $q->submit(-name=>"projectid_submit",
		     -label=>"Submit",);
  }

}

=item B<proposals>

View proposals for specific projects.

  proposals($q, %cookie);

=cut

sub proposals {
  my $q = shift;
  my %cookie = @_;

  my $projectid;

  if ($q->param) {
    my $projstring = $q->url_param('urlprojid');
    (! $projstring) and $projstring = $q->param('projectid');

    # Got the project ID, untaint it
    $projectid = OMP::General->extract_projectid($projstring);

    # Proposals directory
    my $propdir = OMP::Config->getData('propdir');

    # Which directories to use?
    my @dirs;
    push(@dirs, $propdir);
    ($cookie{notlocal}) and push(@dirs, $propdir . "/restricted");

    my $propfilebase = $projectid;

    $propfilebase =~ s/\W//g;
    $propfilebase = lc($propfilebase);

    my %extensions = (ps => "application/postscript",
		      pdf => "application/pdf",
		      "ps.gz" => "application/postscript",
		      "txt" => "text/plain",);

    my $propfile;
    my $type;

  dirloop:
    for my $dir (@dirs) {
      for my $ext (qw/ps pdf ps.gz txt/) {
	if (-e "$dir/$propfilebase.$ext") {
	  $propfile = "$dir/$propfilebase.$ext";
	  $type = $extensions{$ext};
	  last dirloop;
	}
      }
    }

    if ($propfile) {

      # Read in proposal file
      open(PROP, $propfile);
      my @file = <PROP>;   # Slurrrp!

      close(PROP);

      # Serve proposal
      print $q->header(-type=>$type);
      print join("",@file);

      # Enter log message
      my $message = "Proposal for $projectid retrieved.";
      OMP::General->log_message( $message );

    } else {
      # Proposal file not found

      print $q->header;
      print "<h2>Proposal file not available</h2>";
    }

  } else {
    # Didn't get project ID, put up form?
  }

}

=item B<sumbit_fb_comment>

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

  # Strip out ^M
  foreach (keys %$comment) {
    $comment->{$_} =~ s/\015//g;
  }

  try {
    OMP::FBServer->addComment( $projectid, $comment );
    print "<h2>Your comment has been submitted.</h2>";
  } otherwise {
    my $E = shift;
    print "<h2>An error has prevented your comment from being submitted</h2>";
    print "<pre>$E</pre>";
  };
}

=item B<msb_action>

Working in conjunction with the B<msb_comments> function described elsewhere
in this document this function decides if the form generated by B<msb_comments>
was submitted, and if so, what action to take.

  msb_action($q);

Takes a C<CGI> query object as the only argument.

=cut

sub msb_action {
  my $q = shift;

  if ($q->param("submit_msb_comment")) {
    # Submit a comment
    try {

      # Get the user object
      my $user = OMP::UserServer->getUser($q->param('author'));

      # Make sure we got a user object
      if (! $user) {
	print "Must supply a valid OMP user ID in order to submit a comment";

	# Redisplay the comment form and return
	msb_comment_form($q, 1);
	return;
      }

      # Create the comment object
      my $comment = new OMP::Info::Comment( author => $user,
					    text => $q->param('comment'),
					    status => OMP__DONE_COMMENT );

      # Add the comment
      OMP::MSBServer->addMSBcomment( $q->param('projectid'),
				     $q->param('msbid'),
				     $comment );
      print $q->h2("MSB comment successfully submitted");
    } catch OMP::Error::MSBMissing with {
      my $Error = shift;
      print "MSB not found in database:<p>$Error";
    } otherwise {
      my $Error = shift;
      print "An error occurred preventing the comment submission:<p>$Error";
    };

  } elsif ($q->param("Remove")) {
    # Mark msb as 'done'
    try {
      OMP::MSBServer->alldoneMSB( $q->param('projectid'), $q->param('checksum') );
      print $q->h2("MSB removed from consideration");
    } catch OMP::Error::MSBMissing with {
      my $Error = shift;
      print "MSB not found in database:<p>$Error";
    } otherwise {
      my $Error = shift;
      print "An error occurred while attempting to mark the MSB as Done:<p>$Error";
    };

  } elsif ($q->param("Undo")) {
    # Unmark msb as 'done'
    try {
      OMP::MSBServer->undoMSB( $q->param('projectid'), $q->param('checksum') );
      print $q->h2("MSB done mark removed");
    } catch OMP::Error::MSBMissing with {
      my $Error = shift;
      print "MSB not found in database:<p>$Error";
    } otherwise {
      my $Error = shift;
      print "An error occurred while attempting to remove the MSB Done mark:<p>$Error";
    };
  }
}

=item B<proj_sum_table>

Display details for multiple projects in a tabular format.

  proj_sum_table($projects);

=cut

sub proj_sum_table {
  my $projects = shift;

  my $url = OMP::Config->getData('omp-url') . OMP::Config->getData('cgidir');

  print "<table cellspacing=0>";
  print "<tr align=center><td>Project ID</td>";
  print "<td>PI</td>";
  print "<td>Support</td>";
  print "<td># MSBs</td>";
  print "<td>Priority</td>";
  print "<td>Allocated</td>";
  print "<td>Completed</td>";
  print "<td>Tau range</td>";
  print "<td>Seeing range</td>";
  print "<td>Sky</td>";
  print "<td>Title</td>";

  my %bgcolor = (dark => "#6161aa",
		 light => "#8080cc",);
  my $bgcolor = $bgcolor{dark};

  foreach my $project (@$projects) {
    # Get the MSBs for this project so we can count them
    my $msbs;
    try {
      $msbs = OMP::SpServer->programDetails($project->projectid, '***REMOVED***', 'objects');
    } catch OMP::Error::UnknownProject with {
      my $E = shift;
    } otherwise {
      my $E = shift;
    };

    my $nmsb = 0;
    if ($msbs->[0]) {
      $nmsb = scalar(@$msbs);
    }

    # Count remaining msbs
    my @remaining = grep { $_->remaining > 0 } @$msbs;
    my $nremaining = scalar(@remaining);

    # Get seeing and tau info
    my $taurange = $project->taurange;
    my $seerange = $project->seerange;

    # Make sure there is a valid range to display
    for ($taurange, $seerange) {
      if ($_->min == 0 and ! defined $_->max) {
	$_ = "--";
      } else {
	$_ = $_->stringify;
      }
    }

    my $support = join(", ", map {$_->userid} $project->support);

    print "<tr bgcolor=$bgcolor valign=top>";
    print "<td><a href='$url/projecthome.pl?urlprojid=". $project->projectid ."'>". $project->projectid ."</a></td>";
    print "<td>". $project->pi->html ."</td>";
    print "<td>". $support ."</td>";
    print "<td align=center>$nremaining/$nmsb</td>";
    print "<td align=center>". $project->tagpriority ."</td>";
    print "<td align=center>". $project->allocated->pretty_print ."</td>";
    print "<td align=center>". sprintf("%.0f",$project->percentComplete) . "%</td>";
    print "<td align=center>$taurange</td>";
    print "<td align=center>$seerange</td>";
    print "<td align=center>". $project->cloudtxt ."</td>";
    print "<td>". $project->title ."</td>";

    # Alternate background color
    ($bgcolor eq $bgcolor{dark}) and $bgcolor = $bgcolor{light}
      or $bgcolor = $bgcolor{dark};
  }

  print "</table>";

}

=item B<tau_plot_code>

Returns HTML code for displaying a tau plot.

  $html = tau_plot_code($utdate);

Takes a UT date string as the only argument.  Returns undef if no tau plot
exists for the given date.

=cut

sub tau_plot_code {
  my $utdate = shift;

  # Setup tau fits image info
  my $dir = "/WWW/omp/data/taufits";
  my $www = OMP::Config->getData('omp-url') . "/data/taufits";
  my $calibpage = "http://www.jach.hawaii.edu/JACpublic/JCMT/Continuum_observing/SCUBA/astronomy/calibration/calib.html";
  my $gifdate = $utdate;
  $gifdate =~ s/-//g;

  my $gif = $gifdate . "new.gif";

  if (-e "$dir/$gif") {
    return "<a name='taufits'></a>"
      ."<a href='$calibpage'><img src='$www/$gif'>"
	."<br>Click here to visit the calibration page</a>";
  } else {
    return undef;
  }
}

=item B<preify_text>

Replace HTML characters (such as <, > and &) with their associated escape
sequences and place text inside a <PRE> block.

  $escaped = preify_text($text);

=cut

sub preify_text {
  my $string = shift;

  # Escape sequence lookup table
  my %lut = (">" => "&gt;",
	     "<" => "&lt;",
	     "&" => "&amp;",
	     '"' => "&quot;",);

  # Do the search and replace
  # Make sure we replace ampersands first, otherwise we'll end
  # up replacing the ampersands in the escape sequences
  for ("&", ">", "<", '"') {
    $string =~ s/$_/$lut{$_}/g;
  }

  return "<pre>$string</pre>";
}

=item B<public_url>

Return the URL where public cgi scripts can be found.

  $url = OMP::CGIHelper->public_url();

=cut

sub public_url {
  # Get the base URL
  my $url = OMP::Config->getData( 'omp-url' );

  # Now the CGI dir
  my $cgidir = OMP::Config->getData( 'cgidir' );

  return "$url" . "$cgidir";
}

=item B<private_url>

Return the URL where private cgi scripts can be found.

  $url = OMP::CGIHelper->private_url();

=cut

sub private_url {
  # Get the base URL
  my $url = OMP::Config->getData( 'omp-private' );

  # Now the CGI dir
  my $cgidir = OMP::Config->getData( 'cgidir' );

  return "$url" . "$cgidir";
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
