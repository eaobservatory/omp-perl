package OMP::Info::Obs::TimeGap;

=head1 NAME

OMP::Info::Obs::TimeGap - Observation sequence timegap information

=head1 SYNOPSIS

    use OMP::Info::Obs::TimeGap;

    $timegap = OMP::Info::Obs::TimeGap->new(%hash);

    @comments = $timegap->comments;

    %nightlog = $timegap->nightlog;

=head1 DESCRIPTION

A way of handling information associated with a time gap between
observations. It includes possible comments and information on the
cause of the time gap.

This class is a subclass of C<OMP::Info::Obs>.

=cut

use 5.006;
use strict;
use Carp;

use OMP::Constants;

use base qw/OMP::Info::Obs/;

our $VERSION = '2.000';

our %status_label = (
    OMP__TIMEGAP_INSTRUMENT() => 'Instrument',
    OMP__TIMEGAP_WEATHER() => 'Weather',
    OMP__TIMEGAP_FAULT() => 'Fault',
    OMP__TIMEGAP_NEXT_PROJECT() => 'Next project',
    OMP__TIMEGAP_PREV_PROJECT() => 'Last project',
    OMP__TIMEGAP_NOT_DRIVER() => 'Observer not a driver',
    OMP__TIMEGAP_SCHEDULED() => 'Scheduled downtime',
    OMP__TIMEGAP_QUEUE_OVERHEAD() => 'Queue overhead',
    OMP__TIMEGAP_LOGISTICS() => 'Logistics',
    OMP__TIMEGAP_UNKNOWN() => 'Unknown',
);

our @status_order = (
    OMP__TIMEGAP_UNKNOWN(),
    OMP__TIMEGAP_INSTRUMENT(),
    OMP__TIMEGAP_WEATHER(),
    OMP__TIMEGAP_FAULT(),
    OMP__TIMEGAP_NEXT_PROJECT(),
    OMP__TIMEGAP_PREV_PROJECT(),
    OMP__TIMEGAP_NOT_DRIVER(),
    OMP__TIMEGAP_SCHEDULED(),
    OMP__TIMEGAP_QUEUE_OVERHEAD(),
    OMP__TIMEGAP_LOGISTICS(),
);

=head1 METHODS

=head2 Accessors

=over 4

=item B<projectid>

Retrieve the project ID.

    $id = $timegap->projectid;

The project ID for C<OMP::Info::Obs::TimeGap> objects will always
be TIMEGAP.

=cut

sub projectid {
    return 'TIMEGAP';
}

=item B<status>

Retrieve or store the status of the timegap.

    $status = $timegap->status;
    $timegap->status($status);

See C<Obs::Constants> for the valid statuses.

=cut

sub status {
    my $self = shift;
    if (@_) {
        my $status = shift;
        $self->{status} = $status;

        my @comments = $self->comments;
        if (defined($comments[0])) {
            $comments[0]->status($status);
            $self->comments(\@comments);
        }
    }

    if (! exists($self->{status})) {
        my @comments = $self->comments;
        if (defined($comments[0])) {
            $self->{status} = $comments[$#comments]->status;
        }
        else {
            $self->{status} = OMP__TIMEGAP_UNKNOWN;
        }
    }

    return $self->{status};
}

=back

=head2 General Methods

=over 4

=item B<nightlog>

Returns a hash containing two strings used to summarize an
C<Obs::TimeGap> object.

    %nightlog = $timegap->nightlog;

The hash contains {_STRING => string} and {_STRING_LONG} key-value
pairs that give a summary of the time gap, including any comments
that may be associated with that time gap.

=cut

sub nightlog {
    my $self = shift;

    my %return;

    $return{'UT'} = defined($self->startobs) ? $self->startobs->hms : '';

    $return{'_STRING'} = $return{'_STRING_LONG'} = "Time gap: ";

    if (exists $status_label{$self->status}) {
        $return{'_STRING'} = $return{'_STRING_LONG'} .= uc $status_label{$self->status};
    }
    else {
        $return{'_STRING'} = $return{'_STRING_LONG'} .= 'UNKNOWN';
    }

    my $length = $self->endobs - $self->startobs + 1;
    $return{'_STRING'} = $return{'_STRING_LONG'} .= sprintf("  Length: %s", $length->pretty_print);

    foreach my $comment ($self->comments) {
        if (defined $comment) {
            if (exists $return{'_STRING'}) {
                $return{'_STRING'} .= sprintf "\n %19s UT / %s: %-50s",
                    $comment->date->ymd . ' ' . $comment->date->hms,
                    $comment->author->name,
                    $comment->text;
            }
            if (exists $return{'_STRING_LONG'}) {
                $return{'_STRING_LONG'} .= sprintf "\n %19s UT / %s: %-50s",
                    $comment->date->ymd . ' ' . $comment->date->hms,
                    $comment->author->name,
                    $comment->text;
            }
        }
    }

    return %return;
}

=item B<summary>

Summarize the object in a variety of formats.

    $summary = $timegap->summary('80col');

Allowed formats are:

=over 4

=item 72col

72-column summary, with comments.

=back

=cut

sub summary {
    my $self = shift;

    my $format = lc shift;

    if (($format eq '72col') or ($format eq 'text')) {
        my $obssum = "Time gap: ";

        if (exists $status_label{$self->status}) {
            $obssum .= uc $status_label{$self->status};
        }
        else {
            $obssum .= 'UNKNOWN';
        }

        my $length = $self->endobs - $self->startobs;
        $obssum .= sprintf "  Length: %s\n", $length->pretty_print;

        my $commentsum;
        foreach my $comment ($self->comments) {
            if (defined($comment)) {
                my $tc = sprintf "%19s UT / %s: %s\n",
                    $comment->date->ymd . " " . $comment->date->hms,
                    $comment->author->name, $comment->text;

                $commentsum .= OMP::Display->wrap_text($tc, 72, 1);
            }
        }
        if (wantarray) {
            return ($obssum, $commentsum);
        }
        else {
            return $obssum . $commentsum;
        }
    }
    else {
        throw OMP::Error::BadArgs(
            "Format $format not yet implemented for Info::Obs::TimeGap objects");
    }
}

=item B<uniqueid>

Returns a unique ID for the object.

    $id = $object->uniqueid;

This method is subclassed for the C<OMP::Info::Obs::TimeGap> class because
TimeGap dates are stored in the database using (endobs - 1), versus
startobs for regular C<OMP::Info::Obs> objects.

=cut

sub uniqueid {
    my $self = shift;

    return if ! defined($self->runnr)
        || ! defined($self->instrument)
        || ! defined($self->telescope)
        || ! defined($self->endobs);

    return $self->runnr
        . $self->instrument
        . $self->telescope
        . $self->endobs->ymd
        . sprintf('%02d', $self->endobs->hour) . ':'
        . sprintf('%02d', $self->endobs->minute) . ':'
        . sprintf('%02d', ($self->endobs->second - 1));
}

1;

__END__

=back

=head1 SEE ALSO

L<OMP::Info::Obs>

=head1 AUTHORS

Brad Cavanagh E<lt>b.cavanagh@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut
