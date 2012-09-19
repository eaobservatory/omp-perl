#!/local/bin/perl

# Derive Monthly, Weekly, or Daily stats for the JCMT over a given
# time interval based from the accounting in the OMP.
#


BEGIN { $ENV{SYBASE} = "/local/progs/sybase";
        $ENV{OMP_CFG_DIR} = "/jac_sw/omp/msbserver/cfg"
          unless exists $ENV{OMP_CFG_DIR};
        $ENV{PATH} = "/usr/bin";
      }

use lib "/jac_sw/omp/msbserver";
use OMP::NightRep;
use Time::Seconds;
use Time::Piece;
use Getopt::Long;
use strict;

my $tel = 'JCMT';

my %grand = (
    days     => 0.0,
    proj     => 0.0,
    weather  => 0.0,
    tfaults  => 0.0,
    hfaults  => 0.0,
    other    => 0.0,
    extended => 0.0,
    jcmtcal  => 0.0,
    shutdown => 0.0,
    unrep    => 0.0,
    hours    => 0.0
);

# ----------------------------------------------------------------------
# Parse the command line options

my ($vers, $help, $man, $statsmode, $uutx, $ffirst, $llast);
my $status = GetOptions("version" => \$vers,
                        "help" => \$help,
                        "man" => \$man,
                        "statsmode=s" => \$statsmode,
                        "xut" => \$uutx,
                        "first=s"  => \$ffirst,
                        "last=s" => \$llast,
                       );



my $progname = (split(/\//,"$0"))[-1];
my ($prog, $suffix) = split(/\./,$progname,2);
my $version = "1.0";

if (defined $help or defined $man) {
  print qq{
Name: ${progname} - Derive JCMT operations statistics from the OMP
Version: $version\n
Use: $progname [-v|-h] [-s m|w|d] [-x] [-f yyyymmdd] [-l yyyymmdd]\n
\t-h: \t this help
\t-v: \t version
\t-s: \t [m]onthly, [w]eekly, or [d]aily statistics
\t-x: \t Start monthly stats on UT 2nd i.e. night following HST 1st.
\t-f: \t First date (yyyymmdd)
\t-l: \t Last date (yyyymmdd)
\n
};
  exit;
}

if (defined $vers) {
  print qq {
\t$progname --- version $version
\tDerive JCMT operations statistics from the OMP
\tContact Remo Tilanus (rpt\@jach.hawaii.edu) for more information

};
  exit;
}

my $statmode;
if (defined $statsmode) {
  $statmode = $statsmode;
} else {
  print "What kind of statistics? [m]onthly/(w)eekly/(d)aily: ";
  chomp($statmode = <STDIN>);
}
if ($statmode =~ /^w/i) {
  $statmode = 'weekly';
} elsif ($statmode =~ /^d/i) {
  $statmode = 'daily';
} else {
  $statmode = 'monthly';
}

my $utx = "UT";
if ($statmode eq "monthly") {
  if (defined $uutx) {
     $utx = "HST";
  } else {
    print "Start monthly stats on UT 1st? (Else start HST 1st = UT 2nd) [y]/n: ";
    chomp(my $answer = <STDIN>);
    $utx = "HST" if ($answer =~ /^n/i);
 }
}

my $startut;
if (defined $ffirst) {
  $startut = $ffirst;
} else {
  print "First date? YYYYMMDD: ";
  chomp($startut = <STDIN>);
}
die "start ut date not YYYYMMDD:" if ($startut !~ /^\d{8}$/);
die "start ut date not valid:" if ($startut < 20030000 or $startut > 20200000);

my $endut;
if (defined $llast) {
  $endut = $llast;
} else {
  print "Last date?  YYYYMMDD: ";
  chomp ($endut = <STDIN>);
}
die "end ut date not YYYYMMDD:" if ($endut !~ /^\d{8}$/);
die "end ut date not valid:" if ($endut < 20030000 or $endut > 20200000);

die "start ut must be before end ut" if ($startut > $endut);

my $outfile = "${prog}_${startut}_${statmode}.txt";
open(OUTPUT,">${outfile}") || die "Failed to open ${outfile}";

my $ut = $startut;
print "\nMode: $statmode from $startut thru $endut\n\n";
print OUTPUT "\nMode: $statmode from $startut thru $endut\n\n";

my $loop = 0;
while ($ut <= $endut) {

  my $total = 0;
  my $total_pending = 0;

  $loop++;
  my $yy = substr($ut,0,4);
  my $mm = substr($ut,4,2);
  my $dd = substr($ut,6,2);

  #Convert time to object. Assumes YYYY-MM-DDTHH:MM format
  my $t = new Time::Piece->strptime( "$ut","%Y%m%d" );

  my $iut;
  my $delta;
  if ($statmode =~ /^m/i) {


    $dd = "01";
    $dd = "02" if ($utx eq "HST");
    $iut = $yy . $mm . $dd;

    $delta = 31;
    $delta = 30 if ($mm == 4 or $mm == 6 or $mm == 9 or
                       $mm == 11);
    $delta = 28 if ($mm == 2);
    $delta = 29 if ($mm == 2 && $yy%4 == 0);

  } elsif ($statmode =~ /^d/i) {

    $iut = $ut;
    $delta = 1;

  } else {

    $iut = $ut;
    $delta = 7;

  }

  print "Date: $iut\n";
  my $nr = OMP::NightRep->new(date => $iut,
			      telescope => $tel,
			      delta_day => $delta,);

  my $countrylist = "DDT EC CA INT NL UH UK JLS";

  my %acct = $nr->accounting_db(1);

  my $faultloss = $nr->timelost->hours;
  my $technicalloss = $nr->timelost('technical')->hours;
  my %items;

  $total += $faultloss;

  my $total_proj = 0.0;

  foreach my $proj (keys %acct) {
    next if $proj =~ /^$tel/;
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

  my $cnr = 0;
  foreach my $country ( split(/\s/,$countrylist) ) {
    my $done_first = 0;
    foreach my $proj (keys %acct) {
      my ($ptime, $pcountry) = split(/\@/,$items{$proj});
      if ($pcountry eq $country) {
	#        printf "%-10.10s %6.2f hrs", $proj, abs($ptime);
	#        printf "    %-3.3s %6.2f hrs", $country, $country_totals[$cnr]
	#	    if ($done_first eq 0);
	$done_first++;
	#        print  "   [pending]" if ($ptime < 0);
	#        print  "\n";
      }
    }
    #   print "\n" if ($done_first > 0);
    $cnr++;
  }

  foreach my $proj (qw/WEATHER OTHER EXTENDED CAL _SHUTDOWN/) {
    my $time = 0.0;
    my $pending;
    if (exists $acct{$tel.$proj}) {
      $time = $acct{$tel.$proj}->{total}->hours;
      if ($acct{$tel.$proj}->{pending}) {
	$pending += $acct{$tel.$proj}->{pending}->hours;
      }
      $total += $time unless ($proj eq 'EXTENDED' or $proj eq '_SHUTDOWN');
    }

    $time *= -1 if ($pending);
    $items{lc("$proj")} = $time;
  }

  print OUTPUT "  UT        Projects Weather T.flts  H.flts  Other  Extended J_cal   Closed  Unreport Total  t.fperc  h.fperc\n" if ($loop == 1);

  printf OUTPUT "%2.2d/%2.2d/%4.4d",$mm,$dd,$yy;
  printf OUTPUT "  %6.2f",$total_proj;
  printf OUTPUT "  %6.2f",abs($items{"weather"});
  print  OUTPUT  "p" if ($items{"weather"} < 0);
  printf OUTPUT "  %6.2f",$technicalloss;
  printf OUTPUT "  %6.2f",$faultloss-$technicalloss;
  printf OUTPUT "  %6.2f",abs($items{"other"});
  print  OUTPUT  "p" if ($items{"other"} < 0);
  printf OUTPUT "  %6.2f",abs($items{"extended"});
  print  OUTPUT  "p" if ($items{"extended"} < 0);
  printf OUTPUT "  %6.2f",abs($items{"cal"});
  print  OUTPUT  "p" if ($items{"cal"} < 0);
  printf OUTPUT "  %6.2f",abs($items{"_shutdown"});
  print  OUTPUT  "p" if ($items{"_shutdown"} < 0);
  printf OUTPUT "  %6.2f",$delta*12-($total+abs($items{"_shutdown"}));
  printf OUTPUT "  %6.2f",$total;
  my $denom = $total-abs($items{"weather"});
  if ($denom > 0.1) {
    printf OUTPUT "  %6.2f\%",100.0*$faultloss/$denom;
    printf OUTPUT "  %6.2f\%",100.0*($faultloss-$technicalloss)/$denom;
  } else {
    printf OUTPUT "  %6.2f\%",0.0;
    printf OUTPUT "  %6.2f\%",0.0;
  }

  print OUTPUT  "\n";


  # Add to Grand total
  $grand{"days"}     += $delta;
  $grand{"proj"}     += $total_proj;
  $grand{"weather"}  += abs($items{"weather"});
  $grand{"tfaults"}  += $technicalloss;
  $grand{"hfaults"}  += $faultloss-$technicalloss;
  $grand{"other"}    += abs($items{"other"});
  $grand{"extended"} += abs($items{"extended"});
  $grand{"jcmtcal"}  += abs($items{"cal"});
  $grand{"shutdown"} += abs($items{"_shutdown"});
  $grand{"unrep"}    += $delta*12-($total+abs($items{"_shutdown"}));
  $grand{"hours"}    += $total;

  # Add delta to the datetime object
  $t += (24*3600*$delta);

  $ut = $t->ymd;
  $ut =~ s/\-//g;

}

# Print Grand summary

print OUTPUT  "\n\n";

printf OUTPUT "The period from ${startut} thru ${endut} ($utx) contained %3d scheduled\n",
       $grand{"days"};
printf OUTPUT "12-hour nights, in total %4d hours.\n\n", 12*$grand{"days"};

printf OUTPUT "Scheduled Time used for Observing   %7.2f  %6.2f%\n",
        $grand{"proj"}, 100*$grand{"proj"}/$grand{"hours"};
printf OUTPUT "Time lost to Weather                %7.2f  %6.2f%\n",
        $grand{"weather"}, 100*$grand{"weather"}/$grand{"hours"};
printf OUTPUT "Clear Time lost to Technical Faults %7.2f  %6.2f%\n",
        $grand{"tfaults"}, 100*$grand{"tfaults"}/($grand{"hours"}-$grand{"weather"});
printf OUTPUT "Clear Time lost to Human Faults     %7.2f  %6.2f%\n",
        $grand{"hfaults"}, 100*$grand{"hfaults"}/($grand{"hours"}-$grand{"weather"});
printf OUTPUT "Calibrations                        %7.2f  %6.2f%\n",
        $grand{"jcmtcal"}, 100*$grand{"jcmtcal"}/$grand{"hours"};
printf OUTPUT "Other Time                          %7.2f  %6.2f%\n",
        $grand{"other"}, 100*$grand{"other"}/$grand{"hours"};
printf OUTPUT "Unreported Time                     %7.2f  %6.2f%\n",
        $grand{"unrep"}, 100*$grand{"unrep"}/$grand{"hours"};
printf OUTPUT "Total Time Scheduled                %7.2f  %6.2f%\n",
        $grand{"hours"}, 100*$grand{"hours"}/$grand{"hours"};
printf OUTPUT "Facility Shutdown                   %7.2f  %6.2f%\n",
        $grand{"shutdown"}, 100*$grand{"shutdown"}/$grand{"hours"};
printf OUTPUT "Total Nighttime available           %7.2f  %6.2f%\n",
        ($grand{"hours"}+$grand{"shutdown"}),
        100*($grand{"hours"}+$grand{"shutdown"})/$grand{"hours"};
printf OUTPUT "Extended Time                       %7.2f  %6.2f%\n\n\n",
        $grand{"extended"}, 100*$grand{"extended"}/$grand{"hours"};

close OUTPUT;

print "Finished: output in file ${outfile}\n\n";
