package OMP::CGIComponent::NightRep;

=head1 NAME

OMP::CGIComponent::NightRep - CGI functions for the observation log tool.

=head1 SYNOPSIS

use OMP::CGIComponent::NightRep;

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
use OMP::NightRep;
use OMP::General;
use OMP::Info::Comment;
use OMP::Info::Obs;
use OMP::Info::ObsGroup;
use OMP::ObslogDB;
use OMP::ProjServer;
use OMP::Error qw/ :try /;

use base qw/OMP::CGIComponent/;

our $VERSION = '2.000';

=head1 Routines

=over 4

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

  my $summary = OMP::NightRep->get_obs_summary(obsgroup => $obsgroup, %options);

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
            [$_ => $OMP::Info::Obs::status_label{$_}]
        } @OMP::Info::Obs::status_order]
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

  my $verify =
   { 'ut'      => qr/^(\d{4}-\d\d-\d\d-\d\d?-\d\d?-\d\d?)/a,
     'runnr'   => qr/^(\d+)$/a,
     'inst'    => qr/^([\-\w\d]+)$/a,
     'timegap' => qr/^([01])$/,
     'oid'     => qr/^([a-zA-Z]+[-_A-Za-z0-9]+)$/,
   };

  my $ut      = $self->_cleanse_query_value( 'ut',      $verify );
  my $runnr   = $self->_cleanse_query_value( 'runnr',   $verify );
  my $inst    = $self->_cleanse_query_value( 'inst',    $verify );
  my $timegap = $self->_cleanse_query_value( 'timegap', $verify );
  $timegap   ||= 0;
  my $obsid   = $self->_cleanse_query_value( 'oid',     $verify );

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
      throw OMP::Error("OMP::CGIComponent::NightRep: Cannot determine telescope!\n");
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

  $value = $comp->_cleanse_query_value( 'number',
                                  { 'number' => qr/^(\d+)$/a, }
                                );

=cut

sub _cleanse_query_value {

  my ( $self, $key, $verify ) = @_;

  my $val = $self->page->decoded_url_param( $key );

  return
    unless defined $val
    && length $val;

  my $regex = $verify->{ $key } or return;

  return ( $val =~ $regex )[0];
}

=back

=head1 SEE ALSO

C<OMP::CGIPage::NightRep>

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
