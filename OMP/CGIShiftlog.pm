package OMP::CGIShiftlog;

=head1 NAME

OMP::CGIShiftlog - CGI functions for the shiftlog tool.

=head1 SYNOPSIS

  use OMP::Shiftlog;

  my $verified = parse_query( $cgi );

  display_shift_comments( $verified );
  display_comment_form ( $cgi, $verified );
  display_telescope_form ( $cgi, $verified );

=head1 DESCRIPTION

This module provides routines used for CGI-related functions for
shiftlog - variable verification, form creation, comment
submission, etc.

=cut

use strict;
use warnings;
use Carp;

use CGI;
use CGI::Carp qw/ fatalsToBrowser /;
use Time::Piece;
use Time::Seconds;

use OMP::CGI;
use OMP::ProjDB;
use OMP::ShiftQuery;
use OMP::ShiftDB;

our $VERSION = (qw$Revision$ )[1];

require Exporter;

our @ISA = qw/Exporter/;
our @EXPORT = qw( shiftlog_page shiftlog_page_submit parse_query
                  display_shift_comments display_shift_table
                  display_comment_form display_shift_form
                  display_telescope_form submit_comment );
our %EXPORT_TAGS = (
                    'all' => [ @EXPORT ]
                    );

Exporter::export_tags(qw/ all /);


=head1 Routines

All routines are exported by default.

=over 4

=item B<shiftlog_page>

Creates a page with a form for filing a shiftlog entry.

  shiftlog_page( $cgi );

The only argument is the C<CGI> object.

=cut

sub shiftlog_page {
  my $q = shift;
  my %cookie = @_;

}

=item B<shiftlog_page_submit>

Creates a page with a form for filing a shiftlog entry
after a form on that page has been submitted.

  shiftlog_page_submit( $cgi );

The only argument is the C<CGI> object.

=cut

sub shiftlog_page_submit {
  my $q = shift;
  my %cookie = @_;
}

=item B<parse_query>

Converts the values submitted in a query into a hash
for easier parsing later.

  $parsed_query = parse_query( $cgi );

The only argument is the C<CGI> object, and this function
will return a hash reference.

=cut

sub parse_query {
  my $q = shift;
}

=item B<display_shift_comments>

Prints a table containing shift comments for a given
date.

  display_shift_comments( $verified, $cookie );

The first argument is a hash reference to a verified
query (see B<parse_query>), and the second is a hash reference
to a cookie.

Note that timestamps on comments will always be displayed
in HST regardless of the timezone setting.

=cut

sub display_shift_comments {
  my $v = shift;
  my $cookie = shift;

  # Verify the project id and password given in the cookie
  # with information in the database.
  my $projectid;
  my $password = $cookie->{'password'};
  if( exists( $cookie->{'projectid'} ) ) {
    $projectid = $cookie->{'projectid'};
  } else {
    $projectid = 'staff';
    $password = 'kalapana';
  }

  my $projdb = new OMP::ProjDB( ProjectID => $projectid,
                                DB => new OMP::DBbackend );
  my $verified_project = $projdb->verifyPassword( $password );

  if( !$verified_project ) {
    print "<br>could not verify password for project $projectid.<br>\n";
    return;
  }

  my $date = $v->{'date'};
  my $telescope = $v->{'telescope'};

  # If the date given is in HST, we need to convert it to UT so the query
  # knows how to deal with it.
  my $ut;
  if( $v->{'zone'} =~ /HST/i ) {
    my $hstdate = Time::Piece->strptime( $date, "%Y-%m-%d" );
    my $utdate = $hstdate + 10 * ONE_HOUR;
    $ut = $utdate->datetime;
  } else {
    $ut = $date;
  }

  # Form the XML.
  my $xml = "<ShiftQuery><date delta=\"1\">$ut</date><telescope>$telescope></ShiftQuery>";

  # Form the query.
  my $query = new OMP::ShiftQuery( XML => $xml );

  # Grab the results.
  my $sdb = new OMP::ShiftDB( DB => new OMP::DBbackend );
  my @result = $sdb->getShiftLogs( $query );

  # At this point we have an array of relevant Info::Comment objects,
  # so display them.
  display_shift_table( $date, $v->{'zone'}, $v->{'telescope'}, \@result );
}

=item B<display_shift_table>

Prints a table that displays shiftlog comments for a specific
date.

  display_shift_table( $date, $timezone, $telescope, $comments );

The first three arguments are strings used for display purposes. The
fourth argument is a reference to an array of C<Info::Comment> objects.

=cut

sub display_shift_table {
  my $date = shift;
  my $zone = shift;
  my $telescope = shift;
  my $comments = shift;

  print "<h2>Shift comments for $date $zone for $telescope</h2>\n";
  print "<table border=\"1\">\n";
  print "<tr><td><strong>HST time<br>User ID</strong></td><td><strong>comment</strong></td></tr>\n";
  foreach my $comment (@$comments) {
    print "<tr><td>";
    my $hstdate = $comment->date - 10 * ONE_HOUR;
    print $hstdate->hms;
#    print ( $comment->date->hms );
    print "<br>";
    print $comment->author->userid;
    print "</td><td>";
    print $comment->text;
    print "</td></tr>\n";
  }
  print "</table>";

}

=item B<display_comment_form>

Prints a form used to enter a shiftlog comment.

  display_comment_form( $cgi, $verified, $cookie );

The first argument is the C<CGI> object, the second is
a hash reference to a verified
query (see B<parse_query>), and the second is a hash
reference to a cookie.

=cut

sub display_comment_form {
  my $cgi = shift;
  my $v = shift;
  my $cookie = shift;

  print $cgi->startform;
  print "<table border=\"0\" width=\"100%\"><tr><td width=\"20%\">";
  print "Author:</td><td>";
  print $cgi->textfield( -name => 'user',
                         -size => '16',
                         -maxlength => '90',
                         -default => $cookie->{'user'},
                       );

  print "</td></tr>\n";
  
  print "<tr><td>Time: (HHMM or HH:MM format)</td><td>";
  print $cgi->textfield( -name => 'time',
                         -size => '16',
                         -maxlength => '5',
                       );
  print "&nbsp;";
  print $v->{'zone'};
  print " (will default to current time if blank)</td></tr>\n";

  print "<tr><td>Comment:</td><td>";
  print $cgi->textarea( -name => 'text',
                        -rows => 20,
                        -columns => 78,
                      );
  print "</td></tr></table>\n";
  print $cgi->hidden( -name => 'date',
                      -value => $v->{'date'},
                    );
  print $cgi->hidden( -name => 'zone',
                      -value => $v->{'zone'},
                    );
  print $cgi->hidden( -name => 'telescope',
                      -value => $v->{'telescope'},
                    );  
  print $cgi->submit( -name => 'Submit Comment' );
  print $cgi->endform;

}

=item B<display_date_form>

Prints a form used to change the date for which shiftlog
comments will be displayed and entered.

  display_date_form( $cgi, $verified );

The first argument is the C<CGI> object, and the second
argument is a hash reference to a verified
query (see B<parse_query>).

=cut

sub display_date_form {
  my $cgi = shift;
  my $v = shift;

  print "<br>\n";
  print $cgi->startform;
  print "<a name=\"changeut\">New</a> date (yyyy-mm-dd format, please: ";
  print $cgi->textfield( -name => 'date',
                         -size => '16',
                         -maxlength => '10',
                       );
  print "&nbsp;&nbsp;";
  print $cgi->radio_group( -name => 'zone',
                           -values => ['UT', 'HST'],
                           -default => ( defined( $v->{'zone'} ) ?
                                         $v->{'zone'} :
                                         'UT' ),
                           -linebreak => 'false',
                         );
  print $cgi->hidden( -name => 'telescope',
                      -value => $v->{'telescope'},
                    );
  print $cgi->submit( -name => 'Submit New Date' );
  print $cgi->endform;

}

=item B<display_telescope_form>

Prints a form used to change the telescope for which
shiftlog comments will be displayed and entered.

  display_telescope_form( $cgi, $verified );

The first argument is the C<CGI> object, and the second
argument is a hash reference to a verified
query (see B<parse_query>).

=cut

sub display_telescope_form {
  my $cgi = shift;
  my $v = shift;

  print "<br>\n";
  print $cgi->startform;
  print "<a name=\"changetelescope\">Change</a> telescope: ";
  print $cgi->radio_group( -name => 'telescope',
                           -values => ['JCMT', 'UKIRT'],
                           -default => $v->{'telescope'},
                           -linebreak => 'false',
                         );

}

=item B<submit_comment>

Submits a comment to the database.

  submit_comment( $verified );

The only argument is a hash reference to a verified
query (see B<parse_query>).

=cut

sub submit_comment {
  my $v = shift;

}

1;
