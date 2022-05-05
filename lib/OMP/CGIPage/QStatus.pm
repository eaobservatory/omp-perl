package OMP::CGIPage::QStatus;

=head1 NAME

OMP::CGIPage::QStatus - Plot the queue status

=cut

use strict;
use warnings;

use CGI;
use CGI::Carp qw/fatalsToBrowser/;
use List::MoreUtils qw/uniq/;

use OMP::CGIComponent::CaptureImage;
use OMP::CGIComponent::Helper qw/url_absolute/;
use OMP::DBbackend;
use OMP::DateTools;
use OMP::General;
use OMP::ProjAffiliationDB qw/%AFFILIATION_NAMES/;
use OMP::ProjDB;
use OMP::SiteQuality;
use OMP::QStatus qw/query_queue_status/;
use OMP::QStatus::Plot qw/create_queue_status_plot/;

use base qw/OMP::CGIPage/;

our $telescope = 'JCMT';

=head1 METHODS

=over 4

=item B<view_queue_status>

Creates a page allowing the user to select the queue status viewing options.

=cut

sub view_queue_status {
    my $self = shift;

    my $q = $self->cgi;

    return $self->_show_input_page({})
        unless $q->param('submit_plot');

    my %opt = (telescope => $telescope);

    do {
        my $semester = $q->param('semester');
        if (defined $semester) {
            die 'invalid semester' unless $semester =~ /^([-_A-Za-z0-9]+)$/;
            $opt{'semester'} = $1;
        }
    };

    $opt{'country'} = {
        map {die 'invalid queue' unless /^([-_A-Za-z0-9+]+)$/; $_ => 1}
        grep {defined $_ and $_ ne 'Any'} $q->multi_param('country')};

    do {
        my $affiliation = $q->param('affiliation');
        if (defined $affiliation and $affiliation ne 'Any') {
            die 'invalid affiliation ' unless $affiliation =~ /^([-_A-Za-z0-9]+)$/;
            $opt{'affiliation'} = $1;
        }
    };

    $opt{'instrument'} = {
        map {die 'invalid instrument' unless /^([-_A-Za-z0-9]+)$/; $_ => 1}
        grep {defined $_ and $_ ne 'Any'} $q->multi_param('instrument')};

    do {
        my $band = $q->param('band');
        if (defined $band and $band ne 'Any') {
            die 'invalid band' unless $band =~ /^([1-5])$/;
            $opt{'band'} = $1;
        }
    };

    do {
        my $date = $q->param('date');
        if (defined $date and $date ne '') {
            die 'invalid date' unless $date =~ /^([-0-9]+)$/;
            $opt{'date'} = OMP::DateTools->parse_date($1);
        }
    };

    my %query_opt = %opt;
    if (exists $query_opt{'band'}) {
        my $r = OMP::SiteQuality::get_tauband_range($telescope, delete $query_opt{'band'});
        $query_opt{'tau'} = ($r->min() + $r->max()) / 2.0;
    }
    foreach my $param (qw/country instrument/) {
        $query_opt{$param} = [uniq map {split /\+/} keys %{$query_opt{$param}}];
    }

    # Pass options to query_queue_status.
    my ($proj_msb, $utmin, $utmax) = query_queue_status(
        return_proj_msb => 1, %query_opt);

    my @proj_order;
    my $order = $q->param('order');
    if ($order eq 'priority') {
        my %priority = ();
        while (my ($proj, $msbs) = each %$proj_msb) {
            my (undef, $msb) = each %$msbs; keys %$msbs;
            $priority{$proj} = int($msb->priority());
        }
        @proj_order = sort {$priority{$a} <=> $priority{$b}} keys %$proj_msb;
    }
    else {
        # Default ordering is by project ID.
        @proj_order = sort keys %$proj_msb;
    }

    my @project = $q->multi_param('project');
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

    my $capture = new OMP::CGIComponent::CaptureImage(page => $self);

    $opt{'order'} = $order;
    $opt{'projects'} = {map {$_ => 1} @project};
    my $context = $self->_show_input_page(\%opt, projects => \@proj_order);

    if (%$proj_msb_filt) {
        $context->{'plot'} = $capture->capture_png_as_data(sub {
            create_queue_status_plot(
                $proj_msb_filt, $utmin, $utmax,
                output => '-',
                hdevice => '/PNG',
            );
        });

        $context->{'results'} = $self->_show_result_table(
            $proj_msb, \@project, \@proj_order);
    }
    else {
        $context->{'results'} = []
    }

    return $context;
}

=back

=head2 Private Subroutines

=over 4

=item _show_input_page

Shows the input parameters form.

=cut

sub _show_input_page {
    my $self = shift;
    my $values = shift;
    my %opt = @_;

    my $q = $self->cgi;

    my $db = new OMP::ProjDB(DB => new OMP::DBbackend());
    my $semester = OMP::DateTools->determine_semester();
    my @semesters = $db->listSemesters(telescope => $telescope);
    push @semesters, $semester unless grep {$_ eq $semester} @semesters;
    $values->{'semester'} //= $semester;

    my @countries = grep {! /^ *$/ || /^serv$/i} $db->listCountries(telescope => $telescope);
    # Add special combinations (see fault 20210831.001).
    push @countries, 'PI+IF';

    my @affiliation_codes = sort {
        $AFFILIATION_NAMES{$a} cmp $AFFILIATION_NAMES{$b}
    } keys %AFFILIATION_NAMES;

    return {
        target => url_absolute($q),
        semesters => [sort @semesters],
        countries => [sort @countries],
        affiliations => [map {
            [$_, $AFFILIATION_NAMES{$_}]
            } @affiliation_codes],
        instruments => [qw/SCUBA-2 HARP AWEOWEO UU ALAIHI RXA3M/],
        bands => [qw/1 2 3 4 5/],
        orders => [
            [priority => 'Priority'],
            [projectid => 'Project ID'],
        ],
        values => $values,
        projects => ((exists $opt{'projects'}) ? $opt{'projects'} : []),
    };
}

=item _show_result_table

Shows a table of the query results.

=cut

sub _show_result_table {
    my $self = shift;
    my $proj_msb = shift;
    my $proj_search = shift;
    my $proj_order = shift;

    my @proj_shown = ();
    my @proj_hidden = ();

    my $no_filter = not scalar @$proj_search;

    foreach my $project (@$proj_order) {
        if ($no_filter or grep {$_ eq $project} @$proj_search) {
            push @proj_shown, $proj_msb->{$project};
        }
        else {
            push @proj_hidden, $proj_msb->{$project};
        }
    }

    return [
        (map {[$_, 1]} @proj_shown),
        (map {[$_, 0]} @proj_hidden),
    ];
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
