use warnings;
use strict;

use FindBin;
use lib
  "$FindBin::RealBin/..",
  '/jac_sw/hlsroot/perl-JAC-ErrExit/lib'
  ;

use Getopt::Long qw(:config gnu_compat no_ignore_case no_debug);
use Pod::Usage;
use MIME::Lite;
use List::Util qw/ max /;

use JAC::ErrExit 'err_exit';

use OMP::BaseDB;
use OMP::DBbackend;
use OMP::Error qw/ :try /;
use OMP::KeyDB;

my $msg;
my $trunc;
my $missing_prog;
my $row_count;
my $missing_msb;
my $critical;
my $fault = 0;

# Roles are as defined by the entries in a "interfaces" file.  In this case,
# they are based on the file as found in "/local/progs/sybase".
my $primary_db = "SYB_JAC";
my $secondary_db = "SYB_JAC2";

my ( @to_addr, @cc_addr, $debug, $progress );

{
  my $help;
  GetOptions(
    'h|help' => \$help,
    'p|pri|primary=s' => \$primary_db,
    's|sec|secondary=s' => \$secondary_db,
    'to=s' => \@to_addr,
    'cc=s' => \@cc_addr,
    'debug' => \$debug,
    'progress' => \$progress
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

  progress( "Checking if $primary_db is up" );

  $primary_kdb = new OMP::KeyDB( DB => new OMP::DBbackend );
} catch OMP::Error with {
  my $E = shift;
  $primary_db_down = 1;
  $critical = 1;
};

$msg .= make_server_status( $primary_db, $primary_db_down );

progress( "Generating a key in database on $primary_db" );

my $key = !!$primary_kdb && $primary_kdb->genKey();

progress( "Sleeping for 20 seconds" );

sleep 20;

# Look for insert on replicate DB
$ENV{OMP_DBSERVER} = $secondary_db;
try {

  progress( "Checking if $secondary_db is up" );

  $secondary_kdb = new OMP::KeyDB( DB => new OMP::DBbackend(1) )
} catch OMP::Error with {
  $secondary_db_down = 1;
  $critical = 1;
};

$msg .= make_server_status( $secondary_db, $secondary_db_down );

progress( "Verifying key in database on $secondary_db" );

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

  my @msg;
  ( $msg[0], $trunc ) = check_truncated_sciprog();

  ( $msg[1], $missing_prog ) = check_missing_sciprog();

  ( $msg[2], $row_count ) = compare_row_count();

  ( $msg[3], $missing_msb ) = check_missing_msb();

  $msg .= join '', grep { $_ } @msg;

}

my $subject;
if ($critical) {
  $subject = 'CRITICAL!';
} elsif ($fault > 1) {
  $subject = 'MULTIPLE FAULTS!';
} elsif ($trunc) {
  $subject = 'TRUNCATED PROGRAMS FOUND!';
} elsif ($missing_prog) {
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

err_exit( $subject, 'pass' => qr{^OK\b}i );

sub check_missing_msb {

  # Make sure MSBs are present if there's a science program
  progress( "Checking for MSB in science program" );

  my ( $msg ) = ( '' ) ;
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
          unless $really_missing_ref->[0];
      }
    }

    if ($really_missing[0]) {

      $missing_msb = 1;
      $fault++;

      $msg .= "Missing MSBs detected on ${dbserver}!\n"
            . "The following projects are affected:\n"
            . join "\t", map { "$_\n" } @really_missing
            ;

      $msg .= "\n";
    }
  }

  if (! $missing_msb) {
    $msg = "MSBs are present for each science program. [OK]\n\n";
  }

  return ( $msg, $missing_msb );
}

sub compare_row_count {

  # Compare row counts for disparity
  progress( "Comparing row count" );

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

  my ( $msg, $fault );
  if ($row_count_disparity[0]) {

    $row_count = 1;
    $fault++;

    $msg = <<"DISPARITY";
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

    $msg = "Row counts are equal across both databases. [OK]\n\n";
  }

  return ( $msg, $row_count );
}

sub check_missing_sciprog {

  # Check for missing science programs
  progress( "Checking for missing science program" );

  my $sql = "SELECT DISTINCT F.projectid\n".
    "FROM ompfeedback F, ompsciprog S\n".
      "WHERE F.projectid = S.projectid\n".
        "AND F.msgtype = 70\n".
          "AND S.sciprog LIKE NULL";

  my %results;
  for my $dbserver ( $primary_db, $secondary_db ) {
    $ENV{OMP_DBSERVER} = $dbserver;
    my $db = new OMP::BaseDB( DB => new OMP::DBbackend(1) );

    my $ref = $db->_db_retrieve_data_ashash( $sql );

        if ($ref->[0]) {
      map {push @{$results{$dbserver}}, $_->{projectid}} @$ref;
    }
  }

  my $msg;
  if (%results) {

    $missing_prog = 1;
    $fault++;
    $msg = "Missing programs detected!\n";

    for my $dbserver (keys %results) {
      $msg .= "$dbserver:\n";
      map {$msg .= "\t$_\n"} @{$results{$dbserver}};
      $msg .= "\n";
    }
  } else {

    $msg = "All science programs are present. [OK]\n\n";
  }

  return ( $msg, $missing_prog );
}

sub check_truncated_sciprog {

  # Check for truncated science programs
  progress( "Checking for truncated science program" );

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

  my ( $msg, $trunc );
  if (%results) {

    $trunc = 1;
    $fault++;

    $msg = "Truncated science programs found!\n";

    for my $dbserver (keys %results) {

      $msg .= "$dbserver:\n";
      map {$msg .= "\t$_\n"} @{$results{$dbserver}};
      $msg .= "\n";
    }
  } else {

    $msg = "No truncated science programs found. [OK]\n\n";
  }

  return ( $msg, $trunc );
}

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

sub progress {

  $progress and warn @_ , ( $_[-1] =~ m/\n$/ ? () : "\n" );
  return;
}

=pod

=head1 NAME

checkrepdb.pl - Check database replication

=head1 SYNOPSIS

  checkrepdb.pl -help

  checkrepdb.pl \
    [ -progress ] \
    [-p <primary db server>] [-s <secondary db server>] \
    [ -to root@example.org [, -to tech@example.org ] ] \
    [ -cc support@example.net [, -cc sales@example.com ] ]

=head1 OPTIONS

=over 2

=item B<-h> | B<-help>

Prints this message.

=item B<-to> <email address>

Specify email address as the recipient of the check report; default is
"omp_group@jach.hawaii.edu".

It can be specified multiple times to send email to more than one address.

=item B<-cc> <email address>

Specify email address as the carbon copy recipient of the check report.
Note that if given, default email address will not be used.

It can be specified multiple times to send email to more than one address.

=item B<-p> <db server> | B<-primary> <db server>

Specify primary database server (source); default is "SYB_JAC".

=item B<-s> <db server> | B<-secondary> <db server>

Specify secondary database server (replicate); default is "SYB_JAC2".

=item B<-progress>

Prints what is going to be done next on standard error.

=back

=cut

