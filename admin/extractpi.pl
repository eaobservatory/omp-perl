#!/local/perl/bin/perl

# Query the database for all projects associated with a specific
# semester and telescope and dump to stdout in a form suitable for use
# as a majordomo mailing list import.

use warnings;

use OMP::ProjServer;

my $SEM = '04A';
my $TEL = 'JCMT';

# Query the database
$projects = OMP::ProjServer->listProjects( "<ProjQuery><semester>$SEM</semester><telescope>$TEL</telescope></ProjQuery>", "object");


# Extract PI users and remove duplicates
my %users = map { $_->pi->userid, $_->pi } @$projects;

# Dump user information sorted
for my $id ( sort keys %users ) {
  print $users{$id}->as_email_hdr ."\n";

}
