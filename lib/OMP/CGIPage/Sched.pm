package OMP::CGIPage::Sched;

=head1 NAME

OMP::CGIPage::Sched - Display of complete schedule web pages

=head1 SYNOPSIS

  use OMP::CGIPage::Sched;

=head1 DESCRIPTION

Helper methods for constructing and displaying complete web pages
that display telescope schedules.

=cut

use strict;
use warnings;

use Carp;
use Data::ICal;
use Data::ICal::Entry::Event;
use Time::Piece ':override';
use Time::Seconds qw/ONE_DAY ONE_HOUR/;

use OMP::Error qw/:try/;
use OMP::DateTools;
use OMP::DBbackend;
use OMP::NetTools;
use OMP::SchedDB;
use OMP::Info::Sched::Night;
use OMP::Info::Sched::Slot;

use base qw/OMP::CGIPage/;

$| = 1;

=head1 Routines

=over 4

=item B<staff_sched_view>

Creates the page showing the staff version of the schedule.

=cut

sub staff_sched_view {
    my $self = shift;
    $self->_sched_view(1);
}

=item B<public_sched_view>

Creates the page showing the staff version of the schedule.

=cut

sub public_sched_view {
    my $self = shift;

    $self->_sched_view(0);
}

sub _sched_view {
    my $self = shift;
    my $is_staff = shift;

    my ($tel, $semester, $start, $end) = $self->_sched_view_edit_info();
    my ($semester_next, $semester_prev, @semester_options);
    if ($semester =~ /^(\d\d)([AB])$/) {
        if ($2 eq 'A') {
            $semester_prev = sprintf('%02d%s', $1 - 1, 'B');
            $semester_next = sprintf('%02d%s', $1, 'B');
        }
        else {
            $semester_prev = sprintf('%02d%s', $1, 'A');
            $semester_next = sprintf('%02d%s', $1 + 1, 'A');
        }
    }
    if (OMP::DateTools->determine_semester(tel => $tel) =~ /^(\d\d)([AB])$/) {
        for (my ($year, $suffix) = ($1, $2); $year > 14; ($year, $suffix) = ($suffix eq 'B') ? ($year, 'A') : ($year - 1, 'B')) {
            push @semester_options, sprintf('%02d%s', $year, $suffix);
        }
    }

    my $db = new OMP::SchedDB(DB => new OMP::DBbackend());

    my $sched = $db->get_schedule(tel => $tel, start => $start, end => $end)->nights();
    my $queue_info = $db->get_sched_queue_info(tel => $tel, include_hidden => 1);

    return {
        title => "$tel Schedule $semester",
        schedule => $sched,
        queue_info => $queue_info,
        slot_times => [map {($_->{'time'} + 14 * ONE_HOUR)->strftime('%H:%M')} @{$sched->[0]->slots_full()}],
        is_staff => $is_staff,
        is_edit => 0,
        telescope => $tel,
        semester => $semester,
        semester_next => $semester_next,
        semester_prev => $semester_prev,
        semester_options => \@semester_options,
    };
}

sub _sched_view_edit_info {
    my $self = shift;

    my $tel = $self->decoded_url_param('tel')
        or die 'Telescope not selected';

    my $semester = $self->decoded_url_param('semester');
    if (defined $semester) {
        die 'Semester not in expected format'
            unless $semester =~ /^(\d\d[AB])$/;
        $semester = $1;
    }
    else {
        $semester = OMP::DateTools->determine_semester(tel => $tel);
    }

    my ($start, $end) = OMP::DateTools->semester_boundary(
        tel => $tel, semester => $semester);

    return ($tel, $semester, $start, $end);
}

=item B<sched_edit>

Creates the page containing a form for editing a schedule, and
processes updates to the schedule.  Should redirect back to the schedule
viewing page in the case of successful edit.

=cut

sub sched_edit {
    my $self = shift;

    my ($tel, $semester, $start, $end) = $self->_sched_view_edit_info();

    my $db = new OMP::SchedDB(DB => new OMP::DBbackend());

    my $sched = $db->get_schedule(tel => $tel, start => $start, end => $end)->nights();

    my $q = $self->cgi;

    if ($q->param('submit_save')) {
        # The existing schedule for the given semester will give
        # us lists of dates (and slot times) so that we know which form
        # parameters to read.

        foreach my $day (@$sched) {
            my $date_str = $day->date()->strftime('%Y-%m-%d');

            my $queue = _str_or_undef(scalar $q->param('queue_' . $date_str));
            $day->queue($queue);
            $day->staff_op(_str_or_undef(scalar $q->param('staff_op_' . $date_str)));
            $day->staff_eo(_str_or_undef(scalar $q->param('staff_eo_' . $date_str)));
            $day->staff_it(_str_or_undef(scalar $q->param('staff_it_' . $date_str)));
            $day->notes(_str_or_undef(scalar $q->param('notes_' . $date_str)));
            $day->notes_private((scalar $q->param('notes_private_' . $date_str)) ? 1 : 0);
            $day->holiday((scalar $q->param('holiday_' . $date_str)) ? 1 : 0);

            my @slots = ();
            for my $slot_option (@{$day->slots_full()}) {
                my $slot_queue = _str_or_undef(scalar $q->param(
                    'queue_' . $date_str . $slot_option->{'time'}->strftime('_%H-%M-%S')));
                push @slots, new OMP::Info::Sched::Slot(
                    telescope => $tel,
                    date => $day->date(),
                    time => $slot_option->{'time'},
                    queue => $slot_queue,
                ) if defined $slot_queue
                    and not ((defined $queue) and ($slot_queue eq $queue));
            }
            $day->slots(\@slots);
        }

        $db->update_schedule($sched);

        return $self->_write_redirect("sched.pl?tel=$tel&semester=$semester");
    }

    return {
        title => "Edit $tel Schedule $semester",
        schedule => $sched,
        slot_times => [map {($_->{'time'} + 14 * ONE_HOUR)->strftime('%H:%M')} @{$sched->[0]->slots_full()}],
        queue_info => $db->get_sched_queue_info(tel => $tel),
        is_staff => 1,
        is_edit => 1,
        telescope => $tel,
        semester => $semester,
    };
}

sub sched_view_queue_stats {
    my $self = shift;

    my ($tel, $semester, $start, $end) = $self->_sched_view_edit_info();
    my $db = new OMP::SchedDB(DB => new OMP::DBbackend());

    my $sched = $db->get_schedule(tel => $tel, start => $start, end => $end);
    my $queue_info = $db->get_sched_queue_info(tel => $tel, include_hidden => 1);

    my %queue_night = ();
    my %queue_slot = ();
    my $total_night = 0;
    my $total_slot = 0;

    foreach my $night (@{$sched->nights()}) {
        $queue_night{$night->queue // 'Unassigned'} ++;
        $total_night ++;
        foreach my $slot_info (@{$night->slots_full()}) {
            $queue_slot{$slot_info->{'queue'} // 'Unassigned'} ++;
            $total_slot ++;
        }
    }

    # Create full list of queues present.
    my %queues = ();
    $queues{$_} = 1 foreach keys %queue_night;
    $queues{$_} = 1 foreach keys %queue_slot;

    # Make sure dividing by total will not cause a divide by zero error.
    $total_night = 1 unless $total_night;
    $total_slot = 1 unless $total_slot;

    return {
        title => "$tel Schedule $semester Queue Statistics",
        queues => [sort keys %queues],
        queue_night => \%queue_night,
        queue_slot => \%queue_slot,
        queue_info => $queue_info,
        total_night => $total_night,
        total_slot => $total_slot,
        telescope => $tel,
        semester => $semester,
    };
}

sub sched_cal_list {
    my $self = shift;

    my $tel = $self->decoded_url_param('tel')
        or die 'Telescope not selected';

    my $db = new OMP::SchedDB(DB => new OMP::DBbackend());

    my $cal_list = $db->list_schedule_calendars(tel => $tel);

    return {
        title => "$tel Schedule Calendars",
        telescope => $tel,
        calendars => $cal_list,
        base_url => OMP::Config->getData('omp-url') . OMP::Config->getData('cgidir') . '/schedcal.pl',
    };
}

sub sched_cal_view {
    my $self = shift;

    my $q = $self->cgi;

    my $token = $self->decoded_url_param('token')
        or die 'Access token not specified';

    my $db = new OMP::SchedDB(DB => new OMP::DBbackend());

    my $cal_info = $db->get_schedule_calendar($token);

    die 'Access token not recognized'
        unless defined $cal_info;

    my $cal = _create_calendar(
        $db,
        $cal_info->{'telescope'},
        $cal_info->{'name'},
        $cal_info->{'pattern'},
        $cal_info->{'include_holiday'},
    );

    my $name = lc $cal_info->{'name'};
    $name =~ s/[^0-9a-z]/_/g;

    print $q->header(
        -type => 'text/calendar',
        -attachment => (sprintf 'calendar_%s.ics', $name),
    );

    print $cal;
}

sub _create_calendar {
    my $db = shift;
    my $tel = shift;
    my $queryname = shift;
    my $queryregexp = shift;
    my $include_holiday = shift;

    my $summary_prefix = $tel;
    my $query = qr/$queryregexp/;
    my $now = gmtime()->strftime('%Y%m%dT%H%M%SZ');

    my $uid_query = lc $queryname;
    $uid_query =~ s/[^0-9a-z]/_/g;

    my $semester = OMP::DateTools->determine_semester(tel => $tel);
    my $semester_next;
    if ($semester =~ /^(\d\d)([AB])$/) {
        if ($2 eq 'A') {
            $semester_next = sprintf('%02d%s', $1, 'B');
        }
        else {
            $semester_next = sprintf('%02d%s', $1 + 1, 'A');
        }
    }

    my ($start, $end) = OMP::DateTools->semester_boundary(
        tel => $tel, semester => [$semester, $semester_next]);

    my $sched = $db->get_schedule(tel => $tel, start => $start, end => $end);

    my (undef, $localhost, undef) = OMP::NetTools->determine_host(1);

    my $cal = new Data::ICal(
        calname => (sprintf 'JCMT Calendar - %s', $queryname),
        rfc_strict => 1,
    );

    # List of fields to search, giving the name, accessor method
    # and whether it refers to the previous local date.
    my @items = (
        ['Night', 'staff_op', 0],
        ['Morning', 'staff_eo', 1],
        ['IT', 'staff_it', 0],
    );

    # Assemble hash of nights by "next" date string.  This will allow us to
    # find the previous night object for items which require it.
    my %night_by_next = ();

    foreach my $night (@{$sched->nights}) {
        my $date_next = ($night->date_local + ONE_DAY)->strftime('%Y%m%d');
        $night_by_next{$date_next} = $night;
    }

    # Track previous value of each item, in case of use of dittos
    # on the schedule.
    my %prev = map {$_->[0] => undef} @items;

    foreach my $date_next (sort keys %night_by_next) {
        my $night = $night_by_next{$date_next};
        my $date = $night->date_local->strftime('%Y%m%d');
        my $night_prev = (exists $night_by_next{$date}) ? $night_by_next{$date} : undef;

        if ($include_holiday) {
            if ($night->holiday) {
                my $event = new Data::ICal::Entry::Event();

                $event->add_properties(
                    created => $now,
                    dtend => [$date_next, {VALUE => 'DATE'}],
                    dtstamp => $now,
                    dtstart => [$date, {VALUE => 'DATE'}],
                    summary => (sprintf '%s: %s', $summary_prefix, 'Holiday'),
                    transp => 'TRANSPARENT',
                    uid => (sprintf 'omp-jcmt-%s-hol-%s@%s', $uid_query, $date, $localhost),
                );

                $cal->add_entry($event);
            }
        }

        my @info = ();
        my @desc = ();
        foreach my $item (@items) {
            my ($title, $method, $is_date_prev) = @$item;

            # Look at $night unless this is an entry we get from the
            # previous night, in which case use $night_prev.
            my $item_night = $is_date_prev ? $night_prev : $night;
            next unless defined $item_night;

            my $val = $item_night->$method;
            if (defined $val) {
                # Check for ditto.
                if ($val eq '"') {
                    if (defined $prev{$title}) {
                        $val = $prev{$title};
                    }
                    else {
                        next;
                    }
                }
                else {
                    $prev{$title} = $val;
                }

                if ($val =~ $query) {
                    push @info, $title;
                    push @desc, sprintf '%s: %s', $title, $val;
                }
            }
            else {
                undef $prev{$title};
            }
        }

        next unless scalar @info;
        my $info = join ', ', @info;

        if (defined $night->notes) {
            unshift @desc, $night->notes;
        }
        my $desc = join "\n", @desc;

        my $event = new Data::ICal::Entry::Event();

        $event->add_properties(
            created => $now,
            description => $desc,
            dtend => [$date_next, {VALUE => 'DATE'}],
            dtstamp => $now,
            dtstart => [$date, {VALUE => 'DATE'}],
            summary => (sprintf '%s: %s', $summary_prefix, $info),
            transp => 'TRANSPARENT',
            uid => (sprintf 'omp-jcmt-%s-%s@%s', $uid_query, $date, $localhost),
        );

        $cal->add_entry($event);
    }

    return $cal->as_string;
}

sub _str_or_undef {
    my $value = shift;
    return undef if $value eq '';
    return $value;
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

1;
