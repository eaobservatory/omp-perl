package OMP::CGIComponent::Feedback;

=head1 NAME

OMP::CGIComponent::Feedback - Web display of feedback system comments

=head1 SYNOPSIS

    use OMP::CGIComponent::Feedback;

    $entries = OMP::CGIComponent::Feedback::fb_entries;

=head1 DESCRIPTION

Helper methods for creating web pages that display feedback
comments.

=cut

use 5.006;
use strict;
use warnings;
use Carp;

use OMP::Constants qw/:fb/;
use OMP::Error qw/:try/;
use OMP::DB::Feedback;
use OMP::NetTools;

use base qw/OMP::CGIComponent/;

=head1 Routines

=over 4

=item B<fb_entries>

Display feedback comments

    $comp->fb_entries($projectid);

=cut

sub fb_entries {
    my $self = shift;
    my $projectid = shift;

    my $q = $self->cgi;

    my $status = [OMP__FB_IMPORTANT];

    my $selected_status = $q->param("status");
    if (defined $selected_status) {
        my %status;
        $status{&OMP__FB_IMPORTANT} = [OMP__FB_IMPORTANT];
        $status{&OMP__FB_INFO} = [OMP__FB_IMPORTANT, OMP__FB_INFO];
        $status{&OMP__FB_SUPPORT} = [OMP__FB_IMPORTANT, OMP__FB_INFO, OMP__FB_SUPPORT];
        $status{&OMP__FB_HIDDEN} = [OMP__FB_IMPORTANT, OMP__FB_INFO, OMP__FB_HIDDEN, OMP__FB_SUPPORT];

        $status = $status{$selected_status};
    }

    my $order = (scalar $q->param("order")) // 'ascending';

    my $fdb = OMP::DB::Feedback->new(ProjectID => $projectid, DB => $self->database);
    my $comments = $fdb->getComments(status => $status, order => $order);

    return {
        comments => $comments,
        orders => [qw/ascending descending/],
        statuses => [
            [OMP__FB_IMPORTANT() => 'important'],
            [OMP__FB_INFO() => 'info'],
            [OMP__FB_SUPPORT() => 'support'],
            [OMP__FB_HIDDEN() => 'hidden'],
        ],
        selected_status => $selected_status,
        selected_order => $order,
        };
}

=item B<fb_entries_count>

Return the number of comments.

    my $num_comments = $comp->fb_entries_count($projectid);

=cut

sub fb_entries_count {
    my $self = shift;
    my $projectid = shift;

    my $fdb = OMP::DB::Feedback->new(ProjectID => $projectid, DB => $self->database);
    my $comments = $fdb->getComments(
        status => [
            OMP__FB_IMPORTANT,
            OMP__FB_INFO,
            OMP__FB_SUPPORT,
            OMP__FB_HIDDEN,
    ]);
    return scalar @$comments;
}

=item B<submit_fb_comment>

Submit a feedback comment

    $comp->submit_fb_comment($projectid);

=cut

sub submit_fb_comment {
    my $self = shift;
    my $projectid = shift;

    my $q = $self->cgi;

   # Get the address of the machine remotely running this cgi script to be given
    # to the addComment method as the sourceinfo param
    (undef, my $host, undef) = OMP::NetTools->determine_host;

    my $comment = {
        author => $self->auth->user,
        subject => scalar $q->param('subject'),
        sourceinfo => $host,
        text => scalar $q->param('text'),
        program => $q->url(-relative => 1),    # the name of the cgi script
        status => OMP__FB_IMPORTANT,
    };

    my $fdb = OMP::DB::Feedback->new(ProjectID => $projectid, DB => $self->database);

    my @messages;
    try {
        $fdb->addComment($comment);
        push @messages, 'Your comment has been submitted.';

    }
    otherwise {
        my $E = shift;
        push @messages,
            'An error has prevented your comment from being submitted:',
            "$E";
    };

    return {
        messages => \@messages,
    };
}

1;

__END__

=back

=head1 SEE ALSO

C<OMP::CGI::FeedbackPage>

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
