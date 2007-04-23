#!/local/perl/bin/perl

BEGIN {$ENV{OMP_DBSERVER} = 'SYB_OMP2';}
$status = system('/local/perl/bin/perl /jac_sw/omp/msbserver/admin/dumpdb.pl');
