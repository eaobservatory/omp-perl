#!/local/bin/perl

# Dump the contents of the omp tables to disk
# [excluding the sciprog, user, obs and msb tables]

use warnings;
use strict;

# Pick up the OMP database
use FindBin;
use lib "$FindBin::RealBin/..";
use OMP::DBbackend;
use Storable qw(nstore);

my $dumpdir = "/DSS/omp-cache/tables";

chdir $dumpdir
  or die "Error changing to directory $dumpdir: $!\n";

# Connect
my $db = new OMP::DBbackend;
my $dbh = $db->handle;

my @tab;
(@ARGV) and @tab = @ARGV or
  @tab = qw/ompproj ompfeedback ompmsbdone ompfault ompfaultbody ompfaultassoc ompsupuser ompcoiuser/;

foreach my $tab (@tab) {
  my $ref = $dbh->selectall_arrayref("SELECT * FROM $tab")
    or die "Cannot select on $tab: ". $DBI::errstr;

  # rename the previous dump
  if (-e $tab) {
    rename($tab, $tab . "_2")
      or die "Cannot rename previous dump file: $!\n";
  }
  nstore($ref, "$tab");

}

$dbh->disconnect;

