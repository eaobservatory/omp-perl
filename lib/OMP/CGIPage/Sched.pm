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
use Time::Seconds qw/ONE_DAY ONE_HOUR/;

use OMP::CGIDBHelper;
use OMP::Error qw/:try/;
use OMP::DateTools;
use OMP::DBbackend;
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

    $self->render_template('sched_view_edit.html', {
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
    });
}

sub _sched_view_edit_info {
    my $self = shift;

    my $q = $self->cgi;

    my $tel = $q->url_param('tel')
        or die 'Telescope not selected';

    my $semester = $q->url_param('semester');
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

=item B<sched_edit_content>

Creates the page containing a form for editing a schedule.

=cut

sub sched_edit_content {
    my $self = shift;

    my ($tel, $semester, $start, $end) = $self->_sched_view_edit_info();

    my $db = new OMP::SchedDB(DB => new OMP::DBbackend());

    my $sched = $db->get_schedule(tel => $tel, start => $start, end => $end)->nights();
    my $queue_info = $db->get_sched_queue_info(tel => $tel);

    $self->render_template('sched_view_edit.html', {
        title => "Edit $tel Schedule $semester",
        schedule => $sched,
        slot_times => [map {($_->{'time'} + 14 * ONE_HOUR)->strftime('%H:%M')} @{$sched->[0]->slots_full()}],
        queue_info => $queue_info,
        is_staff => 1,
        is_edit => 1,
        telescope => $tel,
        semester => $semester,
    });
}

=item B<sched_edit_output>

Processes updated to the schedule.  Should redirect back to the schedule
viewing page if successful.

=cut

sub sched_edit_output {
    my $self = shift;

    my $q = $self->cgi;

    my ($tel, $semester, $start, $end) = $self->_sched_view_edit_info();

    # Fetch the existing schedule for the given semester: this will give
    # us lists of dates (and slot times) so that we know which form
    # parameters to read.
    my $db = new OMP::SchedDB(DB => new OMP::DBbackend());

    my $sched = $db->get_schedule(tel => $tel, start => $start, end => $end)->nights();

    foreach my $day (@$sched) {
        my $date_str = $day->date()->strftime('%Y-%m-%d');

        my $queue = _str_or_undef($q->param('queue_' . $date_str));
        $day->queue($queue);
        $day->staff_op(_str_or_undef($q->param('staff_op_' . $date_str)));
        $day->staff_eo(_str_or_undef($q->param('staff_eo_' . $date_str)));
        $day->staff_it(_str_or_undef($q->param('staff_it_' . $date_str)));
        $day->notes(_str_or_undef($q->param('notes_' . $date_str)));
        $day->notes_private($q->param('notes_private_' . $date_str) ? 1 : 0);
        $day->holiday($q->param('holiday_' . $date_str) ? 1 : 0);

        my @slots = ();
        for my $slot_option (@{$day->slots_full()}) {
            my $slot_queue = _str_or_undef($q->param(
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

    print $q->redirect("sched.pl?tel=$tel&semester=$semester");
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
