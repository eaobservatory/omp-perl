#!/usr/local/bin/perl

# Populates project database with initial details
# of JAC staff

# Input: text file containing project details
#
# CSV file containing:
#  Root Project name (person initials, no number)
#  OMP User id

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

while (<>) {
  chomp;
  my $line = $_;
  next unless $line =~ /\w/;
  next if $line =~ /^#/;

  # split on comma
  my @file  = split(/,/,$line);




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
		 10000,
		);

  print join("--",@details),"\n";

  # Now loop over 9 project ids
  for my $i (1..9) {
    # Calculate the project ID
    $details[0] = $file[0] . sprintf("%02d", $i);

    # Upload
    OMP::ProjServer->addProject("***REMOVED***", @details[0..9] );
  }

}
