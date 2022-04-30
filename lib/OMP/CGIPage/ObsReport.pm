package OMP::CGIPage::ObsReport;

=head1 NAME

OMP::CGIPage::ObsReport - Web display of observing reports

=head1 SYNOPSIS

  use OMP::CGIPage::ObsReport;

=head1 DESCRIPTION

Helper methods for creating web pages that display observing
reports.

=cut

use 5.006;
use strict;
use warnings;

use Capture::Tiny qw/capture_stdout/;
use Carp;

use OMP::DateTools;
use Time::Piece;
use Time::Seconds qw(ONE_DAY);

use OMP::CGIComponent::IncludeFile;
use OMP::CGIComponent::Weather;
use OMP::Constants qw(:done);
use OMP::DBbackend;
use OMP::General;
use OMP::MSBServer;
use OMP::NightRep;
use OMP::TimeAcctDB;

use base qw/OMP::CGIPage/;

$| = 1;

=head1 Routines

=over 4

=item B<night_report>

Create a page summarizing activity for a particular night.

  $page->night_report($self);

=cut

sub night_report {
  my $self = shift;
  my $q = $self->cgi();

  my $weathercomp = OMP::CGIComponent::Weather->new(page => $self);
  my $includecomp = OMP::CGIComponent::IncludeFile->new(page => $self);

  my $delta;
  my $utdate;
  my $utdate_end;
  my $start;

  if ($q->param('utdate_end')) {
    # Get delta and start UT date from multi night form
    $utdate = OMP::DateTools->parse_date(scalar $q->param('utdate'));
    $utdate_end = OMP::DateTools->parse_date(scalar $q->param('utdate_end'));

    # Croak if date format is wrong
    croak("The date string provided is invalid.  Please provide dates in the format of YYYY-MM-DD")
      if (! $utdate or ! $utdate_end);

    # Derive delta from start and end UT dates
    $delta = $utdate_end - $utdate;
    $delta = $delta->days + 1;  # Need to add 1 to our delta
                                # to include last day
  }
  else {
    if ($q->param('utdate')) {
      # Get UT date from single night form
      $utdate = OMP::DateTools->parse_date(scalar $q->param('utdate'));

      # Croak if date format is wrong
      croak("The date string provided is invalid.  Please provide dates in the format of YYYY-MM-DD")
        if (! $utdate);
    }
    else {
      # No UT date in URL.  Use current date.
      $utdate = OMP::DateTools->today(1);

      $start = substr($utdate->ymd(), 0, 8);
    }

    # Get delta from URL
    if ($q->param('delta')) {
      my $deltastr = $q->param('delta');
      if ($deltastr =~ /^(\d+)$/) {
        $delta = $1;
      } else {
        croak("Delta [$deltastr] does not match the expect format so we are not allowed to untaint it!");
      }

      # We need an end date for display purposes
      $utdate_end = $utdate;

      # Subtract delta (days) from date if we have a delta
      $utdate = $utdate_end - ($delta - 1) * ONE_DAY;

      undef $start;
    }
  }

  # Get the telescope from the URL
  my $telstr = $q->param('tel');

  # Untaint the telescope string
  my $tel;
  if ($telstr) {
    if ($telstr =~ /^(UKIRT|JCMT)$/i ) {
      $tel = uc($1);
    } else {
      croak("Telescope string [$telstr] does not match the expect format so we are not allowed to untaint it!");
    }
  } else {
    return $self->_write_error('No telescope selected.');
  }

  # Setup our arguments for retrieving night report
  my %args = (date => $utdate->ymd,
              telescope => $tel,);
  ($delta) and $args{delta_day} = $delta;

  my $other_nr_link = $tel =~ m/^jcmt$/i ? 'UKIRT' : 'JCMT' ;

  # Get the night report
  my $nr = new OMP::NightRep(%args);

  return $self->_write_error(
      'No observing report available for ' . $utdate->ymd . ' at ' . $tel . '.')
      unless $nr;

  my ($prev, $next);
  unless ($delta) {
    my $epoch = $utdate->epoch();
    ($prev, $next) = map { scalar gmtime( $epoch + $_ ) } ( -1 * ONE_DAY() , ONE_DAY() );
  }

  my $night_report_html = capture_stdout {
      if ($tel eq 'JCMT') {
          $nr->ashtml( worfstyle => 'none',
                       commentstyle => 'staff', );
      } else {
          $nr->ashtml( worfstyle => 'staff',
                       commentstyle => 'staff', );
      }
  };

  # NOTE: disabled as we currently don't have fits in the OMP.
  # taufits: $weathercomp->tau_plot($utdate),
  # NOTE: also currently disabled?
  # wvm: $weathercomp->wvm_graph($utdate->ymd),
  # zeropoint: $weathercomp->zeropoint_plot($utdate),
  # NOTE: currently not working:
  # ['seeing', 'UKIRT K-band seeing', $weathercomp->seeing_plot($utdate)],
  # ['extinction', 'UKIRT extinction', $weathercomp->extinction_plot($utdate)],

  $self->_sidebar_night($tel, $utdate) unless $delta;

  return {
      target_base => $q->url(-absolute => 1),

      telescope => $tel,
      other_telescope => $other_nr_link,

      ut_date => $utdate,
      ut_date_end => $utdate_end,
      ut_date_delta => $delta,
      ut_date_prev => $prev,
      ut_date_next => $next,
      ut_date_start => $start,  # starting value for form

      night_report => $nr,
      night_report_html => $night_report_html,

      dq_nightly_html => ($tel ne 'JCMT' || $delta ? undef :
          $includecomp->include_file_ut('dq-nightly', $utdate->ymd())),

      weather_plots => ($delta ? undef : [
          grep {$_->[2]}
          ['meteogram', 'EAO meteogram', $weathercomp->meteogram_plot($utdate)],
          ['opacity', 'Maunakea opacity', $weathercomp->opacity_plot($utdate)],
          ['forecast', 'MKWC forecast', $weathercomp->forecast_plot($utdate)],
          ['transparency', 'CFHT transparency', $weathercomp->transparency_plot($utdate)],
      ]),
  };
}

=back

=head1 AUTHOR

Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2004 Particle Physics and Astronomy Research Council.
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
