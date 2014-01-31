package OMP::DateSun;

=head1 NAME

OMP::DateSun - Date related methods based on sunrise, sunset.

=head1 SYNOPSIS

  use OMP::DateSun;

  $length =
    OMP::DateSun->determine_night_length( date => $date,
                                          tel => 'JCMT' );

=head1 DESCRIPTION

DateSun purpose routines that are not associated with any particular
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

use OMP::DateTools;
use Time::Piece ':override';
use Time::Seconds;
use POSIX qw/ /;

# Note we have to require this module rather than use it because there is a
# circular dependency with OMP::DateSun such that determine_host must be
# defined before OMP::Config BEGIN block can trigger
require OMP::Config;

our $VERSION = (qw$Revision$)[1];

our $DEBUG = 0;

=head1 METHODS

There are no instance methods, only class (static) methods.

=over 4

=item B<determine_night_length>

Given the start and end times for the night defined in the "freetimeut"
config parameter, return the nominal length of the night as a
Time::Seconds object.

  $length = OMP::DateSun->determine_night_length( date => $date,
                                                  tel => 'JCMT' );

Both arguments are mandatory. The date object is used for sunset/sunrise
times if required.

=cut

sub determine_night_length {
  my $class = shift;
  my %args = @_;

  throw OMP::Error::BadArgs("A telescope must be supplied else we can not determine the valid observing times")
    unless exists $args{tel};

  # key is different in api
  $args{start} = $args{date};

  # Get the range for this date
  my ($min, $max) = $class->_get_freeut_range( %args );

  return scalar ($max - $min );

}

=item B<determine_extended>

Given a start and end time, or a start time and duration, return
the time that should be charged to a project and the time that
should be treated as EXTENDED time.

  ($project, $extended) =
    OMP::DateSun->determine_extended(start => $start,
                                      end => $end,
                                      tel => 'JCMT',
                                    );

  ($project, $extended) =
    OMP::DateSun->determine_extended(start => $start,
                                      tel => 'UKIRT',
                                      duration => $duration);

($project, $extended) =
  OMP::DateSun->determine_extended(duration => $duration,
                                    tel => 'UKIRT',
                                    end => $end);


Telescope is mandatory, as are two of "start", "end" and "duration".
Input times are Time::Piece objects (for start and end) and Time::Seconds
objects (for duration) although and attempt is made to convert these
into objects if scalars are detected. Returns Time::Seconds objects.

=cut

# "freetimeut" is an undocumented argument for overriding the range without requirng
# a config file

sub determine_extended {
  my $class = shift;
  my %args = @_;

  throw OMP::Error::BadArgs("A telescope must be supplied else we can not determine the valid observing times")
    unless exists $args{tel};

  # Convert duration as number into duration as Time::Seconds
  if (exists $args{duration} && defined $args{duration} && not ref $args{duration}) {
    $args{duration} = new Time::Seconds( $args{duration});
  }

  for my $key (qw/ start end /) {
    if (exists $args{$key} && defined $args{$key} && not ref $args{$key}) {
      $args{$key} = OMP::DateTools->parse_date( $args{$key} );
    }
  }

  # Try to get the start time and the end time from the hash
  if (exists $args{start} && defined $args{start}) {

    if (exists $args{end} && defined $args{end}) {
      # We have start and end time already
      if (! exists $args{duration} || ! defined $args{duration}) {
        $args{duration} = $args{end} - $args{start};
      }
    } elsif (exists $args{duration} && defined $args{duration}) {
      # Get the end from the start and duration
      $args{end} = $args{start} + $args{duration}->seconds;
    }

  } elsif (exists $args{end} && defined $args{end}) {
    if (exists $args{duration} && defined $args{duration}) {
      $args{start} = $args{end} - $args{duration};
    }
  }

  # Check that we now have start, end and duration
  throw OMP::Error::BadArgs("Must supply 2 of start, end or duration")
    unless exists $args{start} && defined $args{start} &&
      exists $args{end} && defined $args{end} &&
        exists $args{duration} && defined $args{duration};


  # Check whether "free time" is currently disabled.  If so, return all
  # the time as "time spent" with zero extended time.

  my $freetime_disable = OMP::Config->getData('freetimedisable',
                                              telescope => $args{'tel'});

  if ($freetime_disable) {
    return ($args{'end'} - $args{'start'}, new Time::Seconds(0));
  }


  # Now we need to get the valid ranges
  my ($min, $max) = $class->_get_freeut_range( %args );

  throw OMP::Error::BadArgs("Error parsing the extended boundary string")
    unless defined $min && defined $max;

  # Now work out the extended time and project time
  # If the startobs is earlier than min time we need to check endobs
  my $extended = Time::Seconds->new(0);
  my $timespent;
  if ($args{start} < $min) {
    if ($args{end} < $min) {
      # This is entirely extended time
      $extended = $args{end} - $args{start};
      $timespent = new Time::Seconds(0);
    } else {
      # Split over shift boundary
      $timespent = $args{end} - $min;
      $extended = $min - $args{start};
    }

  } elsif ($args{end} > $max) {
    if ($args{start} > $max) {
      # Entirely extended time
      $timespent = new Time::Seconds(0);
      $extended = $args{end} - $args{start};
    } else {
      # Split over end of night boundary
      $timespent = $max - $args{start};
      $extended = $args{end} - $max;
    }

  } else {
    # Duration is simply the full range
    $timespent = $args{end} - $args{start};
  }

  return ($timespent, $extended);

}

# Work out what the range should be based.
# %args needs to have keys "tel" and "start" and optionally
# an override values "freetimeut".

sub _get_freeut_range {
  my $class = shift;
  my %args = @_;

  # We assume that the UT date matches that of the start and end times
  # For testing we allow an override so that we do not have to test
  # the Config system as well as this method
  my @range;
  if (exists $args{freetimeut} && defined $args{freetimeut}) {
    @range = @{ $args{freetimeut} };
  } else {
    @range = OMP::Config->getData('freetimeut',telescope=>$args{tel});
  }

  # Now convert to Time::Piece object
  my ($min, $max) = $class->_process_freeut_range( $args{tel}, $args{start}, @range );
  print "Min = $min  Max = $max  duration = ".(($max-$min)/3600)."\n" if $DEBUG;
return ($min, $max);
}

# Convert a range parameter as provided in the config file, to a date object.
# Input values can be given as either UT numbers HH:MM format or as the
# phrase "sunrise+NN" or "sunset+NN" where NN is in minutes.

# my ($datestart, $dateend) = $class->_process_freeut_range( $tel, $refdate, $range1, $range2 );

my %SUN_CACHE;

sub _process_freeut_range {
  my $class = shift;
  my ($telescope, $refdate, @ranges) = @_;

  throw OMP::Error::BadArgs("Must supply two values for the range argument of process_freeut_range")
    if (@ranges != 2 || !defined $ranges[0] || !defined $ranges[1]);

  # A cache of the Sun coordinate object if needed.
  my $Sun;

  my @processed;
  for my $r (@ranges) {
    my $out;
    if ($r =~ /^\s*\d\d:\d\d\s*$/) {
      # HH:MM
      $out = OMP::DateTools->parse_date($refdate->ymd . "T$r");
    } elsif ($r =~ /^(sunrise|sunset)\s*([\+\-]\s*\d+)\s*$/) {
      require Astro::Coords;
      my $mode = $1;
      my $offset = $2;
      if (!defined $Sun) {
        # need to create an Astro::Coords object for the sun
        $Sun = Astro::Coords->new( planet => 'sun');
        my $tel = Astro::Telescope->new( $telescope );
        $Sun->telescope( $tel );
        $Sun->datetime( $refdate );

        # assume that all observations are during the night not during the day(!) - probably bad
        # Get previous midday and then add 12 hours so that we can refer to next and previous
        # for sunset, sunrise.
        my $midday = $Sun->meridian_time( event => -1 );

        throw OMP::Error::FatalError("Error calculating transit time of Sun!")
          unless defined $midday;

        # now add 12 hours to get us roughly in the middle of the night
        $midday += 12 * 60 * 60;

        # and update that as the reference time
        $Sun->datetime( $midday );
      }

      my $cacheKey = $Sun->datetime->datetime;

      my $sundef = Astro::Coords::SUN_RISE_SET();
      my $event;
      my $eventKey;
      my $method;
      if ($mode =~ /rise$/) {
        $event = 1;
        $eventKey = "RISE";
        $method = "rise_time";
      } elsif ($mode =~ /set$/) {
        $event = -1;
        $eventKey = "SET";
        $method = "set_time";
      } else {
        throw OMP::Error::FatalError("Odd programming error");
      }

      if (exists $SUN_CACHE{$cacheKey}{$eventKey}) {
        $out = $SUN_CACHE{$cacheKey}{$eventKey};
      } else {
        $out = $Sun->$method( event => $event, horizon => $sundef );
        $SUN_CACHE{$cacheKey}{$eventKey} = $out;
      }

      # and add on the offset (convert to seconds)
      $out += $offset * 60;

    } else {
      throw OMP::Error::BadArgs("Error parsing the extended boundary string of '$r' (expect HH:MM or sunxxx+/-NNN");
    }

    throw OMP::Error::BadArgs("Error processing boundary event '$r'")
      unless defined $out;
    push(@processed, $out);
  }
  return @processed;
}

=back

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

1;

