package OMP::CGIObslog;

=head1 NAME

OMP::CGIObslog - CGI functions for the observation log tool.

=head1 SYNOPSIS

use OMP::CGIObslog;

=head1 DESCRIPTION

This module provides routines used for CGI-related functions for
obslog -- variable verification, form creation, etc.

=cut

use strict;
use warnings;
use Carp;

use CGI;
use CGI::Carp qw/fatalsToBrowser/;
use Net::Domain qw/ hostfqdn /;

use OMP::CGI;
use OMP::Constants;
use OMP::General;
use OMP::Info::Comment;
use OMP::Info::Obs;
use OMP::Info::ObsGroup;
use OMP::ObslogDB;
use OMP::BaseDB;
use OMP::ArchiveDB;
use OMP::DBbackend::Archive;
use OMP::WORF;
use OMP::Error qw/ :try /;

use Data::Dumper;

our $VERSION = (qw$Revision$ )[1];

require Exporter;

our @ISA = qw/Exporter/;
our @EXPORT = qw( obs_table obs_summary obs_comment_form
                  file_comment file_comment_output list_observations
                  obs_add_comment cgi_to_obs cgi_to_obsgroup );
our %EXPORT_TAGS = (
                    'all' => [ @EXPORT ]
                    );

Exporter::export_tags(qw/ all /);

# Colours for displaying observation status. First is 'good', second
# is 'questionable', third is 'bad'.
our @colour = ( "BLACK", "#BB3333", "#FF3300" );

=head1 Routines

All routines are exported by default.

=over 4

=item B<file_comment>

Creates a page with a form for filing a comment.

  file_comment( $cgi );

Only argument should be the C<CGI> object.

=cut

sub file_comment {
  my $q = shift;
  my %cookie = @_;

  # Get the Info::Obs object
  my $obs = cgi_to_obs( $q );

  # Print a summary about the observation.
  obs_summary( $q, $obs );

  # Display a form for adding a comment.
  obs_comment_form( $q, $obs, \%cookie );

  # Print a footer
  print_obscomment_footer( $q );

}

=item B<file_comment_output>

Submit a comment and create a page with a form for filing a comment.

  file_comment_output( $cgi );

Only argument should be the C<CGI> object.

=cut

sub file_comment_output {
  my $q = shift;
  my %cookie = @_;

  # Insert the comment into the database.
  obs_add_comment( $q );

  # Get the updated Info::Obs object.
  my $obs = cgi_to_obs( $q );

  # Print a summary about the observation.
  obs_summary( $q, $obs );

  # Display a form for adding a comment.
  obs_comment_form( $q, $obs, \%cookie );

  # Print a footer
  print_obscomment_footer( $q );

}

=item B<list_observations>

Create a page containing a list of observations.

  list_observations( $cgi );

Only argument should be the C<CGI> object.

=cut

sub list_observations {
  my $q = shift;
  my %cookie = @_;

  print_obslog_header();

  my ($inst, $ut);

  ( $inst, $ut ) = obs_inst_summary( $q, \%cookie );

  my $tempinst;
  if( $inst =~ /rxa/i ) { $tempinst = "rxa3"; }
  elsif( $inst =~ /rxb/i ) { $tempinst = "rxb3"; }
  else { $tempinst = $inst; }

  my $telescope = OMP::Config->inferTelescope( 'instruments', $tempinst );

  if( defined( $inst ) &&
      defined( $ut ) ) {
    # We need to get an Info::ObsGroup object for this query object.
    my $obsgroup;
    try {
      $obsgroup = cgi_to_obsgroup( $q, ut => $ut, telescope => $telescope );
#      print "<h2>Observations for $inst on $ut</h2><br>\n";
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

    # And display the table.
    my %options;
    $options{'showcomments'} = 1;
    $options{'ascending'} = 0;
    $options{'instrument'} = $inst;
    try {
      obs_table( $obsgroup, %options );
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
  } else {
      print "<table width=\"600\" class=\"sum_table\" border=\"0\">\n<tr class=\"sum_table_head\"><td>";
      print "<strong class=\"small_title\">Observation Log</strong></td></tr>\n";
      print "<tr class=\"sum_other\"><td>No observations available</td></tr></table>\n";
  }

  print_obslog_footer( $q );

}

=item B<obs_table>

Prints an HTML table containing a summary of information about a
group of observations.

  obs_table( $obsgroup, $options );

The first argument is the C<OMP::Info::ObsGroup>
object, and the second optional argument tells the function how to
display things. It is a hash reference optionally containing the
following keys:

=over 4

=item *

showcomments - Boolean on whether or not to print comments [true].

=item *

ascending - Boolean on if observations should be printed in
chronologically ascending or descending order [true].

=item *

sort - Determines the order in which observations are displayed.
If set to 'chronological', then the observations in the given
C<Info::ObsGroup> object will be displayed in chronological order,
with table breaks occurring whenever an instrument changes. If
set to 'instrument', then one table will be displayed for each
instrument in the C<Info::ObsGroup> object, regardless of the order
in which observations for those instruments were taken. Defaults
to 'instrument'.

=back

This function will print a colour legend before the table.

=cut

sub obs_table {
  my $obsgroup = shift;
  my %options = @_;

  # Check the arguments.
  my $showcomments;
  if( exists( $options{showcomments} ) ) {
    $showcomments = $options{showcomments};
  } else {
    $showcomments = 1;
  }

  my $sort;
  if( exists( $options{sort} ) ) {
    if( $options{sort} =~ /^chronological/i ) {
      $sort = 'chronological';
    } else {
      $sort = 'instrument';
    }
  } else {
    $sort = 'instrument';
  }

  my $ascending;
  if( exists( $options{ascending} ) ) {
    $ascending = $options{ascending};
  } else {
    $ascending = 1;
  }

  my $instrument;
  if( exists( $options{instrument} ) ) {
    $instrument = $options{instrument};
  } else {
    $instrument = '';
  }

# Verify the ObsGroup object.
  if( ! UNIVERSAL::isa($obsgroup, "OMP::Info::ObsGroup") ) {
    throw OMP::Error::BadArgs("Must supply an Info::ObsGroup object")
  }

  my @allobs;

  # Make the array of Obs objects.
  if( $sort eq 'instrument' ) {

    my %grouped = $obsgroup->groupby('instrument');
    foreach my $inst (sort keys %grouped) {
      my @obs;
      if( $ascending ) {
        @obs = sort { $a->startobs->epoch <=> $b->startobs->epoch } $grouped{$inst}->obs;
      } else {
        @obs = sort { $b->startobs->epoch <=> $b->startobs->epoch } $grouped{$inst}->obs;
      }
      push @allobs, @obs;
    }
  } else {
    if( $ascending ) {
      @allobs = sort { $a->startobs->epoch <=> $b->startobs->epoch } $obsgroup->obs;
    } else {
      @allobs = sort { $b->startobs->epoch <=> $a->startobs->epoch } $obsgroup->obs;
    }
  }

  my $currentinst = (length( $instrument . '' ) == 0 ) ? $allobs[0]->instrument : $instrument;

  print "<table width=\"600\" class=\"sum_table\" border=\"0\">\n<tr class=\"sum_table_head\"><td>";
  print "<strong class=\"small_title\">Observation Log</strong></td></tr>\n";
  print "<tr class=\"sum_other\"><td>";
  print "Colour legend: <font color=\"" . $colour[0] . "\">good</font> <font color=\"" . $colour[1] . "\">questionable</font> <font color=\"" . $colour[2] . "\">bad</font></td></tr>\n";
  print "</table>";

  if(!defined($currentinst)) {
    print "<table width=\"600\" class=\"sum_table\" border=\"0\">\n";
    print "<tr class=\"sum_other\"><td>No observations available</td></tr></table>\n";
    return;
  }

  # Start off the table.

  # Get the headings from the first observation. Note that we have to test
  # if it's a timegap or not, because if it is it'll throw an Xbox-sized spanner
  # into the whole mess.
  my %nightlog;
  foreach my $obshdr (@allobs) {
    if(!UNIVERSAL::isa($obshdr, "OMP::Info::Obs::TimeGap") && uc($obshdr->instrument) eq uc($currentinst)) {
      %nightlog = $obshdr->nightlog;
      last;
    }
  }

  my $ncols = scalar(@{$nightlog{_ORDER}}) + 2;
  print "<table class=\"sum_table\" border=\"0\">\n";
  print "<tr class=\"sum_other\"><td colspan=\"$ncols\"><div class=\"small_title\">Observations for " . uc($currentinst) . "</div></td></tr>\n";

  # Print the column headings.
  print "<tr class=\"sum_other\"><td>";
  print join ( "</td><td>", @{$nightlog{_ORDER}} );
  print "</td><td>Comments</td><td>WORF</td></tr>\n";

  my $rowclass = "row_b";

  foreach my $obs (@allobs) {

    next if( ( length( $instrument . '' ) > 0 ) &&
             ( uc( $instrument ) ne uc( $obs->instrument ) ) );

    my %nightlog = $obs->nightlog;
    # First, check to see if the instrument has changed. If it has, close the old table
    # and start a new one.
    if( uc($obs->instrument) ne uc($currentinst) && !UNIVERSAL::isa($obs, "OMP::Info::Obs::TimeGap") ) {
      print "</table>\n";
      $currentinst = $obs->instrument;
      print "<table class=\"sum_table\" border=\"0\">\n";
      print "<tr class=\"sum_other\"><td colspan=\"$ncols\"><div class=\"small_title\">Observations for " . uc($currentinst) . "</div></td></tr>\n";

      # Print the column headings.
      print "<tr class=\"sum_other\"><td>";
      print join ( "</td><td>", @{$nightlog{_ORDER}} );
      print "</td><td>Comments</td></tr>\n";
    }

    my $comments = $obs->comments;
#    my $status = ( defined( $comments->[0] ) ? $comments->[0]->status : 0 );
    my $status = $obs->status;
    my $colour = defined( $status ) ? $colour[$status] : $colour[0];
    my $instrument = $obs->instrument;
    if( UNIVERSAL::isa( $obs, "OMP::Info::Obs::TimeGap") ) {
      print "<tr class=\"$rowclass\"><td colspan=\"" . ( $ncols - 1 ) . "\"><font color=\"BLACK\">";
      $nightlog{'_STRING'} =~ s/\n/\<br\>/g;
      print $nightlog{'_STRING'};
    } else {
      print "<tr class=\"$rowclass\"><td><font color=\"$colour\">";
      print join("</font></td><td><font color=\"$colour\">" , map {
        ref($nightlog{$_}) eq "ARRAY" ? join ', ', @{$nightlog{$_}} : $nightlog{$_};
      } @{$nightlog{_ORDER}} );
    }
    print "</font></td><td><a class=\"link_dark_small\" href=\"obscomment.pl?ut=";
    my $obsut = $obs->startobs->ymd . "-" . $obs->startobs->hour;
    $obsut .= "-" . $obs->startobs->minute . "-" . $obs->startobs->second;
    print $obsut;
    print "&runnr=" . $obs->runnr . "&inst=" . $instrument;
    if( UNIVERSAL::isa( $obs, "OMP::Info::Obs::TimeGap" ) ) {
      print "&timegap=1";
    }
    print "\">edit/view</a></td>";

    # Display WORF box if we do not have a TimeGap.
    if( !UNIVERSAL::isa( $obs, "OMP::Info::Obs::TimeGap" ) ) {

      # Form an OMP::WORF object for the obs
      my $worf = new OMP::WORF( obs => $obs );

      # Get a list of suffices
      my @ind_suffices = $worf->suffices;
      my @grp_suffices = $worf->suffices( 1 );

      print "<td><a class=\"link_dark_small\" href=\"worf.pl?ut=";
      print $obsut;
      print "&runnr=" . $obs->runnr . "&inst=" . $instrument;
      print "\">raw</a> ";
      foreach my $suffix ( @ind_suffices ) {
        next if ! $worf->file_exists( suffix => $suffix, group => 0 );
        print "<a class=\"link_dark_small\" href=\"worf.pl?ut=";
        print $obsut;
        print "&runnr=" . $obs->runnr . "&inst=" . $instrument;
        print "&suffix=$suffix\">$suffix</a> ";
      }
      print "/ ";
      if( $worf->file_exists( suffix => '', group => 1 ) ) {
        print "<a class=\"link_dark_small\" href=\"worf.pl?ut=";
        print $obsut;
        print "&runnr=" . $obs->runnr . "&inst=" . $instrument;
        print "&group=1\">group</a> ";
      }
      foreach my $suffix ( @grp_suffices ) {
        next if ! $worf->file_exists( suffix => $suffix, group => 1 );
        print "<a class=\"link_dark_small\" href=\"worf.pl?ut=";
        print $obsut;
        print "&runnr=" . $obs->runnr . "&inst=" . $instrument;
        print "&suffix=$suffix&group=1\">$suffix</a> ";
      }
      print "</td>";
    } else {
      print "<td>&nbsp;</td>";
    }
    print "</tr>\n";

    # Print the comments underneath, if there are any, and if the
    # 'showcomments' parameter is not '0', and if we're not looking at a timegap
    # (since timegap comments show up in the nightlog string)
    if( defined( $comments ) &&
        defined( $comments->[0] ) &&
        $showcomments &&
        ! UNIVERSAL::isa( $obs, "OMP::Info::Obs::TimeGap" ) ) {

      print "<tr class=\"$rowclass\"><td colspan=\"" . (scalar(@{$nightlog{_ORDER}}) + 2) . "\">";
      my @printstrings;
      foreach my $comment (@$comments) {
        my $string = "<font color=\"";
        $string .= $colour[$comment->status];
        $string .= "\">" . $comment->date->cdate . " UT / " . $comment->author->name . ":";
        $string .= " " . $comment->text;
        $string .= "</font>";
        $string =~ s/\n/\<br\>/g;
        push @printstrings, $string;
      }
      if($#printstrings > -1) {
        print join "<br>", @printstrings;
      };
      print "</td></tr>\n";
    }

    $rowclass = ( $rowclass eq 'row_a' ) ? 'row_b' : 'row_a';

  }

  # And finish the table.
  print "</table>\n";

}

=item B<obs_summary>

Prints a table containing a summary about a given observation

  obs_summary( $cgi, $obs );

The first argument is a C<CGI> object, and the second is an
C<Info::Obs> object.

=cut

sub obs_summary {
  my $cgi = shift;
  my $obs = shift;

  # Verify that we do have an Info::Obs object.
  if( ! UNIVERSAL::isa( $obs, "OMP::Info::Obs" ) ) {
    throw OMP::Error::BadArgs("Must supply an Info::Obs object");
  }

  my @comments = $obs->comments;

  print "<table width=\"600\" border=\"0\" class=\"sum_table\">\n";
  print "<tr class=\"sum_table_head\"><td><strong class=\"small_title\">";
  print "Comment for ";
  print $obs->instrument;

  if( UNIVERSAL::isa( $obs, "OMP::Info::Obs::TimeGap" ) ) {
    print " timegap between observations ";
    print ( $obs->runnr - 1 );
    print " and ";
    print $obs->runnr;
  } else {
    print " observation ";
    print $obs->runnr;
  }
  print " on " . $obs->startobs->ymd;
  print "</strong></td></tr></table>\n";

  if( defined( $comments[0] ) ) {
    print "<table border=\"0\" class=\"sum_table\" width=\"600\">";

    my $rowclass = 'row_a';
    foreach my $comment (@comments) {
      print "<tr class=\"$rowclass\"><td>";
      my $string = "<font color=\"";
      $string .= ( defined( $colour[$comment->status] ) ) ? $colour[$comment->status] : "BLACK";
      $string .= "\"><strong>" . $comment->date->cdate . " UT / " . $comment->author->name . ":";
      $string .= "</strong> " . $comment->text;
      $string .= "</font>";
      $string =~ s/\n/\<br\>/g;
      print $string . "</td></tr>";
      $rowclass = ( $rowclass eq 'row_a' ) ? 'row_b' : 'row_a';
    }
    print "</table>\n";
  }
}

=item B<obs_inst_summary>

Prints a table summarizing observations taken for a telescope,
broken up by instrument.

  ( $inst, $ut ) = obs_inst_summary( $q );

The first argument must be a C<CGI> object.

The function will return the name of the active instrument in the
table and the UT date for the observations. These two values are
normally given in the C<CGI> object.

An instrument is "active" if it is given in the C<CGI> object. If
no instrument is defined in the C<CGI> object, then the first
instrument in the table (listed alphabetically) that has one or
more observations for the UT date is considered "active".

If a UT date is not supplied in the C<CGI> object, then the returned
UT date will be the current one, and the table will give a summary
of observations for the current UT date.

=cut

sub obs_inst_summary {
  my $q = shift;
  my $cookie = shift;

  my $qv = $q->Vars;

  my $ut = ( defined( $qv->{'ut'} ) ? $qv->{'ut'} : OMP::General->today() );

  my $firstinst;
  if( defined( $qv->{'inst'} ) ) {
    $firstinst = $qv->{'inst'};
  }

  my $telescope;
  # Form an instrument array, depending on where we're at. If we don't know
  # where we are, just push every single instrument onto the array.
  #
  # First, check the 'projectid' in the cookie.
  my $projectid = $cookie->{'projectid'};
  if( defined( $projectid ) && ! OMP::General->am_i_staff( $projectid ) ) {
    my $proj = new OMP::ProjDB( ProjectID => $projectid,
                                DB => new OMP::DBbackend );
    if( defined( $proj ) ) {
      $telescope = uc( $proj->telescope );
    }
  }

  if( ! defined( $telescope ) ) {

    # Okay, the cookie didn't work, or we're on the staff project.
    # Check the hostname of the computer the script is running on.
    # If it's ulili, we're at JCMT. If it's mauiola, we're at UKIRT.
    # Otherwise, we don't know where we are.
    my $hostname = hostfqdn;
    if( $hostname =~ /ulili/i ) {
      $telescope = "JCMT";
    } elsif( $hostname =~ /mauiola/i ) {
      $telescope = "UKIRT";
    }
  }

# DEBUGGING ONLY
#$telescope = "JCMT";
#$telescope = "UKIRT";

  if( ! defined( $telescope ) ) {
    throw OMP::Error( "Unable to determine telescope" );
  }

  # Form an ObsGroup object for the telescope.
  my %results;
  try {
    my $grp = new OMP::Info::ObsGroup( telescope => $telescope,
                                       date => $ut,
                                     );

    %results = $grp->groupby('instrument');
  }
  catch OMP::Error with {
    my $Error = shift;
    print "Error in CGIObslog::obs_inst_summary: " . $Error->{'-text'} . "\n";
  }
  otherwise {
    my $Error = shift;
    print "Error in CGIObslog::obs_inst_summary: " . $Error->{'-text'} . "\n";
  };

  my @printarray;
  if( scalar keys %results ) {
    print "<table border=\"0\" class=\"sum_table\"><tr class=\"sum_table_head\"><td><strong class=\"small_title\">";
    foreach my $inst ( sort keys %results ) {
      my $header = "<a style=\"color: #05054f;\" href=\"obslog.pl?inst=$inst&ut=$ut\">$inst (" . scalar(@{$results{$inst}->obs}) . ")</a>";
      push @printarray, $header;
      if( ! defined( $firstinst ) && scalar(@{$results{$inst}->obs}) > 0 ) {
        $firstinst = $inst;
      }
    }
    print join "</strong></td><td><strong class=\"small_title\">", @printarray;
    print "</strong></td></tr></table><br>\n";

    return ( $firstinst, $ut );

  } else {
    return ( undef, undef );
  }

}

=item B<obs_comment_form>

Prints a form that is used to enter a comment about an observation.

  obs_comment_form( $cgi, $obs, $cookie );

The first argument must be a C<CGI> object, the second must be an
C<Info::Obs> object, and the third is a hash reference containing
cookie information.

=cut

sub obs_comment_form {
  my $q = shift;
  my $obs = shift;
  my $cookie = shift;

  my %status_label = ( 0 => 'Good',
                       1 => 'Questionable',
                       2 => 'Bad' ) ;
  my @status_value = qw/ 0 1 2 /;

  my %timegap_label = ( 10 => 'Instrument',
                        11 => 'Weather',
                        12 => 'Fault',
                        13 => 'Unknown',
                        14 => 'Next Project',
                        15 => 'Last Project',
                      );
  my @timegap_value = qw/ 10 11 12 15 14 13 /;

  # Verify we have an Info::Obs object.
  if( ! UNIVERSAL::isa($obs, "OMP::Info::Obs") ) {
    throw OMP::Error::BadArgs("Must supply Info::Obs object");
  }

  print $q->startform;
  print "<table border=\"0\" width=\"100%\"><tr><td width=\"20%\">";
  print "Author: </td><td>";

  print $q->textfield( -name => 'user',
                       -size => '16',
                       -maxlength => '90',
                       -default => $cookie->{user},
                     );

  print "</td></tr>\n";
  print "<tr><td>Status: </td><td>";

  my $status = $obs->status;
  my $comments = $obs->comments;
  if( UNIVERSAL::isa( $obs, "OMP::Info::Obs::TimeGap" ) ) {

    print $q->popup_menu( -name => 'status',
                          -values => \@timegap_value,
                          -labels => \%timegap_label,
                          -default => $status,
                        );
  } else {

    print $q->popup_menu( -name => 'status',
                          -values => \@status_value,
                          -labels => \%status_label,
                          -default => $status,
                        );
  }

  print "</td></tr>\n";
  print "<tr><td colspan=\"2\">";

  print $q->textarea( -name => 'text',
                      -rows => 20,
                      -columns => 78,
                      -default => ( defined( $comments ) && defined( $comments->[0] ) ?
                                    $comments->[0]->text :
                                    "" ),
                    );

  my $ut = $obs->startobs->ymd;
  my $runnr = $obs->runnr;
  my $instrument = $obs->instrument;
  print $q->hidden( -name => 'ut',
                    -value => $ut,
                  );
  print $q->hidden( -name => 'runnr',
                    -value => $runnr,
                  );
  print $q->hidden( -name => 'inst',
                    -value => $instrument,
                  );
  print $q->hidden( -name => 'timegap',
                    -value => UNIVERSAL::isa( $obs, "OMP::Info::Obs::TimeGap" ),
                  );

  print "</td></tr>\n<tr><td colspan=\"2\">";

  print $q->submit( -name => 'Submit Comment' );

  print "</td></tr></table>\n";

  print $q->endform;

}

=item B<obs_add_comment>

Store a comment in the database.

  obs_add_comment( $cgi );

The only argument should be the C<CGI> object.

=cut

sub obs_add_comment {
  my $q = shift;

  # Set up variables.
  my $qv = $q->Vars;
  my $user = $qv->{'user'};
  my $status = $qv->{'status'};
  my $text = ( defined( $qv->{'text'} ) ? $qv->{'text'} : "" );

  if( ! defined($user)) {
#    print "Must supply user in order to store a comment.<br>\n";
    return;
  }

  # Get the Info::Obs object from the CGI object
  my $obs = cgi_to_obs( $q );

  # Get the OMP::User object.
  my $udb = new OMP::UserDB( DB => new OMP::DBbackend );
  my $user_obj = $udb->getUser( $user );

  if( ! defined( $user_obj ) ) {
    print "Must supply valid user in order to store a comment.<br>\n";
    return;
  }

  # Form the Info::Comment object.
  my $comment = new OMP::Info::Comment( author => $user_obj,
                                        text => $text,
                                        status => $status,
                                      );

  # Store the comment in the database.
  my $odb = new OMP::ObslogDB( DB => new OMP::DBbackend );
  $odb->addComment( $comment, $obs );

  # Display congratulatory message.
  print "Comment successfully stored in database.<br>\n";

}

=item B<cgi_to_obs>

Given a C<CGI> object, return an C<Info::Obs> object.

  $obs = cgi_to_obs( $cgi );

In order for this method to work properly, the C<CGI> object
must have the following variables:

=over 4

=item *

ut - In the form YYYY-MM-DD-hh-mm-ss, where the month, day, hour,
minute and second can be optionally zero-padded. The month is 1-based
(i.e. a value of "1" is January) and the hour is 0-based and based on
the 24-hour clock.

=item *

runnr - The run number of the observation.

=item *

inst - The instrument that the observation was taken with. Case-insensitive.

=back

=cut

sub cgi_to_obs {
  my $q = shift;

  my $qv = $q->Vars;
  my $ut = $qv->{'ut'};
  my $runnr = $qv->{'runnr'};
  my $inst = uc( $qv->{'inst'} );
  my $timegap = $qv->{'timegap'};

  # Form the Time::Piece object
  my $startobs = Time::Piece->strptime( $ut, '%Y-%m-%d-%H-%M-%S' );

  # Form the Info::Obs object.
  my $obs;
  if( $timegap ) {
    $obs = new OMP::Info::Obs::TimeGap( runnr => $runnr,
                                        startobs => $startobs,
                                        instrument => $inst,
                                      );
  } else {
    $obs = new OMP::Info::Obs( runnr => $runnr,
                               startobs => $startobs,
                               instrument => $inst,
                             );
  }

  # Comment-ise the Info::Obs object.
  my @obs;
  push @obs, $obs;
  my $db = new OMP::ObslogDB( DB => new OMP::DBbackend );
  $db->updateObsComment( \@obs );
  $obs = $obs[0];

  # And return the Info::Obs object.
  return $obs;

}

=item B<cgi_to_obsgroup>

Given a C<CGI> object, return an C<Info::ObsGroup> object.

  $obsgroup = cgi_to_obsgroup( $cgi, ut => $ut, inst => $inst );

In order for this method to work properly, the C<CGI> object
should have the following variables:

=over 4

=item *

ut - In the form YYYY-MM-DD.

=item *

inst - The instrument that the observation was taken with. Case-insensitive.

=item *

projid - The project ID for which observations will be returned.

=back

The C<inst> and C<projid> variables are optional, but either one or the
other (or both) must be defined.

The parameters following the C<CGI> object are optional and can include:

=over 4

=item * ut - The UT date in the form YYYY-MM-DD.

=item * inst - The instrument that the observation was taken with.

=item * projid - The project ID for which observations will be returned.

=item * telescope - The telescope that the observations were taken with.

=back

These parameters will override any values contained in the C<CGI> object.

=cut

sub cgi_to_obsgroup {
  my $q = shift;
  my %args = @_;

  my $ut = defined( $args{'ut'} ) ? $args{'ut'} : undef;
  my $inst = defined( $args{'inst'} ) ? uc( $args{'inst'} ) : undef;
  my $projid = defined( $args{'projid'} ) ? $args{'projid'} : undef;
  my $telescope = defined( $args{'telescope'} ) ? uc( $args{'telescope'} ) : undef;

  my $qv = $q->Vars;
  $ut = ( defined( $ut ) ? $ut : $qv->{'ut'} );
  $inst = ( defined( $inst ) ? $inst : uc( $qv->{'inst'} ) );
  $projid = ( defined( $projid ) ? $projid : $qv->{'projid'} );
  $telescope = ( defined( $telescope ) ? $telescope : uc( $qv->{'telescope'} ) );

  if( !defined( $ut ) ) {
    throw OMP::Error::BadArgs("Must supply a UT date in order to get an Info::ObsGroup object");
  }

  my $grp;

  if( defined( $telescope ) ) {

    $grp = new OMP::Info::ObsGroup( date => $ut,
                                    telescope => $telescope,
                                    timegap => OMP::Config->getData('timegap') );
  } else {

    if( defined( $projid ) ) {
      if( defined( $inst ) ) {
        $grp = new OMP::Info::ObsGroup( date => $ut,
                                        instrument => $inst,
                                        projectid => $projid,
                                        timegap => OMP::Config->getData('timegap') );
      } else {
        $grp = new OMP::Info::ObsGroup( date => $ut,
                                        projectid => $projid,
                                        timegap => OMP::Config->getData('timegap') );
      }
    } elsif( defined( $inst ) && length( $inst . "" ) > 0 ) {
      $grp = new OMP::Info::ObsGroup( date => $ut,
                                      instrument => $inst,
                                      timegap => OMP::Config->getData('timegap') );
    } else {
      throw OMP::Error::BadArgs("Must supply either an instrument name or a project ID to get an Info::ObsGroup object");
    }
  }

  return $grp;

}

=item B<print_obslog_header>

Prints a header for obslog.

  print_obslog_header();

There are no arguments.

=cut

sub print_obslog_header {
  print <<END;
Welcome to obslog. <a href="#changeut">Change the UT date</a><br>
<hr>
END
};



=item B<print_obslog_footer>

Print a footer that allows for changing of the UT date.

  print_obslog_footer( $cgi );

Only argument is the C<CGI> object.

=cut

sub print_obslog_footer {
  my $q = shift;

  my $qv = $q->Vars;

  print "<br>\n";
  print $q->startform;

  if(defined($qv->{'inst'})) {
    print $q->hidden( -name => 'inst',
                      -value => $qv->{'inst'},
                    );
  }

  my $time = localtime;
  my $currentut = $time->ymd;

  print "<a name=\"changeut\">Enter</a> new UT date (yyyy-mm-dd format): ";
  print $q->textfield( -name => 'ut',
                       -default => ( defined( $qv->{'ut'} ) ?
                                     $qv->{'ut'} :
                                     $currentut ),
                       -size => '16',
                       -maxlength => '10',
                     );

  print "<br>\n";

  print $q->submit( -name => 'Submit New UT' );
  print $q->endform;
}

=item B<print_obscomment_footer>

Prints a footer that gives a link back to obslog.

  print_obscomment_footer( $cgi );

The only argument is the C<CGI> object.

=cut

sub print_obscomment_footer {
  my $q = shift;
  my $qv = $q->Vars;

  $qv->{'ut'} =~ /^(\d{4}-\d\d-\d\d)/;

  print "<br>\n";
  print "<a href=\"obslog.pl?ut=$1&inst=" . $qv->{'inst'} . "\">back to obslog</a>\n";
}

=back

=head1 AUTHOR

Brad Cavanagh E<lt>b.cavanagh@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
