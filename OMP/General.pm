package OMP::General;

=head1 NAME

OMP::General - general purpose methods

=head1 SYNOPSIS

  use OMP::General

  $date = OMP::General->parse_date( "1999-01-05T05:15" );

=head1 DESCRIPTION

General purpose routines that are not associated with any particular
class but that are useful in more than one class.

For example, date parsing is required in the MSB class and in the query class.

=cut

use Time::Piece;

our $VERSION = (qw$Revision$)[1];

our $DEBUG = 0;

=head1 METHODS

There are no instance methods, only class (static) methods.

=over 4

=item B<parse_date>

Parse a ISO8601 format date (YYYY-MM-DDTHH:MM:SS) and return a time
object (usually a C<Time::Piece> object).

 $time = $msb->_parse_date( $date );

Returns C<undef> if the time could not be parsed.

The date is assumed to be in UT.

=cut

sub parse_date {
  my $self = shift;
  my $date = shift;

  # We can use Time::Piece->strptime but it requires an exact
  # format rather than working it out from context (and we don't
  # want an additional requirement on Date::Manip or something
  # since Time::Piece is exactly what we want for Astro::Coords)
  # Need to fudge a little

  # All arguments should have a day, month and year
  my $format = "%Y-%m-%d";

  # Now check for time
  if ($date =~ /T/) {
    # Date and time
    # Now format depends on the number of colons
    my $n = ( $date =~ tr/:/:/ );
    $format .= "T" . ($n == 2 ? "%T" : "%R");
  }

  # Now parse
  # Use Time::Piece::Sybase so that we can instantiate
  # the object in a state that can be used for sybase queries
  # This won't work if we use standard overridden gmtime.
  # Note also that this time is treated as "local" rather than "gm"
  my $time = eval { Time::Piece::Sybase->strptime( $date, $format ); };
  if ($@) {
    return undef;
  } else {
    # Convert to gmtime by adding on tzoffset
    # This is always a Time::Piece (another bug).
    $time -= $time->tzoffset;

    return bless $time, "Time::Piece::Sybase";
  }

}


=back

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

# For sybase format dates

package Time::Piece::Sybase;

our @ISA = qw/ Time::Piece /;

use overload '""' => "stringify";

sub stringify {
  my $self = shift;
  my $string = $self->strftime("%Y%m%d %T");
  return $string;
}



1;
