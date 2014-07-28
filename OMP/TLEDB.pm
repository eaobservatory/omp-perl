package OMP::TLEDB;

=head1 NAME

OMP::TLEDB - Class providing access to cached TLE coordinates

=cut

use strict;
use warnings;

use Astro::Coords::TLE;

=head1 METHODS

=head2 Constructor

=over 4

=item new

Construct new OMP::TLEDB object.

=cut

sub new {
    my $class = shift;

    my $self = {
    };

    return bless $self, (ref $class) || $class;
}

=back

=head2 General Methods

=over 4

=item get_coord

Retrieve TLE coordinates by object name.  This will be an
Astro::Coords::TLE object.

B<Currently a dummy implementation.>

=cut

sub get_coord {
    my $self = shift;
    my $object = shift;

    return new Astro::Coords::TLE(
        name => $object,
        epoch_year => 2014,
        epoch_day => 90.51853956,
        bstar => 0.0,
        inclination => new Astro::Coords::Angle(6.9693, units => 'degrees'),
        raanode => new Astro::Coords::Angle(338.3797, units => 'degrees'),
        e => 0.0001636,
        perigee => new Astro::Coords::Angle(42.8768, units => 'degrees'),
        mean_anomaly => new Astro::Coords::Angle(204.2600, units => 'degrees'),
        mean_motion => 1.00276036,
    );
}

=back

=head1 COPYRIGHT

Copyright (C) 2014 Science and Technology Facilities Council.
All Rights Reserved.

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

=cut

1;
