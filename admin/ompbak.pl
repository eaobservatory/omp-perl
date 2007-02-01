use Time::Piece;

my $date = localtime;
my $tarfile = 'ompbak_'. $date->strftime("%Y%m%d") .'.tar.gz';

chdir "/export/data/jcmtarch/ompbak";

my $output = qx!/bin/tar -zcvf $tarfile omp1 omp2!
  or die "Error creating tar archive: $!\n";
