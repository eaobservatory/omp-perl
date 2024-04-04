#!/local/bin/perl

# Short script to print an observing summary in the usual opsmeeting
# format.

use FindBin;
use File::Spec;

use constant OMPLIB => "$FindBin::RealBin/../lib";

BEGIN {
        $ENV{OMP_CFG_DIR} = File::Spec->catdir(OMPLIB, "../cfg")
          unless exists $ENV{OMP_CFG_DIR};
        $ENV{PATH} = "/usr/bin:/usr/local/bin:/usr/local/progs/bin:/usr/sbin";
      }


use lib OMPLIB;
use OMP::DB::Backend;
use OMP::NightRep;
use strict;
use Getopt::Long;

# Options
my ($help, $man, $tel, $ut, $days);
my $status = GetOptions("help" => \$help,
                        "man" => \$man,
                        "ut=s" => \$ut,
                        "tel=s" => \$tel,
                        "days=s" => \$days
                       );

# Some help
#
do { &help(); exit; } if ( defined($help) or defined($man) );

# First thing we need to do is determine the telescope and
# the UT date
my $startut;
if ( defined($ut) ) {
  $startut = $ut;
} elsif ( $#ARGV == 0 ) {
  $startut = $ARGV[0];
} else {
    &help();
    die "*Error*: no start ut specified\n\n";
}
chomp($startut);

# Telescope
my $telescope = "JCMT";
if(defined($tel)) {
  $telescope = "JCMT" if ($tel =~ /^J/i);
  $telescope = "UKIRT" if ($tel =~ /^U/i);
}
die "*Error*: telescope must be J(CMT) or U(KIRT). Exiting.\n"
   if ($telescope ne "JCMT" and $telescope ne "UKIRT");

my $delta = 7;
$delta = $days if ( defined($days) );

my $db = OMP::DB::Backend->new();
my $nr = OMP::NightRep->new(DB => $db,
                            date => $startut,
                            telescope => $telescope,
                            delta_day => $delta,);

my @countrylist = qw/DDT EC CA INT NL UH UK PI JLS GT JAC LAP VLBI IF/;


#print scalar $nr->astext();


my %acct = $nr->accounting_db('byproject');

my $faultloss = $nr->timelost->hours;
my $technicalloss = $nr->timelost('technical')->hours;
#my %items;

#my $total = 0;
#my $total_pending = 0;

#$total += $faultloss;

#my $total_proj = 0.0;



sub print_reporting_breakdown {
    my $faultloss = $_[0];
    my $technicalloss = $_[1];
    my $longrep = $_[2];
    my %acct = %{$_[3]};

    my $total = 0;
    my $total_pending = 0;
    my $total_proj = 0.0;
    my %items;
    $total += $faultloss;

    foreach my $proj (keys %acct) {
        next if $proj =~ /^$telescope/;
        my $account = $acct{$proj};
        $total += $account->{total}->hours;
        $total_proj += $account->{total}->hours;

        # No determine_country method exists, so we'll get project
        # details instead
        my $details = OMP::ProjServer->projectDetails($proj, "object");

        my $country = $details->country;
        #countrylist .= " $country" if ($country !~ /$countrylist/);

        my $pending;
        if  ($account->{pending}) {
            $total_pending += $account->{pending}->hours;
            $pending = $account->{pending}->hours;
        }

        my $time = $account->{total}->hours;
        $time *= -1 if ($pending);
        $items{"$proj"} = "${time}\@${country}";
    }

    my @country_totals;
    foreach my $country (@countrylist) {
        my $ctotal = 0.0;
        foreach my $proj (keys %acct) {
            my ($ptime, $pcountry) = split(/\@/,$items{$proj});
            $ctotal += abs($ptime) if ($pcountry eq $country);
        }
        push @country_totals, $ctotal;
    }


    foreach my $proj (qw/WEATHER OTHER EXTENDED CAL _SHUTDOWN/) {
        my $time = 0.0;
        my $pending;
        if (exists $acct{$telescope.$proj}) {
            $time = $acct{$telescope.$proj}->{total}->hours;
            if ($acct{$telescope.$proj}->{pending}) {
                $pending += $acct{$telescope.$proj}->{pending}->hours;
            }
            $total += $time unless ($proj eq 'EXTENDED' or $proj eq '_SHUTDOWN');
        }

        $time *= -1 if ($pending);
        $items{lc("$proj")} = $time;
    }

    if ($longrep ) {
        print  "Total time lost to weather                   W:  ";
        printf "%6.2f hrs",abs($items{"weather"});
        print  "  \[pending\]" if ($items{"weather"} < 0);
        print  "\n";
    }
    printf "Time lost to faults                          F:  %6.2f hrs\n",
        $faultloss;
    if ($longrep) {
        printf "  technical faults         F1:  %6.2f hrs\n",
            $technicalloss;
        printf "  non-technical faults     F2:  %6.2f hrs\n",
            $faultloss-$technicalloss;
    }
    printf "Prime time observed on Projects              P:  %6.2f hrs\n",
            $total_proj;

    if ($longrep) {
        print  "Other Time                                   O:  ";
        printf "%6.2f hrs",abs($items{"other"});
        print  "  \[pending\]" if ($items{"other"} < 0);
        print  "\n";

        print  "Calibrations                                 C:  ";
        printf "%6.2f hrs",abs($items{"cal"});
        print  "  \[pending\]" if ($items{"cal"} < 0);
        print  "\n";

        print  "                                                 ------\n";
    }
    printf "Total                                        T:  %6.2f hrs\n",
        $total;
    if ($longrep) {
        print  "Facility Closure                             S:  ";
        printf "%6.2f hrs",abs($items{"_shutdown"});
        print  "  \[pending\]" if ($items{"_shutdown"} < 0);
        print  "\n";
    }
    if (($total-abs($items{"weather"})) > 0) {
        printf "Clear time lost to faults              F/(T-W):  %6.2f \%\n",
        100.0*$faultloss/($total-abs($items{"weather"}));

        if ($longrep) {
            printf "Clear time lost to technical faults   F1/(T-W):  %6.2f \%\n",
            100.0*$technicalloss/($total-abs($items{"weather"}));
            print  "\n";
        }
    }
    if ($longrep) {
        print  "Extended Time                                E:  ";
        printf "%6.2f hrs",abs($items{"extended"});
        print  "  \[pending\]" if ($items{"extended"} < 0);
        print  "\n\n";



        my $cnr = 0;
        foreach my $country (@countrylist) {
            my $done_first = 0;
            foreach my $proj (keys %acct) {
                my ($ptime, $pcountry) = split(/\@/,$items{$proj});
                if ($pcountry eq $country) {
                    printf "%-10.10s %6.2f hrs", $proj, abs($ptime);
                    printf "    %-3.3s %6.2f hrs", $country, $country_totals[$cnr]
                        if ($done_first eq 0);
                    $done_first++;
                    print  "   [pending]" if ($ptime < 0);
                    print  "\n";
                }
            }
            print "\n" if ($done_first > 0);
            $cnr++;
        }
    }
}

print
qq{__________________________________________________________________________


...Observing Summary:

};
print_reporting_breakdown($faultloss, $technicalloss, 1, \%acct);
print "...Observing Summary By shift:\n\n";

print "";

my %shiftacct = $nr->accounting_db('byshftprj');

my %faultlosses = $nr->timelostbyshift;
my %techfaultlosses = $nr->timelostbyshift('technical');
my @faultshifts = (keys %faultlosses);
my @shifts = (keys %shiftacct);



for my $shift (@faultshifts) {
    my $losttime = $faultlosses{$shift};
    if((! exists($shiftacct{$shift}) ) && ($shift ne '') && ($losttime > 0 )) {
          push @shifts, $shift;
      }
  }

if (@shifts > 1) {
   for my $shift (@shifts) {
      print "_________________________________________________________________________\n";
      print "$shift\n";
      if ( exists $faultlosses{$shift} ) {

          $faultloss = $faultlosses{$shift}->hours;
          $technicalloss = $techfaultlosses{$shift}->hours;
    } else {
     $faultloss = 0.0;
     $technicalloss = 0.0;
    }
    if (exists $shiftacct{$shift} ) {
       %acct = %{$shiftacct{$shift}};
     print_reporting_breakdown($faultloss, $technicalloss, 0, \%acct);
    }
}
}

print "_________________________________________________________________________\n";


sub help () {

    print "\n";
    print "Use: projrep.pl [-tel JCMT|UKIRT] [-days #] yyyymmdd\n";
    print "     projrep.pl [-tel JCMT|UKIRT] [-days #] -ut yyyymmdd\n\n";
    print "Defaults are JCMT and a period of 7 days\n\n";

}
