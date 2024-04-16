package OMP::DB::Hedwig2OMP;

=head1 NAME

OMP::DB::Hedwig2OMP - Query the Hedwig user account mapping table

=cut

use strict;

use base qw/OMP::DB/;

our $HEDWIG2OMPTABLE = 'user';

=head1 METHODS

=over 4

=item get_omp_id

Fetch OMP user ID for a given Hedwig person number.

Returns C<undef> if the database does not return exactly one result.

=cut

sub get_omp_id {
    my $self = shift;
    my $hedwig_id = shift;

    my $result = $self->_dbhandle()->selectall_arrayref(
        'SELECT omp_id FROM `' . $HEDWIG2OMPTABLE . '` WHERE hedwig_id = ?',
        {},
        $hedwig_id);

    return undef unless 1 == scalar @$result;

    return $result->[0]->[0];
}

=item get_hedwig_ids

Fetch a list of Hedwig person numbers for a given OMP user ID.

=cut

sub get_hedwig_ids {
    my $self = shift;
    my $omp_id = shift;

    my @hedwig_ids = map {$_->[0]} @{
        $self->_dbhandle->selectall_arrayref(
            'SELECT hedwig_id FROM `' . $HEDWIG2OMPTABLE . '` WHERE omp_id = ?',
            {},
            $omp_id)};

    return \@hedwig_ids;
}

1;

__END__

=back

=head1 COPYRIGHT

Copyright (C) 2020-2024 East Asian Observatory
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
