#!/local/perl-5.6/bin/perl -X
#
# WWW Observing Remotely Facility (WORF)
#
# http://www.jach.hawaii.edu/JACpublic/UKIRT/software/worf/
#
# Requirements:
# TBD
#
# Authors: Frossie Economou (f.economou@jach.hawaii.edu)
#          Brad Cavanagh (b.cavanagh@jach.hawaii.edu)

BEGIN { $ENV{'ORAC_DIR'} = "/jcmt_sw/oracdr"; }

use CGI;
use CGI::Carp qw/fatalsToBrowser/;
use PDL::Graphics::LUT;

use lib qw(/jac_sw/omp/msbserver);
#use lib qw( /home/bradc/development/omp/msbserver);
use OMP::CGI;
use OMP::Info::Obs;
use OMP::ArchiveDB;
use OMP::ObslogDB;
use OMP::BaseDB;
use OMP::DBbackend::Archive;
use Net::Domain qw/ hostfqdn /;

use strict;

# Define colours.
my @colour = qw/ BLACK #660000 #FFCCCC /;

# Undefine the orac_warn filehandle
my $Prt = new ORAC::Print;
$Prt->warhdl(undef);

# Set up global variables, system variables, etc.

$| = 1;  # make output unbuffered

my @instruments = qw/ scuba cgs4 ircam michelle ufti uist /;
my $cquery = new CGI;
my $cgi = new OMP::CGI( CGI => $cquery );
$cgi->html_title("obslog: Observation Log Tool");

my $dbconnection = new OMP::DBbackend;

# Set up the UT date
my $current_ut;
  {
    my ($sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdist) = gmtime(time);
    $current_ut = ($year + 1900) . "-" . pad($month + 1, "0", 2) . "-" . pad($day, "0", 2);
#    $current_ut = '2002-06-02';
  }

# Check to see if we're at one of the telescopes or not. Do this
# by a hostname lookup, then checking if we're on ulili (JCMT)
# or mauiola (UKIRT).
my $location;
my $hostname = hostfqdn;
if($hostname =~ /ulili/i) {
  $location = "jcmt";
} elsif ($hostname =~ /mauiola/i) {
  $location = "ukirt";
} else {
  $location = "nottelescope";
}

# Write the page, using the proper authentication on whether or
# not we're at one of the telescopes
if(($location eq "jcmt") || ($location eq "ukirt")) {
  $cgi->write_page_noauth( \&obslog_output, \&obslog_output );
} else {
  $cgi->write_page( \&obslog_output, \&obslog_output );
}

sub obslog_output {
# this subroutine is basically the "main" subroutine for this CGI

# First, pop off the CGI object and the cookie hash

  my $query = shift;
  my %cookie = @_;

  my %verified = ();
  my %params = $query->Vars;

  my $projectid = $cookie{'projectid'};
  my $password = $cookie{'password'};
  if(length($projectid . "") == 0) {
    $projectid = 'staff';
    $password = 'kalapana';
  }
# Verify the $query->param() hash
  verify_query( \%params, \%verified );

# Set the desired UT date.
  my $ut = $verified{'ut'} || $current_ut;

# Print out the page
print "<META HTTP-EQUIV=\"refresh\" content=\"300;URL=obslog.pl?ut=$ut&inst=" . $verified{'inst'} . "&collapse=" . $verified{'collapse'} . "\">\n";

  print_header();

  list_observations( $projectid, $password, $ut, \%verified );

  print_footer();

} # end sub obslog_output


sub list_observations {
  my $projectid = shift;
  my $password = shift;
  my $ut = shift;
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

  if( !defined($ut) ) {
    print "<br>Error: UT date not defined (this shouldn't be possible).<br>\n";
    return;
  }

  my @instarray;
  if($location eq 'jcmt') {
    push @instarray, "scuba";
  } elsif($location eq 'ukirt') {
    push @instarray, qw/ cgs4 ircam michelle ufti uist /;
  } else {
    push @instarray, @instruments;
  }

  my %results;

  # Grab the Info::Obs objects from either the archive or off disk for each
  # available instrument.
  foreach my $inst (@instarray) {

    # Form the XML.
    my $xml = "<ArcQuery><instrument>$inst</instrument><date delta=\"1\">$ut</date>";
    if( ! OMP::General->am_i_staff( $projectid ) ) {
      $xml .= "<projectid>$projectid</projectid>";
    }
    $xml .= "</ArcQuery>";

    # Form the query.
    my $arcquery = new OMP::ArcQuery( XML => $xml );

    # Grab the results.
    my $adb = new OMP::ArchiveDB( DB => new OMP::DBbackend::Archive );
    my @result = $adb->queryArc( $arcquery );

    # Sort them by reverse date
    @result = sort {$b->startobs->epoch <=> $a->startobs->epoch} @result;

    # Push the results array into the results hash (keyed by instrument).
    $results{$inst} = \@result;
  }

  # At this point we have a collection of relevant Info::Obs objects.
  # Display them.

  print "<table border=\"1\">\n<tr><td><strong>";

  # Form the header, made up of instrument names and the number of
  # observations for that instrument.
  my @header;
  foreach my $inst (sort keys %results) {
    my $header = "<a href=\"obslog.pl?inst=$inst&ut=$ut\">$inst (" . scalar(@{$results{$inst}}) . ")</a>";
    push @header, $header;
  }
  print join "</strong></td><td><strong>", @header;
  print "</table><br>\n";

  # Now print the observations for either the first instrument that
  # has observations or the instrument passed in the HTML form.
  my $firstinst;
  if( ! defined( $verified->{'inst'} ) ) {
    foreach my $inst (sort keys %results) {
      if( scalar( @{$results{$inst}} ) > 0 ) {
        $firstinst = $inst;
        last;
      }
    }
  } else {
    $firstinst = $verified->{'inst'};
  }
  print "<h2>Observations for $firstinst for $ut</h2>\n";
  if($verified->{'collapse'} eq 'f') {
    print "<a href=\"obslog.pl?inst=$firstinst&ut=$ut&collapse=t\">Don't show comments</a>\n";
  } else {
    print "<a href=\"obslog.pl?inst=$firstinst&ut=$ut&collapse=f\">Show comments</a>\n";
  }
  print "&nbsp;Colour legend: <font color=\"" . $colour[0] . "\">good</font> <font color=\"" . $colour[1] . "\">questionable</font> <font color=\"" . $colour[2] . "\">bad</font><br>\n";
  print "<table border=\"1\">\n<tr><td>";

  # Print the headers.
  if( defined( ${$results{$firstinst}}[0] )) {
    my %nightlog = ${$results{$firstinst}}[0]->nightlog;
    print join("</td><td>", @{$nightlog{_ORDER}} );
    print "</td><td>Comments</td></tr>\n";
  }

  my $odb = new OMP::ObslogDB( DB => new OMP::DBbackend );

  # Print each observation.
  foreach my $obs (@{$results{$firstinst}}) {

    # Grab the comment (if there is one) so we know what colour to
    # make the observation.
    my $comment = $odb->getComment( $obs );
    my $colour;
    if(defined($comment)) {
      my $status = $comment->status . "";
      $colour = $colour[$status];
    } else {
      $colour = $colour[0];
    }
    print "<tr><td><font color=\"" . $colour . "\">";
    my %nightlog = $obs->nightlog;
    print join("</font></td><td><font color=\"" . $colour . "\">", map {
      ref($nightlog{$_}) eq "ARRAY" ? join ', ', @{$nightlog{$_}} : $nightlog{$_};
    } @{$nightlog{_ORDER}} );
    print "</font></td><td><a href=\"obscomment.pl?ut=";
    my $obsut = $obs->startobs->ymd . "-" . $obs->startobs->hour;
    $obsut .= "-" . $obs->startobs->minute . "-" . $obs->startobs->second;
    print $obsut;
    print "&runnr=" . $obs->runnr . "&inst=" . $firstinst . "\">edit/view</a></td></tr>\n";
    # "Print each observation," he says. As easy as that, eh?

    # Print the comment underneath, if there is one, and if the 'collapse'
    # query parameter is 'f'.
    if(defined($comment) && $verified->{'collapse'} eq 'f') {
      print "<tr><td></td><td colspan=\"" . (scalar(@{$nightlog{_ORDER}})) . "\"><font color=\"$colour\">";
      print "<strong>" . $comment->date->cdate . " UT / " . $comment->author->userid . ":";
      print "</strong> " . $comment->text;
      print "</font></td></tr>\n";
    }
  }

  print "</td></tr></table>";
}

sub verify_query {
  my $q = shift;
  my $v = shift;

  if($q->{inst}) {

# The 'inst' parameter must match one of the strings listed in the
# @instrument array. If it doesn't, set it to an empty string.

    # first, strip out anything that's not a letter or a number

    my $t_instrument = $q->{inst};
    $t_instrument =~ s/[^a-zA-Z0-9]//g;

    # this parameter needs to match exactly one of the strings listed in @instruments
    foreach my $t_inst (@instruments) {
      if(uc($t_instrument) eq uc($t_inst)) {
        $v->{inst} = $t_inst;
      }
    }
  }

  # The 'ut' parameter is of the form yyyy-mm-dd
  if(defined($q->{ut})) {
    my $ut = $q->{'ut'};
    if($ut =~ /^\d{4}-\d\d-\d\d$/) {
      $v->{'ut'} = $ut;
    }
  }

  # The 'collapse' parameter is either 't' or 'f' (defaults to 'f')
  if(defined($q->{'collapse'})) {
    if($q->{'collapse'} =~ /^t$/i) {
      $v->{'collapse'} = 't';
    } else {
      $v->{'collapse'} = 'f';
    }
  } else {
    $v->{'collapse'} = 'f';
  }

}

=item B<print_header>

Prints a header.

  print_header();

There are no arguments.

=cut

sub print_header {
  print <<END;
Welcome to obslog. <a href="#changeut">Change the UT date</a><br>
<hr>
END
};

=item B<print_footer>

Prints a footer.

  print_footer();

There are no arguments.

=cut

sub print_footer {
  print <<END;
  <p><form action="obslog.pl" method="post"><br>
<a name="changeut">New</a> UT date (yyyy-mm-dd format, please): <input type="text" name="ut" value=""><br>
<input type="submit" value="submit"> <input type="reset">
  <p>
  <hr>
  <address>Last Modification Author: bradc<br>Brad Cavanagh (<a href="mailto:b.cavanagh\@jach.hawaii.edu">b.cavanagh\@jach.hawaii.edu</a>)</address>
</html>
END
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
