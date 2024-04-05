package OMP::CGIPage::ShiftLog;

=head1 NAME

OMP::CGIPage::ShiftLog - Display complete web pages for the shiftlog tool

=head1 SYNOPSIS

    use OMP::CGIComponent::ShiftLog;

    shiftlog_page($cgi);

=head1 DESCRIPTION

This module provides routines to display complete web pages for viewing
shiftlog information, and submitting shiftlog comments.

=cut

use strict;
use warnings;

use CGI;
use CGI::Carp qw/fatalsToBrowser/;

use OMP::CGIComponent::Search;
use OMP::CGIComponent::ShiftLog;
use OMP::Error qw/:try/;
use OMP::ShiftDB;
use OMP::ShiftQuery;

use base qw/OMP::CGIPage/;

our $VERSION = '2.000';

=head1 Routines

All routines are exported by default.

=over 4

=item B<shiftlog_page>

Creates a page with a form for filing a shiftlog entry
after a form on that page has been submitted.

    $page->shiftlog_page([$projectid]);

=cut

sub shiftlog_page {
    my $self = shift;
    my $projectid = shift;

    my $q = $self->cgi;
    my $comp = OMP::CGIComponent::ShiftLog->new(page => $self);

    my $parsed = $comp->parse_query();

    if ($q->param('submit_comment')) {
        my $E;
        try {
            $comp->submit_comment($parsed);
        }
        otherwise {
            $E = shift;
        };

        return $self->_write_error('Error storing shift comment.', "$E")
            if defined $E;

        return $self->_write_redirect($self->url_absolute());
    }

    $self->_sidebar_night($parsed->{'telescope'}, $parsed->{'date'})
        unless defined $projectid;

    return {
        target => $self->url_absolute(),
        target_base => $q->url(-absolute => 1),
        project_id => $projectid,
        values => $parsed,
        telescopes => [sort map {uc} OMP::Config->telescopes()],

        comments => $comp->get_shift_comments($parsed),
    };
}

=item B<shiftlog_search>

Creates a page for searching shiftlog entries.

=cut

sub shiftlog_search {
    my $self = shift;

    my $q = $self->cgi;
    my $search = OMP::CGIComponent::Search->new(page => $self);

    my $telescope = 'JCMT';
    my $message = undef;
    my $result = undef;
    my %values = (
        text => '',
        text_boolean => 0,
        period => 'arbitrary',
        author => '',
        mindate => '',
        maxdate => '',
        days => '',
    );

    if ($q->param('search')) {
        %values = (
            %values,
            $search->read_search_common(),
            $search->read_search_sort(),
        );

        ($message, my $hash) = $search->common_search_hash(\%values, 'author');

        unless (defined $message) {
            $hash->{'telescope'} = $telescope;
            my $query = OMP::ShiftQuery->new(HASH => $hash);

            my $sdb = OMP::ShiftDB->new(DB => $self->database);
            $result = $search->sort_search_results(
                \%values, 'date',
                scalar $sdb->getShiftLogs($query));

            $message = 'No matching shift log entries found.'
                unless scalar @$result;
        }
    }

    return {
        message => $message,
        form_info => {
            target => $self->url_absolute(),
            values => \%values,
        },
        log_entries => $result,
        telescope => $telescope,
    };
}

1;

__END__

=back

=head1 SEE ALSO

C<OMP::CGIComponent::ShiftLog>

=head1 AUTHOR

Brad Cavanagh E<lt>b.cavanagh@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

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
