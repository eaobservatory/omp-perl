#!/local/perl/bin/perl

# Query the database for all projects associated with a specific
# semester and telescope and dump to stdout in a form suitable for use
# as a majordomo mailing list import.

use warnings;
use strict;

use FindBin;
use constant OMPLIB => "$FindBin::RealBin/..";

use lib OMPLIB;

BEGIN {
  $ENV{OMP_CFG_DIR} = File::Spec->catdir( OMPLIB, "cfg" )
    unless exists $ENV{OMP_CFG_DIR};
};

use OMP::ProjServer;

my $SEM = '04A';
my $TEL = 'JCMT';

# Query the database
my $projects = OMP::ProjServer->listProjects( "<ProjQuery><semester>$SEM</semester><telescope>$TEL</telescope></ProjQuery>", "object");


# Extract PI users and remove duplicates
my %users = map { $_->pi->userid, $_->pi } @$projects;

# Dump user information sorted
for my $id ( sort keys %users ) {
  print $users{$id}->as_email_hdr ."\n";

}
