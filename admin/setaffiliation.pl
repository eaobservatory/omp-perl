#!/local/perl/bin/perl

=head1 NAME

setaffiliation - Set affiliation for projects

=head1 SYNOPSIS

  perl admin/setaffiliation.pl < affiliation.txt

=head1 DESCRIPTION

Sets the affiliations for projects.  Accepts a set of
projects and affiliations on standard input, where each line
should contain a project identifier, affiliation code and
fraction.  The affiliation code should be a lower case two
digit country code and the fractions for a given project
must add up to one.

=cut

use strict;

use OMP::DBServer;
use OMP::ProjAffiliationDB;

my $affiliation_db = new OMP::ProjAffiliationDB(
    DB => OMP::DBServer->dbConnection());

my %projects;

while (<>) {
    chomp;
    my ($project, $affiliation, $fraction) = split;

    if (exists $projects{$project}) {
        $projects{$project}->{$affiliation} = $fraction;
    }
    else {
        $projects{$project} = {$affiliation => $fraction};
    }
}

while (my ($project, $affiliations) = each %projects) {
    print 'Setting affiliations for ' . $project . "\n";
    $affiliation_db->set_project_affiliations($project, $affiliations);
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
