#!/local/perl/bin/perl

use strict;

my $err;
BEGIN {
 use Getopt::Long;
 my ($main, $secondary);
 my $status = GetOptions("jac" => \$main, "jac2" => \$secondary );
 if ($main && $secondary) {
   $err = "Can not use both JAC and JAC2";
 } elsif ($main) {
   $ENV{OMP_DBSERVER} = 'SYB_JAC';
 } elsif ($secondary) {
   $ENV{OMP_DBSERVER} = 'SYB_JAC2';
 } else {
   $err = "Must specify -jac or -jac2";
 }
}
die "$err\n" if defined $err;
my $status = system('/local/perl/bin/perl /jac_sw/omp/msbserver/admin/dumpdb.pl');
if ($status != 0) {
  print "Error running dumpdb.pl (exit code = $status)\n";
  exit 1;
}
