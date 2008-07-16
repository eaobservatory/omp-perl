package OMP::Translator::Base;

=head1 NAME

OMP::Translator::Base - translate science program to sequence

=head1 SYNOPSIS

**  need update

  use OMP::Translator::Base;

=head1 DESCRIPTION

**  need update

This class converts a science program object (an C<OMP::SciProg>)
into a sequence understood by the data acquisition system.

In the case of SCUBA, an Observation Definition File (ODF) is
generated (or multiple ODFs). For DAS heterodyne systems a HTML
summary of the MSB will be generated. For ACSIS, XML configuration files
are generated.

The actual translation is done in a subclass. The top level class
determines the correct class to use for the MSB and delegates the
translation of each observation within the MSB to that class.

=cut

use 5.006;
use strict;
use warnings;

use OMP::Constants qw/ :msb /;
use OMP::General;

our $DEBUG = 0;
our $VERBOSE = 0;

=head1 METHODS

=over 4

=item <PosAngRot>

Rotate coordinates through a specified position angle.
Position Angle is defined as "East of North". This means
that the rotation angle is a reverse of the normal mathematical definition
of "North of East"

          N
          ^
          |
          |
    E <---+

In the above diagram (usually RA/Dec) the position angle will be
positive anti-clockwise.

  ($x2, $y2) = OMP::Translator::Base->PosAngRot( $x1, $y1, $PA );

where PA is given in degrees and not radians (mainly because
the Science Program rotation angles are all given in degrees).

Note that this routine should really be in some generic Math::
or Coords:: class. Note also that this is a class method to
facilitate use in subclasses.

After rotation, the accuracy is limited to two decimal places.

=cut

use constant DEG2RAD => 3.141592654 / 180.0;

sub PosAngRot {
  my $self = shift;
  my ($x1, $y1, $pa) = @_;

  # New coordinates
  my ($x2,$y2);

  # Do rotation if rotation is nonzero (since in most cases
  # people do not ask for rotated coordinates) - this is 
  # a very minor optimization compared two the multiple sprintfs!!
  if (abs($pa) > 0.0) {

    # Convert to radians
    my $rpa = $pa * DEG2RAD;

    # Precompute the cos and sin since we use it twice
    my $cosrpa = cos( $rpa );
    my $sinrpa = sin( $rpa );

    # Rotate to new frame
    $x2 =   $x1 * $cosrpa  +  $y1 * $sinrpa;
    $y2 = - $x1 * $sinrpa  +  $y1 * $cosrpa;

  } else {
    $x2 = $x1;
    $y2 = $y1;
  }

  # Now format to 2dp
  my $f = '%.2f';
  $x2 = sprintf($f,$x2);
  $y2 = sprintf($f,$y2);

  # trap -0.00 by formatting a negative zero
  # This is more convoluted a check because the format is variable
  $x2 = sprintf($f,0.0) if $x2 eq sprintf($f,-0.0);
  $y2 = sprintf($f,0.0) if $y2 eq sprintf($f,-0.0);

  return ($x2, $y2);
}

=item B<PruneMSBs>

Remove MSBs that should not be translated. Currently, removes
MSBs that are marked as REMOVED unless there is only one MSB
supplied.

  @pruned = OMP::Translator::Base->PruneMSBs( @msbs );

Arguments are C<OMP::MSB> objects.

=cut

sub PruneMSBs {
  my $class = shift;
  my @msbs = @_;

  my @out;
  if (scalar(@msbs) > 1) {
    @out = grep { $_->remaining != OMP__MSB_REMOVED } @msbs;
  } else {
    @out = @msbs;
  }
  return @out;
}

=item B<correct_offsets>

For some observing modes, the offset iterator should not generate a set
of standalone observations, but should generate a single observation
that itself iterates over the offsets.

This routine can be used to correct the structure of the MSB such that
when it is unrolled, the named observing modes will see a set of offsets
rather than a single offset.

The name of the affected observing modes can be specified (the "obstype"
setting, ie drop the SpIter and trailing Obs).

  OMP::Translator::Base->correct_offsets( $msb, "Stare", "Jiggle" );

The MSB is modified inplace.

Problems can be encountered by this routine if there is more than one
observing type below each Offset iterator. Since this is unusual in
practice and extremely difficult to get correct (since you have to
account for all structures below the iterator) we should croak in this
situation. Currently we let it go.

=cut

sub correct_offsets {
  my $self = shift;
  my $msb = shift;
  my @obstypes = @_;

  # Note that this returns references to each observation summary.
  # We can modify this hash in place without putting the structure
  # back into the object. This will trigger a nice bug if the obssum
  # method is changed to return a copy.
  my @obs = $msb->obssum;

  # Pattern match
  my $patt = "SpIter(" . join( "|", @obstypes) . ")Obs";

  # loop over each observation
  for my $obs (@obs) {

    my %modes = map { $_ => undef } @{$obs->{obstype}};

    # skip to next observation unless we have a specified obs type
    my $hastype;
    for my $type (@obstypes) {
      $hastype = 1 if exists $modes{$type};
    }
    next unless $hastype;

    # Now need to recurse through the data structure changing
    # offset iterator to a single array rather than an array
    # separate positions.

    # Note that this will not do the right thing if you have
    # a Raster and Stare as child of offset iterator because the
    # raster will not unroll correctly
    for my $child (@{ $obs->{SpIter}->{CHILDREN} }) {
      $self->_fix_offset_recurse( $child, $patt );
    }
  }

  return;
}

# When we hit SpIterOffset we correct the ATTR array
# This modifies it in-place. No need to re-register.

sub _fix_offset_recurse {
  my $self = shift;
  my $this = shift;
  my $types = shift;

  # Loop over keys in children [the iterators]
  for my $key (keys %$this) {

    if ($key eq 'SpIterOffset') {

      # Need to determine whether this Offset iterator has a child
      # that is a StareObs
      my @children;
      push(@children,$self->_list_children( $this ));

      # Look for Stare
      my $isstare;
      for my $c (@children) {
        if ($c =~ /$types/) {
          $isstare = 1;
          last;
        }
      }

      if ($isstare) {
        # FIX UP - it does not make any sense to have another
        # offset iterator below this level but we do support it
        my @offsets = @{ $this->{$key}->{ATTR}};

        # and store it back
        $this->{$key}->{ATTR} = [ { offsets => \@offsets } ];
      }
    }

    # Now need to go deeper if need be
    # We also need to worry about sanity checks
    # with the possibility of encountering a Raster
    if (UNIVERSAL::isa($this->{$key},"HASH") &&
        exists $this->{$key}->{CHILDREN}) {
      # This means we have some children to analyze

      for my $child (@{ $this->{$key}->{CHILDREN} }) {
        $self->_fix_offset_recurse( $child, $types );
      }

    }

  }

}

# Returns list of children
sub _list_children {
  my $self = shift;
  my $this = shift;

  my @children;
  for my $key (keys %$this) {

    # Store all children
    push(@children,$key);

    if (UNIVERSAL::isa($this->{$key},"HASH") &&
        exists $this->{$key}->{CHILDREN}) {
      # This means we have some children to analyze
      for my $child (@{ $this->{$key}->{CHILDREN} }) {
        push(@children,$self->_list_children( $child ));
      }
    }
  }
  return @children;
}

=item B<correct_wplate>

Convert separate waveplate angles per observation into a single
observation. All OCS config driven instruments at JCMT require
that all angles are in a single observation.

  OMP::Translator::Base->correct_wplate( $msb );

=cut

sub correct_wplate {
  my $self = shift;
  my $msb = shift;

  # Note that this returns references to each observation summary.
  # We can modify this hash in place without putting the structure
  # back into the object. This will trigger a nice bug if the obssum
  # method is changed to return a copy.
  my @obs = $msb->obssum;

  # loop over each observation
  for my $obs (@obs) {
    # do not care what happens if this is not polarimetry
    next unless $obs->{pol};

    # Now need to recurse through the data structure changing
    # waveplate iterator to a single array rather than an array
    # separate positions.
    for my $child (@{ $obs->{SpIter}->{CHILDREN} }) {
      $self->_fix_wplate_recurse( $child );
    }

  }
  return;
}

# When we hit SpIterPOL we correct the ATTR array
# This modifies it in-place. No need to re-register.

sub _fix_wplate_recurse {
  my $self = shift;
  my $this = shift;

  # Loop over keys in children [the iterators]
  for my $key (keys %$this) {

    if ($key eq 'SpIterPOL') {

      # if we have no waveplate angles skip
      next unless exists $this->{$key}->{ATTR}->[0]->{waveplate};

      # FIX UP - it does not make any sense to have another
      # waveplate iterator below this level but we do support it
      my @wplate = map { @{$_->{waveplate}} } @{ $this->{$key}->{ATTR}};

      # and store it back
      $this->{$key}->{ATTR} = [ { waveplate => \@wplate } ];

    }

    # Now need to go deeper if need be
    if (UNIVERSAL::isa($this->{$key},"HASH") &&
        exists $this->{$key}->{CHILDREN}) {
      # This means we have some children to analyze

      for my $child (@{ $this->{$key}->{CHILDREN} }) {
        $self->_fix_wplate_recurse( $child );
      }

    }

  }
  return;
}

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

1;
