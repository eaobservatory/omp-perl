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
use OMP::General;
use OMP::MSBServer;
use OMP::ProjDB;
use OMP::ProjServer;
use OMP::TimeAcctDB;

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
  OMP::CGIComponent::MSB::fb_msb_active($q, $cookie{projectid});

  print $q->hr;
}

=item B<issuepwd>

Create a page with a form for requesting a password.

  issuepwd($cgi);

=cut

sub issuepwd {
  my $q = shift;

  print "<H1>OMP Password Request Page</h1>";
  print "You can use this page to request an updated password for your project.<br>";
  print "Example project IDs: u/02b/20, m03ac18<br><br>";
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

  # Get the Private and Public cgi-bin URLs
  my $public_url = public_url();
  my $private_url = private_url();

  my $semester = $q->param('semester');
  my $state = ($q->param('state') eq 'all' ? undef : $q->param('state'));
  my $status = ($q->param('status') eq 'all' ? undef : $q->param('status'));
  my $support = $q->param('support');
  my $country = $q->param('country');
  my $telescope = $q->param('telescope');
  my $order = $q->param('order');

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
    # sort by TAG priority
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
      if ($telescope and $country) {
	@sorted = sort {$a->tagpriority <=> $b->tagpriority} @$projects;
      } else {
	my %group;
	for (@$projects) {
	  push @{$group{$_->telescope}{$_->country}}, $_;
	}

	for my $telescope (sort keys %group) {
	  for my $country (sort keys %{$group{$telescope}}) {
	    my @sortedcountry = sort {$a->tagpriority <=> $b->tagpriority} @{$group{$telescope}{$country}};
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
      foreach my $project (@sorted) {
	print "<a href='$public_url/projecthome.pl?urlprojid=" . $project->projectid . "'>";
	print $q->h2('Project ' . $project->projectid);
	print "</a>";
	my %details = (projectid=>$project->projectid, password=>$cookie{password});
	OMP::CGIComponent::Project::proj_status_table($q, %details);
	
	print $q->h3('MSBs observed');
	OMP::CGIComponent::MSB::fb_msb_observed($q, $project->projectid);
	
	print $q->h3('MSBs to be observed');
	OMP::CGIComponent::MSB::fb_msb_active($q,$project->projectid);	
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
  my $pi = OMP::Display->userhtml($project->pi, $q, $project->contactable($project->pi->userid), $project->projectid);
  my $taurange = $project->taurange;
  my $seerange = $project->seerange;
  my $cloud = $project->cloud;

  # Store coi and support html emails
  my $coi = join(", ",map{OMP::Display->userhtml($_, $q, $project->contactable($_->userid), $project->projectid)} $project->coi);

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
  if ($country =~ /(UK|INT|CA|NL|UH|JAC|JP)/) {
    my $country = lc($country);
    print "<img src='/images/flag_$country.gif'>";
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

  # Display a flex page link for UKIRT.  Temporary, of course.
  if ($project->telescope =~ /ukirt/i) {
    my $sem = $project->semester;
    print "<tr><td><a href='http://www.jach.hawaii.edu/JAClocal/cgi-bin/omp/flexpage.pl?output=1&sem=$sem'>View the Flex programme descriptions page</a></td>";
  }

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
  print "<tr><td><b>Completion rate:</b></td><td>".
    int($project->percentComplete) ."%</td>\n";

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

  # Link to obslog for current day
  my $today = OMP::General->today();
  print "<br><a href=\"utprojlog.pl?urlprojid=$cookie{projectid}&utdate=$today\">".
    "Click here to remote eavesdrop</a><br>";

  # Display nights where data was taken
  if (%nights) {

    # Sort account objects by night
    my %accounts;
    for (@accounts) {
      $accounts{$_->date->ymd} = $_;
    }

    print "<h3>Observations were acquired on the following dates:</h3>";

    my $pkg_url = OMP::Config->getData('pkgdata-url');

    for my $ymd (sort keys %nights) {

      # Make a link to the obslog page
      print "<a href='utprojlog.pl?urlprojid=$cookie{projectid}&utdate=$ymd'>$ymd</a> ";

      if (exists $accounts{$ymd}) {
	my $timespent = $accounts{$ymd}->timespent;
        if ($timespent->hours) {
  	  my $h = sprintf("%.1f", $timespent->hours);

	  # If the time spent is unconfirmed, say so
	  print "[UNCONFIRMED] " unless ($accounts{$ymd}->confirmed);

	  print "($h hours) click on date to retrieve data";
        } else {
	  print "(no science data taken) ";
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
  OMP::CGIComponent::MSB::fb_msb_active($q, $cookie{projectid});

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
  print $q->start_form;
  print "<strong>Project ID: </strong>";
  print $q->textfield(-name=>'projectid',
		      -size=>12,
		      -maxlength=>32,);
  print " " . $q->submit(-name=>'get_projectid', -value=>'Submit');
  print $q->end_form;
  print "<hr>";

  return if (! $projectid);

  my $projdb = new OMP::ProjDB( ProjectID => $projectid,
				Password => "***REMOVED***",
				DB => new OMP::DBbackend, );

  # Verify that project exists
  my $verify = $projdb->verifyProject;
  if (! $verify) {
    print "<h3>No project with ID of [$projectid] exists</h3>";
    return;
  }

  # Get project details (as object)
  my $project = $projdb->projectDetails("object");

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
      
      $project->contactable(%contactable);

      # Store changes to DB
      my $E;
      try {
	$projdb->addProject( $project, 1 );
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
  print $q->start_form(-name=>'define_primary');
  print $q->checkbox_group(-name=>'primary',
			   -values=>\@userids,
			   -defaults=>\@defaults,
			   -linebreak=>'true',
			   -labels=>\%labels,);

  # Hide project ID in form
  print $q->hidden(-name=>'projectid', -default=>$projectid);
  print "<br>" . $q->submit(-name=>'change_primary', -value=>'Submit');
  print $q->end_form;
  print "<br><small>Note: Only primary support contacts will recieve project email.</small>";
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

=cut

1;
