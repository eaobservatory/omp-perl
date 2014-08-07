#!/local/perl/bin/perl

=head1 NAME

scuba2-acct - Generate SCUBA-2 usage statistics

=head1 SYNOPSIS

Show usage only for every date in the schedule ...

  scuba2-acct -tss schedule-file

Show usage only for Jan 13 2012 ...

  scuba2-acct -tss schedule-file  20120113

Show usage for Jan 13 2012 to Jan 23 2012 ...

  scuba2-acct -tss schedule-file  20120113 20120123


=head1 DESCRIPTION

Calculate usage statistics for the supplied start date and optional
end date.  Calibrations are assigned to the project in proportion to
the amount of science time spent relative to other projects.

Fault time is charged if a fault on the night is associated with a
SCUBA-2 project.

If no date is given, listing for all the dates in the schedule file
will be printed. Else, a date I<range> is used, generated from the
earliest and latest dates in given dates.

Currently assumes JCMT.

=head1 OPTIONS

=over 2

=item B<-help>

A help message.

=item B<-man>

This manual page.

=item B<-tss>

It is B<required>.

Specify the schedule file in the following format ...

  <4 digit year>-<2 digit month>
  <TSS id>  <2 digit date>

A exmaple would be ...

  2011-10
  ABC      02
  PQR      03
  ABC/PQR  04
  XYZ/UVW  05
  ...


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
use List::Util ( 'min', 'max' );
use List::MoreUtils qw[ any ];

use DateTime;
use DateTime::Duration;
use DateTime::Format::ISO8601;

#use Time::Piece ( 'localtime' );
#use Time::Seconds 'ONE_DAY';

my $TELESCOPE  = 'JCMT';
my $SCUBA2     = 'SCUBA-2';
my $SCUBA2_CAL = 'SCUBA-2-CAL';
my $OTHER_INST = 'Other Instruments';
my @TSS_TYPE   = qw[ regular daytime ];

my $UTC_TZ = 'UTC';
my $HST_TZ = 'Pacific/Honolulu';
my $HST_OFFSET = DateTime->now( 'time_zone' => $HST_TZ )->offset();

#  "It seems reasonable for you to define daytime as anything after 9:30am and
#  before 2pm and after 2pm and before 5pm Note that in UT-land a
#  daytime TSS can be in two UT dates and [...] they will all probably start
#  before 2pm on the UT date listed and continue afterwards [...]" -- Tim,
#  <CA+G92Rfe547Yte4j6fA-FGa398=+JcRzFyC-ZNCkiMEvieY5cQ@mail.gmail.com>.
#
#  Day start time has been changed to 7.30a.
#
# Schedule is in HST time zone (-1000).

#  7:30:00a HST.
my @DAYTIME_START_HST = qw( 07 30 00 );
my %DAYTIME_START_HST = ( 'hour' => 7, 'minute' => 30, 'second' => 0 );
my %DAYTIME_HST =
  ( # 7.30a to < 2p HST;
    'prev' => [ sprintf( '%02d:%02d:%02d', @DAYTIME_START_HST ), '14:00:00' ],
    # 2p    to < 5p HST.
    'next' => [ '14:00:00',  '17:00:00' ]
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

$schedule_file
  or pod2usage( '-exitval' => 1, '=verbose' => 10,
                '-message' => "TSS schedule file is not given.\n"
              );

die "TSS schedule file, $schedule_file, is unreadable\n"
  unless -r $schedule_file;

my %tss_sched = OMP::SCUBA2Acct::make_schedule( $schedule_file )
  or die "Could not parse schedule file.\n";

my @filter = expand_date_range( verify_date( @ARGV ) );
@filter = sort keys %tss_sched
  unless scalar @filter;


sub _time_string {

  my ( $list ) = @_;

  return [ map { [ map { $_ . '' } @$_ ] } @{ $list } ];
}

my %stat;
for my $date ( @filter ) {

  my %data = generate_stat( $date ) or next;
  $stat{ $date } = $data{'inst'};
  $stat{ $date }->{'FAULTS'} = $data{'fault'};

  for my $type ( @TSS_TYPE ) {

    my $val = $tss_sched{ $date }->{ $type };

    $stat{ $date }->{ $type } = $val
      if exists $tss_sched{ $date }
      && $val
      && scalar @{ $val };
  }

  $stat{ $date }->{'start-end'} = $data{'start-end'};
}
print_stat( %stat );
exit;


sub verify_date {

  my ( @date ) = @_;

  for my $d ( @date ) {

    next unless $d;

   # When a date cannot be parsed, the given parameter is becomes undef. This
   # needs to be changed.
    my $tmp = $d;
    $d = OMP::DateTools->parse_date( $d )
      or die "Could not parse date: $tmp.\n";

    $d = $d->ymd( '' );
  }

  return @date;
}

sub expand_date_range {

  my ( @date ) = @_;

  return unless @date;

  my $min = min @date;
  my $max = max @date;

  my @out;
  while ( $min <= $max ) {

    push @out, $min;

    my $t = make_time( $min, '00:00:00', $UTC_TZ );
    $t->add( days => 1 );
    $min = $t->ymd( '' );
  }

  return @out;
}

sub generate_stat {

  my ( $date ) = @_;

  my $rep = OMP::NightRep->new( 'date' => $date, 'telescope' => $TELESCOPE );

  my $group = $rep->obs() or return;

  my ( %stat, @scuba2, %obs_time );
  my $i = 0;
  for my $obs ( $group->obs() )
  {
    my $inst = $obs->instrument() or return;

    if ( $SCUBA2 eq uc $inst ) {

      push @scuba2, $obs->projectid();

      $stat{'start-end'}->[ $i++ ] = [ $obs->startobs(), $obs->endobs() ];
    }
  }
  if ( scalar @scuba2 ) {

    my %acct = $rep->accounting();
    show_warnings( \%acct );

    $stat{'inst'}  = get_inst_proj_time( \%acct, @scuba2 );
    $stat{'fault'} = get_fault_time( $rep->faults() );
  }

  if ( $stat{'start-end'} )
  {
    my @period =
      sort
      { $a->[0] <=> $b->[0] || $a->[1] <=> $b->[1] }
      @{ $stat{'start-end'} }
      ;
    $stat{'start-end'} = [ @period ];
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

  my ( $group ) = @_;

  return unless $group;

  my %time;
  for my $fault ( $group->faults() ) {

    next unless $fault->isSCUBA2Fault();

    my $date = $fault->date();
    if ( $date ) {

      # Returns in hours.
      $time{ $fault->date() } += $fault->timelost();
      next;
    }

    warn "Could not find a date to add time loss for fault:\n", "$fault", "\n";
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

sub last_obs_end_time {

  my ( $times ) = @_;

  my $last = ( sort
                { $b->[1] <=> $a->[1]
                  ||
                  $b->[0] <=> $a->[0]
                }
                @{ $times }
              )[0];

  return max( @{ $last } );
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

  my @time_name = ( 'SCUBA-2 Time', 'CAL Time', 'Fault Loss', 'Regular', 'Daytime', 'TOTAL' );
  my @col_name  = ( 'Date   ', @time_name, map qq[TSS:$_], @TSS_TYPE );

  my $format = make_col_format( \@time_name, \@col_name );

  my $header = sprintf $format, @col_name;
  print $header;

  my %tss_sum;
  my ( $s2_sum, $s2_cal_sum, $fault_sum, $reg_sum, $day_sum, $row_sum );

  for my $date ( sort keys %stat ) {

    my @time =
      map { defined $_ ? $_ : 0.0 }
      map { $stat{ $date }->{ $_ } } ( $SCUBA2, $SCUBA2_CAL, 'FAULTS' );


    my ( @tss_reg, @tss_day );
    exists $stat{ $date }->{'regular'}  and @tss_reg = @{ $stat{ $date }->{'regular'} };
    exists $stat{ $date }->{'daytime'} and @tss_day  = @{ $stat{ $date }->{'daytime'} };

    $s2_sum     += $time[0];
    $s2_cal_sum += $time[1];
    $fault_sum  += $time[2];

    my $row;
    $row     += $_ for @time;

    my $day_tss = 0.0;
    my $day_end = last_obs_end_time( $stat{ $date }->{'start-end'} );
    if ( defined $day_end ) {

      my $end   = TimePiece_to_DateTime( $day_end, $UTC_TZ );
      my $start = DateTime->new( %DAYTIME_START_HST, 'time_zone' => $HST_TZ,
                                  map { $_ => $end->$_() } qw[ year month day ]
                                );
      $start->set_time_zone( $UTC_TZ );

      # In case there is no daytime observing.
      $start < $end and $day_tss  = diff_time( $start, $end );
    }

    $row     += $day_tss;
    $day_sum += $day_tss;

    my $reg_tss = $row - $day_tss;
    $reg_sum += $reg_tss;

    for my $tss ( @tss_day ) {

      $tss_sum{ $tss }->{'daytime'} += $day_tss;
    }
    for my $tss ( @tss_reg ) {

      $tss_sum{ $tss }->{'regular'} += $reg_tss;
    }

    $row_sum += $row;

    printf $format,
      $date,
      map( sprintf( '%0.2f', $_ ), @time, $reg_tss, $day_tss, $row ),
      join( ' ', @tss_reg ) || '-' ,
      join( ' ', @tss_day  ) || '-'
      ;
  }

  print +( '-' ) x length $header, "\n";
  printf $format,
    '',
    ( map sprintf( '%0.2f', $_ ),
            $s2_sum,
            $s2_cal_sum,
            $fault_sum,
            $reg_sum,
            $day_sum,
            $row_sum,
    ),
    '',
    ''
    ;

  return print_tss_stat( $stat{'start-end'}, \%tss_sum );
}

sub print_tss_stat {

  my ( $obs_time, $tss_sum ) = @_;

  return unless keys %{ $tss_sum };

  my $tss_sum_format = "  %5s  %8s  %8s\n";
  my $div_size = 2 * 3 + 5 + 8 * 2;

  print "\n";
  printf $tss_sum_format, qw[ TSS Daytime Regular ];
  print  join '', ('-') x $div_size, "\n";

  for my $tss ( sort keys %{ $tss_sum } ) {

    my ( $day, $reg ) = map { $tss_sum->{ $tss }{ $_ } || 0 } qw[ daytime regular ];

    printf $tss_sum_format,
      $tss,
      map { sprintf '%0.2f', $_ } $day ? ( $day, 0 ) : ( 0 , $reg )
  }
  return;
}

sub day_time {

  my ( $time ) = @_;

  return
    unless $time
    && ref $time
    && scalar @{ $time };

  my @prev = @{ $DAYTIME_HST{'prev'} };
  my @next = @{ $DAYTIME_HST{'next'} };

  my ( %time );
  for my $pair( @{ $time } ) {

    my ( $start, $end ) = @{ $pair }[0,1];

    # Time::Piece objects come via OMP::Info::Obs.
    die "Need obs start and end times as Time::Piece objects to find daytime hours.\n"
      unless is_TimePiece( $start )
          && is_TimePiece( $end );

    my ( $start_ut_string, $end_ut_string ) =
      map { $_->ymd( '' ) } ( $start, $end );

    my ( $start_hst, $end_hst ) = to_HST( $start, $end );

    my ( $start_date, $end_date ) = map { $_->ymd( '' ) } ( $start_hst, $end_hst );

    # Prime, in case no daytime duration is available.
    $time{ $start_ut_string } += 0.0;
    $time{ $end_ut_string }   += 0.0;

    my ( $at_730, undef, $at_1400, $at_1700 ) =
      map { make_time( $start_hst->ymd( '' ), $_, $HST_TZ ) } ( @prev, @next );

    my ( $at_730_e, undef, $at_1400_e, $at_1700_e ) =
      map { make_time( $end_hst->ymd( '' ), $_, $HST_TZ ) } ( @prev, @next );

   # Before 7.30a or after 5p.
    next
      if $end_hst   <  $at_730_e
      || $start_hst >= $at_1700;

    # Latest time.
    my $alt_start = $start_hst < $at_730    ? $at_730  : $start_hst;

    # Earliest time.
    my $alt_end   = $end_hst   < $at_1700_e ? $end_hst : $at_1700_e;

    # Contained within same UT date:
    #    start >= 7.30a & end < 2p
    # OR start >= 2p    & end < 5p.
    if ( $end_hst < $at_1400_e || $start_hst >= $at_1400 ) {

      $time{ $start_ut_string } += diff_time( $alt_start, $alt_end );
      next;
    }

    # Split over two UT dates:
    #  7.30a <= start < 2p, end > 2p.
    $time{ $start_ut_string } += diff_time( $alt_start, $at_1400 );
    $time{ $end_ut_string }   += diff_time( $at_1400, $alt_end );
  }

  return %time;
}

sub to_HST {

  my ( @time ) = @_;

  my @out;
  for my $t ( @time ) {

    my $alt =
      is_DateTime( $t )
      ? $t
      : is_TimePiece( $t )
        ? TimePiece_to_DateTime( $t )
        : undef
        ;

    $alt->set_time_zone( $HST_TZ )
      unless $HST_OFFSET == $alt->offset();

    push @out,  $alt;
  }

  return @out;
}

sub diff_time {

  my ( $t1, $t2 ) = @_;

  # Don't care for negative values.
  die "Unexpected values given: t1: $t1, t2: $t2\n"
    if $t1 > $t2;

  my $diff = $t2->subtract_datetime_absolute( $t1 );
  return $diff->in_units( 'seconds' ) / 3600;

}

sub is_TimePiece { return _is_type( $_[0], 'Time::Piece' ); }
sub is_DateTime  { return _is_type( $_[0], 'DateTime' ); }
sub _is_type     { return $_[0] && ref $_[0] && $_[0]->isa( $_[1] ); }

sub TimePiece_to_DateTime {

  my ( $tp, $tz ) = @_;

  return
    DateTime->from_epoch( 'epoch'     => $tp->epoch(),
                          'time_zone' => defined $tz ? $tz : $UTC_TZ
                        );
}

sub make_time {

  my ( $date, $time, $tz ) = @_;

  $tz = $UTC_TZ unless defined $tz;

  my $sep_re  = qr{[-.:/\ ]*}x;
  my $num2_re = qr{(\d{2})};
  my @date = ( $date =~ m{^(\d{4})  $sep_re $num2_re $sep_re $num2_re }x );
  my @time = ( $time =~ m{^$num2_re $sep_re $num2_re $sep_re $num2_re }x );
  my %dt;
  @dt{('year', 'month', 'day')}     = @date;
  @dt{('hour', 'minute', 'second')} = @time;

  return DateTime->new( %dt, 'time_zone' => $tz );
}

sub make_col_format {

  my ( $time_name, $col_name ) = @_;

  my %col_format;

  # End columns.
  for my $name ( @{ $col_name } ) {

    if ( $name =~ /Date/ ) {

      $col_format{ $name } = '%8s';
    }
  }
  # Time format.
  for my $name ( @{ $time_name } ) {

    my $max = max ( length $name, 6 );
    $col_format{ $name } = '%' . $max . 's';
  }
  # TSS types.
  $col_format{ qq[TSS:$_] } = '%11s' for @TSS_TYPE;

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
