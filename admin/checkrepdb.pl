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
my $critical = 0;
my $fault = 0;

# Roles are as defined by the entries in a "interfaces" file.  In this case,
# they are based on the file as found in "/local/progs/sybase".
my $primary_db = "SYB_JAC";
my $secondary_db = "SYB_JAC2";

my $wait  = 20;
my $tries = 15;
my ( @to_addr, @cc_addr, $nomail, $debug, $progress );

my %run =
  ( 'truncated-prog' => 1,
    'missed-prog'    => 1,
    'missed-msb'     => 1,
    'rows'           => 1,
    'replication'    => 1
  );

{
  my $help;
  GetOptions(
    'h|help'   => \$help,

    'debug'    => \$debug,
    'progress' => \$progress,

    'to=s'     => \@to_addr,
    'cc=s'     => \@cc_addr,
    'nomail'   => \$nomail,

    'p|pri|primary=s'   => \$primary_db,
    's|sec|secondary=s' => \$secondary_db,
    'wait=i'            => \$wait,
    'tries=i'           => \$tries,

    'truncated-prog|tp!' => \$run{'truncated-prog'},
    'missed-prog|mp!'    => \$run{'missed-prog'},
    'missed-msb|mm!'     => \$run{'missed-msb'},
    'rows!'              => \$run{'rows'},
    'replication!'       => \$run{'replication'},
  ) || die pod2usage( '-exitval' => 2, '-verbose' => 1 );

  pod2usage( '-exitval' => 1, '-verbose' => 2 ) if $help;
}

#  Default address.
@to_addr = ( 'omp_group@jach.hawaii.edu' )
  if 0 == scalar @to_addr + scalar @cc_addr ;

my (  $primary_kdb,
      $primary_db_down,
      $secondary_kdb,
      $secondary_db_down,
      $tmp
    );

( $primary_kdb, $primary_db_down, $tmp ) = check_db_up( $primary_db );
$msg .= $tmp;

( $secondary_kdb, $secondary_db_down, $tmp ) = check_db_up( $secondary_db );
$msg .= $tmp;

if ( $primary_db_down || $secondary_db_down ) {

  $critical++;
  $msg .= "\nCannot proceed with tests.\n";
}
unless ( $primary_db_down || $secondary_db_down ) {

  $run{'replication'} and
    ( $critical, $tmp ) =
      check_rep(  $primary_db, $primary_kdb, $secondary_db, $secondary_kdb,
                  'wait'  => $wait,
                  'tries' => $tries
                );

  my @msg;
  $run{'truncated-prog'} and
    ( $msg[0], $trunc ) = check_truncated_sciprog();

  $run{'missed-prog'} and
    ( $msg[1], $missing_prog ) = check_missing_sciprog();

  $run{'rows'} and
    ( $msg[2], $row_count ) = compare_row_count();

  $run{'missed-msb'} and
    ( $msg[3], $missing_msb ) = check_missing_msb();

  $msg .= join '', grep { $_ } ( $tmp, @msg );
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

if ( $debug || $nomail ) {

  print $subject, "\n", $msg;
}
else {

  my %addr =
    (
      scalar @to_addr ? ( 'To' => join ', ', @to_addr ) : (),
      scalar @cc_addr ? ( 'Cc' => join ', ', @cc_addr ) : ()
    );
  send_mail( $subject, $msg, %addr );
}

err_exit( $subject, 'pass' => qr{^OK\b}i, 'use-exit' => 1, 'show-text' => 0 );


sub check_rep {

  my (  $pri_db, $pri_kdb, $sec_db, $sec_kdb, %wait ) = @_;

  my $msg = '';
  my $critical = 0;

  my ( $key, $verify, $time_msg ) =
    check_key_rep(  $pri_db, $sec_db, $pri_kdb, $sec_kdb,
                    %wait
                  );

  $msg .= $time_msg;

  if ( $verify ) {

    $msg .= "\nReplication server ($pri_db -> $sec_db) is actively replicating. [OK]\n\n";
  }
  else {

    $critical++;
    $msg .= sprintf "Replication server (%s -> %s) is not replicating!\n"
                    . "(key used to verify was %s)\n",
                    $pri_db, $sec_db, $key;
  }

  return ( $critical, $msg );
}

sub check_key_rep {

  my ( $pri_db, $sec_db, $pri_kdb, $sec_kdb, %opt ) = @_;

  my $wait  = $opt{'wait'}  || 20;
  my $tries = $opt{'tries'} || 15;

  my $msg = '';
  my ( $key, $verify );

  if ( !! $pri_kdb ) {

    $key = $pri_kdb->genKey();
    progress( "key on $pri_db to check: $key" );
  }
  $key or return ( $key, $verify, $msg );

  progress( "Verifying key on $sec_db" );

  # XXX To find the replication time.
  my $loops = 0;
  use Time::HiRes ( 'gettimeofday', 'tv_interval' );
  my $_rep_time = [ gettimeofday() ];

  do {

    $loops++;
    unless ( $verify ) {

      progress( "Sleeping for $wait seconds ($loops)" );
      sleep $wait;
    }

    !!$sec_kdb and $verify = $sec_kdb->verifyKey( $key );
  }
  while ( !$verify && --$tries );

  # XXX To find the replication time.
  $msg .= sprintf "\n( key replication: total wait: %0.2f s,  tries: %d )\n",
            tv_interval( $_rep_time ),
            $loops;

  return ( $key, $verify, $msg );
}

sub check_db_up {

  my ( $db ) = @_;

  progress( "Checking if $db is up" );

  my $kdb;
  my $down = 0;

  $ENV{OMP_DBSERVER} = $db;
  try {

    $kdb = OMP::KeyDB->new( 'DB' => OMP::DBbackend->new(1) );
  }
  catch OMP::Error with {

    $down = 1;
  };

  return ( $kdb, $down, make_server_status( $db, $down ) );
}

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

  my ( $text ) = @_;

  return unless $progress;

  warn join $text, '#  ',  ( $text =~ m/\n$/ ? () : "\n" );
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

  checkrepdb.pl -notruncated-prog -nomissed-prog

=head1 OPTIONS

=head2 General

=over 2

=item B<-debug>

Run in debug mode. No email is sent.

=item B<-help> | B<-h>

Prints this message.

=item B<-progress>

Prints what is going to be done next on standard error.

=back

=head2 Email

=over 2

=item B<-nomail>

Do not send any mail. Messages are printed to standard output. It
overrides I<-to> and I<-cc> options.

=item B<-cc> <email address>

Specify email address as the carbon copy recipient of the check report.
Note that if given, default email address will not be used.

It can be specified multiple times to send email to more than one address.

=item B<-to> <email address>

Specify email address as the recipient of the check report; default is
"omp_group@jach.hawaii.edu".

It can be specified multiple times to send email to more than one address.

=back

=head2 Database Servers

=over 2

=item B<-primary> | B<-p> <db server>

Specify primary database server (source); default is "SYB_JAC".

=item B<-secondary> | B<-s> <db server>

Specify secondary database server (replicate); default is "SYB_JAC2".

=item B<-tries> number

Specify the number of tries over which to check the replication of a
key generated.

=item B<-wait> time in second

Specify the time to wait before checking replication of a key
generated per try.

=back

=head2 Checks

All the checks are run by default.

=over 2

=item B<-nomissed-msb> | B<-nomm>

Specify to skip check for missed MSBs in a science program.

=item B<-nomissed-prog> | B<-nomp>

Specify to skip check for missed science programs.

=item B<-noreplication>

Specify to skip check for continuing replication.

=item B<-norows>

Specify to skip checking of same number of rows.

=item B<-notruncated-prog> | B<-notp>

Specify to skip check for truncated science programs.

=back

=head1 AUTHOR

Kynan Delorey <k.delorey@jach.hawaii.edu>

=head1 COPYRIGHT

Copyright (C) 2007-2012 Science and Technology Facilities Council.
All Rights Reserved.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful,but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc., 59 Temple
Place,Suite 330, Boston, MA  02111-1307, USA

=cut

