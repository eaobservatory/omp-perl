#!/usr/bin/perl

# quick program to create a "database" table for testing the OMP

use strict;
use warnings;
use DBI;
use File::Spec;

my $dbdir = "/jac_sw/omp/dbxml/csv";

my $dbh = DBI->connect("DBI:CSV:f_dir=$dbdir")
  or die "Cannot connect: ". $DBI::errstr;


my %tables = (
	      ompmsb => {
			 msbid => "INTEGER",
			 projectid=> "INTEGER",
			 remaining => "INTEGER",
			 checksum => "CHAR(64)",
			 tauband => "INTEGER",
			 seeing => "INTEGER",
			 priority => "INTEGER",
			 moon => "INTEGER",
			 timeest => "REAL",
			 sciprog => "CHAR(256)",
			 _ORDER => [qw/ msbid projectid remaining checksum
				    tauband seeing priority moon timeest 
				    sciprog
				    /],
		       },
	      ompproj => {
			  projectid => "CHAR(32)",
			  pi => "CHAR(256)",
			  piemail => "CHAR(64)",
			  coi => "CHAR(256)",
			  coiemail => "CHAR(64)",
			  remaining => "REAL",
			  pending => "REAL",
			  allocated => "REAL",
			  country => "CHAR(32)",
			  tagpriority => "INTEGER",
			  semester => "CHAR(5)",
			  _ORDER => [qw/projectid pi piemail
				     coi coiemail tagpriority
				     country semester allocated
				     remaining pending
				     /],
			 },
	      ompobs => {
			 obsid => "INTEGER",
			 msbid => "INTEGER",
			 projectid => "INTEGER",
			 instrument => "CHAR(32)",
			 wavelength => "REAL",
			 coordstype => "CHAR(32)",
			 target => "CHAR(32)",
			 ra2000 => "REAL",
			 dec2000 => "REAL",
			 el1 => "REAL",
			 el2 => "REAL",
			 el3 => "REAL",
			 el4 => "REAL",
			 el5 => "REAL",
			 el6 => "REAL",
			 el7 => "REAL",
			 el8 => "REAL",
			 _ORDER => [qw/obsid msbid projectid
				    instrument wavelength coordstype
				    target ra2000 dec2000 el1 el2
				    el3 el4 el5 el6 el7 el8
				    /],
			},
	     );

for my $table (sort keys %tables) {
  my $str = join(", ", map {
    "$_ " .$tables{$table}->{$_}
  } @{ $tables{$table}{_ORDER}} );
  print "$table: $str\n";
  my $sth = $dbh->prepare("CREATE TABLE $table ($str)")
    or die "Cannot prepare table $table: ". $dbh->errstr();

  $sth->execute() or die "Cannot execute: " . $sth->errstr();
  $sth->finish();
}

# Close connection
$dbh->disconnect();
