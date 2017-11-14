#!/local/perl/bin/perl

use warnings; use strict;

use Time::Piece;

my $date = localtime;
my $tarfile = 'ompbak_'. $date->strftime("%Y%m%d") .'.tar.gz';

my $arc_dir = '/export/data/jcmtdata/jcmtarch/ompbak';
chdir $arc_dir
  or die "Could not change directory to $arc_dir: $!\n";

my $output = qx!/bin/tar -zcvf $tarfile omp3 omp4 2>&1!
  or die "Error creating tar archive: $!\n";

print $output;

