package OMP::CGI::MSBPage;

=head1 NAME

OMP::CGI::MSBPage - Display of complete MSB web pages

=head1 SYNOPSIS

  use OMP::CGI::MSBPage;

=head1 DESCRIPTION

Helper methods for constructing and displaying complete web pages
that display MSB comments and general MSB information.

=cut

use 5.006;
use strict;
use warnings;
use Carp;

use OMP::CGI::Feedback;
use OMP::CGI::MSB;
use OMP::CGI::Project;
use OMP::Constants qw(:fb :done :msb);
use OMP::Error qw(:try);

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

  OMP::CGI::Project::proj_status_table($q, %cookie);
  OMP::CGI::Feedback::fb_entries_hidden($q, %cookie);
  OMP::CGI::MSB::msb_sum($q, %cookie);
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

  OMP::CGI::Project::proj_status_table($q, %cookie);
  OMP::CGI::Feedback::fb_entries_hidden($q, %cookie);

  ($q->param("Add Comment")) and OMP::CGI::MSB::msb_comment_form($q);

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

  OMP::CGI::MSB::msb_sum($q, %cookie);
}

=item B<msb_hist_output>

Create a page with a comment submission form or a message saying the comment was submitted.

  msb_hist_output($cgi, %cookie);

=cut

sub msb_hist_output {
  my $q = shift;
  my %cookie = @_;

  OMP::CGI::Project::proj_status_table($q, %cookie);

  # If they clicked the "Add Comment" button bring up a comment form
  if ($q->param("Add Comment")) {
    print $q->h2("Add a comment to MSB");
    OMP::CGI::MSB::msb_comment_form($q);
  }

  # Perform any actions on the msb?
  OMP::CGI::MSB::msb_action($q);

  # Use the lower-level method to fetch the science program so we
  # can disable the feedback comment associated with this action
  my $db = new OMP::MSBDB( Password => $cookie{password},
			   ProjectID => $cookie{projectid},
			   DB => new OMP::DBbackend, );

  my $sp = $db->fetchSciProg(1);

  # Redisplay MSB comments
  my $commentref = OMP::MSBServer->historyMSB($q->param('projectid'), '', 'data');
  OMP::CGI::MSB::msb_comments($q, $commentref, $sp);
}

=item B<msb_hist_content>

Create a page with a summary of MSBs and their associated comments

  msb_hist_content($cgi, %cookie);

=cut

sub msb_hist_content {
  my $q = shift;
  my %cookie = @_;

  my $commentref;
  if (! $q->param('show')) {
    # show all
    $commentref = OMP::MSBServer->historyMSB($cookie{projectid}, '', 'data');
  } elsif ($q->param('show') =~ /observed/) {
    # show observed
    my $xml = "<MSBDoneQuery><projectid>$cookie{projectid}</projectid><status>" . OMP__DONE_DONE . "</status></MSBDoneQuery>";

    $commentref = OMP::MSBServer->observedMSBs({projectid => $cookie{projectid},
					       returnall => 1,
					       format => 'data'});
  } else {
    # show current
    $commentref = OMP::MSBServer->historyMSB($cookie{projectid}, '', 'data');
  }

  # Use the lower-level method to fetch the science program so we
  # can disable the feedback comment associated with this action
  my $db = new OMP::MSBDB( Password => $cookie{password},
			   ProjectID => $cookie{projectid},
			   DB => new OMP::DBbackend, );

  my $sp = $db->fetchSciProg(1);
  
  print $q->h2("MSB History for project $cookie{projectid}");

  ### put code for not displaying non-existant msbs here? ###
  OMP::CGI::Project::proj_status_table($q, %cookie);
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

  OMP::CGI::MSB::msb_comments($q, $commentref, $sp);
}

=item B<observed>

Create a page with a list of all the MSBs observed for a given UT sorted by project

  observed($cgi);

=cut

sub observed {
  my $q = shift;

#  my $utdate = OMP::General->today;

#  my $commentref = OMP::MSBServer->observedMSBs($utdate, 0, 'data');

#  (@$commentref) and print $q->h2("MSBs observed on $utdate")
#    or print $q->h2("No MSBs observed on $utdate");

  OMP::CGI::MSB::observed_form($q);
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
    OMP::CGI::MSB::msb_comment_form($q);
  }

  if (!$q->param("Add Comment")) {
    # Just viewing comments
    OMP::CGI::MSB::observed_form($q);
    print $q->hr;

    my $utdate = $q->param('utdate');

    print $utdate;

    my $telescope = $q->param('telescope');

    my $dbconnection = new OMP::DBbackend;

    my $commentref = OMP::MSBServer->observedMSBs({date => $utdate,
						  returnall => 0,
						  format => 'data'});

    # Now keep only the comments that are for the telescope we want
    # to see observed msbs for
    my @msbs;
    for my $msb (@$commentref) {
      my $projdb = new OMP::ProjDB( ProjectID => $msb->projectid,
				    Password => "***REMOVED***",
				    DB => $dbconnection );
      my $proj = $projdb->projectDetails( 'object' );
      if ($proj->telescope eq $telescope) {
	push @msbs, $msb;
      }
    }

    (@msbs) and print $q->h2("MSBs observed on $utdate")
      or print $q->h2("No MSBs observed on $utdate");

    OMP::CGI::MSB::msb_comments_by_project($q, \@msbs);

    # If they've just submitted a comment show some comforting output
    # or catch an error
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
    
    # If they click the "Mark as Done" button mark it as done
    
    if ($q->param("Remove")) {
      try {
	OMP::MSBServer->alldoneMSB( $q->param('projectid'), $q->param('checksum'));
	print $q->h2("MSB removed from consideration");
      } catch OMP::Error::MSBMissing with {
	print "MSB not found in database";
      } otherwise {
	my $Error = shift;
      print "An error occurred while attempting to mark the MSB as Done: $Error";
    };
    }
    
    (@msbs) and print OMP::CGI::MSB::observed_form($q);
  }
}

=back

=head1 SEE ALSO

C<OMP::CGI::MSB>, C<OMP::CGI::Feedback>, C<OMP::CGI::Project>

=head1 AUTHOR

Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2004 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
