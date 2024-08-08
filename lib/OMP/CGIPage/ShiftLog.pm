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
use OMP::DB::Shift;
use OMP::Query::Shift;

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

    my $allow_edit = (not defined $projectid);

    my $q = $self->cgi;
    my $comp = OMP::CGIComponent::ShiftLog->new(page => $self);

    my $parsed = $comp->parse_query();

    if ($allow_edit and $q->param('submit_comment')) {
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
        allow_edit => $allow_edit,

        comments => $comp->get_shift_comments(
            $parsed, (not defined $projectid)),
    };
}

=item B<shiftlog_edit>

Page allowing an existing shift log entry to be edited.

=cut

sub shiftlog_edit {
    my $self = shift;

    my $q = $self->cgi;
    my @messages = ();
    my $id = $self->decoded_url_param('shiftid');

    return $self->_write_error('Shift log entry ID not given.')
        unless defined $id;

    my $sdb = OMP::DB::Shift->new(DB => $self->database);
    my @result = $sdb->getShiftLogs(
        OMP::Query::Shift->new(HASH => {shiftid => $id, private => {any => 1}}));

    return $self->_write_not_found_page('Shift log entry not found.')
        unless @result;
    die 'Multiple entries' if 1 < scalar @result;

    my $comment = $result[0];
    die 'Retrieved entry has wrong ID'
        unless $comment->id == $id;

    if ($q->param('submit_edit')) {
        my $text = $q->param('text');
        $text =~ s/^\s+//s;
        $text =~ s/\s+$//s;
        $comment->text($text);
        $comment->preformatted(0);
        $comment->private((scalar $q->param('private')) ? 1 : 0);

        my $E;
        try {
            $sdb->updateShiftLog($comment);
        }
        otherwise {
            $E = shift;
        };

        if (defined $E) {
            push @messages,
                'Error storing updated shift comment: ' . $E;
        }
        else {
            return $self->_write_redirect(
                sprintf '/cgi-bin/shiftlog.pl?utdate=%s&telescope=%s',
                $comment->date->ymd, $comment->telescope);
        }
    }

    return {
        target => $self->url_absolute(),
        messages => \@messages,
        values => {
            text => OMP::Display->prepare_edit_text($comment),
            author => $comment->author,
            private => $comment->private,
        },
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
            my $query = OMP::Query::Shift->new(HASH => $hash);

            my $sdb = OMP::DB::Shift->new(DB => $self->database);
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
