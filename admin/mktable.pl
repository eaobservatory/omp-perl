#!/local/perl-5.6/bin/perl5.6.1

# quick program to create a "database" table for testing the OMP

use strict;
use warnings;
use File::Spec;

# Pick up the OMP database
use FindBin;
use lib "$FindBin::RealBin/..";
use OMP::DBbackend;

# Connect
my $db = new OMP::DBbackend;
my $dbh = $db->handle;

# Some constants to ensure that the table columns are the same
# type/size when containing identical types of information
use constant PROJECTID => "VARCHAR(32) not null";
use constant USERID => "VARCHAR(32)";
use constant FAULTID => "DOUBLE PRECISION"; # Need this precision
use constant NUMID => "numberic(5,0) IDENTITY";

# Actual table descriptions
my %tables = (
	      # Fundamental scheduling table. Deals with information
              # that is part of a single MSB
	      # Used mainly in OMP::MSBDB
	      ompmsb => {
			 msbid => "INTEGER",
			 projectid=> PROJECTID,
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
			 datemin => "DATETIME",
			 cloud => "INTEGER",
			 datemax => "DATETIME",
			 telescope => "VARCHAR(16)",
			 _ORDER => [qw/ msbid projectid remaining checksum
				    obscount taumin taumax seeingmin seeingmax
				    priority telescope moon cloud
				    timeest title datemin datemax
				    /],
		       },
	      # Associates individual Co-Is with associated projects
	      # See OMP::ProjDB
	      ompcoiuser => {
			     userid => USERID . " NULL",
			     projectid => PROJECTID,
			     _ORDER => [ qw/ projectid userid /],
			    },
	      # Associates individual support scientists with
	      # associated projects
	      # See OMP::ProjDB
	      ompsupuser => {
			     userid => USERID . " NULL",
			     projectid => PROJECTID,
			     _ORDER => [ qw/ projectid userid /],
			    },
	      # General project details
	      # See OMP::ProjDB
	      ompproj => {
			  projectid => PROJECTID,
			  pi => USERID,
			  remaining => "REAL",
			  pending => "REAL",
			  allocated => "REAL",
			  country => "VARCHAR(32)",
			  tagpriority => "INTEGER",
			  semester => "VARCHAR(5)",
			  encrypted => "VARCHAR(20)",
			  title => "VARCHAR(255)",
			  telescope => "VARCHAR(16)",
			  _ORDER => [qw/projectid pi
				     title tagpriority
				     country semester encrypted allocated
				     remaining pending telescope
				     /],
			 },
	      # Scheduling information associated with observations
	      # that are present in MSBs.
	      # See OMP::MSBDB
	      ompobs => {
			 obsid => "INTEGER",
			 msbid => "INTEGER",
			 projectid => PROJECTID,
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
	      # Log of messages/comments associated with a particular MSB
	      # Could just as easily be called "ompmsblog". Name derives
	      # from the fact that this table is the only place where
	      # we explicitly log when an MSB is observed (done)
	      # See OMP::MSBDoneDB
	      ompmsbdone => {
			     commid => "numeric(5,0) IDENTITY",
			     checksum => "VARCHAR(64)",
			     projectid => PROJECTID,
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
	      # XML representation of the science program. Store it in
	      # a table so we dont  have to worry about file locking.
	      # See OMP::MSBDB
	      ompsciprog => {
			     projectid => PROJECTID,
			     timestamp => "INTEGER",
			     sciprog   => "TEXT",
			     _ORDER => [qw/
					projectid timestamp sciprog
					/],
			     },
	      # General comments associated with a project.
	      # See OMP::FeedbackDB
	      ompfeedback => {
			      commid => NUMID,
			      entrynum => "numeric(4,0) not null",
			      projectid => PROJECTID,
			      author => USERID ." not null",
			      date => "datetime not null",
			      subject => "varchar(128) null",
			      program => "varchar(50) not null",
			      sourceinfo => "varchar(60) not null",
			      status => "integer null",
			      text => "text not null",
			      _ORDER => [qw/
					 commid entrynum projectid author date
					 subject program sourceinfo status text
					/],
			     },
	      # Bug/Fault meta-data
	      # See OMP::FaultDB
	      ompfault => {
			   faultid => FAULTID,
			   entity => "varchar(64) null",
			   type   => "integer",
			   system => "integer",
			   category => "VARCHAR(32)",
			   timelost => "REAL",
			   faultdate => "datetime null",
			   status => "INTEGER",
			   subject => "VARCHAR(128) null",
			   urgency => "INTEGER",
			   _ORDER => [qw/
				      faultid category subject faultdate type
				      system status urgency timelost entity
				      /],
			  },
	      # Textual information associated with each fault. Can be
	      # responsees or the actual fault report
	      # See OMP::FaultDB
	      ompfaultbody => {
			       respid => NUMID,
			       faultid => FAULTID,
			       date => "datetime",
			       isfault => "integer",
			       text => "text",
			       author => USERID,
			       _ORDER => [qw/
					  respid faultid date author isfault
					  text
					  /],
			      },
	      # Table associating individual faults with projects
	      # See OMP::FaultDB
	      ompfaultassoc => {
				associd => NUMID,
				faultid => FAULTID,
				projectid => PROJECTID,
				_ORDER => [qw/ associd faultid projectid /],
			       },
	      # Fundamental unit of "user" in the OMP system. All other
	      # tables use OMP::User userids rather than explicit names
	      # See OMP::UserDB
	      ompuser => {
			  userid => USERID,
			  name => "VARCHAR(255)",
			  email => "VARCHAR(64)",
			  _ORDER => [qw/ userid name email /],
			 },
	      # Comments associated with the observing shift.
	      # basically a narrative timestamped log
	      # See OMP::ShiftDB
	      ompshiftlog => {
			      shiftid => NUMID,
			      date => "DATETIME",
			      author => USERID,
			      text => "TEXT",
			      _ORDER => [qw/ shiftid date author text /],
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
  next if $table eq 'ompfault';
  next if $table eq 'ompfaultbody';
  next if $table eq 'ompfaultassoc';
  next if $table eq 'ompuser';
  next if $table eq 'ompsupuser';
  next if $table eq 'ompcoiuser';
  next if $table eq 'ompshiftlog';

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
