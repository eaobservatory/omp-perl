#!/usr/bin/perl

# quick program to create a "database" table for testing the OMP

use strict;
use warnings;
use DBI;
use File::Spec;

my $XMLDIR = "/jac_sw/omp/dbxml";
my $table = "ompmsb";

my $filename = File::Spec->catdir($XMLDIR, "csv");
my $dbh = DBI->connect("DBI:CSV:f_dir=$filename")
  or die "Cannot connect: ". $DBI::errstr;

# Columns are  ID, checksum, projectID, filename

my $sth = $dbh->prepare("CREATE TABLE $table ( id INTEGER, checksum CHAR(64), projectid CHAR(16), filename CHAR(256))") or die "Cannot prepare: " . $dbh->errstr();

$sth->execute() or die "Cannot execute: " . $sth->errstr();
$sth->finish();
$dbh->disconnect();
