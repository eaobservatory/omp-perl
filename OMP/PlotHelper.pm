package OMP::PlotHelper;

=head1 NAME

OMP::PlotHelper - helpful methods for generating plots based on OMP statistics

=head1 SYNOPSIS

  use OMP::PlotHelper;

  @values_binned = OMP::PlotHelper->bin_up(size => 7,
                                           method => 'sum',
                                           values => \@values,);

=head1 DESCRIPTION

Routines that help in the process of generating plots based on statistics
such as fault rate and time accounting.

=cut

use 5.006;
use strict;
use warnings;

use Data::Dumper;
use Scalar::Util qw(looks_like_number);

=head1 METHODS

There are no instance methods, only class (static) methods.

=head2 General Methods

=over 4

=item B<bin_up>

Bin up values by an arbitrary number (can be fractional).

  @values_binned = OMP::PlotHelper->bin_up(size => 7,
                                           method => 'sum',
                                           values => \@values,);

  @values_binned = OMP::PlotHelper->bin_up(size => [31,29,31,30,
                                                    31,30,31,31,
                                                    30,31,30,31,],
                                           method => 'average',
                                           values => \@values,
                                           startnum => $modified_julian_date);

Arguments should be provided in hash form.  The arguments are:

  size     - Number to bin up by, or an array reference of bin sizes.
             If an array reference is given, values are binned until
             there are no more bins left, otherwise values are binned
             until there are no more values left.
  method   - Method to use when binning.  A string that is either
             'sum', 'average', or 'max'.
  values   - An array reference whose elements are coordinates where the
             first element (the x value) is a value to bin by, and
             the second element (the y value) is a value to be binned.
  startnum - Number to start binning at.  Defaults to the lowest x
             value in the 'values' array.

Except for 'startnum', all arguments are required. Returns an array
of coordinates.

=cut

sub bin_up {
  my $self = shift;
  my %args = @_;
  my $size = $args{size};
  my $method = lc($args{method});
  my $start_num = $args{startnum};
  my @values = @{$args{values}};

  # Check that bin size is greater than 0
  throw OMP::Error::BadArgs("Argument 'size' must be either a number or an array reference")
    unless (looks_like_number $size or ref($size) eq 'ARRAY');

  # Check that method argument is either 'sum' or 'average'
  throw OMP::Error::BadArgs("Argument 'method' must be either 'sum', 'average', or 'max'")
    unless ($method eq 'sum' or $method eq 'average' or $method eq 'max');

  # Check that a value array was provided
  throw OMP::Error::BadArgs("Argument 'values' must provide an array of arrays")
    unless (defined $values[0]->[0] and defined $values[0]->[1]);

  # Sort the values
  @values = sort {$a->[0] <=> $b->[0]} @values;

  if (defined $start_num) {

    # Check that 'startnum' value is a number
    throw OMP::Error::BadArgs("Argument 'startnum' must be a number")
      unless (looks_like_number $start_num);

    # Make sure 'startnum' is lower than, or equal to, the lowest value 
    # in the values array
    throw OMP::Error::BadArgs("Argument 'startnum' must be lower than or equal to lowest X value")
      unless ($start_num <= $values[0]->[0] );
  }

  # Get the high and low values for the bin.  Low value will be
  # the lowest x value in the array, unless a 'startnum' was provided,
  # in which case the low value will be the 'startnum' value.
  my $bin_size = $self->_get_bin_size($size, 0);
  my $low_val = (defined $start_num ? $start_num : $values[0]->[0]);
  my $high_val = $low_val + $bin_size;

  # The starting X value (middle of bin)
  my $bin_mid = $low_val + ($bin_size / 2);

  # Bin up the values
  my @result;
  my $bin_num = 0; # Keep track of bin number
  my @count; # Keep count of values added to each bin
  for my $val (@values) {

    until ($val->[0] >= $low_val and $val->[0] <= $high_val) {
      # Value is outside the range of this bin.  Keep moving
      # through the bins until we find one that the value belongs in

      $result[$bin_num]->[1] = 0                 # Set bin Y value to zero if nothing
	unless (defined $result[$bin_num]->[1]); # went in this bin.

      $result[$bin_num]->[0] = $bin_mid          # Set the X value if it wasn't set
	unless (defined $result[$bin_num]->[0]); # earlier

      # Move to the next bin
      $bin_size = $self->_get_bin_size($size, ++$bin_num); # Increase bin number

      if (defined $bin_size) {
	$low_val += $bin_size;
	$high_val += $bin_size;
	$bin_mid = $low_val + ($bin_size / 2);
      } else {
	# $bin_size was undefined - we're out of bins, so stop.
	last;
      }
    }

    if (defined $bin_size) {
      # Set the X value
      $result[$bin_num]->[0] = $bin_mid
	unless (defined $result[$bin_num]->[0]);

      # Found a bin that the value belongs in
      # Add the y value to the bin

      # If method is 'max' store the value to the bin
      # only if it is greater than the bin's current value.
      if ($method eq 'max') {
	$result[$bin_num]->[1] = $val->[1]
	  unless ($result[$bin_num]->[1] > $val->[1]);
      } else {
	$result[$bin_num]->[1] += $val->[1];
	$count[$bin_num]++;
      }
    } else {
      # Stop if we're out of bins
      last;
    }
  }

  # Average the results if that method is being used
  if ($method eq 'average') {
    for (my $i = 0; $i <= $#result; $i++) {
      $result[$i]->[1] = $result[$i]->[1] / $count[$i]
	unless ($result[$i]->[1] == 0);
    }
  }

  return @result;
}

=item B<bin_up_by_date>

Bin up values by a number of days (can be fractional).

  @values_binned = OMP::PlotHelper->bin_up_by_date(days => 0.5,
                                                   method => 'sum'
                                                   values => \@values
                                                   startdate => $date);

Arguments should be provided in hash form.  The arguments are:

  days      - Number of days to bin up by.
  method    - Method to use when binning.  A string that is either
              'sum' or 'average'.
  values    - An array reference whose elements are arrays where the
              first element (the x value) is an object of class
              C<Time::Piece> to bin up by, and the second element
              (the y value) is a value to be binned.
  startdate - Date to start binning by.  Provide as a C<Time::Piece>
              object.  Defaults to the lowest date in the 'values'
              array.

Except for 'startdate', all arguments are required. Returns an array
where the elements are the value of each bin.

=cut

# Hey, everybody! This is a wrapper around the bin_up method -
# it just converts the x values from dates to numeric values
# and hands everything off to bin_up.

sub bin_up_by_date {
  my $self = shift;
  my %args = @_;
  my $days = $args{days};
  my $method = $args{method};
  my $start_date = $args{startdate};
  my @values = @{$args{values}};

  if ($start_date) {

    # Make sure startdate is a Time::Piece object
    throw OMP::Error::BadArgs("Argument 'startdate' must be a Time::Piece object")
      unless UNIVERSAL::isa($start_date, "Time::Piece");

    # Convert startdate to modified Julian date
    $start_date = $start_date->mjd;
  }

  # Convert the Time::Piece objects to modified Julian dates
  for my $val (@values) {

    # Check that we have Time::Piece objects
    throw OMP::Error::BadArgs("Must provide x values as Time::Piece objects")
      unless UNIVERSAL::isa($val->[0], "Time::Piece");

    $val->[0] = $val->[0]->mjd;
  }

  # Call bin_up to do the rest
  return $self->bin_up(size => $days,
		       method => $method,
		       startnum => $start_date,
		       values => \@values,);
}

=back

=head2 Internal Methods

=over 4

=item B<_get_bin_size>

Get the size of a bin.  First argumentt should be either a bin
size or an array reference containing bin sizes.  The second
argument is the array index of the bin.  If the first argument
is an array reference, the second argument is required.
Returns undef if the bin size could not be obtained.

=cut

sub _get_bin_size {
  my $self = shift;
  my $bin = shift;
  my $index = shift;

  my $size = (ref($bin) eq 'ARRAY' ? $bin->[$index] : $bin);

  throw OMP::Error::BadArgs("Bin size must be greater than 0")
    unless ($size > 0 or ! defined $size);

  return $size;
}

=back

=head1 AUTHOR

Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2004 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
