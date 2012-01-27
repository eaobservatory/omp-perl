#!/local/perl/bin/perl

=head1 NAME

scuba2-acct - Generate SCUBA-2 usage statistics

=head1 SYNOPSIS

Show usage only for Jan 13 2012 ...

  scuba2-acct  20120113

Show usage for Jan 13 2012 to Jan 23 2012 ...

  scuba2-acct  20120113 20120123


=head1 DESCRIPTION

Calculate usage statistics for the supplied start date and optional
end date.  Calibrations are assigned to the project in proportion to
the amount of science time spent relative to other projects.

Fault time is charged if a fault on the night is associated with a
SCUBA-2 project.

Currently assumes JCMT.

=head1 OPTIONS

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

use OMP::DateTools;
use OMP::NightRep;

use Getopt::Long;
use Pod::Usage;
use Time::Seconds 'ONE_DAY';

my $TELESCOPE  = 'JCMT';
my $SCUBA2     = 'SCUBA-2';
my $SCUBA2_CAL = 'SCUBA-2-CAL';
my $OTHER_INST = 'Other Instruments';

my $man;
my $help;
my $verbose;

my $result = GetOptions(
                        "verbose" => \$verbose,
                        "h|help" => \$help,
                        "man" => \$man,
                       );

my ( $start_date , $end_date ) = @ARGV[0,1];

die "No start date given.\n"
  unless $start_date;

for ( $start_date, $end_date ) {

  next unless $_;
  $_ = OMP::DateTools->parse_date( $_ );
}
$end_date = $start_date unless $end_date;

my ( %stat );
my $date = $start_date;

while ( $date <= $end_date ) {

  my $date_str = $date->ymd( '' );

  my $rep = OMP::NightRep->new( 'date' => $date_str, 'telescope' => $TELESCOPE );

  my $group = $rep->obs() or next;

  my @scuba2;
  for my $obs ( $group->obs() )
  {
    my $inst = $obs->instrument() or next;

    push @scuba2, $obs->projectid()
      if $SCUBA2 eq uc $inst;
  }
  if ( scalar @scuba2 ) {

    my %acct = $rep->accounting();
    show_warnings( \%acct );

    $stat{ $date_str } = get_inst_proj_time( \%acct, @scuba2 );
    $stat{ $date_str }->{'FAULTS'} = get_fault_time( $rep->faults(), @scuba2 );
  }

  $date += ONE_DAY;
}

print_stat( %stat );
exit;


sub print_stat {

  my ( %stat ) = @_;

             print "Date     SCUBA-2 Time    CAL Time  Fault Loss\n";
  my     $format = "%8s       %0.2f          %0.2f     %0.2f\n";
  my $format_sum = (' ') x ( 8 + 6 )
                           . "%0.2f         %0.2f     %0.2f\n";

  my ( $s2_sum, $s2_cal_sum, $fault_sum );

  for my $date ( sort keys %stat ) {

    my @time = map { $stat{ $date }->{ $_ } } ( $SCUBA2, $SCUBA2_CAL, 'FAULTS' );

    $s2_sum     += $time[0];
    $s2_cal_sum += $time[1];
    $fault_sum  += $time[2];

    printf $format, $date, @time;
  }

  print "-------------------------------------------------\n";
  printf $format_sum, $s2_sum, $s2_cal_sum, $fault_sum;
  return;
}


sub get_fault_time {

  my ( $group, @scuba2 ) = @_;

  return unless $group;

  my %time;
  for my $proj ( @scuba2 ) {

    next if exists $time{ $proj };

    for my $fault ( $group->faults() ) {

      if ( grep { m/$proj/i } $fault->projects() ) {

        # Returns in hours.
        $time{ $proj } += $fault->timelost();
      }
    }
  }

  return unless values %time;
  return sum_hashref_time( \%time );
}

sub get_inst_proj_time {

 my ( $acct, @scuba2_proj ) = @_;

  my @ignore = ( 'WEATHER', 'EXTENDED', 'OTHER', 'UNKNOWN', 'FAULTS' , 'CAL' );
  my $ignore = join '|', @ignore;
     $ignore = qr{(?:$ignore)$}i;

  my %time;
  for my $proj ( keys %{ $acct } ) {

    next if $proj =~ $ignore;

    my $save =
      scalar grep( $proj eq $_, @scuba2_proj )
      ? $SCUBA2
      : $OTHER_INST;

    # Instead of creating a layer of indirection with $time{ $save }->{ $proj }
    # to be expanded later, just sum up now.
    $time{ $save } += extract_hours( $acct->{ $proj } );
  }

  my @cal = grep { /CAL/ } keys %{ $acct };
  $time{'CAL'} += extract_hours( $acct->{ $_ } ) for @cal;

  my $s2_time    = $time{ $SCUBA2 };
  my $other_time = $time{ $OTHER_INST };
  my $inst_total = $s2_time + $other_time;
  if ( $inst_total > 0 ) {

    $time{ $SCUBA2_CAL } = ( $time{'CAL'} * $s2_time ) / $inst_total ;
  }
  # Convert to hours.
  for my $key ( keys %time ) {

    $time{ $key } /= 3600;
  }
  return \%time;
}

sub sum_hashref_time {

  my ( $hash ) = @_;

  my $s = 0;
  for my $k ( keys %{ $hash } ) {

    $s += $hash->{ $k };
  }
  return $s;
}

sub extract_hours {

  my ( $acct ) = @_;

  return 0 unless defined $acct;

  my $source;
  if ( exists $acct->{'DB'} && $acct->{'DB'}->confirmed() ) {

    $source = 'DB';
  }
  elsif ( exists $acct->{'DATA'} ) {

    $source = 'DATA';
  }
  elsif ( exists $acct->{'DB'} ) {

    $source = 'DB';
  }

  return 0 unless $source;
  return $acct->{ $source }->timespent()->seconds();
}

sub show_warnings {

  my ( $acct ) = @_;

  my $key = $OMP::NightRep::WARNKEY;

  return unless exists $acct->{  $key };

  my $warn =  $acct->{ $key };
  delete $acct->{ $key };

  return unless scalar @{ $warn };

  print join "\n", "Warnings from header analysis:", @{ $warn }, '';
  return;
}


=head1 AUTHOR

Anubhav <a.agarwal@jach.hawaii.edu>

=head1 COPYRIGHT

Copyright (C) 2012 Science & Technology Facilities Council.
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
