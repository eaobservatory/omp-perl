#!/local/perl/bin/perl -X

=head1 NAME

ompscheduleimport - Import telescope observing schedule

=head1 SYNOPSIS

    ompscheduleimport --tel JCMT [--dry-run] schedule_21a.csv

=head1 DESCRIPTION

This program imports schedule information into the OMP database,
overwriting any previous information for the given dates.
Only one queue per night (no hourly slots) is supported.

The file must contain the following columns:

=over 4

=item A. Year (4-digit)

=item B. Month (name)

=item C. Date (HST, with "h" prefix if holiday, "s" allowed but ignored)

=item D. IT

=item E. EO

=item F. TSS

=item G. Notes

=item H. Queue (only first word retained)

=back

=head1 OPTIONS

=over 4

=item B<--tel>

Specify the telescope to use.

=back

=cut

use warnings;
use strict;

use Getopt::Long;
use Pod::Usage;
use File::Spec;
use FindBin;
use Term::ReadLine;
use Text::CSV;
use Time::Piece;
use Time::Seconds qw/ONE_DAY/;

BEGIN {
  use constant OMPLIB => "$FindBin::RealBin/../lib";
  use lib OMPLIB;
}

use OMP::SchedDB;
use OMP::DBbackend;
use OMP::Info::Sched::Night;
use OMP::General;

local $| = 1;

my ($tel, $dry_run, $help);
my $status = GetOptions(
    'tel=s' => \$tel,
    'dry-run' => \$dry_run,
    'help' => \$help,
) or pod2usage(1);

pod2usage(-exitstatus => 0, -verbose => 2) if $help;

die 'Telescope not specified' unless defined $tel;
$tel = uc($tel);

# Queues to be renamed to aid in importing old schedules.
our %QUEUE = (
    LARGE => 'LAP',
    EHT => 'VLBI',
    UHFLEX => 'UH',
    EAO => 'PI',
    EA => 'VLBI',
    EAVN => 'VLBI',
    'E&C' => 'EC',
    'STUDIES-SXDS' => 'LAP',
);

my @sched = ();
my %semesters = ();
my $queue_prev = undef;

die 'Please specify one file' unless 1 == scalar @ARGV;
die 'File does not exist' unless -e $ARGV[0];
foreach my $fields (@{Text::CSV::csv(in => $ARGV[0])}) {
    my ($year, $month, $day, $staff_it, $staff_eo, $staff_op, $notes, $queue) = map {s/\x{201c}/"/g; $_} @$fields;

    ($queue, undef) = split ' ', $queue, 2;
    $queue = uc $queue;
    $queue = $queue_prev if $queue eq '"';
    if (exists $QUEUE{$queue}) {
        $queue = $QUEUE{$queue};
    }
    elsif ($queue =~ /^M\d\d[ABXYZW]([PLH])/) {
        if ($1 eq 'P') {$queue = 'PI';}
        elsif ($1 eq 'L') {$queue = 'LAP';}
        elsif ($1 eq 'H') {$queue = 'UH';}
        else {die "Unknown queue code: $1";}
    }
    $queue_prev = $queue;

    my $holiday = !! ($day =~ s/^h//i);
    $day =~ s/^s//i;

    my $date_ut = Time::Piece->strptime("$year $month $day", '%Y %B %d') + ONE_DAY;

    push @sched, new OMP::Info::Sched::Night(
        telescope => $tel,
        date => $date_ut,
        holiday => $holiday,
        queue => _str_or_undef($queue),
        staff_op => _str_or_undef($staff_op),
        staff_eo => _str_or_undef($staff_eo),
        staff_it => _str_or_undef($staff_it),
        notes => _str_or_undef($notes),
        notes_private => 0,
    );

    $semesters{OMP::DateTools->determine_semester(date => $date_ut, tel => $tel)} = 1;
}

foreach my $day (@sched) {
    print "$day\n";
}

print "\nSemester(s): " . join(', ', sort {$a cmp $b} keys %semesters) . "\n\n";

unless ($dry_run) {
    my $term = new Term::ReadLine('ompscheduleimport');
    my $confirm = $term->readline('Import schedule? [y/N] ');

    if ($confirm =~ /^[yY]/) {
        print "\nImporting...";

        my $db = new OMP::SchedDB(DB => new OMP::DBbackend());
        $db->update_schedule(\@sched);

        print " [DONE]\n";
    }
}

sub _str_or_undef {
    my $value = shift;
    return undef if $value eq '';
    return $value;
}
__END__

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
