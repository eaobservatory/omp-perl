package OMP::General;

=head1 NAME

OMP::General - general purpose methods

=head1 SYNOPSIS

  use OMP::General

  $date = OMP::General->parse_date( "1999-01-05T05:15" );
  $today = OMP::General->today();

=head1 DESCRIPTION

General purpose routines that are not associated with any particular
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
if ($] >= 5.006 || $] < 5.008) {
  eval "use utf8;";
}
use Carp;
use OMP::Constants qw/ :logging /;
use OMP::Range;
use Term::ANSIColor qw/ colored /;
use Time::Piece ':override';
use Net::Domain qw/ hostfqdn /;
use Net::hostent qw/ gethost /;
use File::Spec;
use Fcntl qw/ :flock /;
use OMP::Error qw/ :try /;
use Time::Seconds qw/ ONE_DAY /;
use Text::Balanced qw/ extract_delimited /;
use OMP::SiteQuality;

require HTML::TreeBuilder;
require HTML::FormatText;

# Note we have to require this module rather than use it because
# there is a circular dependency with OMP::General such that determine_host
# must be defined before OMP::Config BEGIN block can trigger
require OMP::Config;
require OMP::UserServer;

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

  $ut = OMP::General->parse_date( $localdate, 1);

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
  chomp($date);
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
    print "$date = YYYYMMDD with format $format\n" if $DEBUG;
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
    # need to correct
    my $epoch = $time->epoch;
    my $tzoffset = $time->tzoffset;
    if ($islocal) {
      # We are supposed to have a local time, if we have a UT
      # We need to subtract the timezone and then convert the
      # time to a localtime
      if (! $time->[Time::Piece::c_islocal]) {
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

  $today = OMP::General->today();

If true, the optional argument will cause the routine to return
a Time::Piece object rather than a string.

  $obj = OMP::General->today( 1 );

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

  $y = OMP::General->yesterday();

If true, the optional argument will cause the routine to return
a Time::Piece object (midnight on the specified date) rather than
a string.

  $obj = OMP::General->yesterday( 1 );

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

  $datestring = OMP::General->display_date($date);

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

  $datestring = OMP::General->mail_date();

=cut

sub mail_date {
  my $class = shift;

  my $date = localtime;
  my $string = $date->strftime("%a, %d %b %Y %H:%M:%S %z");

  return $string;
}

=item B<determine_extended>

Given a start and end time, or a start time and duration, return
the time that should be charged to a project and the time that 
should be treated as EXTENDED time.

  ($project, $extended) = OMP::General->determine_extended(start => $start,
                                                           end => $end,
							   tel => 'JCMT',
							  );

  ($project, $extended) = OMP::General->determine_extended(start => $start,
							   tel => 'UKIRT',
                                                           duration => $duration);

  ($project, $extended) = OMP::General->determine_extended(duration => $duration,
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
      $args{$key} = $class->parse_date( $args{$key} );
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

  # Now we need to get the valid ranges
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
  my $min = $class->parse_date($args{start}->ymd . "T$range[0]");
  my $max = $class->parse_date($args{end}->ymd . "T$range[1]");

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

=item B<determine_utdate>

Determine the relevant UT date to use. If the argument
can be parsed as a UT date by C<parse_date> the object corresponding
to that date is returned. If no date can be parsed, or no argument
exists a time object corresponding to the current UT date is returned.

  $tobj = OMP::General->determine_utdate( $utstring );
  $tobj = OMP::General->determine_utdate();

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

=head2 Strings

=over 4

=item B<prepare_for_insert>

Convert a text string into one that is ready to be stored in
the database.

  $insertstring = OMP::General->prepare_for_insert( $string );

This method converts the string as follows:

=over 8

=item *

Converts a single quote into the HTML entity &apos;

=item *

Converts a carriage return into <lt>br<gt>.

=item *

Strips all ^M characters.

=back

The returned string is then ready to be inserted into the database.

=cut

sub prepare_for_insert {
  my $class = shift;
  my $string = shift;

  $string =~ s/\'/\&apos;/g;
  $string =~ s/\015//g;
  $string =~ s/\n/<br>/g;

  return $string;
}

=back

=head2 Hosts

=over 4

=item B<determine_host>

Determine the host and user name of the person either running this
task. This is either determined by using the CGI environment variables
(REMOTE_ADDR and REMOTE_USER) or, if they are not set, the current
host running the program and the associated user name.

  ($user, $host, $email) = OMP::General->determine_host;

The user name is not always available (especially if running from
CGI).  The email address is simply determined as C<$user@$host> and is
identical to the host name if no user name is determined.

An optional argument can be used to disable remote host checking
for CGI. If true, this method will return the host on which
the program is running rather than the remote host information.

  ($user, $localhost, $email) = OMP::General->determine_host(1);

If the environment variable C<$OMP_NOGETHOST> is set this method will
return a hostname of "localhost" if we are not running in a CGI
context, or the straight IP address if we are. This is used when no
network connection is available and you do not wish to wait for a
timeout from C<gethostbyname>.

=cut

sub determine_host {
  my $class = shift;
  my $noremote = shift;

  # Try and work out who is making the request
  my ($user, $addr);

  if (!$noremote && exists $ENV{REMOTE_ADDR}) {
    # We are being called from a CGI context
    my $ip = $ENV{REMOTE_ADDR};

    # Try to translate number to name if we have network
    if (!exists $ENV{OMP_NOGETHOST}) {
      $addr = gethost( $ip );

      # if we have nothing just use the IP
      $addr = ( (defined $addr && ref $addr) ? $addr->name : $ip );
      $addr = $ip if !$addr;

    } else {
      # else default to the IP address
      $addr = $ip;
    }

    # User name (only set if they have logged in)
    $user = (exists $ENV{REMOTE_USER} ? $ENV{REMOTE_USER} : '' );

  } elsif (exists $ENV{OMP_NOGETHOST}) {
    # Do not do network lookup
    $addr = "localhost.localdomain";
    $user = (exists $ENV{USER} ? $ENV{USER} : '' );

  } else {
    # For taint checking with Net::Domain when etc/resolv.conf
    # has no domain
    local $ENV{PATH} = "/bin:/usr/bin:/usr/local/bin" 
      unless ${^TAINT} == 0;

    # localhost
    $addr = hostfqdn;
    $user = (exists $ENV{USER} ? $ENV{USER} : '' );

  }

  # Build a pseudo email address
  my $email = '';
  $email = $addr if $addr;
  $email = $user . "@" . $email if $user;

  $email = "UNKNOWN" unless $email;

  # Replace space with _
  $email =~ s/\s+/_/g;

  return ($user, $addr, $email);
}

=item B<is_host_local>

Returns true if the host accessing this page is local, false
if not. The definition of "local" means that either there are
no dots in the domainname (eg "lapaki" or "ulu") or the domain
includes one of the endings specified in the "localdomain" config
setting.

  print "local" if OMP::General->is_host_local

Usually only relevant for CGI scripts where REMOTE_ADDR is
used.

=cut

sub is_host_local {
  my $class = shift;

  my @domain = $class->determine_host();

  # if no domain, assume we are really local (since only a host name)
  return 1 unless $domain[1];

  # Also return true if the domain does not include a "."
  return 1 if $domain[1] !~ /\./;

  # Now get the local definition of allowed remote hosts
  my @local = OMP::Config->getData('localdomain');

  # See whether anything in @local matches $domain[1]
  if (grep { $domain[1] =~ /$_$/i } @local) {
    return 1;
  } else {
    return 0;
  }
}

=back

=head2 Time Allocation Bands

These methods are now deprecated in favour of the C<OMP::SiteQuality>
class. Please do not use these in new code.

=over 4

=item B<determine_band>

Determine the time allocation band. This is used for scheduling
and for decrementing observing time.

  $band = OMP::General->determine_band( %details );

The band is determined from the supplied details. Recognized
keys are:

  TAU       - the current CSO tau
  TAURANGE  - OMP::Range object containing a tau range
  TELESCOPE - name of the telescope

Currently TAU or TAURANGE are only used if TELESCOPE=JCMT. In all
other cases (and if TELESCOPE is not supplied) the band returned is 0.
If TELESCOPE=JCMT either TAU or TAURANGE must be present. An exception
is thrown if neither TAU nor TAURANGE are present.

From a single tau value it is not possible to distinguish a split band
(e.g. "2*") from a "normal" band (e.g. "2"). In these cases the normal
band is always returned.

If a tau range is supplied, this method will return an array of all
bands that present in that range (including partial bands). In this
case starred bands will be recognized correctly.

=cut

sub determine_band {
  my $self = shift;
  my %details = @_;
  warnings::warnif( "OMP::General::determine_band deprecated. Use OMP::SiteQuality instead");
  return OMP::SiteQuality::determine_tauband( @_ );
}

=item B<get_band_range>

Given a band name, return the OMP::Range object that defines the band.

  $range = OMP::General->get_band_range($telescope, @bands);

If multiple bands are supplied the range will include the extreme values.
(BUG: no check is made to determine whether the bands are contiguous)

Only defined for JCMT. Returns an unbounded range (lowe limit zero) for
any other telescope.

Returns undef if the band is not known.

=cut

sub get_band_range {
  my $class = shift;
  my $tel = shift;
  my @bands = @_;
  warnings::warnif( "OMP::General::get_band_range deprecated. Use OMP::SiteQuality instead");
  return OMP::SiteQuality::get_tauband_range( $tel, @_);
}

=back

=head2 Semesters

=over 4

=item B<determine_semester>

Given a date determine the current semester.

  $semester = OMP::General->determine_semester( date => $date, tel => 'JCMT' );

Date should be of class C<Time::Piece> and should be in UT. The
current date is used if none is supplied.

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
			  },
                 JCMT  => {
                           '05B' => [ 20050802, 20060214 ],
                           '06A' => [ 20060214, 20060801 ], # shutdown
                          },
		);


sub determine_semester {
  my $self = shift;
  my %args = @_;
  my $date = $args{date};
  if (defined $date) {
    croak "determine_semester: Date should be of class Time::Piece rather than \"$date\""
      unless UNIVERSAL::isa($date, "Time::Piece");
  } else {
    $date = gmtime();
  }

  my $tel = uc($args{tel});
  $tel = 'PPARC' unless $tel;

  # First we can automatically run through any special semesters
  # in a generic search. This will have minimal impact on a telescope
  # that has never had a special semester boundary (apart from the
  # requirement to convert date to YYYYMMDD only once)
  my $ymd = $date->strftime("%Y%m%d");
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

  # 4 digit year
  my $yyyy = $date->year;

  # Month plus two digit day
  my $mmdd = $date->mon . sprintf( "%02d", $date->mday );

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

    # Convert into a 4 digit year. We are in trouble in 2094 but I'm not going to
    # worry about it
    if ($old || $ny > 93) {
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

  ($begin, $end) = OMP::General->semester_boundary( semester => '04B',
                                                    tel => 'JCMT' );

The telescope is mandatory. If a semester is not specified the current semester
is used. 'PPARC' is a special telescope used for generic PPARC semester boundaries.

If semester is a reference to an array, the beginning and end dates will refer
to the start of the earliest semester and the end of the latest semester. An exception
will be thrown if the semesters themselves are not contiguous.

  ($begin, $end) = OMP::General->semester_boundary( semester => [qw/ 04A 04B/],
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
  return  map { OMP::General->parse_date( $_  ) } ($start, $end);

}

=back

=head2 Projects

=over 4

=item B<infer_projectid>

Given a subset of a project ID attempt to determine the actual
project ID.

  $proj = OMP::General->infer_projectid( projectid => $input,
					 telescope => 'ukirt',
				       );

  $proj = OMP::General->infer_projectid( projectid => $input,
					 telescope => 'ukirt',
					 semester => $sem,
				       );

  $proj = OMP::General->infer_projectid( projectid => $input,
					 telescope => 'ukirt',
					 date => $date,
				       );

If telescope is not supplied it is guessed.  If the project ID is just
a number it is assumed to be part of a UKIRT style project. If it is a
number with a letter prefix it is assumed to be the JCMT style (ie u03
-> m01bu03) although a prefix of "s" is treated as a UKIRT service
project and expanded to "u/serv/01" (for "s1"). If the supplied ID is
ambiguous (most likely from a UH ID since both JCMT and UKIRT would
use a shortened id of "h01") the telescope must be supplied or else
the routine will croak. Japanese UKIRT programs can be abbreviated
as "j4" for "u/02b/j4". JCMT service programs can be abbreviated with
the letter "s" and the country code ("su03" maps to s02bu03, valid
prefixes are "su", "si", and "sc". Dutch service programmes can not
be abbreviated). In general JCMT service programs do not really benefit
from abbreviations since in most cases the current semester is not
appropriate.

The semester is determined from a "semester" key directly or from a date.
The current date is used if no date or semester is supplied.
The supplied date must be a C<Time::Piece> object.

Finally, if the number is prefixed by more than one letter 
(with the exception of s[uic] reserved for JCMT service) it is
assumed to indicate a special ID (usually reserved for support
scientists) that is not telescope specific (although be aware that
the Observing Tool can not mix telescopes in a single science
program even though the rest of the OMP could do it). The only
translation occuring in these cases is to pad the digit to two
characters.

If a project id consists entirely of alphabetic characters it
will be returned without modification.

=cut

sub infer_projectid {
  my $self = shift;
  my %args = @_;

  # The supplied ID
  my $projid = $args{projectid};
  croak "Must supply a project ID"
    unless defined $projid;

  # Make sure its not complete already
  return $projid if defined $self->extract_projectid( $projid );

  # If it's a special reserved ID (two characters + digit)
  # and *not* an abbreviated JCMT service programme
  # return it - padding the number)
  if ($projid !~ /^s[uic]\d\d/i && 
      $projid =~ /^([A-Za-z]{2,}?)(\d+)$/) {
    return $1 . sprintf("%02d", $2);
  }

  # We need a guess at a telescope before we can guess a semester
  # In most cases the supplied ID will be able to distinguish
  # JCMT from UKIRT (for example JCMT has a letter prefix
  # such as "u03" whereas UKIRT mainly has a number "03" or "3")
  # The exception is for UH where both telescopes have 
  # an "h" prefix. Additinally "s" prefix is UKIRT service.
  my $tel;
  if (exists $args{telescope}) {
    $tel = uc($args{telescope});
  } else {
    # Guess
    if ($projid =~ /^[sj]?\d+$/i) {
      $tel = "UKIRT";
    } elsif ($projid =~ /^s?[unci]\d+$/i) {
      $tel = "JCMT";
    } else {
      croak "Unable to determine telescope from supplied project ID: $projid is ambiguous";
    }
  }

  # Now that we have a telescope we can find the semester
  my $sem;
  if (exists $args{semester}) {
    $sem = $args{semester};
  } elsif (exists $args{date}) {
    $sem = $self->determine_semester( date => $args{date}, tel => $tel );
  } else {
    $sem = $self->determine_semester( tel => $tel );
  }

  # Now guess the actual projectid
  my $fullid;
  if ($tel eq "UKIRT") {

    # Get the prefix and numbers if supplied project id is in 
    # that form

    if ($projid =~ /^([hsHSJj]?)(\d+)$/ ) {
      my $prefix = $1;
      my $digits = $2;

      # Need to remove leading zeroes
      $digits =~ s/^0+//;

      # For service the semester is always "serv" and
      # the prefix is blank
      if ($prefix =~ /[sS]/) {
	$sem = "serv";
	$prefix = '';
      }

      # Recreate the root project id
      $projid = $prefix . $digits;
    }

    # Now construct the full ID
    $fullid = "u/$sem/$projid";

  } elsif ($tel eq "JCMT") {

    # Service mode changes the prefix
    my $prefix = ( $projid =~ /^s/  ? 's' : 'm' );

    # remove the s signifier
    $projid =~ s/^s//;

    $fullid = "$prefix$sem$projid";

  } else {
    croak "$tel is not a recognized telescope";
  }

  return $fullid;

}

=item B<extract_projectid>

Given a string (for example a full project id or possibly a subject
line of a mail message) attempt to extract a string that looks like
a OMP project ID.

  $projectid = OMP::General->extract_projectid( $string );

Returns undef if nothing looking like a project ID could be located.
The match is done on word boundaries.

No attempt is made to verify that this project ID is actually
in the OMP system.

Note that this method has the side effect of untainting the
supplied variable.

=cut

sub extract_projectid {
  my $class = shift;
  my $string = shift;

  my $projid;

  if ($string =~ /\b(u\/\d\d[ab]\/[jhd]?\d+[ab]?)\b/i    # UKIRT
      or $string =~ /\b([ms]\d\d[ab][unchid]\d+([a-z]|fb)?)\b/i # JCMT [inc serv, FB and A/B suffix]
      or $string =~ /\b(m\d\d[ab]ec\d+)\b/i         # JCMT E&C
      or $string =~ /\b(m\d\d[ab]h\d+[a-z]\d?)\b/i  # UH funny suffix JCMT
      or $string =~ /\b(u\/serv\/\d+)\b/i           # UKIRT serv
      or $string =~ /\b(u\/ec\/\d+)\b/i           # UKIRT E&C
      or $string =~ /\b(u\/ukidss\/[a-z]{3}(\d+[a-z]?|_sv)?)\b/i # UKIRT UKIDSS program
      or $string =~ /\b(nls\d+)\b/i                 # JCMT Dutch service (deprecated format)
      or $string =~ /\b([LS]X_\d\d\w\w_\w\w)\b/i    # SHADES proposal
      or $string =~ /\b([A-Za-z]+CAL)\b/i           # Things like JCMTCAL
      or ($string =~ /\b([A-Za-z]{2,}\d{2,})\b/     # Staff projects TJ02
	  && $string !~ /\bs[uinc]\d+\b/ ) # but not JCMT service abbrev
     ) {
    $projid = $1;
  }

  return $projid;

}

=back

=head2 Telescopes

=over 4

=item B<determine_tel>

Return the telescope name to use in the current environment.
This is usally obtained from the config system but if the config
system returns a choice of telescopes a Tk window will popup
requesting that the specific telescope be chosen.

If no Tk window reference is supplied, and multiple telescopes
are available, returns all the telescopes (either as a list
in list context or an array ref in scalar context). ie, if called
with a Tk widget, guarantees to return a single telescope, if called
without a Tk widget is identical to querying the config system directly.

  $tel = OMP::General->determine_tel( $MW );

Returns undef if the user presses the "cancel" button when prompted
for a telescope selection.

If a Term::ReadLine object is provided, the routine will prompt for 
a telescope if there is a choice. This has the same behaviour as for the
Tk option. Returns undef if the telescope was not valid after a prompt.

=cut

sub determine_tel {
  my $class = shift;
  my $w = shift;

  my $tel = OMP::Config->getData( 'defaulttel' );

  my $telescope;
  if( ref($tel) eq "ARRAY" ) {
    if (! defined $w) {
      # Have no choice but to return the array
      if (wantarray) {
	return @$tel;
      } else {
	return $tel;
      }
    } elsif (UNIVERSAL::isa($w, "Term::ReadLine") ||
	     UNIVERSAL::isa($w, "Term::ReadLine::Perl")) {
      # Prompt for it
      my $res = $w->readline("Which telescope [".join(",",@$tel)."] : ");
      $res = uc($res);
      if (grep /^$res$/i, @$tel) {
	return $res;
      } else {
	# no match
	return ();
      }

    } else {
      # Can put up a widget
      require Tk::DialogBox;
      my $newtel;
      my $dbox = $w->DialogBox( -title => "Select telescope",
				-buttons => ["Accept","Cancel"],
			      );
      my $txt = $dbox->add('Label',
			   -text => "Select telescope for obslog",
			  )->pack;
      foreach my $ttel ( @$tel ) {
	my $rad = $dbox->add('Radiobutton',
			     -text => $ttel,
			     -value => $ttel,
			     -variable => \$newtel,
			    )->pack;
      }
      my $but = $dbox->Show;

      if( $but eq 'Accept' && $newtel ne '') {
	$telescope = uc($newtel);
      } else {
	# Pressed cancel
	return ();
      }
    }
  } else {
    $telescope = uc($tel);
  }

  return $telescope;
}

=back

=head2 Verification

=over 4

=item B<verify_administrator_password>

Compare the supplied password with the administrator password. Throw
an exception if the two do not match. This safeguard is used to
prevent people from modifying the contents of the project database
without having permission.

  OMP::General->verify_administrator_password( $input );

Note that the supplied password is assumed to be unencrypted.

An optional second argument can be used to disable the exception
throwing. If the second argument is true the routine will return
true or false depending on whether the password is verified.

  $isokay = OMP::General->verify_administrator_password( $input, 1 );

Always fails if the supplied password is undefined.

=cut

sub verify_administrator_password {
  my $self = shift;
  my $password = shift;
  my $retval = shift;

  # The encrypted admin password
  # At some point we'll pick this up from somewhere else.
  my $admin = OMP::Config->getData("password.admin");

  # Encrypt the supplied password using the admin password as salt
  # unless the supplied password is undefined
  my $encrypted = ( defined $password ? crypt($password, $admin) : "fail" );

  # A bit simplistic at the present time
  my $status;
  if ($encrypted eq $admin) {
    $status = 1;
  } else {
    # Throw an exception if required
    if ($retval) {
      $status = 0;
    } else {
      throw OMP::Error::Authentication("Failed to match administrator password\n");
    }
  }
  return $status;
}

=item B<verify_staff_password>

Compare the supplied password with the staff password. Throw
an exception if the two do not match. This provides access to some
parts of the system normally restricted to principal investigators.

  OMP::General->verify_staff_password( $input );

Note that the supplied password is assumed to be unencrypted.

An optional second argument can be used to disable the exception
throwing. If the second argument is true the routine will return
true or false depending on whether the password is verified.

  $isokay = OMP::General->verify_staff_password( $input, 1 );

Always fails if the supplied password is undefined.

The password is always compared with the administrator password
first.

=cut

sub verify_staff_password {
  my $self = shift;
  my $password = shift;
  my $retval = shift;

  # First try admin password
  my $status = OMP::General->verify_administrator_password( $password,1);

  # Return immediately if all is well
  # Else try against the staff password
  return $status if $status;

  # The encrypted staff password
  # At some point we'll pick this up from somewhere else.
  my $admin = OMP::Config->getData("password.staff");

  # Encrypt the supplied password using the staff password as salt
  # unless the supplied password is undefined
  my $encrypted = ( defined $password ? crypt($password, $admin) : "fail" );

  # A bit simplistic at the present time
  if ($encrypted eq $admin) {
    $status = 1;
  } else {
    # Throw an exception if required
    if ($retval) {
      $status = 0;
    } else {
      throw OMP::Error::Authentication("Failed to match staff password\n");
    }
  }
  return $status;
}

=item B<verify_queman_password>

Compare the supplied password with the queue manager password. Throw
an exception if the two do not match. This provides access to some
parts of the system normally restricted to queue managers.

  OMP::General->verify_queueman_password( $input, $queue );

Note that the supplied password is assumed to be unencrypted. The
queue name (usually country name) must be supplied.

An optional third argument can be used to disable the exception
throwing. If the second argument is true the routine will return
true or false depending on whether the password is verified.

  $isokay = OMP::General->verify_queman_password( $input, $queue, 1 );

Always fails if the supplied password is undefined. The country
must be defined unless the password is either the staff or administrator
password (which is compared first).

=cut

sub verify_queman_password {
  my $self = shift;
  my $password = shift;
  my $queue = shift;
  my $retval = shift;

  # First try staff password
  my $status = OMP::General->verify_staff_password( $password,1);

  # Return immediately if all is well
  # Else try against the queue password
  return $status if $status;

  # rather than throwing conditional exceptions with complicated
  # repeating if statements just paper over the cracks until the
  # final failure triggers the throwing of exceptions
  $queue = "UNKNOWN" unless $queue;
  $queue = uc($queue);

  # The encrypted passwords
  # At some point we'll pick this up from somewhere else.
  my %passwords = (
		   UH => OMP::Config->getData("password.uh"),
		  );

  my $admin = (exists $passwords{$queue} ? $passwords{$queue} : "noadmin");

  # Encrypt the supplied password using the queue password as salt
  # unless the supplied password is undefined
  my $encrypted = ( defined $password ? crypt($password, $admin)
		    : "fail" );

  # A bit simplistic at the present time
  if ($encrypted eq $admin) {
    $status = 1;
  } else {
    # Throw an exception if required
    if ($retval) {
      $status = 0;
    } else {
      throw OMP::Error::Authentication("Failed to match queue manager password for queue '$queue'\n");
    }
  }
  return $status;
}

=item B<am_i_staff>

Compare the supplied project ID with the internal staff project ID.

  OMP::General->am_i_staff( $projectid );

Returns true if the supplied project ID matches, false otherwise. This 
method does a case-insensitive match, and does not do password or database 
verification.

=cut

sub am_i_staff {
  my $self = shift;
  my $projectid = shift;

  return $projectid =~ /^staff$/i;
}

=item B<determine_user>

See if the user ID can be guessed from the system environment
without asking for it.

  $user = OMP::General->determine_user( );

Uses the C<$USER> environment variable for the first guess. If that
is not available or is not verified as a valid user the method either
returns C<undef> or, if the optional widget object is supplied,
popups up a Tk dialog box requesting input from the user.

  $user = OMP::General->determine_user( $MW );

If the userid supplied via the widget is still not valid, give
up and return undef.

Returns the user as an OMP::User object.

=cut

sub determine_user {
  my $class = shift;
  my $w = shift;

  my $user;
  if (exists $ENV{USER}) {
    $user = OMP::UserServer->getUser($ENV{USER});
  }

  unless ($user) {
    # no user so far so if we have a widget popup dialog
    if ($w) {
      require Tk::DialogBox;
      require Tk::LabEntry;

      while( ! defined $user ) {

        my $dbox = $w->DialogBox( -title => "Request OMP user ID",
                                  -buttons => ["Accept","Don't Know"],
                                );
        my $ent = $dbox->add('LabEntry',
                             -label => "Enter your OMP User ID:",
                             -width => 15)->pack;
        my $but = $dbox->Show;
        if ($but eq 'Accept') {
          my $id = $ent->get;

          # Catch any errors that might pop up.
          try {
            $user = OMP::UserServer->getUser($id);
          } catch OMP::Error with {
            my $Error = shift;

            my $dbox2 = $w->DialogBox( -title => "Error",
                                       -buttons => ["OK"],
                                     );
            my $label = $dbox2->add( 'Label',
                                     -text => "Error: " . $Error->{-text} )->pack;
            my $but2 = $dbox2->Show;
          } otherwise {
            my $Error = shift;

            my $dbox2 = $w->DialogBox( -title => "Error",
                                       -buttons => ["OK"],
                                     );
            my $label = $dbox2->add( 'Label',
                                     -text => "Error: " . $Error->{-text} )->pack;
            my $but2 = $dbox2->Show;
          };
          if( defined( $user ) ) {
            last;
          }
        } else {
          last;
        }
      }

    }
  }

  return $user;
}

=back

=head2 Logging

=over 4

=item B<log_level>

Control which log messages are written to the log file.

  $current = OMP::General->log_level();
  OMP::General->log_level( &OMP__LOG_DEBUG );
  OMP::General->log_level( "DEBUG" );

The constants are defined in OMP::Constants. Currently supported
logging levels are:

  IMPORTANT   (only important messages)
  INFO        (informational and important messages)
  DEBUG       (debugging, info and important messages)

The level can be set using the above strings as well as the actual
constants, but constants will be returned if the level is requested.
If the new level is not recognized, the existing level will be retained.

Note that WARNING and ERROR log messages are always written to the log
and can not be disabled individually.

The default log level is INFO (ie no DEBUG messages) but can be over-ridden
by defining the environment OMP_LOG_LEVEL to one of "IMPORTANT", "INFO" or
"DEBUG"

=cut

{
  # Hide access to this variable
  my $LEVEL;

  # private routine to translate string to constant value
  # and then sort out the bit mask
  # return undef if not recognized
  # Note that the only system that calculates level from bits is this
  # internal function
  sub _str_or_const_to_level {
    my $arg = shift;
    my $bits = 0;

    # define some groups
    my $important = OMP__LOG_IMPORTANT;
    my $info      = $important | OMP__LOG_INFO;
    my $debug     = $info | OMP__LOG_DEBUG;
    my $err       = OMP__LOG_ERROR | OMP__LOG_WARNING;

    if ($arg eq 'IMPORTANT' || $arg eq OMP__LOG_IMPORTANT) {
      $bits = $important;
    } elsif ($arg eq 'INFO' || $arg eq OMP__LOG_INFO) {
      $bits = $info;
    } elsif($arg eq 'DEBUG' || $arg eq OMP__LOG_DEBUG) {
      $bits = $debug;
    }

    # Now set LEVEL to this value if we have $bits != 0
    # else no change to $LEVEL
    # if we allow 0 then nothing will be logged ever. We currently
    # do not have a OMP__LOG_NONE option
    if ($bits != 0) {
      # Include WARNING and ERROR in bitmask
      $bits |= $err;
      $LEVEL = $bits;
    }

    return;
  }

  # Accessor method
  sub log_level {
    my $class = shift;
    if (@_) {
      _str_or_const_to_level( shift );
    }
    # force default if required. This will only be called once
    if (!defined $LEVEL) {
      _str_or_const_to_level( $ENV{OMP_LOG_LEVEL} )
        if exists $ENV{OMP_LOG_LEVEL};
      _str_or_const_to_level( OMP__LOG_INFO ) 
        unless defined $LEVEL;
    }
    return $LEVEL;
  }

  # Returns true if the supplied message severity is consistent with
  # the current logging level.
  # undef indicates INFO
  # Keep this private for now
  sub _log_logok {
    my $class = shift;
    my $sev = shift;
    $sev = OMP__LOG_INFO unless defined $sev;
    return ( $class->log_level & $sev );
  }

  # Translate supplied constant back to a descriptive string
  # we assume that multiple logging levels are not specified
  # keep internal for the moment since we only need it for the
  # log output
  sub _log_level_string {
    my $class = shift;
    my $sev = shift;
    $sev = OMP__LOG_INFO unless defined $sev;
    return colored("ERROR:    ",'red')     if $sev & OMP__LOG_ERROR;
    return colored("WARNING:  ",'yellow')  if $sev & OMP__LOG_WARNING;
    return colored("IMPORTANT:",'green')   if $sev & OMP__LOG_IMPORTANT;
    return colored("INFO:     ",'cyan')    if $sev & OMP__LOG_INFO;
    return colored("DEBUG:    ",'magenta') if $sev & OMP__LOG_DEBUG;
  }

}

=item B<log_message>

Log general information to a file. Each message can be associated with
a particular importance or severity such that a particular log message
will only be written to the log file if that particular level of
logging is enabled (which can be set via the C<log_level>
method). WARNING and ERROR log messages will always be written.

By default, all messages are treated as "INFO" messages if no log
level is specified.

  OMP::General->log_message( $message );

If a second argument is provided, it specifies the log
severity/importance level. Constants are available from
C<OMP::Constants>.

  OMP::General->log_message( $message, OMP__LOG_DEBUG );

The currently defined set are:

  ERROR     - an error message
  WARNING   - a warning message
  IMPORTANT - important log message (always written)
  INFO      - general information
  DEBUG     - verbose logging

The log file is opened for append (with a lock), the message is written
and the file is closed. The message is augmented with details of the
hostname, the process ID and the date.

Fails silently if the file can not be opened (rather than cause the whole
system to stop because it is not being written).

Uses the config C<logdir> entry to determine the required logging
directory but will fall back to C</tmp/ompLogs> if the required
directory can not be written to. A new file is created for each UT day.
The directory is created if it does not exist.

Returns immediately if the environment variable C<$OMP_NOLOG> is set,
even if the message has been tagged ERROR [maybe it should always send
error messages to STDERR if the process is attached to a terminal?].

=cut

sub log_message {
  my $class = shift;
  my $message = shift;
  my $severity = shift;

  return if exists $ENV{OMP_NOLOG};

  # Check the logging level.
  return unless $class->_log_logok( $severity );

  # Get the current date
  my $datestamp = gmtime;

  # "Constants"
  my $logdir;

  # Look for the logdir but make sure this is none fatal
  # so for any error ignore it. in some cases a bare eval{}
  # here did not catch everyhing so use a try with empty otherwise
  try {
    # Make sure a date is available to the config system
    $logdir = OMP::Config->getData( "logdir", utdate => $datestamp );
  } otherwise {
    # empty - we want to catch everything
  };
  my $fallback_logdir = File::Spec->catdir( File::Spec->tmpdir, "ompLogs");
  my $today = $datestamp->strftime("%Y%m%d");

  # The filename depends on whether the logdir includes the ut date
  my $file1 = "omp.log";
  my $file2 = "omp_$today.log";

  # Create the message
  my ($user, $host, $email) = OMP::General->determine_host;

  my $sevstr = $class->_log_level_string( $severity );

  # Create the log message without a prefix
  my $logmsg = colored("$datestamp",'blue underline').
     " PID: ".colored("$$","green underline") .
     " User: ".colored("$email","green underline")."\nMsg: $message\n";

  # Split on newline, attached prefix, and then join on new line
  my @lines = split(/\n/, $logmsg);
  $logmsg = join("\n", map { $sevstr .$_ } @lines) . "\n";

  # Get current umask
  my $umask = umask;

  # Set umask to 0 so that we can remove all protections
  umask 0;

  # Try both the logdir and the back up
  for my $thisdir ($logdir, $fallback_logdir) {
    next unless defined $thisdir;

    my $filename = ($thisdir =~ /$today/ ? $file1 : $file2 );

    my $path = File::Spec->catfile( $thisdir, $filename);

    # First check the directory and create it if it isnt here
    # Loop around if we can not open it
    unless (-d $thisdir) {
      mkdir $thisdir, 0777
	or next;
    }

    # Open the file for append
    # Creating the file if it is not there already
    open my $fh, ">> $path"
      or next;

    # Get an exclusive lock (this blocks)
    flock $fh, LOCK_EX;

    # write out the message
    print $fh $logmsg;

    # Explicitly close the file (dont check return value since
    # we will just return anyway)
    close $fh;

    # If we got to the end we jump out the loop
    last;

  }

  # Reset umask
  umask $umask;

  return;
}

=back

=head2 String manipulation

=over 4

=item B<split_string>

Split a string that uses a whitespace as a delimiter into a series of
substrings. Substrings that are surrounded by double-quotes will be
separated out using the double-quotes as the delimiters.

  $string = 'foo "baz xyz" bar';
  @substrings = OMP::General->split_string($string);

Returns an array of substrings.

=cut

sub split_string {
  my $self = shift;
  my $string = shift;

  my @substrings;

  # Loop over the string extracting out the double-quoted substrings
  while ($string =~ /\".*?\"/s) {
    my $savestring = '';
    if ($string !~/^\"/) {
      # Modify the string so that it begins with a quoted string and
      # store the portion of the string preceding the quoted string
      my $index = index($string, '"');
      $savestring .= substr($string, 0, $index);
      $string = substr($string, $index);
    }

    # Extract out the quoted string
    my ($extracted, $remainder) = extract_delimited($string,'"');
    $extracted =~ s/^\"(.*?)\"$/$1/; # Get rid of the begin and end quotes
    push @substrings, $extracted;
    $string = $savestring . $remainder;
  }

  # Now split the string apart on white space
  push @substrings, split(/\s+/,$string);

  return @substrings;
}

=item B<preify_text>

This method is used to prepare text for storage to the database so that
when it is retrieved it can be displayed properly in HTML format.
If the text is not HTML formatted then it goes inside PRE tags and HTML characters (such as <, > and &) are replaced with their associated entities.  Also
strips out windows ^M characters.

  $escaped = $self->preify_text($text);

Text is considered to be HTML formatted if it begins with the string "<html>" (case-insensitive).  This string is stripped off if found.

=cut

sub preify_text {
  my $self = shift;
  my $string = shift;

  if ($string !~ /^<html>/i) {
    $string = escape_entity( $string );
    $string = "<pre>$string</pre>";
  } else {
    $string =~ s!</*html>!!ig;
  }

  # Strip ^M
  $string =~ s/\015//g;

  return $string;
}

=item B<escape_entity>

Replace a & > or < with the corresponding HTML entity.

  $esc = escape_entity( $text );

=cut

sub escape_entity {
  my $text = shift;

  # Escape sequence lookup table
  my %lut = (">" => "&gt;",
	     "<" => "&lt;",
	     "&" => "&amp;",
	     '"' => "&quot;",);

  # Do the search and replace
  # Make sure we replace ampersands first, otherwise we'll end
  # up replacing the ampersands in the escape sequences
  for ("&", ">", "<", '"') {
    $text =~ s/$_/$lut{$_}/g;
  }

  return $text;
}

=item B<replace_entity>

Replace some HTML entity references with their associated characters.

  $text = OMP::General->replace_entity($text);

Returns an empty string if $text is undefined.

=cut

sub replace_entity {
  my $self = shift;
  my $string = shift;
  return '' unless defined $string;

  # Escape sequence lookup table
  my %lut = ("&gt;" => ">",
	     "&lt;" => "<",
	     "&amp;" => "&",
	     "&quot;" => '"',);

  # Do the search and replace
  for (keys %lut) {
    $string =~ s/$_/$lut{$_}/gi;
  }

  return $string;
}

=item B<html_to_plain>

Convert HTML formatted text to plaintext.  Also expands hyperlinks
so that their URL can be seen.

  $plaintext = OMP::General->html_to_plain($html);

=cut

sub html_to_plain {
  my $self = shift;
  my $text = shift;

  # Expand HTML links for our plaintext message
  $text =~ s!<a\s+href=\W*(\w+://.*?/*)\W*?\s*\W*?>(.*?)</a>!$2 \[ $1 \]!gis;

  # Create the HTML tree and parse it
  my $tree = HTML::TreeBuilder->new;
  $tree->parse($text);
  $tree->eof;

  # Convert the HTML to text and store it
  my $formatter = HTML::FormatText->new(leftmargin => 0);
  my $plaintext = $formatter->format($tree);

  return $plaintext;
}

=item B<nint>

Return the nearest integer to a supplied floating point
value. 0.5 is rounded up.

  $nint = OMP::General::nint( $in );

=cut

sub nint {
    my $value = shift;

    if ($value >= 0) {
        return (int($value + 0.5));
    } else {
        return (int($value - 0.5));
    }
};


=back

=head2 Files

=over 4

=item B<files_on_disk>

For a given instrument and UT date, this method returns a list of
observation files.

  my @files = OMP::General->files_on_disk( 'CGS4', '20060215' );
  my $files = OMP::General->files_on_disk( 'CGS4', '20060215' );

If called in list context, returns a list of array references. Each
array reference points to a list of observation files for a single
observation. If called in scalar context, returns a reference to an
array of array references.

=cut

sub files_on_disk {
  my $class = shift;
  my $instrument = shift;
  my $utdate = shift;

  my @return;

  # Retrieve information from the configuration system.
  my $tel = OMP::Config->inferTelescope( 'instruments', $instrument );
  my $directory = OMP::Config->getData( 'rawdatadir',
                                        telescope => $tel,
                                        instrument => $instrument,
                                        utdate => $utdate,
                                      );
  my $flagfileregexp = OMP::Config->getData( 'flagfileregexp',
                                             telescope => $tel,
                                           );

  # Remove the /dem from non-SCUBA directories.
  if( uc( $instrument ) ne 'SCUBA' ) {
    $directory =~ s/\/dem$//;
  }

  # Change wfcam to wfcam1 if the instrument is WFCAM.
  if( uc( $instrument ) eq 'WFCAM' ) {
    $directory =~ s/wfcam/wfcam1/;
  }

  # ACSIS directory is actually acsis/acsis00/utdate.
  if( uc( $instrument ) eq 'ACSIS' ) {
    $directory =~ s[(acsis)/(\d{8})][$1/spectra/$2];
  }

  # Open the directory.
  opendir( OMP_DIR, $directory );

  # Get the list of files that match the flag file regexp.
  my @flag_files = map { File::Spec->catfile( $directory, $_ ) } sort grep ( /$flagfileregexp/, readdir( OMP_DIR ) );

  # Close the directory.
  close( OMP_DIR );

  # Go through each flag file, open it, and retrieve the list of files
  # within it. If the flag file size is 0 bytes, then we assume that
  # the observation file associated with that flag file is of the same
  # naming convention, removing the dot from the front and replacing
  # the .ok on the end with .sdf.
  foreach my $flag_file ( @flag_files ) {

    # Zero-byte filesize.
    if ( -z $flag_file ) {

      $flag_file =~ /(.+)\.(\w+)\.ok$/;
      my $data_file = $1 . $2 . ".sdf";

      my @array;
      push @array, $data_file;
      push @return, \@array;

    } else {

      open my $flag_fh, "<", $flag_file;

      my @array;
      while (<$flag_fh>) {
        chomp;
        push @array, File::Spec->catfile( $directory, $_ );
      }
      push @return, \@array;

      close $flag_fh;

    }

  }

  if( wantarray ) {
    return @return;
  } else {
    return \@return;
  }

}

=back

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>,
Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>,
Brad Cavanagh E<lt>b.cavanagh@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001-2006 Particle Physics and Astronomy Research Council.
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
along with this program (see SLA_CONDITIONS); if not, write to the 
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



1;
