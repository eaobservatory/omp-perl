#!/local/perl/bin/perl

=head1 NAME

sql_client - Opens an SQL client

=head1 DESCRIPTION

This script uses the OMP's configuration system to determine how to log in
to the MySQL database and launches a copy of MySQL client.  The
"hdr_database" configuration is used, so the user should be prompted
for the staff password.

Any command line arguments are passed on to the MySQL client,
following the connection parameters.  The "-u" / "-h" arguments
are processed specially to customize the displayed message.  They
replace the user or host name taken from the configuration file.

=cut

use strict;

use FindBin;
use File::Spec;

use constant OMPLIB => "$FindBin::RealBin/../lib";

BEGIN {
    $ENV{'OMP_CFG_DIR'} = File::Spec->catdir(OMPLIB, '../cfg')
        unless exists $ENV{'OMP_CFG_DIR'};
}

use lib OMPLIB;

use OMP::DB::Backend::Archive;

my %lh = OMP::DB::Backend::Archive->loginhash();

# Check the command line arguments for a user / host option so that we can
# print a suitable "Connecting..." message.
my $username = $lh{'user'};
my $hostname = $lh{'server'};
my @args = ();
while (my $arg = shift @ARGV) {
    if ($arg eq '-u' or $arg eq '--user') {
        $username = shift @ARGV;
    }
    elsif ($arg =~ /^--user=(\w+)$/) {
        $username = $1;
    }
    elsif ($arg eq '-h' or $arg eq '--host') {
        $hostname = shift @ARGV;
    }
    elsif ($arg =~ /^--host=(\w+)$/) {
        $hostname = $1;
    }
    else {
        push @args, $arg;
    }
}

print STDERR 'Connecting to MySQL server on ', $hostname, ' as ', $username, ".\n";

exec('mysql', '-h', $hostname, '-u', $username, '-p', @args);

__END__

=head1 COPYRIGHT

Copyright (C) 2017 East Asian Observatory. All Rights Reserved.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

=cut
