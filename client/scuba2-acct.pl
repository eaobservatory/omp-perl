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

=over 2

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
use OMP::SCUBA2Acct;

use Getopt::Long;
use Pod::Usage;
use List::Util 'max';
use Time::Seconds 'ONE_DAY';

my $TELESCOPE  = 'JCMT';
my $SCUBA2     = 'SCUBA-2';
my $SCUBA2_CAL = 'SCUBA-2-CAL';
my $OTHER_INST = 'Other Instruments';

#  "It seems reasonable for you to define daytime as anything after 9:30am and
#  before 2pm [HST] and after 2pm and before 5pm [HST]. Note that in UT-land a
#  daytime TSS can be in two UT dates and [...] they will all probably start
#  before 2pm on the UT date listed and continue afterwards [...]" -- Tim,
#  <CA+G92Rfe547Yte4j6fA-FGa398=+JcRzFyC-ZNCkiMEvieY5cQ@mail.gmail.com>.
#
# Schedule is in HST time zone (-1000).
my %DAYTIME_UT =
  ( # 9.30a to < 2p HST;
    'prev' => [ '19:30:00', '23:59:59' ],
    # 2p    to < 5p HST.
    'next' => [ '00:00:00', '03:59:59' ],
  );

my ( $schedule_file );
my ( $man, $help );
my $result = GetOptions( "h|help" => \$help,
                          "man"   => \$man,
                          'tss=s' => \$schedule_file,
                        )
                or pod2usage( '-exitval' => 1, '=verbose' => 10);

$man  and pod2usage( '-exitval' => 1, '=verbose' => 10);
$help and pod2usage( '-exitval' => 1, '=verbose' => 0);

die "TSS schedule ($schedule_file) is unreadable\n"
  unless -r $schedule_file;

my %tss_sched = OMP::SCUBA2Acct::make_schedule( $schedule_file )
  or die "Could not parse schedule file.\n";

my @filter = verify_date( @ARGV );
@filter = sort keys %tss_sched
  unless scalar @filter;

my %stat;
for my $date ( @filter ) {

  my %data = generate_stat( $date ) or next;
  $stat{ $date } = $data{'inst'};
  $stat{ $date }->{'FAULTS'} = $data{'fault'};

  $stat{ $date }->{'TSS'} = $tss_sched{ $date }
    if exists $tss_sched{ $date } ;
}
print_stat( %stat );
exit;


sub verify_date {

  my ( @date ) = @_;

  for ( @date ) {

    next unless $_;
    $_ = OMP::DateTools->parse_date( $_ ) or next;
    $_ = $_->ymd( '' );
  }

  return @date;
}

sub generate_stat {

  my ( $date ) = @_;

  my $rep = OMP::NightRep->new( 'date' => $date, 'telescope' => $TELESCOPE );

  my $group = $rep->obs() or return;

  my ( %stat, @scuba2, %obs_time );
  for my $obs ( $group->obs() )
  {
    my $inst = $obs->instrument() or return;

    if ( $SCUBA2 eq uc $inst ) {

      push @scuba2, $obs->projectid();

      $obs_time{ $date } or $obs_time{ $date } = {};
      save_obs_time( $obs_time{ $date }, $obs->startobs(), $obs->endobs() );
    }
  }
  if ( scalar @scuba2 ) {

    my %acct = $rep->accounting();
    show_warnings( \%acct );

    $stat{'inst'}  = get_inst_proj_time( \%acct, @scuba2 );
    $stat{'fault'} = get_fault_time( $rep->faults(), @scuba2 );

    $stat{'start-end'} = { %obs_time };
  }

  return %stat;
}

sub save_obs_time {

  my ( $hash, $start, $end ) = @_;

  my $old_start = $hash->{'start'};
  my $old_end   = $hash->{'end'};

  $hash->{'start'} = $start
    if ! defined $old_start
    || ( defined $start && $start < $old_start );

  $hash->{'end'} = $end
    if ! defined $old_end
    || ( defined $end && $end > $old_end );

  return;
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
    $time{ $save } += extract_time( $acct->{ $proj } );
  }

  my @cal = grep { /CAL/ } keys %{ $acct };
  $time{'CAL'} += extract_time( $acct->{ $_ } ) for @cal;

  # 1 microsecond.
  my $min_diff = 1e-6;

  my $s2_time    = $time{ $SCUBA2 } || 0.0;
  my $other_time = $time{ $OTHER_INST } || 0.0;
  my $inst_total = $s2_time + $other_time;
  if ( $inst_total > $min_diff ) {

    $time{ $SCUBA2_CAL } = ( $time{'CAL'} * $s2_time ) / $inst_total ;
  }
  # Convert to hours.
  for my $key ( keys %time ) {

    $time{ $key } = sprintf '%0.2f', $time{ $key }/3600;
  }
  return \%time;
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

sub sum_hashref_time {

  my ( $hash ) = @_;

  my $s = 0.0;
  for my $k ( keys %{ $hash } ) {

    $s += $hash->{ $k };
  }
  return $s;
}

sub sum_time {

  my ( $list ) = @_;

  my $s = 0.0;
  for my $k ( @{ $list } ) {

    $s += $k;
  }
  return $s;
}



sub extract_time {

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

sub print_stat {

  my ( %stat ) = @_;

  unless ( scalar keys %stat ) {

    print "No data found.\n";
    return;
  }

  my @time_name = ( 'SCUBA-2 Time', 'CAL Time', 'Fault Loss', 'TOTAL' );
  my @col_name = ( 'Date   ', @time_name, 'TSS' );

  my $format = make_col_format( \@time_name, \@col_name );

#epl( $format , \@col_name ) ; die;

  my $header = sprintf $format, @col_name;
  print $header;

  my %tss_sum;
  my ( $s2_sum, $s2_cal_sum, $fault_sum, $row_sum );

  for my $date ( sort keys %stat ) {

    my @time =
      map { defined $_ ? $_ : 0.0 }
      map { $stat{ $date }->{ $_ } } ( $SCUBA2, $SCUBA2_CAL, 'FAULTS' );

    my @tss_list;
    @tss_list = @{ $stat{ $date }->{'TSS'} }
      if exists $stat{ $date }->{'TSS'};

    $s2_sum     += $time[0];
    $s2_cal_sum += $time[1];
    $fault_sum  += $time[2];

    my $row;
    $row     += $_ for @time;
    $row_sum += $row;

    for my $tss ( @tss_list ) {

      $tss_sum{ $tss } += $row;
    }

    printf $format,
      $date,
      map( sprintf( '%0.2f', $_ ), @time, $row ),
      join ' ', @tss_list
      ;
  }

  print +( '-' ) x length $header, "\n";
  printf $format,
    '',
    ( map sprintf( '%0.2f', $_ ),
            $s2_sum,
            $s2_cal_sum,
            $fault_sum,
            $row_sum,
    ),
    ''
    ;

  my $tss_sum_format = "  %s  %0.2f\n";

  print "\n";
  for my $tss ( sort keys %tss_sum ) {

    printf $tss_sum_format, $tss, $tss_sum{ $tss };
  }

  return;
}

sub make_col_format {

  my ( $time_name, $col_name ) = @_;

  my %col_format;

  # End columns.
  for my $name ( @{ $col_name } ) {

    if ( $name =~ /Date/ ) {

      $col_format{ $name } = '%8s';
    }
    elsif ( $name eq 'TSS' ) {

      $col_format{ $name } = '%s';
    }
  }
  # Time format.
  for my $name ( @{ $time_name } ) {

    my $max = max ( length $name, 6 );
    $col_format{ $name } = '%' . $max . 's';
  }

  return join( '  ', @col_format{ @{ $col_name } } ) . "\n";
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
