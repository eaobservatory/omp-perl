package OMP::CGI::Fault;

=head1 NAME

OMP::CGI::Fault - Helper for the OMP fault CGI scripts

=head1 SYNOPSIS

  use OMP::CGI::Fault;
  use OMP::CGI::Fault qw/file_fault/;

=head1 DESCRIPTION

Provide functions to generate and display components of fault
system web pages.

=cut

use 5.006;
use strict;
use warnings;
use Carp;
our $VERSION = (qw$ Revision: 1.2 $ )[1];

use Text::Wrap;

use OMP::Config;
use OMP::General;
use OMP::Fault;
use OMP::FaultDB;
use OMP::FaultUtil;
use OMP::FaultStats;
use OMP::Display;
use OMP::FaultServer;
use OMP::MSBServer;
use OMP::UserServer;
use OMP::KeyServer;
use OMP::Error qw(:try);

use vars qw/@ISA %EXPORT_TAGS @EXPORT_OK/;

require Exporter;

$| = 1;

@ISA = qw/Exporter/;

@EXPORT_OK = (qw/fault_table response_form show_faults fault_summary_form/);

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
		 urgency => undef,
		 condition => undef,);

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

    # Is this fault marked chronic?
    my $chronic = ($fault->conditionText =~ /chronic/i ? "chronic" : undef);

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
		 urgency => $urgent,
		 condition => $chronic,);

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

  print "</td><tr><td colspan='2'><b>";

  # Setup condition checkbox group.  If the fault already exists,
  # allow user to indicate whether or not the fault is chronic
  my @convalues = ('urgent');
  my %conlabels = (urgent => "Urgent");
  my @condefaults = ($defaults{urgency});
  if ($fault) {
    if ($fault->id) {
      push @convalues, "chronic";
      $conlabels{chronic} = "Chronic";
      push @condefaults, $defaults{condition};
    }
  }

  # Even though there is only a single option for urgency I'm using a checkbox group
  # since it's easier to set a default this way
  print "This fault is ";
  print $q->checkbox_group(-name=>'condition',
			   -values=>\@convalues,
			   -labels=>\%conlabels,
			   -defaults=>\@condefaults,);

  print "</b></td><tr><td colspan='2' align=right>";
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

=item B<show_faults>

Show a list of faults

  show_faults(CGI => $cgi, 
	      faults => $faults,
	      orderby => 'response',
	      descending => 1,
	      url => "fbfault.pl"
              showcat => 1,);

Takes the following key/value pairs as arguments:

CGI: A C<CGI> query object
faults: A reference to an array of C<OMP::Fault> objects
descending: If true faults are listed in descending order
url: The absolute or relative path to the script to be used for the view/respond link
orderby: Should be either 'response' (to sort by date of latest response) or 'filedate'
showcat: true if a category column should be displayed

Only the B<CGI> and B<faults> keys are required.


=cut

sub show_faults {
  my %args = @_;
  my $q = $args{CGI};
  my $faults = $args{faults};
  my $descending = $args{descending};
  my $url = $args{url};
  my $showcat = $args{showcat};

  (! $url) and $url = "viewfault.pl";

  # Generate stats so we can decide to show fields like "time lost"
  # only if any faults have lost time
  my $stats = new OMP::FaultStats( faults => $faults );

  print "<table width=$TABLEWIDTH cellspacing=0>";
  print "<tr>";

  # Show category column?
  print "<td><b>Category</b></td>"
    unless (! $showcat);

  print "<td><b>ID</b></td><td><b>Subject</b></td><td><b>Filed by</b></td><td><b>System</b></td><td><b>Type</b></td><td><b>Status</b></td>";


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

    print "<tr bgcolor=$bgcolor>";

    # Show category column?
    print "<td>". $fault->category ."</td>"
      unless (! $showcat);

    print "<td>$faultid</td>";
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
    $toptitle = ($cookie{category} ne "ANYCAT" ? $cookie{category} : "All") . " Faults";
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

  # Determine urgency and condition
  my @checked = $q->param('condition');
  my %urgency = OMP::Fault->faultUrgency;
  my %condition = OMP::Fault->faultCondition;
  $parsed{urgency} = $urgency{Normal};
  $parsed{condition} = $condition{Normal};

  for (@checked) {
    ($_ =~ /urgent/i) and $parsed{urgency} = $urgency{Urgent};
    ($_ =~ /chronic/i) and $parsed{condition} = $condition{Chronic};
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

=item B<category_xml>

Given a string that is the name of a fault category, return a snippet of xml containing
the named category surrounded by an opening and closing category tag.

  my $xmlpart = category_xml($category);

Returns an empty string if the given category is 'ANYCAT' or if the only argument is undef.

=cut

sub category_xml {
  my $cat = shift;

  if (defined $cat and $cat ne "ANYCAT") {
    return "<category>$cat</category>";
  } else {
    return "";
  }
}

=back

=head1 AUTHOR

Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>,

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
