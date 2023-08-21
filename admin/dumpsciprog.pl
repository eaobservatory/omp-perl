#!/local/perl/bin/perl

# Dump the contents of the Database
# [currently only the science programs and the project info]
# to disk

# Note: Faults, Feedback and MSBDone info is not dumped!!!!

# The output directory is obtained from $OMP_DUMP_DIR

use 5.006;
use strict;
use warnings;

use FindBin;

use constant OMPLIB => "$FindBin::RealBin/../lib";

BEGIN {
        $ENV{OMP_CFG_DIR} = File::Spec->catdir(OMPLIB, "../cfg")
            unless exists $ENV{OMP_CFG_DIR};
        $ENV{PATH} = "/usr/bin";
      }

use lib OMPLIB;

use OMP::Config;
use OMP::MSBDB;
use OMP::DBbackend;
use OMP::ProjServer;
use OMP::Error qw/ :try /;
use Data::Dumper;
use Time::Piece;
use File::Spec;

# Get the timestamp before doing the query, so we get programs which changed
# while we were doing the export.
my $today = gmtime;

# Abort if $OMP_DUMP_DIR is not set
$ENV{OMP_DUMP_DIR} = '/opt/omp/cache/sciprogs'
  unless exists $ENV{OMP_DUMP_DIR};

chdir $ENV{OMP_DUMP_DIR}
  or die "Error changing to directory $ENV{OMP_DUMP_DIR}: $!\n";

my $dumplog = File::Spec->catfile($ENV{OMP_DUMP_DIR}, "dumpsciprog.log");

# Get the date of the last dump
my $date;
if (-e $dumplog) {
  open my $fh, '<', $dumplog or die "Error opening file $dumplog: $!";
  my $line = <$fh>;
  close $fh;

  # Abort early if nothing at all was read from the file.
  die "Could not read date of last dump from the log file"
    unless defined $line;

  chomp $line;

  # It looks like "gmtime" might accept anything, so check the format here.
  # The check below may not actually ever trigger.
  die "Date of last dump not in expected format"
    unless $line =~ /^\d{10}$/a;

  $date = gmtime($line);
  die "Unable to parse date of last dump!"
    unless $date;
}

my $db = new OMP::MSBDB( DB => new OMP::DBbackend );

# Query the database for all projects whose programs have been modified
# since the last dump

my @projects = $db->listModifiedPrograms($date);

exit unless (@projects);

# Now for each of these projects attempt to read a science program
my $n_err = 0;
for my $projid (@projects) {
  try {

    # Create new DB object using backdoor password
    my $db = new OMP::MSBDB(
                             ProjectID => $projid,
                             DB => new OMP::DBbackend );

    my $xml = $db->fetchSciProg(1, raw => 1);

    print "Retrieved science program for project $projid\n";

    # Write it out
    my $outfile = $projid . ".xml";
    $outfile =~ s/\//_/g;
    open my $fh, '>',  $outfile or die "Error opening outfile, $outfile: $!\n";
    print $fh $xml;
    close $fh;

  } catch OMP::Error::SpBadStructure with {
    # Want to know if a program stored in the DB is truncated
    my $E = shift;
    print "Science program truncated [$projid]: $E\n";
    $n_err ++;
  } otherwise {
    my $E = shift;
    print "Error retrieving program [$projid]: $E\n";
    $n_err ++;
  };

}

# Write date of this dump to the log (using the date logged at the start).
open my $log, '>', $dumplog or die "Error opening file $dumplog: $!";
print $log $today->epoch;
print $log "\nTHIS FILE KEEPS TRACK OF THE MOST RECENT SCIENCE PROGRAM DUMP.\nREMOVING THIS FILE WILL RESULT IN A REFETCH OF ALL SCIENCE PROGRAMS.";
close $log;

# Exit with bad status if errors were encountered.
exit(1) if $n_err;
