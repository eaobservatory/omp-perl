package OMP::CGIPage::Home;

=head1 NAME

OMP::CGIPage::Home - Display OMP home page

=head1 SYNOPSIS

    use OMP::CGIPage::Home;

=head1 DESCRIPTION

Helper methods for preparing the OMP home page.

=cut

use strict;
use warnings;

use Carp;

use base qw/OMP::CGIPage/;

$| = 1;

=head1 Routines

=over 4

=item B<home_page_view>

Creates the OMP home page.

=cut

sub home_page_view {
    my $self = shift;

    return {
        fault_categories => [
            ['JCMT', 'JCMT faults'],
            ['JCMT_EVENTS', 'JCMT events'],
            ['UKIRT', 'UKIRT faults'],
            ['CSG', 'CSG faults'],
            ['OMP', 'OMP faults'],
            ['DR', 'DR faults'],
            ['FACILITY', 'Facility faults'],
            ['VEHICLE_INCIDENT', 'Vehicle incident reporting'],
            ['SAFETY', 'Safety reporting'],
        ],
    };
}

1;

__END__

=back

=head1 COPYRIGHT

Copyright (C) 2022 East Asian Observatory
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

1;
