package OMP::Info::Sched::Night;

=head1 Name

OMP::Info::Sched::Night - Information about one night in a telescope schedule

=cut

use warnings;
use strict;
use Carp;

use Time::Piece;
use Time::Seconds qw/ONE_DAY ONE_HOUR/;

use OMP::Info::Sched::Slot;

use base qw/OMP::Info/;

our $TIME_START = Time::Piece->strptime('05:00', '%H:%M');
our $TIME_END = Time::Piece->strptime('16:00', '%H:%M');
our $TIME_INC = ONE_HOUR;

use overload '""' => 'stringify';

__PACKAGE__->CreateAccessors(
    telescope => '$',
    date => 'Time::Piece',
    holiday => '$',
    holiday_next => '$',
    queue => '$',
    staff_op => '$',
    staff_eo => '$',
    staff_it => '$',
    staff_po => '$',
    notes => '$',
    notes_private => '$',
    slots => '@OMP::Info::Sched::Slot',
);

=head1 Methods

=over 4

=item B<date_local>

Return the date in the local time zone.

=cut

sub date_local {
    my $self = shift;

    return $self->{'date'} - ONE_DAY;
}

=item B<date_local_next>

Return the next date in the local time zone.

=cut

sub date_local_next {
    my $self = shift;

    return $self->date_local + ONE_DAY;
}

=item B<date_next>

Return the next date.

=cut

sub date_next {
    my $self = shift;

    return $self->{'date'} + ONE_DAY;
}

=item B<slots_merged>

Return a list of "merged" schedule slots.  Each entry is a hash
containing the "queue" and a "num" value indicating how many
consecutive slots are of that queue.

=cut

sub slots_merged {
    my $self = shift;

    my $slots = $self->slots_full();
    my $slot_first = shift @$slots;
    my @result = ($self->_slot_merged_info($slot_first));

    for my $slot (@$slots) {
        if (((not defined $result[-1]->{'queue'})
                    and (not defined $slot->{'queue'}))
                or ((defined $result[-1]->{'queue'})
                    and (defined $slot->{'queue'})
                    and ($result[-1]->{'queue'} eq $slot->{'queue'}))
            ) {
            $result[-1]->{'num'} ++;
            $result[-1]->{'time_last'} = $slot->{'time'};
        }
        else {
            push @result, $self->_slot_merged_info($slot);
        }
    }

    return \@result;
}

sub _slot_merged_info {
    my $self = shift;
    my $slot = shift;
    return {
        queue => $slot->{'queue'},
        num => 1,
        time_first => $slot->{'time'},
        time_last => undef,
    };
}

=item B<slots_full>

Generate a complete list of schedule slots.

This works by iterating between the times specified in the
variables C<TIME_START>, C<TIME_END> and C<TIME_INC>.
If a time is matched by an entry in our C<slots> list,
the a slot will be included with its queue.  Otherwise
a slot will be included using the queue specified by
our C<queue> parameter.

=cut

sub slots_full {
    my $self = shift;

    my $queue_default = $self->queue();

    my %slots;
    for my $slot (@{$self->slots()}) {
        my $timestr = $slot->{'time'}->strftime('%H:%M:%S');
        $slots{$timestr} = $slot;
    }

    my @result = ();

    my $time = $TIME_START;
    my $time_end = $TIME_END;
    $time_end += ONE_DAY if $time_end < $time;

    for (; $time <= $time_end; $time += $TIME_INC) {
        my $timestr = $time->strftime('%H:%M:%S');
        push @result, {
            time => $time,
            queue => ((exists $slots{$timestr})
                ? $slots{$timestr}->{'queue'}
                : $queue_default),
        };
    }

    return \@result;
}

=item B<stringify>

Convert the object to a string.

=cut

sub stringify {
    my $self = shift;
    return $self->date_local()->strftime('%Y-%m-%d')
        . ($self->holiday() ? ' H ' : ($self->date_local()->day_of_week =~ /[06]/ ? ' S ' : '   '))
        . sprintf(
            '%-10.10s %-10.10s %-10.10s %-20.20s',
            ($self->staff_po() // '--'),
            ($self->staff_op() // '--'),
            ($self->staff_eo() // '--'),
            ($self->notes() // ''),
        )
        . ' ' . ((defined $self->queue()) ? $self->queue() : '??')
        . ' ['
        . ((defined $self->slots()) ? (join ' ', map {$_->stringify()} @{$self->slots()}) : '--')
        . ']';
}

1;

__END__

=back

=head1 COPYRIGHT

Copyright (C) 2021 East Asian Observatory
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
