#!/local/bin/perl

# Short script to print an observing summary in the usual opsmeeting
# format.

BEGIN { $ENV{SYBASE} = "/local/progs/sybase";
        $ENV{OMP_CFG_DIR} = "/jac_sw/omp/msbserver/cfg"
          unless exists $ENV{OMP_CFG_DIR};
        $ENV{PATH} = "/usr/bin:/usr/local/bin:/usr/local/progs/bin:/usr/sbin";
      }

use DBI;
use DBD::Sybase;

use lib "/jac_sw/omp/msbserver";
use OMP::NightRep;
use strict;
use Getopt::Long;

my $total = 0;
my $total_pending = 0;

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

my $nr = OMP::NightRep->new(date => $startut,
			    telescope => $telescope,
			    delta_day => $delta,);

my $countrylist = "DDT EC CA INT NL UH UK JLS GT JAC";

my %acct = $nr->accounting_db(1);

my $faultloss = $nr->timelost->hours;
my $technicalloss = $nr->timelost('technical')->hours;
my %items;

$total += $faultloss;

my $total_proj = 0.0;

foreach my $proj (keys %acct) {
  next if $proj =~ /^$telescope/;
  my $account = $acct{$proj};
  $total += $account->{total}->hours;
  $total_proj += $account->{total}->hours;

  # No determine_country method exists, so we'll get project
  # details instead
  my $details = OMP::ProjServer->projectDetails($proj, "***REMOVED***", "object");

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
foreach my $country ( split(/\s+/,$countrylist) ) {
   my $ctotal = 0.0;
   foreach my $proj (keys %acct) {
      my ($ptime, $pcountry) = split(/\@/,$items{$proj});
      $ctotal += abs($ptime) if ($pcountry eq $country);
   }
   push @country_totals, $ctotal;
}

print
qq{__________________________________________________________________________


...Observing Summary:

};

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

print  "Total time lost to weather                   W:  ";
printf "%6.2f hrs",abs($items{"weather"});
print  "  \[pending\]" if ($items{"weather"} < 0);
print  "\n";

printf "Time lost to faults                          F:  %6.2f hrs\n",
             $faultloss;
printf "  technical faults         F1:  %6.2f hrs\n",
             $technicalloss;
printf "  non-technical faults     F2:  %6.2f hrs\n",
             $faultloss-$technicalloss;

printf "Prime time observed on Projects              P:  %6.2f hrs\n",
             $total_proj;

print  "Other Time                                   O:  ";
printf "%6.2f hrs",abs($items{"other"});
print  "  \[pending\]" if ($items{"other"} < 0);
print  "\n";

print  "Calibrations                                 C:  ";
printf "%6.2f hrs",abs($items{"cal"});
print  "  \[pending\]" if ($items{"cal"} < 0);
print  "\n";

print  "                                                 ------\n";
printf "Total                                        T:  %6.2f hrs\n",
	     $total;

print  "Facility Closure                             S:  ";
printf "%6.2f hrs",abs($items{"_shutdown"});
print  "  \[pending\]" if ($items{"_shutdown"} < 0);
print  "\n";

printf "Clear time lost to faults              F/(T-W):  %6.2f \%\n",
       100.0*$faultloss/($total-abs($items{"weather"}));
printf "Clear time lost to technical faults   F1/(T-W):  %6.2f \%\n",
       100.0*$technicalloss/($total-abs($items{"weather"}));
print  "\n";

print  "Extended Time                                E:  ";
printf "%6.2f hrs",abs($items{"extended"});
print  "  \[pending\]" if ($items{"extended"} < 0);
print  "\n\n";

my $cnr = 0;
foreach my $country ( split(/\s/,$countrylist) ) {
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


sub help () {

    print "\n";
    print "Use: projrep.pl [-tel JCMT|UKIRT] [-days #] yyyymmdd\n";
    print "     projrep.pl [-tel JCMT|UKIRT] [-days #] -ut yyyymmdd\n\n";
    print "Defaults are JCMT and a period of 7 days\n\n";

}
