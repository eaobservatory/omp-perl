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

#$server = "SYB_OMP";
#$database = "omp";

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
			 title => "VARCHAR(255)",
			 obscount => "INTEGER",
			 earliest => "DATETIME",
			 latest => "DATETIME",
			 telescope => "VARCHAR(16)",
			 _ORDER => [qw/ msbid projectid remaining checksum
				    obscount tauband seeing priority
				    telescope moon
				    timeest title earliest latest
				    /],
		       },
	      ompproj => {
			  projectid => "VARCHAR(32)",
			  pi => "VARCHAR(255)",
			  piemail => "VARCHAR(64)",
			  coi => "VARCHAR(255) NULL",
			  coiemail => "VARCHAR(64) NULL",
			  remaining => "REAL",
			  pending => "REAL",
			  allocated => "REAL",
			  country => "VARCHAR(32)",
			  tagpriority => "INTEGER",
			  semester => "VARCHAR(5)",
			  password => "VARCHAR(10)",
			  _ORDER => [qw/projectid pi piemail
				     coi coiemail tagpriority
				     country semester password allocated
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
			 pol => "INTEGER",
			 timeest => "REAL",
			 type => "VARCHAR(32)",
			 _ORDER => [qw/obsid msbid projectid
				    instrument type pol wavelength coordstype
				    target ra2000 dec2000 el1 el2
				    el3 el4 el5 el6 el7 el8 timeest
				    /],
			},
	      ompsciprog => {
			     projectid => "VARCHAR(32)",
			     timestamp => "INTEGER",
			     sciprog   => "TEXT",
			     _ORDER => [qw/
					projectid timestamp sciprog
					/],
			     },
	      ompfeedback => {
			      commid => "numeric(5,0) IDENTITY",
			      projid => "char(9) not null",
			      author => "char(50) not null",
			      date => "datetime not null",
			      subject => "char(128) null",
			      program => "char(50) not null",
			      sourceinfo => "char(60) not null",
			      status => "bit not null",
			      text => "text not null",
			      _ORDER => [qw/
					 commid projid author date subject
					 program sourceinfo status text
					/],
			     },
	     );

for my $table (sort keys %tables) {
   next if $table eq 'ompproj';
   next if $table eq 'ompsciprog';
   next if $table eq 'ompmsb';
   next if $table eq 'ompobs';
 # next if $table eq 'ompfeedback';

  my $str = join(", ", map {
    "$_ " .$tables{$table}->{$_}
  } @{ $tables{$table}{_ORDER}} );

   my $sth;
   print "Drop table $table\n";
   $sth = $dbh->prepare("DROP TABLE $table")
    or die "Cannot drop table $table: ". $dbh->errstr();

   $sth->execute() or die "Cannot execute: " . $sth->errstr();
   $sth->finish();

  print "\n$table: $str\n";
  print "SQL: CREATE TABLE $table ($str)\n";
  $sth = $dbh->prepare("CREATE TABLE $table ($str)")
    or die "Cannot create table $table: ". $dbh->errstr();

  $sth->execute() or die "Cannot execute: " . $sth->errstr();
  $sth->finish();

  # We can grant permission on this table as well
  $dbh->do("GRANT ALL ON $table TO omp")
    or die "Error1: $DBI::errstr";

}

# Close connection
$dbh->disconnect();
