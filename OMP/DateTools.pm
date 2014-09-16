package OMP::DateTools;

=head1 NAME

OMP::DateTools - Date, time, semester related methods.

=head1 SYNOPSIS

  use OMP::DateTools;

  $date = OMP::DateTools->parse_date( "1999-01-05T05:15" );
  $today = OMP::DateTools->today();

=head1 DESCRIPTION

DateTools purpose routines that are not associated with any particular
class but that are useful in more than one class.

For example, date parsing is required in the MSB class and in the query class.

=cut

use 5.006;
use strict;
use warnings;
use warnings::register;

# In some random cases with perl 5.6.1 (and possibly 5.6.0) we get
# errors such as:
#   Can't locate object method "SWASHNEW" via package "utf8"
#              (perhaps you forgot to load "utf8"?)
# Get round this by loading the utf8 module. Note that we solve the
# bug without contaminating our lexical namespace because the use
# line has the side effect of loading in the module that knows about
# the SWASHNEW method. Clearly crazy that the perl core can need this
# without loading it first. Fixed in perl 5.8.0. These are triggered
# because the XML parser and the web server provide UTF8 characters
# without loading associated handler code.
if ($] >= 5.006 && $] < 5.008) {
  eval "use utf8;";
}
use Carp;
use OMP::Constants qw/ :logging /;
use Time::Piece ':override';
use Time::Seconds qw/ ONE_DAY /;
use POSIX qw/ /;

our $VERSION = (qw$Revision$)[1];

our $DEBUG = 0;

=head1 METHODS

There are no instance methods, only class (static) methods.

=head2 Dates

=over 4

=item B<parse_date>

Parse a ISO8601 format date (YYYY-MM-DDTHH:MM:SS) and return a time
object (usually a C<Time::Piece> object).

 $time = $msb->_parse_date( $date );

Returns C<undef> if the time could not be parsed.
If the argument is already a C<Time::Piece> object it is returned
unchanged if the time is a UT time, else a new object is returned
using a UT representation (this does not change the epoch).

It will also recognize a Sybase style date: 'Mar 15 2002  7:04AM'
and a simple YYYYMMDD.

The date is assumed to be in UT. If the optional second argument is true,
the date will be treated as a local time and converted to UT on return.

  $ut = OMP::DateTools->parse_date( $localdate, 1);

=cut

sub parse_date {
  my $self = shift;
  my $date = shift;
  my $islocal = shift;

  # If we already have a Time::Piece return
  # We should convert to a UT date representation
  if (UNIVERSAL::isa( $date, "Time::Piece")) {
    if ($date->[Time::Piece::c_islocal]) {
      # Convert it to UT
      my $epoch = $date->epoch;
      $date = gmtime( $epoch );
    }
    return bless $date, "Time::Piece::Sybase"
  }

  # Clean trailing and leading spaces from the string and remove new lines
  $date =~ s/^\s+//;
  $date =~ s/\s+$//;

  # We can use Time::Piece->strptime but it requires an exact
  # format rather than working it out from context (and we don't
  # want an additional requirement on Date::Manip or something
  # since Time::Piece is exactly what we want for Astro::Coords)
  # Need to fudge a little

  my $format;

  # Need to disambiguate ISO date from Sybase date
  if ($date =~ /\d\d\d\d-\d\d-\d\d/) {
    # ISO

    # All arguments should have a day, month and year
    $format = "%Y-%m-%d";

    # Now check for time
    if ($date =~ /T/) {
      # Date and time
      # Now format depends on the number of colons
      my $n = ( $date =~ tr/:/:/ );
      $format .= "T" . ($n == 2 ? "%T" : "%R");
    }
    print "$date = ISO date with format $format\n" if $DEBUG;

  } elsif ($date =~ /^\d\d\d\d\d\d\d\d\b/) {
    # YYYYMMDD format

    $format = "%Y%m%d";

    if ($date =~ /\s\d\d:\d\d:\d\d$/) {
      $format .= " %H:%M:%S";
      print "$date = YYYYMMDD HH:MM:SS with format $format\n" if $DEBUG;
    } else {
      print "$date = YYYYMMDD with format $format\n" if $DEBUG;
    }

  } elsif ($date =~ /^\w+\s+\d+\s+\d+\s+\d+:\d+[ap]m/i) {
    # Sybase date
    # Mar 15 2002  7:04AM

    # On OSX %t seems to mean a real tab but on linux %t seems to be interpreted
    # as "any number of spaces". Replace all spaces with underscores before doing
    # the match.
    $date =~ s/\s+/_/g;

    $format = "%b_%d_%Y_%I:%M%p";

    print "$date = Sybase with Format $format\n" if $DEBUG;
  } elsif ($date =~ /^\w+\s+\d+\s+\d+\s+\d+:\d+:\d+:\d+[ap]m/i) {
    # Sybase Long Date from ObsLog
    # Mar 14 2002 7:04:50:000AM

    # Help %t definition
    $date =~ s/\s+/_/g;

    $format = "%b_%d_%Y_%I:%M:%S:000%p";
    print "$date = Sybase Long date with Format $format\n" if $DEBUG;
  } else {
    print ">>>>>>>>>>>>>>> $date Was Not recognized\n" if $DEBUG;
    return undef;
  }

  # If Time::Piece worked as advertised (broken between v1.08 and v1.11)
  # the following code would work. For now we need to kluge with tzoffset.
  # Create a dummy Time::Piece in the required time zone
  #my $dummy = ( $islocal ? Time::Piece::localtime(0) : Time::Piece::gmtime(0));
  #my $time = eval { $dummy->strptime( $date, $format ); };
  #if ($@) {
  #  print "Could not parse\n" if $DEBUG;
  #  return undef;
  #} else {
  #  # if we got a local, convert it to UTC
  #  if ($islocal) {
  #    $time = Time::Piece::gmtime( $time->epoch );
  #  }
  #}

  # Now need to bless into class Time::Piece::Sybase
  #return bless $time, "Time::Piece::Sybase";

  # Now parse
  # Use Time::Piece::Sybase so that we can instantiate
  # the object in a state that can be used for sybase queries
  # This won't work if we use standard overridden gmtime.
  # Note also that this time is treated as "local" rather than "gm"
  my $time = eval { Time::Piece->strptime( $date, $format ); };
  if ($@) {
    print "Could not parse\n" if $DEBUG;
    return undef;
  } else {
    # Note that the above constructor actually assumes the date
    # to be parsed is a local time not UTC. To switch to UTC
    # simply get the epoch seconds and the timezone offset
    # and run gmtime
    # Sometime around v1.07 of Time::Piece the behaviour changed
    # to return UTC rather than localtime from strptime!
    # The joys of backwards compatibility.
    # If we have been supplied a localtime we just need to change the
    # representation rather than the epoch if we have a localtime
    # if we get a UT back but had a local time to start with we
    # need to correct.
    # In fact, as of V1.08, strptime will be UTC if called without
    # an object, but inherit the object if called as a instance method.
    # So we could do this using a dummy local or UTC object.
    my $epoch = $time->epoch;
    my $tzoffset = $time->tzoffset;
    if ($islocal) {
      # We are supposed to have a local time, if we have a UT
      # We need to subtract the timezone and then convert the
      # time to a localtime
      if (! $time->[Time::Piece::c_islocal]) {
        if ($tzoffset->seconds == 0) {
          # this may well be because Time::Piece v1.10 decided that
          # tzoffset should return 0 if you were asking via a UTC
          # object
          my $dummy = Time::Piece::localtime($epoch);
          $tzoffset = $dummy->tzoffset;
        }
        $epoch -= $tzoffset->seconds;
      }

    } else {
      # We are supposed to have a UT, if we do not, add on the timezone
      if ($time->[Time::Piece::c_islocal]) {
        $epoch += $tzoffset->seconds;
      }
    }

    # Convert back to a gmtime using the reference epoch
    $time = gmtime( $epoch );

    print "Got result: " . $time->datetime ."\n" if $DEBUG;

    # Now need to bless into class Time::Piece::Sybase
    return bless $time, "Time::Piece::Sybase";

  }

}

=item B<today>

Return the UT date for today in C<YYYY-MM-DD> format.

  $today = OMP::DateTools->today();

If true, the optional argument will cause the routine to return
a Time::Piece object rather than a string.

  $obj = OMP::DateTools->today( 1 );

=cut

sub today {
  my $class = shift;
  my $useobj = shift;
  my $time = gmtime();

  my $string = $time->ymd;

  if ($useobj) {
    return $class->parse_date( $string );
  } else {
    return $string;
  }
}

=item B<yesterday>

Return the UT date for yesterday in C<YYYY-MM-DD> format.

  $y = OMP::DateTools->yesterday();

If true, the optional argument will cause the routine to return
a Time::Piece object (midnight on the specified date) rather than
a string.

  $obj = OMP::DateTools->yesterday( 1 );

=cut

sub yesterday {
  my $class = shift;
  my $useobj = shift;

  # Get today as an object (probably more efficient to just use gmtime
  # here rather than the today() method since we are not interested in
  # hms anyway and using gmtime will result in one less parse
  my $time = gmtime;

  # Convert to yesterday
  $time -= ONE_DAY;

  # Convert to a string
  my $string = $time->ymd;


  if ($useobj) {
    return $class->parse_date( $string );
  } else {
    return $string;
  }

}

=item B<display_date>

Given a C<Time::Piece> object return a string displaying the date in
YYYYMMDD HH:MM:SS format and append the appropriate timezone representation.

  $datestring = OMP::DateTools->display_date($date);

=cut

sub display_date {
  my $class = shift;
  my $date = shift;

  # Decide whether timezone designation should be 'UT' or local time
  my $tz;
  if ($date->[Time::Piece::c_islocal]) {
    $tz = $date->strftime("%Z");
  } else {
    $tz = "UT";
  }

  my $string = $date->strftime("%Y%m%d %T");

  return "$string $tz";
}

=item B<mail_date>

Return the local date and time in the format specified in RFC822, for use
in an email Date header.

  $datestring = OMP::DateTools->mail_date();

=cut

sub mail_date {
  my $class = shift;

  my $string = POSIX::strftime("%a, %d %b %Y %H:%M:%S %z", localtime);

  return $string;
}

=item B<determine_utdate>

Determine the relevant UT date to use. If the argument
can be parsed as a UT date by C<parse_date> the object corresponding
to that date is returned. If no date can be parsed, or no argument
exists a time object corresponding to the current UT date is returned.

  $tobj = OMP::DateTools->determine_utdate( $utstring );
  $tobj = OMP::DateTools->determine_utdate();

Hours, minutes and seconds are ignored.

A warning is issued if the date is unparseable.

=cut

sub determine_utdate {
  my $class = shift;
  my $utstr = shift;

  my $date;
  if (defined $utstr) {
    $date = $class->parse_date( $utstr );
    if (defined $date) {
      # Have a date object, check that we have no hours, minutes
      # or seconds
      if ($date->hour != 0 || $date->min != 0 || $date->sec != 0) {
        # Force pure date
        $date = $class->parse_date( $date->ymd );
      }
    } else {
      # did not parse, use today
      warn "Unable to parse UT date $utstr. Using today's date.\n";
      $date = $class->today( 1 );
    }
  } else {
    $date = $class->today( 1 );
  }

  return $date;
}

=back

=head2 Semesters

=over 4

=item B<determine_semester>

Given a date determine the current semester.

  $semester = OMP::DateTools->determine_semester( date => $date, tel => 'JCMT' );

Date should be of class C<Time::Piece> or a string in I<yyyymmdd>
format, and should be in UT. The current date is used if none is
supplied.

A telescope option is supported since semester boundaries are a
function of telescope.  If no telescope is provided, a telescope of
"PPARC" will be assumed. This is a special class of semester selection
where the year is split into two parts (labelled "A" and "B")
beginning in February and ending in August. The year is prefixed to
the A/B label as a two digit year. eg 99B or 05A.

Other supported telescopes are JCMT (an alias for PPARC) and UKIRT
(some special boundaries in some semesters due to instrument
deliveries).

Note that currently the PPARC calculation is probably incorrect for
telescopes other than Hawaii. This is because the semester technically
starts in local time not UT. For example, 1st Feb HST is the start of
the JCMT semester A but this is treated as 2nd Feb UT for this
calculation.

=cut

# Hard-wired boundaries that can not be calculated using an algorithm
# Indexed by telescope, then semester name then YYYYMMDD date in 2 element array
# These are inclusive numbers
my %SEM_BOUND = (
                 UKIRT => {
                           # 04A started early and finished very late because of WFCAM
                           # this also forces 03B to finish early
                           # Note that we do not attempt to indicate undef when the
                           # date is the normal date but with a new uppoer or lower bound
                           '03B' => [ 20030802, 20040116 ],
                           '04A' => [ 20040117, 20041001 ],
                           '04B' => [ 20041002, 20041101 ],
                           '05A' => [ 20041102, 20050822 ],
                           '05B' => [ 20050823, 20060209 ],
                           '06A' => [ 20060210, 20060801 ],
                           '06B' => [ 20060802, 20070401 ],
                           '09A' => [ 20090126, 20090728 ],
                           '09B' => [ 20090727, 20100131 ],
                          },
                 JCMT  => {
                           '05B' => [ 20050802, 20060214 ],
                           '06A' => [ 20060214, 20060801 ], # shutdown
                           '06B' => [ 20060802, 20070301 ],
                           '08A' => [ 20080129, 20080801 ],
                           '14A' => [ 20140202, 20141001 ],
                           '14B' => [ 20141002, 20150201 ],
                          },
                );


sub determine_semester {
  my $self = shift;
  my %args = @_;
  my $date = $args{date};
  if (defined $date) {

    croak 'determine_semester: Date should be of class Time::Piece'
        . qq[ or a "yyyymmdd" formatted string rather than "$date"]
      unless UNIVERSAL::isa($date, "Time::Piece")
          or $date =~ m/
                        ^\d{4}
                        (?: [01]\d | 1[0-2])
                        (?: [0-2]\d | 3[01])
                        $
                      /x;

  } else {
    $date = gmtime();
  }

  my $tel = "PPARC";
  $tel = uc($args{tel}) if (exists $args{tel} && defined $args{tel});

  # First we can automatically run through any special semesters
  # in a generic search. This will have minimal impact on a telescope
  # that has never had a special semester boundary (apart from the
  # requirement to convert date to YYYYMMDD only once)

  my $ymd = $date =~ m/^\d{8}$/
            ? $date
            : $date->strftime("%Y%m%d");

  if (exists $SEM_BOUND{$tel}) {
    for my $lsem (keys %{ $SEM_BOUND{$tel} } ) {
      if ($ymd >= $SEM_BOUND{$tel}{$lsem}[0] &&
          $ymd <= $SEM_BOUND{$tel}{$lsem}[1] ) {
        # we have a hit
        return $lsem;
      }
    }
  }

  # This is the standard PPARC calculation
  if ($tel eq 'PPARC' || $tel eq 'JCMT' || $tel eq 'UKIRT') {
    return _determine_pparc_semester( $date );
  } else {
    croak "Unrecognized telescope '$tel'. Should not happen.\n";
  }

}

# Private helper sub for determine_semester
# implements the standard PPARC calculation
# Probably an off by one error since the PPARC boundaries are local time
# but the calculation here assumes Hawaii + UT
# Takes a Time::Piece object
# Returns the semester 04b 04a etc
# Not a class method

sub _determine_pparc_semester {
  my $date = shift;

  #  Parse date into 4-digit year & 4-digit month.day portions.
  my ( $yyyy, $mmdd );

  if ( $date =~ m/^ (\d{4}) (\d{4}) $/x ) {

    ( $yyyy, $mmdd ) = ( "$1", "$2" );
  }
  else {

    $yyyy = $date->year;
    $mmdd = $date->mon . sprintf( "%02d", $date->mday );
  }

  # Calculate previous year
  my $prev_yyyy = $yyyy - 1;

  # Two digit years
  my $yy = substr( $yyyy, 2, 2);
  my $prevyy = substr( $prev_yyyy, 2, 2);

  # Need to put the month in the correct
  # semester. Note that 199?0201 is in the
  # previous semester, same for 199?0801
  my $sem;
  if ($mmdd > 201 && $mmdd < 802) {
    $sem = "${yy}A";
  } elsif ($mmdd < 202) {
    $sem = "${prevyy}B";
  } else {
    $sem = "${yy}B";
  }

  return $sem;
}

# Convert PPARC style semester NN[AB] to UT dates
# eg 04B becomes 20040802 to 20050201
# Takes a semester name as argument

sub _determine_pparc_semester_boundary {
  my $sem = uc(shift);

  # First convert alphabetic historical semesters to
  # modern format. Only go back to semester V
  my %oldsem = ( V => '92A', W => '92B', X => '93A', Y => '93B' );
  my $old;
  if (exists $oldsem{$sem}) {
    $old = 1; # we have an old semester label
    $sem = $oldsem{$sem};
  }

  if ($sem =~ /^(\d\d)([AB])$/) {
    my $year = $1;
    my $ab   = $2;

    # Convert year to numeric year (remove "0" prefix sinc "09" and "08" are bad octal)
    my $ny   = $year;
    $ny =~ s/^0//;

    # Convert into a 4 digit year. We are in trouble in 2074 but I'm not going to
    # worry about it
    if ($old || $ny > 73) {
      $year = "19" . $year;
    } else {
      $year = "20" . $year;
    }

    # Boundaries without the year prefix
    # incyr indicates whether the year should be incremented prior to
    # concatenation
    my %bound = (
                 A => {
                       incyr  => [ 0, 0 ],
                       suffix => [qw/ 0202 0801 /],
                      },
                 B => {
                       incyr  => [ 0, 1 ],
                       suffix => [qw/ 0802 0201 /],
                      },
                );

    my %semdetails = %{ $bound{$ab} };
    my @bounds = map { ( $year + $semdetails{incyr}[$_] ) . $semdetails{suffix}[$_] } (0,1);

  } else {
    croak "This semester ($sem) does not look like a PPARC style semester designation";
  }

}

=item B<semester_boundary>

Returns a Time::Piece object for both the start of the semester and
the end of the semester (both dates are in the semester such that if
they are passed to C<determine_semester> the semester returned will
match the semester given to this routine).

  ($begin, $end) = OMP::DateTools->semester_boundary( semester => '04B',
                                                    tel => 'JCMT' );

The telescope is mandatory. If a semester is not specified the current semester
is used. 'PPARC' is a special telescope used for generic PPARC semester boundaries.

If semester is a reference to an array, the beginning and end dates will refer
to the start of the earliest semester and the end of the latest semester. An exception
will be thrown if the semesters themselves are not contiguous.

  ($begin, $end) = OMP::DateTools->semester_boundary( semester => [qw/ 04A 04B/],
                                                    tel => 'UKIRT' );

=cut

sub semester_boundary {
  my $class = shift;
  my %args = @_;

  # we can not do anything without a telescope
  throw OMP::Error::BadArgs( "Must supply a telescope!" )
    unless exists $args{tel};

  # do we have a semester? If not, get the current value
  $args{semester} = $class->determine_semester( tel => $args{tel} )
    unless exists $args{semester};

  $args{tel}      = uc($args{tel});

  # The semester can either be a single value or an array reference
  my @sem = (ref($args{semester}) ? @{ $args{semester}} : $args{semester} );

  my @dates;
  for my $sem (@sem) {
    $sem = uc($sem);

    # Do fast lookup
    if (exists $SEM_BOUND{$args{tel}}{$sem} ) {
      push(@dates, $SEM_BOUND{$args{tel}}{$sem} );
      next;
    }

    # telescope specific
    if ($args{tel} eq 'PPARC' || $args{tel} eq 'JCMT' || $args{tel} eq 'UKIRT') {
      push(@dates, [ _determine_pparc_semester_boundary( $sem ) ] );
    } else {
      croak "Unrecognized telescope '$args{tel}'. Should not happen.\n";
    }

  }

  # Check continuity. First sort
  @dates = sort { $a->[0] <=> $b->[0] } @dates;

  my ($start, $end) = @{ $dates[0] };
  for my $d (1..$#dates) {
    # check continuity
    if ($dates[$d]->[0] - $end > 1) {
      throw OMP::Error::FatalError("Gap in semester range specified to semester_boundary method");
    }
    $end = $dates[$d][1];
  }

  # Return
  return  map { OMP::DateTools->parse_date( $_  ) } ($start, $end);

}

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>,
Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>,

=head1 COPYRIGHT

Copyright (C) 2007 Science and Technology Facilities Council.
All Rights Reserved.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the
Free Software Foundation, Inc., 59 Temple Place, Suite 330,
Boston, MA  02111-1307  USA


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

# Unable to integrate this pretty_print function into the Time::Piece
# distribution so we need to add it here

package Time::Seconds;
no warnings 'redefine';
sub pretty_print {
    my $s = shift;
    my $fmt = shift || "h";
    $fmt = lc(substr($fmt,0,1));

    my %lut = (
               "y" => ONE_YEAR,
               "d" => ONE_DAY,
               "h" => ONE_HOUR,
               "m" => ONE_MINUTE,
               "s" => 1.0,
              );
    my @precedence = (qw/y d h m s/);

    # if the required format is not known convert it to "s"
    $fmt = "s" unless exists $lut{$fmt};

    my $string = '';
    my $go = 0; # indicate when to start
    my $rem = $s->seconds; # number of seconds remaining

    # Take care of any sign
    my $sgn = '';
    if ($rem < 0) {
      $rem *= -1;
      $sgn = '-';
    }

    # Now loop over each allowed format
    for my $u (@precedence) {

        # loop if we havent triggered yet
        $go = 1 if $u eq $fmt;
        next unless $go;

        # divide the current number of seconds by the number of seconds
        # in the unit and store the integer
        my $div = int( $rem / $lut{$u} );

        # calculate the new remainder
        $rem -= $div * $lut{$u};

        # append the value to the string if non-zero
        # and we havent already appended something. ie
        # do not allow 0h52m15s but do allow 1h0m2s
        $string .= $div . $u if ($div > 0 || $string);

    }

    return $sgn . $string;

}

1;
