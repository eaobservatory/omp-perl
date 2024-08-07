package OMP::DB::Sched;

=head1 NAME

OMP::DB::Sched - Manipulate the telescope schedule database tables

=cut

use strict;

use Time::Piece;
use Time::Seconds qw/ONE_DAY/;

use OMP::Info::Sched;
use OMP::Info::Sched::Night;
use OMP::Info::Sched::Slot;

use base qw/OMP::DB/;

# Database tables relating to telescope schedules.
our $SCHEDTABLE = 'ompsched';
our $SCHEDSLOTTABLE = 'ompschedslot';
our $SCHEDQUEUETABLE = 'ompschedqueue';
our $SCHEDCALTABLE = 'ompschedcal';

=head1 METHODS

=over 4

=item get_sched_queue_info

Fetch information about queues defined for a given telescope's schedule.

    my $queue_info = $db->get_sched_queue_info(tel => 'JCMT');

=cut

sub get_sched_queue_info {
    my $self = shift;
    my %opt = @_;

    my $tel = $opt{'tel'} or die 'Telescope not specified';

    my $results = $self->_db_retrieve_data_ashash(
        'SELECT * FROM ' . $SCHEDQUEUETABLE
        . ' WHERE telescope=?'
        . ($opt{'include_hidden'} ? '' : ' AND NOT hidden'),
        $tel);

    my %queues;

    foreach my $row (@$results) {
        $queues{$row->{'queue'}} = $row;
    }

    return \%queues;
}

=item get_schedule

Retrieve a telescope schedule for the given date range.

The date range can either be specified as 'start' and 'end', or for a single
(UT) date, with 'date'.  These values should be Time::Piece objects.

    my $sched = $db->get_schedule(
        tel => 'JCMT',
        start => Time::Piece->strptime('2020-06-10', '%Y-%m-%d'),
        end => Time::Piece->strptime('2020-06-15', '%Y-%m-%d'));

=cut

sub get_schedule {
    my $self = shift;
    my %opt = @_;

    my $tel = $opt{'tel'} or die 'Telescope not specified';

    my ($start, $end);
    if ((exists $opt{'date'}) and (defined $opt{'date'})) {
        $start = $end = $opt{'date'};
    }
    elsif ((exists $opt{'start'}) and (defined $opt{'start'})
            and (exists $opt{'end'}) and (defined $opt{'end'})) {
        $start = $opt{'start'};
        $end = $opt{'end'};
    }
    else {
        die 'Neither date nor start and end specified';
    }

    # Fetch the SCHEDTABLE results for one extra night so that
    # the holiday_next field can be filled in.
    my $end_next = $end + ONE_DAY;

    my $result_days = $self->_db_retrieve_data_ashash(
        'SELECT * FROM ' . $SCHEDTABLE
        . ' WHERE telescope=? AND `date` BETWEEN ? AND ?',
        $tel, $start->strftime('%Y-%m-%d'), $end_next->strftime('%Y-%m-%d'));

    my $result_slots = $self->_db_retrieve_data_ashash(
        'SELECT * FROM ' . $SCHEDSLOTTABLE
        . ' WHERE telescope=? AND `date` BETWEEN ? AND ?'
        . ' ORDER BY `time` ASC',
        $tel, $start->strftime('%Y-%m-%d'), $end->strftime('%Y-%m-%d'));

    my %days;
    foreach my $day (@$result_days) {
        $days{$day->{'date'}} = {%$day,
            date => Time::Piece->strptime($day->{'date'}, '%Y-%m-%d')};
    }
    my %slots;
    foreach my $slot (@$result_slots) {
        push @{$slots{$slot->{'date'}}}, {%$slot,
            date => Time::Piece->strptime($slot->{'date'}, '%Y-%m-%d'),
            time => Time::Piece->strptime($slot->{'time'}, '%H:%M:%S')};
    }

    my @schedule;

    for (my $date = $start; $date <= $end; $date += ONE_DAY) {
        my $datestr = $date->strftime('%Y-%m-%d');
        my $datestr_next = ($date + ONE_DAY)->strftime('%Y-%m-%d');
        my $info;
        unless (exists $days{$datestr}) {
            $info = OMP::Info::Sched::Night->new(
                telescope => $tel, date => $date);
        }
        else {
            $info = OMP::Info::Sched::Night->new(%{$days{$datestr}});
            if (exists $days{$datestr_next}) {
                $info->holiday_next($days{$datestr_next}->{'holiday'});
            }

            if (exists $slots{$datestr}) {
                my @slots;
                foreach my $slot (@{$slots{$datestr}}) {
                    push @slots, OMP::Info::Sched::Slot->new(%$slot);
                }

                $info->slots(\@slots);
            }
        }
        push @schedule, $info;
    }

    return OMP::Info::Sched->new(nights => \@schedule);
}

=item update_schedule

Update the schedule table with new and/or updated records.  Requires a
reference to an array of C<OMP::Info::Sched::Night> objects.

    $db->update_schedule(\@sched);

=cut

sub update_schedule {
    my $self = shift;
    my $sched = shift;

    die 'Not an array reference' unless 'ARRAY' eq ref $sched;

    my $dbh = $self->_dbhandle();
    my $sth_sched = $dbh->prepare(
        'INSERT INTO `' . $SCHEDTABLE . '`'
        . ' (`telescope`, `date`, `holiday`, `queue`'
        . ', `staff_op`, `staff_eo`, `staff_it`, `staff_po`, `notes`, `notes_private`)'
        . ' VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
        . ' ON DUPLICATE KEY UPDATE'
        . ' `holiday`=?, `queue`=?, `staff_op`=?'
        . ', `staff_eo`=?, `staff_it`=?, `staff_po`=?, `notes`=?, `notes_private`=?');
    my $sth_slot_del = $dbh->prepare(
        'DELETE FROM `'. $SCHEDSLOTTABLE . '`'
        . ' WHERE `telescope`=? AND `date`=?');
    my $sth_slot_ins = $dbh->prepare(
        'INSERT INTO `' . $SCHEDSLOTTABLE . '`'
        . ' (`telescope`, `date`, `time`, `queue`)'
        . ' VALUES (?, ?, ?, ?)');


    # Start transaction.
    $self->_db_begin_trans();
    $self->_dblock();

    # Insert / update entries.
    foreach my $day (@$sched) {
        my @key = ($day->telescope(), $day->date()->strftime('%Y-%m-%d'));
        my @val = ($day->holiday(), $day->queue(), $day->staff_op(),
            $day->staff_eo(), $day->staff_it(), $day->staff_po(),
            $day->notes(), $day->notes_private());
        $sth_sched->execute(@key, @val, @val)
            or throw OMP::Error::DBError("Error inserting/updating table $SCHEDTABLE: $DBI::errstr");

        $sth_slot_del->execute(@key)
            or throw OMP::Error::DBError("Error deleting from table $SCHEDSLOTTABLE: $DBI::errstr");

        foreach my $slot (@{$day->slots()}) {
            my @val_slot = ($slot->time()->strftime('%H:%M:%S'), $slot->queue());
            $sth_slot_ins->execute(@key, @val_slot)
                or throw OMP::Error::DBError("Error inserting into table $SCHEDSLOTTABLE: $DBI::errstr");
        }
    }

    # End transaction.
    $self->_dbunlock();
    $self->_db_commit_trans();
}

=item get_schedule_calendar

Retrieve a telescope schedule calendar configuration by token.

    my $cal_info = $db->get_schedule_calendar($token);

=cut

sub get_schedule_calendar {
    my $self = shift;
    my $token = shift;

    my $result = $self->_db_retrieve_data_ashash(
        'SELECT * FROM ' . $SCHEDCALTABLE . ' WHERE token=?',
        $token);

    return undef unless 1 == scalar @$result;
    return $result->[0];
}

=item list_schedule_calendars

Retrieve all telescope schedule calendar configurations.

    my $cal_list = $db->list_schedule_calendars(tel => $tel);

=cut

sub list_schedule_calendars {
    my $self = shift;
    my %opt = @_;

    my $tel = $opt{'tel'} or die 'Telescope not specified';

    return $self->_db_retrieve_data_ashash(
        'SELECT * FROM ' . $SCHEDCALTABLE . ' WHERE telescope=?'
        . ' ORDER BY name ASC',
        $tel);
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
