#!/local/bin/perl
#
# Quick script to download and order the faults in the usual
# opsmeeting format:
#              - All faults between given dates
#              - All faults open from week before
#              - All faults closed during the week
#              - (if -events given:): all events filed between dates.


use strict;
use FindBin;
use File::Spec;
use Getopt::Long;

use constant OMPLIB => "$FindBin::RealBin/../lib";

BEGIN {
    $ENV{OMP_CFG_DIR} = File::Spec->catdir(OMPLIB, "../cfg")
        unless exists $ENV{OMP_CFG_DIR};
    $ENV{PATH} = "/usr/bin:/usr/local/bin:/usr/local/progs/bin:/usr/sbin";
}

use DBI;

use lib OMPLIB;
use OMP::DB::Backend;
use OMP::DB::Fault;

my $dbs = OMP::DB::Backend->new;

my ($help, $man, $tel, $ut, $days, $events);
my $status = GetOptions(
    "help" => \$help,
    "man" => \$man,
    "ut=s" => \$ut,
    "tel=s" => \$tel,
    "days=s" => \$days,
    "events" => \$events,
);

# Some help
if (defined($help) or defined($man)) {
    help();
    exit;
}

# First thing we need to do is determine the telescope and
# the UT date
my $startut;
if (defined($ut)) {
    $startut = $ut;
}
elsif ($#ARGV == 0) {
    $startut = $ARGV[0];
}
else {
    help();
    die "*Error*: no start ut specified\n\n";
}
chomp($startut);

# Telescope
my $telescope = "JCMT";
if (defined($tel)) {
    $telescope = "JCMT" if ($tel =~ /^J/i);
    $telescope = "UKIRT" if ($tel =~ /^U/i);
}

if (defined($events)) {
    $telescope = "JCMT_EVENTS";
}
die "*Error*: telescope must be J(CMT) or U(KIRT), or events must be selected. Exiting.\n"
    if ($telescope ne "JCMT"
    and $telescope ne "UKIRT"
    and $telescope ne "JCMT_EVENTS");

my $delta = 7;
$delta = $days if (defined($days));

my @statusname = (
    "OPEN",
    "CLOSED",
    "WORKS FOR ME",
    "NOT A FAULT",
    "WON'T BE FIXED",
    "DUPLICATE",
    "WILL BE FIXED"
);

# Get the connection handle
my $db = $dbs->handle
    or die "Error connecting to DB: $DBI::errstr";

my $faultname = "faults";
if ($telescope eq "JCMT_EVENTS") {
    $faultname = "events";
}
print
"___________________________________________________________________________


...New $faultname this week:

";

my $current_ref = $db->selectall_arrayref(
    qq{select
        F.faultid,
        date_format(date_sub(date, interval 10 hour), "%H:%i HST"),
        substring(subject,1,80),
        author,
        0.01*floor(100*timelost),
        status
    from $OMP::DB::Fault::FAULTTABLE F, $OMP::DB::Fault::FAULTBODYTABLE FB
    where date between "$startut" and date_add("$startut", interval ${delta} day)
        and FB.faultid = F.faultid
        and category='${telescope}'
        and isfault = 1
    order by substring(subject,1,80),faultid}
) or die "Error retrieving from DB: $DBI::errstr";

# order by (-1*timelost)})  === previous sort by timelost

# Group same faults together

my %faults;

my $totallost = 0;

foreach my $row (@$current_ref) {
    my ($faultid, $time, $subject, $author, $timelost, $status) = @$row;

    $subject =~ s/^\s+//;
    $subject = substr($subject,0,55);
    $subject =~ s/\s+$//;

    # Try to omit some variations and anything after a '('
    my $subj = $subject;

    my $index = index($subj, '(');
    $subj = substr($subj, 0, $index) if ($index > -1);

    $subj =~ s/Errors/Error/i;
    $subj =~ s/Faults/Fault/i;
    $subj =~ s/\s+$//g;

    # Now just get rid of all spaces for key
    $subj =~ s/\s+/\_/g;

    $author = substr($author, 0, 5) . substr($author, -1, 1)
        if length($author) > 6 ;

    if (exists $faults{$subj}) {
        $faults{$subj}{totallost} += $timelost;
        $faults{$subj}{listing} .= sprintf "%12.12s %8.8s  %-s\n", $faultid, $time, $subject;
        $faults{$subj}{author} .= ',' . $author
            unless ($faults{$subj}{author} =~ /$author/i);
        $faults{$subj}{status} = $statusname[$status]
            if ($statusname[$status] =~ /open/i);
    }
    else {
        my %ref;
        $ref{totallost} = $timelost;
        $ref{listing} = sprintf "%12.12s %8.8s  %-s\n", $faultid, $time, $subject;
        $ref{author} = $author;
        $ref{status} = $statusname[$status];
        $faults{$subj} = \%ref;
    }
}

# Now print everything in from largest time lost;
foreach my $subj (
        sort {$faults{"$b"}{totallost} cmp $faults{"$a"}{totallost}}
        keys %faults) {
    printf "%s", $faults{$subj}{listing};

    if ($telescope ne "JCMT_EVENTS") {
        printf " %-21.21s %4.4s hrs lost %25.25s %s\n\n",
            $faults{$subj}{author}, $faults{$subj}{totallost}, ' ',
            $faults{$subj}{status};
    }
    else {
        printf " %-21.21s\n\n", $faults{$subj}{author};
    }
}


if ($telescope ne "JCMT_EVENTS") {
    print "

=========================================================================
                              OBSERVATORY STATUS
=========================================================================

...Last week faults, still OPEN:

";

    my $previous_ref = $db->selectall_arrayref(
        qq{select
            F.faultid,
            date_format(date_sub(date, interval 10 hour), "%H:%i HST"),
            substring(subject,1,80),
            author,
            0.01*floor(100*timelost),
            status
        from $OMP::DB::Fault::FAULTTABLE F, $OMP::DB::Fault::FAULTBODYTABLE FB
        where date between date_sub("$startut", interval ${delta} day) and "$startut"
            and FB.faultid = F.faultid
            and category='${telescope}'
            and isfault = 1
            and status in (0, 6)
        order by (-1*timelost)}
    ) or die "Error retrieving from DB: $DBI::errstr";

    foreach my $row (@$previous_ref) {
        my ($faultid, $time, $subject, $author, $timelost, $status) = @$row;

        $subject =~ s/^\s+//;
        $subject = substr($subject, 0, 55);
        $subject =~ s/\s+$//g;

        printf "%12.12s %8.8s  %-s\n %-21.21s %4.4s hrs lost %25.25s %s\n\n",
            $faultid, $time, $subject,
            $author, $timelost, ' ', $statusname[$status];
    }

    print "
...Selected older faults, Fixed/Closed this week:

";

    my $previous_ref = $db->selectall_arrayref(
        qq{select
            distinct F.faultid,
            substring(subject,1,80),
            0.01*floor(100*timelost),
            status
        from $OMP::DB::Fault::FAULTTABLE F, $OMP::DB::Fault::FAULTBODYTABLE FB
        where date between "$startut" and date_add("$startut", interval ${delta} day)
            and faultdate < "$startut"
            and FB.faultid = F.faultid
            and status = 1
            and category='${telescope}'
        order by F.faultid}
    ) or die "Error retrieving from DB: $DBI::errstr";

    foreach my $row (@$previous_ref) {
        my ($faultid, $subject, $timelost, $status) = @$row;

        $subject =~ s/^\s+//;
        $subject = substr($subject, 0, 55);
        $subject =~ s/\s+$//g;

        printf "%12.12s %8.8s  %-s\n\n", $faultid, ' ', $subject;
    }
}
else {
    print "\n\n";
}


# DISCONNECT FROM DB SERVER
$db->disconnect;

sub help () {
    print "\n";
    print "Use: faults.pl [-tel JCMT|UKIRT] [-days #] yyyymmdd\n";
    print "     faults.pl [-tel JCMT|UKIRT] [-days #] -ut yyyymmdd\n\n";
    print "Defaults are JCMT and periods of 7 days\n\n";
    print " To get JCMT events, do faults.pl -events [-days #] yyyymmdd\n";
}
