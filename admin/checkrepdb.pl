use warnings;
use strict;

use FindBin;
use lib "$FindBin::RealBin/..";

use Getopt::Long qw(:config gnu_compat no_ignore_case no_debug);
use Pod::Usage;
use MIME::Lite;
use List::Util qw/ max /;
use OMP::BaseDB;
use OMP::DBbackend;
use OMP::Error qw/ :try /;
use OMP::KeyDB;

my $msg;
my $trunc;
my $missing;
my $row_count;
my $missing_msb;
my $critical;
my $fault = 0;

# Roles are as defined by the enteries in a "interfaces" file.  In this case,
# they are based on the file as found in "/local/progs/sybase".
my $primary_db = "SYB_JAC";
my $secondary_db = "SYB_JAC2";

my ( @to_addr, @cc_addr, $debug);

{
  my $help;
  GetOptions(
    'h|help' => \$help,
    'p|pri|primary=s' => \$primary_db,
    's|sec|secondary=s' => \$secondary_db,
    'to=s' => \@to_addr,
    'cc=s' => \@cc_addr,
    'debug' => \$debug
  ) || die pod2usage( '-exitval' => 2, '-verbose' => 1 );

  pod2usage( '-exitval' => 1, '-verbose' => 2 ) if $help;
}

#  Default address.
@to_addr = ( 'omp_group@jach.hawaii.edu' )
  if 0 == scalar @to_addr + scalar @cc_addr ;

my $primary_kdb;
my $secondary_kdb;
my $primary_db_down;
my $secondary_db_down;

# Do insert on primary DB
$ENV{OMP_DBSERVER} = $primary_db;
try {
  $primary_kdb = new OMP::KeyDB( DB => new OMP::DBbackend );
} catch OMP::Error with {
  my $E = shift;
  $primary_db_down = 1;
  $critical = 1;
};

$msg .= make_server_status( $primary_db, $primary_db_down );

my $key = !!$primary_kdb && $primary_kdb->genKey();

sleep 20;

# Look for insert on replicate DB
$ENV{OMP_DBSERVER} = $secondary_db;
try {
  $secondary_kdb = new OMP::KeyDB( DB => new OMP::DBbackend(1) )
} catch OMP::Error with {
  $secondary_db_down = 1;
  $critical = 1;
};

$msg .= make_server_status( $secondary_db, $secondary_db_down );

my $verify = !!$secondary_kdb && $secondary_kdb->verifyKey($key);

if ($primary_db_down or $secondary_db_down) {
  $msg .= "\nCannot proceed with tests.\n";
}

unless ($primary_db_down or $secondary_db_down) {
  if ($verify) {
    $msg .= "\nReplication server ($primary_db -> $secondary_db) is actively replicating. [OK]\n\n";
  } else {
    $critical = 1;
    $msg .= <<"REP_SERVER";

Replication server ($primary_db -> $secondary_db) is not replicating!
(key used to verify was $key)

REP_SERVER
  }

  # Check for truncated science programs
  my $sql = "SELECT projectid FROM ompsciprog WHERE sciprog not like \"%</SpProg>%\"";

  my %results;
  for my $dbserver ( $primary_db, $secondary_db ) {
    $ENV{OMP_DBSERVER} = $dbserver;
    my $db = new OMP::BaseDB( DB => new OMP::DBbackend(1) );

    my $ref = $db->_db_retrieve_data_ashash( $sql );

    if ($ref->[0]) {
      map {push @{$results{$dbserver}}, $_->{projectid}} @$ref;
    }
  }

  if (%results) {
    $trunc = 1;
    $fault++;
    $msg .= "Truncated science programs found!\n";
    for my $dbserver (keys %results) {
      $msg .= "$dbserver:\n";
      map {$msg .= "\t$_\n"} @{$results{$dbserver}};
      $msg .= "\n";
    }
  } else {
    $msg .= "No truncated science programs found. [OK]\n\n";
  }

  # Check for missing science programs
  my $missing_sql = "SELECT DISTINCT F.projectid\n".
    "FROM ompfeedback F, ompsciprog S\n".
      "WHERE F.projectid = S.projectid\n".
        "AND F.msgtype = 70\n".
          "AND S.sciprog LIKE NULL";

  my %missing_results;
  for my $dbserver ( $primary_db, $secondary_db ) {
    $ENV{OMP_DBSERVER} = $dbserver;
    my $db = new OMP::BaseDB( DB => new OMP::DBbackend(1) );

    my $ref = $db->_db_retrieve_data_ashash( $sql );

        if ($ref->[0]) {
      map {push @{$results{$dbserver}}, $_->{projectid}} @$ref;
    }
  }

  if (%missing_results) {
    $missing = 1;
    $fault++;
    $msg .= "Missing programs detected!\n";
    for my $dbserver (keys %results) {
      $msg .= "$dbserver:\n";
      map {$msg .= "\t$_\n"} @{$results{$dbserver}};
      $msg .= "\n";
    }
  } else {
    $msg .= "All science programs are present. [OK]\n\n";
  }

  # Compare row counts for disparity
  my %row_count_results;
  for my $dbserver ( $primary_db, $secondary_db ) {
    $ENV{OMP_DBSERVER} = $dbserver;
    my $db = new OMP::BaseDB( DB => new OMP::DBbackend(1) );
    for my $table (qw/ompfault ompfaultassoc ompfaultbody ompfeedback
                      ompmsb ompmsbdone ompobs ompobslog ompproj
                      ompprojqueue ompprojuser ompshiftlog ompsciprog
                      omptimeacct ompuser ompkey/) {
      my $sql = "SELECT COUNT(*) AS \'count\' FROM $table";

      my $ref = $db->_db_retrieve_data_ashash( $sql );
      $row_count_results{$dbserver}{$table} = $ref->[0]->{count};
    }
  }

  my @row_count_disparity;
  for my $table (keys %{$row_count_results{ $primary_db }}) {
    if ($row_count_results{ $primary_db }{$table} ne $row_count_results{ $secondary_db }{$table}) {
      push(@row_count_disparity, $table)
        unless $table eq 'ompkey';
    }
  }

  if ($row_count_disparity[0]) {
    $row_count = 1;
    $fault++;
    $msg .= <<"DISPARITY";
Disparity in row counts detected between $primary_db & $secondary_db!
The following tables are affected:
DISPARITY

    $msg .=
      make_diff_status( $row_count_results{ $primary_db },
                        $row_count_results{ $secondary_db },
                        @row_count_disparity
                      );
    $msg .= "\n";
  } else {
    $msg .= "Row counts are equal across both databases. [OK]\n\n";
  }

  # Make sure MSBs are present if there's a science program
  for my $dbserver ( $primary_db, $secondary_db ) {
    $ENV{OMP_DBSERVER} = $dbserver;
    my $db = new OMP::BaseDB( DB => new OMP::DBbackend(1) );
    my $sql = "SELECT projectid FROM ompsciprog\n".
      "WHERE projectid NOT IN (SELECT DISTINCT projectid FROM ompmsb)";

    my $ref = $db->_db_retrieve_data_ashash( $sql );

    my @really_missing;
    if ($ref->[0]) {
      for my $row (@$ref) {
        my $projectid = $row->{projectid};
        my $sql = "SELECT projectid FROM ompsciprog\n".
          "WHERE projectid = '$projectid' AND sciprog NOT LIKE '%<SpObs%'";

        my $really_missing_ref = $db->_db_retrieve_data_ashash( $sql );
        push @really_missing, $projectid
          unless ($really_missing_ref->[0]);
      }
    }

    if ($really_missing[0]) {
      $missing_msb = 1;
      $fault++;

      $msg .= "Missing MSBs detected on ${dbserver}!\n";
      $msg .= "The following projects are affected:\n";
      for my $projectid (@really_missing) {
        $msg .= "\t$projectid\n";
      }
      $msg .= "\n";
    }
  }
  if (! $missing_msb) {
    $msg .= "MSBs are present for each science program. [OK]\n\n";
  }
}

my $subject;
if ($critical) {
  $subject = 'CRITICAL!';
} elsif ($fault > 1) {
  $subject = 'MULTIPLE FAULTS!';
} elsif ($trunc) {
  $subject = 'TRUNCATED PROGRAMS FOUND!';
} elsif ($missing) {
  $subject = 'MISSING PROGRAMS DETECTED!';
} elsif ($row_count) {
  $subject = 'ROW COUNT DISPARITY DETECTED!';
} elsif ($missing_msb) {
  $subject = 'MISSING MSBS DETECTED!';
} else {
  $subject = 'OK';
}
$subject .= " - Replication status ($primary_db -> $secondary_db)";

unless ( $debug ) {

  my %addr =
    (
      scalar @to_addr ? ( 'To' => join ', ', @to_addr ) : (),
      scalar @cc_addr ? ( 'Cc' => join ', ', @cc_addr ) : ()
    );
  send_mail( $subject, $msg, %addr );
}
else {

  warn $msg;
}

exit;

sub send_mail {

  my ( $subj, $msg, %addr ) = @_;

  my $email = MIME::Lite->new( From => 'jcmtarch@jach.hawaii.edu',
                                %addr,
                                Subject => $subject,
                                Data => $msg,
                              );

  MIME::Lite->send("smtp", "mailhost", Timeout => 30);

  # Send the message
  $email->send
    or die "Error sending message: $!\n";
}

sub make_server_status {

  my ( $server, $down ) = @_;

  return "Database server $server is " . ( $down ? "down!\n" : "up. [OK]\n" );
}

sub make_diff_status {

  my ( $prim_rows, $sec_rows, @tables ) = @_;

  # 2: indent spaces.
  my $max = 2 + max( map { length $_ } @tables );

  my $format = "%${max}s: %5d (%7d - %7d)\n";

  my $text = '';
  for my $tab ( sort @tables ) {

    my ( $prim, $sec ) = map { $_->{ $tab } } $prim_rows, $sec_rows;

    $text .= sprintf $format, $tab, $prim - $sec, $prim, $sec;
  }
  return $text;
}

=pod

=head1 NAME

checkrepdb.pl - Check database replication

=head1 SYNOPSIS

  checkrepdb.pl -help

  checkrepdb.pl \
    [-p <primary db server>] [-s <secondary db server>] \
    [ -to root@example.org [, -to tech@example.org ] ] \
    [ -cc support@example.net [, -cc sales@example.com ] ]

=head1 OPTIONS

=over 2

=item B<-h> | B<-help>

Prints this message.

=item B<-to> <email address>

Specify email address as the recepint of the check report; default is
"omp_group@jach.hawaii.edu".

It can be specified multiple times to send email to more than one address.

=item B<-cc> <email address>

Specify email address as the carbon copy recepint of the check report.
Note that if given, default email address will not be used.

It can be specified multiple times to send email to more than one address.

=item B<-p> <db server> | B<-primary> <db server>

Specify primary database server (source); default is "SYB_OMP1".

=item B<-s> <db server> | B<-secondary> <db server>

Specify secondary database server (replicate); default is "SYB_OMP2".

=back

=cut

