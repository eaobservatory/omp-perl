#!/local/bin/perl -X
#
# shiftlog - keep a log throughout a night
#
# Author: Brad Cavanagh (b.cavanagh@jach.hawaii.edu)

BEGIN {
  use constant OMPLIB => "/jac_sw/omp/msbserver";
  use File::Spec;
  $ENV{'OMP_CFG_DIR'} = File::Spec->catdir( OMPLIB, "cfg" )
    unless exists $ENV{'OMP_CFG_DIR'};
}

use CGI;
use CGI::Carp qw/ fatalsToBrowser /;

use lib OMPLIB;

use OMP::CGI;
use OMP::Info::Comment;
use OMP::ShiftDB;
use OMP::DBbackend;
use OMP::General;
use OMP::UserDB;
use Time::Piece qw/ :override /;
use Time::Seconds;
use Net::Domain qw/ hostfqdn /;

use Data::Dumper;

use strict;

$| = 1; # make output unbuffered
my $dbconnection = new OMP::DBbackend;
my $cgiquery = new CGI;
my $cgi = new OMP::CGI( CGI => $cgiquery );
$cgi->html_title( "shiftlog: Shift Log Tool" );

# Check to see if we're at one of the telescopes or not. Do this
# by a hostname lookup, then checking if we're on ulili (JCMT)
# or mauiola (UKIRT).
my $location;
my $hostname = hostfqdn;
if($hostname =~ /ulili/i) {
  $location = "JCMT";
} elsif ($hostname =~ /mauiola/i) {
  $location = "UKIRT";
} else {
  $location = "nottelescope";
}

#$location="UKIRT";

# Write the page, using the proper authentication on whether or
# not we're at one of the telescopes
if((uc($location) eq 'JCMT') || (uc($location) eq 'UKIRT')) {
  $cgi->write_page_noauth( \&shiftlog_output, \&shiftlog_output );
} else {
  $cgi->write_page( \&shiftlog_output, \&shiftlog_output );
}

sub shiftlog_output {
  my $query = shift;
  my %cookie = @_;

  my %vparams = ();
  my %params = $query->Vars;

  my $projectid = $cookie{'projectid'};
  my $password = $cookie{'password'};
  my $cookieuser = $cookie{'user'};

  if(length($projectid . "") == 0) {
    $projectid = 'staff';
    $password = 'kalapana';
  }

  # Verify the $query->param() hash.
  verify_query( \%params, \%vparams );

  # Verify the comment author is in the database.
  my $udb = new OMP::UserDB( DB => new OMP::DBbackend );
  if( defined( $vparams{'user'} ) ) {
    my $userVerified = $udb->verifyUser( $vparams{'user'} );
    if( ! $userVerified ) {
      print "<br>Could not verify user ID " . $vparams{'user'} . " in database.<br>\n";
      return;
    }
  } elsif( defined( $cookieuser ) ) {
    my $userVerified = $udb->verifyUser( $cookieuser );
    if( ! $userVerified ) {
      print "<br>Could not verify user ID " . $cookieuser . " in database.<br>\n";
      return;
    }
    $vparams{'user'} = $cookieuser;
  }

  # Print out the page.

  print_header();

  edit_comment( \%vparams );

  list_comments( $projectid, $password, \%vparams );

  display_form( \%vparams );

  print_footer( \%vparams );

} # end sub shiftlog_output

sub list_comments {
  my $projectid = shift;
  my $password = shift;
  my $verified = shift;

  my $verified_project;

  # Verify the project id with password
  my $projdb = new OMP::ProjDB( ProjectID => $projectid,
                                DB => $dbconnection );
  $verified_project = $projdb->verifyPassword( $password );

  if( !$verified_project ) {
    print "<br>Could not verify password for project $projectid.<br>\n";
    return;
  }

  my $date = $verified->{'date'};
  my $telescope = $verified->{'telescope'};

  # If the date given is in HST, we need to convert it to UT so the query knows
  # how to deal with it.
  my $ut;
  if( $verified->{'zone'} =~ /HST/i ) {
    my $hstdate = Time::Piece->strptime( $date, "%Y-%m-%d");
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

  # At this point we have an array of relevant Info::Comment
  # objects, so we can display them now.
  my $zone = $verified->{'zone'};
  print "<h2>Shift comments for $date $zone for $telescope</h2>\n";
  print "<table border=\"1\">\n";
  print "<tr><td><strong>HST time<br>User ID</strong></td><td><strong>comment</strong></td></tr>\n";
  foreach my $comment (@result) {
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

sub display_form {
  my $params = shift;

  print "<form action=\"shiftlog.pl\" method=\"post\"><br>\n";
  print "<table border=\"0\" width=\"100%\"><tr><td width=\"20%\">";
  print "Author:</td><td><input type=\"text\" name=\"user\" value=\"";
  print ( defined( $params->{'user'} ) ? $params->{'user'} : "");
  print "\"></td></tr>\n";
  print "<tr><td>Time: (HHMM or HH:MM format)</td><td><input type=\"text\" name=\"time\" value=\"";
  print "\"> " . $params->{'zone'} . " (will default to current time if blank)</td></tr>\n";
  print "<tr><td>Comment:</td><td><textarea name=\"text\" rows=\"16\" cols=\"50\">";
  print "</textarea></td></tr>\n";
  print "</table>\n";
  print "<input type=\"hidden\" name=\"date\" value=\"";
  print ( defined($params->{'date'}) ? $params->{'date'} : "" );
  print "\">\n";
  print "<input type=\"hidden\" name=\"zone\" value=\"";
  print ( defined( $params->{'zone'}) ? $params->{'zone'} : "" );
  print "\">\n";
  print "<input type=\"hidden\" name=\"telescope\" value=\"" . $params->{'telescope'} . "\">\n";
  print "<input type=\"submit\" value=\"submit comment\"> <input type=\"reset\">\n";
  print "</form>\n";
}

sub edit_comment {
  my $params = shift;

  # In order to edit a comment, we need at the bare minimum a date/time,
  # an author, some text, and a telescope.
  if( ! defined( $params->{'date'} ) ||
      ! defined( $params->{'time'} ) ||
      ! defined( $params->{'user'} ) ||
      ! defined( $params->{'text'} ) ||
      ! defined( $params->{'telescope'} ) ) {
    # Return silently.
    return;
  }

  my ($uthour, $utminute, $utday);
  # Form the date.

  $params->{'time'} =~ /(\d\d)(\d\d)/;
  my ($hour, $minute) = ($1, $2);

  my $datestring = $params->{'date'} . " $hour:$minute:00";
  my $datetime = Time::Piece->strptime( $datestring, "%Y-%m-%d %H:%M:%S" );

  # Convert the time zone to UT, if necessary.
  if( $params->{'zone'} =~ /HST/i) {
    $datetime += 10 * ONE_HOUR;
  }

  # Get the user.
  my $udb = new OMP::UserDB( DB => new OMP::DBbackend );
  my $user = $udb->getUser( $params->{'user'} );

  # Create an Info::Comment object.
  my $comment = new OMP::Info::Comment( author => $user,
                                        text => $params->{'text'},
                                        date => $datetime );

  # Update/add the comment.
  my $sdb = new OMP::ShiftDB( DB => new OMP::DBbackend );
  $sdb->enterShiftLog( $comment, $params->{'telescope'} );
}

sub verify_query {
  my $q = shift;
  my $v = shift;

  # The 'year' parameter is of the form yyyy-mm-dd
  if(defined($q->{'date'})) {
    if($q->{'date'} =~ /^\d{4}-\d\d-\d\d$/) {
      $v->{'date'} = $q->{'date'};
    } else {
      my ($sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdist) = gmtime(time);
      $v->{'date'} = ($year + 1900) . "-" . pad($month + 1, "0", 2) . "-" . pad($day, "0", 2);
    }
  } else {
    # Default this to the current UT date.
    my ($sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdist) = gmtime(time);
    $v->{'date'} = ($year + 1900) . "-" . pad($month + 1, "0", 2) . "-" . pad($day, "0", 2);
  }

  # The 'user' parameter is made of only alphabetical characters
  if(defined($q->{'user'})) {
    $v->{'user'} = $q->{'user'};
    $v->{'user'} =~ s/[^a-zA-Z]//g;
  }

  # The 'text' parameter can be anything
  if(defined($q->{'text'})) {
    $v->{'text'} = $q->{'text'};
    $v->{'text'} =~ s/\015//g; # get rid of ^M
  }

  # The 'zone' parameter is either HST or UT (default to UT)
  if(defined($q->{'zone'})) {
    if($q->{'zone'} =~ /HST/i) {
      $v->{'zone'} = 'HST';
    } else {
      $v->{'zone'} = 'UT';
    }
  } else {
    $v->{'zone'} = 'UT';
  }

  # The 'time' parameter is four digits or hh:mm
  if(defined($q->{'time'})) {
    if($q->{'time'} =~ /^\d{4}$/) {
      $v->{'time'} = $q->{'time'};
    } elsif($q->{'time'} =~ /^(\d\d):(\d\d)$/) {
      $v->{'time'} = $1 . $2;
    } else {
      my $time;
      if($v->{'zone'} eq 'HST') {
        $time = localtime;
      } else {
        $time = gmtime;
      }
      $v->{'time'} = pad($time->hour, '0', 2) . pad($time->min, '0', 2);
    }
  } else {
    my $time;
    if($v->{'zone'} eq 'HST') {
      $time = localtime;
    } else {
      $time = gmtime;
    }
    $v->{'time'} = pad($time->hour, '0', 2) . pad($time->min, '0', 2);
  }



  # The 'telescope' parameter is either JCMT or UKIRT (default to JCMT)
  if(defined($q->{'telescope'})) {
    if($q->{'telescope'} =~ /UKIRT/i) {
      $v->{'telescope'} = 'UKIRT';
    } else {
      $v->{'telescope'} = 'JCMT';
    }
  } else {
    $v->{'telescope'} = 'JCMT';
  }

}

=item B<print_header>

Prints a header.

  print_header();

There are no arguments.

=cut

sub print_header {
  print <<END;
Welcome to shiftlog. <a href="#changeut">Change the date</a>
<a href="#changetelescope">Change the telescope</a><br>
<hr>
END
};

=item B<print_footer>

Prints a footer.

  print_footer( \%params );

The parameter is a reference to a hash containing CGI query information.

=cut

sub print_footer {
  my $params = shift;

  print "<p><form action=\"shiftlog.pl\" method=\"post\"><br>";
  print "<a name=\"changeut\">New</a> date (yyyy-mm-dd format, please): ";
  print "<input type=\"text\" name=\"date\" value=\"\"> &nbsp;&nbsp;UT";
  print "<input type=\"radio\" name=\"zone\" value=\"ut\"";
  if(lc($params->{'zone'}) ne 'hst') {
    print " checked";
  }
  print "> HST <input type=\"radio\" name=\"zone\" value=\"hst\"";
  if(lc($params->{'zone'}) eq 'hst') {
    print " checked";
  }
  print "><br>\n";
  print "<input type=\"submit\" value=\"submit\"> <input type=\"reset\">\n";
  print "<input type=\"hidden\" name=\"telescope\" value=\"";
  print $params->{'telescope'};
  print "\"></form>\n";
  print "<form action=\"shiftlog.pl\" method=\"post\"><br>";
  print "<a name=\"changetelescope\">Change telescope:</a> JCMT ";
  print "<input type=\"radio\" name=\"telescope\" value=\"JCMT\"";
  if($params->{'telescope'} eq 'JCMT') {
    print " checked";
  }
  print ">";
  print " UKIRT <input type=\"radio\" name=\"telescope\" value=\"UKIRT\"";
  if($params->{'telescope'} eq 'UKIRT') {
    print " checked";
  }
  print "><br>";
  print "<input type=\"submit\" value=\"submit\"> <input type=\"reset\"></form>\n";
  print "<p>\n<hr>\n";
  print "<address>Last Modification Author: bradc<br>Brad Cavanagh ";
  print "(<a href=\"mailto:b.cavanagh\@jach.hawaii.edu\">b.cavanagh\@jach.hawaii.edu</a>)\n";
  print "</address>\n";
  print "</html>";
};

=item B<pad>

A routine that pads strings with characters.

  $padded = pad( $string, $character, $endlength );

The string paramter is the initial string, the character parameter is the character
you wish to pad the string with (at the beginning of the string), and the endlength
parameter is the final length in characters of the padded string.

=cut

sub pad {
  my ($string, $character, $endlength) = @_;
  my $result = ($character x ($endlength - length($string))) . $string;
}
