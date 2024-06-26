package OMP::DB::TLE;

=head1 NAME

OMP::DB::TLE - Class providing access to cached TLE coordinates

=cut

use strict;
use warnings;

use Astro::Coords::TLE;
use OMP::Error;

use parent qw/OMP::DB/;

our $TLETABLE = 'omptle';

=head1 METHODS

=head2 Constructor

=over 4

=item new

Construct new OMP::DB::TLE object.

=cut

# Use base class version.

=back

=head2 General Methods

=over 4

=item get_coord

Retrieve TLE coordinates by object name.  This will be an
Astro::Coords::TLE object.  Returns undef if the target is
not found.

=cut

sub get_coord {
    my $self = shift;
    my $object = shift;

    my $row = $self->_dbhandle()->selectrow_hashref(
        "SELECT * FROM $TLETABLE WHERE target=?",
        {},
        $object,
    );

    return undef unless defined $row;

    return $self->tle_row_to_coord($row);
}

=back

=head1 SUBROUTINES

=over 4

=item standardize_tle_name

As decided in the TLE meeting of 8/19/2014, the "target" name for
AUTO-TLE coordinates is to be standardized in the database.  This
will help with the caching of TLE coordinates and the insertion
of them into MSBs.

=cut

sub standardize_tle_name {
    my $cls = shift;
    my $target = shift;

    if ($target =~ /^\s*NORAD\s*(\d{1,5})\s*$/aai) {
        # Target is a "NORAD" catalog identifier.

        my $norad = $1;
        return sprintf('NORAD%05i', $norad);
    }

    # We did not find a match.
    throw OMP::Error::FatalError(
        'Did not understand AUTO-TLE target name "' . $target . '"');
}

=item tle_row_to_coord

Converts a hashref representation of a database row containing the target
name and elements el1 -- el8 to an Astro::Coords::TLE object.

=cut

sub tle_row_to_coord {
    my $cls = shift;
    my $row = shift;
    return Astro::Coords::TLE->new(
        name => $row->{'target'},
        epoch => $row->{'el1'},
        bstar => $row->{'el2'},
        inclination => Astro::Coords::Angle->new($row->{'el3'}, units => 'rad'),
        raanode => Astro::Coords::Angle->new($row->{'el4'}, units => 'rad'),
        e => $row->{'el5'},
        perigee => Astro::Coords::Angle->new($row->{'el6'}, units => 'rad'),
        mean_anomaly => Astro::Coords::Angle->new($row->{'el7'}, units => 'rad'),
        mean_motion => $row->{'el8'},
    );
}

1;

__END__

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
