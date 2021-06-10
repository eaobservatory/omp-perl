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
use lib "$FindBin::RealBin/../lib";

# Load the servers (but use them locally without SOAP)
use OMP::BaseDB;
use OMP::Config;
use OMP::Constants qw(:fb :logging );
use OMP::DBbackend;
use OMP::FBServer;
use OMP::DateTools;
use OMP::NetTools;
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
    $utdate = OMP::DateTools->yesterday(1);
  } else {
    $utdate = OMP::DateTools->today(1);
  }
} else {
  $utdate = OMP::DateTools->parse_date($utdate);
}

# Get the list of MSBs

_log_message( qq[Getting MSBs for $utdate] );

my $done = OMP::MSBServer->observedMSBs( {date => $utdate,
                                          returnall => 0,
                                          format => 'data'} );

_log_err( $! );

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

  _log_message( qq[Getting project details for $proj] );

  my $proj_details = OMP::ProjServer->projectDetails($proj, "object");

  _log_err( $! );

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

  $msg .= "Observed MSBs\n-----------\n\n";
  $msg .= sprintf "$hfmt\n", "Project", $alt_msb_column, "Instrument",
    "Waveband";

  # UKIRT KLUGE: Find out if project is a UKIRT project
  my $ukirt_proj = ($proj_details->telescope() eq 'UKIRT');

  # Create list of msbs.
  for my $msbid ( @{ $sorted{$proj} } ) {
    # Note that %s does not truncate strings so we have to do that
    # This will be problematic if the format is modified
    $msg .= sprintf "$fmt\n",
      $proj,$msbid->nrepeats,
        substr(($display_msb_name ? $msbid->title : $msbid->target),0,20),
          substr($msbid->instrument,0,20),
            substr($msbid->waveband,0,10);
  }


  # Create the shift log
  my $shiftlog_msg;

  # Query for the telescope's shiftlog if we haven't retrieved it yet
  unless (exists $shiftlog{$proj_details->telescope}) {
    my $sdb = new OMP::ShiftDB( DB => new OMP::DBbackend );

    my $squery_xml = "<ShiftQuery>".
      "<date delta=\"1\">". $utdate ."</date>".
        "<telescope>". $proj_details->telescope ."</telescope>".
          "</ShiftQuery>";

    my $query = new OMP::ShiftQuery( XML => $squery_xml );

    _log_message( qq[Getting shift log for $utdate ] . $proj_details->telescope );

    @{$shiftlog{$proj_details->telescope}} = $sdb->getShiftLogs( $query );

    _log_err( $! );

    # TEMPORARY FIX FOR GARBLED NIGHTREP
    # Strip HTML from comments
    for my $comment (@{$shiftlog{$proj_details->telescope}}) {
      my $text = $comment->text;
      $text =~ s!</*\w+\s*.*?>!!sg;
      $comment->text($text);
    }
  }

  $shiftlog_msg .= "\nShift Comments\n--------------\n\n";

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
    $shiftlog_msg .= "  ".$local->strftime("%H:%M %Z") . ": $author\n";
    $shiftlog_msg .= $text ."\n\n";
  }

  # Attach observation log

  _log_message( qq[Making obs group for $proj & $utdate] );

  my $grp = new OMP::Info::ObsGroup(projectid => $proj,
                                    date => $utdate,
                                    inccal => 0,);

  _log_err( $! );

  my $summary = $grp->summary('72col');
  defined $summary or $summary = '';

  my $obslog_msg = "";
  $obslog_msg .= "\nObservation Log\n---------------\n\n";
  $obslog_msg .= $summary;


  # if UKIRT, but shiftlog before obslog. For JCMT, put obslog before shiftlog.
  if ($ukirt_proj) {
     $msg .= $shiftlog_msg . $obslog_msg;
  } else {
     $msg .= $obslog_msg . $shiftlog_msg;
  }

  my $status = OMP__FB_IMPORTANT;


  my $datestr = $utdate->ymd;


  my $tel = $ukirt_proj ? "UKIRT" : "JCMT";

  my $omp_url = OMP::Config->getData('omp-url') . OMP::Config->getData('cgidir');

  my $jcmt_text = "<html><p>Data were obtained for your $tel project $proj on date $datestr. Please check the quality of these observations promptly and contact your Friend of Project immediately if there are any problems or if they do not meet your requirements.</p><p>You can retrieve your raw data, and calibration/pointing observations from this night, via the <a href=\"${omp_url}/projecthome.pl?project=$proj\">OMP feedback system</a> or directly from the <a href=\"https://www.cadc-ccda.hia-iha.nrc-cnrc.gc.ca/en/search/?Observation.proposal.id=$proj&Observation.collection=JCMT\">CADC JCMT Science Archive</a>.</p>\n<p>The password required for accessing the OMP is the same one you used when submitting your science program MSBs through the Observing Tool.  You also need a CADC username and password, and to have provided those to your Friend of Project.</p>\n\n<p>Pipeline processed data from this night should be available within 24 hours directly from CADC.</p>\n\n";

  # UKIRT KLUGE: Provide a different message for UKIRT users
  my $ukirt_text = "<html><p>Data were obtained for your project on date $datestr.\nFor more details log in to the <a href=\"${omp_url}/projecthome.pl\">OMP feedback system</a></p><p>The password required to log in is the same one you used when submitting your programme.</p>\n\n";

  # Get the appropriate text for jcmt or ukirt projects.
  my $fixed_text = $ukirt_proj ? $ukirt_text : $jcmt_text;
  my $fullmessage = "$fixed_text<p><b>Observing Summary for $datestr</b><p><pre>\n$msg\n</pre>\n";

  # If we are in debug mode just send to stdout. Else
  # contact feedback system
  if ($debug) {
    print $fullmessage;
    print "\nStatus: $status\n";

  } else {
    # Provide a feedback comment informing project users that data has been obtained
    (undef, my $host, undef) = OMP::NetTools->determine_host;
    _log_message( qq[Adding comment for $proj (host: $host, status: $status)] );

    # The feedback comment is too long to add to the feedback system
    # -- it makes the web page unusable. instead send it directly to the users.

    my @contacts = $proj_details->contacts;

    my $basedb = new OMP::BaseDB(DB => new OMP::DBbackend,);
    my $flexuser = OMP::User->get_flex();

    # This line is copied from the FeedbackDB::addComment method.
    my $message_formatted = OMP::Display->preify_text($fullmessage);

    _log_message( qq[Sending email for $proj, $utdate] );

    $basedb->_mail_information( to => \@contacts,
                                from => $flexuser,
                                subject => "[$proj] $tel data obtained for project on " . $utdate->ymd,
                                message => $message_formatted,
                              );


 }

}

sub _log_message {

  my ( $text ) = @_;

  OMP::General->log_message( qq[observed: $text], OMP__LOG_INFO );
  return;
}

sub _log_err {

  my ( @e ) = @_;

  @e = grep { defined $_ && length $_ } @e;

  return unless scalar @e;

  OMP::General->log_message( qq[observed: Possible errors: ] . join( "\n" , @e ),
                             OMP__LOG_ERROR
                            );
  return;
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

