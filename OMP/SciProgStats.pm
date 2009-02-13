# Make sure we load the real class first
use OMP::SciProg;

# Then add our new methods to that class
package OMP::SciProg;

=head1 NAME

OMP::SciProgStats - Find statistical properties of a science program

=head1 SYNOPSIS

 use OMP::SciProgStats;

 @racover = $sp->ra_coverage();


=head1 DESCRIPTION

This class extends C<OMP::SciProg> such that additional methods
associated with statistical analysis are made available. It does not
provide a namespace of its own.

It is separate to reduce the size of the core C<OMP::SciProg> class.

=cut

use 5.006;
use strict;
use warnings;
use warnings::register;
use Carp;

use vars qw/ $VERSION /;
#$VERSION = sprintf("%d", q$Revision$ =~ /(\d+)/);

=head1 METHODS

No constructor or accessor methods provided by this extension.

=over 4

=item B<ra_coverage>

Return a histogram of RA coverage present in the science program.

  my @hist = $sp->ra_coverage();

The return list contains 24 elements, starting at hour 0 and
incrementing to 23. The values are the amount of time present
in each hour, using the time estimates for each observation
and multiplying by the number of MSB repeats.

Optional arguments can be used to constrain the data.

 @hist = $sp->ra_coverage( instrument => 'SCUBA' );

Allowed keys are:

 instrument    Specify an instrument for which the coverage is calculated

=cut

sub ra_coverage {
  my $self = shift;
  my %args = @_;

  # Initialise histogram
  my @rahist = map { 0 } (0..23);

  # Now loop over each MSB
  for my $msb ($self->msb) {

    my $remaining = $msb->remaining;

    # Filter out complete MSBs or removed MSBs.
    next unless $remaining > 0;

    for my $obs ($msb->obssum) {
      # skip if we are specifically looking for one instrument
      next if (defined $args{instrument} && 
	       $obs->{instrument} ne $args{instrument});

      my $target = $obs->{coords};
      if ($target->type ne 'RADEC') {
	# warn "Target ". $target->name ." in project ". $proj->projectid . " is non-sidereal. Skipping\n";
	next;
      }
      my $ra = $target->ra( format => 'h' );
      $ra = int( $ra + 0.5);
      $ra = 0 if $ra >= 24;

      # Take into account the estimated duration of each SpObs
      # If we are just counting SpObs this factor is always 1
      my $dur = $obs->{timeest} / 3600;

      # Total time for this SpObs is the duration of the observation
      # times the number of repeats
      my $incr = $remaining * $dur;

      # Add an entry for each repeat of an MSB
      $rahist[$ra] += $incr;
    }

  }

  return @rahist;
}

=back

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2004 Particle Physics and Astronomy Research Council.
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

=head1 SEE ALSO

L<OMP::SciProg>

=cut

1;
