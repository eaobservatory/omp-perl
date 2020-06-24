package OMP::CGIComponent::Shiftlog;

=head1 NAME

OMP::CGIComponent::Shiftlog - CGI functions for the shiftlog tool.

=head1 SYNOPSIS

  use OMP::CGIComponent::Shiftlog;

  my $verified = $comp->parse_query();

  $comp->display_shift_comments( $verified );
  $comp->display_comment_form( $verified );
  $comp->display_telescope_form( $verified );

=head1 DESCRIPTION

This module provides routines used for CGI-related functions for
shiftlog - variable verification, form creation, comment
submission, etc.

=cut

use strict;
use warnings;

use CGI;
use CGI::Carp qw/ fatalsToBrowser /;
use OMP::DateTools;
use Time::Piece;
use Time::Seconds;

use OMP::CGIComponent::Helper qw/start_form_absolute/;
use OMP::ShiftQuery;
use OMP::ShiftDB;
use OMP::Error qw/ :try /;

use base qw/OMP::CGIComponent/;

our $VERSION = '2.000';

=head1 Routines

=over 4

=item B<parse_query>

Converts the values submitted in a query into a hash
for easier parsing later.

  $parsed_query = $comp->parse_query();

This function will return a hash reference.

=cut

sub parse_query {
  my $self = shift;

  my $q = $self->cgi->Vars;
  my %return = ();

# Telescope. This is a string made up of word characters.
  if( exists( $q->{'telescope'} ) ) {
    ( $return{'telescope'} = $q->{'telescope'} ) =~ s/\W//g;
  }

# Time Zone for display. This is either UT or HST. Defaults to UT.
  if( exists( $q->{'zone'} ) ) {
    if( $q->{'zone'} =~ /hst/i ) {
      $return{'zone'} = 'HST';
    } else {
      $return{'zone'} = 'UT';
    }
  } else {
    $return{'zone'} = 'UT';
  }

# Time Zone for entry. This is either UT or HST. Defaults to HST.
  if( exists( $q->{'entryzone'} ) ) {
    if( $q->{'entryzone'} =~ /ut/i ) {
      $return{'entryzone'} = 'UT';
    } else {
      $return{'entryzone'} = 'HST';
    }
  } else {
    $return{'entryzone'} = 'HST';
  }

# Date. This is in yyyy-mm-dd format. If it is not set, it
# will default to the current UT date.
  if( exists( $q->{'date'} ) ) {
    my $dateobj = OMP::DateTools->parse_date( $q->{'date'} );
    $return{'date'} = $dateobj->ymd;
  } else {
    my $dateobj = gmtime;
    $return{'date'} = $dateobj->ymd;
  }

# Time. This is in hh:mm:ss or hhmmss format. If it is not set, it
# will default to the current local time.
  if( exists( $q->{'time'} ) && $q->{'time'} =~ /(\d\d):?(\d\d):?(\d\d)/ ) {
    $return{'time'} = "$1:$2:$3";
  } else {
    my $dateobj = localtime;
    $return{'time'} = $dateobj->hms;
  }

# Text. Anything goes, but leading/trailing whitespace is stripped.
  if( exists( $q->{'text'} ) ) {
    ( $return{'text'} = $q->{'text'} ) =~ s/^\s+//s;
    $return{'text'} =~ s/\s+$//s;
  }

  return \%return;

}

=item B<display_shift_comments>

Prints a table containing shift comments for a given
date.

  $comp->display_shift_comments( $verified );

The first argument is a hash reference to a verified
query (see B<parse_query>),

Note that timestamps on comments will always be displayed
in HST regardless of the timezone setting.

This function will print nothing if neither the telescope
nor date are given in the verified query.

=cut

sub display_shift_comments {
  my $self = shift;
  my $v = shift;

  return unless defined $v->{'telescope'};
  return unless defined $v->{'date'};

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
  my $xml = "<ShiftQuery><date delta=\"1\">$ut</date><telescope>$telescope</telescope></ShiftQuery>";

  # Form the query.
  my $query = new OMP::ShiftQuery( XML => $xml );

  # Grab the results.
  my $sdb = new OMP::ShiftDB( DB => new OMP::DBbackend );
  my @result = $sdb->getShiftLogs( $query );

  # At this point we have an array of relevant Info::Comment objects,
  # so display them.
  print "<h2>Shift comments for shift on $date ".$v->{'zone'}." for ".$v->{'telescope'}."</h2>\n";
  $self->display_shift_table( \@result );
}

=item B<display_shift_table>

Prints a table that displays shiftlog comments.

  $comp->display_shift_table( \@comments );

The only argument is a reference to an array of C<Info::Comment> objects.

=cut

sub display_shift_table {
  my $self = shift;
  my $comments = shift;

  print "<table class='sum_table' cellspacing='0' width='600'>";
  print "<tr class='sum_table_head'>";
  print "<td colspan=3><strong class='small_title'>Shift Log Comments</strong></td>";

  # Sort shift comments by date
  my %comments;
  for my $c (@$comments) {
    my $time = gmtime($c->date->epoch);
    push(@{$comments{$time->ymd}}, $c);
  }

  my $bgcolor = 'a';
  for my $date (sort keys %comments) {
    my $timecellclass = 'time';  # CSS style class

     if (scalar(keys %comments) > 1) {
      # Summarizing Shift comments for more than one day

       my $cdate = $comments{$date}->[0]->date;
       my $time = gmtime($cdate->epoch);
       $timecellclass = 'time_' . $time->day;

      print "<tr class=sum_other valign=top><td class=".$timecellclass."_$bgcolor colspan=2>$date</td><td colspan=1></td>";
    }
    for my $c (@{$comments{$date}}) {

      my $date = $c->date;
      my $time = gmtime( $date->epoch );
      my $author = $c->author;

      # Call author "anonymous" if name is not defined
      ($author) and $author = $author->name
        or $author = "Anonymous";

      # Get the text
      my $text = $c->text;

      # All Shift Comments tend to be HTML with a <PRE> tag
      # These always look bad and have long lines so we can either
      # cross our fingers and hope that it looks okay without the PRE
      # or word wrap to 72 columns and retain the PRE. For now, remove the PRE
      $text =~ s/^\s*<PRE>//i;
      $text =~ s|</PRE>\s*$||i;

      # Now print the comment
      print "<tr class=\"row_$bgcolor\" valign=top>";
      print "<td class=\"time_a\">$author</td>";
      print "<td class=\"" . $timecellclass . "_$bgcolor\">".
        $time->strftime("%H:%M:%S UT") ."</td>";
      print "<td class=subject>$text</td>";

      # Alternate bg color
      ($bgcolor eq "a") and $bgcolor = "b" or $bgcolor = "a";
    }
  }
  print "</table>";

}

=item B<display_comment_form>

Prints a form used to enter a shiftlog comment.

  $comp->display_comment_form( $verified );

The argument is a hash reference to a verified query (see B<parse_query>).

=cut

sub display_comment_form {
  my $self = shift;
  my $v = shift;

  my $cgi = $self->cgi;

  print start_form_absolute($cgi);
  print "<table border=\"0\" width=\"100%\"><tr><td width=\"20%\">";
  print "Author:</td><td>" , $self->auth->user->userid(), "</td></tr>\n";

  print "<tr><td>Time: (HHMMSS or HH:MM:SS, 24hr format)</td><td>";
  print $cgi->textfield( -name => 'time',
                         -size => '16',
                         -maxlength => '8',
                         -default => '',
                         -override => 1,
                       );
  print "&nbsp;";
  print $v->{'entryzone'};
  print " (will default to current time if blank)</td></tr>\n";

  print "<tr><td>Comment:</td><td>";
  print $cgi->textarea( -name => 'text',
                        -rows => 15,
                        -columns => 50,
                        -default => '',
                        -override => 1,
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
  print $cgi->end_form;

}

=item B<display_date_form>

Prints a form used to change the date for which shiftlog
comments will be displayed and entered.

  $comp->display_date_form( $verified );

The first argument is the C<CGI> object, and the second
argument is a hash reference to a verified
query (see B<parse_query>).

=cut

sub display_date_form {
  my $self = shift;
  my $v = shift;

  my $cgi = $self->cgi;

  print "<br>\n";
  print start_form_absolute($cgi);
  print "<a name=\"changeut\">New</a> date (yyyy-mm-dd format, please): ";
  print $cgi->textfield( -name => 'date',
                         -size => '16',
                         -maxlength => '10',
                         -default => $v->{'date'},
                       );
  print "&nbsp;&nbsp;UT<br>";

  print $cgi->hidden( -name => 'telescope',
                      -value => $v->{'telescope'},
                    );
  print $cgi->hidden( -name => 'zone',
                      -value => 'UT',
                    );
  print $cgi->submit( -name => 'Submit New Date' );
  print $cgi->end_form;

}

=item B<display_telescope_form>

Prints a form used to change the telescope for which
shiftlog comments will be displayed and entered.

  $comp->display_telescope_form( $verified );

The argument is a hash reference to a verified
query (see B<parse_query>).

=cut

sub display_telescope_form {
  my $self = shift;
  my $v = shift;

  my $cgi = $self->cgi;

  my @tels = OMP::Config->telescopes();
  @tels = map { uc } @tels;

  print "<br>\n";
  print start_form_absolute($cgi);
  print "<a name=\"changetelescope\">Change</a> telescope: ";
  print $cgi->radio_group( -name => 'telescope',
                           -values => \@tels,
                           -default => $v->{'telescope'},
                         );
  print "<br>";
  print $cgi->hidden( -name => 'date',
                      -value => $v->{'date'},
                    );
  print $cgi->hidden( -name => 'zone',
                      -value => $v->{'zone'},
                    );
  print $cgi->submit( -name => 'Submit New Telescope' );
  print $cgi->end_form;
}

=item B<submit_comment>

Submits a comment to the database.

  $comp->submit_comment( $verified );

The only argument is a hash reference to a verified
query (see B<parse_query>).

=cut

sub submit_comment {
  my $self = shift;
  my $v = shift;

  if( !defined( $v->{'text'} ) ) { return; }

  my $telescope = $v->{'telescope'};
  my $zone = $v->{'zone'};
  my $entryzone = $v->{'entryzone'};
  my $date = $v->{'date'};
  my $time = $v->{'time'};
  my $text = $v->{'text'};

  my $userobj = $self->auth->user;

# Form the date.
  $time =~ /(\d\d):(\d\d):(\d\d)/;
  my ($hour, $minute, $second) = ($1, $2, $3);

  # Convert the time zone to UT, if necessary.
  if( ($entryzone =~ /hst/i) && ($zone =~ /ut/i)) {
    $hour += 10;
    $hour %= 24;
  }

  my $datestring = "$date $hour:$minute:$second";
  my $datetime = Time::Piece->strptime( $datestring, "%Y-%m-%d %H:%M:%S" );

# Create an OMP::Info::Comment object.
  my $comment = new OMP::Info::Comment( author => $userobj,
                                        text => $v->{'text'},
                                        date => $datetime,
                                      );

# Store the comment in the database.
  try {
    my $sdb = new OMP::ShiftDB( DB => new OMP::DBbackend );
    $sdb->enterShiftLog( $comment, $telescope );
  }
  catch OMP::Error with {
    my $Error = shift;
    print "Error in CGIShiftlog.pm, submit_comment(), comment submission:\n";
    print $Error->{'-text'};
    print "<br>Comment will not be stored<br>\n";
    return;
  }
  otherwise {
    my $Error = shift;
    print "Error in CGIShiftlog.pm, submit_comment(), comment submission:\n";
    print $Error->{'-text'};
    print "<br>Comment will not be stored<br>\n";
    return;
  };

  print "Comment successfully entered into database.<br>\n";

}

=item B<print_header>

Prints a header.

  $comp->print_header();

=cut

sub print_header {
  my $self = shift;

  print <<END;
Welcome to shiftlog. <a href="#changeut">Change the date</a>
<a href="#changetelescope">Change the telescope</a><br>
<hr>
END
};


=back

=head1 SEE ALSO

C<OMP::CGIPage::Shiftlog>

=head1 AUTHOR

Brad Cavanagh E<lt>b.cavanagh@jach.hawaii.eduE<gt>

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
