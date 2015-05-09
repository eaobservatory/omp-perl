package OMP::CGIPage::QStatus;

=head1 NAME

OMP::CGIPage::QStatus - Plot the queue status

=cut

use strict;
use warnings;

use CGI;
use CGI::Carp qw/fatalsToBrowser/;

use OMP::CGIComponent::CaptureImage qw/capture_png_as_img/;
use OMP::CGIDBHelper;
use OMP::DBbackend;
use OMP::DateTools;
use OMP::General;
use OMP::ProjAffiliationDB qw/%AFFILIATION_NAMES/;
use OMP::ProjDB;
use OMP::SiteQuality;
use OMP::QStatus qw/query_queue_status/;
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

    _show_input_page($q);
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

    # Pass options to query_queue_status.
    my ($proj_msb, $utmin, $utmax) = query_queue_status(
        return_proj_msb => 1, %opt);

    _show_input_page($q, project => [sort keys %$proj_msb]);

    my @project = $q->param('project');
    my $proj_msb_filt = {};
    if (scalar @project) {
        # Filter hash by project.
        foreach (@project) {
            $proj_msb_filt->{$_} = $proj_msb->{$_} if exists $proj_msb->{$_};
        }
    }
    else {
        # No filter to apply.
        $proj_msb_filt = $proj_msb;
    }

    print $q->h2('Search results');

    if (%$proj_msb_filt) {
        print $q->p(capture_png_as_img($q, sub {
                create_queue_status_plot(
                    $proj_msb_filt, $utmin, $utmax,
                    output => '-',
                    hdevice => '/PNG',
                );
            }));

        _show_result_table($q, $proj_msb, \@project);
    }
    else {
        print $q->p($q->i('No observations found'));
    }
}

=back

=head2 Private Subroutines

=over 4

=item _show_input_page

Shows the input parameters form.

=cut

sub _show_input_page {
    my $q = shift;
    my %opt = @_;

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

    my @project = (exists $opt{'project'}) ? @{$opt{'project'}} : ();

    print
        $q->h2('View Queue Status'),
        $q->start_form(),
        $q->table(
            $q->Tr([
                $q->td($q->b('Semester')) .
                    $q->td($q->popup_menu(-name => 'semester',
                                          -values => \@semesters,
                                          -default => $semester)) .
                    $q->td({-rowspan => 7}, (scalar @project)
                        ? $q->b('Project') .
                            $q->br() .
                            $q->scrolling_list(-name => 'project',
                                               -values => \@project,
                                               -multiple => 1,
                                               -size => 10)
                        : $q->i('No projects from previous search')
                    ),
                $q->td([
                    $q->b('Country'),
                    $q->popup_menu(-name => 'country',
                                   -values => \@countries,
                                   -default => 'Any')
                ]),
                $q->td([
                    $q->b('Affiliation'),
                    $q->popup_menu(-name => 'affiliation',
                                   -values => \@affiliation_codes,
                                   -default => 'Any',
                                   -labels => \%affiliation_names)
                ]),
                $q->td([
                    $q->b('Instrument'),
                    $q->popup_menu(-name => 'instrument',
                                   -values => \@instruments,
                                   -default => 'Any')
                ]),
                $q->td([
                    $q->b('Band'),
                    $q->popup_menu(-name => 'band',
                                   -values => [qw/Any 1 2 3 4 5/],
                                   -default => 'Any')
                ]),
                $q->td([
                    $q->b('Date'),
                    $q->textfield(-name => 'date', -default => '') .
                        ' (default today)'
                ]),
                $q->td([
                  $q->hidden(-name => 'show_output', -value => 'true'),
                  $q->submit(-value => 'Plot')
                ]),
            ]),
        ),
        $q->end_form();
}

=item _show_result_table

Shows a table of the query results.

=cut

sub _show_result_table {
    my $q = shift;
    my $proj_msb = shift;
    my $proj_search = shift;

    my @proj_shown = ();
    my @proj_hidden = ();

    my $no_filter = not scalar @$proj_search;

    foreach my $project (sort keys %$proj_msb) {
        if ($no_filter or grep {$_ eq $project} @$proj_search) {
            push @proj_shown, $proj_msb->{$project};
        }
        else {
            push @proj_hidden, $proj_msb->{$project};
        }
    }

    print $q->table(
        $q->Tr($q->th({-align => 'left'},
            [qw/Project MSB Target RA Dec Type Instrument Tau Remaining Time Completion/])),
        (map {_show_result_table_project($q, $_, 1)} @proj_shown),
        (map {_show_result_table_project($q, $_, 0)} @proj_hidden),
    );
}

=item _show_result_table_project

Returns a section of results table for one project.

=cut

sub _show_result_table_project {
    my $q = shift;
    my $proj = shift;
    my $shown = shift;

    my %attrib = ();
    $attrib{'-style'} ='opacity: 0.5' unless $shown;

    my @row = ();
    my $proj_first = 1;

    foreach my $msb (values %$proj) {
        my $msb_first = 1;
        my $time = $msb->timeest();
        $time = sprintf('%02i min %02i sec', int($time / 60), $time % 60);
        my $completion = sprintf('%.1f %%', $msb->completion());

        foreach my $obs ($msb->observations()) {
            my $obs_first = 1;

            foreach my $coord ($obs->coords()) {
                my $type = $coord->type();
                $type = 'RADEC' if $type eq 'INTERP';
                my $ra = $type;
                my $dec = $type;
                unless ($type eq 'CAL' or $type eq 'AUTO-TLE') {
                    $ra = $coord->ra();
                    $dec = $coord->dec();
                }

                push @row, [
                    ($proj_first ? _project_link($q, $msb->projectid())
                                                      : '&nbsp'),
                    ($msb_first  ? $msb->title()      : '&nbsp'),
                    ($coord->name()                   // 'Unnamed target'),
                    $ra, $dec, $type,
                    ($obs_first  ? $obs->instrument() : '&nbsp;'),
                    ($msb_first  ? $msb->tau()        : '&nbsp;'),
                    ($msb_first  ? $msb->remaining()  : '&nbsp;'),
                    ($msb_first  ? $time              : '&nbsp;'),
                    ($proj_first ? $completion        : '&nbsp;'),
                ];

                $proj_first = $msb_first = $obs_first = 0;
            }
        }
    }

    return $q->Tr(\%attrib, [map {$q->td($_)} @row]);
}

=item _project_link

Returns HTML linking to a project.

=cut

sub _project_link {
    my $q = shift;
    my $project = shift;

    return
        $q->a({-href => 'projecthome.pl?urlprojid=' . $project}, $project) .
        ' (' .
        $q->a({-href => 'sourceplot.pl?projid=' . $project}, 'plot') .
        ')';
}

1;

__END__

=back

=head1 COPYRIGHT

Copyright (C) 2015 East Asian Observatory.
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
