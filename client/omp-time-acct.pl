#!/usr/local/bin/perl

use warnings;
use strict;

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

use OMP::General;
use OMP::DBbackend;
use OMP::TimeAcctDB;
use OMP::TimeAcctQuery;

my %default_opt =
  ( 'header' => undef,
    'divider' => undef,
    'file' => [],
    'timezone' => 'UTC',
    'start-date' => undef,
    'end-date' => undef,
    # Individual dates.
    'date' => []
  );

my %opt = process_options( %default_opt );

my @proj = get_projects( \%opt, @ARGV )
  or pod2usage( '-exitval' => 2, '-verbose' => 99, '-sections' => 'SYNOPSIS',
                '-msg' => 'No project ids were given.'
              );
my $last = $proj[-1];

my $db = OMP::TimeAcctDB->new( 'DB' => OMP::DBbackend->new );

for my $id ( @proj ) {

  print_header( $opt{'header'} );

  print_csv( $db->queryTimeSpent( make_query( $id ) ) );

  print "\n" if $opt{'divider'} && $id ne $last;
}

exit;

sub parse_date {

  my ( $date ) = @_;

  my $parsed;


  return $parsed;
}

BEGIN {

  # The method names to be called, in order, on given C<OMP::TimeAcctQuery>
  # object.
  my @header = qw{ projectid timespent date confirmed } ;

  #  Prints CSV given a list of C<OMP::TimeAcctQuery> objects.
  sub print_csv {

    my ( @acct ) = @_;

    for my $ac ( @acct ) {

      my @val = map { $ac->$_ } @header ;
      # Specail handling of date.
      for ( $val[2] ) {

        $_ = OMP::General->parse_date( $_ ) || '';
        $_ = $_->ymd if blessed( $_ ) =~ m/^Time::Piece\b/;
      }
      really_print_csv( @val );
    }
    return;
  }

  # Prints the header given a flag (if & how many times to print) and list of
  # header strings.
  sub print_header { return really_print_header( $_[0], @header ); }
}

{
  my $once;
  # Prints header as CSV given a flag and a list of header strings.  Flag
  # specifies if to print the header at all, only once, or every time.
  sub really_print_header {

    my $header_once = shift;

    return unless $header_once;
    return if $once && $header_once == 1;

    $once++;
    my @header = @_;
    return
      # Header in lower case after normalizing any camelCase ones.
      really_print_csv( map { s/([a-z])([A-Z])/$1_$2/; lc $_ } @header );
  }
}

# Simple mindedly prints CSV (see I<Text::CSV> for robustness).
sub really_print_csv {

  printf "%s\n", join ',', @_;
  return;
}

# Returns project id list given the options hash reference, and any additional
# project ids.
sub get_projects {

  my ( $opt, @proj ) = @_;

  my @file = @{ $opt->{'file'} };

  push @file, '-'
    if -p *STDIN && ! first { $_ eq '-' } @file;

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

#  Returns the file handle after opening the given file name.
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

# Returns the C<OMP::TimeAcctQuery> object given a project id.
sub make_query {

  my ( $proj ) = @_;

  my $root = 'TimeAcctQuery';
  my $id = 'projectid';
  return
    OMP::TimeAcctQuery->new( 'XML' => wrap( $root => wrap( $id => $proj ) ) );
}

# Returns a string of given a list of values wrapped in the given tag.
sub wrap {

  my ( $tag, @val ) = @_;

  return qq{<$tag>} . join( ' ' , @val ) . qq{</$tag>};
}

#  Process options.
sub process_options {

  my ( %opt ) = @_;

  my ( $help, @file );
  GetOptions(
    'h|help|man' => \$help,
    'file=s'     => \@file,
    'header+'    => \$opt{'header'},
    'H|noheader' => sub{ $opt{'header'} = 0 },
    'divider!'    => \$opt{'divider'},
    'date=s@'      => $opt{'date'},
    'start-date=s' => \$opt{'start-date'},
    'end-date=s'   => \$opt{'end-date'},
    'tz|timezone'  => \$opt{'timezone'},
  )
    # As of Pod::Usage 1.30, C<'-sections' => 'OPTIONS', '-verbose' => 99> does
    # not output only the OPTIONS part.  Also note that in pod, key is listed
    # '-section' but in code '-sections' is actually used.
    or pod2usage( '-exitval' => 2, '-verbose' => 1,);

  pod2usage( '-exitval' => 1, '-verbose' => 2 ) if $help;

  $opt{'file'} = [ @file ] if scalar @file;

  # Print header at least once in the beginning by default.
  $opt{'header'}++ unless defined $opt{'header'};

  die 'Date options have not been implemented yet.'
    if scalar
          map
          { my $v = $opt{ $_ };
            ( ref $v ? scalar @{ $v } : $v )
            ? undef
              : ()
          }
          qw/ date start-date end-date /;

  # If one date point for date range is given, other must be specified.
  pod2usage( '-msg' => 'Both dates must be specified for a date range.',
              '-exitval' => 2, '-verbose' => 1,
            )
    if $opt{'start-date'} && ! $opt{'end-date'}
    or ! $opt{'start-date'} && $opt{'end-date'}  ;

  return %opt;
}

=pod

=head1 NAME

omp-time-acct.pl - Show time spent on a project as CSV

=head1 SYNOPSIS

omp-time-acct.pl I<project-id> [ I<project-id> ... ]

omp-time-acct.pl -f I<file-containing-project-ids>

omp-time-acct.pl < I<file-containing-project-ids>

echo I<project-id> | omp-time-acct.pl

=head1 DESCRIPTION

Given a list of project ids, this program generates comma separated
values of time spent on each date for each given project id.  The
output format is ...

  project-id,time-spent-in-seconds,date,confirmed


Project ids can be specified as arguments to the program, given in a
file, or provided on standard input.

=head2 OPTIONS

=over 2

=item B<-help> | B<-man>

Show the full help message.

=item B<-date> I<yyyy.mm.dd.hh.mm.ss>

Specify a date in UTC time zone, not used for date range. (See
I<timezone> option to other time zone.)

It can be used mulitple times, with or without date range (see
I<start-date> and I<end-date> options).

A '/' or a '-' is also ok in place of '.', so is lack of any of the
three characters mentioned.  A date can be specified in one of
the following formats ...

=over 2

=item *

yyyy.mm.dd.hh.mm.ss

=item *

yyyy.mm.dd.hh.mm

=item *

yyyy.mm.dd

=back

=item B<-divider>

Print a blank line after output of each project id.  Default is not to
print the blank line.

=item B<-end-date> I<yyyy.mm.dd.hh.mm.ss>

Specify end date, inclusive, for the date range.

Both this option and I<start-date> must be given, when  providing a
date range.  The date range can be specified in addition to I<date>
option.  See I<date> option description on acceptable date formats.

=item B<-file> file-containing-project-ids

Specify a file name which has white space separated project ids.
This option can be specified multiple times.

File name of I<-> specifies to read from standard input.

=item B<-header>

If specified once, print the header only in the beginning (default).

If specified more than once, header is printed before output for each
project id.

=item B<-noheader> | B<-H>

Turn off header printing.

=item B<-start-date> I<yyyy.mm.dd.hh.mm.ss>

Specify starting date, inclusive, for the date range. See I<end-date>
option for other details.

=item B<-timezone> | B<-tz> I<time zone>

Specify a time zone for all the dates given, default is UTC.

Dates will be shifted to UTC time zone (from the given time zone).

=back

=head1 BUGS

Not known yet.

=head1 AUTHORS

Anubhav E<lt>a.agarwal@jach.hawaii.eduE<gt>

=cut

