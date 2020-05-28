#!/local/perl/bin/perl

=head1 NAME

checkrepdb.pl - Check database replication

=head1 SYNOPSIS

    checkrepdb.pl -help

    checkrepdb.pl \
        [-progress] \
        [-p <primary db server>] [-s <secondary db server>] \

    checkrepdb.pl -notruncated-prog -nomissed-prog

=head1 OPTIONS

=head2 General

=over 2

=item B<-help> | B<-h>

Prints this message.

=item B<-progress>

Prints what is going to be done next on standard error.

=back

=head2 Database Servers

=over 2

=item B<-primary> | B<-p> <db server>

Specify primary database server (source); default is "omp1".

=item B<-secondary> | B<-s> <db server>

Specify secondary database server (replicate); default is none.

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

=cut

use warnings;
use strict;

use FindBin;

use constant OMPLIB => "$FindBin::RealBin/../lib";

use lib OMPLIB;

BEGIN {
    $ENV{OMP_CFG_DIR} = File::Spec->catdir(OMPLIB, "../cfg")
        unless exists $ENV{OMP_CFG_DIR};
};

use Getopt::Long qw(:config gnu_compat no_ignore_case no_debug);
use Pod::Usage;
use List::Util qw/max/;
use Time::HiRes qw/gettimeofday tv_interval/;

use OMP::BaseDB;
use OMP::DBbackend;
use OMP::Error qw/:try/;

my $progress = 0;

do {
    my $trunc = 0;
    my $key_replication = 0;
    my $missing_prog = 0;
    my $row_count = 0;
    my $missing_msb;
    my $critical = 0;
    my $fault = 0;

    # Database server host names.
    my $primary_db   = "omp1";
    my $secondary_db = undef;  # "omp2";

    my $wait  = 20;
    my $tries = 15;

    my %run = (
        'truncated-prog' => 1,
        'missed-prog'    => 1,
        'missed-msb'     => 1,
        'rows'           => 1,
        'replication'    => 1
    );

    do {
        my $help;
        GetOptions(
            'h|help'   => \$help,

            'progress' => \$progress,

            'p|pri|primary=s'   => \$primary_db,
            's|sec|secondary=s' => \$secondary_db,
            'wait=i'            => \$wait,
            'tries=i'           => \$tries,

            'truncated-prog|tp!' => \$run{'truncated-prog'},
            'missed-prog|mp!'    => \$run{'missed-prog'},
            'missed-msb|mm!'     => \$run{'missed-msb'},
            'rows!'              => \$run{'rows'},
            'replication!'       => \$run{'replication'},
        ) || die pod2usage('-exitval' => 2, '-verbose' => 1);

        pod2usage('-exitval' => 1, '-verbose' => 2) if $help;
    };

    my ($primary_dbh, $primary_db_down,
        $secondary_dbh, $secondary_db_down,
        $tmp);

    my @msg;

    ($primary_dbh, $primary_db_down, $tmp) = check_db_up($primary_db);
    push @msg, $tmp;

    # Only check secondary database if it was defined.
    if (defined $secondary_db) {
        ($secondary_dbh, $secondary_db_down, $tmp) = check_db_up($secondary_db);
        push @msg, $tmp;
    }
    else {
        $secondary_db_down = 1;
    }

    if ($primary_db_down and $secondary_db_down) {
        $critical ++;
        push @msg, "\nBoth servers down: cannot proceed with tests.\n";
    }
    else {
        unless ($primary_db_down or $secondary_db_down) {
            # Perform test of replication (requires both databases).

            if ($run{'replication'}) {
                ($tmp, $key_replication) = check_rep(
                    $primary_db, $primary_dbh, $secondary_db, $secondary_dbh,
                    'wait'  => $wait,
                    'tries' => $tries);
                push @msg, $tmp;
                $critical += $key_replication;
            }

            if ($run{'rows'}) {
                ($tmp, $row_count) = compare_row_count(
                    $primary_db, $secondary_db);
                push @msg, $tmp;
                $fault += $row_count;
            }
        }
        elsif (defined $secondary_db) {
            $critical ++;
            push @msg, "\nOne database server down: skipping replication tests.\n";
        }

        # Perform tests which are done on individual databases.
        my @databases = ();
        push @databases, $primary_db unless $primary_db_down;
        push @databases, $secondary_db unless $secondary_db_down;

        if ($run{'truncated-prog'}) {
            ($tmp, $trunc) = check_truncated_sciprog(@databases);
            push @msg, $tmp;
            $fault += $trunc;
         }

        if ($run{'missed-prog'}) {
            ($tmp, $missing_prog) = check_missing_sciprog(@databases);
            push @msg, $tmp;
            $fault += $missing_prog;
        }

        if ($run{'missed-msb'}) {
            ($tmp, $missing_msb) = check_missing_msb(@databases);
            push @msg, $tmp;
            $fault += $missing_msb;
        }
    }

    my $subject;
    my $is_ok = 0;

    if ($critical) {
        $subject = 'CRITICAL!';
    }
    elsif ($fault > 1) {
        $subject = 'MULTIPLE FAULTS!';
    }
    elsif ($trunc) {
        $subject = 'TRUNCATED PROGRAMS FOUND!';
    }
    elsif ($missing_prog) {
        $subject = 'MISSING PROGRAMS DETECTED!';
    }
    elsif ($row_count) {
        $subject = 'ROW COUNT DISPARITY DETECTED!';
    }
    elsif ($missing_msb) {
        $subject = 'MISSING MSBS DETECTED!';
    }
    else {
        $subject = 'OK';
        $is_ok = 1;
    }

    $subject .= " - Replication status ($primary_db -> $secondary_db)"
        if defined $secondary_db;

    print $subject, "\n\n", join("\n", @msg);

    exit 1 unless $is_ok;
    exit;
};


sub check_rep {
    my ($pri_db, $pri_dbh, $sec_db, $sec_dbh, %wait) = @_;

    my $msg = '';
    my $critical = 0;

    return ('Replication check not currently supported', 1);

    my ($key, $verify, $time_msg) =
        check_key_rep($pri_db, $sec_db, $pri_dbh, $sec_dbh, %wait);

    $msg .= $time_msg;

    if ($verify) {
        $msg .= "\nReplication server ($pri_db -> $sec_db) is actively replicating. [OK]\n";
    }
    else {
        $critical++;
        $msg .= sprintf "Replication server (%s -> %s) is not replicating!\n"
                        . "(key used to verify was %s)\n",
                        $pri_db, $sec_db, $key;
    }

    return ($msg, $critical);
}

sub check_key_rep {
    my ($pri_db, $sec_db, $pri_kdb, $sec_kdb, %opt) = @_;

    die 'Subroutine check_key_rep is not currently useable';
    # We get a database handle rather than "Key DB", which no longer
    # exists.  If we start using replication again, we must check using
    # another table, e.g. ompauth.

    my $wait  = $opt{'wait'}  || 20;
    my $tries = $opt{'tries'} || 15;

    my $msg = '';
    my ($key, $verify);

    if ($pri_kdb) {
        $key = $pri_kdb->genKey();
        progress("key on $pri_db to check: $key");
    }

    return ($key, $verify, $msg) unless $key;

    progress("Verifying key on $sec_db");

    # XXX To find the replication time.
    my $loops = 0;
    my $_rep_time = [gettimeofday()];

    do {
        $loops++;

        unless ($verify) {
            progress("Sleeping for $wait seconds ($loops)");
            sleep $wait;
        }

        $verify = $sec_kdb->verifyKey($key) if $sec_kdb;
    }
    while (!$verify && --$tries);

    # XXX To find the replication time.
    $msg .= sprintf "\n(key replication: total wait: %0.2f s,  tries: %d)\n",
        tv_interval($_rep_time), $loops;

    return ($key, $verify, $msg);
}

sub check_db_up {
    my ($db) = @_;

    progress("Checking if $db is up");

    my $dbh;
    my $down = 0;

    my $err_die;
    $ENV{OMP_DBSERVER} = $db;

    try {
        $dbh = OMP::DBbackend->new(1);
    }
    catch OMP::Error::BadCfgKey with {
        my ($e) = @_;

        # Cannot do anything sensible with bad configurartion.
        $err_die = $e->text();
    }
    catch OMP::Error with {
        $down = 1;
    };

    die $err_die if $err_die;

    return (
        $dbh, $down,
        "Database server $db is " . ($down ? "down!\n" : "up. [OK]\n"));
}

sub check_missing_msb {
    my @databases = @_;

    # Make sure MSBs are present if there's a science program
    progress("Checking for MSB in science program");

    my $msg = '';
    my $missing_msb = 0;

    foreach my $dbserver (@databases) {
        $ENV{OMP_DBSERVER} = $dbserver;
        my $db = new OMP::BaseDB(DB => new OMP::DBbackend(1));

        my $sql = "SELECT projectid FROM ompsciprog\n".
            "WHERE projectid NOT IN (SELECT DISTINCT projectid FROM ompmsb)";

        my $ref = $db->_db_retrieve_data_ashash($sql);

        my @really_missing;

        if ($ref->[0]) {
            for my $row (@$ref) {
                my $projectid = $row->{projectid};
                my $sql = "SELECT projectid FROM ompsciprog\n".
                  "WHERE projectid = '$projectid' AND sciprog NOT LIKE '%<SpObs%'";

                my $really_missing_ref = $db->_db_retrieve_data_ashash($sql);
                push @really_missing, $projectid
                    unless $really_missing_ref->[0];
            }
        }

        if ($really_missing[0]) {
            $missing_msb ++;

            $msg .= "Missing MSBs detected on ${dbserver}!\n"
                  . "The following projects are affected:\n"
                  . join "\t", map {"$_\n"} @really_missing;

            $msg .= "\n";
        }
    }

    unless ($missing_msb) {
        $msg = "MSBs are present for each science program. [OK]\n";
    }

    return ($msg, $missing_msb);
}

sub compare_row_count {
    my @databases = @_;
    my $primary_db = $databases[0];
    my $secondary_db = $databases[1];

    # Compare row counts for disparity
    progress("Comparing row count");

    my %row_count_results;

    foreach my $dbserver (@databases) {
        $ENV{OMP_DBSERVER} = $dbserver;
        my $db = new OMP::BaseDB(DB => new OMP::DBbackend(1));

        for my $table (qw/ompfault ompfaultassoc ompfaultbody ompfeedback
                          ompmsb ompmsbdone ompobs ompobslog ompproj
                          ompprojqueue ompprojuser ompshiftlog ompsciprog
                          omptimeacct ompuser ompkey/) {
            my $sql = "SELECT COUNT(*) AS \'count\' FROM $table";

            my $ref = $db->_db_retrieve_data_ashash($sql);
            $row_count_results{$dbserver}{$table} = $ref->[0]->{count};
        }
    }

    my @row_count_disparity;

    for my $table (keys %{$row_count_results{$primary_db}}) {
        if ($row_count_results{$primary_db}{$table} ne $row_count_results{$secondary_db}{$table}) {
            push(@row_count_disparity, $table)
                unless $table eq 'ompkey';
        }
    }

    my ($msg, $fault);
    my $row_count = 0;

    if ($row_count_disparity[0]) {
        $row_count ++;

        $msg = <<"DISPARITY";
Disparity in row counts detected between $primary_db & $secondary_db!
The following tables are affected:
DISPARITY

        $msg .= make_diff_status(
            $row_count_results{$primary_db},
            $row_count_results{$secondary_db},
            @row_count_disparity);
        $msg .= "\n";
    }
    else {
        $msg = "Row counts are equal across both databases. [OK]\n";
    }

    return ($msg, $row_count);
}

sub check_missing_sciprog {
    my @databases = @_;

    # Check for missing science programs
    progress("Checking for missing science program");

    my $sql = "SELECT DISTINCT F.projectid\n".
        "FROM ompfeedback F, ompsciprog S\n".
          "WHERE F.projectid = S.projectid\n".
            "AND F.msgtype = 70\n".
              "AND S.sciprog LIKE NULL";

    my %results;

    foreach my $dbserver (@databases) {
        $ENV{OMP_DBSERVER} = $dbserver;
        my $db = new OMP::BaseDB(DB => new OMP::DBbackend(1));

        my $ref = $db->_db_retrieve_data_ashash($sql);

        if ($ref->[0]) {
            map {push @{$results{$dbserver}}, $_->{projectid}} @$ref;
        }
    }

    my $msg;
    my $missing_prog = 0;

    if (%results) {
        $missing_prog  ++;
        $msg = "Missing programs detected!\n";

        foreach my $dbserver (keys %results) {
            $msg .= "$dbserver:\n";
            map {$msg .= "\t$_\n"} @{$results{$dbserver}};
            $msg .= "\n";
        }
    }
    else {
        $msg = "All science programs are present. [OK]\n";
    }

    return ($msg, $missing_prog);
}

sub check_truncated_sciprog {
    my @databases = @_;

    # Check for truncated science programs
    progress("Checking for truncated science program");

    my $sql = "SELECT projectid FROM ompsciprog WHERE sciprog not like \"%</SpProg>%\"";

    my %results;

    foreach my $dbserver (@databases) {
        $ENV{OMP_DBSERVER} = $dbserver;
        my $db = new OMP::BaseDB(DB => new OMP::DBbackend(1));

        my $ref = $db->_db_retrieve_data_ashash($sql);

        if ($ref->[0]) {
            map {push @{$results{$dbserver}}, $_->{projectid}} @$ref;
        }
    }

    my $msg;
    my $trunc = 0;

    if (%results) {
        $trunc ++;

        $msg = "Truncated science programs found!\n";

        for my $dbserver (keys %results) {
            $msg .= "$dbserver:\n";
            map {$msg .= "\t$_\n"} @{$results{$dbserver}};
            $msg .= "\n";
        }
    }
    else {
        $msg = "No truncated science programs found. [OK]\n";
    }

    return ($msg, $trunc);
}

sub make_diff_status {
    my ($prim_rows, $sec_rows, @tables) = @_;

    # 2: indent spaces.
    my $max = 2 + max(map {length $_} @tables);

    my $format = "%${max}s: %5d (%7d - %7d)\n";

    my $text = '';

    foreach my $tab (sort @tables) {
        my ($prim, $sec) = map {$_->{$tab}} $prim_rows, $sec_rows;

        $text .= sprintf $format, $tab, $prim - $sec, $prim, $sec;
    }

    return $text;
}

sub progress {
    my ($text) = @_;

    return unless $progress;

    warn join $text, '#  ',  ($text =~ m/\n$/ ? () : "\n");
    return;
}

__END__

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
