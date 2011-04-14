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

use OMP::CGIDBHelper;
use OMP::CGIComponent::Feedback;
use OMP::CGIComponent::MSB;
use OMP::CGIComponent::Project;
use OMP::Constants qw(:fb :done :msb);
use OMP::Error qw(:try);
use OMP::DateTools;

$| = 1;

=head1 Routines

=over 4

=item B<fb_msb_content>

Creates the page showing the project summary (lists MSBs).
Also provides buttons for adding an MSB comment.
Hides feedback entries.

  fb_msb_content($cgi, %cookie)

=cut

sub fb_msb_content {
  my $q = shift;
  my %cookie = @_;

  print $q->h1("Feedback for project $cookie{projectid}");

  OMP::CGIComponent::Project::proj_status_table($q, %cookie);
  OMP::CGIComponent::Feedback::fb_entries_hidden($q, %cookie);
  OMP::CGIComponent::MSB::msb_sum($q, %cookie);
}

=item B<fb_msb_output>

Creates the page showing the project summary (lists MSBs).
Also creates and parses form for adding an MSB comment.
Hides feedback entries.

  fb_msb_output($cgi, %cookie);

=cut

sub fb_msb_output {
  my $q = shift;
  my %cookie = @_;

  print $q->h1("Feedback for project $cookie{projectid}");

  OMP::CGIComponent::Project::proj_status_table($q, %cookie);
  OMP::CGIComponent::Feedback::fb_entries_hidden($q, %cookie);

  ($q->param("Add Comment")) and OMP::CGIComponent::MSB::msb_comment_form($q);

  if ($q->param("Submit")) {
    try {
      # Get the user object
      my $user = OMP::UserServer->getUser($q->param('author')) or
	throw OMP::Error::BadArgs( "Must supply a valid OMP user ID");

      # Create the comment object
      my $comment = new OMP::Info::Comment( author => $user,
					    text => $q->param('comment'),
					    status => OMP__DONE_COMMENT );

      OMP::MSBServer->addMSBcomment( $q->param('projectid'), $q->param('msbid'), $comment);
      print $q->h2("MSB comment successfully submitted");
    } catch OMP::Error::MSBMissing with {
      print "MSB not found in database";
    } otherwise {
      my $Error = shift;
      print "An error occurred while attempting to submit the comment: $Error";
    };

  }

  OMP::CGIComponent::MSB::msb_sum($q, %cookie);
}

=item B<msb_hist_output>

Create a page with a comment submission form or a message saying the comment was submitted.

  msb_hist_output($cgi, %cookie);

=cut

sub msb_hist_output {
  my $q = shift;
  my %cookie = @_;

  OMP::CGIComponent::Project::proj_status_table($q, %cookie);

  # If they clicked the "Add Comment" button bring up a comment form
  if ($q->param("Add Comment")) {
    print $q->h2("Add a comment to MSB");
    OMP::CGIComponent::MSB::msb_comment_form($q);
  }

  # Perform any actions on the msb?
  OMP::CGIComponent::MSB::msb_action($q);

  # Get the science program (if available)
  my $sp = OMP::CGIDBHelper::safeFetchSciProg( $cookie{projectid}, $cookie{password} );

  # Redisplay MSB comments
  my $commentref = OMP::MSBServer->historyMSB($q->param('projectid'), '', 'data');
  OMP::CGIComponent::MSB::msb_comments($q, $commentref, $sp);
}

=item B<msb_hist_content>

Create a page with a summary of MSBs and their associated comments

  msb_hist_content($cgi, %cookie);

=cut

sub msb_hist_content {
  my $q = shift;
  my %cookie = @_;

  my $projectid = uc($cookie{projectid});

  my $commentref;
  if (! $q->param('show')) {
    # show all
    $commentref = OMP::MSBServer->historyMSB($projectid, '', 'data');
  } elsif ($q->param('show') =~ /observed/) {
    # show observed
    my $xml = "<MSBDoneQuery><projectid>$projectid</projectid><status>" . OMP__DONE_DONE . "</status></MSBDoneQuery>";

    $commentref = OMP::MSBServer->observedMSBs({projectid => $projectid,
					       returnall => 1,
					       format => 'data'});
  } else {
    # show current
    $commentref = OMP::MSBServer->historyMSB($projectid, '', 'data');
  }

  print $q->h2("MSB History for project $projectid");

  ### put code for not displaying non-existant msbs here? ###
  OMP::CGIComponent::Project::proj_status_table($q, %cookie);
  print $q->hr;

  print "<SCRIPT LANGUAGE='javascript'> ";
  print "function mysubmit() ";
  print "{document.sortform.submit()}";
  print "</SCRIPT>";


  print $q->startform(-name=>'sortform'),
        "<b>Show </b>",

	# we want to show this page again, not the output page, so
	# we'll include this hidden param
	$q->hidden(-name=>'show_content',
		   -default=>'show_content'),

	$q->popup_menu(-name=>'show',
		       -values=>[qw/all observed/],
		       -default=>'all',
		       -onChange=>'mysubmit()'),
        "&nbsp;&nbsp;&nbsp;",
        $q->submit("Refresh"),
        $q->endform,
	$q->p;

  # Get the science program (if available)
  my $sp = OMP::CGIDBHelper::safeFetchSciProg( $projectid, $cookie{password} );

  OMP::CGIComponent::MSB::msb_comments($q, $commentref, $sp);
}

=item B<observed>

Create a page with a list of all the MSBs observed for a given UT sorted by project

  observed($cgi);

=cut

sub observed {
  my $q = shift;

#  my $utdate = OMP::DateTools->today;

#  my $commentref = OMP::MSBServer->observedMSBs($utdate, 0, 'data');

#  (@$commentref) and print $q->h2("MSBs observed on $utdate")
#    or print $q->h2("No MSBs observed on $utdate");

  OMP::CGIComponent::MSB::observed_form($q);
#  print $q->hr;

  # Create the MSB comment tables
#  msb_comments_by_project($q, $commentref);

#  (@$commentref) and print observed_form($q);
}

=item B<observed_output>

Create an msb comment page for private use with a comment submission form.

  observed_output($cgi);

=cut

sub observed_output {
  my $q = shift;

  # If they clicked the "Add Comment" button bring up a comment form
  if ($q->param("Add Comment")) {
    print $q->h2("Add a comment to MSB");
    OMP::CGIComponent::MSB::msb_comment_form($q);
  } elsif ($q->param("Remove")) {
    # Clicked Remove button
    try {
      OMP::MSBServer->alldoneMSB( $q->param('projectid'), $q->param('checksum'));
      print $q->h2("MSB removed from consideration");
    } catch OMP::Error::MSBMissing with {
      print "MSB not found in database";
    } otherwise {
      my $Error = shift;
      print "An error occurred while attempting to mark the MSB as Done: $Error";
    };
  } elsif ($q->param("Submit")) {
    # Submitted a comment

    try {
      # Get the user object
      my $user = OMP::UserServer->getUser($q->param('author')) or
	throw OMP::Error::BadArgs( "Must supply a valid OMP user ID");
	
      # Create the comment object
      my $comment = new OMP::Info::Comment( author => $user,
					    text => $q->param('comment'),
					    status => OMP__DONE_COMMENT );
	
      OMP::MSBServer->addMSBcomment( $q->param('projectid'), $q->param('msbid'), $comment);

      print $q->h2("MSB comment successfully submitted");
    } catch OMP::Error::MSBMissing with {
      print "MSB not found in database";
    } otherwise {
      my $Error = shift;
      print "An error occurred while attempting to submit the comment: $Error";
    };
  } else {
    # Just viewing comments
    OMP::CGIComponent::MSB::observed_form($q);
  }

  print $q->hr;

  if (! $q->param("Add Comment")) {
    my $utdate = $q->param('utdate');
    my $telescope = $q->param('telescope');

    # Do nothing if telescope not selected
    if (! $telescope) {
      print $q->h2("Please select a telescope");
      return;
    }

    my $dbconnection = new OMP::DBbackend;
    my $commentref = OMP::MSBServer->observedMSBs({date => $utdate,
						   returnall => 1,
						   format => 'data'});

    # Now keep only the comments that are for the telescope we want
    # to see observed msbs for
    my @msbs;
    for my $msb (@$commentref) {
      my $projdb = new OMP::ProjDB( ProjectID => $msb->projectid,
				    DB => $dbconnection );
      my $proj = $projdb->projectDetailsNoAuth( 'object' );
      if (uc $proj->telescope eq uc $telescope) {
	push @msbs, $msb;
      }
    }

    (@msbs) and print $q->h2("MSBs observed on $utdate")
      or print $q->h2("No MSBs observed on $utdate");

    OMP::CGIComponent::MSB::msb_comments_by_project($q, \@msbs);
    (@msbs) and OMP::CGIComponent::MSB::observed_form($q);
  }
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
along with this program (see SLA_CONDITIONS); if not, write to the
Free Software Foundation, Inc., 59 Temple Place, Suite 330,
Boston, MA  02111-1307  USA

=cut

1;
