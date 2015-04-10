package OMP::ProjAffiliationDB;

=head1 NAME

OMP::ProjAffiliationDB - Manipulate the project affiliation table

=cut

use strict;

use base qw/OMP::BaseDB Exporter/;

our @EXPORT_OK = qw/%AFFILIATION_NAMES @AFFILIATIONS/;

# Table in which to store affiliation information.
our $AFFILIATIONTABLE = 'ompprojaffiliation';

# Printable names for affiliation codes.
our %AFFILIATION_NAMES = (
    ca => 'Canada',
    cn => 'China',
    ea => 'EAO',
    kr => 'Korea',
    jp => 'Japan',
    tw => 'Taiwan',
    uk => 'UK',
);

# List of recognised affiliations.
our @AFFILIATIONS = keys %AFFILIATION_NAMES;

=head1 METHODS

=over 4

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
        unless $project =~ /^([A-Z0-9]+)$/;
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

1;

__END__

=back

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
