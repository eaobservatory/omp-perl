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

use OMP::Fault;
use OMP::FaultServer;
use OMP::Fault::Response;
use OMP::DBbackend;
use OMP::Error qw(:try);

use vars qw/@ISA %EXPORT_TAGS @EXPORT_OK/;

require Exporter;

$| = 1;

@ISA = qw/Exporter/;

@EXPORT_OK = (qw/file_fault file_fault_output query_fault query_fault_output/);

%EXPORT_TAGS = (
		'all' =>[ @EXPORT_OK ],
	       );

Exporter::export_tags(qw/ all /);

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
  print "<td align=right><b>User:</b></td><td>";
  print $q->textfield(-name=>'user',
		      -size=>'16',
		      -maxlength=>'90',);
  print "</td><tr><td align=right><b>System:</b></td><td>";
  print $q->popup_menu(-name=>'system',
		       -values=>\@system_values,
		       -default=>\@system_values[0],
		       -labels=>\%system_labels,);
  print "</td><tr><td align=right><b>Type:</b></td><td>";
  print $q->popup_menu(-name=>'type',
		       -values=>\@type_values,
		       -default=>\@type_values[0],
		       -labels=>\%type_labels,);
  print "</td><tr><td align=right><b>Subject:</b></td><td>";
  print $q->textfield(-name=>'subject',
		      -size=>'65',
		      -maxlength=>'256',);
  print "</td><tr><td colspan=2>";
  print $q->textarea(-name=>'message',
		     -rows=>20,
		     -columns=>72,);
  print "</td><tr><td colspan=2 align=right>";
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

  # Create the fault object;
  my %status = OMP::Fault->faultStatus;

  my $resp = new OMP::Fault::Response(author=>$q->param('user'),
				      text=>$q->param('message'),);

  my $fault = new OMP::Fault(category=>"OMP",
			     subject=>$q->param('subject'),
			     system=>$q->param('system'),
			     type=>$q->param('type'),
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

  # Color code the status
  my $statushtml;
  $fault->isOpen and $statushtml = "<b><font color=#008b24>Open</font></b>"
    or "<b><font color=#a00c0c>Closed</font></b>";

  # First show the fault info
  print "<table bgcolor=#ffffff cellspacing=3 width=620>";
  print "<tr bgcolor=#ffffff><td><b>Report by: </b>" . $fault->author . "</td><td><b>System: </b>" . $fault->systemText . "</td>";
  print "<tr bgcolor=#ffffff><td><b>Date filed: </b>" . $fault->date . "</td><td><b>Fault type: </b>" . $fault->typeText . "</td>";
  print "<tr bgcolor=#ffffff><td><b>Loss: </b>" . $fault->timelost . "</td><td><b>Urgency: </b>" . $fault->urgency . "</td>";
  print "<tr bgcolor=#ffffff><td><b>Actual time of failure: </b>" . $fault->faultdate . "</td><td><b>Status: </b>$statushtml</td>";
  print "<tr bgcolor=#ffffff><td colspan=2><b>Subject: </b>" . $fault->subject . "</td>";

  # Then loop through and display each response
#  my @responses = $fault->responses;
#  for my $resp (@responses) {
#    print
#  }
  print "</table>";
}

=item B<query_fault>

Create a page for querying faults

  query_fault($cgi);

=cut

sub query_fault {
  my $q = shift;

  print "<table><tr><td align=right><b>Fault ID: </b></td><td>";
  print $q->startform;
  print $q->textfield(-name=>'faultid',
		      -size=>'22',
		      -maxlength=>'90');
  print "</td><tr><td colspan=2 align=right>";
  print $q->submit(-name=>"Submit");
  print $q->endform;
  print "</td></table>";
}

=item B<query_fault_output>

Display a fault

  query_fault_output($cgi);

=cut

sub query_fault_output {
  my $q = shift;
  my $faultid = $q->param('faultid');

  my $fault = OMP::FaultServer->getFault($faultid);
  print $q->h2("Fault ID: $faultid");
  fault_table($q, $fault);
}

=head1 AUTHOR

Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>,

=cut

1;
