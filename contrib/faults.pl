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
use List::MoreUtils qw/uniq/;
use Time::Piece qw/:override/;
use Time::Seconds qw/ONE_DAY/;

use constant OMPLIB => "$FindBin::RealBin/../lib";

BEGIN {
    $ENV{OMP_CFG_DIR} = File::Spec->catdir(OMPLIB, "../cfg")
        unless exists $ENV{OMP_CFG_DIR};
    $ENV{PATH} = "/usr/bin:/usr/local/bin:/usr/local/progs/bin:/usr/sbin";
}

use DBI;

use lib OMPLIB;
use OMP::DateTools;
use OMP::DB::Backend;
use OMP::DB::Fault;
use OMP::Query::Fault;

my $dbb = OMP::DB::Backend->new;
my $db = OMP::DB::Fault->new(DB => $dbb);

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
$startut = OMP::DateTools->parse_date($startut);

# Telescope
my $telescope = "JCMT";
if (defined($tel)) {
    $telescope = "JCMT" if ($tel =~ /^J/i);
    $telescope = "UKIRT" if ($tel =~ /^U/i);
}

my $category = $telescope;
if (defined($events)) {
    $category .= "_EVENTS";
}
die "*Error*: telescope must be J(CMT) or U(KIRT), or events must be selected. Exiting.\n"
    unless grep {$category eq $_} qw/JCMT UKIRT JCMT_EVENTS/;

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

my $faultname = (lc OMP::Fault->getCategoryEntryName($category)) . 's';

print
"___________________________________________________________________________


...New $faultname this week:

";

my $current = $db->queryFaults(
    OMP::Query::Fault->new(HASH => {
        EXPR__DT => {or => {
            # Faults that occurred on the dates we are reporting for:
            faultdate => {
                value => $startut,
                delta => $delta,
            },

            # Faults filed on the dates we are reporting for:
            EXPR__DTF => {and => {
                date => {
                    value => $startut,
                    delta => $delta,
                },

                # Provided this was the original filing or an additional time loss:
                EXPR__DTFF => {or => {
                    isfault => {boolean => 1},
                    timelost => {min => 0.001},
                }},
            }},
        }},
        category => $category,
    }),
    matching_responses_only => 1,
    no_text => 1, no_projects => 1);

# Group same faults together

my %faults;

my $totallost = 0;

foreach my $fault ($current->faults) {
    my $subject = $fault->subject;
    $subject =~ s/^\s+//;
    $subject = substr($subject,0,55);
    $subject =~ s/\s+$//;

    # Try to omit some variations, anything after a '(' and xN
    my $subj = $subject;
    $subj =~ s/\(.*//;
    $subj =~ s/\bx\d+\b//;
    $subj =~ s/Errors/Error/i;
    $subj =~ s/Faults/Fault/i;
    $subj =~ s/\s+$//g;

    # Now just get rid of all spaces for key
    $subj =~ s/\s+/\_/g;

    my @author = ();
    foreach my $response ($fault->responses) {
        my $author = $response->author->userid;
        $author = substr($author, 0, 5) . substr($author, -1, 1)
            if length($author) > 6 ;
        push @author, $author;
    }

    my $time = (scalar localtime $fault->date->epoch)->strftime('%H:%M HST');
    my $status = $statusname[$fault->status];

    if (exists $faults{$subj}) {
        $faults{$subj}{totallost} += $fault->timelost;
        $faults{$subj}{listing} .= sprintf "%12.12s %9.9s %-48.48s\n", $fault->id, $time, $subject;
        push @{$faults{$subj}{'author'}}, @author;
        $faults{$subj}{status} = $status if $status =~ /open/i;
        $faults{$subj}{'id'} = $fault->id if $fault->id < $faults{$subj}{'id'};
    }
    else {
        my %ref;
        $ref{totallost} = $fault->timelost;
        $ref{listing} = sprintf "%12.12s %9.9s %-48.48s\n", $fault->id, $time, $subject;
        $ref{'author'} = \@author;
        $ref{status} = $status;
        $ref{'id'} = $fault->id;
        $faults{$subj} = \%ref;
    }
}

# Now print everything in from largest time lost;
foreach my $subj (
        sort {$faults{$b}{totallost} cmp $faults{$a}{totallost}}
        sort {$faults{$a}{'id'} <=> $faults{$b}{'id'}}
        keys %faults) {
    printf "%s", $faults{$subj}{listing};

    my $author = join ',', uniq @{$faults{$subj}{'author'}};
    if ($category ne "JCMT_EVENTS") {
        printf " %-44.44s %6.2f hrs lost %s\n\n",
            $author, $faults{$subj}{totallost},
            $faults{$subj}{status};
    }
    else {
        printf " %-44.44s\n\n", $author;
    }
}


if ($category ne "JCMT_EVENTS") {
    print "

=========================================================================
                              OBSERVATORY STATUS
=========================================================================

...Last week faults, still OPEN:

";
    my $status_open = OMP::Fault->faultStatusOpen($category);
    my $previous = $db->queryFaults(
        OMP::Query::Fault->new(HASH => {
            category => $category,
            date => {
                min => $startut - $delta * ONE_DAY,
                max => $startut,
            },
            isfault => {boolean => 1},
            status => [values %$status_open],
        }),
        no_text => 1, no_projects => 1);

    foreach my $fault ($previous->faults) {
        my $subject = $fault->subject;
        $subject =~ s/^\s+//;
        $subject = substr($subject, 0, 55);
        $subject =~ s/\s+$//g;

        my @author = ();
        foreach my $response ($fault->responses) {
            my $timelost = $response->timelost // 0.0;
            next if (scalar @author) && ! ($timelost > 0.0);
            my $author = $response->author->userid;
            $author = substr($author, 0, 5) . substr($author, -1, 1)
                if length($author) > 6 ;
            push @author, $author;
        }
        my $author = join ',', uniq @author;

        my $time = (scalar localtime $fault->date->epoch)->strftime('%H:%M HST');

        printf "%12.12s %9.9s %-48.48s\n %-44.44s %6.2f hrs lost %s\n\n",
            $fault->id, $time, $subject,
            $author, $fault->timelost, $statusname[$fault->status];
    }

    print "
...Selected older faults, Fixed/Closed this week:

";

    $previous = $db->queryFaults(
        OMP::Query::Fault->new(HASH => {
            category => $category,
            date => {
                value => $startut,
                delta => $delta,
            },
            status => OMP::Fault::CLOSED,
        }),
        no_text => 1, no_projects => 1);

    foreach my $fault ($previous->faults) {
        next unless $fault->date < $startut;

        my $subject = $fault->subject;
        $subject =~ s/^\s+//;
        $subject = substr($subject, 0, 55);
        $subject =~ s/\s+$//g;

        my @author = ();
        foreach my $response ($fault->responses) {
            next if $response->date < $startut;
            my $author = $response->author->userid;
            $author = substr($author, 0, 5) . substr($author, -1, 1)
                if length($author) > 6 ;
            push @author, $author;
        }
        my $author = join ',', uniq @author;

        printf "%-22.22s %-48.48s\n %-44.44s %6.2f hrs lost %s\n\n",
            $fault->id, $subject,
            $author, $fault->timelost, $statusname[$fault->status];;
    }
}
else {
    print "\n\n";
}


# DISCONNECT FROM DB SERVER
$dbb->handle->disconnect;

sub help () {
    print "\n";
    print "Use: faults.pl [-tel JCMT|UKIRT] [-days #] yyyymmdd\n";
    print "     faults.pl [-tel JCMT|UKIRT] [-days #] -ut yyyymmdd\n\n";
    print "Defaults are JCMT and periods of 7 days\n\n";
    print " To get JCMT events, do faults.pl -events [-days #] yyyymmdd\n";
}
