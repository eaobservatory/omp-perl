package OMP::CGIPage::QStatus;

=head1 NAME

OMP::CGIPage::QStatus - Plot the queue status

=cut

use strict;
use warnings;

use OMP::CGIComponent::CaptureImage qw/capture_png_as_img/;
use OMP::QStatus::Plot;

use CGI;
use CGI::Carp qw/fatalsToBrowser/;

use OMP::CGIDBHelper;
use OMP::DBbackend;
use OMP::DateTools;
use OMP::General;
use OMP::ProjAffiliationDB qw/%AFFILIATION_NAMES/;
use OMP::ProjDB;
use OMP::SiteQuality;
use OMP::QStatus::Plot qw/create_queue_status_plot/;

our $telescope = 'JCMT';

=head1 METHODS

=over 4

=item B<view_queue_status>

Creates a page allowing the user to select the queue status viewing options.

=cut

sub view_queue_status {
    my $q = shift;
    my %cookie = @_;

    my $db = new OMP::ProjDB(DB => new OMP::DBbackend());
    my $semester = OMP::DateTools->determine_semester();
    my @semesters = $db->listSemesters();
    unshift @semesters, $semester unless grep {$_ eq $semester} @semesters;

    my @countries = ('Any', grep {! /^ *$/ || /^serv$/i} $db->listCountries());

    my @affiliation_codes = ('Any',
      sort {$AFFILIATION_NAMES{$a} cmp $AFFILIATION_NAMES{$b}}
      keys %AFFILIATION_NAMES);
    my %affiliation_names = (Any => 'Any', %AFFILIATION_NAMES);

    my @instruments = qw/Any SCUBA-2 HARP RXA3/;

    print $q->h2('View Queue Status'),
          $q->start_form(),
          $q->p(
              $q->b('Semester'),
              $q->popup_menu(-name => 'semester',
                             -values => \@semesters,
                             -default => $semester)),
          $q->p(
              $q->b('Country'),
              $q->popup_menu(-name => 'country',
                             -values => \@countries,
                             -default => 'Any')),
          $q->p(
              $q->b('Affiliation'),
              $q->popup_menu(-name => 'affiliation',
                             -values => \@affiliation_codes,
                             -default => 'Any',
                             -labels => \%affiliation_names)),
          $q->p(
              $q->b('Instrument'),
              $q->popup_menu(-name => 'instrument',
                             -values => \@instruments,
                             -default => 'Any')),
          $q->p(
              $q->b('Band'),
              $q->popup_menu(-name => 'band',
                             -values => [qw/Any 1 2 3 4 5/],
                             -default => 'Any')),
          $q->p(
              $q->b('Date'),
              $q->textfield(-name => 'date', -default => ''),
              '(default today)'),
          $q->p(
            $q->hidden(-name => 'show_output', -value => 'true'),
            $q->submit(-value => 'Plot')),
          $q->end_form();
}

=item B<view_queue_status_output>

Outputs the queue status plot.

=cut

sub view_queue_status_output {
    my $q = shift;
    my %cookie = @_;

    my %opt = (telescope => $telescope);

    do {
        my $semester = $q->param('semester');
        if (defined $semester) {
            die 'invalid semester' unless $semester =~ /^([-_A-Za-z0-9]+)$/;
            $opt{'semester'} = $1;
        }
    };

    do {
        my $country = $q->param('country');
        if (defined $country and $country ne 'Any') {
            die 'invalid country' unless $country =~ /^([-_A-Za-z0-9]+)$/;
            $opt{'country'} = $1;
        }
    };

    do {
        my $affiliation = $q->param('affiliation');
        if (defined $affiliation and $affiliation ne 'Any') {
            die 'invalid affiliation ' unless $affiliation =~ /^([-_A-Za-z0-9]+)$/;
            $opt{'affiliation'} = $1;
        }
    };

    do {
        my $instrument = $q->param('instrument');
        if (defined $instrument and $instrument ne 'Any') {
            die 'invalid instrument' unless $instrument =~ /^([-_A-Za-z0-9]+)$/;
            $opt{'instrument'} = $1;
        }
    };

    do {
        my $band = $q->param('band');
        if (defined $band and $band ne 'Any') {
            die 'invalid band' unless $band =~ /^([1-5])$/;
            my $r = OMP::SiteQuality::get_tauband_range($telescope, $1);
            $opt{'tau'} = ($r->min() + $r->max()) / 2.0;
        }
    };

    do {
        my $date = $q->param('date');
        if (defined $date and $date ne '') {
            die 'invalid date' unless $date =~ /^([-0-9]+)$/;
            $opt{'date'} = OMP::DateTools->parse_date($1);
        }
    };

    print
        $q->h2('Search results'),
        $q->p(capture_png_as_img($q, sub {
            create_queue_status_plot(
                output => '-',
                hdevice => '/PNG',
                %opt,
            );
        }));
}

=back

=cut

1;
