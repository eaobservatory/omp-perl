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
use Time::Seconds;
use Date::Manip;
use Text::Wrap;

use OMP::CGI;
use OMP::CGIHelper;
use OMP::Config;
use OMP::General;
use OMP::Fault;
use OMP::FaultUtil;
use OMP::FaultStats;
use OMP::Display;
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

@EXPORT_OK = (qw/file_fault file_fault_output query_fault_content query_fault_output view_fault_content view_fault_output fault_table response_form show_faults update_fault_content update_fault_output update_resp_content update_resp_output fault_summary_form fault_summary_content/);

%EXPORT_TAGS = (
		'all' =>[ @EXPORT_OK ],
	       );

Exporter::export_tags(qw/ all /);

# Width for HTML tables
our $TABLEWIDTH = '100%';

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

  titlebar($q, ["File Fault"], %cookie);
  file_fault_form(cgi => $q,
		  cookie => \%cookie,);
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

  # Make sure all the necessary params were provided
  my %params = (User => "user",
		Subject => "subject",
	        "Fault report" => "message",
	        Type => "type",
	        System => "system",);
  my @error;
  for (keys %params) {
    if (length($q->param($params{$_})) < 1) {
      push @error, $_;
    }
  }

  # Put the form back up if params are missing
  my @title;
  if ($error[0]) {
    push @title, "The following fields were not filled in:";
    titlebar($q, ["File Fault", join('<br>',@title)], %cookie);
    print "<ul>";
    print map {"<li>$_"} @error;
    print "</ul>";
    file_fault_form(cgi => $q,
		    cookie => \%cookie,);
    return;
  }

  # Make sure user is valid
  my $user = OMP::UserServer->getUser($q->param('user'));
  if (! $user) {
    push @title, "The user ID you entered does not exist.  Please enter another and submit again";
    titlebar($q ,["File Fault", join('<br>',@title)], %cookie);
    file_fault_form(cgi => $q,
		    cookie => \%cookie,);
  }

  my %status = OMP::Fault->faultStatus;

  # Get the fault details
  my %faultdetails = parse_file_fault_form($q);

  my $resp = new OMP::Fault::Response(author=>$faultdetails{author},
				      text=>$faultdetails{text},);

  # Create the fault object
  my $fault = new OMP::Fault(category=>$cookie{category},
			     subject=>$faultdetails{subject},
			     system=>$faultdetails{system},
			     type=>$faultdetails{type},
			     status=>$faultdetails{status},
			     urgency=>$faultdetails{urgency},
			     fault=>$resp);

  # The following are not always present
  ($faultdetails{projects}) and $fault->projects($faultdetails{projects});

  ($faultdetails{faultdate}) and $fault->faultdate($faultdetails{faultdate});

  ($faultdetails{timelost}) and $fault->timelost($faultdetails{timelost});

  # Submit the fault the the database
  my $faultid;
  my $E;
  try {
    $faultid = OMP::FaultServer->fileFault($fault);
  } catch OMP::Error::MailError with {
    $E = shift;
    print $q->h2("Fault has been filed, but an error has prevented it from being mailed:");
    print "$E";
  } catch OMP::Error::FatalError with {
    $E = shift;
    print $q->h2("An error has prevented the fault from being filed:");
    print "$E";
  } otherwise {
    $E = shift;
    print $q->h2("An error has occurred");
    print "$E";
  };

  # Show the fault if it was successfully filed
  if ($faultid) {

    # Remove the key
    OMP::KeyServer->removeKey($formkey);

    my $f = OMP::FaultServer->getFault($faultid);
    titlebar($q, ["File Fault", "Fault $faultid has been filed"], %cookie);

    fault_table($q, $f, 'nostatus');
  }
}

=item B<fault_table>

Put a fault into a an HTML table

  fault_table($cgi, $fault, 'noedit');

Takes an C<OMP::Fault> object as the second argument.  Takes a third argument
which is a string of either "noedit" or "nostatus".  "noedit" displays the fault without links for updating the text and details, and without the status update form.  "nostatus" displays the fault just without the status update form.

=cut

sub fault_table {
  my $q = shift;
  my $fault = shift;
  my $option = shift;

  my $nostatus;
  my $noedit;

  if ($option =~ /noedit/) {
    $noedit = 1;
  } elsif ($option =~ /nostatus/) {
    $nostatus = 1;
  }

  my $subject;
  ($fault->subject) and $subject = $fault->subject
    or $subject = "none";

  # Get file date as local time
  my $filedate = localtime($fault->filedate->epoch);
  $filedate = OMP::General->display_date($filedate);

  my $faultdate = $fault->faultdate;
  if ($faultdate) {
    # Convert fault date to local time
    my $epoch = $faultdate->epoch;
    $faultdate = localtime($epoch);
    $faultdate = OMP::General->display_date($faultdate);
  } else {
    $faultdate = "unknown";
  }

  my $urgencyhtml;
  ($fault->isUrgent) and $urgencyhtml = "<b><font color=#d10000>THIS FAULT IS URGENT</font></b>";

  # Get available statuses
  my %status = OMP::Fault->faultStatus();
  my %labels = map {$status{$_}, $_} %status; # pop-up menu labels

  # First show the fault info
  print "<div class='black'>";
  print $q->startform;
  print "<table width=$TABLEWIDTH bgcolor=#6161aa cellspacing=1 cellpadding=0 border=0><td><b class='white'>Report by: " . OMP::Display->userhtml($fault->author, $q) . "</b></td>";
  print "<tr><td>";
  print "<table cellpadding=3 cellspacing=0 border=0 width=100%>";
  print "<tr bgcolor=#ffffff><td><b>Date filed: </b>$filedate"  . "</td><td><b>System: </b>" . $fault->systemText . "</td>";
  print "<tr bgcolor=#ffffff><td><b>Loss: </b>" . $fault->timelost . " hours</td><td><b>Fault type: </b>" . $fault->typeText . "</td>";
  print "<tr bgcolor=#ffffff><td><b>Actual time of failure: </b>$faultdate</td><td><b>Status: </b>";

  unless ($noedit or $nostatus) {
    # Make a form element for changing the status
    print $q->hidden(-name=>'show_output', -default=>'true');
    print $q->hidden(-name=>'faultid', -default=>$fault->id);
    print $q->popup_menu(-name=>'status',
			 -default=>$fault->status,
			 -values=>[values %status],
			 -labels=>\%labels,);
    print " ";
    print $q->submit(-name=>'change_status',
		     -label=>'Change',);
    print $q->endform;
  } else {
    # Display only
    print $fault->statusText;
  }
  print "</td>";

  # Display links to projects associated with this fault if any
  my @projects = $fault->projects;

  if ($projects[0]) {
    my @html = map {"<a href='projecthome.pl?urlprojid=$_'>$_</a>"} @projects;
    print "<tr bgcolor=#ffffff><td colspan=2><b>Projects associated with this fault: </b>";
    print join(', ',@html);
    print "</td>";
  }

  # Display if urgent
  print "<tr bgcolor=#ffffff><td>$urgencyhtml</td><td></td>";

  # Link to fault editing page
  if (! $noedit) {
    print "<tr bgcolor=#ffffff><td> </td><td><span class='editlink'><a href='updatefault.pl?id=". $fault->id ."'>Click here to update or edit this fault</a></span></td>";
  }

  # Then loop through and display each response
  my @responses = $fault->responses;
  for my $resp (@responses) {
    # Convert response date to local time
    my $respdate = $resp->date;
    my $epoch = $respdate->epoch;
    $respdate = localtime($epoch);
    $respdate = OMP::General->display_date($respdate);

    # Make the cell bgcolor darker and dont show "Response by:" and "Date:" if the
    # response is the original fault
    my $bgcolor;
    if ($resp->isfault) {
      $bgcolor = '#bcbce2';
    } else {
      $bgcolor = '#dcdcf2';
      print "<tr bgcolor=$bgcolor><td><b>Response by: </b>" . OMP::Display->userhtml($resp->author, $q) . "</td><td><b>Date: </b>" . $respdate;

      # Link to respons editing page
      if (! $noedit) {
	print "&nbsp;&nbsp;&nbsp;&nbsp;<span class='editlink'><a href='updateresp.pl?id=".$fault->id."&respid=".$resp->id."'>Edit this response</a></span></td>";
      }
    }

    # Show the response

    # Word wrap the text if it is in a pre block
    my $text = $resp->text;
    if ($text =~ m!^<pre>.*?</pre>$!is) {
      $text = wrap('', '', $text);
    }

    # Now turn fault IDs into links
    $text =~ s!([21][90][90]\d[01]\d[0-3]\d\.\d{3})!<a href='viewfault.pl?id=$1'>$1</a>!g;

    print "<tr bgcolor=$bgcolor><td colspan=2><table border=0><tr><td><font color=$bgcolor>___</font></td><td>$text</td></table><br></td>";





  }
  print "</table>";
  print "</td></table>";
  print "</div>";
}

=item B<query_fault_output>

Display output of fault query

  query_fault_output($cgi);

=cut

sub query_fault_output {
  my $q = shift;
  my %cookie = @_;

  my $title;
  my $t = gmtime;
  my %daterange;
  my $mindate;
  my $maxdate;
  my $xml;

  # XML query to return faults from the last 14 days
  my %faultstatus = OMP::Fault->faultStatus;
  my $currentxml = "<FaultQuery>".
    "<category>$cookie{category}</category>".
      "<date delta='-14'>" . $t->datetime . "</date>".
	"</FaultQuery>";

  # Print faults if print button was clicked
  if ($q->param('print')) {
    my $printer = $q->param('printer');
    my @fprint = split(',',$q->param('faults'));

    my $separate = 0;  # Argument governs whether faults are printed combined
    if ($q->param('print_method') eq "separate") {
      $separate = 1;
    }

    OMP::FaultUtil->print_faults($printer, $separate, @fprint);

    titlebar($q, ["View Faults", "Sent faults to printer $printer"], %cookie);
    return;
  }

  if ($q->param('search')) {
    # The 'Search' submit button was clicked
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


    if ($q->param('status') ne "any") {

      my $status = $q->param('status');
      if ($status eq "all_closed") {

	# Do query on all closed statuses
	my %status = OMP::Fault->faultStatusClosed;
	push (@xml, join("",map {"<status>$status{$_}</status>"} %status));
      } elsif ($status eq "all_open") {

	# Do a query on all open statuses
	my %status = OMP::Fault->faultStatusOpen;
	push (@xml, join("",map {"<status>$status{$_}</status>"} %status));
      } else {

	# Do a query on just a single status
	my %status = OMP::Fault->faultStatus;
	push (@xml, "<status>$status</status>");
      }
    }

    if ($q->param('author')) {
      my $author = uc($q->param('author'));

      # Get the user object (this will automatically
      # map the an alias to a user ID)
      my $user = OMP::UserServer->getUser($author);

      push (@xml, "<author>".$user->userid."</author>");
    }

    # Generate the date portion of our query
    my $queryDateStr;
    if ($q->param('period') eq 'arbitrary') {
      
      # Get our min and max dates
      my $mindatestr = $q->param('mindate');
      my $maxdatestr = $q->param('maxdate');

      # Convert dates to UT
      $mindate = OMP::General->parse_date($mindatestr, 1);
      $maxdate = OMP::General->parse_date($maxdatestr, 1);

      if ($mindate and $maxdate) {
	# Imply end of day (23:59) for max date if no time was specified
	($maxdate and $maxdatestr !~ /T/) and $maxdate += ONE_DAY - 1;

	# Do a min/max date query
	if ($mindate or $maxdate) {
	  push (@xml, "<date>");
	  ($mindate) and push (@xml, "<min>" . $mindate->datetime . "</min>");
	  ($maxdate) and push (@xml, "<max>" . $maxdate->datetime . "</max>");
	  push (@xml, "</date>");
	}

	# Convert dates back to localtime
	$mindate = localtime($mindate->epoch);
	$maxdate = localtime($maxdate->epoch);
      }
    } elsif ($q->param('period') eq 'days') {
      my $days = $q->param('days');
      (! $days) and $days = 14;

      $maxdate = localtime($t->epoch);
      $mindate = localtime($maxdate->epoch - $days * ONE_DAY);

      push (@xml, "<date delta='-$days'>". $t->datetime ."</date>");
    } elsif ($q->param('period') eq 'last_month') {
      # Get results for the period between the first 
      # and last days of the last month
      my $year;
      my $month;
      if ($t->strftime("%Y%m") =~ /^(\d{4})(\d{2})$/) {
	$year = $1;
	$month = $2;
      }

      $month -= 1;
      if ($month eq 0) {
	$month = 12;
	$year -= 1;
      }

      my $tempdate = Time::Piece->strptime($year . $month . "01", "%Y%m%d");
      $mindate = gmtime($tempdate->epoch);
      my $tempdate2 = Time::Piece->strptime($year . $month . $tempdate->month_last_day . "T23:59:59", "%Y%m%dT%H:%M:%S");
      $maxdate = gmtime($tempdate2->epoch);

      push (@xml, "<date><min>".$mindate->datetime."</min><max>".$maxdate->datetime."</max></date>");

      # Convert dates to localtime
      $mindate = localtime($mindate->epoch);
      $maxdate = localtime($maxdate->epoch);
    } else {
      push (@xml, "<date delta='-7'>". $t->ymd ."</date>");
    }

    # Get the text param and unescape things like &amp; &quot;
    my $text = $q->param('text');
    if (defined $text) {
      push (@xml, "<text>$text</text>");
    }

    # Return either only faults filed or only faults responded to
    if ($q->param('action') =~ /response/) {
      push (@xml, "<isfault>0</isfault>");
    } elsif ($q->param('action') =~ /file/) {
      push (@xml, "<isfault>1</isfault>");
    }

    if ($q->param('timelost')) {
      push (@xml, "<timelost><min>.001</min></timelost>");
    }

    # Our query XML
    $xml = "<FaultQuery><category>$cookie{category}</category>" . join('',@xml) . "</FaultQuery>";

  } elsif ($q->param('major')) {
    # Faults within the last 14 days with 2 or more hours lost
    $xml = "<FaultQuery><category>$cookie{category}</category><date delta='-14'>" . $t->datetime . "</date><timelost><min>2</min></timelost></FaultQuery>";
  } elsif ($q->param('recent')) {
    # Faults active in the last 36 hours
    $xml = "<FaultQuery><category>$cookie{category}</category><date delta='-2'>" . $t->datetime . "</date></FaultQuery>";
  } elsif ($q->param('current')) {
    # Faults within the last 14 days
    $xml = $currentxml;
    $title = "Displaying faults with any activity in the last 14 days";
  } else {
    # Initial display of query page
    $xml = "<FaultQuery><category>$cookie{category}</category><date delta='-7'>" . $t->datetime . "</date></FaultQuery>";
    $title = "Displaying faults with any activity in the last 7 days";
  }

  my $faults;
  try {
    $faults = OMP::FaultServer->queryFaults($xml, "object");

    # If this is the initial display of faults and no recent faults were
    # returned, display faults for the last 14 days.
    if (! $q->param('faultsearch') and ! $faults->[0]) {
      $title = "No active faults in the last 7 days, displaying faults for the last 14 days";

      $faults = OMP::FaultServer->queryFaults($currentxml, "object");
    }

    return $faults;

  } otherwise {
    my $E = shift;
    print "$E";
  };

  # Generate a title based on the results returned
  if ($q->param('faultsearch')) {
    if ($faults->[1]) {
      $title = scalar(@$faults) . " faults returned matching your query";
    } elsif ($faults->[0]) {
      $title = "1 fault returned matching your query";
    } else {
      $title = "No faults found matching your query";
    }
  }

  # Show results as a summary if that option was checked
  if ($q->param('summary') and $faults->[0]) {
    &fault_summary_content($q, $faults, $mindate, $maxdate);
  } elsif ($faults->[0]) {
    titlebar($q, ["View Faults", $title], %cookie);

    query_fault_form($q, %cookie);
    print "<p>";

    # Total up and display time lost
    my $total_loss;
    for (@$faults) {
      $total_loss += $_->timelost;
    }

    print "<strong>Total time lost: $total_loss hours</strong>";

    print "<p>";

    # Make a link to this script with an argument to alter sort order
    if ($q->param('sort_order') eq "ascending" or $cookie{sort_order} eq "ascending") {
      my $sort_url = url_args($q, "sort_order", "ascending", "descending");
      print "Showing oldest first | <a href='$sort_url'>Show most recent first</a>";
    } else {
      my $sort_url = url_args($q, "sort_order", "descending", "ascending");
      print "<a href='$sort_url'>Show oldest first</a> | Showing most recent first";
    }
    print "<br>";

    # Link to this script with an argument to alter sort criteria
    if ($q->param('orderby') eq "filedate") {
      my $url = url_args($q, "orderby", "filedate", "response");
      print "Sorted by date filed | <a href='$url'>Sort by date of latest response</a>"
    } else {
      my $url = url_args($q, "orderby", "response", "filedate");
      print "<a href='$url'>Sort by file date</a> | Sorted by date of latest response";
    }


    print "<p>";

    my %showfaultargs = (CGI => $q,
			 faults => $faults,);
    
    if ($q->param('orderby') eq 'response' or ! $q->param('orderby')) {
      $showfaultargs{orderby} = 'response';
    } elsif ($q->param('orderby') eq 'filedate') {
      $showfaultargs{orderby} = 'filedate';
    }
    
    if ($faults->[0]) {
      unless ($q->param('sort_order') eq "ascending" or $cookie{sort_order} eq "ascending") {
	$showfaultargs{descending} = 1;
      }

      show_faults(%showfaultargs);

      # Faults to print
      my @faultids = map{$_->id} @$faults;
      
      print_form($q, 1, @faultids);
      
      # Put up the query form again if there are lots of faults displayed
      if ($faults->[15]) {
	print "<P>";
	query_fault_form($q, %cookie);
      }
    }
  } else {
    titlebar($q, ["View Faults", $title], %cookie);
    query_fault_form($q, %cookie);
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
  my @systems = map {$systems->{$_}} sort keys %$systems;
  unshift( @systems, "any" );
  my %syslabels = map {$systems->{$_}, $_} %$systems;
  $syslabels{any} = 'Any';

  my $types = OMP::Fault->faultTypes($cookie{category});
  my @types = map {$types->{$_}} sort keys %$types;
  unshift( @types, "any");
  my %typelabels = map {$types->{$_}, $_} %$types;
  $typelabels{any} = 'Any';

  my %status = OMP::Fault->faultStatus($cookie{category});
  my @status = map {$status{$_}} sort keys %status;
  unshift( @status, "any", "all_open", "all_closed");
  my %statuslabels = map {$status{$_}, $_} %status;
  $statuslabels{any} = 'Any';
  $statuslabels{all_open} = 'All open';
  $statuslabels{all_closed} = 'All closed';

  # Get the date so we can figure out our local timezone
  my $today = localtime;

  print "<table cellspacing=0 cellpadding=3 border=0 bgcolor=#dcdcf2><tr><td colspan=2>";
  print $q->startform(-method=>'GET');
  print $q->hidden(-name=>'faultsearch', -default=>['true']);

  print "<b>Find faults ";
  print $q->radio_group(-name=>'action',
		        -values=>['response','file','activity'],
		        -default=>'activity',
		        -labels=>{response=>"responded to",
				  file=>"filed",
				  activity=>"with any activity"});
  print "</td><tr><td colspan=2><b>by user <small>(ID)</small> </b>";
  print $q->textfield(-name=>'author',
		      -size=>17,
		      -maxlength=>32,);
  print "</b></td><tr><td valign=top align=right><b>";
  print $q->radio_group(-name=>'period',
		        -values=>['arbitrary','days','last_month'],
		        -default=>'arbitrary',
		        -labels=>{arbitrary=>'between dates',days=>'in the last',last_month=>'in the last calendar month'},
			-linebreak=>'true',);
  print "</b></td><td valign=top><b>";
  print "<small>(YYYYMMDD)</small> ";
  print $q->textfield(-name=>'mindate',
		      -size=>18,
		      -maxlength=>32);
  print " and ";
  print $q->textfield(-name=>'maxdate',
		      -size=>18,
		      -maxlength=>32);
  # Display the local timezone since date searches are localtime
  print " ". $today->strftime("%Z");
  print "<br>";
  print $q->textfield(-name=>'days',
		      -size=>3,
		      -maxlength=>4,);
  print " days";
  print "<br>";
  print "</b></td><tr><td colspan=2><b>";
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
  print "<b>Status </b>";
  print $q->popup_menu(-name=>'status',
		       -values=>\@status,
		       -labels=>\%statuslabels,
		       -default=>'any',);

  print "</td><tr><td colspan=2>";
  print "<b>";

  # Only display option to return time-losing faults if the category allows it
  if (OMP::Fault->faultCanLoseTime($cookie{category})) {
    print $q->checkbox(-name=>'timelost',
		       -value=>'true',
		       -label=>'Return time-losing faults only',
		       -checked=>0,);
    print "&nbsp;&nbsp;";
  }

  # Only display option to return affected projects if the category allows it
  if (OMP::Fault->faultCanAssocProjects($cookie{category})) {
    print $q->checkbox(-name=>'show_affected',
		       -value=>'true',
		       -label=>'Show affected projects',
		       -checked=>0,);
  }

  print "<br>";
  print $q->checkbox(-name=>'summary',
		     -value=>'true',
		     -label=>'Organize by system/type',
		     -checked=>0,);
  print "</b></td><tr><td colspan=2>";
  print $q->textfield(-name=>'text',
		      -size=>44,
		      -maxlength=>256,);
  print "&nbsp;&nbsp;";
  print $q->submit(-name=>"search", -label=>"Search",);
  print "</b></td>";

  # Need the show_output hidden field in order for the form to be processed
  print $q->hidden(-name=>'show_output', -default=>['true']);
  print $q->hidden(-name=>'cat', -default=>$cookie{category});
  print "<tr><td colspan=2 bgcolor=#babadd><p><p><b>Or display </b>";
  print $q->submit(-name=>"major", -label=>"Major faults");
  print $q->submit(-name=>"recent", -label=>"Recent faults (2 days)");
  print $q->submit(-name=>"current", -label=>"Current faults (14 days)");
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

  # First try and get the fault ID from the sidebar form param, then 
  # try and get it from the URL or from the regular form param
  my $faultid;
  if ($q->param('goto_fault')) {
    $faultid = $q->param('goto_fault');
  } else {
    $faultid = $q->param('id');
    (! $faultid) and $faultid = $q->url_param('id');
  }

  # If we still havent gotten the fault ID, put up a form and ask for it
  if (!$faultid) {
    view_fault_form($q);
  } else {
    # Got the fault ID, so display the fault
    my $fault = OMP::FaultServer->getFault($faultid);

    # Don't go any further if we got undef back instead of a fault
    if (! $fault) {
      print "No fault with ID of [$faultid] exists.";
      view_fault_form($q);
      return;
    }

    # Send the fault to a printer if print button was clicked
    if ($q->param('print')) {
      my $printer = $q->param('printer');
      my @fprint = split(',',$q->param('faults'));

      OMP::FaultUtil->print_faults($printer, 0, @fprint);
      titlebar($q, ["View Fault: $faultid", "Fault sent to printer $printer"], %cookie);
      return;
    }

    # If the user is "logged in" to the report problem system
    # make sure they can only see problem reports and not faults
    # for other categories.
    if ($cookie{category} =~ /bug/i and $fault->category ne "BUG") {
      print "[$faultid] is not a problem report.";
      return;
    }

    titlebar($q, ["View Fault: $faultid", $fault->subject], %cookie);
    fault_table($q, $fault);

    print "<br>";

    # Show form for printing this fault
    my @faults = ($fault->id);
    print_form($q, 0, @faults);

    # Response form
    print "<p><b><font size=+1>Respond to this fault</font></b>";
    response_form(cgi => $q,
		  cookie => \%cookie,
		  fault => $fault,);

  }
}

=item B<view_fault_output>

Process the view_fault_content "respond" and "close fault" forms

  view_fault_output($cgi);

=cut

sub view_fault_output {
  my $q = shift;
  my %cookie = @_;

  my @title;

  my $faultid = $q->param('faultid');
  my $fault = OMP::FaultServer->getFault($faultid);

  if ($q->param('respond')) {
    # Get the form key
    my $formkey = $q->param('formkey');

    # Croak if key is invalid
    my $verifykey = OMP::KeyServer->verifyKey($formkey);
    croak "Key is invalid [perhaps you already submitted this form?]"
      unless ($verifykey);

    # Make sure all the necessary params were provided
    my %params = (User => "user",
		  Response => "text",);
    my @error;
    for (keys %params) {
      if (length($q->param($params{$_})) < 1) {
	push @error, $_;
      }
    }

    # Put the form back up if params are missing
    if ($error[0]) {
      push @title, "The following fields were not filled in:";
      titlebar($q, ["View Fault ID: $faultid", join('<br>',@title)], %cookie);
      print "<ul>";
      print map {"<li>$_"} @error;
      print "</ul>";
      response_form(cgi => $q,
		    cookie => \%cookie,
		    fault => $fault,);
      fault_table($q, $fault);
      return;
    }

    # Response author
    my $user = new OMP::User(userid => $q->param('user'));

    # Get the status (possibly changed)
    my $status = $q->param('status');

    # Now update the status if necessary
    if ($status != $fault->status) {
      # Lookup table for status
      my %status = OMP::Fault->faultStatus();

      # Change status in fault object
      $fault->status($status);

      my $E;
      try {
	# Resubmit fault with new status
	OMP::FaultServer->updateFault($fault);
	push @title, "Fault status changed to \"" . $fault->statusText . "\"";
      } otherwise {
	$E = shift;
	push @title, "An error prevented the fault status from being updated: $E";
      };
	
    }

    # The text.  Put it in <pre> tags if there isn't an <html>
    # tag present
    my $text = $q->param('text');
    if ($text =~ /<html>/i) {

      # Strip out the <html> and </html> tags
      $text =~ s!</*html>!!ig;
    } else {
      $text = OMP::General->preify_text($text);
    }

    # Strip out ^M
    $text =~ s/\015//g;

    my $E;
    try {
      my $resp = new OMP::Fault::Response(author => $user,
					  text => $text);
      OMP::FaultServer->respondFault($fault->id, $resp);

      push @title, "Fault response successfully submitted";
    } otherwise {
      $E = shift;
      push @title, "An error has prevented your response from being filed: $E";

    };

    # Encountered an error, redisplay form
    if ($E) {
      titlebar($q, ["View Fault ID: $faultid", join('<br>',@title)], %cookie);
      response_form(cgi => $q,
		    cookie => \%cookie,
		    fault => $fault,);
      fault_table($q, $fault);
      return;
    }

    # Remove key
    OMP::KeyServer->removeKey($formkey);

  } elsif ($q->param('change_status')) {

    # Lookup table for status
    my %status = OMP::Fault->faultStatus();

    my $status = $q->param('status');

    if ($status != $fault->status) {
      # Get host (and user maybe) info
      my @user = OMP::General->determine_host;
      my $author;

      # Make author either an email address or "user on [machine name]"
      if ($user[2] =~ /@/) {
	$author = $user[0];
      } else {
	$author = "user on $user[2]";
      }

     try {
	# Right now we'll just do an update by resubmitting the fault
	# with the new status parameter.  But in principal we should
	# have a method for doing an explicit status update.
	
	# Change the status parameter
	$fault->status($q->param('status'));
	
	# Resubmit the fault
	OMP::FaultServer->updateFault($fault, $author);
	
	push @title, "Fault status changed to \"" . $fault->statusText . "\"";
      } otherwise {
	my $E = shift;
	push @title, "An error has prevented the fault status from being updated: $E";
      };
    } else {
      # Status is the same, dont update
      push @title, "This fault already has a status of \"" . $fault->statusText . "\"";
    }
  }

  $fault = OMP::FaultServer->getFault($faultid);

  titlebar($q, ["View Fault ID: $faultid", join('<br>',@title)], %cookie);

  fault_table($q, $fault);
  print "<br>";

  # Form for printing
  my @faults = ($fault->id);
  print_form($q, 0, @faults);
}

=item B<view_fault_form>

Create a form for submitting a fault ID for a fault to be viewed.

  view_fault_form($cgi);

=cut

sub view_fault_form {
  my $q = shift;

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

Provide a form for changing the status of a fault.  Second argument is an C<OMP::Fault> object.

  change_status_form($cgi, $fault);

=cut

sub change_status_form {
  my $q = shift;
  my $fault= shift;

  my $faultid = $fault->id;
  # Get available statuses
  my %status = OMP::Fault->faultStatus();
  my %labels = map {$status{$_}, $_} %status; # pop-up menu labels

  print $q->startform;
  print $q->hidden(-name=>'show_output', -default=>'true');
  print $q->hidden(-name=>'faultid', -default=>$faultid);
  print $q->popup_menu(-name=>'status',
		       -default=>$fault->status,
		       -values=>[values %status],
		       -labels=>\%labels,);
  print " ";
  print $q->submit(-name=>'change_status',
		   -label=>'Change',);
  print $q->endform;
  
}

=item B<file_fault_form>

Create a form for submitting fault details.  This subroutine takes its arguments in
the form of a hash containing the following keys:

  cgi    - the CGI query object
  cookie - a hash REFERENCE containing the usual cookie details
  fault  - an OMP::Fault object

The fault key is optional.  If present, the details of the fault object will be used
to provide defaults for all of the fields This allows this form to be used for editing 
fault details.

  file_fault_form(cgi => $cgi,
		  cookie => \%cookie,
		  fault => $fault_object);

=cut

sub file_fault_form {
  my %args = @_;
  my $q = $args{cgi};
  my $cookie = $args{cookie};
  my $fault = $args{fault};

  # Get a new key for this form
  my $formkey = OMP::KeyServer->genKey;

  # Create values and labels for the popup_menus
  my $systems = OMP::Fault->faultSystems($cookie->{category});
  my @system_values = map {$systems->{$_}} sort keys %$systems;
  my %system_labels = map {$systems->{$_}, $_} keys %$systems;

  my $types = OMP::Fault->faultTypes($cookie->{category});
  my @type_values = map {$types->{$_}} sort keys %$types;
  my %type_labels = map {$types->{$_}, $_} keys %$types;

  # Get available statuses
  my %status = OMP::Fault->faultStatus();
  my @status_values = map {$status{$_}} sort keys %status;
  my %status_labels = map {$status{$_}, $_} %status;

  # Add some empty values to our menus (this is part of making sure that a 
  # meaningful value is selected by the user) if a new fault is being filed
  unless ($fault) {
    push @system_values, undef;
    push @type_values, undef;
    $type_labels{''} = "Select a type";
    $system_labels{''} = "Select a system";
  }

  # Set defaults.  There's probably a better way of doing what I'm about
  # to do...
  my %defaults;
  my $submittext;

  if (!$fault) {
    %defaults = (user => $cookie->{user},
		 system => '',
		 type => '',
		 status => $status{Open},
		 loss => undef,
		 time => undef,
		 tz => 'HST',
		 subject => undef,
		 message => undef,
		 assoc => undef,
		 assoc2 => undef,
		 urgency => undef,);

    # Set the text for our submit button
    $submittext = "Submit fault";
  } else {
    # We have a fault object so use it's details as our defaults

    # Get the fault date (if any)
    my $faultdate = $fault->faultdate;

    # Convert faultdate to local time
    if ($faultdate) {
      my $epoch = $faultdate->epoch;
      $faultdate = localtime($epoch);
      $faultdate = $faultdate->strftime("%Y-%m-%dT%T")
    }

    # Is this fault marked urgent?
    my $urgent = ($fault->urgencyText =~ /urgent/i ? "urgent" : undef);

    # Projects associated with this fault
    my @assoc = $fault->projects;

    # The fault text.  Strip out <PRE> tags.  If there aren't any <PRE> tags
    # we'll assume this fault used explicit HTML formatting so we'll add in
    # an opening <html> tag.
    my $message = $fault->responses->[0]->text;
    if ($message =~ m!^<pre>(.*?)</pre>$!is) {
      $message = OMP::General->replace_entity($1);
    } else {
      $message = "<html>" . $message;
    }

    %defaults = (user=> $fault->responses->[0]->author->userid,
		 system => $fault->system,
		 status => $fault->status,
		 type => $fault->type,
		 loss => $fault->timelost,
		 time => $faultdate,
		 tz => 'HST',
		 subject => $fault->subject,
		 message => $message,
		 assoc2 => join(',',@assoc),
		 urgency => $urgent,);

    # Set the text for our submit button
    $submittext = "Submit changes";
  }

  # Fields in the query param stack will override normal defaults
  for (keys %defaults) {
    if ($q->param($_)) {
      $defaults{$_} = $q->param($_);
    }
  }

  print "<table border=0 cellspacing=4><tr>";
  print $q->startform;

  # Embed the key
  print $q->hidden(-name=>'formkey',
		   -default=>$formkey);

  # Need the show_output param in order for the output code ref to be called next
  print $q->hidden(-name=>'show_output',
		   -default=>'true');

  # Embed the fault ID and status if we are editing a fault
  if ($fault) {
    print $q->hidden(-name=>'faultid', -default=>$fault->id);
    print $q->hidden(-name=>'status', -default=>$defaults{status});
  }

  print "<td align=right><b>User:</b></td><td>";

  # DISABLE USER FIELD IF FORM IS FOR EDITING
  if (! $fault) {
    print $q->textfield(-name=>'user',
			-size=>'16',
			-maxlength=>'90',
			-default=>$defaults{user},);
  } else {
    print " <strong>$defaults{user}</strong>";
    print $q->hidden(-name=>'user_hidden', -default=>$defaults{user});
  }

  print "</td><tr><td align=right><b>System:</b></td><td>";
  print $q->popup_menu(-name=>'system',
		       -values=>\@system_values,
		       -default=>$defaults{system},
		       -labels=>\%system_labels,);
  print "</td><tr><td align=right><b>Type:</b></td><td>";
  print $q->popup_menu(-name=>'type',
		       -values=>\@type_values,
		       -default=>$defaults{type},
		       -labels=>\%type_labels,);

  unless ($fault) {
    print "</td><tr><td align=right><b>Status:</b></td><td>";
    print $q->popup_menu(-name=>'status',
			 -values=>\@status_values,
			 -default=>$defaults{status},
			 -labels=>\%status_labels,);
  }

  # Only provide fields for taking "time lost" and "time of fault"
  # if the category allows it
  if (OMP::Fault->faultCanLoseTime($cookie->{category})) {
    print "</td><tr><td align=right><b>Time lost <small>(hours)</small>:</b></td><td>";
    print $q->textfield(-name=>'loss',
			-default=>$defaults{loss},
			-size=>'4',
			-maxlength=>'10',);
    print "</td><tr><td align=right valign=top><b>Time of fault <small>(YYYY-MM-DDTHH:MM or HH:MM)</small>:</td><td>";
    print $q->textfield(-name=>'time',
			-default=>$defaults{time},
			-size=>20,
			-maxlength=>128,);
    print "&nbsp;";
    print $q->popup_menu(-name=>'tz',
			 -values=>['UT','HST'],
			 -default=>$defaults{tz},);
  }

  print "</td><tr><td align=right><b>Subject:</b></td><td>";
  print $q->textfield(-name=>'subject',
		      -size=>'60',
		      -maxlength=>'128',
		      -default=>$defaults{subject},);

  # Put up this reminder for telescope related filings
  if (OMP::Fault->faultIsTelescope($cookie->{category})) {
    print "</td><tr><td colspan=2>";
    print "<small>Please remember to identify the instrument being used and "
      ."the data frame number if either are relevant</small>";
  }

  print "</td><tr><td colspan=2 align=right>";

  print $q->textarea(-name=>'message',
		     -rows=>20,
		     -columns=>78,
		     -default=>$defaults{message},);

  # If were in a category that allows project association create a
  # checkbox group for specifying an association with projects.

  if (OMP::Fault->faultCanAssocProjects($cookie->{category})) {
    # Values for checkbox group will be tonights projects
    my $aref = OMP::MSBServer->observedMSBs({
					     usenow => 1,
					     format => 'data',
					     returnall => 0,});

    if (@$aref[0] and ! $fault) {
      # We don't want this checkbox group if this form is being used for editing a fault
      my %projects;
      for (@$aref) {
	# Make sure to only include projects associated with the current
	# telescope category
	my $category = $cookie->{category};
	my @instruments = split(/\W/, $_->instrument);
	my $tel = OMP::Config->inferTelescope('instruments', @instruments);
	$projects{$_->projectid} = $_->projectid
	  unless ($tel !~ /$category/i);
	
      }
      if (%projects) {
	print "</td><tr><td colspan=2><b>Fault is associated with the projects: </b>";
	print $q->checkbox_group(-name=>'assoc',
				 -values=>[keys %projects],
				 -default=>$defaults{assoc},
				 -linebreak=>'true',);
	print "</td><tr><td colspan=2><b>Associated projects may also be specified here if not listed above </b>";
      } else {
	print "</td><tr><td colspan=2><b>Projects associated with this fault may be specified here </b>";
      }
    } else {
      print "</td><tr><td colspan=2><b>Projects associated with this fault may be specified here </b>";
    }
    print "<font size=-1>(separated by spaces)</font><b>:</b>";
    print "</td><tr><td colspan=2>";
    print $q->textfield(-name=>'assoc2',
		        -size=>50,
		        -maxlength=>300,
		        -default=>$defaults{assoc2},);
  }

  print "</td><tr><td><b>";

  # Even though there is only a single option for urgency I'm using a checkbox group
  # since it's easier to set a default this way
  print $q->checkbox_group(-name=>'urgency',
			   -values=>['urgent'],
			   -labels=>{urgent => "This fault is urgent"},
			   -default=>$defaults{urgency},);
  print "</b></td><td align=right>";
  print $q->submit(-name=>'submit',
		   -label=>$submittext,);
  print $q->endform;
  print "</td></table>";

}

=item B<response_form>

Create a form for submitting or editing a response.

  response_form(cgi => $cgi,
		cookie => \%cookie,
                respid => $respid,
		fault => $fault);

C<fault> is always a required argument but C<respid> is only required if the
form is going to be used for editing instead of normal response submission.  The response ID sould be that of the response to be edited.

=cut

sub response_form {
  my %args = @_;
  my $q = $args{cgi};
  my $fault = $args{fault};
  my $respid = $args{respid};
  my $cookie = $args{cookie};

  my $faultid = $fault->id;

  # Get a new key for this form
  my $formkey = OMP::KeyServer->genKey;

  # Get available statuses
  my %status = OMP::Fault->faultStatus();
  my %labels = map {$status{$_}, $_} %status; # pop-up menu labels

  # Set defaults.  Use cookie values if param values aren't available.
  my %defaults;
  if ($respid) {
    # Setup defaults for response editing
    my $response = OMP::FaultUtil->getResponse($respid, $fault);

    (! $response) and croak "Unable to retrieve response with ID [$respid] from fault [".$fault->id."]\n";

    my $text = $response->text;

    # Prepare text for editing
    if ($text =~ m!^<pre>(.*?)</pre>$!is) {
      $text = OMP::General->replace_entity($1);
    } else {
      $text = "<html>" . $text;
    }


    %defaults = (user => $response->author->userid,
		 text => $text,
		 submitlabel => "Submit changes",);
  } else {

    %defaults = (user => $cookie->{user},
		 text => undef,
		 status => $fault->status,
		 submitlabel => "Submit response",);
  }

  # Param list values take precedence
  for (keys %defaults) {
    if ($q->param($_)) {
      $defaults{$_} = $q->param($_);
    }
  }

  print "<table border=0><tr><td align=right><b>User: </b></td><td>";
  print $q->startform;

  # Embed the key
  print $q->hidden(-name=>'formkey',
		   -default=>$formkey);
  print $q->hidden(-name=>'show_output', -default=>['true']);
  print $q->hidden(-name=>'faultid', -default=>$faultid);

  # Embed the response ID if we are editing a response
  print $q->hidden(-name=>'respid', -default=>$respid)
    if ($respid);

  # DISABLE USER FIELD IF FORM IS FOR EDITING
  if (! $respid) {
    print $q->textfield(-name=>'user',
			-size=>'25',
			-maxlength=>'75',
			-default=>$defaults{user},);
  } else {
    print " <strong>$defaults{user}</strong>";
    print $q->hidden(-name=>'user_hidden', -default=>$defaults{user});
  }

  # Only show the status if we are filing a new response
  if (! $respid) {
    print "</td><tr><td><b>Status: </b></td><td>";
    print $q->popup_menu(-name=>'status',
			 -default=>$defaults{status},
			 -values=>[values %status],
			 -labels=>\%labels,);
  }

  print "</td><tr><td></td><td>";
  print $q->textarea(-name=>'text',
		     -rows=>20,
		     -columns=>72,
		     -default=>$defaults{text},);
  print "</td></tr><td colspan=2 align=right>";
  print $q->submit(-name=>'respond',
		   -label=>$defaults{submitlabel});
  print $q->endform;
  print "</td></table>";
}

=item B<update_fault_content>

Create a form for updating fault details

  update_fault_content($cgi, %cookie);

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

    titlebar($q, ["Update Fault [$faultid]"], %cookie);

    # Get the fault
    my $fault = OMP::FaultServer->getFault($faultid);

    # Form for taking new details.  Displays current values.
    file_fault_form(cgi => $q,
		    cookie => \%cookie,
		    fault => $fault);
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

  # For the titlebar
  my @title;

  my $faultid = $q->param('faultid');

  # Get host (and user maybe) info of the user who is modifying the fault
  my @user = OMP::General->determine_host;
  my $author;

  # Make author either an email address or "user on [machine name]"
  if ($user[2] =~ /@/) {
    $author = $user[0];
  } else {
    $author = "user on $user[2]";
  }

  # Get the original fault
  my $fault = OMP::FaultServer->getFault($faultid);

  # Get new properties
  my %newdetails = parse_file_fault_form($q);

  # Store details in a fault object for comparison
  my $new_f = new OMP::Fault(category=>$cookie{category},
			     fault=>$fault->responses->[0],
			     %newdetails);

  my @details_changed = OMP::FaultUtil->compare($new_f, $fault);

  # Store details in a fault response object for comparison
  my $new_r = new OMP::Fault::Response(%newdetails);

  # Our original response
  my $response = $fault->responses->[0];

  # "Preify" the text before we compare responses
  my $newtext = $newdetails{text};
  $newtext =~ s!</*html>!!ig;
  $newtext = OMP::General->preify_text($newtext);

  my @response_changed = OMP::FaultUtil->compare($new_r, $fault->responses->[0]);

  if ($details_changed[0] or $response_changed[0]) {
    # Changes have been made so we'll do an update

    my $E;
    try {

      if ($details_changed[0]) {
	# Apply changes to fault
	for (@details_changed) {
	  $fault->$_($newdetails{$_});
	}

	# Store changes to DB
	OMP::FaultServer->updateFault($fault, $author);
      }

      if ($response_changed[0]) {

	# Apply changes to response
	for (@response_changed) {
	  $response->$_($newdetails{$_});
	}

	OMP::FaultServer->updateResponse($fault->id, $response);
      }

      push @title, "This fault has been updated";

      # Get the fault in it's new form
      $fault = OMP::FaultServer->getFault($faultid);

    } otherwise {
      $E = shift;
      push @title, "An error has occurred which prevented the fault from being updated";
      push @title, "$E";
    };
  } else {
    push @title, "No changes were made";
  }

  titlebar($q, ["Update Fault [". $fault-> id ."]", join('<br>',@title)], %cookie);

  # Display the fault
  fault_table($q, $fault);
}

=item B<update_resp_content>

Create a form for updating fault details

  update_resp_content($cgi, %cookie);

=cut

sub update_resp_content {
  my $q = shift;
  my %cookie = @_;

  my $faultid = $q->url_param('id');
  my $respid = $q->url_param('respid');

  if ($faultid and $respid) {
    titlebar($q, ["Update Response [$faultid]"], %cookie);

    # Get the fault
    my $fault = OMP::FaultServer->getFault($faultid);

    (! $fault) and croak "Unable to retrieve fault with ID [$faultid]\n";

    # Form for taking new details.  Displays current values.
    response_form(cgi => $q,
		  cookie => \%cookie,
		  fault => $fault,
		  respid => $respid,);
  } else {
    croak "A fault ID and response ID must be provided in the URL\n";
  }
}

=item B<update_resp_output>

Submit changes to a fault response.

  update_resp_output($cgi, %cookie);

=cut

sub update_resp_output {
  my $q = shift;
  my %cookie = @_;

  my $faultid = $q->param('faultid');
  my $respid = $q->param('respid');
  my $text = $q->param('text');
  my $author = $q->param('user');

  # User may be a hidden param
  (! $author) and $author = $q->param('user_hidden');

  # Convert author to OMP::User object
  $author = OMP::UserServer->getUser($author);

  # Prepare the text
  if ($text =~ /<html>/i) {
    # Strip out the <html> and </html> tags
    $text =~ s!</*html>!!ig;
  } else {
    $text = OMP::General->preify_text($text);
  }

  # Strip out ^M
  $text =~ s/\015//g;

  # Get the fault
  my $fault = OMP::FaultServer->getFault($faultid);

  # Get the response object
  my $response = OMP::FaultUtil->getResponse($respid, $fault);

  # Make changes to the response object
  $response->author($author);
  $response->text($text);

  # SHOULD DO A COMPARISON TO SEE IF CHANGES WERE ACTUALLY MADE

  # Submit the changes
  my @title = ("Update Response");
  try {
    OMP::FaultServer->updateResponse($faultid, $response);
    push @title, "Response has been updated"
  } otherwise {
    my $E = shift;
    push @title, "Unable to update response";
    print "<pre>$E</pre>";
  };

  titlebar($q, \@title, %cookie);

  # Redisplay fault
  $fault = OMP::FaultServer->getFault($faultid);

  fault_table($q, $fault);
}

=item B<show_faults>

Show a list of faults

  show_faults(CGI => $cgi, 
	      faults => $faults,
	      orderby => 'response',
	      descending => 1,
	      URL => "fbfault.pl");

Takes the following key/value pairs as arguments:

CGI: A C<CGI> query object
faults: A reference to an array of C<OMP::Fault> objects
descending: If true faults are listed in descending order
URL: The absolute or relative path to the script to be used for the view/respond link
orderby: Should be either 'response' (to sort by date of latest response) or 'filedate'

Only the B<CGI> and B<faults> keys are required.


=cut

sub show_faults {
  my %args = @_;
  my $q = $args{CGI};
  my $faults = $args{faults};
  my $descending = $args{descending};
  my $url = $args{url};

  (! $url) and $url = "viewfault.pl";

  # Generate stats so we can decide to show fields like "time lost"
  # only if any faults have lost time
  my $stats = new OMP::FaultStats( faults => $faults );

  print "<table width=$TABLEWIDTH cellspacing=0>";
  print "<tr><td><b>ID</b></td><td><b>Subject</b></td><td><b>Filed by</b></td><td><b>System</b></td><td><b>Type</b></td><td><b>Status</b></td>";

  # Show time lost field?
  if ($stats->timelost > 0) {
    print "<td align=center><b>Loss</b></td>";
  }

  print "<td><b>Replies</b></td><td> </td>";

  if ($args{orderby} eq 'response') {
    @$faults = sort {$a->responses->[-1]->date->epoch <=> $b->responses->[-1]->date->epoch} @$faults;
  }

  my @faults;
  # Sort faults in the order they are to be displayed
  if ($descending) {
    @faults = reverse @$faults;
  } else {
    @faults = @$faults;
  }

  my $colorcount;
  for my $fault (@faults) {
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

    my $replies = $#{$fault->responses};  # The number of actual replies

    print "<tr bgcolor=$bgcolor><td>$faultid</td>";
    print "<td><b><a href='$url?id=$faultid'>$subject &nbsp;</a></b>";

    # Show affected projects?
    if ($q->param('show_affected') and $fault->projects) {
      print "<br>";
      my @projlinks = map {"<a href='projecthome.pl?urlprojid=$_'>$_</a>"} $fault->projects;
      print join (" | ", @projlinks);
    }

    print "</td>";
    print "<td>" . OMP::Display->userhtml($user, $q) . "</td>";
    print "<td>$system</td>";
    print "<td>$type</td>";
    print "<td>$status</td>";

    # Show time lost field?
    if ($stats->timelost > 0) {
      my $timelost = $fault->timelost;
      ($timelost == 0) and $timelost = "--" or $timelost = $timelost . " hrs";
      print "<td align=center>$timelost</td>";
    }


    print "<td align='center'>$replies</td>";
    print "<td><b><a href='$url?id=$faultid'>[View/Respond]</a></b></td>";
  }

  print "</table>";
}

=item B<print_form>

Create a simple form for sending faults to a printer.  If the second argument
is true then advanced options will be displayed.  Last argument is an array containing the fault IDs of the faults
to be printed.

  print_form($q, 1, @faultids);

=cut

sub print_form {
  my $q = shift;
  my $advanced = shift;
  my @faultids = @_;

  # Get printers
  my @printers = OMP::Config->getData('printers');

  print $q->startform;

  # ($showoutput) and print $q->hidden(-name=>'show_output', -default=>'true');

  print $q->hidden(-name=>'faults',
		   -default=>join(',',@faultids));
  print $q->submit(-name=>'print',
		   -label=>'Send to printer');
  print "&nbsp;";
  print $q->popup_menu(-name=>'printer',
			-values=>\@printers,);
  if ($advanced) {
    print "<br>Using method ";
    print $q->popup_menu(-name=>'print_method',
			 -values=>["separate","combined"],
			 -labels=>{separate => "One fault per page",
				   combined => "Combined",},);
  }

  print $q->endform;
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

  print "<table width=$TABLEWIDTH><tr bgcolor=#babadd><td><font size=+1><b>$toptitle:&nbsp;&nbsp;".$title->[0]."</font></td>";
  print "<tr><td><font size=+2><b>$title->[1]</b></font></td>"
    if ($title->[1]);
  print "</table><br>";
}

=item B<parse_file_fault_form>

Take the arguments from the fault filing form and parse them so they can be used to create
the fault and fault response objects.  Only argument is a C<CGI> query object.

  parse_file_fault_form($q);

Returns the following keys:

  subject, faultdate, timelost, system, type, status, urgency, projects, author, text

=cut

sub parse_file_fault_form {
  my $q = shift;

  my %parsed = (subject => $q->param('subject'),
	        system => $q->param('system'),
	        type => $q->param('type'),
	        status => $q->param('status'));

  # Determine the urgency
  my %urgency = OMP::Fault->faultUrgency;
  if ($q->param('urgency') =~ /urgent/) {
    $parsed{urgency} = $urgency{Urgent};
  } else {
    $parsed{urgency} = $urgency{Normal};
  }

  # Store time lost if defined.
  (length($q->param('loss')) >= 0) and $parsed{timelost} = $q->param('loss');

  # Get the associated projects
  if ($q->param('assoc') or $q->param('assoc2')) {
    my @assoc = $q->param('assoc');

    # Strip out commas and seperate on spaces
    my $assoc2 = $q->param('assoc2');
    $assoc2 =~ s/,/ /g;
    my @assoc2 = split(/\s+/,$assoc2);

    # Use a hash to eliminate duplicates
    my %projects = map {lc($_), undef} @assoc, @assoc2;
    $parsed{projects} = [keys %projects];
  }

  # If the time of fault was provided use it otherwise
  # do nothing
  if ($q->param('time')) {
    my $t;
    my $time = $q->param('time');

    # Define whether or not we have a local time
    my $islocal = ($q->param('tz') =~ /HST/ ? 1 : 0);
    my $utdate;

    if ($time =~ /^(\d\d*?)\W*(\d{2})$/) {
      # Just the time (something like HH:MM)
      my $hh = $1;
      my $mm = $2;
      if ($islocal) {
	# Time is local
	# Using Time::Piece localtime() method until OMP::General today()
        # method supports local time
	my $today = localtime;
	$utdate = OMP::General->parse_date($today->ymd . "T$hh:$mm", 1);
      } else {
	my $today = OMP::General->today;
	$utdate = OMP::General->parse_date("$today" . "T$hh:$mm");
      }
    } else {
      $utdate = OMP::General->parse_date($time, $islocal);
    }

    # Store the faultdate
    if ($utdate) {
      my $gmtime = gmtime();

      # Subtract a day if date is in the future.
      ($gmtime->epoch < $utdate->epoch) and $utdate -= 86400;

      $parsed{faultdate} = $utdate;
    }
  }

  my $author = $q->param('user');

  # User may be a hidden param
  (! $author) and $author = $q->param('user_hidden');

  $parsed{author} = OMP::UserServer->getUser($author);

  # The text.  Put it in <pre> tags if there isn't an <html>
  # tag present
  my $text = $q->param('message');

  $parsed{text} = OMP::General->preify_text($text);

  return %parsed;
}

=item B<url_args>

Alter query parameters in the current URL.  Useful for creating links to the
same script but with different parameters.

  $url = url_args($cgi, $key, $oldvalue, $newvalue);

All arguments are required.

=cut

sub url_args {
  my $q = shift;
  my $key = shift;
  my $oldvalue = shift;
  my $newvalue = shift;

  my $url = $q->self_url;
  $url =~ s/(\;|\?|\&)$key\=$oldvalue//g;
    if ($url =~ /\?/) {
      $url .= "&" . $key . "=" . $newvalue;
    } else {
      $url .= "?" . $key . "=" . $newvalue;
    }

  return $url;
}

=item B<fault_summary_form>

Create a form for taking parameters for a fault summary.

  fault_summary_form($q);

=cut

sub fault_summary_form {
  my $q = shift;

  # Get available fault categories
  my @categories = sort OMP::Fault->faultCategories;

  print "<h2>Summarize faults</h2>";
  print $q->start_form;
  print "Category";
  print $q->popup_menu(-name=>"category",
		       -values=>\@categories,);
  print "<table><td>";
  print $q->radio_group(-name=>"period",
		        -values=>["last_month","arbitrary"],
		        -labels=>{last_month=>"Last calendar month",arbitrary=>"For the past"},
		        -default=>"last_month",
		        -linebreak=>"true",);
  print "</td><td valign=bottom>";
  print $q->textfield(-name=>"days",
		      -default=>7,
		      -size=>3,
		      -maxlength=>4,);
  print " days";
  print "</td><tr><td>";
  print $q->submit(-name=>'submit',);
  print "</td></table>";
  print $q->end_form;
}

=item B<fault_summary_content>

Create a page summarizing faults for a particular category, or all categories.

  fault_summary_content($cgi, $faults,[$mindate, $maxdate]);

Takes a C<CGI> query object and an array of fault categories as its arguments.

=cut

sub fault_summary_content {
  my $q = shift;
  my $faults = shift;
  my $mindate = shift;
  my $maxdate = shift;
  my $category = $q->param('category');
  my $ompurl = OMP::Config->getData('omp-url');
  my $iconurl = $ompurl . OMP::Config->getData('iconsdir');
  my %status = OMP::Fault->faultStatus;
  my $systems = OMP::Fault->faultSystems($faults->[0]->category);
  my $types = OMP::Fault->faultTypes($faults->[0]->category);
  my %statusOpen = OMP::Fault->faultStatusOpen;

  if (! $faults) {
    # Generate the date portion of our XML query
    my $queryDateStr;
    my $today = localtime;
    my $period;
    if ($q->param('period') eq 'last_month') {
      # Get results for the period between the first 
      # and last days of the last month
      my $today = localtime;
      my $year;
      my $month;
      if ($today->strftime("%Y%m") =~ /^(\d{4})(\d{2})$/) {
	$year = $1;
	$month = $2;
      }

      $month -= 1;
      if ($month eq 0) {
	$month = 12;
	$year -= 1;
      }

      my $beginDate = Time::Piece->strptime($year . $month . "01", "%Y%m%d");
      my $endDate = $year . "-" . $month . "-" . $beginDate->month_last_day . "T23:59:59";
      $queryDateStr = "<date><min>".$beginDate->datetime."</min><max>$endDate</max></date>";
      $period = $beginDate->monname ." ". $beginDate->year;
    } else {
      # Get results between today and N days ago
      my $days = $q->param('days');
      (! $days) and $days = 7;
      
      $queryDateStr = "<date delta='-".$days."'>" . $today->datetime . "</date>";
      $period = "the past $days days";
    }


    # Construct our fault query
    my $xml = "<FaultQuery>".
      "<category>$category</category>".
	$queryDateStr.
	  "<isfault>1</isfault>".
	    "</FaultQuery>";

    # Run the query
    $faults = OMP::FaultServer->queryFaults($xml, 'object');

    # Title
    print "<h2>$category fault summary for $period</h2>";
  }

  # Check that we got some faults back
  if (! $faults->[0]) {
    print "<h3>No faults were filed during this period</h3>";
    return;
  }

  # Store faults by system and type
  my %faults;
  my %totals;
  my %timelost;
  my %sysID; # IDs used to identify table rows that belong to a particular system
  my $timelost = 0;
  my $totalfiled = 0;
  $totals{open} = 0;

  for (@$faults) {

    $totals{$_->systemText}++;
    $timelost += $_->timelost;

    # Keep track of number of faults that were filed during the query period
    my $filedate = $_->responses->[0]->date;
    if ($mindate and $maxdate) {
      ($filedate->epoch >= $mindate->epoch and $filedate->epoch <= $maxdate->epoch) and $totalfiled++;
    }
    # Store open faults and closed major faults
    my $status;
    if (exists $statusOpen{$_->statusText}) {
      $status = 'open';
    } else {
      $status = 'closed';
      $sysID{$_->systemText} = sprintf("%08d",$systems->{$_->systemText}) . "sys";
    }

    push (@{$faults{$_->systemText}{$status}{$_->typeText}}, $_);
    $totals{$status}++;

    $timelost{$status}{$_->systemText} += $_->timelost;
  }

  # Totals
  print "<table cellspacing=1><td>";

  print "<strong>Faults returned by query: </strong>".scalar(@$faults);
  if ($mindate and $maxdate) {
    print "<br><strong>Query period: </strong>".$mindate->strftime("%Y%m%d %H:%M") ." - ". $maxdate->strftime("%Y%m%d %H:%M %Z");
    print "<br><strong>Matching faults filed in period: </strong>$totalfiled";
  }

  print "<br><strong>Total time lost:</strong> $timelost hours";
  print "<br><strong>Open faults:</strong> $totals{open}";
  print "</td></table><br>";

  # First show all open, then all major closed
  print "<table bgcolor=#afafe0 cellspacing=1><td>";
  print "<table width=100% cellspacing=0 cellpadding=2 border=0><td colspan=7><font size=+1><strong>";

  print "All faults";

  print "</strong></font>";

  # Don't hide closed faults if we only have closed faults
  my $toggleDef;
  my $toggleText;
  my $class;
  if ($totals{open} > 0) {
    $toggleDef = 'show';
    $class = 'hide';
    $toggleText = "Show closed faults";
  } else {
    $toggleDef = 'hide';
    $class = 'show';
    $toggleText = "Hide closed faults";
  }

  # Create argument list for calling toggle script
  my $argumentStr = join(",", map {"'$sysID{$_}'"} keys %sysID);
  $argumentStr = "'function__toggleClosed'," . $argumentStr;

  # Create link for toggling display of all closed faults
  if ($totals{closed} > 0 and $totals{open} > 0) {
    print "&nbsp;<a href=\"#\" class=\"link_option\" onclick=\"toggle($argumentStr); return false\"><img border=\"0\" src=\"$iconurl/$toggleDef.gif\" width=\"10\" height=\"10\" id=\"imgfunction__toggleClosed\"></a>";
    print "&nbsp;<a href=\"#\" class=\"link_option\" onclick=\"toggle($argumentStr); return false\"><span id=\"function__toggleClosed\" function=\"$toggleDef\">$toggleText</span></a>";
    print "</td>";
  }

  # Display faults by system
  for my $system (sort keys %faults) {
    print "<tr><td colspan=2 class='row_system_title'>$system <span class='misc_info'>(total: $totals{$system})</span></td>";
    print "<td class='row_system'>Filed by</td>";
    print "<td class='row_system'>Last response by</td>";
    print "<td class='row_system'>Time lost</td>";
    print "<td class='row_system'>Responses</td>";
    print "<td class='row_system'>Days idle</td>";

    my $systemTimeLost = 0;

    for my $status (qw/open closed/) {
      
      next if (! $faults{$system}{$status});

      # Use different background colors for different statuses
      my $bgcolor;
      ($status eq 'open') and $bgcolor = '#8080cc'
	or $bgcolor = '#6767af';

      # Make a button for toggling view of closed faults
      if ($status eq 'closed') {
	print "<tr>";
	print "<td class='row_closed_title' colspan=4>";
	print "<a class=\"link_option\" href=\"#\" onclick=\"toggle('$sysID{$system}'); return false\"><img border=\"0\" src=\"$iconurl/$toggleDef.gif\" width=\"10\" height=\"10\" id=\"img$sysID{$system}\"></a>";
        print "&nbsp;<a class=\"link_option\" href=\"#\" onclick=\"toggle('$sysID{$system}'); return false\">Closed faults</a></td>";
	print "<td class='row_closed'><span id=\"info$sysID{$system}\" value=\"$timelost{$status}{$system}\">";
	($class eq 'hide') and print $timelost{$status}{$system};
        print "</span>&nbsp;</td><td colspan=2 class='row_closed'>&nbsp;</td>";
	print "</tr>";
      }

      for my $type (sort keys %{$faults{$system}{$status}}) {

	my $rowID = $sysID{$system} . "_" . $types->{$type};

	($status eq 'closed') and print "<tr id=\"$rowID\" class=\"$class\">"
	  or print "<tr>";

	print "<td bgcolor=$bgcolor colspan=7><font color=$bgcolor>----</font><strong>$type</strong></td>";

	my $count = 0;

	for my $fault (@{$faults{$system}{$status}{$type}}) {

	  $count++;

	  # Find out how long since the last response
	  my $localtime = localtime;
	  my $locallast = localtime($fault->responses->[-1]->date->epoch);
	  my $lastresponse = $localtime - $locallast;
	  $lastresponse = sprintf("%d", $lastresponse->days);
	  $systemTimeLost += $fault->timelost;

	  # Setup the preview
	  my $preview = substr($fault->responses->[0]->text, 0, 87);
	  $preview = OMP::General->html_to_plain($preview);
	  $preview =~ s/\"/\'\'/gi;
	  $preview =~ s/\s+/ /gi;

	  my $subject = ($fault->subject) ? $fault->subject : "No subject";

	  my $author = OMP::Display->userhtml($fault->responses->[0]->author, $q);
	  my $respAuthor;
	  ($fault->responses->[1]) and
	    $respAuthor = OMP::Display->userhtml($fault->responses->[-1]->author, $q);

	  my $faultRowID = $rowID . "_" . $count;

	  ($status eq 'closed') and print "<tr id=\"$faultRowID\" class=\"$class\""
	    or print "<tr ";

	  print "bgcolor=$bgcolor><td><font color=$bgcolor>------</font>";
	  ($fault->timelost > 0) and print "<img src=$iconurl/timelost.gif alt=\"Fault lost time\">"
	    or print "<img src=$iconurl/spacer.gif height=13 width=10>";
	  print " <a href=\"viewfault.pl?id=".$fault->id."\" class=\"link_fault_id\" title=\"$preview\">". $fault->id ."</td>";
	  print "<td><a href=\"viewfault.pl?id=".$fault->id."\" class=\"link_fault_subject\" title=\"$preview\">". $subject ."</a>";

	  # Show affected projects?
	  if ($q->param('show_affected') and $fault->projects) {
	    print "<br><span class='proj_fault_link'>";
	    my @projlinks = map {"<a href='projecthome.pl?urlprojid=$_'>$_</a>"} $fault->projects;
	    print join (" | ", @projlinks);
	    print "</span>";
	  }

	  print "</td>";
	  print "<td align=right class='userid'>". $fault->responses->[0]->author->html . "</td>";
	  print "<td align=right class='userid'>";
	  ($respAuthor) and print $respAuthor
	    or print "n/a";
	  print "</td>";
	  print "<td align=right><span class='fault_numbers'>". $fault->timelost ."</span></td>";
	  print "<td align=right><span class='fault_numbers'>". $#{$fault->responses} ."</span></td>";
	  print "<td align=right><span class='fault_numbers'>". $lastresponse ."</span></td>";
	}
      }
    }
    # Total time lost for system
    print "<tr bgcolor=#afafe0><td colspan=4 align=right>Total time lost</td><td align=right><span class='fault_total'>$systemTimeLost</span></td><td colspan=2></td>";

  }
  print "</tr></table>";
  print "</table>";
}

=back

=head1 AUTHOR

Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>,

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
