#!/local/perl/bin/perl

# Populates project database with initial details
# of JAC staff test projects

# Input: text file containing project details
#
# CSV file containing:
#  Root Project name (person initials, no number)
#  OMP User id
#  TELESCOPE

# If telescope is not supplied it is assumed that half the
# projects created (1->5) will be UKIRT and half (6-10) will
# be JCMT

# Comments are supported

# This information is converted to project details:

#  Project ID
#     thk -> thk01, thk02, thk03 -> thk09
#  Principal Investigator
#      USER ID
#  Co-investigator
#       blank
#  Support
#       support scientist user id
#  Title
#       "Staff testing"
#  Tag priority
#       1
#  country
#       JAC
#  semester  (YYYYA/B)
#        JAC
#  password                [plain text]
#         "omptest"
#  Allocated time (seconds)
#          10000 [3 hours]

# cat proj.details | perl mkproj_staff.pl

# Uses the infrastructure classes so each project is inserted
# independently rather than as a single transaction

use warnings;
use strict;

use FindBin;
use constant OMPLIB => "$FindBin::RealBin/../lib";

use lib OMPLIB;

BEGIN {
    $ENV{'OMP_CFG_DIR'} = File::Spec->catdir(OMPLIB, '../cfg')
        unless exists $ENV{'OMP_CFG_DIR'};
}

use OMP::DB::Backend;
use OMP::Util::Project;
use OMP::Password;

my $force = 0;

my $db = OMP::DB::Backend->new;

OMP::Password->get_verified_auth($db, 'staff');

while (<>) {
    chomp;
    my $line = $_;
    next unless $line =~ /\w/;
    next if $line =~ /^#/;

    # split on comma
    my @file = split /,/, $line, 3;

    my $tel = $file[2];
    $tel = "????" unless $tel;

    # Now need to create some project details:
    my @details = (
        "$file[0]??",
        $file[1],
        '',
        $file[1],
        "Support scientist testing",
        1,
        ["EAO"],
        0,
        "EAO",
        10000,
        $tel,
        undef, undef,
        undef, undef,
        undef, undef,
        undef, undef,
        1,
        undef, undef,
        undef,
    );

    print join('--', grep {defined $_} @details), "\n";

    # Now loop over 9 project ids
    for my $i (1 .. 10) {
        # Calculate the project ID
        $details[0] = $file[0] . sprintf('%02d', $i);

        # Insert telescope
        unless ($file[2]) {
            $details[11] = ($i <= 5 ? 'UKIRT' : 'JCMT');
        }

        # Upload
        OMP::Util::Project->addProject($db, $force, @details);
    }
}
