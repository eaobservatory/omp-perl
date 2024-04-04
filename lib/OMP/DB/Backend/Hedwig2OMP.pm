package OMP::DB::Backend::Hedwig2OMP;

=head1 NAME

OMP::DB::Backend::Hedwig2OMP - Access to the hedwig2omp database

=cut

use strict;
use warnings;

use OMP::Config;

use base qw/OMP::DB::Backend/;

=head1 METHODS

=over 4

=item B<loginhash>

This class method returns the information required to connect to the
database.

=cut

sub loginhash {
    my $self = shift;

    return (
        driver   => OMP::Config->getData('hedwig2omp.driver'),
        server   => OMP::Config->getData('hedwig2omp.server'),
        database => OMP::Config->getData('hedwig2omp.database'),
        user     => OMP::Config->getData('hedwig2omp.user'),
        password => OMP::Config->getData('hedwig2omp.password'),
    );
}

1;

__END__

=back

=head1 COPYRIGHT

Copyright (C) 2020 East Asian Observatory
All Rights Reserved.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful,but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc.,51 Franklin
Street, Fifth Floor, Boston, MA  02110-1301, USA

=cut
