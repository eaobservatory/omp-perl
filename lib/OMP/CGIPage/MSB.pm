package OMP::CGIPage::MSB;

=head1 NAME

OMP::CGIPage::MSB - Display of complete MSB web pages

=head1 SYNOPSIS

    use OMP::CGIPage::MSB;

=head1 DESCRIPTION

Helper methods for constructing and displaying complete web pages
that display MSB comments and general MSB information.

=cut

use 5.006;
use strict;
use warnings;
use Carp;

use Time::Seconds;

use OMP::CGIComponent::Feedback;
use OMP::CGIComponent::MSB;
use OMP::CGIComponent::Project;
use OMP::Constants qw/:fb :done :msb/;
use OMP::DB::MSB;
use OMP::DB::MSBDone;
use OMP::Error qw/:try/;
use OMP::DateTools;
use OMP::DB::Project;

use base qw/OMP::CGIPage/;

=head1 Routines

=over 4

=item B<fb_msb_output>

Creates the page showing the project summary (lists MSBs).
Also creates and parses form for adding an MSB comment.
Hides feedback entries.

    $page->fb_msb_output($projectid);

=cut

sub fb_msb_output {
    my $self = shift;
    my $projectid = shift;

    my $q = $self->cgi;

    my $fbcomp = OMP::CGIComponent::Feedback->new(page => $self);

    my $msbdb = OMP::DB::MSB->new(DB => $self->database, ProjectID => $projectid);
    my $msbdonedb = OMP::DB::MSBDone->new(DB => $self->database, ProjectID => $projectid);

    my $checksum = undef;
    my $prog_info = undef;
    my @messages = ();

    if ($q->param("submit_add_comment")) {
        $checksum = $q->param('checksum');
    }
    elsif ($q->param("submit_msb_comment")) {
        my $error = undef;

        try {
            # Create the comment object
            my $comment = OMP::Info::Comment->new(
                author => $self->auth->user,
                text => scalar $q->param('comment'),
                status => OMP__DONE_COMMENT,
            );
            $msbdonedb->addMSBcomment((scalar $q->param('checksum')), $comment);
            push @messages, 'MSB comment successfully submitted.';
        }
        catch OMP::Error::MSBMissing with {
            $error = "MSB not found in database.";
        }
        otherwise {
            my $E = shift;
            $error = "An error occurred while attempting to submit the comment: $E";
        };

        return $self->_write_error($error) if defined $error;
    }
    else {
        $prog_info = $msbdb->getSciProgInfo(with_observations => 1);
    }

    return {
        project => OMP::DB::Project->new(DB => $self->database, ProjectID => $projectid)->projectDetails(),
        target => $self->url_absolute(),
        prog_info => $prog_info,
        comment_msb_checksum => $checksum,
        is_staff => (!! $self->auth->is_staff),
        messages => \@messages,
        pretty_print_seconds => sub {
            return Time::Seconds->new($_[0])->pretty_print;
        },
        timestamp_as_utc => sub {
            return sprintf "%s UTC", scalar gmtime($_[0]);
        },
    };
}

=item B<msb_hist>

Create a page with a summary of MSBs and their associated comments

    $page->msb_hist($projectid);

=cut

sub msb_hist {
    my $self = shift;
    my $projectid = shift;

    my $q = $self->cgi;
    my $comp = OMP::CGIComponent::MSB->new(page => $self);
    my $projcomp = OMP::CGIComponent::Project->new(page => $self);

    # Perform any actions on the MSB.
    my $response = $comp->msb_action(projectid => $projectid);
    my $errors = $response->{'errors'};
    my $messages = $response->{'messages'};
    return $self->_write_error(@$errors) if scalar @$errors;

    my $show = $q->param('show') // 'all';
    my $comment_msb_id_fields = undef;
    my $msb_info;

    if ($q->param("submit_add_comment")) {
        $comment_msb_id_fields = {
            checksum => scalar $q->param('checksum'),
            transaction => scalar $q->param('transaction'),
        };
    }
    else {
        my $msbdb = OMP::DB::MSB->new(DB => $self->database, ProjectID => $projectid);
        my $donedb = OMP::DB::MSBDone->new(DB => $self->database, ProjectID => $projectid);

        # Get the science program info (if available)
        my $sp = $msbdb->getSciProgInfo();

        my $commentref;
        if ($show =~ /observed/) {
            # show observed
            $commentref = $donedb->observedMSBs(
                projectid => $projectid,
                comments => 1,
            );
        }
        else {
            # show current
            $commentref = $donedb->historyMSB(undef);

            if ($show =~ /current/) {
                $commentref = [grep {$sp->existsMSB($_->checksum)} @$commentref]
                    if defined $sp;
            }
        }

        $msb_info = $comp->msb_comments($commentref, $sp);
    }

    return {
        target => $self->url_absolute(),
        target_base => $q->url(-absolute => 1),
        project => OMP::DB::Project->new(DB => $self->database, ProjectID => $projectid)->projectDetails(),
        msb_info => $msb_info,
        values => {
            show => $show,
        },
        comment_msb_id_fields => $comment_msb_id_fields,
        messages => $messages,
    };
}

=item B<observed>

Create an MSB comment page for private use with a comment submission form.

    $page->observed();

=cut

sub observed {
    my $self = shift;

    my $q = $self->cgi;
    my $comp = OMP::CGIComponent::MSB->new(page => $self);

    my $projdb = OMP::DB::Project->new(DB => $self->database);

    die 'Invalid telescope'
        unless $self->decoded_url_param('telescope') =~ /^([\w]+)$/a;
    my $telescope = $1;
    my $utdatestr = $self->decoded_url_param('utdate');
    my $utdate = (defined $utdatestr)
        ? OMP::DateTools->parse_date($utdatestr)
        : OMP::DateTools->today(1);
    die 'Invalid date' unless defined $utdate;

    my $comment_msb_id_fields = undef;
    my $projects = undef;

    # Perform any actions on the MSB.
    my $response = $comp->msb_action();
    my $errors = $response->{'errors'};
    my $messages = $response->{'messages'};
    return $self->_write_error(@$errors) if scalar @$errors;

    if ($q->param("submit_add_comment")) {
        $comment_msb_id_fields = {
            checksum => scalar $q->param('checksum'),
            transaction => scalar $q->param('transaction'),
            projectid => scalar $q->param('projectid'),
        };
    }
    else {
        my $commentref = OMP::DB::MSBDone->new(DB => $self->database)->observedMSBs(
            date => $utdate->ymd,
            comments => 1,
        );

        # Now keep only the comments that are for the telescope we want
        # to see observed msbs for
        my %sorted;
        for my $msb (@$commentref) {
            my @instruments = split /\W/, $msb->instrument;
            next unless $telescope
                eq uc OMP::Config->inferTelescope('instruments', @instruments);

            my $projectid = $msb->projectid;
            push @{$sorted{$projectid}}, $msb;
        }

        my $project_info = OMP::DB::MSB->new(
            DB => $self->database)->getSciProgInfoMultiple([keys %sorted]);

        $projects = [map {
            my $projectid = $_;
            {
                project_id => $projectid,
                msb_info => $comp->msb_comments(
                    $sorted{$projectid},
                    $project_info->{$projectid}),
            };
        } sort keys %sorted];
    }

    $self->_sidebar_night($telescope, $utdate);

    return {
        target => $self->url_absolute(),
        target_base => $q->url(-absolute => 1),
        values => {
            telescope => $telescope,
            utdate => $utdate,
        },
        comment_msb_id_fields => $comment_msb_id_fields,
        projects => $projects,
        messages => $messages,
    };
}

1;

__END__

=back

=head1 SEE ALSO

C<OMP::CGIComponent::MSB>, C<OMP::CGIComponent::Feedback>,
C<OMP::CGIComponent::Project>

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
