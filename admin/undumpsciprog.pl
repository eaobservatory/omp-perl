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

use FindBin;
use constant OMPLIB => "$FindBin::RealBin/../lib";

use lib OMPLIB;

BEGIN {
  $ENV{OMP_CFG_DIR} = File::Spec->catdir( OMPLIB, "../cfg" )
    unless exists $ENV{OMP_CFG_DIR};
};

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


my ($provider, $username, $pass) = OMP::Password->get_userpass();

# slurp mode
$/ = undef;

# Go through the files looking for xml
my $n_err = 0;
foreach my $filename (@files) {
  next unless $filename =~ /\.xml$/;
  print "$filename\n";

  # Read the file
  open my $fh, '<', $filename or die "Could not open file $filename: $!\n";
  my $xml = <$fh>;
  close($fh) or die "Error closing file: $!\n";

  try {
    # Force overwrite
    OMP::SpServer->storeProgram( $xml, $provider, $username, $pass, 1);
  } otherwise {
    my $E = shift;
    print "Error storing science program $filename: $E\n";
    $n_err ++;
  };
}

exit(1) if $n_err;
