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

use Carp;
use Time::Piece ':override';
use Net::Domain qw/ hostfqdn /;
use Net::hostent qw/ gethost /;

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
  my $time = eval { Time::Piece->strptime( $date, $format ); };
  if ($@) {
    return undef;
  } else {
    # Note that the above constructor actually assumes the date
    # to be parsed is a local time not UTC. To switch to UTC
    # simply get the epoch seconds and the timezone offset
    # and run gmtime
    my $tzoffset = $time->tzoffset;
    my $epoch = $time->epoch;
    my $time = gmtime( $epoch + $tzoffset );

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

=item B<_determine_host>

Determine the host and user name of the person either running this
task. This is either determined by using the CGI environment variables
(REMOTE_ADDR and REMOTE_USER) or, if they are not set, the current
host running the program and the associated user name.

  ($user, $host, $email) = OMP::General->determine_host;

The user name is not always available (especially if running from
CGI).  The email address is simply determined as C<$user@$host> and is
identical to the host name if no user name is determined.

=cut

sub determine_host {
  my $class = shift;

  # Try and work out who is making the request
  my ($user, $addr);

  if (exists $ENV{REMOTE_ADDR}) {
    # We are being called from a CGI context
    my $ip = $ENV{REMOTE_ADDR};

    # Try to translate number to name
    $addr = gethost( $ip );
    $addr = (defined $addr and ref $addr ? $addr->name : '' );

    # User name (only set if they have logged in)
    $user = (exists $ENV{REMOTE_USER} ? $ENV{REMOTE_USER} : '' );

  } else {
    # localhost
    $addr = hostfqdn;
    $user = (exists $ENV{USER} ? $ENV{USER} : '' );

  }

  # Build a pseudo email address
  my $email = '';
  $email = $addr if $addr;
  $email = $user . "@" . $email if $user;

  # Replce space with _
  $email =~ s/\s+/_/g;

  return ($user, $addr, $email);
}

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
project and expanded to "u/server/01" (for "s1"). If the supplied ID
is ambiguous (most likely from a UH ID) the telescope must be supplied
or else the routine will croak.

The semester is determined from a "semester" key directly or from a date.
The current date is used if no date or semester is supplied.
The supplied date must be a C<Time::Piece> object.

=cut

sub infer_projectid {
  my $self = shift;
  my %args = @_;

  # The supplied ID
  my $projid = $args{projectid};
  croak "Must supply a project ID"
    unless defined $projid;

  # Make sure its not complete already
  return $projid if $projid =~ /^u\/\d\d[ab]/ # UKIRT
    or $projid =~ /^m\d\d[ab]/;               # JCMT
;

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
    } elsif ($projid =~ /^[unci]\d+$/) {
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
    $fullid = "m$sem$projid";

  } else {
    croak "$tel is not a recognized telescope";
  }

  return $fullid;

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

  return $retval;
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
