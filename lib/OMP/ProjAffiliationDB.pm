package OMP::ProjAffiliationDB;

=head1 NAME

OMP::ProjAffiliationDB - Manipulate the project affiliation tables

=cut

use strict;

use base qw/OMP::BaseDB Exporter/;

our @EXPORT_OK = qw/%AFFILIATION_NAMES @AFFILIATIONS/;

# Table in which to store affiliation information.
our $AFFILIATIONTABLE = 'ompprojaffiliation';

# Table in which to store affiliation allocations.
our $AFFILIATIONALLOCATIONTABLE = 'ompaffiliationalloc';

# Printable names for affiliation codes.
our %AFFILIATION_NAMES = (
    ca => 'Canada',
    xc => 'Canada (national)',
    cn => 'China',
    ea => 'EAO',
    kr => 'Korea',
    jp => 'Japan',
    th => 'Thailand',
    tw => 'Taiwan',
    uk => 'UK',
    vn => 'Vietnam',
    zz => 'Unknown',
);

# List of recognised affiliations.
our @AFFILIATIONS = keys %AFFILIATION_NAMES;

=head1 METHODS

=head2 Project Affiliations

=over 4

=item get_all_affiliations

Returns a hash of project identifiers to affiliation hashes
similar to those returned by get_project_affiliations.

=cut

sub get_all_affiliations {
    my $self = shift;

    my $results = $self->_db_retrieve_data_ashash(
        'SELECT * FROM ' . $AFFILIATIONTABLE);

    my %projects;

    foreach my $row (@$results) {
        my $project;
        if (exists $projects{$row->{'projectid'}}) {
            $project = $projects{$row->{'projectid'}};
        }
        else {
            $project = {};
            $projects{$row->{'projectid'}} = $project;
        }

        $project->{$row->{'affiliation'}} = $row->{'fraction'};
    }

    return \%projects;
}

=item get_project_affiliations($project)

Returns a reference to a hash of affiliation fractions by
affiliation.

=cut

sub get_project_affiliations {
    my $self = shift;
    my $project = shift;

    my $results = $self->_db_retrieve_data_ashash(
        'SELECT * FROM ' . $AFFILIATIONTABLE . ' WHERE projectid = ?',
        $project);

    my %affiliations;

    foreach my $row (@$results) {
        $affiliations{$row->{'affiliation'}} = $row->{'fraction'};
    }

    return \%affiliations;
}

=item set_project_affiliations($project, \%affiliations)

Takes a hash of affiliation fractions by affilation.  The fractions
should add up to one.

=cut

sub set_project_affiliations {
    my $self = shift;
    my $project = shift;
    my $affiliations = shift;

    # Validate project.
    die 'Invalid project "' .$project . '"'
        unless $project =~ /^([A-Z0-9\/]+)$/;
    my $valid_project = $1;

    # Validate affiliations:
    #     * Valid affiliation codes.
    #     * Fractions add up to one.
    my $total = 0.0;
    my %valid_affiliations;

    while (my ($affiliation, $fraction) = each %$affiliations) {
        die 'Invalid affiliation "' . $affiliation .'"'
            unless $affiliation=~ /^([a-z]{2})$/;
        my $valid_affiliation = $1;
        die 'Unknown affiliation "' . $valid_affiliation .'"'
            unless grep {$_ eq $valid_affiliation} @AFFILIATIONS;
        $valid_affiliations{$valid_affiliation} = 0.0 + $fraction;
        $total += $fraction;
    }

    die 'Affiliation fractions add up to ' . $total
        unless abs($total - 1.0) < 1.0e-6;

    # Start transaction.
    $self->_db_begin_trans();
    $self->_dblock();

    # Remove old entries.
    $self->_db_delete_data($AFFILIATIONTABLE, "projectid = '$valid_project'");

    # Insert new entries.
    while (my ($affiliation, $fraction) = each %valid_affiliations) {
        $self->_db_insert_data($AFFILIATIONTABLE,
            $valid_project, $affiliation, $fraction);
    }

    # End transaction.
    $self->_dbunlock();
    $self->_db_commit_trans();
}

=back

=head2 Affiliation Allocations

=over 4

=item get_all_affiliation_allocations($telescope)

Retrieve all affiliation allocations as a reference to a hash
of semesters referencing hashes of affiliations referencing hashes
of allocations and time observed (in hours).

=cut

sub get_all_affiliation_allocations {
    my $self = shift;
    my $telescope = shift;

    my $results = $self->_db_retrieve_data_ashash(
        'SELECT * FROM ' .
            $AFFILIATIONALLOCATIONTABLE .
            ' WHERE telescope = ?',
        $telescope);

    my %semesters;

    foreach my $row (@$results) {
        my $semester;
        if (exists $semesters{$row->{'semester'}}) {
            $semester = $semesters{$row->{'semester'}};
        }
        else {
            $semester= {};
            $semesters{$row->{'semester'}} = $semester;
        }

        $semester->{$row->{'affiliation'}} = {
            allocation => $row->{'allocation'},
            observed => $row->{'observed'}
        };
    }

    return \%semesters;
}

=item set_affiliation_allocation($telescope, $semester, $affiliation, $hours)

Sets the allocation (integer number of hours) for a given affiliation in a
given semester.

=cut

sub set_affiliation_allocation {
    my $self = shift;
    my $telescope = shift;
    my $semester = shift;
    my $affiliation = shift;
    my $allocation = shift;

    die 'Telescope not recognized' unless $telescope =~ /^(JCMT|UKIRT)$/;
    my $valid_telescope = $1;

    die 'Invalid semester' unless $semester =~ /^([0-9]{2}[AB])$/;
    my $valid_semester = $1;

    die 'Invalid affiliation "' . $affiliation .'"'
        unless $affiliation=~ /^([a-z]{2})$/;
    my $valid_affiliation = $1;
    die 'Unknown affiliation "' . $valid_affiliation .'"'
        unless grep {$_ eq $valid_affiliation} @AFFILIATIONS;

    die 'Invalid allocation' unless $allocation =~ /^([0-9.]+)$/;
    my $valid_allocation = 0.0 + $1;

    # Check if we already have a record for this semester and
    # affiliation.
    my $results = $self->_db_retrieve_data_ashash(
        'SELECT COUNT(*) AS num FROM ' . $AFFILIATIONALLOCATIONTABLE .
            ' WHERE telescope = ? AND semester = ? AND affiliation = ?',
        $valid_telescope, $valid_semester, $valid_affiliation);
    die 'Could not query number of existing rows'
        unless 1 == scalar @$results;
    my $update = $results->[0]->{'num'};

    # Start transaction.
    $self->_db_begin_trans();
    $self->_dblock();

    # Insert/update entry.
    if ($update) {
        $self->_db_update_data($AFFILIATIONALLOCATIONTABLE,
            {allocation => $valid_allocation},
            'semester="' . $valid_semester .
                '" AND affiliation="' . $valid_affiliation .
                '" AND telescope="' . $valid_telescope .'"')
    }
    else {
        $self->_db_insert_data($AFFILIATIONALLOCATIONTABLE,
            $telescope, $semester, $affiliation, $allocation, 0);
    }

    # End transaction.
    $self->_dbunlock();
    $self->_db_commit_trans();
}

=item set_affiliation_observed($telescope, $semester, $affiliation, $hours)

Sets the time observed for a given affiliation in a given semester.

Assumes that the semester/affiliation are already present in the
affiliation allocation table and performes a simple update of the
allocation field.

=cut

sub set_affiliation_observed {
    my $self = shift;
    my $telescope = shift;
    my $semester = shift;
    my $affiliation = shift;
    my $observed= shift;

    die 'Telescope not recognized' unless $telescope =~ /^(JCMT|UKIRT)$/;
    my $valid_telescope = $1;

    die 'Invalid semester' unless $semester =~ /^([0-9]{2}[AB])$/;
    my $valid_semester = $1;

    die 'Invalid affiliation "' . $affiliation .'"'
        unless $affiliation=~ /^([a-z]{2})$/;
    my $valid_affiliation = $1;
    die 'Unknown affiliation "' . $valid_affiliation .'"'
        unless grep {$_ eq $valid_affiliation} @AFFILIATIONS;

    die 'Invalid time observed' unless $observed =~ /^([.0-9]+)$/;
    my $valid_observed = $1;

    # Start transaction.
    $self->_db_begin_trans();
    $self->_dblock();

    $self->_db_update_data($AFFILIATIONALLOCATIONTABLE,
        {observed => $valid_observed},
        'semester="' . $valid_semester .
            '" AND affiliation="' . $valid_affiliation .
            '" AND telescope="' . $valid_telescope . '"');

    # End transaction.
    $self->_dbunlock();
    $self->_db_commit_trans();
}

1;

__END__

=back

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
