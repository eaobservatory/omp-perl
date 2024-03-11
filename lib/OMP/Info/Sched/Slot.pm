package OMP::Info::Sched::Slot;

=head1 Name

OMP::Info::Sched::Slot - Information about a one hour slot in a telescope schedule

=cut

use warnings;
use strict;
use Carp;

use Time::Piece;
use Time::Seconds qw/ONE_HOUR/;

use base qw/OMP::Info/;

use overload '""' => 'stringify';

__PACKAGE__->CreateAccessors(
    telescope => '$',
    date => 'Time::Piece',
    time => 'Time::Piece',
    queue => '$',
);

=head1 Methods

=over 4

=item B<time_local>

Return the time in the local time zone.

=cut

sub time_local {
    my $self = shift;

    return $self->{'time'} + ONE_HOUR * 14;
}

=item B<stringify>

Convert the object to a string.

=cut

sub stringify {
    my $self = shift;
    return '('
        . $self->time_local()->strftime('%H:%M')
        . ' '
        . ((defined $self->queue()) ? $self->queue() : '??')
        . ')';
}

1;

__END__

=back

=head1 COPYRIGHT

Copyright (C) 2021 East Asian Observatory
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
