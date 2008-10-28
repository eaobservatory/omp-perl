#!/local/perl/bin/perl
# quick program to create a "database" table for testing the OMP

use strict;
use warnings;
use File::Spec;
use Term::ReadLine;

# Pick up the OMP database
use FindBin;
use lib "$FindBin::RealBin/..";
use OMP::DBbackend;
use OMP::Password;

# First thing we do is ask for a password
my $term = new Term::ReadLine 'Make OMP database tables';

# Needs Term::ReadLine::Gnu
my $attribs = $term->Attribs;
$attribs->{redisplay_function} = $attribs->{shadow_redisplay};
my $password = $term->readline( "Please enter administrator password: ");
$attribs->{redisplay_function} = $attribs->{rl_redisplay};

OMP::Password->verify_administrator_password( $password );

# Connect
my $db = new OMP::DBbackend;
my $dbh = $db->handle;

my %loginhash = $db->loginhash;
print "User: $loginhash{user}\nServer: $loginhash{server}\n";

# Some constants to ensure that the table columns are the same
# type/size when containing identical types of information
use constant PROJECTID => "VARCHAR(32) not null";
use constant USERID => "VARCHAR(32)";
use constant FAULTID => "DOUBLE PRECISION"; # Need this precision
use constant TITLE => "VARCHAR(255) null";

# Sybase stores dates in 'datetime', Postgres in 'timestamp'
my $HAS_AUTO_IDENT = OMP::DBbackend->has_automatic_serial_on_insert();
my $NUMID     = OMP::DBbackend->get_serial_type();
my $DATE      = OMP::DBbackend->get_datetime_type();
my $BOOL      = OMP::DBbackend->get_boolean_type();

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
                         moonmax => "INTEGER",
                         moonmin => "INTEGER",
                         timeest => "REAL",
                         title => TITLE,
                         obscount => "INTEGER",
                         datemin => $DATE,
                         cloudmax => "INTEGER",
                         cloudmin => "INTEGER",
                         datemax => $DATE,
                         telescope => "VARCHAR(16)",
                         minel => "REAL NULL",
                         maxel => "REAL NULL",
                         approach => "INTEGER NULL",
                         skymax => "REAL",
                         skymin => "REAL",
                         _ORDER => [qw/ msbid projectid remaining checksum
                                    obscount taumin taumax seeingmin seeingmax
                                    priority telescope moonmax cloudmax
                                    timeest title datemin datemax minel maxel
                                    approach moonmin cloudmin skymin skymax
                                    /],
                       },
              # Associates users with a project
              # See OMP::ProjDB
              ompprojuser => {
                              uniqid => $NUMID,
                              userid => USERID,
                              projectid => PROJECTID,
                              # PI, COI, SUPPORT
                              capacity => "VARCHAR(16)",
                              contactable => $BOOL,
                              capacity_order => 'TINYINT DEFAULT 0 NOT NULL',
                              _ORDER => [qw/
                                         uniqid projectid userid
                                         capacity contactable capacity_order
                                        /],
                             },
              # General project details
              # See OMP::ProjDB
              ompproj => {
                          projectid => PROJECTID,
                          pi => USERID,
                          remaining => "REAL",
                          pending => "REAL",
                          allocated => "REAL",
                          semester => "VARCHAR(10)",
                          encrypted => "VARCHAR(20)",
                          title => TITLE,
                          telescope => "VARCHAR(16)",
                          taumin => "REAL",
                          taumax => "REAL",
                          seeingmin => "REAL",
                          seeingmax => "REAL",
                          cloudmax => "INTEGER",
                          cloudmin => "INTEGER",
                          skymax => "REAL",
                          skymin => "REAL",
                          state => $BOOL,
                          _ORDER => [qw/projectid pi
                                     title semester encrypted allocated
                                     remaining pending telescope taumin
                                     taumax seeingmin seeingmax cloudmax state
                                     cloudmin skymin skymax
                                     /],
                         },
              # Queue details for each project
              ompprojqueue => {
                               projectid => PROJECTID,
                               isprimary => $BOOL,
                               uniqid => $NUMID,
                               country => 'VARCHAR(32) NOT NULL',
                               tagpriority => 'INTEGER',
                               tagadj => 'INTEGER',
                               _ORDER => [qw/
                                          uniqid projectid country
                                          tagpriority isprimary tagadj
                                         /],
                              },
              # Time accounting for projects
              # See OMP::ProjDB
              omptimeacct => {
                              projectid => PROJECTID,
                              date => $DATE,
                              confirmed => $BOOL,
                              timespent => 'INTEGER',
                              _ORDER => [qw/ date projectid timespent
                                         confirmed
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
                         pol => $BOOL,
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
                             commid => $NUMID,
                             checksum => "VARCHAR(64)",
                             projectid => PROJECTID,
                             date => $DATE,
                             comment => "TEXT",
                             instrument => "VARCHAR(64)",
                             waveband => "VARCHAR(64)",
                             target => "VARCHAR(64)",
                             status => "INTEGER",
                             title => TITLE,
                             userid => USERID . " NULL",
                             _ORDER => [qw/
                                        commid checksum status projectid date
                                        target instrument waveband
                                        comment title userid
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
                              commid => $NUMID,
                              entrynum => "numeric(4,0) not null",
                              projectid => PROJECTID,
                              author => USERID . "null",
                              date => "$DATE not null",
                              subject => "varchar(128) null",
                              program => "varchar(50) not null",
                              sourceinfo => "varchar(60) not null",
                              status => "integer null",
                              text => "text not null",
                              msgtype => "integer null",
                              _ORDER => [qw/
                                         commid entrynum projectid author date
                                         subject program sourceinfo status text
                                         msgtype
                                        /],
                             },
              # Bug/Fault meta-data
              # See OMP::FaultDB
              ompfault => {
                           faultid => FAULTID,
                           entity => "varchar(64) null",
                           type   => "integer",
                           fsystem => "integer",
                           category => "VARCHAR(32)",
                           timelost => "REAL",
                           faultdate => "$DATE null",
                           status => "INTEGER",
                           subject => "VARCHAR(128) null",
                           urgency => "INTEGER",
                           condition => "INTEGER null",
                           _ORDER => [qw/
                                      faultid category subject faultdate type
                                      fsystem status urgency timelost entity
                                      condition
                                      /],
                          },
              # Textual information associated with each fault. Can be
              # responsees or the actual fault report
              # See OMP::FaultDB
              ompfaultbody => {
                               respid => $NUMID,
                               faultid => FAULTID,
                               date => $DATE,
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
                                associd => $NUMID,
                                faultid => FAULTID,
                                projectid => PROJECTID,
                                _ORDER => [qw/ associd faultid projectid /],
                               },
              # Fundamental unit of "user" in the OMP system. All other
              # tables use OMP::User userids rather than explicit names
              # See OMP::UserDB
              ompuser => {
                          userid => USERID,
                          uname => "VARCHAR(255)",
                          email => "VARCHAR(64) NULL",
                          alias => USERID . " NULL",
                          cadcuser => "VARCHAR(16) NULL",
                          _ORDER => [qw/ userid uname email alias cadcuser /],
                         },
              # Comments associated with the observing shift.
              # basically a narrative timestamped log
              # See OMP::ShiftDB
              ompshiftlog => {
                              shiftid => $NUMID,
                              date => $DATE,
                              author => USERID,
                              telescope => "VARCHAR(32)",
                              text => "TEXT",
                              _ORDER => [qw/ shiftid date author
                                             telescope text /],
                             },
              # Observation log table, used to store basic
              # information about observations, along with
              # comments associated with those observations.
              # See OMP::ArchiveDB
              ompobslog => {
                            obslogid => $NUMID,
                            runnr => "INT",
                            instrument => "VARCHAR(32)",
                            telescope => "VARCHAR(32) NULL",
                            date => $DATE,
                            obsactive => "INTEGER",
                            commentdate => $DATE,
                            commentauthor => USERID,
                            commenttext => "TEXT NULL",
                            commentstatus => "INTEGER",
                            _ORDER => [qw/ obslogid runnr instrument telescope
                                           date obsactive commentdate commentauthor
                                           commenttext commentstatus /],
                           },
              # OMP key table, used to store authentication
              # keys which are generated to prevent duplicate form
              # submissions.
              ompkey => {
                         keystring => "VARCHAR(64)",
                         expiry => $DATE,
                         _ORDER => [qw/ keystring expiry /],
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
  next if $table eq 'ompshiftlog';
  next if $table eq 'ompobslog';
  next if $table eq 'omptimeacct';
  next if $table eq 'ompprojuser';
  next if $table eq 'ompprojqueue';
  next if $table eq 'ompkey';

  # Create the SQL for the columns.
  # Note that we currently ignore SERIAL/IDENTITY columns on databases
  # that need named inserts
  my $str = join(", ", map {
    "$_ " .$tables{$table}->{$_}
  } grep {
    # Always return TRUE if we are not a NUMID column
    if ($tables{$table}->{$_} ne $NUMID ) {
      1;
    } elsif ($HAS_AUTO_IDENT) {
      1;
    } else {
      0;
    }
  } @{ $tables{$table}{_ORDER}} );

  # Make sure we mean it
  my $confirm = $term->readline( "Dropping/Creating table $table. ".
                                 "Are you sure [y/n]: ");

  next unless $confirm =~ /^y/i;

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

  # No need to do the following, since omp database is owned by login 'omp'
  # We can grant permission on this table as well
  #  $dbh->do("GRANT ALL ON $table TO omp")
  #    or die "Error1: $DBI::errstr";

}

# Close connection
$dbh->disconnect();

