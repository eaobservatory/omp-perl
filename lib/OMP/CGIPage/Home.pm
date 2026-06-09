package OMP::CGIPage::Home;

=head1 NAME

OMP::CGIPage::Home - Display OMP home page

=head1 SYNOPSIS

    use OMP::CGIPage::Home;

=head1 DESCRIPTION

Helper methods for preparing the OMP home page.

=cut

use strict;
use warnings;

use Carp;

use OMP::Constants;
use OMP::CGIComponent::Search;
use OMP::DB::Fault;
use OMP::DB::Obslog;
use OMP::DB::Project;
use OMP::DB::User;
use OMP::DB::Shift;
use OMP::General;
use OMP::Query::Fault;
use OMP::Query::Obslog;
use OMP::Query::Shift;

use base qw/OMP::CGIPage/;

my $query_placeholder = 'Fault, project, obs. ID, date or search';

=head1 Routines

=over 4

=item B<home_page_view>

Creates the OMP home page.

=cut

sub home_page_view {
    my $self = shift;

    return {
        fault_categories => [
            ['JCMT', 'JCMT faults'],
            ['JCMT_EVENTS', 'JCMT events'],
            ['UKIRT', 'UKIRT faults'],
            ['CSG', 'CSG faults'],
            ['OMP', 'OMP faults'],
            ['DR', 'DR faults'],
            ['FACILITY', 'Facility faults'],
            ['VEHICLE_INCIDENT', 'Vehicle incident reporting'],
            ['SAFETY', 'Safety reporting'],
        ],
        query_placeholder => $query_placeholder,
    };
}

=item B<search>

Creates the quick search page.  This page accepts a single text query string.
The query is matched against various patterns and if any match then a redirct
is written.  This allows the page to be used to navigate quickly to an
observation, fault, etc.

=cut

sub search {
    my $self = shift;

    my $db = $self->database;

    my $search = OMP::CGIComponent::Search->new(page => $self);

    my $query = $self->cgi->param('q') // '';
    $query =~ s/^\s*//;
    $query =~ s/\s*$//;

    my $telescope = 'JCMT';

    my @results = ();
    if ($query) {
        # Obs. ID -> WORF page.
        if ($query =~ /^((?:acsis|scuba2)_\d+_\d{8}T\d{6})$/aa) {
            return $self->_write_redirect(sprintf
                '/cgi-bin/staffworf.pl?telescope=JCMT&obsid=%s',
                $1);
        }

        # Fault ID.
        if ($query =~ /^(\d{8}\.\d{3})$/aa) {
            my $faultid = OMP::General->extract_faultid(sprintf '[%s]', $1);
            return $self->_write_redirect(sprintf
                '/cgi-bin/viewfault.pl?fault=%s',
                $faultid)
                if defined $faultid;
        }

        # A date -> obs. log page.
        if ($query =~ /^(\d{4})-?(\d{2})-?(\d{2})$/aa) {
            return $self->_write_redirect(sprintf
                '/cgi-bin/nightrep.pl?tel=%s&utdate=%s-%s-%s',
                $telescope, $1, $2, $3);
        }

        # Alphanumeric sequence - could it be a project?
        if ($query =~ /^([A-Z0-9]+)$/aai) {
            my $projectid = OMP::General->extract_projectid(uc $1);
            if (defined $projectid) {
                my $pdb = OMP::DB::Project->new(
                    DB => $db, ProjectID => $projectid);
                return $self->_write_redirect(sprintf
                    '/cgi-bin/projecthome.pl?project=%s',
                    $projectid)
                    if $pdb->verifyProject;
            }
        }

        # A user ID?
        if ($query =~ /^([A-Z]+[0-9]*)$/aai) {
            my $udb = OMP::DB::User->new(DB => $db);
            my $userid = $udb->verifyUser(uc $1);
            return $self->_write_redirect(sprintf
                '/cgi-bin/userdetails.pl?&user=%s',
                $userid)
                if defined $userid;
        }

        # No quick pattern matched, prepare to perform searches.
        my %options = (
            MaxCount => 15,
            OrderBy => [['relevance', 1]],
        );

        my $min_status_timegap = OMP__TIMEGAP_INSTRUMENT;
        my $odb = OMP::DB::Obslog->new(DB => $self->database);
        push @results, map {{
            type => (($_->status >= $min_status_timegap) ? 'obsgap' : 'obs'),
            comment => $_,
            relevance => $_->relevance,
            snippet => $search->text_snippet($query, $_, html => 1),
        }} @{$odb->queryComments(
            OMP::Query::Obslog->new(HASH => {
                telescope => $telescope,
                text => $query,
                obsactive => {boolean => 1},
            }, %options),
            {allow_dateless => 1})};

        my $sdb = OMP::DB::Shift->new(DB => $self->database);
        push @results, map {{
            type => 'shift',
            comment => $_,
            relevance => $_->relevance,
            snippet => $search->text_snippet($query, $_, html => 1),
        }} @{$sdb->getShiftLogs(
            OMP::Query::Shift->new(HASH => {
                text => $query,
                telescope => $telescope,
                date => {min => '2003-01-01'},  # (exclude old very large single logs)
                private => {any => 1},  # (include entries marked private)
            }, %options))};

        my $fdb = OMP::DB::Fault->new(DB => $self->database);
        push @results, map {{
            type => 'fault',
            fault => $_,
            relevance => $_->relevance,
            snippet => $search->text_snippet($query, $_->responses->[0], html => 1),
        }} @{$fdb->queryFaults(OMP::Query::Fault->new(HASH => {
                 'EXPR__TS' => {or => {
                    text => $query,
                    subject => $query,
                }},
            }, %options),
            matching_responses_only => 1,
            separate_responses => 1,
        )->faults};

        # Sort the combined results by relevance.
        @results = sort {$b->{'relevance'} <=> $a->{'relevance'}} @results;
    }

    return {
        title => 'Search',
        telescope => $telescope,
        query => $query,
        query_placeholder => $query_placeholder,
        results => \@results,
    };
}

1;

__END__

=back

=head1 COPYRIGHT

Copyright (C) 2022 East Asian Observatory
All Rights Reserved.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful,but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc.,51 Franklin
Street, Fifth Floor, Boston, MA  02110-1301, USA

=cut
