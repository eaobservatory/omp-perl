package OMP::PreviewQuery;

=head1 NAME

OMP::PreviewQuery - Class representing a query of the preview database

=cut

use strict;
use warnings;

use OMP::Error;

use base qw/OMP::DBQuery/;

=head1 METHODS

=over 4

=item B<sql>

Return SQL representation of the query.

    $sql = $query->sql($previewtable);

=cut

sub sql {
    my $self = shift;

    throw OMP::Error::DBMalformedQuery(
        'PreviewQuery: sql method invoked with incorrect number of arguments')
        unless 1 == scalar @_;

    my $previewtable = shift;

    my $subsql = $self->_qhash_tosql();

    return sprintf 'SELECT * FROM %s WHERE %s', $previewtable, $subsql;
}

=item B<_root_element>

XML root element to be located in the query XML.

=cut

sub _root_element {
  return 'PreviewQuery';
}

1;

__END__

=back

=head1 COPYRIGHT

Copyright (C) 2024 East Asian Observatory
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
