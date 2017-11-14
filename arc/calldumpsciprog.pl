#!/local/perl/bin/perl

=head1 NAME

calldumpsciprog - Run dumpsciprog for specified database server

=head1 SYNOPSIS

    calldumpsciprog.pl [--server ompX]

=cut

use strict;

use FindBin;
use Getopt::Long;
use Pod::Usage;

my $server = undef;
GetOptions("server=s" => \$server)
    or pod2usage('-exitval' => 2, '-verbose' => 1);

if (defined $server) {
    die 'Database server name is invaid' unless $server =~/^([-_A-Za-z0-9\.]+)$/;
    $ENV{OMP_DBSERVER} = $1;
}

die 'Invalid path to calldumpdb script'
    unless $FindBin::RealBin =~ /^([-_a-zA-Z0-9\/\.]+)$/;

my $status = system("/local/perl/bin/perl $1/../admin/dumpsciprog.pl");
if ($status != 0) {
    print "Error running dumpsciprog.pl (exit code = $status)\n";
    exit 1;
}
