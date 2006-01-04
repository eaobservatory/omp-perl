#!/local/perl/bin/perl

=head1 NAME

observed - Determine what has been observed and contact the feedback system

=head1 SYNOPSIS

  observed [YYYYMMDD]
  observed --debug

=head1 DESCRIPTION

Queries the MSB server to determine the details of all MSBs observed
on the supplied UT date. This information is then sorted by project
ID and sent to the feedback system.

If a UT date is not supplied the current date is assumed.

Usually run via a cron job every night.

=head1 ARGUMENTS

The following arguments are allowed:

=over 4

=item B<date>

If supplied, the date should be in YYYYMMDD or YYYY-MM-DD format.

=back

=head1 OPTIONS

The following options are supported:

=over 4

=item B<-help>

A help message.

=item B<-man>

This manual page.

=item B<-debug>

Do not send messages to the feedback system. Send all messages
to standard output.

=item B<-yesterday>

If no date is supplied, default to the date for yesterday
An error is thrown if a date is also supplied.

=back

=cut

use warnings;
use strict;

use Pod::Usage;
use Getopt::Long;

# Add to @INC for OMP libraries.
use FindBin;
use lib "$FindBin::RealBin/..";

# Load the servers (but use them locally without SOAP)
use OMP::BaseDB;
use OMP::Config;
use OMP::Constants qw(:fb);
use OMP::DBbackend;
use OMP::FBServer;
use OMP::General;
use OMP::Info::ObsGroup;
use OMP::MSBServer;
use OMP::ProjServer;
use OMP::ShiftDB;
use OMP::ShiftQuery;
use OMP::User;

use Text::Wrap;
use Time::Piece;

# Options
my ($help, $man, $debug, $yesterday);
my $optstatus = GetOptions("help" => \$help,
			   "man" => \$man,
			   "debug" => \$debug,
			   "yesterday" => \$yesterday,
			  );

pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

# Get the UT date
my $utdate = shift(@ARGV);

die "Can not specify both a date [$utdate] and the -yesterday flag\n"
  if ($yesterday && defined $utdate);

# Default the date
if (!$utdate) {
  if ($yesterday) {
    $utdate = OMP::General->yesterday(1);
  } else {
    $utdate = OMP::General->today(1);
  }
}

# Get the list of MSBs
my $done = OMP::MSBServer->observedMSBs( {date => $utdate,
					  returnall => 0,
					  format => 'data'} );

# Now sort by project ID
my %sorted;
for my $msbid (@$done) {

  # Get the project ID
  my $projectid = $msbid->projectid;

  # Create a new entry in the hash if this is new ID
  $sorted{$projectid} = [] unless exists $sorted{$projectid};

  # Push this one onto the array
  push(@{ $sorted{$projectid} }, $msbid);
}

# Store each telescope's shiftlog
my %shiftlog;

# Now create the comment and send it to feedback system
my $fmt = "%-14s %03d %-20s %-20s %-10s";
my $hfmt= "%-14s Rpt %-20s %-20s %-10s";
for my $proj (keys %sorted) {

  # Each project info is sent independently to the
  # feedback system so we need to construct a message string
  my $msg;

  # Get project object
  my $proj_details = OMP::ProjServer->projectDetailsNoAuth($proj, "object");

  # Include project completion stats
  $msg .= "Your project [". uc($proj) ."] is now ";
  $msg .= sprintf("%.0f%%",$proj_details->percentComplete);
  $msg .= " complete.\n\n";
  $msg .= "Time allocated: ". $proj_details->allocated->pretty_print . "\n";
  $msg .= "Time remaining: ".
    ($proj_details->allRemaining->seconds > 0 ? $proj_details->allRemaining->pretty_print : "0") ."\n\n";

  # MSB Summary

  # Decide whether to show MSB targets or MSB name
  my $display_msb_name = OMP::Config->getData( 'msbtabdisplayname',
					       telescope => $proj_details->telescope,);
  my $alt_msb_column = ($display_msb_name ? 'Name' : 'Target');

  $msg .= "MSB Summary\n-----------\n\n";
  $msg .= sprintf "$hfmt\n", "Project", $alt_msb_column, "Instrument",
    "Waveband";

  # UKIRT KLUGE: Find out if project is a WFCAM project
  my $wfcam_proj;
  if ($sorted{$proj}->[0]->instrument eq 'WFCAM') {
    $wfcam_proj = 1;
  }

  for my $msbid ( @{ $sorted{$proj} } ) {
    # Note that %s does not truncate strings so we have to do that
    # This will be problematic if the format is modified
    $msg .= sprintf "$fmt\n",
      $proj,$msbid->nrepeats,
	substr(($display_msb_name ? $msbid->title : $msbid->target),0,20),
	  substr($msbid->instrument,0,20),
	    substr($msbid->waveband,0,10);
  }

  # Attach shift log
  # Query for the telescope's shiftlog if we haven't retrieved it yet
  unless (exists $shiftlog{$proj_details->telescope}) {
    my $sdb = new OMP::ShiftDB( DB => new OMP::DBbackend );

    my $squery_xml = "<ShiftQuery>".
      "<date delta=\"1\">". $utdate ."</date>".
	"<telescope>". $proj_details->telescope ."</telescope>".
	  "</ShiftQuery>";

    my $query = new OMP::ShiftQuery( XML => $squery_xml );

    @{$shiftlog{$proj_details->telescope}} = $sdb->getShiftLogs( $query );

    # TEMPORARY FIX FOR GARBLED NIGHTREP
    # Strip HTML from comments
    for my $comment (@{$shiftlog{$proj_details->telescope}}) {
      my $text = $comment->text;
      $text =~ s!</*\w+\s*.*?>!!sg;
      $comment->text($text);
    }
  }

  $msg .= "\nShift Comments\n--------------\n\n";

  $Text::Wrap::columns = 72;
  for my $comment (@{$shiftlog{$proj_details->telescope}}) {
    # Use local time
    my $date = $comment->date;
    my $local = localtime( $date->epoch );
    my $author = $comment->author->name;

    # Get the text and format it
    my $text = $comment->text;

    # Really need to convert HTML to text using general method
    $text =~ s/\&apos\;/\'/g;
    $text =~ s/<BR>/\n/gi;

    # Word wrap
    $text = wrap("    ","    ",$text);

    # Now print the comment
    $msg .= "  ".$local->strftime("%H:%M %Z") . ": $author\n";
    $msg .= $text ."\n\n";
  }

  # Attach observation log
  my $grp = new OMP::Info::ObsGroup(projectid => $proj,
				    date => $utdate,
				    inccal => 0,);

  $grp->locate_timegaps( OMP::Config->getData("timegap") );

  $msg .= "\nObservation Log\n---------------\n\n";
  $msg .= $grp->summary('72col');

  ### TEMPORARILY, if this is a UKIRT project make the comment hidden
  #my $details = OMP::ProjServer->projectDetails($proj, "***REMOVED***", "object");
  my $status = OMP__FB_IMPORTANT;

  # If we are in debug mode just send to stdout. Else
  # contact feedback system
  if ($debug) {
    print $msg;
    print "\nStatus: $status\n";

  } else {
    my ($user, $host, $email) = OMP::General->determine_host;

    my $fixed_text = "<html><p>Data was obtained for your project on date $utdate.\nYou can retrieve it from the <a href=\"http://omp.jach.hawaii.edu/cgi-bin/projecthome.pl\">OMP feedback system</a></p><p>The password required for data retrieval is the same one you used when submitting your programme.  If you have forgotten your password go to the <a href=\"http://omp.jach.hawaii.edu\">OMP home page</a> and click on the \"Issue password\" link to issue yourself a new password.</p>\n\n";

    # UKIRT KLUGE: Provide a different message for WFCAM users
    my $wfcam_text = "<html><p>Data was obtained for your project on date $utdate.\nFor more details log in to the <a href=\"http://omp.jach.hawaii.edu/cgi-bin/projecthome.pl\">OMP feedback system</a></p><p>The password required to log in is the same one you used when submitting your programme.  If you have forgotten your password go to the <a href=\"http://omp.jach.hawaii.edu\">OMP home page</a> and click on the \"Issue password\" link to issue yourself a new password.</p>\n\n";

    if ($wfcam_proj) {
      $fixed_text = $wfcam_text;
    }

    # Provide a feedback comment informing project users that data has been obtained
    OMP::FBServer->addComment(
			      $proj,
			      {
			       author => undef, # this is done by cron
			       subject => "Data obtained for project on ". $utdate->ymd,
			       program => "observed.pl",
			       sourceinfo => $host,
			       status => $status,
#			       text => "$fixed_text<pre>\n$msg\n</pre>\n",
			       text => "$fixed_text\n",
			      }
			     );

    # Email the detailed log to the project users

    # Get project contacts
    my @contacts = $proj_details->contacts;

    my $basedb = new OMP::BaseDB(DB => new OMP::DBbackend,);

    my $flexuser = OMP::User->new(email=>'flex\@jach.hawaii.edu');

    $basedb->_mail_information( to => \@contacts,
				from => $flexuser,
				subject => "[$proj] Project log for $utdate",
				message => "$msg\n",
			      );

 }

}


=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2002-2005 Particle Physics and Astronomy Research Council.
All Rights Reserved.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful,but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc., 59 Temple
Place,Suite 330, Boston, MA  02111-1307, USA

=cut

