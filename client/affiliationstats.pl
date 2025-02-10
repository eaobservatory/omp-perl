#!/local/perl/bin/perl

=head1 NAME

affiliationstats - Generate observing statistics by affiliation

=head1 SYNOPSIS

    client/affiliationstats.pl --telescope TELESCOPE --semester SEMESTER [--store] [--bydate]

=head1 DESCRIPTION

Displays observing statistics by affiliation for a given semester.

=head1 OPTIONS

=over 4

=item B<--telescope>

Telescope name.

=item B<--semester>

Semester.

=item B<--store>

The hours observed are written into the OMP affiliation allocation table.

=item B<--bydate>

Queries for all time accounting records in the date range of the given
semester.  Otherwise queries for the status of projects currently assigned
to the given semester.

=back

=cut

use strict;

use FindBin;
use File::Spec;
use Getopt::Long;
use Pod::Usage;

use constant OMPLIB => "$FindBin::RealBin/../lib";

BEGIN {
    $ENV{'OMP_CFG_DIR'} = File::Spec->catdir(OMPLIB, '../cfg')
        unless exists $ENV{'OMP_CFG_DIR'};
}

use lib OMPLIB;

use OMP::DB::Backend;
use OMP::DB::Project;
use OMP::DB::TimeAcct;
use OMP::DateTools;
use OMP::Error qw/:try/;
use OMP::Query::Project;
use OMP::Query::TimeAcct;
use OMP::DB::ProjAffiliation qw/%AFFILIATION_NAMES/;

my ($telescope, $semester, $store_to_database, $query_by_date);
my $status = GetOptions(
    'telescope=s' => \$telescope,
    'semester=s' => \$semester,
    'store' => \$store_to_database,
    'bydate' => \$query_by_date,
) or pod2usage(1);

$telescope = uc($telescope) or die 'Telescope not specified';
$semester = uc($semester) or die 'Semester not specified';

my $db = OMP::DB::Backend->new;
my $project_db = OMP::DB::Project->new(DB => $db);
my $affiliation_db = OMP::DB::ProjAffiliation->new(DB => $db);
my $timeacct_db = OMP::DB::TimeAcct->new(DB => $db);

my $allocations = $affiliation_db->get_all_affiliation_allocations($telescope);

my @semester_projects;
my @projects;
my %affiliations;
my $total = 0.0;

unless ($query_by_date) {
    # Original query method: all projects matching the given semester.

    foreach my $project (@{$project_db->listProjects(
            OMP::Query::Project->new(HASH => {
                telescope => $telescope,
                semester => $semester,
            }))}) {
        my $observed = ($project->allocated()
            + $project->pending()
            - $project->remaining()) / 3600.0;

        next unless $observed;

        push @semester_projects, [
            $project->projectid(),
            $observed,
            $project->pi()->name(),
        ];
    }
}
else {
    # Alternative query method: all time accounting records for dates
    # in the given semester.

    my ($date_start, $date_end) = OMP::DateTools->semester_boundary(
        semester => $semester, tel => $telescope);

    # Note: $date_end has last date in semester with time 00:00:00.  We then
    # search for time accounting records with date <= this value.  However
    # we should currently get the correct records as the all appear to have
    # time 00:00:00 in them.
    my $query = OMP::Query::TimeAcct->new(HASH => {
        date => {min => $date_start, max => $date_end},
    });

    my %project_records;

    foreach my $record ($timeacct_db->queryTimeSpent($query)) {
        push @{$project_records{$record->projectid}}, $record;
    }

    while (my ($project_id, $records) = each %project_records) {
        next if $project_id =~ /CAL$/;

        $project_db->projectid($project_id);
        my $project;
        try {
            $project = $project_db->projectDetails();
        }
        otherwise {
        };
        next unless (defined $project)
            and $project->telescope eq $telescope
            and $project->primaryqueue ne 'LAP';

        my $observed = 0.0;

        foreach my $record (@$records) {
            # Include confirmed and pending.
            $observed +=$record->timespent->hours;
        }

        next unless $observed;

        push @semester_projects, [
            $project_id,
            $observed,
            $project->pi()->name(),
        ];
    }
}

print "Projects without affiliation:\n\n";

foreach my $info (sort {$b->[1] <=> $a->[1]} @semester_projects) {
    my ($project_id, $observed, $pi_name) = @$info;

    my $project_affiliations =
        $affiliation_db->get_project_affiliations($project_id);

    unless (scalar %$project_affiliations) {
        printf "%-10s %8.2f %-15s\n", $project_id, $observed, $pi_name;
        next;
    }

    $total += $observed;

    push @projects, [
        $project_id, $observed, $project_affiliations,
        $pi_name,
    ];

    while (my ($affiliation, $fraction) = each %$project_affiliations) {
        $affiliations{$affiliation} =
            ($affiliations{$affiliation} // 0.0) + $observed * $fraction;
    }
}

printf "\nTotal time observed: %8.2f hours (projects with affiliations only)\n",
    $total;

print "\nProject observing time:\n\n";

foreach my $info (sort {$b->[1] <=> $a->[1]} @projects) {
    printf "%-10s %8.2f %-15s %s\n", $info->[0], $info->[1],
        substr($info->[3], 0, 15),
        join ', ', map {
            sprintf('%.0f%% %s', $info->[2]->{$_} * 100.0,
                $AFFILIATION_NAMES{$_})
        } sort {
            $info->[2]->{$b} <=> $info->[2]->{$a}
        } keys %{$info->[2]};
}

print "\nAffiliation summary:\n\n";

my %percentages = ();
while (my ($affiliation, $observed) = each %affiliations) {
    my $allocation = $allocations->{$semester}->{$affiliation}->{'allocation'};
    $percentages{$affiliation} = (defined $allocation and $allocation != 0.0)
        ? 100.0 * $observed / $allocation
        : undef;
}

foreach my $affiliation (sort {$percentages{$b} <=> $percentages{$a}}
        keys %affiliations) {
    my $allocation = $allocations->{$semester}->{$affiliation}->{'allocation'};
    my $percentage = $percentages{$affiliation};
    my $pattern = "%-20s %8.2f / %8.2f";
    my @parameters = (
        $AFFILIATION_NAMES{$affiliation},
        $affiliations{$affiliation},
        $allocation,
    );

    if (defined $percentage) {
        $pattern .= " (%5.1f %%)";
        push @parameters, $percentage;
    }

    printf $pattern . "\n", @parameters;
}

if ($store_to_database) {
    print "\nStoring affilation hours observed to database...";

    while (my ($affiliation, $observed) = each %affiliations) {
        $affiliation_db->set_affiliation_observed(
            $telescope, $semester, $affiliation, $observed);
    }

    print " [DONE]\n";
}

__END__

=head1 COPYRIGHT

Copyright (C) 2015-2025 East Asian Observatory. All Rights Reserved.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

=cut
