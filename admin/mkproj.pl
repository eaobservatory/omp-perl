#!/usr/local/bin/perl

# Populates project database with initial details

# Input: text file containing project details
#
# CSV file containing:
#  Project name
#  Principal Investigator
#  PI email
#  Co-investigator
#  Co-I email
#  Title
#  Tag priority
#  country 
#  semester  (YYYYA/B)
#  password                [plain text]
#  Allocated time (hours)

# cat proj.details | perl mkproj.pl

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

  # We have to guess the order
  my @details  = split(/,/,$line);
  print join("--",@details),"\n";

  # Password should be supplied by user
  OMP::ProjServer->addProject("***REMOVED***", @details );

}
