package OMP::Info::SciProg;

=head1 Name

OMP::Info::SciProg - Science Program information

=head1 DESCRIPTION

This class provides a way to handle basic information about a Science Program
in cases where it is not necessary to use the full (XML) program itself.

=cut

use strict;
use warnings;
use Carp;

use base qw/OMP::Info::Base/;

=head1 METHODS

=begin __PRIVATE__

=head2 Create Accessor Methods

Create the accessor methods from a signature of their contents.

=cut

__PACKAGE__->CreateAccessors(
    projectid => '$__UC__',
    msb => '@OMP::Info::MSB',
);

=end __PRIVATE__

=head2 Accessor Methods

=over 4

=item B<projectid>

=item B<msb>

=back

=head2 General Methods

=over 4

=item B<fetchMSB>

Given a checksum, search for the matching MSB.

    my $msbinfo = $info->fetchMSB($checksum);

Returns an C<OMP::Info::MSB> object on success, or C<undef> otherwise.

=cut

sub fetchMSB {
    my $self = shift;
    my $checksum = shift;

    foreach my $msb ($self->msb()) {
        if ($checksum eq $msb->checksum()) {
            return $msb;
        }
    }

    return undef;
}

=item B<existsMSB>

Given a checksum, determine whether a corresponding MSB is present.

    if ($info->existsMSB($checksum)) {
        ...
    }

=cut

sub existsMSB {
    my $self = shift;
    my $checksum = shift;
    return defined $self->fetchMSB($checksum);
}

=back

=head1 SEE ALSO

L<OMP::Info::MSB>

=head1 COPYRIGHT

Copyright (C) 2018 East Asian Observatory
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

1;
