package OMP::Translator::Continuum;

=head1 NAME

OMP::Translator::Continuum - Base translator class for continuum instruments

=head1 SYNOPSIS

    use parent qw/OMP::Translator::Continuum/;

=head1 DESCRIPTION

This is a base class for continuum instrument translator classes.

=cut

use 5.006;
use strict;
use warnings;
use Carp;

use parent qw/OMP::Translator::JCMT/;

=head1 METHODS

=head2 General Methods

=over 4

=item B<velOverride>

Continuum instruments have no requirement for velocity information so return
empty list.

=cut

sub velOverride {
    return ();
}

1;

__END__

=back

=head1 COPYRIGHT

Copyright (C) 2008 Science and Technology Facilities Council.
Copyright (C) 2002-2007 Particle Physics and Astronomy Research Council.
All Rights Reserved.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful,but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc., 59 Temple
Place,Suite 330, Boston, MA  02111-1307, USA

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=cut
