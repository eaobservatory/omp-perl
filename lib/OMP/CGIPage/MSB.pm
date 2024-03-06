package OMP::CGIPage::MSB;

=head1 NAME

OMP::CGIPage::MSB - Display of complete MSB web pages

=head1 SYNOPSIS

  use OMP::CGIPage::MSB;

=head1 DESCRIPTION

Helper methods for constructing and displaying complete web pages
that display MSB comments and general MSB information.

=cut

use 5.006;
use strict;
use warnings;
use Carp;

use Time::Seconds;

use OMP::CGIComponent::Feedback;
use OMP::CGIComponent::MSB;
use OMP::CGIComponent::Project;
use OMP::Constants qw(:fb :done :msb);
use OMP::Error qw(:try);
use OMP::DateTools;
use OMP::MSBServer;

use base qw/OMP::CGIPage/;

$| = 1;

=head1 Routines

=over 4

=item B<fb_msb_output>

Creates the page showing the project summary (lists MSBs).
Also creates and parses form for adding an MSB comment.
Hides feedback entries.

  $page->fb_msb_output($projectid);

=cut

sub fb_msb_output {
  my $self = shift;
  my $projectid = shift;

  my $q = $self->cgi;

  my $fbcomp = new OMP::CGIComponent::Feedback(page => $self);

  my $checksum = undef;
  my $prog_info = undef;
  my @messages = ();

  if ($q->param("submit_add_comment")) {
    $checksum = $q->param('checksum');
  }
  elsif ($q->param("submit_msb_comment")) {
    my $error = undef;

    try {
      # Create the comment object
      my $comment = new OMP::Info::Comment( author => $self->auth->user,
                                            text => scalar $q->param('comment'),
                                            status => OMP__DONE_COMMENT );
      OMP::MSBServer->addMSBcomment( $projectid, (scalar $q->param('checksum')), $comment);
      push @messages, 'MSB comment successfully submitted.';
    } catch OMP::Error::MSBMissing with {
      $error = "MSB not found in database.";
    } otherwise {
      my $E = shift;
      $error = "An error occurred while attempting to submit the comment: $E";
    };

    return $self->_write_error($error) if defined $error;
  }
  else {
    $prog_info = OMP::MSBServer->getSciProgInfo($projectid, with_observations => 1);
  }

  return {
      project => OMP::ProjServer->projectDetails($projectid, 'object'),
      num_comments => $fbcomp->fb_entries_count($projectid),
      target => $self->url_absolute(),
      prog_info => $prog_info,
      comment_msb_checksum => $checksum,
      messages => \@messages,
      pretty_print_seconds => sub {return Time::Seconds->new($_[0])->pretty_print;},
      timestamp_as_utc => sub {return sprintf "%s UTC", scalar gmtime($_[0]);},
  };
}

=item B<msb_hist>

Create a page with a summary of MSBs and their associated comments

  $page->msb_hist($projectid);

=cut

sub msb_hist {
  my $self = shift;
  my $projectid = shift;

  my $q = $self->cgi;
  my $comp = new OMP::CGIComponent::MSB(page => $self);
  my $projcomp = new OMP::CGIComponent::Project(page => $self);

  # Perform any actions on the MSB.
  my $response = $comp->msb_action(projectid => $projectid);
  my $errors = $response->{'errors'};
  my $messages = $response->{'messages'};
  return $self->_write_error(@$errors) if scalar @$errors;

  my $show = $q->param('show') // 'all';
  my $comment_msb_id_fields = undef;
  my $msb_info;

  if ($q->param("submit_add_comment")) {
    $comment_msb_id_fields = {
        checksum => scalar $q->param('checksum'),
        transaction => scalar $q->param('transaction'),
    };
  }
  else {
    # Get the science program info (if available)
    my $sp = OMP::MSBServer->getSciProgInfo($projectid);

    my $commentref;
    if ($show =~ /observed/) {
      # show observed
      my $xml = "<MSBDoneQuery><projectid>$projectid</projectid><status>" . OMP__DONE_DONE . "</status></MSBDoneQuery>";

      $commentref = OMP::MSBServer->observedMSBs({projectid => $projectid,
                                                 returnall => 1,
                                                 format => 'data'});
    } else {
      # show current
      $commentref = OMP::MSBServer->historyMSB($projectid, '', 'data');

      if ($show =~ /current/) {
        $commentref = [grep {$sp->existsMSB($_->checksum)} @$commentref] if defined $sp;
      }
    }

    $msb_info = $comp->msb_comments($commentref, $sp);
  }

  return {
      target => $self->url_absolute(),
      target_base => $q->url(-absolute => 1),
      project => OMP::ProjServer->projectDetails($projectid, 'object'),
      msb_info => $msb_info,
      values => {
          show => $show,
      },
      comment_msb_id_fields => $comment_msb_id_fields,
      messages => $messages,
  };
}

=item B<observed>

Create an MSB comment page for private use with a comment submission form.

  $page->observed();

=cut

sub observed {
  my $self = shift;

  my $q = $self->cgi;
  my $comp = new OMP::CGIComponent::MSB(page => $self);

  my $projdb = OMP::ProjDB->new(DB => $self->database);

  my $telescope = $self->decoded_url_param('telescope'),
  my $utdate = $self->decoded_url_param('utdate');

  my $comment_msb_id_fields = undef;
  my $projects = undef;

  # Perform any actions on the MSB.
  my $response = $comp->msb_action();
  my $errors = $response->{'errors'};
  my $messages = $response->{'messages'};
  return $self->_write_error(@$errors) if scalar @$errors;

  if ($q->param("submit_add_comment")) {
    $comment_msb_id_fields = {
        checksum => scalar $q->param('checksum'),
        transaction => scalar $q->param('transaction'),
        projectid => scalar $q->param('projectid'),
    };
  }
  elsif (defined $utdate and defined $telescope) {

    my $commentref = OMP::MSBServer->observedMSBs({date => $utdate,
                                                   returnall => 1,
                                                   format => 'data'});

    # Now keep only the comments that are for the telescope we want
    # to see observed msbs for
    my %sorted;
    for my $msb (@$commentref) {
      my @instruments = split /\W/, $msb->instrument;
      next unless $telescope eq uc OMP::Config->inferTelescope('instruments', @instruments);

      my $projectid = $msb->projectid;
      push @{$sorted{$projectid}}, $msb;
    }

    $projects = [map {
        my $projectid = $_;
        my $sp = OMP::MSBServer->getSciProgInfo($projectid);
        my $msb_info = $comp->msb_comments(\@{$sorted{$projectid}}, $sp);
        {
          project_id => $projectid,
          msb_info => $msb_info,
        };
    } sort keys %sorted];
  }

  $self->_sidebar_night($telescope, $utdate);

  return {
      target => $self->url_absolute(),
      target_base => $q->url(-absolute => 1),
      telescopes => [$projdb->listTelescopes],
      values => {
          telescope => $telescope,
          utdate => $utdate // OMP::DateTools->today,

      },
      comment_msb_id_fields => $comment_msb_id_fields,
      projects => $projects,
      messages => $messages,
  };
}

=back

=head1 SEE ALSO

C<OMP::CGIComponent::MSB>, C<OMP::CGIComponent::Feedback>,
C<OMP::CGIComponent::Project>

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
along with this program; if not, write to the
Free Software Foundation, Inc., 59 Temple Place, Suite 330,
Boston, MA  02111-1307  USA

=cut

1;
