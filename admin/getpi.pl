#!/local/perl/bin/perl

# Read in the .ini file used by mkproj.pl and extract the PI
# information and write it to disk suitable for use as a mailing
# list.

# Takes the file name as argument.

use warnings;
use strict;

use FindBin;
use constant OMPLIB => "$FindBin::RealBin/../lib";

use lib OMPLIB;

BEGIN {
    $ENV{'OMP_CFG_DIR'} = File::Spec->catdir(OMPLIB, '../cfg')
        unless exists $ENV{'OMP_CFG_DIR'};
}

use Config::IniFiles;
use OMP::UserServer;
use Data::Dumper;
use IO::File;

# Read file from arg list
my $file = shift(@ARGV);
die "Please supply a filename\n" unless defined $file;

my %alloc;
my $fh = IO::File->new($file, 'r');
die "Could not open file '$file'" unless defined $fh;
$fh->binmode(':utf8');
tie %alloc, 'Config::IniFiles', (-file => $fh);
$fh->close();

# Loop over all projects
my %users;
for my $proj (keys %alloc) {
    next if $proj eq 'info';

    my @users = ($alloc{$proj}->{pi});
    for (@users) {
        next unless $_ =~ /\w/;
        $users{$_}++;
    }
}

# print out all the users and the frequency
for (sort keys %users) {
    # Check if the user is in the database already
    my $isthere = OMP::UserServer->verifyUser($_);
    my $string;
    if ($isthere) {
        my $user = OMP::UserServer->getUser($_);
        print $user->as_email_hdr . "\n";
    }
    else {
        print STDERR "User $_ is not in the database!\n";
    }
}
