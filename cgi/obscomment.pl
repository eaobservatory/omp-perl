#!/local/perl-5.6/bin/perl

use CGI;
use CGI::Carp qw/fatalsToBrowser/;

use lib qw(/jac_sw/omp/msbserver);
use OMP::CGI;
use OMP::Info::Obs;
use OMP::Info::Comment;
use OMP::ArchiveDB;
use OMP::ObslogDB;
use OMP::Constants;
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

# And that's it!

}

sub verifyParams {
  my $qparams = shift;
  my $vparams = {};

  # The 'ut' parameter is of the form yyyy-mm-dd-hh-mm-ss.
  if(defined($qparams->{'ut'})) {
    my $ut = $qparams->{'ut'};
    if($ut =~ /^\d{4]-\d\d-\d\d-\d\d-\d\d-\d\d$/) {
      $vparams->{'ut'} = $ut;
    }
  }

  # The 'runnr' parameter is an integer
  if(defined($qparams->{'runnr'})) {
    my $runnr = $qparams->{'runnr'};
    $runnr =~ s/[^0-9]//g;
    $vparams->{'runnr'} = $runnr;
  }

  # The 'inst' parameter is a string made of alphanumerics
  if(defined($qparams->{'inst'})) {
    my $inst = $qparams->{'inst'};
    $inst =~ s/[^0-9a-zA-Z]//g;
    $vparams->{'inst'} = $inst;
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
    print "Unable to store comment with no valid author or status<br>\n";
    return;
  }

  if( ! defined( $params->{'ut'} ) ||
      ! defined( $params->{'runnr'} ) ||
      ! defined( $params->{'inst'} ) ) {
    print "Unable to store comment with no associated observation<br>\n";
    return;
  }

  my $startobs = Time::Piece->strptime( $params->{'ut'}, '%y-%m-%d-%H-%M-%S' );

  my $obs = new OMP::Info::Obs ( runnr => $params->{'runnr'},
                                 startobs => $startobs,
                                 instrument => $params->{'inst'} );

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
  my $startobs = Time::Piece->strptime( $params->{'ut'}, '%y-%m-%d-%H-%M-%s' );

  # Form the Info::Obs object.
  my $obs = new OMP::Info::Obs ( runnr => $params->{'runnr'},
                                 startobs => $startobs,
                                 instrument => $params->{'inst'} );

  # Grab the most recent active comment.
  my $odb = new OMP::ObslogDB( DB => new OMP::DBbackend );
  my $comment = $odb->getComment( $obs );

  # Print it out.
  print "<table border=\"1\">\n";
  print "<tr><td><strong>Instrument</strong></td><td>";
  print $comment->{instrument};
  print "</td></tr>\n";
  print "<tr><td><strong>Observation date</strong></td><td>";
  print $obs->{startobs};
  print "</td></tr>\n";
  print "<tr><td><strong>Run number</strong></td><td>";
  print $obs->{runnr};
  print "</td></tr>\n";
  print "<tr><td><strong>Status</strong></td><td>";
  if($comment->{Status} == OMP__OBS_GOOD) {
    print "Good";
  } elsif ($comment->{Status} == OMP__OBS_QUESTIONABLE) {
    print "Questionable";
  } elsif ($comment->{Status} == OMP__OBS_BAD) {
    print "Bad";
  } else {
    print "unknown";
  }
  print "</td></tr>\n<tr><td><strong>Author</strong></td><td>";
  print $comment->{Author}->userid, " - ", $comment->{Author}->name;
  print "</td></tr>\n<tr><td><strong>Comment Date</strong></td><td>";
  print $comment->{Date};
  print "</td></tr>\n<tr><td><strong>Comment</strong></td><td>";
  print $comment->{Text};
  print "</td></tr>\n";
  print "</table>\n";
}

sub displayForm {
  my $params = shift;

  print "<form action=\"obscomment.pl\" method=\"post\"><br>\n";
  print "Author: <input type=\"text\" name=\"author\" value=\"";
  print defined($params->{author}) ? $params->{author} : "";
  print "\"><br>\n";
  print "Status: <select name=\"status\">\n";
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
  print "</select>\n";
  print "<textarea name=\"text\" rows=\"20\" columns=\"80\">";
  print defined($params->{text}) ? $params->{text} : "";
  print "</textarea>\n";
  print "<input type=\"hidden\" name=\"ut\" value=\"";
  print defined($params->{ut}) ? $params->{ut} : "";
  print "\">\n";
  print "<input type=\"hidden\" name=\"runnr\" value=\"";
  print defined($params->{runnr}) ? $params->{runnr} : "";
  print "\">\n";
  print "<input type=\"hidden\" name=\"inst\" value=\"";
  print defined($params->{inst}) ? $params->{inst} : "";
  print "\">\n";

  print "<input type=\"submit\"> <input type=\"reset\"><br>\n";

}
