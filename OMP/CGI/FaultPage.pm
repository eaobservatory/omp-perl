package OMP::CGI::FaultPage;

=head1 NAME

OMP::CGI::FaultPage - Helper for the OMP fault CGI scripts

=head1 SYNOPSIS

  use OMP::CGI::FaultPage;

=head1 DESCRIPTION

Construct and display complete web pages for viewing faults
and interacting with the fault system in general.

=cut

use 5.006;
use strict;
use warnings;
use Carp;
our $VERSION = (qw$ Revision: 1.2 $ )[1];

use Time::Piece;
use Time::Seconds qw(ONE_DAY);

use OMP::CGI::Project;
use OMP::Config;
use OMP::DBServer;
use OMP::General;
use OMP::Fault;
use OMP::FaultDB;
use OMP::FaultUtil;
use OMP::Display;
use OMP::FaultServer;
use OMP::Fault::Response;
use OMP::User;
use OMP::UserServer;
use OMP::KeyServer;
use OMP::Error qw(:try);

use vars qw/@ISA %EXPORT_TAGS @EXPORT_OK/;

require Exporter;

$| = 1;

@ISA = qw/Exporter/;

@EXPORT_OK = (qw/file_fault file_fault_output query_fault_content query_fault_output view_fault_content view_fault_output update_fault_content update_fault_output update_resp_content update_resp_output fault_summary_content fb_fault_content/);

%EXPORT_TAGS = (
		'all' =>[ @EXPORT_OK ],
	       );

Exporter::export_tags(qw/ all /);

# Width for HTML tables
our $TABLEWIDTH = '100%';

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

  OMP::CGI::Fault::titlebar($q, ["File Fault"], %cookie);
  OMP::CGI::Fault::file_fault_form(cgi => $q,
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
    OMP::CGI::Fault::titlebar($q, ["File Fault", join('<br>',@title)], %cookie);
    print "<ul>";
    print map {"<li>$_"} @error;
    print "</ul>";
    OMP::CGI::Fault::file_fault_form(cgi => $q,
				     cookie => \%cookie,);
    return;
  }

  # Make sure user is valid
  my $user = OMP::UserServer->getUser($q->param('user'));
  if (! $user) {
    push @title, "The user ID you entered does not exist.  Please enter another and submit again";
    OMP::CGI::Fault::titlebar($q ,["File Fault", join('<br>',@title)], %cookie);
    OMP::CGI::Fault::file_fault_form(cgi => $q,
				     cookie => \%cookie,);
  }

  my %status = OMP::Fault->faultStatus;

  # Get the fault details
  my %faultdetails = OMP::CGI::Fault::parse_file_fault_form($q);

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
    OMP::CGI::Fault::titlebar($q, ["File Fault", "Fault $faultid has been filed"], %cookie);

    OMP::CGI::Fault::fault_table($q, $f, 'nostatus');
  }
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

  OMP::CGI::Project::proj_status_table($q, %cookie);

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

  OMP::CGI::Fault::show_faults(CGI => $q, 
			       faults => \@faults,
			       descending => 0,
			       URL => "fbfault.pl",);
  print "<hr>";
  print "<font size=+1><b>ID: " . $showfault->faultid . "</b></font><br>";
  print "<font size=+1><b>Subject: " . $showfault->subject . "</b></font><br>";
  OMP::CGI::Fault::fault_table($q, $showfault, 'noedit');
  print "<br>You may comment on this fault by clicking <a href='fbcomment.pl?subject=Fault%20ID:%20". $showfault->faultid ."'>here</a>";
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
    OMP::CGI::Fault::category_xml( $cookie{category} ).
	"<date delta='-14'>" . $t->datetime . "</date>".
	  "</FaultQuery>";

  # Setup an argument for use with the query_fault_form function
  my $hidefields = ($cookie{category} ne 'ANYCAT' ? 0 : 1);

  # Print faults if print button was clicked
  if ($q->param('print')) {
    my $printer = $q->param('printer');
    my @fprint = split(',',$q->param('faults'));

    my $separate = 0;  # Argument governs whether faults are printed combined
    if ($q->param('print_method') eq "separate") {
      $separate = 1;
    }

    OMP::FaultUtil->print_faults($printer, $separate, @fprint);

    OMP::CGI::Fault::titlebar($q, ["View Faults", "Sent faults to printer $printer"], %cookie);
    return;
  }

  if ($q->param('search')) {
    # The 'Search' submit button was clicked
    my @xml;

    push (@xml, OMP::CGI::Fault::category_xml( $cookie{category} ));

    if ($q->param('system') !~ /any/) {
      my $system = $q->param('system');
      push (@xml, "<system>$system</system>");
    }

    if ($q->param('type') !~ /any/) {
      my $type = $q->param('type');
      push (@xml, "<type>$type</type>");
    }

    # Return chronic faults only?
    if ($q->param('chronic')) {
      my %condition = OMP::Fault->faultCondition;
      push (@xml, "<condition>$condition{Chronic}</condition>");
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

      # Check that we will understand the dates` formats
      # Maybe OMP::General parse_date method should be
      # catching these...
      for ($mindatestr, $maxdatestr) {
	if ($_) {
	  unless ($_ =~ /^\d{8}$/ or
		  $_ =~ /^\d\d\d\d-\d\d-\d\d$/ or
		  $_ =~ /^\d{4}-\d\d-\d\dT\d\d:\d\d$/ or
		  $_ =~ /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d$/) {

	    croak "Date [$_] not understood. Please use either YYYYMMDD or YYYY-MM-DDTHH:MM format.";
	  }
	}
      }

      # Convert dates to UT
      $mindate = OMP::General->parse_date($mindatestr, 1);
      $maxdate = OMP::General->parse_date($maxdatestr, 1);

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
      ($mindate) and $mindate = localtime($mindate->epoch);
      ($maxdate) and $maxdate = localtime($maxdate->epoch);

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

      # Zero pad the month number
      $month = sprintf("%02d", $month);

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
    $xml = "<FaultQuery>" . join('',@xml) . "</FaultQuery>";

  } elsif ($q->param('major')) {
    # Faults within the last 14 days with 2 or more hours lost
    $xml = "<FaultQuery>".
      OMP::CGI::Fault::category_xml( $cookie{category} ).
	"<date delta='-14'>" . $t->datetime . "</date><timelost><min>2</min></timelost></FaultQuery>";
  } elsif ($q->param('recent')) {
    # Faults active in the last 36 hours
    $xml = "<FaultQuery>".
      OMP::CGI::Fault::category_xml( $cookie{category} ).
	"<date delta='-2'>" . $t->datetime . "</date></FaultQuery>";
  } elsif ($q->param('current')) {
    # Faults within the last 14 days
    $xml = $currentxml;
    $title = "Displaying faults with any activity in the last 14 days";
  } else {
    # Initial display of query page
    $xml = "<FaultQuery>".
      OMP::CGI::Fault::category_xml( $cookie{category} ).
	"<date delta='-7'>" . $t->datetime . "</date></FaultQuery>";
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
    fault_summary_content($q, $faults, $mindate, $maxdate);
  } elsif ($faults->[0]) {
    OMP::CGI::Fault::titlebar($q, ["View Faults", $title], %cookie);

    OMP::CGI::Fault::query_fault_form($q, $hidefields, %cookie);
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
      my $sort_url = OMP::CGI::Fault::url_args($q, "sort_order", "ascending", "descending");
      print "Showing oldest first | <a href='$sort_url'>Show most recent first</a>";
    } else {
      my $sort_url = OMP::CGI::Fault::url_args($q, "sort_order", "descending", "ascending");
      print "<a href='$sort_url'>Show oldest first</a> | Showing most recent first";
    }
    print "<br>";

    # Link to this script with an argument to alter sort criteria
    if ($q->param('orderby') eq "filedate") {
      my $url = OMP::CGI::Fault::url_args($q, "orderby", "filedate", "response");
      print "Sorted by date filed | <a href='$url'>Sort by date of latest response</a>"
    } else {
      my $url = OMP::CGI::Fault::url_args($q, "orderby", "response", "filedate");
      print "<a href='$url'>Sort by file date</a> | Sorted by date of latest response";
    }


    print "<p>";

    my %showfaultargs = (CGI => $q,
			 faults => $faults,
			 showcat => ($cookie{category} ne 'ANYCAT' ? 0 : 1),
			);
    
    if ($q->param('orderby') eq 'response' or ! $q->param('orderby')) {
      $showfaultargs{orderby} = 'response';
    } elsif ($q->param('orderby') eq 'filedate') {
      $showfaultargs{orderby} = 'filedate';
    }
    
    if ($faults->[0]) {
      unless ($q->param('sort_order') eq "ascending" or $cookie{sort_order} eq "ascending") {
	$showfaultargs{descending} = 1;
      }

      OMP::CGI::Fault::show_faults(%showfaultargs);

      # Faults to print
      my @faultids = map{$_->id} @$faults;
      
      OMP::CGI::Fault::print_form($q, 1, @faultids);
      
      # Put up the query form again if there are lots of faults displayed
      if ($faults->[15]) {
	print "<P>";
	OMP::CGI::Fault::query_fault_form($q, $hidefields, %cookie);
      }
    }
  } else {
    OMP::CGI::Fault::titlebar($q, ["View Faults", $title], %cookie);
    OMP::CGI::Fault::query_fault_form($q, $hidefields, %cookie);
  }
}

=item B<query_fault_form>

Create a form for querying faults.  First argument is the CGI object.
If the second argument is true, no fields are provided for selecting
system/type (useful for non-category specific fault queries). Final
argument is a cookie hash.

  query_fault_form($cgi, $hidesystype, %cookie);

=cut

sub query_fault_form {
  my $q = shift;
  my $hidefields = shift;
  my %cookie = @_;

  my $systems;
  my $types;
  my @systems;
  my @types;
  my %syslabels;
  my %typelabels;

  if (! $hidefields) {
    $systems = OMP::Fault->faultSystems($cookie{category});
    @systems = map {$systems->{$_}} sort keys %$systems;
    unshift( @systems, "any" );
    %syslabels = map {$systems->{$_}, $_} %$systems;
    $syslabels{any} = 'Any';

    $types = OMP::Fault->faultTypes($cookie{category});
    @types = map {$types->{$_}} sort keys %$types;
    unshift( @types, "any");
    %typelabels = map {$types->{$_}, $_} %$types;
    $typelabels{any} = 'Any';
  }

  my %status = OMP::Fault->faultStatus;
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
  print "</b></td><tr><td colspan=2>";

  if (! $hidefields) {
    print "<b>System </b>";
    print $q->popup_menu(-name=>'system',
			 -values=>\@systems,
			 -labels=>\%syslabels,
			 -default=>'any',);
    print "<b>Type </b>";
    print $q->popup_menu(-name=>'type',
			 -values=>\@types,
			 -labels=>\%typelabels,
			 -default=>'any',);
  }

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

  # Return chronic faults checkbox
  print "<br>";
  print $q->checkbox(-name=>'chronic',
		     -value=>'true',
		     -label=>'Return chronic faults only',
		     -checked=>0,);

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
    OMP::CGI::Fault::view_fault_form($q);
  } else {
    # Got the fault ID, so display the fault
    my $fault = OMP::FaultServer->getFault($faultid);

    # Don't go any further if we got undef back instead of a fault
    if (! $fault) {
      print "No fault with ID of [$faultid] exists.";
      OMP::CGI::Fault::view_fault_form($q);
      return;
    }

    # Send the fault to a printer if print button was clicked
    if ($q->param('print')) {
      my $printer = $q->param('printer');
      my @fprint = split(',',$q->param('faults'));

      OMP::FaultUtil->print_faults($printer, 0, @fprint);
      OMP::CGI::Fault::titlebar($q, ["View Fault: $faultid", "Fault sent to printer $printer"], %cookie);
      return;
    }

    # If the user is "logged in" to the report problem system
    # make sure they can only see problem reports and not faults
    # for other categories.
    if ($cookie{category} =~ /bug/i and $fault->category ne "BUG") {
      print "[$faultid] is not a problem report.";
      return;
    }

    OMP::CGI::Fault::titlebar($q, ["View Fault: $faultid", $fault->subject], %cookie);
    OMP::CGI::Fault::fault_table($q, $fault);

    print "<br>";

    # Show form for printing this fault
    my @faults = ($fault->id);
    OMP::CGI::Fault::print_form($q, 0, @faults);

    # Response form
    print "<p><b><font size=+1>Respond to this fault</font></b>";
    OMP::CGI::Fault::response_form(cgi => $q,
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
      OMP::CGI::Fault::response_form(cgi => $q,
				     cookie => \%cookie,
				     fault => $fault,);
      OMP::CGI::Fault::fault_table($q, $fault);
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
      OMP::CGI::Fault::titlebar($q, ["View Fault ID: $faultid", join('<br>',@title)], %cookie);
      OMP::CGI::Fault::response_form(cgi => $q,
				     cookie => \%cookie,
				     fault => $fault,);
      OMP::CGI::Fault::fault_table($q, $fault);
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

  OMP::CGI::Fault::titlebar($q, ["View Fault ID: $faultid", join('<br>',@title)], %cookie);

  OMP::CGI::Fault::fault_table($q, $fault);
  print "<br>";

  # Form for printing
  my @faults = ($fault->id);
  OMP::CGI::Fault::print_form($q, 0, @faults);
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

    OMP::CGI::Fault::titlebar($q, ["Update Fault [$faultid]"], %cookie);

    # Get the fault
    my $fault = OMP::FaultServer->getFault($faultid);

    # Form for taking new details.  Displays current values.
    OMP::CGI::Fault::file_fault_form(cgi => $q,
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
  my %newdetails = OMP::CGI::Fault::parse_file_fault_form($q);

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

  OMP::CGI::Fault::titlebar($q, ["Update Fault [". $fault-> id ."]", join('<br>',@title)], %cookie);

  # Display the fault
  OMP::CGI::Fault::fault_table($q, $fault);
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
    OMP::CGI::Fault::titlebar($q, ["Update Response [$faultid]"], %cookie);

    # Get the fault
    my $fault = OMP::FaultServer->getFault($faultid);

    (! $fault) and croak "Unable to retrieve fault with ID [$faultid]\n";

    # Form for taking new details.  Displays current values.
    OMP::CGI::Fault::response_form(cgi => $q,
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

  OMP::CGI::Fault::titlebar($q, \@title, %cookie);

  # Redisplay fault
  $fault = OMP::FaultServer->getFault($faultid);

  OMP::CGI::Fault::fault_table($q, $fault);
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
  my %typeID; # IDs used to identify table rows that belong to a particular type
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
      $sysID{$_->systemText} = sprintf("%08d",$_->system) . "sys";
    }

    $typeID{$_->typeText} = sprintf("%08d",$_->type) . "type";
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

	my $rowID = $sysID{$system} . "_" . $typeID{$type};

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

=head1 SEE ALSO

C<OMP::CGI::Fault>, C<OMP::CGI::Project>

=head1 AUTHOR

Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>,

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
