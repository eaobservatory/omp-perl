package OMP::Info::Sched;

=head1 Name

OMP::Info::Sched - Information about multiple nights in a telescope schedule

=cut

use warnings;
use strict;
use Carp;

use OMP::Info::Sched::Night;
use OMP::Info::Sched::Slot;

use base qw/OMP::Info::Base/;

use overload '""' => 'stringify';

__PACKAGE__->CreateAccessors(
    nights => '@OMP::Info::Sched::Night',
);

=head1 Methods

=over 4

=item B<stringify>

Convert the object to a string.

=cut

sub stringify {
    my $self = shift;
    return join "\n", map {$_->stringify()} @{$self->nights()};
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
