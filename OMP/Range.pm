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
use overload 
  '""' => "stringify",
  'eq' => "equate";

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

Create a new object. Can be populated when supplied with
keys C<Max> and C<Min>.

  $r = new OMP::Range();
  $r = new OMP::Range( Max => 5 );

=cut

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;

  my %args = @_;

  my $r = {
	   Min => undef,
	   Max => undef,
	  };

  # Create object
  my $obj = bless $r, $class;

  # Populate it
  $obj->min( $args{Min}) if exists $args{Min};
  $obj->max( $args{Max}) if exists $args{Max};

  return $obj;
}

=back

=head2 Accessors

=over 4

=item B<max>

Return (or set) the upper end of the range.

  $max = $r->max;
  $r->max(22.0);

C<undef> indicates that the range has no lower bound.

=cut

sub max {
  my $self = shift;
  $self->{Max} = shift if @_;
  return $self->{Max};
}

=item B<min>

Return (or set) the lower end of the range.

  $min = $r->min;
  $r->min( undef );

C<undef> indicates that the range has no lower bound.

=cut

sub min {
  my $self = shift;
  $self->{Min} = shift if @_;
  return $self->{Min};
}

=item B<minmax>

Return (or set) the minimum and maximum values of the
range as an array.

  $r->minmax( 1, 5 );
  @range = $r->minmax;

Returns reference to an array in a scalar context.

=cut

sub minmax {
  my $self = shift;
  if (@_) {
    $self->min( $_[0] );
    $self->min( $_[1] );
  }
  my @minmax = ( $self->min, $self->max );
  return (wantarray ? @minmax : \@minmax);
}

=item B<minmax_hash>

Return (or set) the minimum and maximum values of the
range as an hash.

  $r->minmax_hash( min => 1, max => 5 );
  %range = $r->minmax_hash;

Returns reference to an hash in a scalar context.

C<min> or C<max> can be ommitted. The returned hash always
includes C<min> and C<max>.

=cut

sub minmax_hash {
  my $self = shift;
  if (@_) {
    my %args = @_;
    $self->min( $args{min} ) if exists $args{min};
    $self->max( $args{max} ) if exists $args{max};
  }
  my %minmax = ( min => $self->min, max => $self->max );
  return (wantarray ? %minmax : \%minmax);
}

=back

=head2 General

=over 4

=item B<stringify>

Convert the object into a string representation for display.
Usually called via a stringify overload.

=cut

sub stringify {
  my $self = shift;

  my $min = $self->min;
  my $max = $self->max;

  if (defined $min and defined $max) {
    # Bound
    if ($max < $min) {
      return "<=$max and >=$min";
    } else {
      return "$min-$max";
    }
  } elsif (defined $min) {
    return ">=$min";
  } elsif (defined $max) {
    return "<=$max";
  } else {
    return "**ERROR**";
  }

}

=item B<equate>

Compare with another range object.
Returns true if they are the same. False otherwise.

=cut

sub equate {
  my $self = shift;
  my $comparison = shift;

  # Need to check that both are objects
  return 0 unless defined $comparison;
  return 0 unless UNIVERSAL::isa($comparison, "OMP::Range");
  return 0 if $self->min != $comparison->min;
  return 0 if $self->max != $comparison->max;

}

=back

=head1 COPYRIGHT

Copyright (C) 2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>.

=cut

1;

