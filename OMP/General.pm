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

use Time::Piece ':override';
use Net::Domain qw/ hostfqdn /;
use Net::hostent qw/ gethost /;

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
