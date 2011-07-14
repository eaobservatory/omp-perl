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

use OMP::ProjDB;
use OMP::Project;
use OMP::ProjServer;
use OMP::User;
use OMP::UserServer;
use OMP::Password;

my $force = 0;

my $pass = OMP::Password->get_verified_password({
                'prompt' => 'Enter administrator password: ',
                'verify' => 'verify_administrator_password',
            }) ;

while (<>) {
  chomp;
  my $line = $_;
  next unless $line =~ /\w/;
  next if $line =~ /^#/;

  # split on comma
  my @file  = split(/,/,$line,3);

  my $tel = $file[2];
  $tel = "????" unless $tel;


  # Now need to create some project details:
  my @details = ("$file[0]??",
		 $file[1],
		 '',
		 $file[1],
		 "Support scientist testing",
		 1,
		 "JAC",
		 "JAC",
		 "omptest",  # Password should be supplied by user
		 10000,$tel
		);

  print join("--",@details),"\n";

  # Now loop over 9 project ids
  for my $i (1..10) {
    # Calculate the project ID
    $details[0] = $file[0] . sprintf("%02d", $i);

    # Insert telescope
    if (!$file[2]) {
      $details[10] = ( $i <= 5 ? "UKIRT" : "JCMT" );
    }

    # Upload
    OMP::ProjServer->addProject( $pass, $force, @details[0..10] );
  }

}
