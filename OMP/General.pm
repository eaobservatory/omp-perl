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
use Carp;
use OMP::Range;
use OMP::UserServer;
use Time::Piece ':override';
use Net::Domain qw/ hostfqdn /;
use Net::hostent qw/ gethost /;
use File::Spec;
use Fcntl qw/ :flock /;
use OMP::Error;
use Time::Seconds qw/ ONE_DAY /;

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
Returns the object unchanged if the argument is already a C<Time::Piece>.

It will also recognize a Sybase style date: 'Mar 15 2002  7:04AM'
and a simple YYYYMMDD.

The date is assumed to be in UT.

=cut

sub parse_date {
  my $self = shift;
  my $date = shift;

  # If we already have a Time::Piece return
  return bless $date, "Time::Piece::Sybase"
    if UNIVERSAL::isa( $date, "Time::Piece");

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
  } elsif ($date =~ /^\d\d\d\d\d\d\d\d\b/) {
    # YYYYMMDD format
    $format = "%Y%m%d";
  } else {
    # Assume Sybase date
    # Mar 15 2002  7:04AM
    $format = "%b%t%d%t%Y%t%I:%M%p";

  }

  # Now parse
  # Use Time::Piece::Sybase so that we can instantiate
  # the object in a state that can be used for sybase queries
  # This won't work if we use standard overridden gmtime.
  # Note also that this time is treated as "local" rather than "gm"
  my $time = eval { Time::Piece->strptime( $date, $format ); };
  if ($@) {
    return undef;
  } else {
    # Note that the above constructor actually assumes the date
    # to be parsed is a local time not UTC. To switch to UTC
    # simply get the epoch seconds and the timezone offset
    # and run gmtime
    # Sometime around v1.07 of Time::Piece the behaviour changed
    # to return UTC rather than localtime from strptime!
    # The joys of backwards compatibility.
    if ($time->[Time::Piece::c_islocal]) {
      my $tzoffset = $time->tzoffset;
      my $epoch = $time->epoch;
      $time = gmtime( $epoch + $tzoffset->seconds );
    }

    # Now need to bless into class Time::Piece::Sybase
    return bless $time, "Time::Piece::Sybase";

  }

}


=item B<today>

Return the UT date for today in C<YYYY-MM-DD> format.

  $today = OMP::General->today();

=cut

sub today {
  my $class = shift;
  my $time = gmtime();

  return $time->strftime("%Y-%m-%d");

}

=item B<yesterday>

Return the UT date for yesterday in C<YYYY-MM-DD> format.

  $y = OMP::General->yesterday();

=cut

sub yesterday {
  my $class = shift;
  my $time = gmtime();

  $time -= ONE_DAY;

  return $time->strftime("%Y-%m-%d");

}

=back

=head2 Strings

=over 4

=item B<prepare_for_insert>

Convert a text string into one that is ready to be stored in
the database.

  $insertstring = OMP::General->prepare_for_insert( $string );

This method converts the string as follows:

=over 4

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
      $addr = (defined $addr and ref $addr ? $addr->name : $ip );
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
    # localhost
    $addr = hostfqdn;
    $user = (exists $ENV{USER} ? $ENV{USER} : '' );

  }

  # Build a pseudo email address
  my $email = '';
  $email = $addr if $addr;
  $email = $user . "@" . $email if $user;

  $email = "UNKNOWN" unless $email;

  # Replce space with _
  $email =~ s/\s+/_/g;

  return ($user, $addr, $email);
}

=back

=head2 Time Allocation Bands

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

  # JCMT is the only interesting one
  my $band;
  if (exists $details{TELESCOPE} and $details{TELESCOPE} eq 'JCMT') {

    if (exists $details{TAU}) {
      my $cso = $details{TAU};
      throw OMP::Error::FatalError("CSO TAU supplied but not defined. Unable to determine band")
	unless defined $cso;

      # do not use the OMP::Range objects here (yet KLUGE) because
      # OMP::Range can not yet do >= with the contains method
      if ($cso >= 0 && $cso <= 0.05) {
	$band = 1;
      } elsif ($cso > 0.05 && $cso <= 0.08) {
	$band = 2;
      } elsif ($cso > 0.08 && $cso <= 0.12) {
	$band = 3;
      } elsif ($cso > 0.12 && $cso <= 0.2) {
	$band = 4;
      } elsif ($cso > 0.2) {
	$band = 5;
      } else {
	throw OMP::Error::FatalError("CSO tau out of range: $cso\n");
      }

    } elsif (exists $details{TAURANGE}) {

      croak "Sorry. Not yet supported. Please write\n";

    } else {
      throw OMP::Error::FatalError("Unable to determine band for JCMT without TAU");
    }


  } else {
    # Everything else is boring
    $band = 0;
  }

  return $band;
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

{
  # Specify the bands
  my %bands = (
	       0   => new OMP::Range( Min => 0 ),
	       1   => new OMP::Range( Min => 0,    Max => 0.05),
	       2   => new OMP::Range( Min => 0.05, Max => 0.08),
	       3   => new OMP::Range( Min => 0.08, Max => 0.12),
	       4   => new OMP::Range( Min => 0.12, Max => 0.20),
	       5   => new OMP::Range( Min => 0.20 ),
	       '2*' => new OMP::Range( Min => 0.05, Max => 0.10),
	       '3*' => new OMP::Range( Min => 0.10, Max => 0.12),
	      );

  sub get_band_range {
    my $class = shift;
    my $tel = shift;
    my @bands = @_;

    if ($tel eq 'JCMT') {

      my ($min, $max) = (50,-50);
      for my $band (@bands) {
	if (exists $bands{$band}) {
	  my ($bmin, $bmax) = $bands{$band}->minmax;
	  $min = $bmin if $bmin < $min;
	  $max = $bmax if $bmax > $max;
	} else {
	  return undef;
	}

      }

      return new OMP::Range( Min => $min, Max => $max );


    } else {
      return $bands{"0"};
    }

  }
}

=back

=head2 Semesters

=over 4

=item B<determine_semester>

Given a date determine the current semester.

  $semester = OMP::General->determine_semester( $date );

Date should be of class C<Time::Piece>. The current date is used
if none is supplied.

=cut

sub determine_semester {
  my $self = shift;
  my $date = shift;

  if (defined $date) {
    croak "determine_semester: Date should be of class Time::Piece rather than \"$date\""
      unless UNIVERSAL::isa($date, "Time::Piece");
  } else {
    $date = gmtime();
  }

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
    $sem = "${yy}a";
  } elsif ($mmdd < 202) {
    $sem = "${prevyy}b";
  } else {
    $sem = "${yy}b";
  }

  return $sem;
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
the routine will croak. JCMT service programs can be abbreviated with
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
  if ($projid !~ /^s[uic]\d\d/ && 
      $projid =~ /^([A-Za-z]{2,}?)(\d+)$/) {
    return $1 . sprintf("%02d", $2);
  }

  # First the semester
  my $sem;
  if (exists $args{semester}) {
    $sem = $args{semester};
  } elsif (exists $args{date}) {
    $sem = $self->determine_semester( $args{date} );
  } else {
    $sem = $self->determine_semester();
  }

  # Now determine the telescope
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
    if ($projid =~ /^s?\d+$/) {
      $tel = "UKIRT";
    } elsif ($projid =~ /^s?[unci]\d+$/) {
      $tel = "JCMT";
    } else {
      croak "Unable to determine telescope from supplied project ID: $projid is ambiguous";
    }
  }

  # Now guess the actual projectid
  my $fullid;
  if ($tel eq "UKIRT") {

    # Get the prefix and numbers if supplied project id is in 
    # that form

    if ($projid =~ /^([hsHS]?)(\d+)$/ ) {
      my $prefix = $1;
      my $digits = $2;

      # Need to pad numbers to at least 2 digits
      $digits = sprintf "%02d", $digits;

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

=cut

sub extract_projectid {
  my $class = shift;
  my $string = shift;

  my $projid;

  if ($string =~ /\b(u\/\d\d[ab]\/h?\d+)\b/i        # UKIRT
      or $string =~ /\b([ms]\d\d[ab][unchi]\d+)\b/i # JCMT [inc service]
      or $string =~ /\b(m\d\d[ab]h\d+[a-z]\d?)\b/i  # UH funny suffix JCMT
      or $string =~ /\b(u\/serv\/\d+)\b/i           # UKIRT serv
      or $string =~ /\b(nls\d+)\b/i                 # JCMT Dutch service
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
  my $admin = "Fgq1aNqFqOvsg";

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
  my $admin = "bf4xPHRr.bUxE";

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
		   UH => 'afZ1FBCsmx63Y',
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
      throw OMP::Error::Authentication("Failed to match queue password password\n");
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
      my $dbox = $w->DialogBox( -title => "Request OMP user ID",
				-buttons => ["Accept","Don't Know"],
			      );
      my $ent = $dbox->add('LabEntry',
		 -label => "Enter your OMP User ID:",
		 -width => 15)->pack;
      my $but = $dbox->Show;
      if ($but eq 'Accept') {
	my $id = $ent->get;
	$user = OMP::UserServer->getUser($id);
      }

    }
  }

  return $user;
}

=back

=head2 Logging

=over 4

=item B<log_message>

Log general information (usually debug) to a file. The file is opened
for append (with a lock), the message is written and the file is
closed. The message is augmented with details of the hostname, the
process ID and the date.

  OMP::General->log_message( $message );

Fails silently if the file can not be opened (rather than cause the whole
system to stop because it is not being written).

A new file is created for each UT day in directory C</tmp/omplog>.
The directory is created if it does not exist.

Returns immediately if the environment variable C<$OMP_NOLOG> is set.

=cut

sub log_message {
  my $class = shift;
  my $message = shift;

  return if exists $ENV{OMP_NOLOG};

  # "Constants"
  my $logdir = File::Spec->catdir( File::Spec->tmpdir, "omplog");
  my $datestamp = gmtime;
  my $filename = "log." . $datestamp->strftime("%Y%m%d");
  my $path = File::Spec->catfile( $logdir, $filename);

  # Create the message
  my ($user, $host, $email) = OMP::General->determine_host;

  my $logmsg = "$datestamp PID: $$  User: $email\nMsg: $message\n";

  # Get current umask
  my $umask = umask;

  # Set umask to 0 so that we can remove all protections
  umask 0;

  # First check the directory and create it if it isnt here
  unless (-d $logdir) {
    mkdir $logdir, 0777
      or do { umask $umask; return};
  }

  # Open the file for append
  # Creating the file if it is not there already
  open my $fh, ">> $path"
    or do { umask $umask; return };

  # Reset umask
  umask $umask;

  # Get an exclusive lock (this blocks)
  flock $fh, LOCK_EX;

  # write out the message
  print $fh $logmsg;

  # Explicitly close the file (dont check return value since
  # we will just return anyway)
  close $fh;

  return;
}

=back

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
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
