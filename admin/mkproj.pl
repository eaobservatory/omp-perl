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
#  Tag priority
#  country 
#  semester  (YYYYA/B)
#  Allocated time (hours)

# cat proj.details | perl mkproj.pl

# BUGS: Each project is inserted independently rather than as
#       a single transaction

use warnings;
use strict;
use DBI;

my $DBserver = "SYB_UKIRT";
my $DBuser = "omp";
my $DBpwd  = "***REMOVED***";
my $DBdatabase = "archive";


my $dbh = DBI->connect("dbi:Sybase:server=${DBserver};database=${DBdatabase};timeout=120", $DBuser, $DBpwd)
  or die "Cannot connect: ". $DBI::errstr;


while (<>) {
  chomp;
  my $line = $_;

  # We have to guess the order
  my @details  = split(/,/,$line);
  print join("--",@details),"\n";
  # insert into the table
  $dbh->do("INSERT INTO ompproj VALUES (?,?,?,?,?,?,?,?,?,?,?)", undef,
	  @details, $details[7],0)
    or die "Cannot insert into ompproj: ". $DBI::errstr;

}

# Close connection
$dbh->disconnect();
