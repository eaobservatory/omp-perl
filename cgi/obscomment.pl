#!/local/perl-5.6/bin/perl

use CGI;
use CGI::Carp qw/fatalsToBrowser/;

#use lib qw(/jac_sw/omp/msbserver);
use lib qw(/home/bradc/development/omp/msbserver);
use OMP::CGI;
use OMP::Info::Obs;
use OMP::Info::Comment;
use OMP::ArchiveDB;
use OMP::ObslogDB;
use OMP::Constants;

use Data::Dumper;

use strict;

my @instruments = qw/cgs4 ircam michelle ufti uist scuba/;
my $cquery = new CGI;
my $cgi = new OMP::CGI( CGI => $cquery );

$cgi->write_page( \&obscomment_output, \&obscomment_output );

sub obscomment_output {

  my $query = shift;
  my %cookie = @_;

  my %params = $query->Vars;
  my $projectid = $cookie{'projectid'};
  my $password = $cookie{'password'};

# Verify the project id with password
  my $projdb = new OMP::ProjDB( ProjectID => $projectid,
                                DB => new OMP::DBbackend );
  my $verified = $projdb->verifyPassword( $password );
  if( !$verified ) {
    print "<br>Could not verify password for project $projectid.<br>n";
    return;
  }

# Verify the passed parameters
  my %vparams = verifyParams( \%params );

# Verify the comment author is in the database.
  my $udb = new OMP::UserDB( DB => new OMP::DBbackend );
  if( defined( $vparams{'author'} ) ) {
    my $userVerified = $udb->verifyUser( $vparams{'author'} );
    if( ! $userVerified ) {
      print "<br>Could not verify author " . $vparams{'author'} . " is in database.<br>\n";
      return;
    }
  }

# Update the comment, if necessary (the check will be done
# by the function and not in here).
  updateComment ( \%vparams );

# Display the observation and comment.
  displayComment( \%vparams );

# Display the form so people can edit things.
  displayForm( \%vparams );

# Put a link to get back to obslog
  $vparams{'ut'} =~ /^(\d{4}-\d\d-\d\d)/;
  print "<a href=\"obslog.pl?ut=$1&inst=" . $vparams{'inst'} . "\">back to obslog</a>\n";

# And that's it!

}

sub verifyParams {
  my $qparams = shift;
  my $vparams = {};

  # The 'ut' parameter is of the form yyyy-mm-dd-hh-mm-ss,
  # but the hours, minutes, and seconds will not have leading
  # zeros, so they can be either one or two digits long.
  if(defined($qparams->{'ut'})) {
    my $ut = $qparams->{'ut'};
    if($ut =~ /^\d{4}-\d\d-\d\d-\d{1,2}-\d{1,2}-\d{1,2}$/) {
      $vparams->{'ut'} = $ut;
    }
  }

  # The 'runnr' parameter is an integer
  if(defined($qparams->{'runnr'})) {
    my $runnr = $qparams->{'runnr'};
    $runnr =~ s/[^0-9]//g;
    $vparams->{'runnr'} = $runnr;
  }

  # The 'inst' parameter is a string made of alphanumerics,
  # and is to be in upper-case.
  if(defined($qparams->{'inst'})) {
    my $inst = $qparams->{'inst'};
    $inst =~ s/[^0-9a-zA-Z]//g;
    $vparams->{'inst'} = uc($inst);
  }

  # The 'author' parameter is a string made of alphanumerics
  if(defined($qparams->{'author'})) {
    my $author = $qparams->{'author'};
    $author =~ s/[^0-9a-zA-Z]//g;
    $vparams->{'author'} = $author;
  }

  # The 'status' parameter is an integer
  if(defined($qparams->{'status'})) {
    my $status = $qparams->{'status'};
    $status =~ s/[^0-9]//g;
    $vparams->{'status'} = $status;
  }

  # The 'text' parameter can be anything.
  if(defined($qparams->{'text'})) {
    $vparams->{'text'} = $qparams->{'text'};
  }

  return %$vparams;

}

sub updateComment {
  my $params = shift;

  if( ! defined( $params->{'author'} ) ||
      ! defined( $params->{'status'} ) ) {
    return;
  }

  if( ! defined( $params->{'ut'} ) ||
      ! defined( $params->{'runnr'} ) ||
      ! defined( $params->{'inst'} ) ) {
    print "Unable to store comment with no associated observation<br>\n";
    return;
  }

  my $startobs = Time::Piece->strptime( $params->{'ut'}, '%Y-%m-%d-%H-%M-%S' );

  my $obs = new OMP::Info::Obs ( runnr => $params->{'runnr'},
                                 startobs => $startobs,
                                 instrument => uc($params->{'inst'}) );

  my $udb = new OMP::UserDB( DB => new OMP::DBbackend );
  my $user = $udb->getUser( $params->{'author'} );

  my $comment = new OMP::Info::Comment( author => $user,
                                        text => $params->{'text'},
                                        status => $params->{'status'} );

  my $odb = new OMP::ObslogDB( DB => new OMP::DBbackend );
  $odb->addComment( $comment, $obs );

}

sub displayComment {
  my $params = shift;

  # To display a comment, we just need the relevant information
  # to form an Info::Obs object to grab the comment.

  if( ! defined( $params->{'ut'} ) ||
      ! defined( $params->{'runnr'} ) ||
      ! defined( $params->{'inst'} ) ) {
    return;
  }

  # Form the Time::Piece object.

  my $startobs = Time::Piece->strptime( $params->{'ut'}, '%Y-%m-%d-%H-%M-%S' );

  # Form the Info::Obs object.
  my $obs = new OMP::Info::Obs ( runnr => $params->{'runnr'},
                                 startobs => $startobs,
                                 instrument => uc($params->{'inst'}) );

  # Grab the most recent active comment.
  my $odb = new OMP::ObslogDB( DB => new OMP::DBbackend );
  my $comment = $odb->getComment( $obs );

  # Print it out.
  if(defined($comment)) {
    print "<table border=\"1\">\n";
    print "<tr><td><strong>Instrument</strong></td><td>";
    print $obs->{instrument};
    print "</td></tr>\n";
    print "<tr><td><strong>Observation date</strong></td><td>";
    print $obs->{startobs};
    print "</td></tr>\n";
    print "<tr><td><strong>Run number</strong></td><td>";
    print $obs->{runnr};
    print "</td></tr>\n";
    print "<tr><td><strong>Status</strong></td><td>";
    if($comment->status == OMP__OBS_GOOD) {
      print "Good";
    } elsif ($comment->status == OMP__OBS_QUESTIONABLE) {
      print "Questionable";
    } elsif ($comment->status == OMP__OBS_BAD) {
      print "Bad";
    } else {
      print "unknown";
    }
    print "</td></tr>\n<tr><td><strong>Author</strong></td><td>";
    print $comment->author->userid, " - ", $comment->author->name;
    print "</td></tr>\n<tr><td><strong>Comment Date</strong></td><td>";
    print $comment->date;
    print "</td></tr>\n<tr><td><strong>Comment</strong></td><td>";
    print $comment->text;
    print "</td></tr>\n";
    print "</table>\n";
  }
}

sub displayForm {
  my $params = shift;

  # First try to find out if there's a comment associated with this
  # observation.
  if( defined( $params->{'ut'} ) &&
      defined( $params->{'runnr'} ) &&
      defined( $params->{'inst'} ) ) {

    # Form the Time::Piece object.

    my $startobs = Time::Piece->strptime( $params->{'ut'}, '%Y-%m-%d-%H-%M-%S' );

    # Form the Info::Obs object.
    my $obs = new OMP::Info::Obs ( runnr => $params->{'runnr'},
                                   startobs => $startobs,
                                   instrument => uc($params->{'inst'}) );

    # Grab the most recent active comment.
    my $odb = new OMP::ObslogDB( DB => new OMP::DBbackend );
    my $comment = $odb->getComment( $obs );

    if(defined($comment)) {
      $params->{author} = $comment->author->userid;
      $params->{status} = $comment->status;
      $params->{text} = $comment->text;
    }
  }
  print "<form action=\"obscomment.pl\" method=\"post\"><br>\n";
  print "<table border=\"0\" width=\"40%\"><tr><td>";
  print "Author:</td><td><input type=\"text\" name=\"author\" value=\"";
  print ( defined($params->{author}) ? $params->{author} : "" );
  print "\"></td></tr>\n";
  print "<tr><td>Status:</td><td><select name=\"status\">\n";
  print "<option value=\"" . OMP__OBS_GOOD . "\"";
  if (!defined($params->{status}) ||
      ($params->{status} == OMP__OBS_GOOD)) { print " selected>"; }
  else { print ">"; }
  print "Good</option>\n";
  print "<option value=\"" . OMP__OBS_QUESTIONABLE . "\"";
  if ($params->{status} == OMP__OBS_QUESTIONABLE) { print " selected>"; }
  else { print ">"; }
  print "Questionable</option>\n";
  print "<option value=\"" . OMP__OBS_BAD . "\"";
  if ($params->{status} == OMP__OBS_BAD) { print " selected>"; }
  else { print ">"; }
  print "Bad</option>\n";
  print "</select></td></tr>\n";
  print "<tr><td colspan=\"2\"><textarea name=\"text\">";
  print defined($params->{text}) ? $params->{text} : "";
  print "</textarea></td></tr>\n";
  print "<tr><td><input type=\"hidden\" name=\"ut\" value=\"";
  print defined($params->{ut}) ? $params->{ut} : "";
  print "\">\n";
  print "<input type=\"hidden\" name=\"runnr\" value=\"";
  print defined($params->{runnr}) ? $params->{runnr} : "";
  print "\">\n";
  print "<input type=\"hidden\" name=\"inst\" value=\"";
  print defined($params->{inst}) ? $params->{inst} : "";
  print "\"></td></tr>\n";

  print "<tr><td colspan=\"2\"><input type=\"submit\" value=\"submit\"> <input type=\"reset\"></td></tr></table>\n";

}
