#!/local/perl-5.6/bin/perl

# Dump the contents of the Database
# [currently only the science programs and the project info]
# to disk

# Note: Faults, Feedback and MSBDone info is not dumped!!!!

# The output directory is obtained from $OMP_DUMP_DIR

use 5.006;
use strict;
use warnings;
use OMP::SpServer;
use OMP::ProjServer;
use OMP::Error qw/ :try /;
use Data::Dumper;

# Abort if $OMP_DUMP_DIR is not set
die "Must specify output data directory via \$OMP_DUMP_DIR"
  unless exists $ENV{OMP_DUMP_DIR};

chdir $ENV{OMP_DUMP_DIR}
  or die "Error changing to directory $ENV{OMP_DUMP_DIR}: $!\n";


# Now query the database for all projects
my $projects = OMP::ProjServer->listProjects("<ProjQuery></ProjQuery>",
					     "object");


# Now for each of these projects attempt to read a science program
for my $proj (@$projects) {
  my $projid = $proj->projectid;
  try {
    # Use back door password
    my $xml = OMP::SpServer->fetchProgram($projid, "***REMOVED***");
    print "Retrieved science program for project $projid\n";

    # Write it out
    my $outfile = $projid . ".xml";
    $outfile =~ s/\//_/g;
    open my $fh, "> $outfile" or die "Error opening outfile\n";
    print $fh $xml;
    close $fh;

  } otherwise {
    print "No science program available for $projid\n";

  };

}

# Now dump the project info
my $outfile = "projects.dump";
open my $fh, ">$outfile" or die "Error opening file $outfile: $!";
print $fh Dumper($projects);
close $fh;
