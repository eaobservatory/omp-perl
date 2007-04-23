#!/local/perl/bin/perl

use strict;

my $err;
BEGIN {
 use Getopt::Long;
 my ($omp1, $omp2);
 my $status = GetOptions("omp1" => \$omp1, "omp2" => \$omp2 );
 if ($omp1 && $omp2) {
   $err = "Can not use both OMP1 and OMP2";
 } elsif ($omp1) {
   $ENV{OMP_DBSERVER} = 'SYB_OMP1';
 } elsif ($omp2) {
   $ENV{OMP_DBSERVER} = 'SYB_OMP2';
 } else {
   $err = "Must specify -omp1 or -omp2";
 }
}
die "$err\n" if defined $err;
my $status = system('/local/perl/bin/perl /jac_sw/omp/msbserver/admin/dumpsciprog.pl');
if ($status != 0) {
  print "Error running dumpsciprog.pl (exit code = $status)\n"
}
