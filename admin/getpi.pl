#!/local/perl-5.6/bin/perl

# Read in the .ini file used by mkproj.pl and extract the PI
# information and write it to disk suitable for use as a mailing
# list.

# Takes the file name as argument.

use Config::IniFiles;
use OMP::UserServer;
use Data::Dumper;

# Read file from arg list
my $file = shift(@ARGV);
die "Please supply a filename\n" unless defined $file;

my %alloc;
tie %alloc, 'Config::IniFiles', ( -file => $file );

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
  my $isthere = OMP::UserServer->verifyUser( $_ );
  my $string;
  if ($isthere) {
    my $user = OMP::UserServer->getUser( $_ );
    print $user->as_email_hdr ."\n";
  } else {
    print STDERR "User $_ is not in the database!\n";
  }

}

