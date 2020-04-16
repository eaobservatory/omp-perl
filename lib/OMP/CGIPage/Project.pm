package OMP::CGIPage::Project;

=head1 NAME

OMP::CGIPage::Project - Web display of complete project information pages

=head1 SYNOPSIS

  use OMP::CGIPage::Project;

=head1 DESCRIPTION

Helper methods for creating and displaying complete web pages that
display project information.

=cut

use 5.006;
use strict;
use warnings;
use CGI::Carp qw/fatalsToBrowser/;
use Time::Seconds;

use OMP::CGIComponent::Fault;
use OMP::CGIComponent::Feedback;
use OMP::CGIComponent::Helper;
use OMP::CGIComponent::MSB;
use OMP::CGIComponent::Project;
use OMP::Constants qw(:fb);
use OMP::Config;
use OMP::Display;
use OMP::Error qw(:try);
use OMP::FBServer;
use OMP::UserServer;
use OMP::DateTools;
use OMP::General;
use OMP::MSBServer;
use OMP::ProjAffiliationDB;
use OMP::ProjDB;
use OMP::ProjServer;
use OMP::TimeAcctDB;
use OMP::SiteQuality;

$| = 1;

=head1 Routines

=over 4

=item B<fb_fault_content>

Display a fault along with a list of faults associated with the project.
Also provide a link to the feedback comment submission page for responding
to the fault.

  $fp->fb_fault_content();

=cut

sub fb_fault_content {
  my $q = shift;
  my %cookie = @_;

  # Get a fault component object
  my $faultcomp = new OMP::CGIComponent::Fault( CGI => $q );

  my $faultdb = new OMP::FaultDB( DB => OMP::DBServer->dbConnection, );
  my @faults = $faultdb->getAssociations(lc($cookie{projectid}),0);

  print $q->h2("Feedback: Project $cookie{projectid}: View Faults");

  OMP::CGIComponent::Project::proj_status_table($q, %cookie);

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

  $faultcomp->show_faults(faults => \@faults,
                          descending => 0,
                          url => "fbfault.pl",);

  print "<hr>";
  print "<font size=+1><b>ID: " . $showfault->faultid . "</b></font><br>";
  print "<font size=+1><b>Subject: " . $showfault->subject . "</b></font><br>";
  $faultcomp->fault_table($showfault, 'noedit');
  print "<br>You may comment on this fault by clicking <a href='fbcomment.pl?subject=Fault%20ID:%20". $showfault->faultid ."'>here</a>";
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
  OMP::CGIComponent::Project::proj_status_table($q, %cookie);
  print $q->hr;
  print $q->h2("MSBs observed");

  # Observed MSB table
  OMP::CGIComponent::MSB::fb_msb_observed($q, $cookie{projectid});

  print $q->hr;
  print $q->h2("MSBs to be observed");

  # MSBs to be observed table
  OMP::CGIComponent::MSB::fb_msb_active($q, @cookie{qw/projectid password/});

  print $q->hr;
}

=item B<list_projects>

Create a page with a form prompting for the semester to list projects for.

  list_projects($cgi);

=cut

sub list_projects {
  my $q = shift;

  print $q->h2("List projects");

  OMP::CGIComponent::Project::list_projects_form($q);

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
  my $state = ($q->param('state') eq 'all' ? undef : $q->param('state'));
  my $status = ($q->param('status') eq 'all' ? undef : $q->param('status'));
  my $support = $q->param('support');
  my $country = $q->param('country');
  my $telescope = $q->param('telescope');
  my $order = $q->param('order');

  undef $semester if $semester =~ /any/i;
  ($support eq 'dontcare') and $support = undef;
  ($country =~ /any/i) and $country = undef;
  ($telescope =~ /any/i) and $telescope = undef;

  my $xmlquery = "<ProjQuery><state>$state</state><status>$status</status><semester>$semester</semester><support>$support</support><country>$country</country><telescope>$telescope</telescope></ProjQuery>";

  OMP::General->log_message("Projects list retrieved by user $cookie{userid}");

  my $projects = OMP::ProjServer->listProjects($xmlquery, 'object');

  if (@$projects) {
    # Group by either project ID or TAG priority
    # If grouping by project ID, group by telescope, semester, and
    # country, then sort by project number.
    # Otherwise, group the projects by country and telescope, then
    # sort by TAG priority, or adjusted priority.
    #
    # NOTE: This may be too slow.  We will probably want to let the
    # database do the sorting and grouping for us in the future,
    # although that will require OMP::ProjQuery to support
    # <orderby> and <groupby> tags
    my @sorted;

    if ($order eq 'projectid') {

      my %group;
      for (@$projects) {

        # Try to get the semester from the project ID since that is
        # more useful for sorting than the actual semester which will
        # be the same for all projects
        my $sem = $_->semester_ori;
        (! $sem) and $sem = $_->semester;

        # Fudge with semesters like 99A so that they are sorted
        # before and not after later semesters like 00B and 04A
        ($sem =~ /^(9\d)([ab])$/i) and $sem = $1 - 100 . $2;

        push @{$group{$_->telescope}{$sem}{$_->country}}, $_;
      }

      # Grouping is finished. Now sort.
      for my $telescope (sort keys %group) {
        for my $semester (sort {$a <=> $b} keys %{$group{$telescope}}) {
          for my $country (sort keys %{$group{$telescope}{$semester}}) {

            my @tmpsort = sort {$a->project_number <=> $b->project_number}
              @{$group{$telescope}{$semester}{$country}};

            push @sorted, @tmpsort;
          }
        }
      }
    } else {

      my %adj_priority;
      for ( @$projects ) {

        $adj_priority{$_} = $_->tagpriority();

        next unless $order eq 'adj-priority';

        my $adj = $_->tagadjustment( $_->primaryqueue() )
          or next;

        $adj_priority{$_} += $adj;
      }

      if ($telescope and $country) {
        @sorted = sort {$adj_priority{$a} <=> $adj_priority{$b}} @$projects;
      } else {
        my %group;
        for (@$projects) {
          push @{$group{$_->telescope}{$_->country}}, $_;
        }

        for my $telescope (sort keys %group) {
          for my $country (sort keys %{$group{$telescope}}) {
            my @sortedcountry = sort {$adj_priority{$a} <=> $adj_priority{$b}} @{$group{$telescope}{$country}};
            push @sorted, @sortedcountry;
          }
        }
      }
    }

    # Display a list of projects if any were returned
    print $q->h2("Projects for semester $semester");

    OMP::CGIComponent::Project::list_projects_form($q);

    print $q->hr;

    if ($q->param('table_format')) {

      if ($order eq 'priority') {
        OMP::CGIComponent::Project::proj_sum_table(\@sorted, $q);
      } else {
        # Display table with semester and country headings
        # since we sorted by project ID
        OMP::CGIComponent::Project::proj_sum_table(\@sorted, $q, 1);
      }

    } else {

      my $pub = public_url();

      foreach my $project (@sorted) {
        print "<a href='$pub/projecthome.pl?urlprojid=" . $project->projectid . "'>";
        print $q->h2('Project ' . $project->projectid);
        print "</a>";
        my %details = (projectid=>$project->projectid, password=>$cookie{password});
        OMP::CGIComponent::Project::proj_status_table($q, %details);

        print $q->h3('MSBs observed');
        OMP::CGIComponent::MSB::fb_msb_observed($q, $project->projectid);

        print $q->h3('MSBs to be observed');
        OMP::CGIComponent::MSB::fb_msb_active($q,$project->projectid,$cookie{'password'});
      }

    }

    print $q->hr;

    OMP::CGIComponent::Project::list_projects_form($q);

  } else {
    # Otherwise just put the form back up
    print $q->h2("No projects for semester $semester matching your query");

    OMP::CGIComponent::Project::list_projects_form($q);

    print $q->hr;
  }
}

=item B<project_home>

Create a page which has a simple summary of the project and links to the rest of the system that are easy to follow.

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
  my $projectid = $project->projectid;
  my $country = $project->country;
  my $title = $project->title;
  my $semester = $project->semester;
  my $allocated = $project->allocated->pretty_print;
  ($project->allRemaining->seconds > 0) and
    my $remaining = $project->allRemaining->pretty_print;
  my $pi = OMP::Display->userhtml(
    $project->pi, $q, $project->contactable($project->pi->userid), $project->projectid,
    affiliation => $project->pi()->affiliation());
  my $taurange = $project->taurange;
  my $seerange = $project->seeingrange;
  my $skyrange = $project->skyrange;
  my $cloud = $project->cloudrange;
  my $expirydate = $project->expirydate() // 'not specified';

  # Store coi and support html emails
  my $coi = join(", ",map{
    OMP::Display->userhtml($_, $q, $project->contactable($_->userid), $project->projectid,
    affiliation => $_->affiliation())
  } $project->coi);

  my $support = join(", ",map{OMP::Display->userhtml($_, $q)} $project->support);

  # Make a big header for the page with the project ID and title
  print "<table width=100%><tr><td>";
  print "<h2>$projectid: $title</h2>";

  # Is this project a TOO?
  ($project->isTOO) and print "<i>This project is a target of opportunity</i><br>";

  # Make it obvious if this project is disabled
  (! $project->state) and print "<h2>This project is disabled</h2>";

  print "</td><td align=right valign=top>";

  # We'll display a flag icon representing the country if we have
  # one for it
  if ($country =~ /\b(UK|INT|CA|NL|UH|JAC|JP|KR)\b/) {
    my $country = lc($country);
    print "<img src='/images/flag_$country.gif'>";
  }
  print "</td></table>";

  my $pub = public_url();

  my $proposal_url = 'https://proposals.eaobservatory.org/'
    . (lc $project->telescope)
    . '/proposal_by_code?code=' . $projectid;

  # The project info (but in a different format than what is
  # generated by proj_status_table)
  print <<"_HEADER_";
    <table>
    <tr><td><b>Principal Investigator:</b></td><td>$pi</td>
    <tr><td><b>Co-investigators:</b></td><td>$coi</td>
    <tr><td><b>Support:</b></td><td>$support</td>
    <tr><td><b>Country:</b></td><td>$country</td>
    <tr><td><b>Semester:</b></td><td>$semester</td>
    <tr><td><b>Expiry date:</b></td><td>$expirydate</td>
    <tr><td colspan=2><a href="$pub/props.pl?urlprojid=$cookie{projectid}">Click here to view the science case for this project</a></td>
    <tr><td colspan=2><a href="$proposal_url">Click here to view this project in the proposal system</a></td>
    </table>
_HEADER_

  # Time allocated/remaining along with tau range
  print "<br>";
  print "<table>";
  print "<tr><td><b>Time allocated to project:</b></td><td>$allocated ";

  # If range is from 0 to infinity dont bother displaying it
  print "in tau range $taurange"
    if !OMP::SiteQuality::is_default( 'TAU',$taurange );

  print " in seeing range $seerange"
    if !OMP::SiteQuality::is_default( 'SEEING',$seerange );

  print " with sky brightness $skyrange"
    if !OMP::SiteQuality::is_default( 'SKY',$skyrange );

  print " with sky " . $project->cloudtxt
    if !OMP::SiteQuality::is_default( 'CLOUD',$cloud );

  print "</td>";

  if ($remaining) {
    print "<tr><td><b>Time remaining on project:</b></td><td>$remaining</td>";
  } else {
    print "<tr><td colspan=2><b>There is no time remaining on this project</b></td>";
  }
  print "<tr><td><b>Completion rate:</b></td><td>".
    int($project->percentComplete) ."%</td>\n";

  print "</table>";

  # Get nights for which data was taken
  my $nights = OMP::MSBServer->observedDates($project->projectid, 1);

  # Since time may have been charged to the project even though no MSBs
  # were observed, check with the accounting DB as well
  my $adb = new OMP::TimeAcctDB( DB => new OMP::DBbackend );

  # Because of shifttypes, there may be more than one shift per night.
  my @accounts = $adb->getTimeSpent( projectid => $project->projectid );

  # Merge our results
  #my %nights = map {$_->date->ymd, undef} @accounts;

  #for (@$nights) {
  #  $nights{$_->ymd} = undef;
  #}

  # Link to obslog for current day
  my $today = OMP::DateTools->today();
  print "<br><a href=\"utprojlog.pl?urlprojid=$cookie{projectid}&utdate=$today\">".
    "Click here to remote eavesdrop</a><br>";

  # Display nights where data was taken
  if (@$nights) {

      my %accounts;
      # Sort account objects by night
      for my $acc (@accounts) {
	  unless (exists $accounts{$acc->date->ymd}) {
	      $accounts{$acc->date->ymd} = [];
	  }
	  push (@{$accounts{$acc->date->ymd}}, $acc);

      }

      # Some instruments do not allow data retrieval. For now, assume that
      # we can not retrieve if any of the instruments in the project are marked as such.
      # For surveys this will usually be the case
      my $cannot_retrieve;
      try {
	  my @noretrieve = OMP::Config->getData( "unretrievable", telescope => $project->telescope );
	  my $projinst = OMP::SpServer->programInstruments($cookie{projectid});

	  # See if the instrument in the project are listed in noretrieve
	  my %inproj = map { (uc($_), undef ) } @$projinst;

	  for my $nr (@noretrieve) {
	      if (exists $inproj{uc($nr)}) {
		  $cannot_retrieve = 1;
		  last;
	      }
	  }
      } otherwise {
      };

      print "<h3>Observations were acquired on the following dates:</h3>";

      my $pkg_url = OMP::Config->getData('pkgdata-url');

      for my $ymd (sort keys %accounts) {

	  # Make a link to the obslog page
	  my $obslog_url = "utprojlog.pl?urlprojid=$cookie{projectid}&utdate=$ymd";

	  # If project is an unretrievable project, link to project log with
	  # 'noretrv' paramater so that no data retrieval links will appear
	  $obslog_url .= "&noretrv=1" if ($cannot_retrieve);

	  print "<a href='$obslog_url'>$ymd</a> ";

	  if (exists $accounts{$ymd}) {

	      # Need to sum up over shift:
	      my $confirmedtime = 0.0;
	      my $unconfirmedtime = 0.0;

	      my $confirmed_string = "";
	      my $unconfirmed_string = "";
	      for my $timeacctobject (@{$accounts{$ymd}}) {
		  my $timespent = $timeacctobject->timespent;
		  if ($timespent->hours) {
		      if ($timeacctobject->confirmed) {
			  $confirmedtime += $timespent->hours;
		      } else {
			  $unconfirmedtime += $timespent->hours;
		      }
		  }
	      }

	      $confirmed_string = sprintf("%.2f hrs ", $confirmedtime) . "";
	      if ($unconfirmedtime > 0 ) {
		  # If the time spent is unconfirmed, say so
		  $unconfirmed_string = sprintf(" +  UNCONFIRMED: %.2f hrs ", $unconfirmedtime);
	      }
	      if (($confirmedtime >0) || ($unconfirmedtime > 0)) {
		  print $confirmed_string;
		  print $unconfirmed_string;


		  if ($cannot_retrieve) {
		      print "click on date to view project log";
		  } else {
		      print "click on date to retrieve data";
		  }

	      } else {
		  print "(no science data charged) ";
	      }
	  } else {
	      print "[internal error - do not know accounting information] ";
	  }

	  print "<br>";

      }
  } else {
    print "<h3>No data have been acquired for this project</h3>";
  }

  # Display observed MSBs if any data have been taken for this project
  if (@$nights) {
    print "<h3>The following MSBs have been observed:</h3>";
    OMP::CGIComponent::MSB::fb_msb_observed($q, $cookie{projectid});
    print "<br>";
  } else {
    print "<h3>No MSBs have been observed</h3>";
  }

  # Link to the MSB history page
  print "Click <a href='msbhist.pl'>here</a> for more details on the observing history of each MSB.";

  # Display remaining MSBs
  print "<h3>MSBs remaining to be observed:</h3>";
  OMP::CGIComponent::MSB::fb_msb_active($q, @cookie{qw/projectid password/});

  # Link to the program details page
  print "<br>Click <a href='fbmsb.pl'>here</a> for more details on the science program.";

  # Link to the region plot / download
  print '<br>Click <a href="spregion.pl">here</a> to download or plot the regions observed in this program.';

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

    # Display project details
    OMP::CGIComponent::Project::proj_status_table($q, %cookie);

    # Submit feedback comment or display form
    if ($q->param('Submit')) {
      OMP::CGIComponent::Feedback::submit_fb_comment($q, $cookie{projectid});
      print "<P>";

      # Link back to start page
      print "<a href='". $q ->url(-relative=>1) ."'>View details for another project</a>";

    } else {
      # Form for adding feedback comment
      print "<strong>Add a feedback comment</strong><br>";
      OMP::CGIComponent::Feedback::comment_form($q, %cookie);
    }

  } else {
    print start_form_absolute($q);
    print "Project ID: ";
    print $q->textfield(-name=>"projectid",
                        1-size=>12,
                        -maxlength=>32,);
    print "&nbsp;";
    print $q->submit(-name=>"projectid_submit",
                     -label=>"Submit",);
  }

}

=item B<program_summary>

View summary text of a science program.

=cut

sub program_summary {
    my $q = shift;
    my %cookie = @_;

    # Retrieve the science program.
    my $projectid = OMP::General->extract_projectid($cookie{'projectid'});
    die 'Did not recieve valid project ID.' unless $projectid;

    select(STDERR);
    my $sp = OMP::CGIDBHelper::safeFetchSciProg($projectid, $cookie{'password'});
    select(STDOUT);

    unless (defined $sp) {
        print
            $q->header(),
            $q->start_html('Error: no science program'),
            $q->h2('Error'),
            $q->p('The science program could not be fetched for this project.'),
            $q->end_html();
        return;
    }

    # Program retrieved successfully: apply summary XSLT.
    print $q->header(-type => 'text/plain');

    $sp->apply_xslt('toml_summary.xslt');
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
    #  File name to offer for file being downloaded.
    my $offer = 'proposal';

  dirloop:
    for my $dir (@dirs) {
      for my $ext (qw/ps pdf ps.gz txt/) {
        my $name = "$propfilebase.$ext";
        if (-e "$dir/$name") {
          $propfile = "$dir/$name";
          $offer .= '-' . $name;
          $type = $extensions{$ext};
          last dirloop;
        }
      }
    }

    if ($propfile) {

      # Read in proposal file
      open( my $fh, '<', $propfile);
      my @file = <$fh>;   # Slurrrp!

      close($fh);

      # Serve proposal
      print $q->header( -type=>$type,
                        -Content_Disposition => qq[attachment; filename=$offer]
                      );

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

=item B<support>

Create a page listing staff contacts for a project and which also provides a form for defining which is the primary staff contact.

  support($cgi);

=cut

sub support {
  my $q = shift;
  my %cookie = @_;

  # Try and get a project ID
  my $projectid = OMP::General->extract_projectid($q->param('projectid'));
  (! $projectid) and $projectid = OMP::General->extract_projectid($q->url_param('urlprojid'));

  # A form for providing a project ID
  print start_form_absolute($q);
  print "<strong>Project ID: </strong>";
  print $q->textfield(-name=>'projectid',
                      -size=>12,
                      -maxlength=>32,);
  print " " . $q->submit(-name=>'get_projectid', -value=>'Submit');
  print $q->end_form;
  print "<hr>";

  return if (! $projectid);

  my $projdb = new OMP::ProjDB( ProjectID => $projectid,
                                'Password' => $cookie{'password'},
                                DB => new OMP::DBbackend, );

  # Verify that project exists
  my $verify = $projdb->verifyProject;
  if (! $verify) {
    print "<h3>No project with ID of [$projectid] exists</h3>";
    return;
  }

  # Get project details (as object)
  my $project;
  try {
    $project = $projdb->projectDetails("object");
  }
  catch OMP::Error::Authentication with {

    my ( $E ) = @_;
    print "<h3>An error occurred while getting project details.</h3>",
      "<p>$E</p>";
  };
  return unless $project;

  # Make contact changes, if any
  if ($q->param('change_primary')) {

    # Get new primary contacts (frox checkbox group)
    my %primary = map {$_, undef} $q->param('primary');

    # Must have atleast one primary contact defined.
    if (%primary) {
      # Create a new contactability hash
      my %contactable = map {
        $_->userid, (exists $primary{$_->userid} ? 1 : 0)
      } $project->support;

      # Store changes to DB
      my $E;
      try {
        $projdb->updateContactability( \%contactable );
        $project->contactable(%contactable);
      } otherwise {
        $E = shift;
        print "<h3>An error occurred.  Your changes have not been stored.</h3>$E";
      };
      return if ($E);

      print "<h3>Primary support contacts have been changed</h3>";
    } else {
      # No new primary contacts defined
      print "<h3>Atleast one primary support contact must be defined.  Your changes have not been stored.</h3>";
    }
  }

  # Get support contacts
  my @support = $project->support;

  # Store primary
  my @primary = grep {$project->contactable($_->userid)} @support;

  # Store secondary
  my @secondary = grep {! $project->contactable($_->userid)} @support;

  print "<h3>Editing support contacts for $projectid</h3>";

  # List primary
  print "<strong>Support contacts</strong>: ";
  print join(", ", map {OMP::Display->userhtml($_, $q)} @primary);

  # List secondary
  if (@secondary) {
    print "<br>";
    print "<strong>Secondary support contacts</strong>: ";
    print join(", ", map {OMP::Display->userhtml($_, $q)} @secondary);
  }

  # Generate labels and values for primary support form
  my %labels = map {$_->userid, $_->name} @support;
  my @userids = sort map {$_->userid} @support;
  my @defaults = map {$_->userid} @primary;

  # Form for defining primary support
  print "<h3>Define primary support contacts</h3>";
  print start_form_absolute($q, -name=>'define_primary');
  print $q->checkbox_group(-name=>'primary',
                           -values=>\@userids,
                           -defaults=>\@defaults,
                           -linebreak=>'true',
                           -labels=>\%labels,);

  # Hide project ID in form
  print $q->hidden(-name=>'projectid', -default=>$projectid);
  print "<br>" . $q->submit(-name=>'change_primary', -value=>'Submit');
  print $q->end_form;
  print "<br><small>Note: Only primary support contacts will receive project email.</small>";
}

=item B<alter_proj>

Create a page for adjusting a project's properties.

  alter_proj($cgi_object, %cookie);

=cut

sub alter_proj {
  my $q = shift;
  my %cookie = @_;

  # Obtain project ID
  my $projectid = OMP::CGIComponent::Project::obtain_projectid( $q );

  my $userid = $cookie{userid};

  return unless $projectid;

  print "<h3>Alter project details for ". uc($projectid) ."</h3>";

  # Connect to the database
  my $projdb = new OMP::ProjDB( DB => new OMP::DBbackend );

  # Set the project ID in the DB object
  $projdb->projectid( $projectid );

  # Retrieve the project object
  my $project = $projdb->_get_project_row();

  print "<b>(". $project->pi .")</b> ". $project->title ."<br><br>";

  return process_project_changes( $q, $userid, $project, $projdb )
    if $q->param('alter_submit');

  # Display form for updating project details
  print start_form_absolute($q, -name=>'alter_project');

  print $q->hidden(-name=>'projectid',
                    -default=>$project->projectid,);

  print $q->hidden(-name=>'userid',
                    -default=>$userid,);

  print "<table>";

  my $pi = $project->pi->userid();
  my $pi_affiliation = $project->pi->affiliation();
  $pi .= ':' . $pi_affiliation if defined $pi_affiliation;
  print qq[<tr><td align="right">PI</td> <td>],
    $q->textfield( 'pi', $pi, 32, 32 ),
    qq[</td></tr>];

  print qq[<tr><td align="right">Title</td> <td>],
    $q->textfield( 'title', $project->title, 50, 255 ),
    qq[</td></tr>];

  my $coi = join "\n", map {
    my $userid = $_->userid();
    my $coi_affiliation = $_->affiliation();
    $userid .= ':' . $coi_affiliation if defined $coi_affiliation;
    $userid;
  } $project->coi;
  print qq[<tr><td align="right">Co-I</td> <td>],
    $q->textarea( -name => 'coi',
                  -default => $coi,
                  -rows => 5,
                  -columns => 32,
                ),
    qq[</td></tr>];

  my $supp = join "\n", map { $_->userid } $project->support;
  print qq[<tr><td align="right">Support</td> <td>],
    $q->textarea( -name => 'support',
                  -default => $supp,
                  -rows => 5,
                  -columns => 32,
                ),
    qq[</td></tr>];

  # Allocation
  print "<tr><td align='right'>Allocation</td>";
  my $allocated = $project->allocated;
  my $remaining = $project->remaining;
#    my ($alloc_h, $alloc_m, $alloc_s) = split(/\D/,$allocated->pretty_print);
  my $alloc_h = int( $allocated / 3600 );
  my $alloc_m = int( ( $allocated - $alloc_h * 3600 ) / 60 );
  my $alloc_s = $allocated - $alloc_h * 3600 - $alloc_m * 60;
  print "<td>";
  print $q->textfield('alloc_h',$alloc_h,3,5);
  print " hours ";
  print $q->textfield('alloc_m',$alloc_m,2,2);
  print " minutes ";
  print $q->textfield('alloc_s',$alloc_s,2,2);
  print " seconds";
  print "</td></tr><tr><td align='right'>Remaining</td><td>". $remaining->pretty_print;
  print "</td></tr>";

  # Semester
  print "<tr><td align='right'>Semester</td>";
  my $semester = $project->semester;

  # Get semester options
  my @semesters = $projdb->listSemesters();

  print "<td>";
  print $q->popup_menu(-name=>'semester',
                        -default=>$semester,
                        -values=>[@semesters]);
  print "</td></tr>";

  # Cloud
  print "<tr><td align='right'>Cloud</td>";
  my $cloud = $project->cloudrange;

  # Get cloud options
  my %cloud_lut = OMP::SiteQuality::get_cloud_text();
  my %cloud_labels = map {$cloud_lut{$_}->max(), $_} keys %cloud_lut;

  print "<td>";
  print $q->popup_menu(-name=>'cloud',
                        -default=>int($cloud->max()),
                        -values=>[reverse sort {$a <=> $b} keys %cloud_labels],
                        -labels=>\%cloud_labels,);
  print "</td></tr>";

  # Tag adjustment
  print "<tr><td align='right' valign='top'>TAG adj.</td>";
  my %tagpriority = $project->queue;
  my %tagadj = $project->tagadjustment;

  my $keycount;
  for my $queue (keys %tagpriority) {
    $keycount++;
    print "<tr><td></td>"
      if ($keycount > 1);

    print "<td valign='top'>";
    print "<font size=-1>Note: a negative number increases the project's priority</font><br>"
      unless ($keycount > 1);

    print $q->textfield("tag_${queue}",
                        ($tagadj{$queue} =~ /^\d+$/ ? '+' : '') . $tagadj{$queue},
                        4,32);
    print " <font size=-1>(Queue: $queue Priority: $tagpriority{$queue})</font>";

    print "</td></tr>";
  }

  # TAU Range
  print "<tr><td align='right' valign='top'>TAU range</td>";
  my $taurange = $project->taurange;
  my $taumin = $taurange->min();
  my $taumax = $taurange->max();
  print "<td>";
  print $q->textfield("taumin", $taumin, 3, 4);
  print " - ";
  print $q->textfield("taumax", $taumax, 3, 4);
  print "</td></tr>";

  # Seeing Range
  print "<tr><td align='right' valign='top'>Seeing range</td>";
  my $seeingrange = $project->seeingrange;
  my $seeingmin = $seeingrange->min();
  my $seeingmax = $seeingrange->max();
  print "<td>";
  print $q->textfield("seeingmin", $seeingmin, 3, 4);
  print " - ";
  print $q->textfield("seeingmax", $seeingmax, 3, 4);
  print "</td></tr>";

  print $q->Tr(
    $q->td([
        'Expiry date',
        $q->textfield(-name => 'expirydate', -default => ($project->expirydate() // '')),
    ]),
  );

  print "</table>";

  print q[<p>],
    $q->checkbox( -name => 'send-mail',
                  -checked => 0,
                  -value => 1,
                  -label => 'Send email about project changes'
                ),
    q[</p><p>],
    $q->submit( -name=>"alter_submit",
                -label=>"Submit",
              ),
    ( '&nbsp;' ) x 4,
    $q->reset,
    q[</p>],
    $q->end_form();
}

sub process_project_changes {

  my ( $q, $userid, $project, $projdb ) = @_;

  my @msg; # Build up output message

  my $err;
  for my $type ( qw[ pi coi support ] ) {

    my $users = $q->param( $type );
    try {

      push @msg, update_users( $project, $type, split /[;,\s]+/, $users );
    }
    catch OMP::Error with {

      my ( $e ) = @_;
      $err = _print_user_err( $e->text );
    };
  }

  return if $err;

  push @msg,
    _update_project_make_message( $project,
                                  \&_match_string,
                                  'update' => 'title',
                                  'field-text' => 'title',
                                  'old' => $project->title,
                                  'new' => $q->param( 'title' )
                                );

  # Check whether allocation has changed
  my $new_alloc_h = $q->param('alloc_h') * 3600;
  my $new_alloc_m = $q->param('alloc_m') * 60;
  my $new_alloc_s = $q->param('alloc_s');
  my $new_alloc = Time::Seconds->new($new_alloc_h + $new_alloc_m + $new_alloc_s);
  my $old_alloc = $project->allocated;

  if ($new_alloc != $old_alloc) {

    # Allocation was changed
    $project->fixAlloc($new_alloc->hours);

    push @msg, "Updated allocated time from ". $old_alloc->pretty_print ." to ". $new_alloc->pretty_print .".";
  }

  # Check whether semester has changed
  my $new_sem = $q->param('semester');
  my $old_sem = $project->semester;

  if ($new_sem ne $old_sem) {

    # Semester waschanged
    $project->semester($new_sem);

    push @msg, "Updated semester from ". $old_sem ." to ". $new_sem .".";
  }

  # Check whether cloud constraint has changed
  my $new_cloud_max = $q->param('cloud');
  my $new_cloud = OMP::SiteQuality::default_range('CLOUD');
  $new_cloud->max($new_cloud_max);
  my $old_cloud = $project->cloudrange;

  if ($new_cloud->max() != $old_cloud->max()) {

    # Cloud constraint was changed
    $project->cloudrange($new_cloud);

    push @msg, "Updated cloud range constraint from ". $old_cloud." to ". $new_cloud .".";
  }

  # Check whether TAG adjustment has changed
  my %oldadj = $project->tagadjustment;
  my %newadj;
  for my $queue (keys %oldadj) {
    $newadj{$queue} = $q->param('tag_'. $queue);

    # Taint checking


    if (defined $newadj{$queue} and $newadj{$queue} != $oldadj{$queue}) {

      # POSSIBLE KLUGE: setting a new tagadjustment causes the actual
      # tagpriority to change, which is okay when reading a project
      # object, but not okay when storing the object back to the database.
      # In order to reset the tagpriority, the tagpriority method is
      # called with its original value.

      my $oldpriority = $project->tagpriority($queue);

      $project->tagadjustment({$queue, $newadj{$queue}});

      $project->tagpriority($queue => $oldpriority);

      push @msg, "Updated TAG adjustment for $queue queue from $oldadj{$queue} to $newadj{$queue}."
    }
  }

  # Check whether TAU range has changed
  my $old_taurange = $project->taurange;
  my %tau_params;
  $tau_params{Min} = $q->param('taumin');
  $tau_params{Max} = $q->param('taumax')
    unless (! $q->param('taumax'));
  my $new_taurange = new OMP::Range(%tau_params);

  if ($old_taurange->min() != $new_taurange->min()
      or $old_taurange->max() != $new_taurange->max()) {

    $project->taurange($new_taurange);

    push @msg, "Updated TAU range from ". $old_taurange ." to ". $new_taurange .".";
  }

  # Check whether Seeing range has changed
  my $old_seeingrange = $project->seeingrange;
  my %seeing_params;
  $seeing_params{Min} = $q->param('seeingmin');
  $seeing_params{Max} = $q->param('seeingmax')
    unless (! $q->param('seeingmax'));
  my $new_seeingrange = new OMP::Range(%seeing_params);

  if ($old_seeingrange->min() != $new_seeingrange->min()
      or $old_seeingrange->max() != $new_seeingrange->max()) {

    $project->seeingrange($new_seeingrange);

    push @msg, "Updated Seeing range from ". $old_seeingrange ." to ". $new_seeingrange .".";
  }

  # Check whether the expiry date was changed
  my $old_expirydate = $project->expirydate();
  my $expirydate = $q->param('expirydate');
  if ((not defined $old_expirydate) and (! $expirydate)) {
    # Expiry date null in database and not set here: do nothing.
  }
  elsif ((not defined $old_expirydate) or (! $expirydate) or ($expirydate ne "$old_expirydate")) {
    # Expiry date has changed.
    undef $expirydate unless $expirydate;
    $project->expirydate($expirydate);

    push @msg, 'Updated expiry date from ' .
        ($old_expirydate // 'none') . ' to ' .
        ($expirydate // 'none') . '.';
  }

  # Generate feedback message

  # Get OMP user object
  if ( $q->param( 'send-mail' ) ) {

    my $user_obj = OMP::UserServer->getUser($userid);
    OMP::FBServer->addComment($project->projectid,
                              {author => $user_obj,
                                subject => 'Project details altered',
                                text => "The following changes have been made to this project:\n\n".
                                join("\n", @msg)},
                              );
  }

  # Now store the changes
  $projdb->_update_project_row( $project );

  if ($msg[0]) {
    print join("<br>", @msg);

    print '<br><br>',
      ( scalar @msg == 1 ? 'This change has' : 'These changes have' ),
      ' been committed.<br>';

  } else {
    print "<br>No changes were submitted.</br>";
  }

  return;
}

sub update_users {

  my ( $proj, $type, @userid ) = @_;

  return unless $proj && (scalar @userid or $type ne 'pi');

  my @old = $proj->$type;

  my $old_id = join ',', map {
    my $id = $_->userid();
    my $affiliation = $_->affiliation();
    $id .= ':' . $affiliation if defined $affiliation;
    $id;
  } @old;
  return if _match_string( $old_id, join ',', @userid );

  my @user = map { _make_user( $_ ) } @userid;

  if ($type eq 'pi') {
    # The "pi" method only accepts a single user (first argument) so pass
    # list directly.
    $proj->$type( @user );
  }
  else {
    # Pass list as a reference in case it is empty.
    $proj->$type( \@user );
  }

  my $join = sub { join ', ', map { $_->name } @_ };
  return
    sprintf 'Updated %s from (%s) to (%s)',
      $type,
      $join->( @old ),
      $join->( @user )
      ;
}

sub _make_user {

  my ( $userid ) = @_;

  return unless $userid;

  my $affiliation;
  ($userid, $affiliation) = split ':', $userid, 2;

  my $user = OMP::UserServer->getUser( $userid )
    or throw OMP::Error "Unknown user id given: $userid";

  if (defined $affiliation) {
    throw OMP::Error::FatalError("User $userid affiliation '$affiliation' not recognized by the OMP")
      unless exists $OMP::ProjAffiliationDB::AFFILIATION_NAMES{$affiliation};

    $user->affiliation($affiliation);
  }

  return $user;
}

sub _print_user_err {

  my ( $text ) = @_;

  return unless $text && (
    $text =~ m/^Unknown user id given/
    || $text =~ m/not recognized by the OMP$/);

  printf "<p>%s</p>\n", $text;
  return 1;
}

sub _match_string {

  my ( $one, $two ) = @_;

  return
    ( defined $one && defined $two )
    &&
    ( $one eq $two )
    ;
}

sub _match_number {

  my ( $one, $two ) = @_;

  return
    ( defined $one && defined $two )
    &&
    ( $one == $two )
    ;
}

sub _update_project_make_message {

  my ( $project, $match, %args ) = @_;

  my ( $old, $new ) = @args{qw[ old new ]};

  return if $match && $match->( $old, $new );

  my $update = $args{'update'};
  $project->$update( $new )
    and return qq[Updated $args{'field-text'} from "$old" to "$new".];

  return;
}


=back

=head1 SEE ALSO

C<OMP::CGIComponent::Project>, C<OMP::CGIComponent::Feedback>,
C<OMP::CGIComponent::MSB>

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
