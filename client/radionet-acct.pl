#!/local/perl/bin/perl

use warnings;
use strict;
use Data::Dumper;

use Carp qw[ croak ];
use Getopt::Long qw/ :config gnu_compat no_ignore_case /;
use Pod::Usage;

BEGIN {
  use FindBin;
  use constant OMPLIB => "$FindBin::RealBin/..";
  use lib OMPLIB;

  $ENV{'OMP_DIR'} = OMPLIB unless exists $ENV{'OMP_DIR'};
}

use OMP::Constants qw/ :logging /;
use OMP::DateTools;
use OMP::General;
use OMP::DBbackend;
use OMP::FaultServer;

use Time::Piece;

my %default_opt =
  ( 'projects'  => [],
    'semesters' => [],
  );
my %opt = process_options( %default_opt );
#  This is "radionet*pl", so telescope is fixed.
$opt{'telescope'} = 'JCMT';

my $db = OMP::DBbackend->new();
my $dbh = $db->handle();


for my $sm ( @{ $opt{'semesters'} } ) {

  my ( $start, $end ) = dates_from_semester( $sm, $opt{'telescope'} );

  my $times = get_sci_time_by_sql( $dbh, \%opt, $start, $end );

  save_fault_time( $times, $start, $end );

  show_formatted( $times );

}

exit;

sub extract_date {

  my $date_re = qr{^(\d{4}-\d\d-\d\d)};

  return ( $_[0] =~ $date_re )[0];
}

sub show_formatted {

  my ( $times ) = @_;

  my $sum_length = 10;

  my $header =
    sprintf "%-10s  %-10s  %${sum_length}s  %15s  %17s  %${sum_length}s\n",
      'Date',
      'Project',
      'Spent (h)',
      'CAL Portion (h)',
      'Lost to Fault (h)',
      'Total (h)'
      ;

  my $footer_shift = length $header;

  my $rec_format =
    "%10s  %-10s  %${sum_length}.2f  %15.2f  %17.2f  %${sum_length}.2f\n";

  print $header;

  my $sum = 0;
  for my $date ( sort keys %{ $times } ) {

    my $list = $times->{ $date };
    add_cal_time( $list );

    for my $proj ( sort keys %{ $list } ) {

      next if $proj =~ /cal$/i;

      my $cur = $list->{ $proj };

      my ( $spent, $cal, $lost ) =
        map
        { $cur->{ $_ } ? $cur->{ $_ } : 0 }
        (qw[ timespent cal-portion fault-lost-time ])
        ;

      # Convert second to hour.
      $_ = $_ / 3600 for ( $spent, $cal );

      my $proj_sum = $spent + $cal;

      $sum += $proj_sum;

      printf $rec_format,
        extract_date( $date ),
        $proj,
        $spent,
        $cal,
        $lost,
        $proj_sum
        ;
    }
  }

  my $sum_label = 'TOTAL (h)';

  $footer_shift -= ( $sum_length + 3 );

  printf "%${footer_shift}s: %${sum_length}.2f\n",
    $sum_label,
    $sum
    ;

  return;
}

sub add_cal_time {

  my ( $times ) = @_;

  my $cal = 0;
  my $proj_sum = 0;

  my $cal_re = qr{cal$}i;

  for my $proj ( keys %{ $times } ) {

    my $time = $times->{ $proj }{'timespent'};

    if ( $proj =~ $cal_re ) {

      $cal += $time;
      next;
    }

    $proj_sum  += $time;
  }

  for my $proj ( keys %{ $times } ) {

    next if $proj =~ $cal_re;

    my $cur = $times->{ $proj };

    $cur->{'cal-portion'} =
      $cal && $proj_sum
      ? $cur->{'timespent'} * $cal / $proj_sum
      : 0
      ;
  }

  return;
}

sub save_fault_time {

  my ( $times, $start, $end ) = @_;

  return
    unless $times
      and  ref $times
      and  keys %{ $times };

  my $query = <<'_FAULT_QUERY_';
    <FaultQuery>
      <isfault> 1 </isfault>
      <timelost><min> 0.001 </min></timelost>
      <date>
        <min> %s </min>
        <max> %s </max>
      </date>
    </FaultQuery>
_FAULT_QUERY_

  $query = sprintf $query, map { extract_date( $_ ) } ( $start, $end );

  my $faults = OMP::FaultServer->queryFaults( $query, 'objects' );

  for my $f ( @{ $faults } ) {

    next
      # Saving only for JCMT.
      if 'ukirt' eq lc $f->{'Category'};

    my ( $f_date, $lost_time, $f_projs ) =
      map { $f->{ $_ } } (qw[ FaultDate TimeLost Projects ] );

    next
      unless $f_date
        and  $lost_time
        and  $f_projs
        and  ref $f_projs
        and  scalar @{ $f_projs };

    # Ignore actual fault hour, minute, second to be able to match with dates in
    # omptimeacct table.
    my $date_plain = $f_date->strftime( '%Y-%m-%dT00:00:00' );

    next unless exists $times->{ $date_plain };

    for my $proj ( keys %{ $times->{ $date_plain } } ) {

      for my $fp ( @{ $f_projs } ) {

        next unless lc $fp eq lc $proj;

        $times->{ $date_plain }{ $proj }{'fault-lost-time'} += $lost_time;
      }
    }
  }

  return;
}

sub get_sci_time_by_sql {

  my ( $dbh, $opt, $start, $end ) = @_;

  my $sql = <<'_SQL_';
    SELECT t.projectid, t.timespent,
           CONVERT( VARCHAR, t.date, 23 ) AS date
    FROM omptimeacct t, ompproj p
    WHERE t.projectid = p.projectid
      AND p.telescope = ?
      AND t.projectid NOT IN ( %s )
      -- Choose by date.
      AND ( %%s )
    ORDER BY t.date, t.projectid
_SQL_

  #  Projects to skip.
  my @skip = map { uc qq[JCMT$_] } ( 'weather', 'other' );

  $sql = sprintf $sql, join ', ', ('?') x scalar @skip;

  my @bind = ( $opt{'telescope'}, @skip );

  # Semester dates.
  push @bind, ( $start, $end );
  my $where = sql_between( 't.date' );

  if ( $opt->{'projects'}
        && ref $opt->{'projects'}
        && scalar @{ $opt->{'projects'} }
      ) {

    push @bind, @{ $opt->{'projects'} };

    $where = sprintf " %s AND %s ",
      $where,
      sql_in( 't.projectid', $opt->{'projects'} )
      ;
  }

  $sql = sprintf $sql, $where;

  my $times =
    # Used *hashref() instead of *arrayref() to fill the results with lost time
    # due to faults without creating another data structure.
    $dbh->selectall_hashref( $sql, ['date' , 'projectid' ], undef, @bind )
      or die log_db_error( $dbh->errstr );

  return $times;
}

sub sql_in {

  my ( $col, $in, $not ) = @_;

  return
    unless $col
    && $in && ref $in && scalar @{ $in };

  my $holder = join ', ' , ( '?' ) x scalar @{ $in };

  return $col . ( $not ? ' NOT ' : ' ' ) . qq[ IN ( $holder ) ];
}

sub sql_between {

  my ( $col ) = @_;

  return unless $col;

  return sprintf ' %s BETWEEN %s AND %s ', $col, ( '?' ) x 2;
}

#  Process options.
sub process_options {

  my ( %opt, @proj ) = @_;

  my ( $help );
  GetOptions(
    'h|help|man' => \$help,
    'proj=s@'    => \@proj,
  )
    or pod2usage( '-exitval' => 2, '-verbose' => 1,);

  pod2usage( '-exitval' => 1, '-verbose' => 2 ) if $help;

  $opt{'projects'} = [ @proj ]
    if scalar @proj;

  pod2usage( '-exitval' => 2, '-verbose' => 99, '-sections' => 'SYNOPSIS',
              '-msg' => 'No semester was given.'
            )
    if ! scalar @ARGV;


  $opt{'semesters'} = [ map { $_ ? uc $_ : () } @ARGV ];

  return %opt;
}

sub dates_from_semester {

  my ( $sem, $tel ) = @_;

  croak "No semester or telescope were given to convert to a date range.\n"
    unless $sem
        && $tel ;

  my %range;

  return
    map
    { $_->ymd }
    OMP::DateTools->semester_boundary( 'tel' => $tel,
                                      'semester' => $sem
                                    );
}

sub is_non_empty_aref { return $_[0] && ref $_[0] && scalar @{ $_[0] }; }

# Returns ...
#   - the first argument given (error string)
#
# ... given ...
#   - a list of strings to be logged.
sub log_db_error {

  my $err = shift;
  OMP::General->log_message( join( ': ', $0, $err, @_ ), OMP__LOG_ERROR );

  return $err;
}

=pod

=head1 NAME

radionet-acct.pl - Show time statistics for JCMT projects for a semester.

=head1 SYNOPSIS

To get statistics for a semester ...

  radionet-acct.pl  10a

To get statistics for projects in a semester ...

  radionet-acct.pl -proj M09BI143 -proj M10AN04  10a

=head1 DESCRIPTION

Given a semester, this program prints the time spent and lost statistics due to
faults for JCMT projects.

Printed output is sorted by date, then by project id. For example, for semester
10a, output would be ...

  Date        Project      Spent (h)  CAL Portion (h)  Lost to Fault (h)   Total (h)
  2010-02-02  M09AC09           2.50             0.00               0.00        2.50
  2010-02-02  M09BEC04          0.00             0.00               0.00        0.00
  2010-02-02  M10AEC04          0.55             0.00               0.00        0.55
  . . .
  2010-07-30  M10BC04           2.45             0.08               0.00        2.53
  2010-07-31  M10BC04           4.10             1.27               0.15        5.37
  . . .
                                                               TOTAL (h):    1914.20


=head2 OPTIONS

=over 2

=item B<-help> | B<-man>

Show the full help message.

=item B<-proj> projectid

Specify a project to be shown in a given semester.

Use multiple times to select multiple projects.

=back

=head1 AUTHORS

Anubhav E<lt>a.agarwal@jach.hawaii.eduE<gt>

=cut

