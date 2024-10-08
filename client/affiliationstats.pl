#!/local/perl/bin/perl

=head1 NAME

affiliationstats - Generate observing statistics by affiliation

=head1 SYNOPSIS

    client/affiliationstats.pl TELESCOPE SEMESTER [--store]

=head1 DESCRIPTION

Displays observing statistics by affiliation for a given semester.  If the
--store argument is given, then the hours observed are written into the
OMP affiliation allocation table.

=cut

use strict;

use FindBin;
use File::Spec;

use constant OMPLIB => "$FindBin::RealBin/../lib";

BEGIN {
    $ENV{'OMP_CFG_DIR'} = File::Spec->catdir(OMPLIB, '../cfg')
        unless exists $ENV{'OMP_CFG_DIR'};
}

use lib OMPLIB;

use OMP::DB::Backend;
use OMP::DB::Project;
use OMP::Query::Project;
use OMP::DB::ProjAffiliation qw/%AFFILIATION_NAMES/;

my $telescope = uc($ARGV[0]) or die 'Telescope not specified';
my $semester = uc($ARGV[1]) or die 'Semester not specified';
my $store_to_database = (exists $ARGV[2]) && (lc($ARGV[2]) eq '--store');

my $db = OMP::DB::Backend->new;
my $project_db = OMP::DB::Project->new(DB => $db);
my $affiliation_db = OMP::DB::ProjAffiliation->new(DB => $db);

my $allocations = $affiliation_db->get_all_affiliation_allocations($telescope);

my @projects;
my %affiliations;
my $total = 0.0;

print "\nProjects without affiliation:\n\n";

foreach my $project (@{$project_db->listProjects(
        OMP::Query::Project->new(HASH => {
            telescope => $telescope,
            semester => $semester,
        }))}) {
    my $project_id = $project->projectid();
    my $observed = ($project->allocated()
        + $project->pending()
        - $project->remaining()) / 3600.0;

    next unless $observed;

    my $project_affiliations =
        $affiliation_db->get_project_affiliations($project_id);

    unless (scalar %$project_affiliations) {
        printf "%-10s %8.2f\n", $project_id, $observed;
        next;
    }

    $total += $observed;

    push @projects, [
        $project_id, $observed, $project_affiliations,
        $project->pi()->name()];

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
    $percentages{$affiliation} = (defined $allocation)
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

Copyright (C) 2015-2018 East Asian Observatory. All Rights Reserved.

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
