#!/local/perl/bin/perl

=head1 NAME

affiliationstats - Generate observing statistics by affiliation

=head1 SYNOPSIS

  client/affiliationstats.pl TELESCOPE SEMESTER

=cut

use strict;

use OMP::DBServer;
use OMP::ProjDB;
use OMP::ProjQuery;
use OMP::ProjAffiliationDB qw/%AFFILIATION_NAMES/;

my $telescope = $ARGV[0] or die 'Telescope not specified';
my $semester = $ARGV[1] or die 'Semester not specified';

my $project_db = new OMP::ProjDB(
    DB => OMP::DBServer->dbConnection());

my $affiliation_db = new OMP::ProjAffiliationDB(
    DB => OMP::DBServer->dbConnection());

my @projects;
my %affiliations;
my $total = 0.0;

foreach my $project ($project_db->listProjects(
        new OMP::ProjQuery(XML => '<ProjQuery><telescope>' . $telescope .
            '</telescope><semester>' . $semester .
            '</semester></ProjQuery>'))) {
    my $project_id = $project->projectid();
    my $observed = ($project->allocated()
        + $project->pending()
        - $project->remaining()) / 3600.0;

    next unless $observed;

    my $project_affiliations =
        $affiliation_db->get_project_affiliations($project_id);

    next unless %$project_affiliations;

    $total += $observed;

    push @projects, [$project_id, $observed, $project_affiliations];

    while (my ($affiliation, $fraction) = each %$project_affiliations) {
        $affiliations{$affiliation} =
            ($affiliations{$affiliation} // 0.0) + $observed * $fraction;
    }
}

printf "Total time observed: %8.2f hours\n", $total;

print "\nProject observing time:\n\n";

foreach my $info (sort {$b->[1] <=> $a->[1]} @projects) {
    printf "%-10s %8.2f %s\n", $info->[0], $info->[1],
        join ', ', map {
            sprintf('%.0f%% %s', $info->[2]->{$_} * 100.0,
                $AFFILIATION_NAMES{$_})
        } keys %{$info->[2]};
}

print "\nAffiliation summary:\n\n";

foreach my $affiliation (sort {$affiliations{$b} <=> $affiliations{$a}}
        keys %affiliations) {
    printf "%-10s %8.2f\n", $AFFILIATION_NAMES{$affiliation},
        $affiliations{$affiliation};
}

__END__

=head1 COPYRIGHT

Copyright (C) 2015 East Asian Observatory. All Rights Reserved.

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