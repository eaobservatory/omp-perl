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

use CGI;
use CGI::Carp qw/fatalsToBrowser/;
use Net::Domain qw/ hostfqdn /;
use Time::Seconds qw/ ONE_DAY /;

use OMP::CGIComponent::Obslog;
use OMP::CGIComponent::IncludeFile;
use OMP::CGIComponent::MSB;
use OMP::CGIComponent::Shiftlog;
use OMP::CGIComponent::Weather;
use OMP::CGIDBHelper;
use OMP::Config;
use OMP::Constants;
use OMP::DateTools;
use OMP::General;
use OMP::Info::Comment;
use OMP::Info::Obs;
use OMP::Info::ObsGroup;
use OMP::MSBServer;
use OMP::ObslogDB;
use OMP::ProjServer;
use OMP::BaseDB;
use OMP::ArchiveDB;
use OMP::DBbackend::Archive;
use OMP::Error qw/ :try /;

use base qw/OMP::CGIPage/;

our $VERSION = '2.000';

=head1 Routines

=over 4

=item B<file_comment>

Creates a page with a form for filing a comment.

  $page->file_comment( [$projectid] );

The parameter C<$projectid> is given from C<fbobscomment.pl>
but not C<staffobscomment.pl>.

=cut

sub file_comment {
  my $self = shift;
  my $projectid = shift;

  my $q = $self->cgi;

  my $comp = new OMP::CGIComponent::Obslog(page => $self);

#print "calling file_comment<br>\n";
  # Get the Info::Obs object
  my $obs = $comp->cgi_to_obs();

  # Print a summary about the observation.
  $comp->obs_summary( $obs, $projectid );

  # Display a form for adding a comment.
  $comp->obs_comment_form( $obs, $projectid );

  # Print a footer
  $comp->print_obscomment_footer();

}

=item B<file_comment_output>

Submit a comment and create a page with a form for filing a comment.

  $page->file_comment_output( [$projectid] );

The parameter C<$projectid> is given from C<fbobscomment.pl>
but not C<staffobscomment.pl>.

=cut

sub file_comment_output {
  my $self = shift;
  my $projectid = shift;

  my $q = $self->cgi;

  my $comp = new OMP::CGIComponent::Obslog(page => $self);

  # Insert the comment into the database.
  $comp->obs_add_comment();

  # Get the updated Info::Obs object.
  my $obs = $comp->cgi_to_obs();

  # Print a summary about the observation.
  $comp->obs_summary( $obs, $projectid );

  # Display a form for adding a comment.
  $comp->obs_comment_form( $obs, $projectid );

  # Print a footer
  $comp->print_obscomment_footer();

}

=item B<list_observations_txt>

Create a page containing only a text-based listing of observations.

=cut

sub list_observations_txt {
  my $self = shift;
  my $projectid = shift;

  my $query = $self->cgi;
  my $qv = $query->Vars;

  my $comp = new OMP::CGIComponent::Obslog(page => $self);

  print $query->header( -type => 'text/plain' );

  my $obsgroup;
  try {
    $obsgroup = $comp->cgi_to_obsgroup( projid => $projectid, inccal => 1, timegap => 0 );
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
    $comp->obs_table( $obsgroup, %options, projectid => $projectid );
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

  $page->projlog_content($projectid);

=cut

sub projlog_content {
  my $self = shift;
  my $projectid = shift;

  my $q = $self->cgi;

  my $comp = new OMP::CGIComponent::Obslog(page => $self);
  my $msbcomp = new OMP::CGIComponent::MSB(page => $self);
  my $weathercomp = new OMP::CGIComponent::Weather(page => $self);

  my $utdatestr = $q->url_param('utdate');
  my $no_retrieve = $q->url_param('noretrv');

  my $utdate;

  # Untaint the date string
  if ($utdatestr =~ /^(\d{4}-\d{2}-\d{2})$/) {
    $utdate = $1;
  } else {
    croak("UT date string [$utdate] does not match the expect format so we are not allowed to untaint it!");
  }

  print "<h2>Project log for " . uc($projectid) . " on $utdate</h2>";

  # Get a project object for this project
  my $proj;
  try {
    $proj = OMP::ProjServer->projectDetails($projectid, "object");
  } otherwise {
    my $E = shift;
    croak "Unable to retrieve the details of this project:\n$E";
  };

  my $telescope = $proj->telescope;

  # Make links for retrieving data
  # To keep people from following the links before the data are available
  # for download gray out the links if the current UT date is the same as the
  # UT date of the observations
  my $today = OMP::DateTools->today(1);
  if ($today->ymd =~ $utdate) {
    $today += ONE_DAY;
    print "Retrieve data [This link will become active on " . $today->strftime("%Y-%m-%d %H:%M") . " GMT]";
  } else {
    my $pkgdataurl = OMP::Config->getData('pkgdata-url');

    unless ($no_retrieve) {
      print "<a href='$pkgdataurl?project=$projectid&utdate=$utdate&inccal=1'>Retrieve data with calibrations</a><br>";
      print "<a href='$pkgdataurl?project=$projectid&utdate=$utdate&inccal=0'>Retrieve data excluding calibrations</a>";
    }
  }

  # Link to WORF thumbnails
#  print "<p><a href=\"fbworfthumb.pl?ut=$utdate&telescope=$telescope\">View WORF thumbnails</a>\n";

  # Link to shift comments
  print "<p><a href='#shiftcom'>View shift comments</a> / <a href=\"fbshiftlog.pl?project=$projectid&date=$utdate&telescope=$telescope\">Add shift comment</a><p>";


  # Get code for tau plot display
  my $plot_html = $weathercomp->tau_plot_code($utdate);

  # Link to the tau fits and wvm graph images on this page
  if ($plot_html) {
    print"<p><a href='#taufits'>View polynomial fit</a>";
  }

  print "<p><a href='#wvm'>View WVM graph</a>";

  print '<p><a href="' . OMP::Config->getData( 'cgidir' ) . qq[/obslog_text.pl?ut=$utdate&project=$projectid">]
        . "View text-based observation log</a>\n";

  # Make a form for submitting MSB comments if an 'Add Comment'
  # button was clicked
  if ($q->param("Add Comment")) {
    print $q->h2("Add a comment to MSB");
    $msbcomp->msb_comment_form();
  }

  # Find out if (and execute) any actions are to be taken on an MSB
  $msbcomp->msb_action();

  # Display MSBs observed on this date

  my $observed = OMP::MSBServer->observedMSBs({projectid => $projectid,
                                               date => $utdate,
                                               comments => 0,
                                               transactions => 1,
                                               format => 'data',});
  print $q->h2("MSB history for $utdate");

  my $sp = OMP::CGIDBHelper::safeFetchSciProg( $projectid );
  $msbcomp->msb_comments($observed, $sp);

  # Display observation log
  try {
    # Want to go to files on disk
    $OMP::ArchiveDB::FallbackToFiles = 1;

    my $grp = new OMP::Info::ObsGroup(projectid => $projectid,
                                      date => $utdate,
                                      inccal => 1,);

    if ($grp->numobs > 0) {
      print "<h2>Observation log</h2>";

      $comp->obs_table($grp, projectid => $projectid);
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
  OMP::CGIComponent::Shiftlog->new(page => $self)->display_shift_comments(\%shift_args);

  # Display polynomial fit image
  if ($plot_html) {
    print "<p>$plot_html";
  }

  print "<p>";
  # Display WVM graph
  my $wvm_html = $weathercomp->wvm_graph_code($utdate);
  print $wvm_html;

  # Include nightly data quality analysis.
  print "\n<h2>Data Quality Analysis</h2>\n\n",
        '<p><a href="https://pipelinesandarchives.blogspot.com/',
        '2013/03/new-omp-features-for-projects.html">',
        'Explanation of the graphs and tables.',
        "</a></p>\n\n";
  OMP::CGIComponent::IncludeFile->new(page => $self)->include_file_ut(
      'dq-nightly', $utdate, projectid => $projectid);
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
along with this program; if not, write to the
Free Software Foundation, Inc., 59 Temple Place, Suite 330,
Boston, MA  02111-1307  USA

=cut

1;
