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

use CGI::Carp qw/fatalsToBrowser/;
use Net::Domain qw/ hostfqdn /;

use OMP::Config;
use OMP::Constants qw/ :obs :timegap /;
use OMP::Display;
use OMP::DateTools;
use OMP::MSBDoneDB;
use OMP::General;
use OMP::Info::Comment;
use OMP::Info::Obs;
use OMP::Info::ObsGroup;
use OMP::ObslogDB;
use OMP::ProjServer;
use OMP::Error qw/ :try /;

use base qw/OMP::CGIComponent/;

our $VERSION = '2.000';

# Colours for displaying observation status.

our %css = (
               OMP__OBS_GOOD() => 'obslog-good',
               OMP__OBS_QUESTIONABLE() => 'obslog-questionable',
               OMP__OBS_BAD() => 'obslog-bad',
               OMP__OBS_JUNK() => 'obslog-junk',
               OMP__OBS_REJECTED() => 'obslog-rejected'
    );

# Labels for observation status.
our %status_label = ( OMP__OBS_GOOD() => 'Good',
                      OMP__OBS_QUESTIONABLE() => 'Questionable',
                      OMP__OBS_BAD() => 'Bad',
                      OMP__OBS_JUNK() => 'Junk',
                      OMP__OBS_REJECTED() => "Rejected",
    ) ;

=head1 Routines

=over 4

=item B<get_obs_summary>

Prepare summarized observation information as required for
printing a table of observations.

    my $summary = $comp->get_obs_summary($obsgroup, %options);

L<%options> is a hash optionally containing the
following keys:

=over 4

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

=cut

sub get_obs_summary {
  my $self = shift;
  my $obsgroup = shift;
  my %options = @_;

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
    return undef;
  }

  my %result = (
    block => [],
  );

  my $currentinst = undef;
  my $currentblock = undef;

  my $msbdb = OMP::MSBDoneDB->new(DB => OMP::DBbackend->new());

  my $old_sum = '';
  my $old_tid = '';

  foreach my $obs (@allobs) {
    next if( ( length( $instrument . '' ) > 0 ) &&
             ( uc( $instrument ) ne uc( $obs->instrument ) ) );

    unless ((defined $currentblock) and ($currentinst eq uc $obs->instrument)) {
      $currentinst = uc $obs->instrument;
      push @{$result{'block'}}, $currentblock = {
        instrument => $currentinst,
        ut => $obs->startobs->ymd,
        telescope => $obs->telescope,
        obs => []};
    }

    my %nightlog = $obs->nightlog;
    my $is_time_gap = eval {$obs->isa('OMP::Info::Obs::TimeGap')};

    my $endpoint = $is_time_gap
      ? $obs->endobs
      : $obs->startobs;

    my %entry = (
      is_time_gap => $is_time_gap,
      obs => $obs,
      obsut => (join '-', map { $endpoint->$_ } qw/ymd hour minute second/),
      nightlog => \%nightlog,
    );

    unless ($is_time_gap) {
      unless (exists $currentblock->{'heading'}) {
        $currentblock->{'heading'} = \%nightlog;
      }

      # In case msbtid column is missing or has no value (calibration), use checksum.
      my $checksum = $obs->checksum;
      my $msbtid   = $obs->msbtid;

      my $has_msbtid = defined $msbtid && length $msbtid;

      my ($is_new_msbtid, $is_new_checksum);

      if ($has_msbtid) {
        $is_new_msbtid =
              $msbtid ne ''
          &&  $msbtid ne $old_tid ;

        $old_tid = $msbtid if $is_new_msbtid;

        # Reset to later handle case of 'calibration' since sum 'CAL' never
        # changes.
        $old_sum = '';
      }
      else {
        $is_new_checksum = ! ($old_sum eq $checksum);

        $old_sum = $checksum if $is_new_checksum;
      }

      # If the current MSB differs from the MSB to which this observation belongs,
      # we need to insert as the start of the MSB. Ignore blank MSBTIDS.
      if ( $checksum && ( $is_new_msbtid || $is_new_checksum ) ) {
        # Get any activity associated with this MSB accept.
        my $history;
        if ($has_msbtid) {
          try {
            $history = $msbdb->historyMSBtid($msbtid);
          } otherwise {
            my $E = shift;
            print STDERR $E;
          };
        }

        if (defined $history) {
          my $title = $history->title();
          undef $title unless 2 < length $title;
          $entry{'msb_comments'} = {
              title => $title,
              comments => [grep {
                  my $text = $_->text();
                  defined $text && length $text;
              } $history->comments()],
          };
        }
      }
    }

    push @{$currentblock->{'obs'}}, \%entry;
  }

  return \%result;
}

=item B<obs_table>

Prints an HTML table containing a summary of information about a
group of observations.

=over 4

=item *

worfstyle - Write WORF links to the staff WORF page. Can be either 'none', 'staff'
or 'project', and if the parameter is not 'staff' or 'none', will default to 'project'.

=back

This function will print a colour legend before the table.

=cut

sub obs_table {
  my $self = shift;
  my $obsgroup = shift;
  my %options = @_;

  # Check the arguments.
  my $commentlink;
  if( exists( $options{commentstyle} ) && defined( $options{commentstyle} ) &&
      lc( $options{commentstyle} ) eq 'staff' ) {
    $commentlink = 'staffobscomment.pl?';
  } else {
    $commentlink = 'fbobscomment.pl?project=' . $options{'projectid'} . '&';
  }

  my $worflink;
  if( exists( $options{worfstyle} ) && defined( $options{worfstyle} ) &&
      lc( $options{worfstyle} ) eq 'staff' ) {
    $worflink = 'staffworf.pl?';
  } elsif (exists( $options{worfstyle} ) && defined( $options{worfstyle} ) &&
             lc( $options{worfstyle} ) eq 'none' ) {
      $worflink = 'none';
  } else {
    $worflink = 'fbworf.pl?project=' . $options{'projectid'} . '&';
  }

  my $showcomments;
  if( exists( $options{showcomments} ) ) {
    $showcomments = $options{showcomments};
  } else {
    $showcomments = 1;
  }

  # Verify the ObsGroup object.
  if( ! UNIVERSAL::isa($obsgroup, "OMP::Info::ObsGroup") ) {
    throw OMP::Error::BadArgs("Must supply an Info::ObsGroup object")
  }

  my $summary = $self->get_obs_summary($obsgroup, %options);

  unless (defined $summary) {
    return;
  }

  print "<h2>Observation log</h2>\n";
  print qq[<table width="600" class="sum_table" border="0">\n<tr class="sum_other"><td>\n];
  print 'Colour legend: ',
    join ', ',
    map
    { '<span class="' . $css{$_->[0]} . '">' . $_->[1] . '</span>' }
    (
      [ OMP__OBS_GOOD(),         'good'         ],
      [ OMP__OBS_QUESTIONABLE(), 'questionable' ],
      [ OMP__OBS_BAD(),          'bad'          ],
      [ OMP__OBS_JUNK(),         'junk'         ],
      [ OMP__OBS_REJECTED(),     'rejected'     ]
    ) ;
  print  "</td></tr>\n";

  print "</table>";

  # Start off the table.

  my %worfraw;
  my %worfreduced;

  my $rowclass = "row_b";

  my $is_first_block = 1;
  foreach my $instblock (@{$summary->{'block'}}) {
    my $ut = $instblock->{'ut'};
    my $telescope = $instblock->{'telescope'};
    my $currentinst = $instblock->{'instrument'};

    if( ($worflink ne 'none') && (! defined( $worfraw{$currentinst} ))) {
        # Check to see if we should be doing WORF raw or reduced links. We do
        # this by checking for the raw and reduced data directories to see if
        # they exist.
        my $rawdir = OMP::Config->getData( 'rawdatadir',
                                           telescope => $telescope,
                                           instrument => lc( $currentinst ),
                                           utdate => $ut );
        my $reduceddir = OMP::Config->getData( 'reduceddatadir',
                                               telescope => $telescope,
                                               instrument => lc( $currentinst ),
                                               utdate => $ut );
        $worfraw{$currentinst} = 0;
        $worfreduced{$currentinst} = 0;
        if( -d $rawdir ) {
          $worfraw{$currentinst} = 1;
        }
        if( -d $reduceddir ) {
          $worfreduced{$currentinst} = 1;
        }
    }

    my $column_order = $instblock->{'heading'}->{'_ORDER'};
    my $ncols = 4 + scalar @$column_order;

    if ($is_first_block) {
      print "<h3>Observations for " . uc($currentinst) . "</h3>\n";
      print "<table class=\"sum_table\" border=\"0\">\n";

    }
    else {
      print "</table>\n";
      print "<h3>Observations for " . uc($currentinst) . "</h3>\n";
      print "<table class=\"sum_table\" border=\"0\">\n";
    }

    # Print the column headings.
    print "<tr class=\"sum_other\"><td>";
    print join ( "</td><td>", @$column_order );

    # Don't include WORF columns if they were specifically not requested.
    if ($worflink eq 'none') {
        print "</td><td>Comments</td><td>Run</td><td>Status</td></tr>\n";
    } else {
        print "</td><td>Comments</td><td>WORF</td><td>Run</td><td>Status</td></tr>\n";
    }

    foreach my $entry (@{$instblock->{'obs'}}) {
      my $obs = $entry->{'obs'};
      my $nightlog = $entry->{'nightlog'};

      my $comments = $obs->comments;
      my $obsid  = $obs->obsid;
      my $status = $obs->status;
      my $css_status = defined( $status ) ? $css{$status} : $css{OMP__OBS_GOOD()};
      my $label_status = defined( $status ) ? $status_label{$status} : $status_label{OMP__OBS_GOOD()};
      my $instrument = $obs->instrument;

      if ($entry->{'is_time_gap'}) {
        print "<tr class=\"$rowclass\"><td colspan=\"" . ( $ncols - 4) . "\"><font color=\"BLACK\">";
        $nightlog->{'_STRING'} =~ s/\n/\<br\>/g;
        print $nightlog->{'_STRING'};
      }
      else {
        if (exists $entry->{'msb_comments'}) {
          my $comment = $entry->{'msb_comments'};

          my $title = '';
          $title = sprintf qq[<b>%s</b><br>\n], $comment->{'title'}
            if defined $comment->{'title'};

          print qq[<tr class="$rowclass"><td class="msb-comment-nightrep" colspan="$ncols">];

          foreach my $c (@{$comment->{'comments'}}) {
            print '<p>' . $title . (sprintf qq[%s UT by %s\n<br>%s\n],
                $c->date,
                ((defined $c->author) ? $c->author->name : 'UNKNOWN PERSON'),
                $c->text()) . '</p>';
          }

          print qq[</td></tr>];
        }

        print qq[<tr class="$rowclass"><td class="$css_status">],
          join qq[</td><td class="$css_status">],
            map
            { ref($nightlog->{$_}) eq 'ARRAY'
              ? join ', ', @{$nightlog->{$_}}
              : $nightlog->{$_};
            }
            @{$nightlog->{_ORDER}} ;
      }

      my $obsut = $entry->{'obsut'};

      my %param = ( 'ut'  => $obsut,
                    'runnr' => $obs->runnr,
                    'inst' => $instrument,
                    'oid'  => $obsid,
                  );

      $param{'timegap'} = 1
        if $entry->{'is_time_gap'};

      print qq[</td><td><a class="link_dark_small" href="$commentlink]
            . join( '&', map { $_ . '=' . $param{ $_ } } grep { defined $param{$_} } keys %param )
            . qq[">comment</a></td>];

      if ($worflink ne 'none') {
        # Display WORF box if we do not have a TimeGap.
        unless ($entry->{'is_time_gap'}) {

          my $worf;
          try {

            print "<td>";

            # First the raw.
            if( $worfraw{$currentinst} ) {
              # Form an OMP::WORF object for the obs
              if( ! defined( $worf ) ) {
                require OMP::WORF;
                $worf = new OMP::WORF( obs => $obs );
              }
              if( $worf->file_exists( suffix => '', group => 0 ) ) {
                print "<a class=\"link_dark_small\" href=\"${worflink}ut=";
                print $obsut;
                print "&runnr=" . $obs->runnr . "&inst=" . $instrument;
                print "\">raw</a> ";
              }
            }

            # Then the individual reduced.
            if( $worfreduced{$currentinst} ) {
              if( ! defined( $worf ) ) {
                require OMP::WORF;
                $worf = new OMP::WORF( obs => $obs );
              }
              my @ind_suffices = $worf->suffices;
              foreach my $suffix ( @ind_suffices ) {
                next if ! $worf->file_exists( suffix => $suffix, group => 0 );
                print "<a class=\"link_dark_small\" href=\"${worflink}ut=";
                print $obsut;
                print "&runnr=" . $obs->runnr . "&inst=" . $instrument;
                print "&suffix=$suffix\">$suffix</a> ";
              }
            }

            print "/ ";

            # And the group reduced.
            if( $worfreduced{$currentinst} ) {
              if( ! defined( $worf ) ) {
                require OMP::WORF;
                $worf = new OMP::WORF( obs => $obs );
              }
              # Get a list of suffices
              my @grp_suffices = $worf->suffices( 1 );
              if( $worf->file_exists( suffix => '', group => 1 ) ) {
                print "<a class=\"link_dark_small\" href=\"${worflink}ut=";
                print $obsut;
                print "&runnr=" . $obs->runnr . "&inst=" . $instrument;
                print "&group=1\">group</a> ";
              }
              foreach my $suffix ( @grp_suffices ) {
                next if ! $worf->file_exists( suffix => $suffix, group => 1 );
                print "<a class=\"link_dark_small\" href=\"${worflink}ut=";
                print $obsut;
                print "&runnr=" . $obs->runnr . "&inst=" . $instrument;
                print "&suffix=$suffix&group=1\">$suffix</a> ";
              }
            }

           print "</td>";
          }
          catch OMP::Error with {
            my $Error = shift;
#            print STDERR "Error in OMP::CGIObslog::obs_table: " . $Error->{'-text'} . "\n";
            print "<td>Error 1</td>";
#          next;
          }
          otherwise {
            my $Error = shift;
#            print STDERR "Error in OMP::CGIObslog::obs_table: " . $Error->{'-text'} . "\n";
            print "<td>" . $Error->{'-text'} . "</td>";
#          next;
          };
        } else {
          print "<td>&nbsp;</td>";
        }
      }

      print qq[<td class="$css_status">] . $obs->runnr . '</td>';
      # Print the status of the observation explicitly.
      print qq[<td class="$css_status">] . $label_status . '</td>';

      # Print the comments underneath, if there are any, and if the
      # 'showcomments' parameter is not '0', and if we're not looking at a timegap
      # (since timegap comments show up in the nightlog string)
      if( defined( $comments ) &&
          defined( $comments->[0] ) &&
          ( $showcomments != 0 ) &&
          ! $entry->{'is_time_gap'} ) {

        print "<tr class=\"$rowclass\"><td colspan=\"" . $ncols . "\">";
        my @printstrings;
        foreach my $comment (@$comments) {
          my $string = qq[ <span class="] . $css{$comment->status} . '">'
                      . $comment->date->cdate . ' UT / '
                      . $comment->author->name . ':'
                      . ' '
                      . OMP::Display::escape_entity( $comment->text )
                      . '</span>';

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

    $is_first_block = 0;
  }

  # And finish the table.
  print "</table>\n";
}

=item B<obs_table_text>

Prints a plain text table containing a summary of information about a
group of observations.

  $comp->obs_table_text( $obsgroup, %options );

The first argument is the C<OMP::Info::ObsGroup>
object, and remaining options tell the function how to
display things.

=over 4

=item *

showcomments - Boolean on whether or not to print comments [true].

=back

=cut

sub obs_table_text {
  my $self = shift;
  my $obsgroup = shift;
  my %options = @_;

  # Verify the ObsGroup object.
  if( ! UNIVERSAL::isa($obsgroup, "OMP::Info::ObsGroup") ) {
    throw OMP::Error::BadArgs("Must supply an Info::ObsGroup object")
  }

  my $showcomments;
  if( exists( $options{showcomments} ) ) {
    $showcomments = $options{showcomments};
  } else {
    $showcomments = 1;
  }

  my $summary = $self->get_obs_summary($obsgroup, %options);

  unless (defined $summary) {
    print "No observations for this night\n";
    return;
  }

  my $is_first_block = 1;
  foreach my $instblock (@{$summary->{'block'}}) {
    my $ut = $instblock->{'ut'};
    my $currentinst = $instblock->{'instrument'};

    if ($is_first_block) {
      print "\nObservations for " . $currentinst . " on $ut\n";
    }
    else {
      print "\nObservations for " . $currentinst . "\n";
    }

    print $instblock->{'heading'}->{_STRING_HEADER}, "\n";

    foreach my $entry (@{$instblock->{'obs'}}) {
      my $obs = $entry->{'obs'};
      my $nightlog = $entry->{'nightlog'};

      if ($entry->{'is_time_gap'}) {
        print $nightlog->{'_STRING'}, "\n";
      }
      else {
        my @text;
        if (exists $entry->{'msb_comments'}) {
          my $comment = $entry->{'msb_comments'};

          my $title = '';
          $title = sprintf "%s\n", $comment->{'title'}
            if defined $comment->{'title'};

          foreach my $c (@{$comment->{'comments'}}) {
            push @text, $title . sprintf "%s UT by %s\n%s\n",
              $c->date,
              ((defined $c->author) ? $c->author->name : 'UNKNOWN PERSON'),
              $c->text();
          }
        }

        print @text, "\n", $nightlog->{'_STRING'}, "\n";

        if ($showcomments) {
          # Print the comments underneath, if there are any, and if the
          # 'showcomments' parameter is not '0', and if we're not looking at a timegap
          # (since timegap comments show up in the nightlog string)
          my $comments = $obs->comments;
          if (defined($comments) && defined($comments->[0])) {
            foreach my $comment (@$comments) {
              print "    " . $comment->date->cdate . " UT / " . $comment->author->name . ":";
              print $comment->text . "\n";
            }
          }
        }
      }
    }

    $is_first_block = 0;
  }
}

=item B<obs_comment_form>

Returns information for a form that is used to enter a comment about
an observation or time gap.

    $values = $comp->obs_comment_form( $obs, $projectid );

The first argument must be a an C<Info::Obs> object.

=cut

sub obs_comment_form {
  my $self = shift;
  my $obs = shift;
  my $projectid = shift;

  return {
    statuses => (eval {$obs->isa('OMP::Info::Obs::TimeGap')}
        ? [
            [OMP__TIMEGAP_UNKNOWN() => 'Unknown'],
            [OMP__TIMEGAP_INSTRUMENT() => 'Instrument'],
            [OMP__TIMEGAP_WEATHER() => 'Weather'],
            [OMP__TIMEGAP_FAULT() => 'Fault'],
            [OMP__TIMEGAP_NEXT_PROJECT() => 'Next project'],
            [OMP__TIMEGAP_PREV_PROJECT() => 'Last project'],
            [OMP__TIMEGAP_NOT_DRIVER() => 'Observer not driver'],
            [OMP__TIMEGAP_SCHEDULED() => 'Scheduled downtime'],
            [OMP__TIMEGAP_QUEUE_OVERHEAD() => 'Queue overhead'],
            [OMP__TIMEGAP_LOGISTICS() => 'Logistics'],
        ]
        : [map {
            [$_ => $status_label{$_}]
        } sort keys %status_label]
    ),
  };
}

=item B<obs_add_comment>

Store a comment in the database.

  $comp->obs_add_comment();

=cut

sub obs_add_comment {
  my $self = shift;

  my $q = $self->cgi;

  # Set up variables.
  my $qv = $q->Vars;
  my $status = $qv->{'status'};
  my $text = ( defined( $qv->{'text'} ) ? $qv->{'text'} : "" );

  # Get the Info::Obs object from the CGI object
  my $obs = $self->cgi_to_obs( );

  # Form the Info::Comment object.
  my $comment = new OMP::Info::Comment( author => $self->auth->user,
                                        text => $text,
                                        status => $status,
                                      );

  # Store the comment in the database.
  my $odb = new OMP::ObslogDB( DB => new OMP::DBbackend );
  $odb->addComment( $comment, $obs );

  return {
    messages => ['Comment successfully stored in database.'],
  };
}

=item B<cgi_to_obs>

Return an C<Info::Obs> object.

  $obs = $comp->cgi_to_obs( );

In order for this method to work properly, the parent page's C<CGI> object
must have the following URL parameters:

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
  my $self = shift;

  my $q = $self->cgi;

  my $verify =
   { 'ut'      => qr/^(\d{4}-\d\d-\d\d-\d\d?-\d\d?-\d\d?)/,
     'runnr'   => qr/^(\d+)$/,
     'inst'    => qr/^([\-\w\d]+)$/,
     'timegap' => qr/^([01])$/,
     'oid'     => qr/^([a-zA-Z]+[-_A-Za-z0-9]+)$/,
   };

  my $ut      = _cleanse_query_value( $q, 'ut',      $verify );
  my $runnr   = _cleanse_query_value( $q, 'runnr',   $verify );
  my $inst    = _cleanse_query_value( $q, 'inst',    $verify );
  my $timegap = _cleanse_query_value( $q, 'timegap', $verify );
  $timegap   ||= 0;
  my $obsid   = _cleanse_query_value( $q, 'oid',     $verify );

  # Form the Time::Piece object
  $ut = Time::Piece->strptime( $ut, '%Y-%m-%d-%H-%M-%S' );

  # Get the telescope.
  my $telescope = uc(OMP::Config->inferTelescope('instruments', $inst));

  # Form the Info::Obs object.
  my $obs;
  if( $timegap ) {
    $obs = new OMP::Info::Obs::TimeGap( runnr => $runnr,
                                        endobs => $ut,
                                        instrument => $inst,
                                        telescope => $telescope,
                                        obsid     => $obsid,
                                      );
  } else {
    $obs = new OMP::Info::Obs( runnr => $runnr,
                               startobs => $ut,
                               instrument => $inst,
                               telescope => $telescope,
                               obsid     => $obsid,
                             );
  }

  # Comment-ise the Info::Obs object.
  my $db = new OMP::ObslogDB( DB => new OMP::DBbackend );
  $db->updateObsComment([$obs]);

  # And return the Info::Obs object.
  return $obs;

}

=item B<cgi_to_obsgroup>

Given a hash of information, return an C<Info::ObsGroup> object.

  $obsgroup = $comp->cgi_to_obsgroup( ut => $ut, inst => $inst );

In order for this method to work properly, the hash
should have the following keys:

=over 8

=item *

ut - In the form YYYY-MM-DD.

=back

Other parameters are optional and can include:

=over 8

=item *

inst - The instrument that the observation was taken with.

=item *

projid - The project ID for which observations will be returned.

=item *

telescope - The telescope that the observations were taken with.

=back

The C<inst> and C<projid> variables are optional, but either one or the
other (or both) must be defined.

These parameters will override any values contained in the parent page's
C<CGI> object.

=cut

sub cgi_to_obsgroup {
  my $self = shift;
  my %args = @_;

  my $q = $self->cgi;

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

=item B<_cleanse_query_value>

Returns the cleansed URL parameter value given a CGI object,
parameter name, and a hash reference of parameter names as keys &
compiled regexen (capturing a value to be returned) as values.

  $value = _cleanse_query_value( $cgi, 'number',
                                  { 'number' => qr/^(\d+)$/, }
                                );

=cut

sub _cleanse_query_value {

  my ( $q, $key, $verify ) = @_;

  my $val = $q->url_param( $key );

  return
    unless defined $val
    && length $val;

  my $regex = $verify->{ $key } or return;

  return ( $val =~ $regex )[0];
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
along with this program; if not, write to the
Free Software Foundation, Inc., 59 Temple Place, Suite 330,
Boston, MA  02111-1307  USA

=cut

1;
