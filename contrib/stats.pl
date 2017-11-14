#!/local/bin/perl

=head1 NAME

ompstats - Derive daily, weekly, and monthly operation statistics
           from the JAC OMP.

=head1 SYNOPSIS

  ompstats -tel UKIRT -stats monthly -first yyyymmdd  -last yyyymmdd
  ompstats (program will prompt for any info not on the command-line)

=head1 DESCRIPTION

Prints table with UKIRT or JCMT operations statistics over a period of
time. Reporting can be daily, weekly, or monthly, recursing over the
requested period.  A summary with the cumulative statistics is
appended to the report.

=head1 OPTIONS

The following options are supported:

=over 4

=item B<-help>

Print help information.

=item B<-version>

Print version information.

=item B<-man>

Print the full documentation to STDOUT.

=item B<-debug>

Switch on debug output (nothing at present)

=item B<-tel>

Telescope to obtain statistics for: UKIRT | JCMT

=item B<-stats>

Statistics: d(aily) | m(onthly) | w(eekly) recursing over the
requested period. Note that the monthly statistics will always look at
the whole month even if the start or end date are part-way within the
month. The weekly statistics will start the seven day blocks on the
start date, but may extend the last block beyond the end date.

=item B<-utx>

This parameters is only used for the monthly stats. Ordinarily the
stats are derived from UT the 1st in the month. However, traditionally
the semesters start on UT the 2nd (evening of HST 1st). When '-utx' is
specified the monthly stats are derived from UT the 2nd of each month
through UT the 1st of the next month. The daily and weekly stats
operate in UT exclusively.

=item B<-first, -last>

First and last UT date ('yyyymmdd') to report on. Note that for the
monthly stats the day numbers are irrelevant: -first 20080131 -last 20080501
will report on January thru May.

=item B<-xw>

Plot stats as stacked bar chart to screen.

=item B<-gif/-ps>

Plot (also) to a gif or postscript file: -gif filename/-ps filename.

=item B<-hours>

Plot statistics in 'hours' instead of as percentages versus time available.

=back

=cut

# ----------------------------------------------------------------------

use FindBin;
use File::Spec;

use constant OMPLIB => "$FindBin::RealBin/../lib";

BEGIN { 
  $ENV{OMP_CFG_DIR} = File::Spec->catdir(OMPLIB, "../cfg")
         unless exists $ENV{OMP_CFG_DIR};
  $ENV{PGPLOT_DIR} = "/star/bin"
         unless (exists $ENV{PGPLOT_DIR});
  $ENV{PATH} = "/usr/bin";
}

use lib OMPLIB;
use OMP::NightRep;
use Time::Seconds;
use Time::Piece;
use Getopt::Long;
use Pod::Usage;

use PGPLOT;
use strict;
use warnings;

our $VERSION = '2.000';

# ----------------------------------------------------------------------

my $progname = (split(/\//,"$0"))[-1];
my ($prog, $suffix) = split(/\./,$progname,2);
my $vers = "1.0";

my ($help, $man, $version, $debug);
my ($tel, $statsmode, $utx, $first, $last, $xw, $gif, $ps, $hours);

# Default plotting devices
my $pdevice = "/xserve";  # screen
my $hdevice = "";         # no hardcopy

my $ostatus = GetOptions(   "help"        => \$help,
			    "man"         => \$man,
			    "version"     => \$version,
			    "debug"       => \$debug,
                            "tel=s"       => \$tel,
                            "statsmode=s" => \$statsmode,
                            "xut"         => \$utx,
                            "first=s"     => \$first,
                            "last=s"      => \$last,
                            "xw"          => \$xw,
                            "gif=s"       => \$gif,
                            "ps=s"        => \$ps,
                            "hours"       => \$hours
                         );

pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose =>2) if $man;
if ($version) {
    print "${prog} - show UKIRT/JCMT operations statistics.\n";
    print "Version: ", $VERSION, "\n";
    exit;
}


# Hash to hold running total
my %grand = (
    days      => 0.0,
    proj      => 0.0,
    weather   => 0.0,
    tfaults   => 0.0,
    hfaults   => 0.0,
    other     => 0.0,
    extended  => 0.0,
    cal       => 0.0,
    shutdown  => 0.0,
    hours     => 0.0
);

# Array of hashes to hold daily/weekly/monthly stats
my @stats;

# ----------------------------------------------------------------------
# Parse the command line options

unless (defined $tel) {
  print STDERR "Telescope? jcmt | ukirt: ";
  chomp($tel = <STDIN>);
}
if ($tel =~ /^j/i) {
  $tel = "JCMT";
} elsif ($tel =~ /^u/i) {
  $tel = "UKIRT";
} else {
  die "Telescope must be JCMT or UKIRT (case insensitive)\n";
}
$tel = uc $tel;

unless (defined $statsmode) {
  print STDERR "What kind of statistics? [m]onthly/(w)eekly/(d)aily: ";
  chomp($statsmode = <STDIN>);
  if ($statsmode =~ /^m/i) {
    if (defined $utx) {
      $utx = "HST";
    } else {
      print STDERR "Start monthly stats on UT 1st? (Else start HST 1st = UT 2nd) [y]/n: ";
      chomp($utx = <STDIN>);
      if ($utx =~ /^n/i) { 
        $utx = "HST";
      } else {
        $utx = "UT";
      }
    }
  }
}

if ($statsmode =~ /^w/i) {
  $statsmode = 'weekly';
} elsif ($statsmode =~ /^d/i) {
  $statsmode = 'daily';
} else {
  $statsmode = 'monthly';
}

$utx = "UT" unless (defined $utx);

my $startut;
if (defined $first) {
  $startut = $first;
} else {
  print STDERR "First date? YYYYMMDD: ";
  chomp($startut = <STDIN>);
}
die "start ut date not YYYYMMDD:" if ($startut !~ /^\d{8}$/);
die "start ut date not valid:" if ($startut < 20030000 or $startut > 20200000);

my $endut;
if (defined $last) {
  $endut = $last;
} else {
  print STDERR "Last date?  YYYYMMDD: ";
  chomp ($endut = <STDIN>);
}
die "end ut date not YYYYMMDD:" if ($endut !~ /^\d{8}$/);
die "end ut date not valid:" if ($endut < 20030000 or $endut > 20200000);
die "start ut must be before end ut" if ($startut > $endut);

if ($gif) {
  $gif = "${gif}.gif" if ($gif !~ /\./);
  $hdevice = "${gif}/gif";
}
if ($ps) {
  $ps = "${ps}.ps" if ($ps !~ /\./);
  $hdevice = "${ps}/cps";
}

print "\n$tel $statsmode operations stats ($utx) from $startut thru $endut\n\n";

# ----------------------------------------------------------------------
#
# Loop over blocks
#
my $loop = 0;
my $ut = $startut;
my $maxtotal = -1;
while ($ut <= $endut) {

  $loop++;
  my $yy = substr($ut,0,4);
  my $mm = substr($ut,4,2);
  my $dd = substr($ut,6,2);

  #Convert time to object. Assumes YYYY-MM-DDTHH:MM format
  my $t = new Time::Piece->strptime( "$ut","%Y%m%d" );

  # Need to set up start ut and delta for each block. Special
  # handling in case of 'utx'.
  my $iut;
  my $delta;
  if ($statsmode =~ /^m/i) {
    $dd = "01";
    $dd = "02" if ($utx eq "HST");
    $iut = $yy . $mm . $dd;

    $delta = 31;
    $delta = 30 if ($mm == 4 or $mm == 6 or $mm == 9 or
                       $mm == 11);
    $delta = 28 if ($mm == 2);
    $delta = 29 if ($mm == 2 and
                   ( ($yy%4 == 0 and $yy%100 != 0) or
                      $yy%400 == 0 ));
  } elsif ($statsmode =~ /^d/i) {
    $iut = $ut;
    $delta = 1;
  } else {
    $iut = $ut;
    $delta = 7;
  }

  # Reset start date to actual value used
  $startut = $iut if ($loop == 1);

  # Get the accounting objects from the OMP
  my $nr = OMP::NightRep->new(date => $iut,
			      telescope => $tel,
			      delta_day => $delta,);
  my %acct = $nr->accounting_db(1);

  my $total = 0;
  my $total_pending = 0;
  my $total_eac = 0;

  # Get fault loss
  # (human fault loss would be difference between next two)
  my $faultloss     = $nr->timelost->hours;
  my $technicalloss = $nr->timelost('technical')->hours;
  $total += $faultloss;

  # Cycle over each project and count the time
  my %items;
  $items{"eac"} = 0.0;
  my $total_proj = 0.0;
  foreach my $proj (keys %acct) {

    # Special projects start with the Tel name (a bit of a hack this if)
    next if $proj =~ /^$tel/;

    my $account = $acct{$proj};
    $total      += $account->{total}->hours;
    $total_proj += $account->{total}->hours;

    # Get project details instead
    my $details = OMP::ProjServer->projectDetailsNoAuth($proj, "object");

    my $country = $details->country;
    if ( $country =~ /ec/i ) {
      $total_eac    += $account->{total}->hours;
    }

    my $pending;
    if  ($account->{pending}) {
      $total_pending += $account->{pending}->hours;
      $pending       = $account->{pending}->hours;
    }

    my $time = $account->{total}->hours;
    $time *= -1 if ($pending);

    # Not actually using this at present
    $items{"$proj"} = "${time}\@${country}";

  }

  # Special accounting queues which are prepended by the telescope name
  foreach my $queue (qw/WEATHER OTHER EXTENDED CAL _SHUTDOWN/) {
    my $time = 0.0;
    my $pending;
    if (exists $acct{$tel.$queue}) {
      $time = $acct{$tel.$queue}->{total}->hours;
      if ($acct{$tel.$queue}->{pending}) {
	$pending += $acct{$tel.$queue}->{pending}->hours;
      }
      $total += $time unless $queue =~ /EXTENDED/;
    }

    $time *= -1 if ($pending);
    $items{lc("$queue")} = $time;
  }

  if ( $tel =~ /^j/i ) {
    print STDOUT "   UT       Projects  Weather  Faults  Other  Extended  Cal    Closed  Unreport  Total  Frate\n" if ($loop == 1);
  } else {
    print STDOUT "   UT       Projects of which EAC  Weather  Faults  Other  Cal    Closed  Total  Frate\n" if ($loop == 1);
  }

  printf STDOUT "%2.2d/%2.2d/%4.4d",$mm,$dd,$yy;
  printf STDOUT "  %6.2f",$total_proj;
  printf STDOUT "    %6.2f   ",$total_eac if ( $tel =~ /^u/i );

  printf STDOUT "    %6.2f",abs($items{"weather"});
  print  STDOUT "p" if ($items{"weather"} < 0);

  printf STDOUT "  %6.2f",$faultloss;

  printf STDOUT "  %6.2f",abs($items{"other"});
  print  STDOUT  "p" if ($items{"other"} < 0);

  if ( $tel =~ /^j/i ) {
    printf STDOUT "  %6.2f  ",abs($items{"extended"});
    print  STDOUT  "p" if ($items{"extended"} < 0);
  }

  printf STDOUT "%6.2f",abs($items{"cal"});
  print  STDOUT  "p" if ($items{"cal"} < 0);

  if ( $tel =~ /^j/i ) {
    print  STDOUT  "     ... ";
    printf STDOUT "  %6.2f",$delta*12-$total;
    printf STDOUT "   %6.2f",$total;
  } else {
    printf STDOUT "  %6.2f",$items{"_shutdown"};
    printf STDOUT "  %6.2f",$total;
  }
  my $denom = $total-abs($items{"weather"});
  if ($denom > 0.1) {
    printf STDOUT " %6.2f%%",100.0*$faultloss/$denom;
  } else {
    printf STDOUT " %6.2f%%",0.0;
  }

  print STDOUT  "\n";

  # Add to Grand total
  $grand{"days"}     += $delta;
  $grand{"proj"}     += $total_proj;
  $grand{"eac"}      += $total_eac;
  $grand{"weather"}  += abs($items{"weather"});
  $grand{"tfaults"}  += $technicalloss;
  $grand{"hfaults"}  += $faultloss-$technicalloss;
  $grand{"other"}    += abs($items{"other"});
  $grand{"extended"} += abs($items{"extended"});
  $grand{"cal"}      += abs($items{"cal"});
  if ( $tel =~ /^j/i ) {
    $grand{"shutdown"} += $delta*12-$total;
  } else {
    $grand{"shutdown"} += abs($items{"_shutdown"});
  }
  $grand{"hours"}    += $total;

  # Push on hash array for plotting
  my %ref;
  $ref{"iut"}      = $iut;
  $ref{"hours"}    = $total;
  $ref{"proj"}     = $total_proj;
  $ref{"eac"}      = $total_eac;
  $ref{"weather"}  = abs($items{"weather"});
  $ref{"tfaults"}  = $technicalloss;
  $ref{"hfaults"}  = $faultloss-$technicalloss;
  $ref{"other"}    = abs($items{"other"});
  $ref{"extended"} = abs($items{"extended"});
  $ref{"cal"}      = abs($items{"cal"});
  if ( $tel =~ /^j/i ) {
    $ref{"available"} = $delta*12;
    $ref{"available"} -= 12 if ( ${yy}*1e+04+1225 >= $iut and 
                                 ${yy}*1e+04+1225 <  $iut+$delta and
                                 $statsmode !~ /^d/i );
    $ref{"shutdown"}  = $delta*12-$total;
  } else {
    $ref{"available"} = $total;
    $ref{"shutdown"}  = abs($items{"_shutdown"});
    if ( $total == 0 ) {
      $ref{"available"} = 12.0;
      $ref{"shutdown"}  = 12.0;
    }
  }

  # Save maximum for plotting
  $maxtotal = $total+$items{"extended"}
              if ($total+$items{"extended"} > $maxtotal);

  push @stats, \%ref;

  # Add delta to the datetime object
  $t += (24*3600*$delta);

  $ut = $t->ymd;
  $ut =~ s/\-//g;

}

# Print Grand summary

print STDOUT  "\n\n";

if ( $tel =~ /^j/i ) {
  printf STDOUT "The report from $startut covers %d scheduled ", 
        $grand{"days"};
  printf STDOUT "12-hour nights, in total %3d hours:\n\n", 12*$grand{"days"};
} else {
  printf STDOUT "The report from $startut covers %d scheduled nights ", 
        $grand{"days"};
  printf STDOUT "for a total of %6.2f hours:\n\n", $grand{"hours"};
}

printf STDOUT "Scheduled Time used for Observing   %7.2f  %6.2f%%\n",
        $grand{"proj"}, 100*$grand{"proj"}/$grand{"hours"};

printf STDOUT "                  of which on EAC   %7.2f  %6.2f%%\n",
        $grand{"eac"}, 100*$grand{"eac"}/$grand{"hours"}
     if ( $tel =~ /^u/i );

printf STDOUT "Time lost to Weather                %7.2f  %6.2f%%\n",
        $grand{"weather"}, 100*$grand{"weather"}/$grand{"hours"};

printf STDOUT "Clear Time lost to Faults           %7.2f  %6.2f%%",
       $grand{"tfaults"}+$grand{"hfaults"},
       100*($grand{"tfaults"}+$grand{"hfaults"})/$grand{"hours"};

if ( $grand{"hours"} != $grand{"weather"} ) {
        printf STDOUT "   (fault rate: %6.2f%%)\n",
        100*($grand{"tfaults"}+$grand{"hfaults"})/
        ($grand{"hours"}-$grand{"weather"});
} else {
        printf STDOUT "   (fault rate: %6.2f%%)\n", 0.0;
}

printf STDOUT "Scheduled Closed                    %7.2f  %6.2f%%\n",
        $grand{"shutdown"}, 100*$grand{"shutdown"}/$grand{"hours"};
printf STDOUT "Other Time                          %7.2f  %6.2f%%\n",
        $grand{"other"}, 100*$grand{"other"}/$grand{"hours"};
printf STDOUT "Unallocated Calibrations            %7.2f  %6.2f%%\n",
        $grand{"cal"}, 100*$grand{"cal"}/$grand{"hours"};
printf STDOUT "Total Schedule Time                 %7.2f  %6.2f%%\n",
        $grand{"hours"}, 100*$grand{"hours"}/$grand{"hours"};

printf STDOUT "Extended Time                       %7.2f  %6.2f%%\n",
        $grand{"extended"}, 100*$grand{"extended"}/$grand{"hours"}
    if ( $tel =~ /^j/i );
print "\n\n";

# Make plot to screen
&plot_stats() if (defined $xw );

# Plot to file
if ( $hdevice ne "" ) {
  $pdevice = $hdevice;
  &plot_stats();
}

exit;

sub plot_stats {

  my %days = ( 'daily' => 1, 'weekly' => 7, 'monthly' => 28 );

  # Plot boundaries
  my $xlo = 0;
  my $xhi = $#stats+2;
  my $ylo = 0;
  my $yhi;
  my $pfactor = 1.0;

  my $xlabel;
  my $ylabel;
  my $ytick;
  if ($statsmode =~ /^m/i) {
    $xlabel = "Months";
    $ytick  = 5*12;
  } elsif ($statsmode =~ /^w/i) {
    $xlabel = "Weeks";
    $ytick  = 12;
  } else {
    $xlabel = "Days";
    $ytick  = 3;
  }

  if ( defined $hours ) {
    $yhi = 1.1*$maxtotal;
    $ylabel = "Hours";
  } else {
    $pfactor = 100.0;
    $yhi = int (100.0*$maxtotal/(12*$days{$statsmode}));
    $yhi = int 1.05*$yhi if ( $tel =~ /^j/i );
    $ylabel = "Percentage";
  }

  my $xrange = $xhi-$xlo;
  my $yrange = $yhi-$ylo;

  pgbegin(0,$pdevice,1,1);               # Open device: single window

  pgpage;                                # Open new page
  pgvstand;                              # Standard view port

  pgwindow($xlo,$xhi,$ylo,$yhi);

  if ($pdevice =~ /gif/) {               # Swap black and white for gif
    pgscr(0,1,1,1);                      # so that it will have a white
    pgscr(1,0,0,0);                      # background as the /ps
  }

  my $lw = 3;
  pgslw($lw);

  my $scd = 1.0;
  my $sc = 1.2*$scd;
  pgsch($sc);

  my ($x1, $x2, $y1, $y2, $tx, $ty );

  $tx = 0.0;
  $tx += 0.08*$xrange if ( $tel =~ /^u/i );
  $ty = $yhi + 0.02*$yrange;

  for ( my $i = 0; $i <= $#stats; $i++ ) {

    $x1 = $i+0.55;
    $x2 = $i+1.45;
    $y1 = 0.0;
    $y2 = 0.0;

    my $avail;
    if ( defined $hours ) {
      $avail = 1.0;
    } else {
      $avail = $stats[$i]{"available"};
    }

    pgsci(3);
    $y2 += $pfactor*$stats[$i]{"proj"}/$avail;
    pgrect( $x1, $x2, $y1, $y2 ) if ($y2 != $y1);
    $tx += 0.02*$xrange; pgtext($tx, $ty, "Science") if ($i == 0);

    pgsci(5);
    $y1 = $y2;
    $y2 += $pfactor*$stats[$i]{"other"}/$avail;
    pgrect( $x1, $x2, $y1, $y2 ) if ($y2 != $y1);
    $tx += 0.15*$xrange; pgtext($tx, $ty, "Other") if ($i == 0);

    pgsci(6);
    $y1 = $y2;
    $y2 += $pfactor*$stats[$i]{"cal"}/$avail;
    pgrect( $x1, $x2, $y1, $y2 ) if ($y2 != $y1);
    $tx += 0.15*$xrange; pgtext($tx, $ty, "Cal") if ($i == 0);

    pgsci(4);
    $y1 = $y2;
    $y2 += $pfactor*($stats[$i]{"tfaults"}+$stats[$i]{"hfaults"})/$avail;
    pgrect( $x1, $x2, $y1, $y2 ) if ($y2 != $y1);
    $tx += 0.10*$xrange; pgtext($tx, $ty, "Faults") if ($i == 0);

    pgsci(7);
    $y1 = $y2;
    $y2 += $pfactor*$stats[$i]{"shutdown"}/$avail;
    pgrect( $x1, $x2, $y1, $y2 ) if ($y2 != $y1);
    $tx += 0.15*$xrange; pgtext($tx, $ty, "Closed") if ($i == 0);

    pgsci(1);
    $y1 = $y2;
    $y2 += $pfactor*$stats[$i]{"weather"}/$avail;
    pgrect( $x1, $x2, $y1, $y2 ) if ($y2 != $y1);
    $tx += 0.15*$xrange; pgtext($tx, $ty, "Weather") if ($i == 0);

    pgsci(2);
    if ( $tel =~ /^j/i ) {
      $y1 = $y2;
      $y2 += $pfactor*$stats[$i]{"extended"}/$avail;
      pgrect( $x1, $x2, $y1, $y2 ) if ($y2 != $y1);
      $tx += 0.15*$xrange; pgtext($tx, $ty, "Extended") if ($i == 0);
    }

  }

  # Draw box last to make sure axes on top
  pgsci(1);

  my $iut = $stats[0]{"iut"};
  my $title = "$tel operations statistics $statsmode from $iut";

  pgbox('BCNST',0,0,'BCNST',0,$ytick);
  pglab ($xlabel, $ylabel, $title);

  pgend;

}



=head1 AUTHOR

Remo Tilanus E<lt>r.tilanus@jach.hawaii.eduE<gt>

Copyright (C) 2008 Science and Technology Facilities Council.
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

= cut
