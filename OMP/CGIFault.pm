package OMP::CGIFault;

=head1 NAME

OMP::CGIHelper - Helper for the OMP fault CGI scripts

=head1 SYNOPSIS

  use OMP::CGIFault;
  use OMP::CGIFault qw/file_fault/;

=head1 DESCRIPTION

Provide functions to generate the OMP fault system CGI scripts.

=cut

use 5.006;
use strict;
use warnings;
use Carp;
our $VERSION = (qw$ Revision: 1.2 $ )[1];

use Time::Piece;

use OMP::Fault;
use OMP::FaultServer;
use OMP::Fault::Response;
use OMP::MSBServer;
use OMP::User;
use OMP::Error qw(:try);

use vars qw/@ISA %EXPORT_TAGS @EXPORT_OK/;

require Exporter;

$| = 1;

@ISA = qw/Exporter/;

@EXPORT_OK = (qw/file_fault file_fault_output query_fault_content query_fault_output view_fault_content view_fault_output sidebar_summary fault_table response_form show_faults/);

%EXPORT_TAGS = (
		'all' =>[ @EXPORT_OK ],
	       );

Exporter::export_tags(qw/ all /);

# Width for HTML tables
our $TABLEWIDTH = 620;

=head1 Routines

=over 4

=item B<file_fault>

Creates a page with a form for for filing a fault.

  file_fault( $cgi );

Only argument should be the C<CGI> object.

=cut

sub file_fault {
  my $q = shift;
  my %cookie = @_;

  # Create values and labels for the popup_menus
  my $systems = OMP::Fault->faultSystems($cookie{category});
  my @system_values = map {$systems->{$_}} sort keys %$systems;
  my %system_labels = map {$systems->{$_}, $_} keys %$systems;

  my $types = OMP::Fault->faultTypes($cookie{category});
  my @type_values = map {$types->{$_}} sort keys %$types;
  my %type_labels = map {$types->{$_}, $_} keys %$types;

  titlebar($q, ["File Fault"], %cookie);

  print "<table border=0 cellspacing=4><tr>";
  print $q->startform;

  # Need the show_output param in order for the output code ref to be called next
  print $q->hidden(-name=>'show_output',
		   -default=>'true');

  print "<td align=right><b>User:</b></td><td>";
  print $q->textfield(-name=>'user',
		      -size=>'16',
		      -maxlength=>'90',
		      -default=>$cookie{user},);

  print "</td><tr><td align=right><b>System:</b></td><td>";
  print $q->popup_menu(-name=>'system',
		       -values=>\@system_values,
		       -default=>\$system_values[0],
		       -labels=>\%system_labels,);
  print "</td><tr><td align=right><b>Type:</b></td><td>";
  print $q->popup_menu(-name=>'type',
		       -values=>\@type_values,
		       -default=>\$type_values[0],
		       -labels=>\%type_labels,);
  print "</td><tr><td align=right><b>Time lost (hours):</b></td><td>";
  print $q->textfield(-name=>'loss',
		      -default=>'0',
		      -size=>'4',
		      -maxlength=>'10',);
  print "</td><tr><td align=right><b>Subject:</b></td><td>";
  print $q->textfield(-name=>'subject',
		      -size=>'60',
		      -maxlength=>'256',);
  print "</td><tr><td colspan=2>";
  print $q->textarea(-name=>'message',
		     -rows=>20,
		     -columns=>78,);

  # If were in the ukirt or jcmt fault categories create a checkbox group
  # for specifying an association with projects.

  if ($cookie{category} =~ /(jcmt|ukirt)/i) {
    # Values for checkbox group will be tonights projects
    my $today = OMP::General->today;
    my $aref = OMP::MSBServer->observedMSBs($today, 0, 'data');
    if (@$aref[0]) {
      my %projects;
      for (@$aref) {
	$projects{$_->projectid} = $_->projectid;
      }
      print "</td><tr><td colspan=2><b>Fault is associated with the projects: </b>";
      print $q->checkbox_group(-name=>'assoc',
			       -values=>[keys %projects] );
      print "</td><tr><td colspan=2><b>Associated projects may also be specified here if not listed above </b>";
    } else {
      print "</td><tr><td colspan=2><b>Projects associated with this fault may be specified here </b>";
    }
    print "<font size=-1>(separated by spaces)</font><b>:</b>";
    print "</td><tr><td colspan=2>";
    print $q->textfield(-name=>'assoc2',
		        -size=>50,
		        -maxlength=>300,);
  }

  print "</td><tr><td><b>";
  print $q->checkbox(-name=>'urgency',
		     -value=>'urgent',
		     -label=>"This fault is urgent");
  print "</b></td><td align=right>";
  print $q->submit(-name=>'Submit Fault');
  print $q->endform;
  print "</td></table>";
}

=item B<file_fault_output>

Submit a fault and create a page that shows the status of the submission.

  file_fault_output( $cgi );

=cut

sub file_fault_output {
  my $q = shift;
  my %cookie = @_;

  my %status = OMP::Fault->faultStatus;

  my $urgency;
  my %urgency = OMP::Fault->faultUrgency;
  if ($q->param('urgency') =~ /urgent/) {
    $urgency = $urgency{Urgent};
  } else {
    $urgency = $urgency{Normal};
  }

  # Get the associated projects
  my %projects;
  if ($q->param('assoc') or $q->param('assoc2')) {
    my @assoc = $q->param('assoc');

    # Strip out commas and seperate on spaces
    my $assoc2 = $q->param('assoc2');
    $assoc2 =~ s/,/ /g;
    my @assoc2 = split(/\s+/,$assoc2);

    %projects = map {lc($_), undef} @assoc, @assoc2;
  }

  my $author = $q->param('user');
  my $user = new OMP::User(userid => $author);

  my $resp = new OMP::Fault::Response(author=>$user,
				      text=>$q->param('message'),);

  # Create the fault object
  my $fault = new OMP::Fault(category=>$cookie{category},
			     subject=>$q->param('subject'),
			     system=>$q->param('system'),
			     type=>$q->param('type'),
			     timelost=>$q->param('loss'),
			     urgency=>$urgency,
			     fault=>$resp);

  if (%projects) {
    $fault->projects([keys %projects]);
  }

  # Submit the fault the the database
  my $faultid;
  try {
    $faultid = OMP::FaultServer->fileFault($fault);
  } otherwise {
    my $E = shift;
    print $q->h2("An error has occurred");
    print "$E";
  };

  # Show the fault if it was successfully filed
  if ($faultid) {
    my $f = OMP::FaultServer->getFault($faultid);
    titlebar($q, ["File Fault", "Fault $faultid has been filed"], %cookie);

    fault_table($q, $f);
  }
}

=item B<fault_table>

Put a fault into a an HTML table

  fault_table($cgi, $fault);

Takes an C<OMP::Fault> object as the last argument.

=cut

sub fault_table {
  my $q = shift;
  my $fault = shift;

  my $subject;
  ($fault->subject) and $subject = $fault->subject
    or $subject = "none";

  my $faultdate;
  ($fault->faultdate) and $faultdate = $fault->faultdate
    or $faultdate = "unknown";

  my $urgencyhtml;
  ($fault->isUrgent) and $urgencyhtml = "<b><font color=#d10000>THIS FAULT IS URGENT</font></b>";

  my $statushtml = ($fault->isOpen ?
		    "<b><font color=#008b24>Open</font></b>" :
		    "<b><font color=#a00c0c>Closed</font></b>");

  # First show the fault info
  print "<div class='black'>";
  print "<table width=$TABLEWIDTH bgcolor=#6161aa cellspacing=1 cellpadding=0 border=0><td><b>Report by: </b>" . $fault->author->html . "</td>";
  print "<tr><td>";
  print "<table cellpadding=3 cellspacing=0 border=0 width=100%>";
  print "<tr bgcolor=#ffffff><td><b>Date filed: </b>" . $fault->date . "</td><td><b>System: </b>" . $fault->systemText . "</td>";
  print "<tr bgcolor=#ffffff><td><b>Loss: </b>" . $fault->timelost . " hours</td><td><b>Fault type: </b>" . $fault->typeText . "</td>";
  print "<tr bgcolor=#ffffff><td><b>Actual time of failure: </b>$faultdate</td><td><b>Status: </b>$statushtml</td>";

  # Display links to projects associated with this fault if any
  my @projects = $fault->projects;

  if ($projects[0]) {
    my @html = map {"<a href='feedback.pl?urlprojid=$_'>$_</a>"} @projects;
    print "<tr bgcolor=#ffffff><td colspan=2><b>Projects associated with this fault: </b>";
    print join(', ',@html);
    print "</td>";
  }

  print "<tr bgcolor=#ffffff><td>$urgencyhtml</td><td></td>";

  # Then loop through and display each response
  my @responses = $fault->responses;
  for my $resp (@responses) {

    # Make the cell bgcolor darker and dont show "Response by:" and "Date:" if the
    # response is the original fault
    my $bgcolor;
    if ($resp->isfault) {
      $bgcolor = '#bcbce2';
    } else {
      $bgcolor = '#dcdcf2';
      print "<tr bgcolor=$bgcolor><td><b>Response by: </b>" . $resp->author->html . "</td><td><b>Date: </b>" . $resp->date . "</td>";
    }

    # Show the response
    print "<tr bgcolor=$bgcolor><td colspan=2><table border=0><tr><td><font color=$bgcolor>___</font></td><td>" . $resp->text . "</td></table><br></td>";

  }
  print "</table>";
  print "</td></table>";
  print "</div>";
}

=item B<query_fault>

Create a page for querying faults

  query_fault($cgi);

=cut

sub query_fault_content {
  my $q = shift;
  my %cookie = @_;

  titlebar($q, ["View Faults"], %cookie);

  query_fault_form($q, %cookie);
  print "<p>";

  # Display recent faults
  my $t = gmtime;
  my $xml = "<FaultQuery><category>$cookie{category}</category><date delta='-36' units='hours'>" . $t->datetime . "</date><isfault>1</isfault></FaultQuery>";

  my $faults;
  try {
    $faults = OMP::FaultServer->queryFaults($xml, "object");
    return $faults;
  } otherwise {
    my $E = shift;
    print "$E";
  };

  if ($faults->[0]) {
    show_faults($q, $faults, "viewfault.pl");

    # Put up the query form again if there are lots of faults displayed
    if ($faults->[15]) {
      print "<P>";
      query_fault_form($q, %cookie);
    }
  }
}

=item B<query_fault_output>

Display output of fault query

  query_fault_output($cgi);

=cut

sub query_fault_output {
  my $q = shift;
  my %cookie = @_;

  # Which XML query are we going to use?
  # and which title are we displaying?
  my $title;
  my $t = gmtime;
  my $delta;
  my $xml;

  # The 'Submit' submit button was clicked
  if ($q->param('Submit')) {
    $delta = $q->param('days');
    my @xml;

    push (@xml, "<category>$cookie{category}</category>");

    if ($q->param('system') !~ /any/) {
      my $system = $q->param('system');
      push (@xml, "<system>$system</system>");
    }

    if ($q->param('type') !~ /any/) {
      my $type = $q->param('type');
      push (@xml, "<type>$type</type>");
    }

    if ($q->param('search') =~ /response/) {
      push (@xml, "<isfault>0</isfault>");
      $title = "Displaying faults responded to in the last $delta days";
    } elsif ($q->param('search') =~ /file/) {
      push (@xml, "<isfault>1</isfault>");
      $title = "Displaying faults filed in the last $delta days";
    } else {
      $title = "Displaying faults with any activity in the last $delta days";
    }
    $xml = "<FaultQuery><date delta='-$delta'><category>$cookie{category}</category>" . $t->datetime . "</date>" . join('',@xml) . "</FaultQuery>";

  } else {
    # One of the other submit buttons was clicked
    if ($q->param('Major faults')) {
      # Faults within the last 14 days with 2 or more hours lost
      $xml = "<FaultQuery><category>$cookie{category}</category><date delta='-14'>" . $t->datetime . "</date><timelost><min>2</min></timelost></FaultQuery>";
      $title = "Displaying major faults";
    } elsif ($q->param('Recent faults')) {
      # Faults filed in the last 36 hours
      $xml = "<FaultQuery><category>$cookie{category}</category><date delta='-36' units='hours'>" . $t->datetime . "</date><isfault>1</isfault></FaultQuery>";
      $title = "Displaying recent faults";
    } elsif ($q->param('Current faults')) {
      # Faults within the last 14 days that are 'OPEN'
      my %status = OMP::Fault->faultStatus;
      $xml = "<FaultQuery><category>$cookie{category}</category><date delta='-14'>" . $t->datetime . "</date><status>$status{OPEN}</status></FaultQuery>";
      $title = "Displaying current faults";
    }
  }

  my $faults;
  try {
    $faults = OMP::FaultServer->queryFaults($xml, "object");
    return $faults;
  } otherwise {
    my $E = shift;
    print "$E";
  };

  titlebar($q, ["View Faults", $title], %cookie);

  query_fault_form($q, %cookie);
  print "<p>";

  if ($faults->[0]) {
    show_faults($q, $faults, "viewfault.pl");

    # Put up the query form again if there are lots of faults displayed
    if ($faults->[15]) {
      print "<P>";
      query_fault_form($q, %cookie);
    }
  }
}

=item B<query_faults>

Do a fault query and return a reference to an array of fault objects

  query_faults([$days]);

Optional argument is the number of days delta to return faults for.

=cut

sub query_faults {
  my $days = shift;
  my $xml;

  if ($days) {
    my $t = gmtime;
    $xml = "<FaultQuery><date delta='$days'>" . $t->ymd . "</date></FaultQuery>";
  } else {
    $xml = "<FaultQuery></FaultQuery>";
  }

  my $faults;
  try {
    $faults = OMP::FaultServer->queryFaults($xml, "object");
    return $faults;
  } otherwise {
    my $E = shift;
    print "$E";
  };
}

=item B<query_fault_form>

Create a form for querying faults

  query_fault_form($cgi);

=cut

sub query_fault_form {
  my $q = shift;
  my %cookie = @_;

  my $systems = OMP::Fault->faultSystems($cookie{category});
  my @systems = values %$systems;
  unshift( @systems, "any" );
  my %syslabels = map {$systems->{$_}, $_} %$systems;
  $syslabels{any} = 'Any';

  my $types = OMP::Fault->faultTypes($cookie{category});
  my @types = values %$types;
  unshift( @types, "any");
  my %typelabels = map {$types->{$_}, $_} %$types;
  $typelabels{any} = 'Any';

  print "<table cellspacing=0 cellpadding=3 border=0 bgcolor=#dcdcf2><tr><td>";
  print $q->startform;
  print "<b>Display faults for the last ";
  print $q->textfield(-name=>'days',
		      -size=>3,
		      -maxlength=>5);
  print " days</b></td><td></td><tr><td><b>";
  print "System </b>";
  print $q->popup_menu(-name=>'system',
		       -values=>\@systems,
		       -labels=>\%syslabels,
		       -default=>'any',);
  print "<b>Type </b>";
  print $q->popup_menu(-name=>'type',
		       -values=>\@types,
		       -labels=>\%typelabels,
		       -default=>'any',);
  print "</td><tr><td><b>";
  print $q->radio_group(-name=>'search',
		        -values=>['response','file','activity'],
		        -default=>'activity',
		        -labels=>{response=>"Responded to",
				  file=>"Filed",
				  activity=>"With any activity"});

  print "</b></td><td valign=bottom>";

  # Need the show_output hidden field in order for the form to be processed
  print $q->hidden(-name=>'show_output', -default=>['true']);

  print $q->submit(-name=>"Submit");
  print "</td><tr><td colspan=2 bgcolor=#babadd><p><p><b>Or display </b>";
  print $q->submit(-name=>"Major faults");
  print $q->submit(-name=>"Recent faults");
  print $q->submit(-name=>"Current faults");
  print $q->endform;
  print "</td></table>";
}

=item B<view_fault_content>

Show a fault

  view_fault_content($cgi);

=cut

sub view_fault_content {
  my $q = shift;
  my %cookie = @_;

  # First try and get the fault ID from the URL param list, then try the normal param list.
  my $faultid = $q->url_param('id');
  (!$faultid) and $faultid = $q->param('id');

  # If we still havent gotten the fault ID, put up a form and ask for it
  if (!$faultid) {
    print $q->h2("View a fault");
    print "<table border=0><tr><td>";
    print $q->startform;
    print "<b>Enter a fault ID: </b></td><td>";
    print $q->textfield(-name=>'id',
		        -size=>15,
		        -maxlength=>32);
    print "</td><tr><td colspan=2 align=right>";
    print $q->submit(-name=>'Submit');
    print $q->endform;
    print "</td></table>";
  } else {
    # Got the fault ID, so display the fault
    my $fault = OMP::FaultServer->getFault($faultid);

    titlebar($q, ["View Fault ID: $faultid", $fault->subject], %cookie);

    fault_table($q, $fault);
    close_fault_form($q, $faultid)
      if ($fault->isOpen);

    print "<p><b><font size=+1>Respond to this fault</font></b>";
    response_form($q, $fault->id, %cookie);
  }
}

=item B<view_fault_output>

Process the view_fault_content "respond" and "close fault" forms

  view_fault_output($cgi);

=cut

sub view_fault_output {
  my $q = shift;
  my %cookie = @_;

  my $title;

  my $faultid = $q->param('faultid');
  my $fault = OMP::FaultServer->getFault($faultid);

  if ($q->param('respond')) {
    my $author = $q->param('user');
    my $text = $q->param('text');

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
  } elsif ($q->param('close')) {
    try {
      OMP::FaultServer->closeFault($faultid);
      $title = "Fault $faultid has been closed";
    } otherwise {
      my $E = shift;
      $title = "An error has prevented the fault from being closed: $E";
    };
  }

  $fault = OMP::FaultServer->getFault($faultid);

  titlebar($q, ["View Fault ID: $faultid", $title], %cookie);

  fault_table($q, $fault);
  close_fault_form($q, $faultid)
    if ($fault->isOpen);
}

=item B<close_fault_form>

Create a form with a button for closing a fault

  close_fault_form($cgi, $faultid);

=cut

sub close_fault_form {
  my $q = shift;
  my $faultid = shift;

  print "<table border=0 width=$TABLEWIDTH bgcolor=#6161aa>";
  print "<tr><td align=right>";
  print $q->startform;
  print $q->hidden(-name=>'show_output', -default=>'true');
  print $q->hidden(-name=>'faultid', -default=>$faultid);
  print $q->submit(-name=>'close',
		   -label=>'Close Fault',);
  print $q->endform;
  print "</td></table>";
}

=item B<response_form>

Create a form for submitting a response

  response_form($cgi, $faultid, %cookie);

=cut

sub response_form {
  my $q = shift;
  my $faultid = shift;
  my %cookie = @_;

  print "<table border=0><tr><td align=right><b>User: </b></td><td>";
  print $q->startform;
  print $q->hidden(-name=>'show_output', -default=>['true']);
  print $q->hidden(-name=>'faultid', -default=>$faultid);
  print $q->textfield(-name=>'user',
		      -size=>'25',
		      -maxlength=>'75',
		      -default=>$cookie{user},);
  print "</td><tr><td></td><td>";
  print $q->textarea(-name=>'text',
		     -rows=>20,
		     -columns=>72);
  print "</td><tr><td colspan=2 align=right>";
  print $q->submit(-name=>'respond',
		   -label=>'Submit Response');
  print $q->endform;
  print "</td></table>";
}

=item B<respond_fault_content>

Create a form for responding to a fault

  respond_fault_content($cgi);

=cut

sub respond_fault_content {
  my $q = shift;
  my $faultid = $q->url_param('id');
}

=item B<show_faults>

Show a list of faults

  show_faults($cgi, $faults, $url);

Takes a reference to an array of fault objects as the second argument. Optional third
argument is a URL for the links.

=cut

sub show_faults {
  my $q = shift;
  my $faults = shift;
  my $url = shift;

  # Use the current URL for links if it hasnt been provided as an argument
  $url = $q->url
    if (! $url);

  print "<table width=$TABLEWIDTH cellspacing=0>";
  print "<tr><td><b>ID</b></td><td><b>Subject</b></td><td><b>Filed by</b></td><td><b>System</b></td><td><b>Type</b></td><td><b>Status</b></td><td></td>";
  my $colorcount;
  for my $fault (@$faults) {
    my $bgcolor;

    # Alternate background color for the rows and make the background color
    # red if the fault is urgent.
    $colorcount++;
    if ($colorcount == 1) {
      $bgcolor = ($fault->isUrgent ? '#c44646' : '#6161aa'); # darker
    } else {
      $bgcolor = ($fault->isUrgent ? '#c44646' : '#8080cc'); # lighter
      $colorcount = 0;
    }

    my $faultid = $fault->id;
    my $user = $fault->author;
    my $system = $fault->systemText;
    my $type = $fault->typeText;
    my $subject = $fault->subject;
    (!$subject) and $subject = "[no subject]";

    my $status = ($fault->isOpen ? "Open" : "Closed");
    ($fault->isNew and $status eq "Open") and $status = "New";

    print "<tr bgcolor=$bgcolor><td>$faultid</td>";
    print "<td><b><a href='$url?id=$faultid'>$subject &nbsp;</a></b></td>";
    print "<td>" . $user->html . "</td>";
    print "<td>$system</td>";
    print "<td>$type</td>";
    print "<td>$status</td>";
    print "<td><b><a href='$url?id=$faultid'>[View/Respond]</a></b></td>";
  }

  print "</table>";
}

=item B<titlebar>

Create a title heading that identifies the current page

  titlebar($q, \@title, %cookie);

Second argument should be an array reference containing the titlebar elements.

=cut

sub titlebar {
  my $q = shift;
  my $title = shift;
  my %cookie = @_;

  print "<table width=$TABLEWIDTH><tr bgcolor=#babadd><td><font size=+1><b>$cookie{category} Faults:&nbsp;&nbsp;@$title->[0]</font></td>";
  print "<tr><td><font size=+2><b>@$title->[1]</b></font></td>"
    if (@$title->[1]);
  print "</table><br>";
}

=item B<sidebar_summary>

A summary of the fault system formatted for display in the sidebar

  sidebar_summary($cgi);

=cut

sub sidebar_summary {
  my $q = shift;

  return "faults: ";
}

=back

=head1 AUTHOR

Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>,

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
