#!/local/perl/bin/perl

# Read project IDs from standard input and for each projid set
# the state to disabled.

# Pick up the OMP database
use FindBin;
use lib "$FindBin::RealBin/../lib";
use OMP::DB::Backend;
use OMP::DB::Project;
use OMP::Password;

OMP::Password->get_verified_auth('staff');

# Connect to the database and create a proj db object
my $db = OMP::DB::Project->new(DB => OMP::DB::Backend->new);

while (<>) {
    chomp;
    my $line = $_;

    # Comments
    $line =~ s/\#.*//;
    next unless length($line) > 0;

    $db->projectid($line);
    $db->disableProject();
}
