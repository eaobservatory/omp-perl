package OMP::CGIComponent::Obslog;

=head1 NAME

OMP::CGIComponent::Obslog - CGI functions for the observation log tool.

=head1 SYNOPSIS

use OMP::CGIComponent::Obslog;

=head1 DESCRIPTION

This module provides routines used for CGI-related functions for
obslog -- variable verification, form creation, etc.

=cut

use strict;
use warnings;
use Carp;

use CGI::Carp qw/fatalsToBrowser/;
use Net::Domain qw/ hostfqdn /;

use OMP::CGIComponent::Helper qw/ public_url /;
use OMP::Config;
use OMP::Constants qw/ :obs :timegap /;
use OMP::General;
use OMP::Info::Comment;
use OMP::Info::Obs;
use OMP::Info::ObsGroup;
use OMP::ObslogDB;
use OMP::ProjServer;
use OMP::WORF;
use OMP::Error qw/ :try /;

use vars qw(@ISA @EXPORT_OK %EXPORT_TAGS);

our $VERSION = (qw$Revision$ )[1];

require Exporter;

@ISA = qw/Exporter/;
@EXPORT_OK = qw( obs_table obs_summary obs_inst_summary obs_comment_form
                 obs_add_comment cgi_to_obs cgi_to_obsgroup
                 print_obslog_header print_obslog_footer
                 print_obscomment_footer );

%EXPORT_TAGS = (
                'all' => [ @EXPORT_OK ]
               );

Exporter::export_tags(qw/ all /);

# Colours for displaying observation status.

our %css = (
               OMP__OBS_GOOD() => '.obslog-good',
               OMP__OBS_QUESTIONABLE() => '.obslog-questionable',
               OMP__OBS_BAD() => '.obslog-bad',
               OMP__OBS_REJECTED() => '.obslog-rejected'
              );

=head1 Routines

All routines are exported by default.

=over 4

=item B<obs_table>

Prints an HTML table containing a summary of information about a
group of observations.

  obs_table( $obsgroup, $options );

The first argument is the C<OMP::Info::ObsGroup>
object, and the third optional argument tells the function how to
display things. It is a hash reference optionally containing the
following keys:

=over 8

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

=item *

text - Produce a text table rather than an HTML table. Defaults
to 0 (false).

=item *

worfstyle - Write WORF links to the staff WORF page. Can be either 'staff'
or 'project', and if the parameter is not 'staff', will default to 'project'.

=back

This function will print a colour legend before the table.

=cut

sub obs_table {
  my $obsgroup = shift;
  my %options = @_;

  my %dir_exists;

  # Check the arguments.
  my $commentlink;
  if( exists( $options{commentstyle} ) && defined( $options{commentstyle} ) &&
      lc( $options{commentstyle} ) eq 'staff' ) {
    $commentlink = 'staffobscomment.pl';
  } else {
    $commentlink = 'fbobscomment.pl';
  }

  my $worflink;
  if( exists( $options{worfstyle} ) && defined( $options{worfstyle} ) &&
      lc( $options{worfstyle} ) eq 'staff' ) {
    $worflink = 'staffworf.pl';
  } else {
    $worflink = 'fbworf.pl';
  }

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

  my $text;
  if( exists( $options{text} ) ) {
    $text = $options{text};
  } else {
    $text = 0;
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

  unless (@allobs) {
    if ($text) {
      print "No observations for this night\n";
    }
    return;
  }

  my $currentinst = (length( $instrument . '' ) == 0 ) ? $allobs[0]->instrument : $instrument;

  my $ut = $allobs[0]->startobs->ymd;

  if( $text ) {

  } else {
    print qq[<table width="600" class="sum_table" border="0">\n<tr class="sum_table_head"><td>];
    print qq[<strong class="small_title">Observation Log</strong></td></tr>\n];
    print qq[<tr class="sum_other"><td>\n];
    print 'Colour legend: ',
      join ', ',
      map
      { '<span class="' . $css{$_->[0]} . '">' . $_->[1] . '</span>' }
      (
        [ OMP__OBS_GOOD(),         'good'         ],
        [ OMP__OBS_QUESTIONABLE(), 'questionable' ],
        [ OMP__OBS_BAD(),          'bad'          ],
        [ OMP__OBS_REJECTED(),     'rejected'     ]
      ) ;
    print  "</td></tr>\n";

    print "</table>";
  }

  if(!defined($currentinst)) {

    if( $text ) {

    } else {
      print qq[<table width="600" class="sum_table" border="0">\n];
      print qq[<tr class="sum_other"><td>No observations available</td></tr></table>\n];
    }
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

# Check to see if we should be doing WORF raw or reduced links. We do
# this by checking for the raw and reduced data directories to see if
# they exist.
  my $rawdir = OMP::Config->getData( 'rawdatadir',
                                     telescope => $allobs[0]->telescope,
                                     instrument => lc( $currentinst ),
                                     utdate => $allobs[0]->startobs->ymd );
  my $reduceddir = OMP::Config->getData( 'reduceddatadir',
                                         telescope => $allobs[0]->telescope,
                                         instrument => lc( $currentinst ),
                                         utdate => $allobs[0]->startobs->ymd );
  my %worfraw;
  my %worfreduced;
  if( -d $rawdir ) {
    $worfraw{$currentinst} = 1;
  } else {
    $worfraw{$currentinst} = 0;
  }
  if( -d $reduceddir ) {
    $worfreduced{$currentinst} = 1;
  } else {
    $worfreduced{$currentinst} = 0;
  }

  my $ncols;
  if( $text ) {
    print "\nObservations for " . uc( $currentinst ) . " on $ut\n";
    print $nightlog{_STRING_HEADER}, "\n";
  } else {
    $ncols = scalar(@{$nightlog{_ORDER}}) + 2;
    print "<table class=\"sum_table\" border=\"0\">\n";
    print "<tr class=\"sum_other\"><td colspan=\"$ncols\"><div class=\"small_title\">Observations for " . uc($currentinst) . "</div></td></tr>\n";

    # Print the column headings.
    print "<tr class=\"sum_other\"><td>";
    print join ( "</td><td>", @{$nightlog{_ORDER}} );
    print "</td><td>Comments</td><td>WORF</td><td>Observation</td></tr>\n";
  }

  my $rowclass = "row_b";

  foreach my $obs (@allobs) {

    next if( ( length( $instrument . '' ) > 0 ) &&
             ( uc( $instrument ) ne uc( $obs->instrument ) ) );

    my %nightlog = $obs->nightlog;

    # First, check to see if the instrument has changed. If it has, close the old table
    # and start a new one.
    if( uc($obs->instrument) ne uc($currentinst) && !UNIVERSAL::isa($obs, "OMP::Info::Obs::TimeGap") ) {
      $currentinst = $obs->instrument;

      if( ! defined( $worfraw{$currentinst} ) ) {

        my $rawdir = OMP::Config->getData( 'rawdatadir',
                                           telescope => $allobs[0]->telescope,
                                           instrument => lc( $currentinst ),
                                           utdate => $allobs[0]->startobs->ymd );
        my $reduceddir = OMP::Config->getData( 'reduceddatadir',
                                               telescope => $allobs[0]->telescope,
                                               instrument => lc( $currentinst ),
                                               utdate => $allobs[0]->startobs->ymd );
        $worfraw{$currentinst} = 0;
        $worfreduced{$currentinst} = 0;
        if( -d $rawdir ) {
          $worfraw{$currentinst} = 1;
        }
        if( -d $reduceddir ) {
          $worfreduced{$currentinst} = 1;
        }
      }

      if( $text ) {
        print "\nObservations for " . uc( $currentinst ) . "\n";
        print $nightlog{_STRING_HEADER}, "\n";
      } else {
        print "</table>\n";
        print "<table class=\"sum_table\" border=\"0\">\n";
        print "<tr class=\"sum_other\"><td colspan=\"$ncols\"><div class=\"small_title\">Observations for " . uc($currentinst) . "</div></td></tr>\n";

        # Print the column headings.
        print "<tr class=\"sum_other\"><td>";
        print join ( "</td><td>", @{$nightlog{_ORDER}} );
        print "</td><td>Comments</td><td>WORF</td><td>Observation</td></tr>\n";
      }
    }

    my $comments = $obs->comments;
    my $status = $obs->status;
    my $css_status = defined( $status ) ? $css{$status} : $css{OMP__OBS_GOOD()};
    my $instrument = $obs->instrument;
    if( UNIVERSAL::isa( $obs, "OMP::Info::Obs::TimeGap") ) {
      if( $text ) {
        print $nightlog{'_STRING'}, "\n";
      } else {
        print "<tr class=\"$rowclass\"><td colspan=\"" . ( $ncols - 2 ) . "\"><font color=\"BLACK\">";
        $nightlog{'_STRING'} =~ s/\n/\<br\>/g;
        print $nightlog{'_STRING'};
      }
    } else {
      if( $text ) {
        print $nightlog{'_STRING'}, "\n";
      } else {
        print qq[<tr class="$rowclass"><td class="$css_status">],
          join qq[</td><td class="$css_status">],
            map
            { ref($nightlog{$_}) eq 'ARRAY'
              ? join ', ', @{$nightlog{$_}}
              : $nightlog{$_};
            }
            @{$nightlog{_ORDER}} ;

        $ncols = scalar( @{$nightlog{_ORDER}} ) + 2;
      }
    }

    my $obsut;
    if( $text ) {

    } else {

      my $endpoint =
        UNIVERSAL::isa( $obs, "OMP::Info::Obs::TimeGap" )
        ? $obs->endobs
        : $obs->startobs;

      $obsut = join '-', map { $endpoint->$_ } qw[ ymd hour minute second ];

      my %param = ( 'ut'  => $obsut,
                    'runnr' => $obs->runnr,
                    'inst' => $instrument
                  );

      $param{'timegap'} = 1
        if UNIVERSAL::isa( $obs, "OMP::Info::Obs::TimeGap");

      print qq[</td><td><a class="link_dark_small" href="$commentlink?]
            . join( '&', map { $_ . '=' . $param{ $_ } } keys %param )
            . qq[">comment</a></td>];
    }

    if( $text ) {

    } else {

      # Display WORF box if we do not have a TimeGap.
      if( !UNIVERSAL::isa( $obs, "OMP::Info::Obs::TimeGap" ) ) {

        my $worf;
        try {

          print "<td>";

          # First the raw.
          if( $worfraw{$currentinst} ) {
            # Form an OMP::WORF object for the obs
            if( ! defined( $worf ) ) {
              $worf = new OMP::WORF( obs => $obs );
            }
            if( $worf->file_exists( suffix => '', group => 0 ) ) {
              print "<a class=\"link_dark_small\" href=\"$worflink?ut=";
              print $obsut;
              print "&runnr=" . $obs->runnr . "&inst=" . $instrument;
              print "\">raw</a> ";
            }
          }

          # Then the individual reduced.
          if( $worfreduced{$currentinst} ) {
            if( ! defined( $worf ) ) {
              $worf = new OMP::WORF( obs => $obs );
            }
            my @ind_suffices = $worf->suffices;
            foreach my $suffix ( @ind_suffices ) {
              next if ! $worf->file_exists( suffix => $suffix, group => 0 );
              print "<a class=\"link_dark_small\" href=\"$worflink?ut=";
              print $obsut;
              print "&runnr=" . $obs->runnr . "&inst=" . $instrument;
              print "&suffix=$suffix\">$suffix</a> ";
            }
          }

          print "/ ";

          # And the group reduced.
          if( $worfreduced{$currentinst} ) {
            if( ! defined( $worf ) ) {
              $worf = new OMP::WORF( obs => $obs );
            }
            # Get a list of suffices
            my @grp_suffices = $worf->suffices( 1 );
            if( $worf->file_exists( suffix => '', group => 1 ) ) {
              print "<a class=\"link_dark_small\" href=\"$worflink?ut=";
              print $obsut;
              print "&runnr=" . $obs->runnr . "&inst=" . $instrument;
              print "&group=1\">group</a> ";
            }
            foreach my $suffix ( @grp_suffices ) {
              next if ! $worf->file_exists( suffix => $suffix, group => 1 );
              print "<a class=\"link_dark_small\" href=\"$worflink?ut=";
              print $obsut;
              print "&runnr=" . $obs->runnr . "&inst=" . $instrument;
              print "&suffix=$suffix&group=1\">$suffix</a> ";
            }
          }

          print "</td>";
        }
        catch OMP::Error with {
          my $Error = shift;
#          print STDERR "Error in OMP::CGIObslog::obs_table: " . $Error->{'-text'} . "\n";
          print "<td>Error 1</td>";
#        next;
        }
        otherwise {
          my $Error = shift;
#          print STDERR "Error in OMP::CGIObslog::obs_table: " . $Error->{'-text'} . "\n";
          print "<td>" . $Error->{'-text'} . "</td>";
#        next;
        };
      } else {
        print "<td>&nbsp;</td>";
      }
      print qq[<td class="$css_status">] . $obs->runnr . '</td>';
      print "</tr>\n";
    }

    # Print the comments underneath, if there are any, and if the
    # 'showcomments' parameter is not '0', and if we're not looking at a timegap
    # (since timegap comments show up in the nightlog string)
    if( defined( $comments ) &&
        defined( $comments->[0] ) &&
        ( $showcomments != 0 ) &&
        ! UNIVERSAL::isa( $obs, "OMP::Info::Obs::TimeGap" ) ) {

      if( $text ) {
        foreach my $comment ( @$comments ) {
          print "    " . $comment->date->cdate . " UT / " . $comment->author->name . ":";
          print $comment->text . "\n";
        }
      } else {
        print "<tr class=\"$rowclass\"><td colspan=\"" . (scalar(@{$nightlog{_ORDER}}) + 2) . "\">";
        my @printstrings;
        foreach my $comment (@$comments) {
          my $string = qq[ <span class="] . $css{$comment->status} . '">'
                      . $comment->date->cdate . ' UT / '
                      . $comment->author->name . ':'
                      . ' '
                      . OMP::General::escape_entity( $comment->text )
                      . '</span>';

          $string =~ s/\n/\<br\>/g;
          push @printstrings, $string;
        }
        if($#printstrings > -1) {
          print join "<br>", @printstrings;
        };
        print "</td></tr>\n";
      }
    }

    $rowclass = ( $rowclass eq 'row_a' ) ? 'row_b' : 'row_a';

  }

  if( $text ) {

  } else {

    # And finish the table.
    print "</table>\n";
  }

}

=item B<obs_summary>

Prints a table containing a summary about a given observation

  obs_summary( $cgi, $obs, $cookie );

The first argument is a C<CGI> object, the second is an
C<Info::Obs> object, and the third is an C<OMP::Cookie> object.

=cut

sub obs_summary {
  my $cgi = shift;
  my $obs = shift;
  my $cookie = shift;

  # Verify that we do have an Info::Obs object.
  if( ! UNIVERSAL::isa( $obs, "OMP::Info::Obs" ) ) {
    throw OMP::Error::BadArgs("Must supply an Info::Obs object");
  }

  if( exists( $cookie->{'projectid'} ) && defined( $cookie->{'projectid'} ) &&
      $obs->isScience && (lc( $obs->projectid ) ne lc( $cookie->{'projectid'} ) ) ) {
    throw OMP::Error( "Observation does not match project " . $cookie->{'projectid'} );
  }

  my @comments = $obs->comments;

  print qq[<table width="600" border="0" class="sum_table">\n],
    '<tr class="sum_table_head"><td><strong class="small_title">',
    "Comment for ",
    $obs->instrument;

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
    print '<table border="0" class="sum_table" width="600">';

    my $rowclass = 'row_a';
    foreach my $comment (@comments) {
      print '<tr class="$rowclass"><td>';
      my $string = '<font color="';
      $string .= ( defined( $css{$comment->status} ) ) ? $css{$comment->status} : "BLACK";
      $string .= '"><strong>' . $comment->date->cdate . " UT / " . $comment->author->name . ":";
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

  ( $inst, $ut ) = obs_inst_summary( $q, \%cookie );

The first argument must be a C<CGI> object and the second argument
is a reference to a hash containing the cookie information.

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
  my $password = $cookie->{'password'};
  my $obsloglink;
  if( defined( $projectid ) && ! OMP::General->am_i_staff( $projectid ) ) {
    my $proj = OMP::ProjServer->projectDetails( $projectid,
                                                $password,
                                                'object' );
    if( defined( $proj ) ) {
      $telescope = uc( $proj->telescope );
    }

    $obsloglink = "fbobslog.pl";

  } else {
    $obsloglink = "staffobslog.pl";
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
                                       projectid => $projectid,
                                       inccal => 1,
                                       ignorebad => 1,
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
      my $header = "<a style=\"color: #05054f;\" href=\"$obsloglink?inst=$inst&ut=$ut\">$inst (" . scalar(@{$results{$inst}->obs}) . ")</a>";
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

  my %status_label = ( OMP__OBS_GOOD() => 'Good',
                       OMP__OBS_QUESTIONABLE() => 'Questionable',
                       OMP__OBS_BAD() => 'Bad',
                       OMP__OBS_REJECTED() => "Rejected",
                     ) ;
  my @status_value = sort keys %status_label;

  # Note that we want Unknown to appear at the end
  my %timegap_label = ( OMP__TIMEGAP_INSTRUMENT() => 'Instrument',
                        OMP__TIMEGAP_WEATHER() => 'Weather',
                        OMP__TIMEGAP_FAULT() => 'Fault',
                        OMP__TIMEGAP_NEXT_PROJECT() => 'Next Project',
                        OMP__TIMEGAP_PREV_PROJECT() => 'Last Project',
                        OMP__TIMEGAP_NOT_DRIVER() => 'Observer Not Driver',
                        OMP__TIMEGAP_SCHEDULED() => 'Scheduled Downtime',
                        OMP__TIMEGAP_QUEUE_OVERHEAD() => 'Queue Overhead',
                        OMP__TIMEGAP_LOGISTICS() => 'Logistics',
                      );
  my @timegap_value = sort(keys %timegap_label);
  $timegap_label{OMP__TIMEGAP_UNKNOWN()} = "Unknown";
  push(@timegap_value, OMP__TIMEGAP_UNKNOWN );

  # Verify we have an Info::Obs object.
  if( ! UNIVERSAL::isa($obs, "OMP::Info::Obs") ) {
    throw OMP::Error::BadArgs("Must supply Info::Obs object");
  }

  if( exists( $cookie->{'projectid'} ) && defined( $cookie->{'projectid'} ) &&
      $obs->isScience && lc( $cookie->{'projectid'} ) ne lc( $obs->projectid ) ) {
    throw OMP::Error("The projectid for the observation (" . $obs->projectid . ") does not match the project you are logged in as (" . $cookie->{'projectid'} . ")");
  }

  print $q->startform;
  print '<table border="0" width="100%"><tr><td width="20%">';
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
  print '<tr><td colspan="2">';

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

  print $q->hidden( -name => 'show_output',
                    -value => 1,
                  );

  print '</td></tr>\n<tr><td colspan="2">';

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

=over 8

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

  my $ut;
  if( exists( $qv->{'ut'} ) && defined( $qv->{'ut'} ) ) {
    $qv->{'ut'} =~ /^(\d{4}-\d\d-\d\d-\d\d?-\d\d?-\d\d?)/;
    $ut = $1;
  }

  my $runnr;
  if( exists( $qv->{'runnr'} ) && defined( $qv->{'runnr'} ) ) {
    $qv->{'runnr'} =~ /^(\d+)$/;
    $runnr = $1;
  }

  my $inst;
  if( exists( $qv->{'inst'} ) && defined( $qv->{'inst'} ) ) {
    $qv->{'inst'} =~ /^([\w\d]+)$/;
    $inst = $1;
  }

  my $timegap;
  if( exists( $qv->{'timegap'} ) && defined( $qv->{'timegap'} ) ) {
    $qv->{'timegap'} =~ /^([01])$/;
    $timegap = $1;
  } else {
    $timegap = 0;
  }

  # Form the Time::Piece object
  my $startobs = Time::Piece->strptime( $ut, '%Y-%m-%d-%H-%M-%S' );

  # Get the telescope.
  my $telescope = uc(OMP::Config->inferTelescope('instruments', $inst));

  # Form the Info::Obs object.
  my $obs;
  if( $timegap ) {
    $obs = new OMP::Info::Obs::TimeGap( runnr => $runnr,
                                        startobs => $startobs,
                                        instrument => $inst,
                                        telescope => $telescope,
                                      );
  } else {
    $obs = new OMP::Info::Obs( runnr => $runnr,
                               startobs => $startobs,
                               instrument => $inst,
                               telescope => $telescope,
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

Given a C<CGI> object and a reference to cookie information, return an
C<Info::ObsGroup> object.

  $obsgroup = cgi_to_obsgroup( $cgi, \%cookie, ut => $ut, inst => $inst );

In order for this method to work properly, the cookie hash
should have the following keys:

=over 8

=item *

ut - In the form YYYY-MM-DD.

=item *

inst - The instrument that the observation was taken with. Case-insensitive.

=item *

projid - The project ID for which observations will be returned.

=back

The C<inst> and C<projid> variables are optional, but either one or the
other (or both) must be defined.

The parameters following the cookie are optional and can include:

=over 8

=item *

ut - The UT date in the form YYYY-MM-DD.

=item *

inst - The instrument that the observation was taken with.

=item *

projid - The project ID for which observations will be returned.

=item *

telescope - The telescope that the observations were taken with.

=back

These parameters will override any values contained in the C<CGI> object.

=cut

sub cgi_to_obsgroup {
  my $q = shift;
  my $cookie = shift;
  my %args = @_;

  my $ut = defined( $args{'ut'} ) ? $args{'ut'} : undef;
  my $inst = defined( $args{'inst'} ) ? uc( $args{'inst'} ) : undef;
  my $projid = defined( $args{'projid'} ) ? $args{'projid'} : undef;
  my $telescope = defined( $args{'telescope'} ) ? uc( $args{'telescope'} ) : undef;
  my $inccal = defined( $args{'inccal'} ) ? $args{'inccal'} : 0;
  my $timegap = defined( $args{'timegap'} ) ? $args{'timegap'} : 1;

  my %options;
  if( $inccal ) { $options{'inccal'} = $inccal; }
  if( $timegap ) { $options{'timegap'} = OMP::Config->getData('timegap'); }

  my $qv = $q->Vars;
  $ut = ( defined( $ut ) ? $ut : $qv->{'ut'} );
  $inst = ( defined( $inst ) ? $inst : uc( $qv->{'inst'} ) );
  $projid = ( defined( $projid ) ? $projid : $qv->{'projid'} );
  $telescope = ( defined( $telescope ) ? $telescope : uc( $qv->{'telescope'} ) );

  $projid = ( defined( $projid ) ? $projid : $cookie->{'projectid'} );

  if( !defined( $telescope ) || length( $telescope . '' ) == 0 ) {
    if( defined( $inst ) && length( $inst . '' ) != 0) {
      $telescope = uc( OMP::Config->inferTelescope('instruments', $inst));
    } elsif( defined( $projid ) ) {
      $telescope = OMP::ProjServer->getTelescope( $projid );
    } else {
      throw OMP::Error("CGIObslog: Cannot determine telescope!\n");
    }
  }

  if( !defined( $ut ) ) {
    throw OMP::Error::BadArgs("Must supply a UT date in order to get an Info::ObsGroup object");
  }

  my $grp;

  if( defined( $telescope ) ) {
    $grp = new OMP::Info::ObsGroup( date => $ut,
                                    telescope => $telescope,
                                    projectid => $projid,
                                    instrument => $inst,
                                    ignorebad => 1,
                                    %options,
                                  );
  } else {

    if( defined( $projid ) ) {
      if( defined( $inst ) ) {
        $grp = new OMP::Info::ObsGroup( date => $ut,
                                        instrument => $inst,
                                        projectid => $projid,
                                        ignorebad => 1,
                                        %options,
                                      );
      } else {
        $grp = new OMP::Info::ObsGroup( date => $ut,
                                        projectid => $projid,
                                        ignorebad => 1,
                                        %options,
                                      );
      }
    } elsif( defined( $inst ) && length( $inst . "" ) > 0 ) {
      $grp = new OMP::Info::ObsGroup( date => $ut,
                                      instrument => $inst,
                                      ignorebad => 1,
                                      %options,
                                    );
    } else {
      throw OMP::Error::BadArgs("Must supply either an instrument name or a project ID to get an Info::ObsGroup object");
    }
  }

  return $grp;

}

=item B<print_obslog_header>

Prints a header for obslog.

  print_obslog_header( $q );

The only argument is the C<CGI> object.

=cut

sub print_obslog_header {
  my $q = shift;

  my $qv = $q->Vars;

  print "Welcome to obslog.<hr>\n";
  print $q->startform;

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

  print '<a href="' .  public_url() . '/obslog_text.pl?ut="'
        . ( defined( $qv->{'ut'} ) ?  $qv->{'ut'} : $currentut );

  if( defined( $qv->{'inst'} ) ) {
    print "&inst=" . $qv->{'inst'};
  }
  if( defined( $qv->{'telescope'} ) ) {
    print "&telescope=" . $qv->{'telescope'};
  }
  if( defined( $qv->{'projid'} ) ) {
    print "&projid=" . $qv->{'projid'};
  }
  print "\">text listing</a><br>\n";

  print "<hr>\n";

};

=item B<print_obslog_footer>

Print a footer.

  print_obslog_footer( $cgi );

Only argument is the C<CGI> object.

Currently essentially a no-op.

=cut

sub print_obslog_footer {

}

=item B<print_obscomment_footer>

Prints a footer.

  print_obscomment_footer( $cgi );

The only argument is the C<CGI> object.

Currently a no-op.

=cut

sub print_obscomment_footer {

}

=back

=head1 SEE ALSO

C<OMP::CGIPage::Obslog>

=head1 AUTHOR

Brad Cavanagh E<lt>b.cavanagh@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2008 Science and Technology Facilities Council.
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
along with this program (see SLA_CONDITIONS); if not, write to the
Free Software Foundation, Inc., 59 Temple Place, Suite 330,
Boston, MA  02111-1307  USA

=cut

1;
