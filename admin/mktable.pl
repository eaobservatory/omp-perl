#!/usr/bin/perl

# quick program to create a "database" table for testing the OMP

use strict;
use warnings;
use DBI;
use File::Spec;

my $server = "SYB_UKIRT";
my $dbuser = "sa";
my $dbpwd  = "";
my $database = "archive";


my $dbh = DBI->connect("dbi:Sybase:server=${server};database=${database};timeout=120", $dbuser, $dbpwd)
  or die "Cannot connect: ". $DBI::errstr;


my %tables = (
	      ompmsb => {
			 msbid => "INTEGER",
			 projectid=> "VARCHAR(32)",
			 remaining => "INTEGER",
			 checksum => "VARCHAR(64)",
			 tauband => "INTEGER",
			 seeing => "INTEGER",
			 priority => "INTEGER",
			 moon => "INTEGER NULL",
			 timeest => "REAL",
			 sciprog => "VARCHAR(255)",
			 title => "VARCHAR(255)",
			 obscount => "INTEGER",
			 _ORDER => [qw/ msbid projectid remaining checksum
				    obscount tauband seeing priority moon 
				    timeest sciprog title
				    /],
		       },
	      ompproj => {
			  projectid => "VARCHAR(32)",
			  pi => "VARCHAR(255)",
			  piemail => "VARCHAR(64)",
			  coi => "VARCHAR(255)",
			  coiemail => "VARCHAR(64)",
			  remaining => "REAL",
			  pending => "REAL",
			  allocated => "REAL",
			  country => "VARCHAR(32)",
			  tagpriority => "INTEGER",
			  semester => "VARCHAR(5)",
			  _ORDER => [qw/projectid pi piemail
				     coi coiemail tagpriority
				     country semester allocated
				     remaining pending
				     /],
			 },
	      ompobs => {
			 obsid => "INTEGER",
			 msbid => "INTEGER",
			 projectid => "VARCHAR(32)",
			 instrument => "VARCHAR(32)",
			 wavelength => "REAL",
			 coordstype => "VARCHAR(32)",
			 target => "VARCHAR(32)",
			 ra2000 => "REAL NULL",
			 dec2000 => "REAL NULL",
			 el1 => "REAL NULL",
			 el2 => "REAL NULL",
			 el3 => "REAL NULL",
			 el4 => "REAL NULL",
			 el5 => "REAL NULL",
			 el6 => "REAL NULL",
			 el7 => "REAL NULL",
			 el8 => "REAL NULL",
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

  # We can grant permission on this table as well
  $dbh->do("GRANT ALL ON $table TO omp")
    or die "Error1: $DBI::errstr";

}

# Close connection
$dbh->disconnect();
