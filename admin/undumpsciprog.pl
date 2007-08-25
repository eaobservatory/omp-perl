#!/local/perl/bin/perl

# UnDump the contents of the Database
# [currently only the science programs are restored]
# from disk

# Note: Only looks for science programs
# Assumes projects are okay
# Note: Does not undump project information yet

# The input directory is obtained from $OMP_DUMP_DIR

use 5.006;
use strict;
use warnings;
use OMP::SpServer;
use OMP::ProjServer;
use OMP::Error qw/ :try /;
use OMP::Constants qw/ :status /;
use OMP::Password;
use Data::Dumper;

# Abort if $OMP_DUMP_DIR is not set
die "Must specify input data directory via \$OMP_DUMP_DIR"
  unless exists $ENV{OMP_DUMP_DIR};

chdir $ENV{OMP_DUMP_DIR}
  or die "Error changing to directory $ENV{OMP_DUMP_DIR}: $!\n";


# Read the directory
opendir my $dh, "."
  or die "Could not read directory: $!\n";
my @files = readdir($dh);
closedir $dh
  or die "Could not stop reading directory: $!\n";

# slurp mode
$/ = undef;

# Go through the files looking for xml
for (@files) {
  next unless /\.xml$/;
  print "$_\n";

  # Read the file
  open my $fh, $_ or die "Could not open file $_: $!\n";
  my $xml = <$fh>;
  close($fh) or die "Error closing file: $!\n";

  # Force overwrite
  my $pass =
    OMP::Password->get_verified_password({
      'prompt' => 'Enter admin password: ',
      'verify' => 'verify_administrator_password',
    }) ;
  OMP::SpServer->storeProgram( $xml, $pass, 1);
}
