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
use OMP::Info::Comment;
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

    my $selected_order = (scalar $q->param('order')) // 'ascending';

    # Split the combined "status" parameter into status and type.
    my $status_type = $q->param('status');
    my $selected_status = ($status_type =~ /^status:(\d+)$/aa) ? $1 : undef;
    my $selected_type = ($status_type =~ /^type:(\d+)$/aa) ? $1 : undef;

    my %options = (
        order => $selected_order,
    );

    if (defined $selected_type) {
        # In principle we should constrain "status" here to exclude
        # OMP__FB_DELETE, but it appears this value has never been used.
        $options{'msgtype'} = $selected_type;
        $options{'status'} = undef;  # Remove 'getComments' default constraint.
    }
    else {
        # Status values are listed in descending priority order, so go through
        # the list, accumulating status values to include, until we find that specified.
        my @status;
        foreach my $info (@{OMP::Info::Comment->get_fb_status_options}) {
            push @status, $info->[0];
            last if (not defined $selected_status)
                or ($selected_status == $info->[0]);
        }
        $options{'status'} = \@status;
    }

    my $fdb = OMP::DB::Feedback->new(ProjectID => $projectid, DB => $self->database);
    my $comments = $fdb->getComments(%options);

    return {
        comments => $comments,
        orders => [map {[(lc $_) => $_]} qw/Ascending Descending/],
        statuses => OMP::Info::Comment->get_fb_status_options,
        types => OMP::Info::Comment->get_fb_type_options,
        selected_order => $selected_order,
        selected_status => $selected_status,
        selected_type => $selected_type,
    };
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
