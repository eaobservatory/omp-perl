#!/local/perl/bin/perl

=head1 NAME

radionet-acct - Generate RadioNet usage statistics

=head1 SYNOPSIS

  radionet-acct 11A M11AN08

=head1 DESCRIPTION

Calculate usage statistics for the supplied project in the supplied
semester. Calibrations are assigned to the project in proportion to
the amount of science time spent relative to other projects. Fault
time is charged if a fault on the night is associated with the
project ID.

Currently assumes JCMT.

=head1 OPTIONS

=item B<-verbose>

Be verbose.

=item B<-help>

A help message.

=item B<-man>

This manual page.

=back

=cut

use warnings;
use strict;

BEGIN {
  use FindBin;
  use constant OMPLIB => "$FindBin::RealBin/..";
  use lib OMPLIB;

  $ENV{'OMP_DIR'} = OMPLIB unless exists $ENV{'OMP_DIR'};
}

use OMP::NightRep;
use OMP::TimeAcctDB;
use OMP::DateTools;

use Time::Seconds qw/ ONE_DAY /;
use Getopt::Long;
use Pod::Usage;

my $man;
my $help;
my $verbose;

my $result = GetOptions(
                        "verbose" => \$verbose,
                        "h|help" => \$help,
                        "man" => \$man,
                       );

my $SEMESTER = $ARGV[0];
my $PROJECT = $ARGV[1];
my $TELESCOPE = "JCMT";

die "Please specify a semester\n"
  unless defined $SEMESTER;
die "Please specify a project ID\n"
  unless defined $PROJECT;
$PROJECT = uc($PROJECT);

# Convert the semester to a date range

my ($start, $end) = OMP::DateTools->semester_boundary( semester => $SEMESTER,
                                                       tel => $TELESCOPE );

# Now we need to find the nights in that range that we observed that
# project. It should be possible to do a quick query on the time accounting
# table for this information.

# For now assume all dates are valid
my %totals;
my $current = $start;

while ( $current < $end ) {
  my $nr = OMP::NightRep->new( date => $current,
                               telescope => $TELESCOPE);

  my %data = $nr->accounting_db();

  # See if we have the project
  if (exists $data{$PROJECT}) {

    # Calculate total project time
    my $projtotal = 0;
    my $calkey;
    for my $proj (keys %data) {
      $calkey = $proj if $proj =~ /CAL$/;
      next if $proj =~ /^$TELESCOPE/;
      $projtotal += $data{$proj}->timespent->seconds;
    }

    my $projtime = $data{$PROJECT}->timespent->seconds;

    my $projcaltime = 0.0;
    my $fraction = 0.0;
    if ($projtotal > 0) {
      $fraction = $projtime / $projtotal;
      if ( defined $calkey ) {
        $projcaltime = $fraction * $data{$calkey}->timespent->seconds;
      }
    }

    # Now get the faults for this night
    my $faultloss = 0.0;
    my $faultgrp = $nr->faults;
    for my $fault ($faultgrp->faults) {
      if (grep { /$PROJECT/i  } $fault->projects ) {
        $faultloss += $fault->timelost;
      }
    }

    # Store it
    $totals{$current->ymd} = { PROJTIME => ($projtime / 3600 ),
                               CALTIME => ( $projcaltime / 3600 ),
                               FAULTTIME => $faultloss,
                               };
  }

  # Go to next day
  $current += ONE_DAY;
}

my $fulltotal = 0;
my $fullproj = 0;
my $fullcal = 0;
my $fullfault = 0;

print " UT          Proj    CAL  FAULT  TOTAL\n";
for my $night (sort keys %totals) {
  my $this = $totals{$night};
  my $total = 0.0;
  for my $key (qw/ PROJTIME CALTIME FAULTTIME / ) {
    $total += $this->{$key};
  }
  printf "%s %6.2f %6.2f %6.2f %6.2f\n",$night, $this->{PROJTIME},
    $this->{CALTIME}, $this->{FAULTTIME}, $total;

  $fulltotal += $total;
  $fullproj += $this->{PROJTIME};
  $fullcal  += $this->{CALTIME};
  $fullfault+= $this->{FAULTTIME};

}
print "-----------------------------------\n";
printf "           %6.2f %6.2f %6.2f %6.2f\n",$fullproj,
  $fullcal, $fullfault, $fulltotal;

exit;

=head1 AUTHOR

Tim Jenness <t.jenness@jach.hawaii.edu>

=head1 COPYRIGHT

Copyright (C) 2011 Science & Technology Facilities Council.
All Rights Reserved.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 3 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful,but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc., 59 Temple
Place,Suite 330, Boston, MA  02111-1307, USA

=cut
