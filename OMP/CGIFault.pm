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
use OMP::Error qw(:try);

use vars qw/@ISA %EXPORT_TAGS @EXPORT_OK/;

require Exporter;

$| = 1;

@ISA = qw/Exporter/;

@EXPORT_OK = (qw/file_fault file_fault_output query_fault_content query_fault_output view_fault_content view_fault_output/);

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

  # Create values and labels for the popup_menus
  my $systems = OMP::Fault->faultSystems("OMP");
  my @system_values = map {$systems->{$_}} sort keys %$systems;
  my %system_labels = map {$systems->{$_}, $_} keys %$systems;

  my $types = OMP::Fault->faultTypes("OMP");
  my @type_values = map {$types->{$_}} sort keys %$types;
  my %type_labels = map {$types->{$_}, $_} keys %$types;

  print $q->h2("File Fault");
  print "<table border=0 cellspacing=4><tr>";
  print $q->startform;

  # Need the show_output param in order for the output code ref to be called next
  print $q->hidden(-name=>'show_output',
		   -default=>'true');

  print "<td align=right><b>User:</b></td><td>";
  print $q->textfield(-name=>'user',
		      -size=>'16',
		      -maxlength=>'90',);
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
  print "</td><tr><td colspan=4><b>";
  print $q->checkbox(-name=>'urgency',
		     -value=>'urgent',
		     -label=>"This fault is urgent");
  print "</b></td><tr><td colspan=2 align=right>";
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

  my %status = OMP::Fault->faultStatus;

  my $urgency;
  my %urgency = OMP::Fault->faultUrgency;
  if ($q->param('urgency') =~ /urgent/) {
    $urgency = $urgency{Urgent};
  } else {
    $urgency = $urgency{Normal};
  }

  my $resp = new OMP::Fault::Response(author=>$q->param('user'),
				      text=>$q->param('message'),);

  # Create the fault object
  my $fault = new OMP::Fault(category=>"OMP",
			     subject=>$q->param('subject'),
			     system=>$q->param('system'),
			     type=>$q->param('type'),
			     timelost=>$q->param('loss'),
			     urgency=>$urgency,
			     fault=>$resp);

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
    print $q->h2("Fault $faultid was successfully filed");
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

  my $statushtml;
  $fault->isOpen and $statushtml = "<b><font color=#008b24>Open</font></b>"
    or "<b><font color=#a00c0c>Closed</font></b>";

  # First show the fault info
  print "<table bgcolor=#ffffff cellpadding=3 cellspacing=0 border=0 width=$TABLEWIDTH>";
  print "<tr bgcolor=#ffffff><td><b>Report by: </b>" . $fault->author . "</td><td><b>System: </b>" . $fault->systemText . "</td>";
  print "<tr bgcolor=#ffffff><td><b>Date filed: </b>" . $fault->date . "</td><td><b>Fault type: </b>" . $fault->typeText . "</td>";
  print "<tr bgcolor=#ffffff><td><b>Loss: </b>" . $fault->timelost . " hours</td><td><b>Status: </b>$statushtml</td>";
  print "<tr bgcolor=#ffffff><td><b>Actual time of failure: </b>$faultdate</td><td>$urgencyhtml</td>";
  print "<tr bgcolor=#ffffff><td colspan=2><b>Subject: </b>$subject</td>";

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
      print "<tr bgcolor=$bgcolor><td><b>Response by: </b>" . $resp->author . "</td><td><b>Date: </b>" . $resp->date . "</td>";
    }

    # Show the response
    print "<tr bgcolor=$bgcolor><td colspan=2><table border=0><tr><td><font color=$bgcolor>___</font></td><td>" . $resp->text . "</td></table><br></td>";

  }
  print "</table>";
}

=item B<query_fault>

Create a page for querying faults

  query_fault($cgi);

=cut

sub query_fault_content {
  my $q = shift;

  print $q->h2("Fault Search");

  query_fault_form($q);
  print "<p>";

  # Display recent faults
  my $t = gmtime;
  my $xml = "<FaultQuery><date delta='-36' units='hours'>" . $t->datetime . "</date><isfault>1</isfault></FaultQuery>";

  my $faults;
  try {
    $faults = OMP::FaultServer->queryFaults($xml, "object");
    return $faults;
  } otherwise {
    my $E = shift;
    print "$E";
  };

  if ($faults->[0]) {
    show_faults($q, $faults);

    # Put up the query form again if there are lots of faults displayed
    if ($faults->[15]) {
      print "<P>";
      query_fault_form($q);
    }
  }
}

=item B<query_fault_output>

Display a fault

  query_fault_output($cgi);

=cut

sub query_fault_output {
  my $q = shift;

  # Which XML query are we going to use?
  # and which title are we displaying?
  my $title;
  my $t = gmtime;
  my $delta;
  my $xml;

  # The 'Submit' submit button was clicked
  if ($q->param('Submit')) {
    $delta = $q->param('days');
    my $xmlpiece;

    if ($q->param('search') =~ /response/) {
      $xmlpiece = "<isfault>0</isfault>";
      $title = "Displaying faults responded to in the last $delta days";
    } elsif ($q->param('search') =~ /file/) {
      $xmlpiece = "<isfault>1</isfault>";
      $title = "Displaying faults filed in the last $delta days";
    } else {
      $title = "Displaying faults with any activity in the last $delta days";
    }
    $xml = "<FaultQuery><date delta='-$delta'>" . $t->datetime . "</date>$xmlpiece</FaultQuery>";

  } else {
    # One of the other submit buttons was clicked
    if ($q->param('Major faults')) {
      # Faults within the last 14 days with 2 or more hours lost
      $xml = "<FaultQuery><date delta='-14'>" . $t->datetime . "</date><timelost><min>2</min></timelost></FaultQuery>";
      $title = "Displaying major faults";
    } elsif ($q->param('Recent faults')) {
      # Faults filed in the last 36 hours
      $xml = "<FaultQuery><date delta='-36' units='hours'>" . $t->datetime . "</date><isfault>1</isfault></FaultQuery>";
      $title = "Displaying recent faults";
    } elsif ($q->param('Current faults')) {
      # Faults within the last 14 days that are 'OPEN'
      my %status = OMP::Fault->faultStatus;
      $xml = "<FaultQuery><date delta='-14'>" . $t->datetime . "</date><status>$status{OPEN}</status></FaultQuery>";
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

  print $q->h2($title);

  query_fault_form($q);
  print "<p>";

  if ($faults->[0]) {
    show_faults($q, $faults);

    # Put up the query form again if there are lots of faults displayed
    if ($faults->[15]) {
      print "<P>";
      query_fault_form($q);
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

  print "<table cellspacing=0 cellpadding=3 border=0 bgcolor=#dcdcf2><tr><td>";
  print $q->startform;
  print "<b>Display faults for the last ";
  print $q->textfield(-name=>'days',
		      -size=>3,
		      -maxlength=>5);
  print " days</b></td><tr><td><b>";
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
    print $q->h2("Fault ID: $faultid");
    fault_table($q, $fault);
    print "<p><b><font size=+1>Respond to this fault</font></b>";
    response_form($q, $fault->id);
  }
}

=item B<view_fault_output>

Parse any forms of the view_fault_content forms

  view_fault_output($cgi);

=cut

sub view_fault_output {
  my $q = shift;
  my $faultid = $q->param('faultid');
  my $author = $q->param('user');
  my $text = $q->param('text');

  my $fault = OMP::FaultServer->getFault($faultid);

  try {
    my $resp = new OMP::Fault::Response(author => $author,
				        text => $text);
    OMP::FaultServer->respondFault($fault->id, $resp);
    print $q->h2("Fault response successfully submitted");
  } otherwise {
    my $E = shift;
    print "An error had prevented your response from being filed: $E";
  };

  $fault = OMP::FaultServer->getFault($faultid);
  fault_table($q, $fault);
}

=item B<response_form>

Create a form for submitting a response

  response_form($cgi, $faultid);

=cut

sub response_form {
  my $q = shift;
  my $faultid = shift;

  print "<table border=0><tr><td align=right><b>User: </b></td><td>";
  print $q->startform;
  print $q->hidden(-name=>'show_output', -default=>['true']);
  print $q->hidden(-name=>'faultid', -default=>$faultid);
  print $q->textfield(-name=>'user',
		      -size=>'25',
		      -maxlength=>'75');
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

  show_faults($cgi, $faults)

Takes a reference to an array of fault objects as the second argument

=cut

sub show_faults {
  my $q = shift;
  my $faults = shift;

  print "<table width=$TABLEWIDTH cellspacing=0>";
  print "<tr><td><b>Fault ID</b></td><td><b>User</b></td><td><b>System</b></td><td><b>Type</b></td><td><b>Subject</b></td>";
  my $colorcount;
  for my $fault (@$faults) {
    my $bgcolor;

    $colorcount++;
    if ($colorcount == 1) {
      $bgcolor = '#6161aa'; # darker
    } else {
      $bgcolor = '#8080cc'; # lighter
      $colorcount = 0;
    }

    my $faultid = $fault->id;
    my $user = $fault->author;
    my $system = $fault->systemText;
    my $type = $fault->typeText;
    my $subject = $fault->subject;

    print "<tr bgcolor=$bgcolor><td><b><a href='viewfault.pl?id=$faultid'>$faultid</b></td>";
    print "<td>$user</td>";
    print "<td>$system</td>";
    print "<td>$type</td>";
    print "<td>$subject &nbsp;</td>";
  }

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
