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

my $dbh = DBI->connect("dbi:Sybase:server=${server};database=${database};timeout=120", $dbuser, $dbpwd,{RaiseError => 0, PrintError => 0})
  or die "Cannot connect: ". $DBI::errstr;


my %tables = (
	      ompmsb => {
			 msbid => "INTEGER",
			 projectid=> "VARCHAR(32)",
			 remaining => "INTEGER",
			 checksum => "VARCHAR(64)",
			 taumin => "REAL",
			 taumax => "REAL",
			 seeingmin => "REAL",
			 seeingmax => "REAL",
			 priority => "INTEGER",
			 moon => "INTEGER",
			 timeest => "REAL",
			 title => "VARCHAR(255)",
			 obscount => "INTEGER",
			 earliest => "DATETIME",
			 cloud => "INTEGER",
			 latest => "DATETIME",
			 telescope => "VARCHAR(16)",
			 _ORDER => [qw/ msbid projectid remaining checksum
				    obscount taumin taumax seeingmin seeingmax
				    priority telescope moon cloud
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
			  encrypted => "VARCHAR(20)",
			  title => "VARCHAR(132)",
			  support => "VARCHAR(255) NULL",
			  supportemail => "VARCHAR(64) NULL",
			  _ORDER => [qw/projectid pi piemail
				     coi coiemail support supportemail
				     title tagpriority
				     country semester encrypted allocated
				     remaining pending
				     /],
			 },
	      ompobs => {
			 obsid => "INTEGER",
			 msbid => "INTEGER",
			 projectid => "VARCHAR(32)",
			 instrument => "VARCHAR(32)",
			 wavelength => "REAL",
			 disperser => "VARCHAR(32) NULL",
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
			 pol => "BIT",
			 timeest => "REAL",
			 type => "VARCHAR(32)",
			 _ORDER => [qw/obsid msbid projectid
				    instrument type pol wavelength disperser
				    coordstype target ra2000 dec2000 el1 el2
				    el3 el4 el5 el6 el7 el8 timeest
				    /],
			},
	      ompmsbdone => {
			     commid => "numeric(5,0) IDENTITY",
			     checksum => "VARCHAR(64)",
			     projectid => "VARCHAR(32)",
			     date => "DATETIME",
			     comment => "TEXT",
			     instrument => "VARCHAR(64)",
			     waveband => "VARCHAR(64)",
			     target => "VARCHAR(64)",
			     status => "INTEGER",
			     _ORDER => [qw/
					commid checksum status projectid date
					target instrument waveband
					comment
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
			      projectid => "char(9) not null",
			      author => "char(50) not null",
			      date => "datetime not null",
			      subject => "char(128) null",
			      program => "char(50) not null",
			      sourceinfo => "char(60) not null",
			      status => "integer null",
			      text => "text not null",
			      _ORDER => [qw/
					 commid projectid author date subject
					 program sourceinfo status text
					/],
			     },
	     );

for my $table (sort keys %tables) {
  # Comment out as required
  next if $table eq 'ompproj';
  next if $table eq 'ompsciprog';
  next if $table eq 'ompmsb';
  next if $table eq 'ompobs';
  next if $table eq 'ompfeedback';
  next if $table eq 'ompmsbdone';

  my $str = join(", ", map {
    "$_ " .$tables{$table}->{$_}
  } @{ $tables{$table}{_ORDER}} );

  # Usually a failure to drop is non fatal since it
  # indicates that the table is not there to drop
  my $sth;
  print "Drop table $table\n";
  $sth = $dbh->prepare("DROP TABLE $table")
    or die "Cannot prepare SQL to drop table";

  $sth->execute();
  $sth->finish();

  print "\n$table: $str\n";
  print "SQL: CREATE TABLE $table ($str)\n";
  $sth = $dbh->prepare("CREATE TABLE $table ($str)")
    or die "Cannot prepare SQL for CREATE table $table: ". $dbh->errstr();

  $sth->execute() or die "Cannot execute: " . $sth->errstr();
  $sth->finish();

  # We can grant permission on this table as well
  $dbh->do("GRANT ALL ON $table TO omp")
    or die "Error1: $DBI::errstr";

}

# Close connection
$dbh->disconnect();
