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
use Date::Manip;
use Text::Wrap;

use OMP::CGI;
use OMP::CGIHelper;
use OMP::Fault;
use OMP::FaultServer;
use OMP::Fault::Response;
use OMP::MSBServer;
use OMP::User;
use OMP::UserServer;
use OMP::KeyServer;
use OMP::Error qw(:try);

use vars qw/@ISA %EXPORT_TAGS @EXPORT_OK/;

require Exporter;

$| = 1;

@ISA = qw/Exporter/;

@EXPORT_OK = (qw/file_fault file_fault_output query_fault_content query_fault_output view_fault_content view_fault_output sidebar_summary fault_table response_form show_faults update_fault_content update_fault_output sql_match_string/);

%EXPORT_TAGS = (
		'all' =>[ @EXPORT_OK ],
	       );

Exporter::export_tags(qw/ all /);

# Width for HTML tables
our $TABLEWIDTH = 620;

# Text wrap column size
$Text::Wrap::columns = 80;

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

  # Get a new key for this form
  my $formkey = OMP::KeyServer->genKey;

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

  # Embed the key
  print $q->hidden(-name=>'formkey',
		   -default=>$formkey);

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

  # If we're using the bug report system don't
  # provide fields for taking "time lost" and "time of fault"
  if ($cookie{category} !~ /bug/i) {
    print "</td><tr><td align=right><b>Time lost (hours):</b></td><td>";
    print $q->textfield(-name=>'loss',
			-default=>'0',
			-size=>'4',
			-maxlength=>'10',);
    print "</td><tr><td align=right valign=top><b>Time of fault:</td><td>";
    print $q->textfield(-name=>'time',
			-size=>20,
			-maxlength=>128,);
    print "<b>";
    print $q->radio_group(-name=>'tz',
			  -values=>['UT','HST'],
			  -default=>'UT',);
    # print "</b><br><font size=-1>(YYYY-MM-DDTHH:MM or HH:MM)</font><b>";
  }

  print "</b>";
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

  # Get the form key
  my $formkey = $q->param('formkey');

  # Croak if key is invalid
  my $verifykey = OMP::KeyServer->verifyKey($formkey);
  croak "Key is invalid [perhaps you already submitted this form?]"
    unless ($verifykey);

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

  # If the time of fault was provided use it otherwise
  # do nothing
  my $t;
  if ($q->param('time')) {
    my $format = "%Y-%m-%dT%H:%M";
    my $time = $q->param('time');

    if ($time =~ /^(\d\d*?)\W*(\d{2})$/) {
      # Just the time (something like HH:MM)
      my $hh = $1;
      my $mm = $2;
      if ($q->param('tz') =~ /HST/) {
	# Time is local
	my $date = localtime;
	$t = Time::Piece->strptime($date->ymd . "T$hh:$mm", $format);

	# Convert to UT
	$t -= $t->tzoffset;
      } else {

	# Time is already UT
	my $date = gmtime;
	$t = Time::Piece->strptime($date->ymd . "T$hh:$mm", $format);
      }

    } else {
      # It is the entire date
      my $date = UnixDate($time,$format);
      $t = Time::Piece->strptime($date,$format);

      # Convert time to UT if it was given as HST
      ($q->param('tz') =~ /HST/) and $t -= $t->tzoffset;
    }

    # Subtract a day if date is in the future.
    my $gmtime = gmtime;
    ($gmtime < $t) and $t -= 86400;
  }

  my $author = $q->param('user');
  my $user = OMP::UserServer->getUser($author);

  # The text.  Put it in <pre> tags if there isn't an <html>
  # tag present
  my $text = $q->param('message');
  if ($text =~ /<html>/i) {

    # Strip out the <html> and </html> tags
    $text =~ s!</*html>!!ig;
  } else {
    $text = preify_text($text);
  }

  my $resp = new OMP::Fault::Response(author=>$user,
				      text=>$text,);

  # Create the fault object
  my $fault = new OMP::Fault(category=>$cookie{category},
			     subject=>$q->param('subject'),
			     system=>$q->param('system'),
			     type=>$q->param('type'),
			     urgency=>$urgency,
			     fault=>$resp);

  if (%projects) {
    $fault->projects([keys %projects]);
  }

  ($t) and $fault->faultdate($t);

  # Should convert this to a Time::Seconds object
  ($q->param('loss')) and $fault->timelost($q->param('loss'));

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

    # Remove the key
    OMP::KeyServer->removeKey($formkey);

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

  # Get the Private and Public cgi-bin URLs
  my $cgi = new OMP::CGI;
  my $public_url = $cgi->public_url;
  my $private_url = $cgi->private_url;

  my $subject;
  ($fault->subject) and $subject = $fault->subject
    or $subject = "none";

  my $faultdate;
  ($fault->faultdate) and $faultdate = $fault->faultdate
    or $faultdate = "unknown";

  my $urgencyhtml;
  ($fault->isUrgent) and $urgencyhtml = "<b><font color=#d10000>THIS FAULT IS URGENT</font></b>";

  my $status = $fault->statusText;
  my $statushtml = ($fault->isOpen ?
		    "<b><font color=#a00c0c>$status</font></b>" :
		    "<b><font color=#008b24>$status</font></b>");

  # First show the fault info
  print "<div class='black'>";
  print "<table width=$TABLEWIDTH bgcolor=#6161aa cellspacing=1 cellpadding=0 border=0><td><b>Report by: </b>" . $fault->author->html . "</td>";
  print "<tr><td>";
  print "<table cellpadding=3 cellspacing=0 border=0 width=100%>";
  print "<tr bgcolor=#ffffff><td><b>Date filed: </b>" . $fault->filedate . "</td><td><b>System: </b>" . $fault->systemText . "</td>";
  print "<tr bgcolor=#ffffff><td><b>Loss: </b>" . $fault->timelost . " hours</td><td><b>Fault type: </b>" . $fault->typeText . "</td>";
  print "<tr bgcolor=#ffffff><td><b>Actual time of failure: </b>$faultdate</td><td><b>Status: </b>$statushtml</td>";

  # Display links to projects associated with this fault if any
  my @projects = $fault->projects;

  if ($projects[0]) {
    my @html = map {"<a href='$public_url/projecthome.pl?urlprojid=$_'>$_</a>"} @projects;
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

    # Word wrap the text if it is in a pre block
    my $text = $resp->text;
    if ($text =~ m!^<pre>.*?</pre>$!is) {
      $text = wrap('', '', $text);
    }

    # Now turn fault IDs into links
    $text =~ s!([21][90][90]\d[01]\d[0-3]\d\.\d{3})!<a href='$public_url/viewfault.pl?id=$1'>$1</a>!g;

    print "<tr bgcolor=$bgcolor><td colspan=2><table border=0><tr><td><font color=$bgcolor>___</font></td><td>" . $text . "</td></table><br></td>";

  }
  print "</table>";
  print "</td></table>";
  print "</div>";
}

=item B<query_fault_content>

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

    # No recent faults, get current faults instead
    if (!$faults->[0]) {
      my %status = OMP::Fault->faultStatus;
      $xml = "<FaultQuery><category>$cookie{category}</category><date delta='-14'>" . $t->datetime . "</date><status>$status{Open}</status></FaultQuery>";
      $faults = OMP::FaultServer->queryFaults($xml, "object");
    }

    return $faults;
  } otherwise {
    my $E = shift;
    print "$E";
  };

  if ($faults->[0]) {
    # Make the link to the report viewing script if we're using
    # the report system
    if ($cookie{category} =~ /bug/i) {
      show_faults($q, $faults, "viewreport.pl");
    } else {
      show_faults($q, $faults, "viewfault.pl");
    }

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
  if ($q->param('Search')) {
    my @xml;


    # Make sure users of the bug reporting system can't
    # view faults for another category
    my $category;
    if ($cookie{category} =~ /bug/i) {
      $category = "BUG";
    } else {
      $category = $q->param('cat');
    }
    push (@xml, "<category>$category</category>");

    if ($q->param('system') !~ /any/) {
      my $system = $q->param('system');
      push (@xml, "<system>$system</system>");
    }

    if ($q->param('type') !~ /any/) {
      my $type = $q->param('type');
      push (@xml, "<type>$type</type>");
    }

    if ($q->param('status') !~ /any/) {
      my $status = $q->param('status');
      push (@xml, "<status>$status</status>");
    }

    if ($q->param('author')) {
      my $author = uc($q->param('author'));
      push (@xml, "<author>$author</author>");
    }

    $delta = $q->param('days');
    push (@xml, "<date delta='-$delta'>" . $t->datetime . "</date>")
      if ($delta);

    my $text = $q->param('text');
    if ($text) {
      $text = sql_match_string($text);
      push (@xml, "<text>$text</text>");	
    }

    if ($q->param('action') =~ /response/) {
      push (@xml, "<isfault>0</isfault>");
      $title = "Displaying faults responded to in the last $delta days";
    } elsif ($q->param('action') =~ /file/) {
      push (@xml, "<isfault>1</isfault>");
      $title = "Displaying faults filed in the last $delta days";
    } else {
      $title = "Displaying faults with any activity in the last $delta days";
    }
    $xml = "<FaultQuery><category>$cookie{category}</category>" . join('',@xml) . "</FaultQuery>";

  } else {
    # One of the other submit buttons was clicked
    if ($q->param('Major faults') or $q->param('Major reports')) {
      # Faults within the last 14 days with 2 or more hours lost
      $xml = "<FaultQuery><category>$cookie{category}</category><date delta='-14'>" . $t->datetime . "</date><timelost><min>2</min></timelost></FaultQuery>";
      $title = "Displaying major faults";
    } elsif ($q->param('recent')) {
      # Faults filed in the last 36 hours
      $xml = "<FaultQuery><category>$cookie{category}</category><date delta='-36' units='hours'>" . $t->datetime . "</date><isfault>1</isfault></FaultQuery>";
      $title = "Displaying recent faults";
    } elsif ($q->param('current')) {
      # Faults within the last 14 days that are 'OPEN'
      my %status = OMP::Fault->faultStatus;
      $xml = "<FaultQuery><category>$cookie{category}</category><date delta='-14'>" . $t->datetime . "</date><status>$status{Open}</status></FaultQuery>";
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
    # Make the link to the report viewing script if we're using
    # the report system
    if ($cookie{category} =~ /bug/i) {
      show_faults($q, $faults, "viewreport.pl");
    } else {
      show_faults($q, $faults, "viewfault.pl");
    }

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

  # If this is a report problems script use the word reports instead of faults
  my $word;
  my $script = $q->url(-relative=>1);
  ($script =~ /report/) and $word = "reports"
    or $word = "faults";

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

  my %status = OMP::Fault->faultStatus($cookie{category});
  my @status = values %status;
  unshift( @status, "any");
  my %statuslabels = map {$status{$_}, $_} %status;
  $statuslabels{any} = 'Any';

  print "<table cellspacing=0 cellpadding=3 border=0 bgcolor=#dcdcf2><tr><td>";
  print $q->startform(-method=>'GET');
  print "<b>Display $word for the last ";
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
  print "</td><tr><td><b>Status </b>";
  print $q->popup_menu(-name=>'status',
		       -values=>\@status,
		       -labels=>\%statuslabels,
		       -default=>'any',);
  print "</td><tr><td><b>User ID </b>";
  print $q->textfield(-name=>'author',
		      -size=>22,
		      -maxlength=>50,);
  print "</td><tr><td><b>";
  print $q->radio_group(-name=>'action',
		        -values=>['response','file','activity'],
		        -default=>'activity',
		        -labels=>{response=>"Responded to",
				  file=>"Filed",
				  activity=>"With any activity"});

  print "</b></td><tr><td>";
  print $q->textfield(-name=>'text',
		      -size=>44,
		      -maxlength=>256,);
  print "&nbsp;&nbsp;";
  print $q->submit(-name=>"Search");
  print "</b></td><td valign=bottom align=left>";

  # Need the show_output hidden field in order for the form to be processed
  print $q->hidden(-name=>'show_output', -default=>['true']);
  print $q->hidden(-name=>'cat', -default=>$cookie{category});
  print "</td><tr><td colspan=2 bgcolor=#babadd><p><p><b>Or display </b>";
  print $q->submit(-name=>"Major $word");
  print $q->submit(-name=>"recent", -label=>"Recent $word (2 days)");
  print $q->submit(-name=>"current", -label=>"Current $word (14 days)");
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

    # If the user is "logged in" to the report problem system
    # make sure they can only see problem reports and not faults
    # for other categories.
    if ($cookie{category} =~ /bug/i and $fault->category ne "BUG") {
      print "[$faultid] is not a problem report.";
      return;
    }

    titlebar($q, ["View Fault: $faultid", $fault->subject], %cookie);
    fault_table($q, $fault);
    change_status_form($q, $faultid);

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
    # Get the form key
    my $formkey = $q->param('formkey');

    # Croak if key is invalid
    my $verifykey = OMP::KeyServer->verifyKey($formkey);
    croak "Key is invalid [perhaps you already submitted this form?]"
      unless ($verifykey);

    my $author = $q->param('user');

    # The text.  Put it in <pre> tags if there isn't an <html>
    # tag present
    my $text = $q->param('text');
    if ($text =~ /<html>/i) {

      # Strip out the <html> and </html> tags
      $text =~ s!</*html>!!ig;
    } else {
      $text = preify_text($text);
    }

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

    # Remove key
    OMP::KeyServer->removeKey($formkey);

  } elsif ($q->param('change_status')) {
    try {
      # Right now we'll just do an update by resubmitting the fault
      # with the new status parameter.  But in principal we should
      # have a method for doing an explicit status update.

      # Change the status parameter
      $fault->status($q->param('status'));

      # Resubmit the fault
      OMP::FaultServer->updateFault($fault);

      $title = "Status for fault $faultid has been updated.";
    } otherwise {
      my $E = shift;
      $title = "An error has prevented the fault status from being updated: $E";
    };
  }

  $fault = OMP::FaultServer->getFault($faultid);

  titlebar($q, ["View Fault ID: $faultid", $title], %cookie);

  fault_table($q, $fault);
  change_status_form($q, $faultid);
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

=item B<change_status_form>

Provide a form for changing the status of a fault.

  change_status_form($cgi, $faultid);

=cut

sub change_status_form {
  my $q = shift;
  my $faultid = shift;

  # Get available statuses
  my %status = OMP::Fault->faultStatus();
  my %labels = map {$status{$_}, $_} %status; # pop-up menu labels

  print "<table border=0 width=$TABLEWIDTH bgcolor=#6161aa>";
  print "<tr><td align=right>";
  print $q->startform;
  print $q->hidden(-name=>'show_output', -default=>'true');
  print $q->hidden(-name=>'faultid', -default=>$faultid);
  print $q->popup_menu(-name=>'status',
		       -values=>[values %status],
		       -labels=>\%labels,);
  print " ";
  print $q->submit(-name=>'change_status',
		   -label=>'Change status',);
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

  # Get a new key for this form
  my $formkey = OMP::KeyServer->genKey;

  print "<table border=0><tr><td align=right><b>User: </b></td><td>";
  print $q->startform;
  # Embed the key
  print $q->hidden(-name=>'formkey',
		   -default=>$formkey);
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

=item B<update_fault_content>

Create a form for updating fault details

  update_fault_content($cgi);

=cut

sub update_fault_content {
  my $q = shift;
  my $faultid = $q->url_param('id');
  my %cookie = @_;

  # Try to get the fault ID from the URL first.
  # If we didn't get it, try and get it from our form
  (! $faultid) and $faultid = $q->param('id');

  # Still didn't get the fault ID so put this form up
  if (!$faultid) {
    print $q->h2("Update a fault");
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
    # Get the fault
    my $fault = OMP::FaultServer->getFault($faultid);

    # Form for taking new details.  Displays current values.
    print $q->h2("Update fault details: $faultid");
    print "<table><tr><td><b>Time lost (". $fault->timelost ."):</b> </td><td>";
    print $q->startform;
    print $q->hidden(-name=>'show_output', -default=>['true']);
    print $q->hidden(-name=>'faultid', -default=>$faultid);
    print $q->textfield(-name=>'timelost',
			-size=>4,
			-maxlength=>8);
    print $q->endform;
    print "</td></table>";
  }
}

=item B<update_fault_output>

Take parameters from the fault update content page and update
the fault.

  update_fault_output($cgi);

=cut

sub update_fault_output {
  my $q = shift;
  my %cookie = @_;

  my $faultid = $q->param('faultid');

  # Get the fault
  my $fault = OMP::FaultServer->getFault($faultid);

  # Change timelost
  if ($q->param('timelost')) {
    # Convert to Time::Seconds object

    $fault->timelost($q->param('timelost'));
  }

  # Now do the update
  OMP::FaultServer->updateFault($fault);

  $fault = OMP::FaultServer->getFault($faultid);

  print $q->h2("Fault $faultid has been updated");

  # Display the fault in it's new form
  fault_table($q, $fault);
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

    my $status = $fault->statusText;
    ($fault->isNew and $fault->isOpen) and $status = "New";

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
Note:  The title displayed in the titlebar depends on the name of the cgi
script.  If the cgi script has the word "report" in it then it is assumed
that the "Report Problems" system is being used and the title is set accordingly.
Also, any occurance of the string "fault" is replaced with "report."

=cut

sub titlebar {
  my $q = shift;
  my $title = shift;
  my %cookie = @_;

  # We'll check the URL to determine if we're in the report problem or the
  # fault system and set the titlebar accordingly
  my $script = $q->url(-relative=>1);

  my $toptitle;
  if ($script =~ /report/) {
    $toptitle = "Report Problems";

    # Replace the word "fault" with "report"
    $title->[0] =~ s/fault/report/ig;
  } else {
    $toptitle = "$cookie{category} Faults";
  }

  print "<table width=$TABLEWIDTH><tr bgcolor=#babadd><td><font size=+1><b>$toptitle:&nbsp;&nbsp;@$title->[0]</font></td>";
  print "<tr><td><font size=+2><b>@$title->[1]</b></font></td>"
    if (@$title->[1]);
  print "</table><br>";
}

=item B<sql_match_string>

Return a string that can be used for case-insensitive pattern matching in
an SQL statement (i.e.: "Cow" becomes "[Cc][Oo][Ww]").

  $newstring = sql_match_string($string);

=cut

sub sql_match_string {
  my $string = shift;

  # In this regexp \U begins the uppercase, \E ends it and \L starts
  # the lowercase
  $string =~ s/([A-Za-z])/\[\U$1\E\L$1\]/g;

  return $string;
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
