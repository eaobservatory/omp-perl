#!/usr/local/bin/perl

# Populates project database with initial details
# of JAC staff

# Input: text file containing project details
#
# CSV file containing:
#  Root Project name (person initials, no number)
#  Staff member
#  computer user id (no jach)

# Comments are supported

# This information is converted to project details:

#  Project ID
#     thk -> thk01, thk02, thk03 -> thk09
#  Principal Investigator
#      Support scientist name
#  PI email
#       tkerr -> tkerr@jach.hawaii.edu
#  Co-investigator
#       blank
#  Co-I email
#       blank
#  Support
#       support scientist name
#  Support email
#       support scientist email
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

# cat proj.details | perl mkproj_ss.pl

# Uses the infrastructure classes so each project is inserted
# independently rather than as a single transaction

use warnings;
use strict;

use OMP::ProjDB;
use OMP::Project;
use OMP::ProjServer;


while (<>) {
  chomp;
  my $line = $_;
  next unless $line =~ /\w/;
  next if $line =~ /^#/;

  # aplit on comma
  my @file  = split(/,/,$line);

  # Now need to create some project details:
  my @details = ("$file[0]??",
		 $file[1],
		 $file[2] . "\@jach.hawaii.edu",
		 '',
		 '',
		 $file[1],
		 $file[2] . "\@jach.hawaii.edu",
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
    OMP::ProjServer->addProject("***REMOVED***", @details[0..12] );
  }

}
