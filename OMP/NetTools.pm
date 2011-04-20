package OMP::NetTools;

=head1 NAME

OMP::NetTools - Methods related to networking, host, etc.

=head1 SYNOPSIS

  use OMP::NetTools;

  $local = OMP::NetTools->is_host_local();

=head1 DESCRIPTION

NetTools routines that are not associated with any particular class
but that are useful in more than one class.

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
use Net::Domain qw/ hostfqdn /;
use Net::hostent qw/ gethost /;

our $VERSION = (qw$Revision$)[1];

our $DEBUG = 0;

=head1 METHODS

There are no instance methods, only class (static) methods.

=over 4

=item B<determine_host>

Determine the host and user name of the person either running this
task. This is either determined by using the CGI environment variables
(REMOTE_ADDR and REMOTE_USER) or, if they are not set, the current
host running the program and the associated user name.

  ($user, $host, $email) = OMP::NetTools->determine_host;

The user name is not always available (especially if running from
CGI).  The email address is simply determined as C<$user@$host> and is
identical to the host name if no user name is determined.

An optional argument can be used to disable remote host checking
for CGI. If true, this method will return the host on which
the program is running rather than the remote host information.

  ($user, $localhost, $email) = OMP::NetTools->determine_host(1);

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

  print "local" if OMP::NetTools->is_host_local

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

1;

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
along with this program (see SLA_CONDITIONS); if not, write to the
Free Software Foundation, Inc., 59 Temple Place, Suite 330,
Boston, MA  02111-1307  USA


=cut


