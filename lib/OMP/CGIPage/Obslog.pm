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
use OMP::CGIComponent::Helper qw/url_absolute/;
use OMP::CGIComponent::IncludeFile;
use OMP::CGIComponent::MSB;
use OMP::CGIComponent::Shiftlog;
use OMP::CGIComponent::Weather;
use OMP::Config;
use OMP::Constants;
use OMP::DateTools;
use OMP::General;
use OMP::Info::Comment;
use OMP::Info::Obs;
use OMP::Info::ObsGroup;
use OMP::MSBServer;
use OMP::NightRep;
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

  my $messages;
  if ($q->param('submit_comment')) {
    # Insert the comment into the database.
    my $response = $comp->obs_add_comment();
    $messages = $response->{'messages'};
  }

  # Get the Info::Obs object
  my $obs = $comp->cgi_to_obs();

  # Verify that we do have an Info::Obs object.
  if( ! UNIVERSAL::isa( $obs, "OMP::Info::Obs" ) ) {
    throw OMP::Error::BadArgs("Must supply an Info::Obs object");
  }

  if( defined( $projectid ) &&
      $obs->isScience && (lc( $obs->projectid ) ne lc( $projectid ) ) ) {
    throw OMP::Error( "Observation does not match project " . $projectid );
  }

  return {
      target => url_absolute($q),
      obs => $obs,
      is_time_gap => scalar eval {$obs->isa('OMP::Info::Obs::TimeGap')},
      status_class => \%OMP::Info::Obs::status_class,
      messages => $messages,
      %{$comp->obs_comment_form($obs, $projectid)},
  };
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
  $options{'sort'} = 'chronological';
  try {
    $comp->obs_table_text( $obsgroup, %options, projectid => $projectid );
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
  my $shiftcomp = new OMP::CGIComponent::Shiftlog(page => $self);
  my $weathercomp = new OMP::CGIComponent::Weather(page => $self);
  my $includecomp = OMP::CGIComponent::IncludeFile->new(page => $self);

  my $utdatestr = $q->url_param('utdate');
  my $no_retrieve = $q->url_param('noretrv');

  my $utdate;

  # Untaint the date string
  if ($utdatestr =~ /^(\d{4}-\d{2}-\d{2})$/) {
    $utdate = $1;
  } else {
    croak("UT date string [$utdate] does not match the expect format so we are not allowed to untaint it!");
  }

  # Get a project object for this project
  my $proj;
  try {
    $proj = OMP::ProjServer->projectDetails($projectid, "object");
  } otherwise {
    my $E = shift;
    croak "Unable to retrieve the details of this project:\n$E";
  };

  my $telescope = $proj->telescope;

  # Perform any actions on the MSB.
  my $response = $msbcomp->msb_action(projectid => $projectid);
  my $errors = $response->{'errors'};
  my $messages = $response->{'messages'};
  return $self->_write_error(@$errors) if scalar @$errors;

  my $comment_msb_id_fields = undef;

  # Make a form for submitting MSB comments if an 'Add Comment'
  # button was clicked
  if ($q->param("submit_add_comment")) {
    $comment_msb_id_fields = {
        checksum => scalar $q->param('checksum'),
        transaction => scalar $q->param('transaction'),
    };
  }

  # Get code for tau plot display
  # NOTE: disabled as we currently don't have fits in the OMP.
  # my $plot_html = $weathercomp->tau_plot($utdate);

  # Make links for retrieving data
  # To keep people from following the links before the data are available
  # for download gray out the links if the current UT date is the same as the
  # UT date of the observations
  my $today = OMP::DateTools->today(1);
  my $retrieve_date = undef;
  unless ($no_retrieve) {
    if ($today->ymd =~ $utdate) {
      $retrieve_date = $today + ONE_DAY;
    }
    else {
      $retrieve_date = 'now';
    }
  }

  # Display MSBs observed on this date
  my $observed = OMP::MSBServer->observedMSBs({projectid => $projectid,
                                               date => $utdate,
                                               comments => 0,
                                               transactions => 1,
                                               format => 'data',});

  my $sp = OMP::MSBServer->getSciProgInfo($projectid);
  my $msb_info = $msbcomp->msb_comments($observed, $sp);

  # Display observation log
  my $obs_summary = undef;
  try {
    # Want to go to files on disk
    $OMP::ArchiveDB::FallbackToFiles = 1;

    my $grp = new OMP::Info::ObsGroup(projectid => $projectid,
                                      date => $utdate,
                                      inccal => 1,);

    if ($grp->numobs > 0) {
      $obs_summary = OMP::NightRep->get_obs_summary(obsgroup => $grp);
    }
  } otherwise {
  };

  return {
      target => url_absolute($q),
      project => $proj,
      utdate => $utdate,
      telescope => $telescope,
      retrieve_date => $retrieve_date,

      obs_summary => $obs_summary,

      shift_log_comments => $shiftcomp->get_shift_comments({
          date => $utdate,
          telescope => $telescope,
          zone => "UT",
      }),

      dq_nightly_html => $includecomp->include_file_ut(
          'dq-nightly', $utdate, projectid => $projectid),

      msb_info => $msb_info,
      comment_msb_id_fields => $comment_msb_id_fields,
      comment_msb_messages => $messages,

      weather_plots => [
          grep {$_->[2]}
          ['wvm', 'WVM graph', $weathercomp->wvm_graph($utdate)],
      ],
  }
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
