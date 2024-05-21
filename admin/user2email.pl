#!/local/perl/bin/perl

# Given OMP user ids on standard input, convert them to email addresses
# and names in email format "Name <email@doma.in>
#
#   cat users.txt | user2email.pl > emails.txt

use warnings;
use strict;

use FindBin;
use constant OMPLIB => "$FindBin::RealBin/../lib";

use lib OMPLIB;

BEGIN {
    $ENV{'OMP_CFG_DIR'} = File::Spec->catdir(OMPLIB, '../cfg')
        unless exists $ENV{'OMP_CFG_DIR'};
}

use OMP::DB::Backend;
use OMP::DB::User;

my $udb = OMP::DB::User->new(DB => OMP::DB::Backend->new);

for my $userid (<>) {
    chomp($userid);
    next unless $userid =~ /\w/;
    $userid =~ s/\s+//;
    my $user = $udb->getUser($userid);
    next unless defined $user;
    print $user->as_email_hdr() . "\n" if defined $user->email();
}
