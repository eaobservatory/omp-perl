#!/local/perl/bin/perl

# Simple script to take the project details for a semester (in INI format)
# and
#  1. Generate a list of all users (COI and PI) along with a list of
#     users that are not currently recognized by the OMP
#
# Each entry in the file is deemded to be a project except for the specil
# entry "info" that contains the semester and telescope name.

# Each project entry must have the following keys:
#   tagpriority
#   country
#   pi
#   coi        [comma separated user id]
#   title
#   allocation [in hours]
#   tau band   [comma separated]
#
# Optionally the following fields are supported:
#
#   support    [comma separated user id]
#
# coi and title can be null. For JCMT support is inserted automatically
# depending on the country.

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
use OMP::DB::Backend;
use OMP::DB::User;
use Data::Dumper;
use IO::File;

my $userdb = OMP::DB::User->new(DB => OMP::DB::Backend->new);

# hard-wire for testing
my $file = 'data/alloc04a_ukirt.ini';

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
    my @users = ($alloc{$proj}->{pi}, split(",", $alloc{$proj}->{coi}));
    @users = map {uc($_)} @users;
    #@users = ($alloc{$proj}->{pi});
    for (@users) {
        next unless $_ =~ /\w/;
        $users{$_}++;
    }
}

# print out all the users and the frequency
for (sort keys %users) {
    # Check if the user is in the database already
    my $isthere = $userdb->verifyUser($_);
    my $string;
    if ($isthere) {
        my $user = $userdb->getUser($_);
        $string = "In database as $user" . ":" . $user->email;
    }
    else {
        $string = "*** NOT IN DATABASE ***";
    }

    print "$_ [$users{$_}]\t$string\n";
    my $user = $userdb->getUser($_);
    next unless $user;
    print "$_," . $user->name . "," . $user->email . "\n";
}
