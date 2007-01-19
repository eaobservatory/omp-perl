package OMP::CGIPage::ObsReport;

=head1 NAME

OMP::CGIPage::ObsReport - Web display of observing reports

=head1 SYNOPSIS

  use OMP::CGIPage::ObsReport;

=head1 DESCRIPTION

Helper methods for creating web pages that display observing
reports.

=cut

use 5.006;
use strict;
use warnings;
use Carp;

use Time::Piece;
use Time::Seconds qw(ONE_DAY);

use OMP::CGIComponent::Weather;
use OMP::Constants qw(:done);
use OMP::DBbackend;
use OMP::General;
use OMP::MSBServer;
use OMP::NightRep;
use OMP::TimeAcctDB;

$| = 1;

=head1 Routines

=over 4

=item B<night_report>

Create a page summarizing activity for a particular night.

  night_report($cgi, %cookie);

=cut

sub night_report {
  my $q = shift;
  my %cookie = @_;

  my $date_format = "%Y-%m-%d";

  my $delta;
  my $utdate;
  my $utdate_end;

  # Get delta and start UT date from multi night form
  if ($q->param('utdate_end')) {
    $utdate = OMP::General->parse_date($q->param('utdate_form'));
    $utdate_end = OMP::General->parse_date($q->param('utdate_end'));

    # Croak if date format is wrong
    croak("The date string provided is invalid.  Please provide dates in the format of YYYY-MM-DD")
      if (! $utdate or ! $utdate_end);

    # Derive delta from start and end UT dates
    $delta = $utdate_end - $utdate;
    $delta = $delta->days + 1;  # Need to add 1 to our delta
                                # to include last day
  } elsif ($q->param('utdate_form')) {
    # Get UT date from single night form
    $utdate = OMP::General->parse_date($q->param('utdate_form'));

    # Croak if date format is wrong
    croak("The date string provided is invalid.  Please provide dates in the format of YYYY-MM-DD")
      if (! $utdate);

  } else {
    # No form params.  Get params from URL

    # Get delta from URL
    if ($q->url_param('delta')) {
      my $deltastr = $q->param('delta');
      if ($deltastr =~ /^(\d+)$/) {
	$delta = $1;
      } else {
	croak("Delta [$deltastr] does not match the expect format so we are not allowed to untaint it!");
      }
    }

    # Get start date from URL
    if ($q->url_param('utdate')) {
      $utdate = OMP::General->parse_date($q->url_param('utdate'));

    # Croak if date format is wrong
    croak("The date string provided is invalid.  Please provide dates in the format of YYYY-MM-DD")
      if (! $utdate);

    } else {
      # No UT date in URL.  Use current date.
      $utdate = OMP::General->today(1);

      # Subtract delta (days) from date if we have a delta
      if ($delta) {
	$utdate -= $delta * ONE_DAY;
      }
    }

    # We need an end date for display purposes
    if ($delta) {
      $utdate_end = $utdate + $delta * ONE_DAY;
      $utdate_end -= ONE_DAY;  # Our delta does not include
                               # the last day
    }
  }

  # Get the telescope from the URL
  my $telstr = $q->url_param('tel');

  # Untaint the telescope string
  my $tel;
  if ($telstr) {
    if ($telstr =~ /^(UKIRT|JCMT)$/i ) {
      $tel = uc($1);
    } else {
      croak("Telescope string [$telstr] does not match the expect format so we are not allowed to untaint it!");
    }
  } else {
    print "Please select a telescope to view observing reports for<br>";
    print "<a href='nightrep.pl?tel=jcmt'>JCMT</a> | <a href='nightrep.pl?tel=ukirt'>UKIRT</a>";
    return;
  }

  # Setup our arguments for retrieving night report
  my %args = (date => $utdate->ymd,
	      telescope => $tel,);
  ($delta) and $args{delta_day} = $delta;

  # Get the night report
  my $nr = new OMP::NightRep(%args);

  if (! $nr) {
    print "<h2>No observing report available for". $utdate->ymd ."at $tel</h2>";
  } else {

    print "<table border=0><td colspan=2>";

    if ($delta) {
      print "<h2 class='title'>Observing Report for ". $utdate->ymd ." to ". $utdate_end->ymd ." at $tel</h2>";
    } else {
      print "<h2 class='title'>Observing Report for ". $utdate->ymd ." at $tel</h2>";
    }

    # Get our current URL
#    my $url = OMP::Config->getData('omp-private') . OMP::Config->getData('cgidir') . "/nightrep.pl";
    my $url = $q->url(-path_info=>1);

    # Display a different form and different links if we are displaying
    # for multiple nights
    if (! $delta) {
      # Get the next and previous UT dates
      my $prevdate = gmtime($utdate->epoch - ONE_DAY);
      my $nextdate = gmtime($utdate->epoch + ONE_DAY);

      # Link to previous and next date reports
      print "</td><tr><td>";

      print "<a href='$url?utdate=".$prevdate->ymd."&tel=$tel'>Go to previous</a>";
      print " | ";
      print "<a href='$url?utdate=".$nextdate->ymd."&tel=$tel'>Go to next</a>";

      print "</td><td align='right'>";

      # Form for viewing another report
      print $q->startform;
      print "View report for ";
      print $q->textfield(-name=>"utdate_form",
			  -size=>10,
			  -default=>substr($utdate->ymd, 0, 8),);
      print "</td><tr><td colspan=2 align=right>";

      print $q->submit(-name=>"view_report",
		       -label=>"Submit",);
      print $q->endform;

      # Link to multi night report
      print "</td><tr><td colspan=2><a href='$url?tel=$tel&delta=7'>Click here to view a report for multiple nights</a>";
      print "</td></table>";
    } else {
      print "</td><tr><td colspan=2>";
     print $q->startform;
      print "View report starting on ";
      print $q->textfield(-name=>"utdate_form",
			  -size=>10,
			  -default=>$utdate->ymd,);
      print " and ending on ";
      print $q->textfield(-name=>"utdate_end",
			  -size=>10,);
      print " UT ";
      print $q->submit(-name=>"view_report",
		       -label=>"Submit",);
      print $q->endform;

      # Link to single night report
      print "</td><tr><td colspan=2><a href='$url?tel=$tel'>Click here to view a single night report</a>";
      print "</td></table>";
    }

    print "<p>";


    # Link to CSO fits tau plot
    my $plot_html = OMP::CGIComponent::Weather::tau_plot_code($utdate);
    ($plot_html) and print "<a href='#taufits'>View tau plot</a><br>";

    # Link to WVM graph
    if (! $utdate_end) {
      print "<a href='#wvm'>View WVM graph</a><br>";
    }

    # Link to seeing plot.
    my $seeing_html = OMP::CGIComponent::Weather::seeing_plot_code( $utdate );
    ($seeing_html) and print "<a href='#seeing'>View seeing graph</a><br>";

    # Link to zeropoint plot.
    my $zeropoint_html = OMP::CGIComponent::Weather::zeropoint_plot_code( $utdate );
    ($zeropoint_html) and print "<a href='#zeropoint'>View zeropoint graph</a><br>";

    $nr->ashtml( worfstyle => 'staff',
                 commentstyle => 'staff', );

    # Display tau plot
    ($plot_html) and print "<p>$plot_html</p>";

    # Display WVM graph
    my $wvm_html;

    if (! $utdate_end) {
      $wvm_html = OMP::CGIComponent::Weather::wvm_graph_code($utdate->ymd);
      print $wvm_html;
    }

    # Display seeing plot.
    ( $seeing_html ) and print "<p>$seeing_html</p>";

    # Display zeropoint plot.
    ( $zeropoint_html ) and print "<p>$zeropoint_html</p>";

  }
}

=item B<nightlog_content>

Create a page summarizing the events for a particular night.  This is not
project specific.

  nightlog_content($q);

=cut

sub nightlog_content {
  my $q = shift;
  my %cookie = @_;

  my $utdatestr = $q->url_param('utdate');

  my $utdate;
  # Untaint the date string
  if ($utdatestr =~ /^(\d{4}-\d{2}-\d{2})$/) {
    $utdate = $1;
  } else {
    croak("UT date string [$utdate] does not match the expect format so we are not allowed to untaint it!");
  }

  print "<h2>Nightly report for $utdate</h2>";

  # Disply time accounting info
  print "<h3>Time accounting information</h3>";

  my $public_url = public_url();

  # Get the time accounting information
  my $acctdb = new OMP::TimeAcctDB(DB => new OMP::DBbackend);
  my @timeacct = $acctdb->getTimeSpent(utdate => $utdate);

  # Put the time accounting info in a table
  print "<table><td><strong>Project ID</strong></td><td><strong>Hours</strong></td>";
  for my $account (@timeacct) {
    my $projectid = $account->projectid;
    my $timespent = $account->timespent;
    my $h = sprintf("%.1f", $timespent->hours);
    my $confirmed = $account->confirmed;
    print "<tr><td>";
    print "<a href='$public_url/projecthome.pl?urlprojid=$projectid'>$projectid</a>";
    print "<td>$h";
    (! $confirmed) and print " [estimated]";
    print "</td>";
  }
  print "</table>";
}

=item B<report_output>

Create a page displaying an observer report.

  report_output($cgi, %cookie);

=cut

sub report_output {
  my $q = shift;
  my %cookie = @_;

  # Get the date, telescope and shift from the URL
  my $date = $q->url_param('date');
  my $shift = $q->url_param('sh')
    unless ($q->url_param('sh') !~ /1|2/);
  my $telescope = $q->url_param('tel');

  my $t = Time::Piece->strptime($date,"%Y%m%d");
#  ($shift eq "1") and $t += 91800          # Set date to end of first shift
#    or $t += 120600;                       # Set date to end of second shift

  # Now get the date in UT
  $t -= $t->tzoffset;

  print "<pre>";
  #  print Dumper($obs);
  print "</pre>";

  print "<h2>Report for $date, $shift shift</h2>";
  print "<h2>Projects Observed</h2>";

  # Get the MSBs observed during this shift sorted by project
  my $xml = "<MSBDoneQuery>".
      "<date delta='-8' units='hours'>". $t->datetime ."</date>".
	# Right now we're specifying the telescope's instruments
	# in the query instead of the telescope since we can't query
	# on telescope yet
	"".
	  "<status>". OMP__DONE_DONE ."</status>".
	    "</MSBDoneQuery>";

  my $commentref = OMP::MSBServer->observedMSBs({});
  msb_comments_by_project($q, $commentref);

  # Get the relative faults

  # Figure out the time lost to faults
}

=back

=head1 AUTHOR

Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2004 Particle Physics and Astronomy Research Council.
All Rights Reserved.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program (see SLA_CONDITIONS); if not, write to the
Free Software Foundation, Inc., 59 Temple Place, Suite 330,
Boston, MA  02111-1307  USA

=cut

1;
