package OMP::NetTools;

=head1 NAME

OMP::NetTools - Methods related to networking, host, etc.

=head1 SYNOPSIS

    use OMP::NetTools;

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
use Net::Domain qw/hostfqdn/;
use Net::hostent qw/gethost/;

our $VERSION = '2.000';

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

    if (! $noremote && exists $ENV{REMOTE_ADDR}) {
        # We are being called from a CGI context
        my $ip = $ENV{REMOTE_ADDR};

        # Try to translate number to name if we have network
        if (! exists $ENV{OMP_NOGETHOST}) {
            $addr = gethost($ip);

            # if we have nothing just use the IP
            $addr = ((defined $addr && ref $addr) ? $addr->name : $ip);
            $addr = $ip if ! $addr;
        }
        else {
            # else default to the IP address
            $addr = $ip;
        }

        # User name (only set if they have logged in)
        $user = (exists $ENV{REMOTE_USER} ? $ENV{REMOTE_USER} : '');
    }
    elsif (exists $ENV{OMP_NOGETHOST}) {
        # Do not do network lookup
        $addr = "localhost.localdomain";
        $user = (exists $ENV{USER} ? $ENV{USER} : '');
    }
    else {
        # For taint checking with Net::Domain when etc/resolv.conf
        # has no domain
        local $ENV{PATH} = "/bin:/usr/bin:/usr/local/bin"
            unless ${^TAINT} == 0;

        # localhost
        $addr = hostfqdn;

        # FQDN is having one at the end at least since Mar 26 2014, that results in
        # no match being found in OMP::Config. See
        # https://omp.eao.hawaii.edu/cgi-bin/viewfault.pl?fault=20140327.003.
        $addr =~ s/[.]$//;

        $user = (exists $ENV{USER} ? $ENV{USER} : '');
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

1;

__END__

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
