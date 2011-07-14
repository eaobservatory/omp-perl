#!/local/perl/bin/perl

use warnings;
use strict;
use Data::Dumper;

use Getopt::Long qw/ :config gnu_compat no_ignore_case /;
use Pod::Usage;
use List::Util qw/ first /;
use Scalar::Util qw/ blessed openhandle /;

BEGIN {
  use FindBin;
  use constant OMPLIB => "$FindBin::RealBin/..";
  use lib OMPLIB;

  $ENV{'OMP_DIR'} = OMPLIB unless exists $ENV{'OMP_DIR'};
}

use OMP::Constants qw/ :logging /;
use OMP::DateTools;
use OMP::General;
use OMP::BaseDB;
use OMP::DBbackend;

my %default_opt =
  ( 'header'   => undef,
    'projects' => [],
    # Date-time ranges (array reference of hash references, with 'min' & 'max'
    # as date-time keys).
    'date-range' => [],
    'telescope'  => undef
  );
my %opt = process_options( %default_opt );

my $db =
  OMP::BaseDB->new( 'DB' => OMP::DBbackend->new )->_dbhandle
    or die "Failed to acquire a database handle.\n";

my $query = make_project_query_2( @opt{qw/ projects date-range /} );
OMP::General->log_message( "$0: Query: $query", OMP__LOG_INFO );

my $st = $db->prepare( $query ) or die log_db_error( $db->errstr );

$st->execute or die log_db_error( $db->errstr );

{
  my $print_head;
  while ( my @rec = $st->fetchrow_array ) {

    # Print header (once, when requested, and) if there are any
    # results, so it is here in loop.
    !$print_head && $opt{'header'} and $print_head++, print_header();

    print_csv( @rec );
  }
}

exit;

BEGIN {

  # The column names (and possible method names to be called, in order, on given
  # C<OMP::TimeAcctQuery> object).
  my @header = qw{ projectid timespent date confirmed } ;

  #  Prints CSV given a list of elements of a record.
  sub print_csv {

    my ( @rec ) = @_;

    # Special handling of date.
    for ( $rec[2] ) {

      $_ = OMP::DateTools->parse_date( $_ ) || '';
      $_ = $_->ymd if blessed( $_ ) =~ m/^Time::Piece\b/;
    }

    return really_print_csv( @rec );
  }

  # Prints the header given a flag (if & how many times to print) and list of
  # header strings.
  sub print_header { return really_print_header( @header ); }
}

sub really_print_header {

  my @header = @_;

  return
    # Header in lower case after normalizing any camelCase ones.
    really_print_csv( map { s/([a-z])([A-Z])/$1_$2/; lc $_ } @header );
}

# Simple minded-ly prints CSV (see I<Text::CSV> for robustness).
sub really_print_csv {

  printf "%s\n", join ',', @_; return;
}

sub make_project_query_2 {

  my ( $projs, $ranges ) = @_;

  unless ( scalar @{ $projs } || scalar @{ $ranges } ) {

    warn "Neither project ids given, nor were date ranges with telescope.";
    return;
  }

  my $sql = '';
  if ( scalar @{ $ranges } ) {

    $sql =
      join "\nOR ",
        sql_between( 'date', [ map { @{ $_ }{qw/ min max /} } @{ $ranges } ] ) ;
  }

  $sql = join "\nAND ", grep { $_ } sql_in( 'projectid', $projs ), $sql ;

  $sql or
    die sprintf <<"NO_SQL", Dumper( $projs, $ranges );
Query statement could not be generated for projects & semesters: (%s).
NO_SQL

  return <<"_SQL_";
    SELECT projectid, timespent, date, confirmed
    FROM omptimeacct
    WHERE $sql
    ORDER BY projectid, date
_SQL_
}

sub sql_in {

  my ( $col, $in , $no_quote ) = @_;

  return unless $col && scalar @{ $in };

  return
    "$col IN ( "
    . join( ' , ', map {  ( $no_quote ? $_ : "'$_'" ) } @{ $in } )
    . ' )'
    ;
}

sub sql_between {

  my ( $col, $in , $no_quote ) = @_;

  return unless $in && ref $in;

  my $size = scalar @{ $in };
  return unless $size && 0 == $size % 2;

  my @out;
  for ( my $i = 0; $i < $size -1 ; $i += 2 ) {

    push @out,
      "$col BETWEEN "
      . join ' AND ',
          map {  $no_quote ? $_ : "'$_'" } @{ $in }[ $i, $i + 1 ]
          ;
  }

  return @out;
}

#  Process options.
sub process_options {

  my ( %opt ) = @_;

  my ( $help, @file, @sem );
  GetOptions(
    'h|help|man' => \$help,
    'file=s'     => \@file,
    'header|'    => \$opt{'header'},
    'H|noheader' => sub{ $opt{'header'} = 0 },
    'semester=s'  => \@sem,
    'telescope=s' => \$opt{'telescope'},
  )
    # As of Pod::Usage 1.30, C<'-sections' => 'OPTIONS', '-verbose' => 99> does
    # not output only the OPTIONS part.  Also note that in pod, key is listed
    # '-section' but in code '-sections' is actually used.
    or pod2usage( '-exitval' => 2, '-verbose' => 1,);

  pod2usage( '-exitval' => 1, '-verbose' => 2 ) if $help;

  # Print header at least once in the beginning by default.
  $opt{'header'}++ unless defined $opt{'header'};

  if ( $opt{'telescope'} ) {

    for  my $sem ( @sem ) {

      my %range;
      @range{qw/ min max /} =
        map { $_->ymd }
          OMP::General
          ->semester_boundary( 'tel' => $opt{'telescope'}, 'semester' => $sem )
          ;

      push @{ $opt{'date-range'} }, \%range;
    }
  }

  $opt{'projects'} =
    [ map { $_ ? uc $_ : () } @ARGV, get_projects( @file ) ] ;

  pod2usage( '-exitval' => 2, '-verbose' => 99, '-sections' => 'SYNOPSIS',
              '-msg' => 'Neither project ids nor semester with telescope were given.'
            )
    if ! ( $opt{'telescope'} || scalar @sem )
    && ! scalar @{ $opt{'projects'} }
    ;

  return %opt;
}

# Returns ...
#   - project ids
#
# ... read from ...
#   - array reference of file names or from standard input.
sub get_projects {

  my ( @file ) = @_;

  return unless scalar @file;

  push @file, '-'
    if -p *STDIN && ! first { $_ eq '-' } @file;

  my @proj;
  for my $file ( @file ) {

    my $fh = ( openhandle $file ? $file : open_file( $file ) ) or next;
    while ( my $line = <$fh> ) {

      next if $line =~ m/^\s*$/ or $line =~ m/^\s*#/;

      for ( $line ) {
        s/^\s+//;
        s/\s+$//;
      }

      push @proj, map { uc $_ } split /\s+/, $line;
    }
  }
  return @proj;
}

# Returns ...
#   - file handle
#
# ... given ...
#   - file name.
sub open_file {

  my ( $file ) = @_;

  my $fh;
  my $err = "Skipped '$file':";

  if ( $file eq '-' ) {

    open $fh, '<-' or do { warn "$err $!\n"; return; };
  }
  else {

    open $fh, '<', $file or do { warn "$err $!\n"; return; };
  }

  return $fh;
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

omp-time-acct.pl - Show time spent on a project as CSV

=head1 SYNOPSIS

  Project ids provided as arguments (lists all the time spent on given
  projects) ...

    omp-time-acct.pl project-id [ project-id ... ]


  ... or, in a file ...

    omp-time-acct.pl -f project-id-file


  ... or, on standard input ...

    echo project-id | omp-time-acct.pl


  Telescope and semester provided (lists all the projects in semester
  08A, where date range of the semester is as appropriate for JCMT)
  ...

    omp-time-acct.pl -semester 08A -telescope jcmt


  Project id, semester and telescope are provided (lists time spent on
  given project in the semester 08A as appropriate for UKIRT) ...

    omp-time-acct.pl -semester 08A -telescope ukirt project-id


=head1 DESCRIPTION

Given a list of project ids, this program generates comma separated
values of time spent on each date for each given project id.  The
output format is ...

  project-id,time-spent-in-seconds,date,confirmed


Project ids can be specified as arguments to the program, given in a
file, or provided on standard input.

If semester is provided and also specify the telescope.

Semester can be given with or without a project id.  If a project id
is not given, then the listing would have all the projects in a given
semester for any telescope.  Otherwise, listing would have accounting
for given projects in a given semester.

=head2 OPTIONS

=over 2

=item B<-help> | B<-man>

Show the full help message.

=item B<-file> file-containing-project-ids

Specify a file name which has white space separated project ids.
This option can be specified multiple times.

File name of I<-> specifies to read from standard input.

=item B<-header>

Specify if to print a header (default).

=item B<-noheader> | B<-H>

Turn off header printing.

=item B<-semester> <semester_1, [semester_2, ...]>

Specify a semester.

It can be used multiple times to specify multiple semesters.

The I<telescope> option would also needed to be specified if a
semester is given.

=item B<-telescope> | B<-tel> <jcmt | ukirt>

Specify a telescope to be used with all the given semesters.  It is
I<required> if a I<-semester> option was specified.

I<This is used only to find a date range from given semester as
applicable for the given telescope.>  In other words, this option is
not used to filter out projects related to one telescope (use project
ids).

=back

=head1 BUGS

Not known yet.

=head1 AUTHORS

Anubhav E<lt>a.agarwal@jach.hawaii.eduE<gt>

=cut

