package OMP::CGIPage::Obslog;

=head1 NAME

OMP::CGIPage::Obslog - Disply complete observation log web pages

=head1 SYNOPSIS

use OMP::CGIPage::Obslog;

=head1 DESCRIPTION

This module provides routines for displaying complete web pages
for viewing observation logs and submitting observation log
comments.

=cut

use strict;
use warnings;
use Carp;

use CGI;
use CGI::Carp qw/fatalsToBrowser/;
use Net::Domain qw/ hostfqdn /;
use Time::Seconds qw/ ONE_DAY /;

use OMP::CGIComponent::Obslog;
use OMP::CGIComponent::MSB;
use OMP::CGIComponent::Shiftlog;
use OMP::CGIComponent::Weather;
use OMP::Config;
use OMP::Constants;
use OMP::General;
use OMP::Info::Comment;
use OMP::Info::Obs;
use OMP::Info::ObsGroup;
use OMP::MSBDB;
use OMP::MSBServer;
use OMP::ObslogDB;
use OMP::ProjServer;
use OMP::BaseDB;
use OMP::ArchiveDB;
use OMP::DBbackend::Archive;
use OMP::Error qw/ :try /;

our $VERSION = (qw$Revision$ )[1];

require Exporter;

our @ISA = qw/Exporter/;
our @EXPORT = qw( file_comment file_comment_output projlog_content
		  list_observations list_observations_txt );

our %EXPORT_TAGS = (
                    'all' => [ @EXPORT ]
                    );

Exporter::export_tags(qw/ all /);

# Colours for displaying observation status. First is 'good', second
# is 'questionable', third is 'bad'.
our @colour = ( "BLACK", "#BB3333", "#FF3300" );

=head1 Routines

All routines are exported by default.

=over 4

=item B<file_comment>

Creates a page with a form for filing a comment.

  file_comment( $cgi );

Only argument should be the C<CGI> object.

=cut

sub file_comment {
  my $q = shift;
  my %cookie = @_;
#print "calling file_comment<br>\n";
  # Get the Info::Obs object
  my $obs = cgi_to_obs( $q );

  # Print a summary about the observation.
  obs_summary( $q, $obs );

  # Display a form for adding a comment.
  obs_comment_form( $q, $obs, \%cookie );

  # Print a footer
  print_obscomment_footer( $q );

}

=item B<file_comment_output>

Submit a comment and create a page with a form for filing a comment.

  file_comment_output( $cgi );

Only argument should be the C<CGI> object.

=cut

sub file_comment_output {
  my $q = shift;
  my %cookie = @_;

  # Insert the comment into the database.
  obs_add_comment( $q );

  # Get the updated Info::Obs object.
  my $obs = cgi_to_obs( $q );

  # Print a summary about the observation.
  obs_summary( $q, $obs );

  # Display a form for adding a comment.
  obs_comment_form( $q, $obs, \%cookie );

  # Print a footer
  print_obscomment_footer( $q );

}

=item B<list_observations>

Create a page containing a list of observations.

  list_observations( $cgi );

Only argument should be the C<CGI> object.

=cut

sub list_observations {
  my $q = shift;
  my %cookie = @_;

  print_obslog_header( $q );

  my ($inst, $ut);

  ( $inst, $ut ) = obs_inst_summary( $q, \%cookie );

  my $tempinst;
  if( $inst =~ /rxa/i ) { $tempinst = "rxa3"; }
  elsif( $inst =~ /rxb/i ) { $tempinst = "rxb3"; }
  else { $tempinst = $inst; }

  my $telescope = OMP::Config->inferTelescope( 'instruments', $tempinst );

  if( defined( $inst ) &&
      defined( $ut ) ) {
    # We need to get an Info::ObsGroup object for this query object.
    my $obsgroup;
    try {
      $obsgroup = cgi_to_obsgroup( $q, \%cookie, ut => $ut, telescope => $telescope, inccal => 1 );
#      print "<h2>Observations for $inst on $ut</h2><br>\n";
    }
    catch OMP::Error with {
      my $Error = shift;
      my $errortext = $Error->{'-text'};
      print "Error in CGIObslog::list_observations: $errortext<br>\n";
    }
    otherwise {
      my $Error = shift;
      my $errortext = $Error->{'-text'};
      print "Error in CGIObslog::list_observations: $errortext<br>\n";
    };

    my %options;
    # Check if we're staff login or not (so we can tell obs_table
    # how to draw the WORF links).
    if( defined( $cookie{'projectid'} ) && exists( $cookie{'projectid'} ) &&
        defined( $cookie{'password'} ) && exists( $cookie{'password'} ) &&
        OMP::ProjServer->verifyPassword( $cookie{'projectid'}, $cookie{'password'} ) ) {
      $options{'worfstyle'} = 'project';
    } else {
      $options{'worfstyle'} = 'staff';
    }

    # And display the table.
    $options{'showcomments'} = 1;
    $options{'ascending'} = 0;
    $options{'instrument'} = $inst;
    try {
      obs_table( $obsgroup, %options );
    }
    catch OMP::Error with {
      my $Error = shift;
      my $errortext = $Error->{'-text'};
      print "Error: $errortext<br>\n";
    }
    otherwise {
      my $Error = shift;
      my $errortext = $Error->{'-text'};
      print "Error: $errortext<br>\n";
    };
  } else {
      print "<table width=\"600\" class=\"sum_table\" border=\"0\">\n<tr class=\"sum_table_head\"><td>";
      print "<strong class=\"small_title\">Observation Log</strong></td></tr>\n";
      print "<tr class=\"sum_other\"><td>No observations available</td></tr></table>\n";
  }

  print_obslog_footer( $q );

}

=item B<list_observations_txt>

Create a page containing only a text-based listing of observations.

=cut

sub list_observations_txt {
  my $query = shift;
  my $qv = $query->Vars;

  print $query->header( -type => 'text/plain' );

  my $obsgroup;
  try {
    # This should be the actual cookie with the project id information
    $obsgroup = cgi_to_obsgroup( $query, {}, inccal => 1, timegap => 0 );
  }
  catch OMP::Error with {
    my $Error = shift;
    my $errortext = $Error->{'-text'};
    print "Error: $errortext\n";
  }
  otherwise {
    my $Error = shift;
    my $errortext = $Error->{'-text'};
    print "Error: $errortext\n";
  };

  my %options;
  $options{'showcomments'} = 1;
  $options{'ascending'} = 1;
  $options{'text'} = 1;
  $options{'sort'} = 'chronological';
  try {
    obs_table( $obsgroup, %options );
  }
  catch OMP::Error with {
    my $Error = shift;
    my $errortext = $Error->{'-text'};
    print "Error: $errortext<br>\n";
  }
  otherwise {
    my $Error = shift;
    my $errortext = $Error->{'-text'};
    print "Error: $errortext<br>\n";
  };

}

=item B<projlog_content>

Display information about observations for a project on a particular
night.

  projlog_content($cgi, %cookie);

=cut

sub projlog_content {
  my $q = shift;
  my %cookie = @_;

  my $utdatestr = $q->url_param('utdate');
  my $no_retrieve = $q->url_param('noretrv');

  my $utdate;
  my $projectid;

  # Untaint the date string
  if ($utdatestr =~ /^(\d{4}-\d{2}-\d{2})$/) {
    $utdate = $1;
  } else {
    croak("UT date string [$utdate] does not match the expect format so we are not allowed to untaint it!");
  }

  # Now untaint the projectid
  $projectid = OMP::General->extract_projectid( $cookie{projectid} );

  (! $projectid) and croak("Project ID string [$cookie{projectid}] does not match the expect format so we are not allowed to untaint it!");

  print "<h2>Project log for " . uc($projectid) . " on $utdate</h2>";

  # Get a project object for this project
  my $proj;
  try {
    $proj = OMP::ProjServer->projectDetails($projectid, $cookie{password}, "object");
  } otherwise {
    my $E = shift;
    croak "Unable to retrieve the details of this project:\n$E";
  };

  my $telescope = $proj->telescope;

  # Make links for retrieving data
  # To keep people from following the links before the data are available
  # for download gray out the links if the current UT date is the same as the
  # UT date of the observations
  my $today = OMP::General->today(1);
  if ($today->ymd =~ $utdate) {
    $today += ONE_DAY;
    print "Retrieve data [This link will become active on " . $today->strftime("%Y-%m-%d %H:%M") . " GMT]";
  } else {
    my $pkgdataurl = OMP::Config->getData('pkgdata-url');

    unless ($no_retrieve) {
      print "<a href='$pkgdataurl?utdate=$utdate&inccal=1'>Retrieve data with calibrations</a><br>";
      print "<a href='$pkgdataurl?utdate=$utdate&inccal=0'>Retrieve data excluding calibrations</a>";
    }
  }

  # Link to WORF thumbnails
#  print "<p><a href=\"fbworfthumb.pl?ut=$utdate&telescope=$telescope\">View WORF thumbnails</a>\n";

  # Link to shift comments
  print "<p><a href='#shiftcom'>View shift comments</a> / <a href=\"fbshiftlog.pl?date=$utdate&telescope=$telescope\">Add shift comment</a><p>";


  # Get code for tau plot display
  my $plot_html = OMP::CGIComponent::Weather::tau_plot_code($utdate);

  # Link to the tau fits and wvm graph images on this page
  if ($plot_html) {
    print"<p><a href='#taufits'>View polynomial fit</a>";
  }

  print "<p><a href='#wvm'>View WVM graph</a>";

  print "<p><a href=\"obslog_text.pl?ut=" . $utdate . "&projid=" . $projectid . "\">View text-based observation log</a>\n";

  # Make a form for submitting MSB comments if an 'Add Comment'
  # button was clicked
  if ($q->param("Add Comment")) {
    print $q->h2("Add a comment to MSB");
    OMP::CGIComponent::MSB::msb_comment_form($q);
  }

  # Find out if (and execute) any actions are to be taken on an MSB
  OMP::CGIComponent::MSB::msb_action($q);

  # Display MSBs observed on this date

  # Use the lower-level method to fetch the science program so we
  # can disable the feedback comment associated with this action
  my $db = new OMP::MSBDB( Password => $cookie{password},
			   ProjectID => $cookie{projectid},
			   DB => new OMP::DBbackend, );

  my $sp = $db->fetchSciProg(1);

  my $observed = OMP::MSBServer->observedMSBs({projectid => $projectid,
					       date => $utdate,
					       returnall => 0,
					       format => 'data',});
  print $q->h2("MSB history for $utdate");
  OMP::CGIComponent::MSB::msb_comments($q, $observed, $sp);

  # Display observation log
  try {
    # Want to go to files on disk
    $OMP::ArchiveDB::FallbackToFiles = 1;

    my $grp = new OMP::Info::ObsGroup(projectid => $projectid,
				      date => $utdate,
				      inccal => 1,);

    if ($grp->numobs > 1) {
      print "<h2>Observation log</h2>";

      obs_table($grp);
    } else {
      # Don't display the table if no observations are available
      print "<h2>No observations available for this night</h2>";
    }
  } otherwise {
    print "<h2>No observations available for this night</h2>";
  };

  # Display shift log
  my %shift_args = (date => $utdate,
                    telescope => $telescope,
                    zone => "UT");

  print "<a name='shiftcom'></a>";
  display_shift_comments(\%shift_args, \%cookie);

  # Display polynomial fit image
  if ($plot_html) {
    print "<p>$plot_html";
  }

  print "<p>";
  # Display WVM graph
  my $wvm_html = OMP::CGIComponent::Weather::wvm_graph_code($utdate);
  print $wvm_html;
}

=back

=head1 SEE ALSO

C<OMP::CGIComponent::Obslog>, C<OMP::CGIComponent::MSB>,
C<OMP::CGIComponent::Shiftlog>, C<OMP::CGIComponent::Weather>

=head1 AUTHORS

Brad Cavanagh E<lt>b.cavanagh@jach.hawaii.eduE<gt>,
Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2002 Particle Physics and Astronomy Research Council.
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
