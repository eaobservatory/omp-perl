#!/usr/local/bin/perl

# Populates project database with initial details

# Input: text file containing project details
#
# CSV file containing:
#  Project name
#  Principal Investigator [as userid]
#  Co-investigator  [colon separated]
#  Support           [colon separated]
#  Title
#  Tag priority
#  country 
#  semester  (YYYYA/B)
#  password                [plain text]
#  Allocated time (seconds)

# cat proj.details | perl mkproj.pl

# Uses the infrastructure classes so each project is inserted
# independently rather than as a single transaction

# Comments are skipped

use warnings;
use strict;

use OMP::ProjDB;
use OMP::Project;
use OMP::ProjServer;


while (<>) {
  chomp;
  my $line = $_;

  # Comments
  $line =~ s/\#.*//;
  next unless length($line) > 0;

  # We have to guess the order
  my @details  = split(/,/,$line);
  print join("--",@details),"\n";

  # Password should be supplied by user
  OMP::ProjServer->addProject("***REMOVED***", @details[0..9] );

}
