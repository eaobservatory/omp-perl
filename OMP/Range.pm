package OMP::Range;

=head1 NAME

OMP::Range - Implement simple ranges

=head1 SYNOPSIS

  use OMP::Range;

  $r = new OMP::Range( Min => -4, Max => 20);
  $r = new OMP::Range( Min => 0 );

  print "$r";

=head1 DESCRIPTION

Simple class to implement a closed or open range. Exists mainly
to allow stringification override.

Ranges can be bound or unbound. If C<max> is less than C<min>
the range is inverted.

=cut

use strict;
use warnings;

use Number::Interval;
use base qw/ Number::Interval /;

=back

=head1 NOTES

A small wrapper class around the C<Number::Interval> module.

=head1 COPYRIGHT

Copyright (C) 2002-2004 Particle Physics and Astronomy Research Council.
All Rights Reserved.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or (at
your option) any later version.

This program is distributed in the hope that it will be useful,but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place,Suite 330, Boston, MA 02111-1307,
USA

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>.

=cut

1;

