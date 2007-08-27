#!/local/perl/bin/perl

# Read project IDs from standard input and for each projid set
# the time remaining to zero seconds.

# Pick up the OMP database
use FindBin;
use lib "$FindBin::RealBin/..";
use OMP::DBbackend;
use OMP::ProjDB;
use OMP::Password;

my $pass = OMP::Password->get_verified_password({
             'prompt' => 'Enter administrator password: ',
             'verify' => 'verify_administrator_password',
            }) ;

# Connect to the database and create a proj db object
my $db = new OMP::ProjDB( DB => new OMP::DBbackend,
			  Password => $pass,
			);

while (<>) {
  chomp;
  my $line = $_;

  # Comments
  $line =~ s/\#.*//;
  next unless length($line) > 0;

  $db->projectid( $line );
  $db->disableProject();



}
