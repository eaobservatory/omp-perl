#!/usr/local/bin/perl

use warnings;
use strict;

use Getopt::Long qw/ :config gnu_compat no_ignore_case /;
use Pod::Usage;
use List::Util qw/ first /;
use Scalar::Util qw/ blessed openhandle /;

use OMP::DBbackend;
use OMP::TimeAcctDB;
use OMP::TimeAcctQuery;

my %opt =
  ( 'header' => undef,
    'divider' => undef,
    'file' => []
  );

{
  my ( $help, @file );
  GetOptions(
    'h|help|man' => \$help,
    'file=s'     => \@file,
    'header+'    => \$opt{'header'},
    'H|noheader' => sub{ $opt{'header'} = 0 },
    'divider!'    => \$opt{'divider'},
  )
    # As of Pod::Usage 1.30, C<'-sections' => 'OPTIONS', '-verbose' => 99> does
    # not output only the OPTIONS part.  Also note that in pod, key is listed
    # '-section' but in code '-sections' is actually used.
    or pod2usage( '-exitval' => 2, '-verbose' => 1,);

  pod2usage( '-exitval' => 1, '-verbose' => 2 ) if $help;

  $opt{'file'} = [ @file ] if scalar @file;

  # Print header at least once in the beginning by default.
  $opt{'header'}++ unless defined $opt{'header'};
}

my @proj = get_projects( \%opt, @ARGV )
  or pod2usage( '-exitval' => 2, '-verbose' => 99, '-sections' => 'SYNOPSIS',
                '-msg' => 'No project ids were given.'
              );
my $last = $proj[-1];

my $db = OMP::TimeAcctDB->new( 'DB' => OMP::DBbackend->new );

for my $id ( @proj ) {

  Acct::print_header( $opt{'header'} );

  Acct::print_csv( $db->queryTimeSpent( make_query( $id ) ) );

  print "\n" if $opt{'divider'} && $id ne $last;
}

exit;

BEGIN
{{
  # Keep related things together.
  package Acct;

  # The method names to be called, in order, on given C<OMP::TimeAcctQuery>
  # object.
  my @header = qw{ projectid timespent date confirmed } ;

  #  Prints CSV given a list of C<OMP::TimeAcctQuery> objects.
  sub print_csv {

    my ( @acct ) = @_;

    for my $ac ( @acct ) {

      main::print_csv( map { $ac->$_ } @header )  ;
    }
    return;
  }

  # Prints the header given a flag (if & how many times to print) and list of
  # header strings.
  sub print_header { return main::print_header( $_[0], @header ); }
}}

{
  my $once;
  # Prints header as CSV given a flag and a list of header strings.  Flag
  # specifies if to print the header at all, only once, or every time.
  sub print_header {

    my $header_once = shift;

    return unless $header_once;
    return if $once && $header_once == 1;

    $once++;
    my @header = @_;
    return
      # Header in lower case after normalizing any camelCase ones.
      print_csv( map { s/([a-z])([A-Z])/$1_$2/; lc $_ } @header );
  }
}

# Simple mindedly prints CSV (see I<Text::CSV> for robustness).
sub print_csv {

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

=item B<-divider>

Print a blank line after output of each project id.  Default is not to
print the blank line.

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

=back

=head1 BUGS

Not known yet.

=head1 AUTHORS

Anubhav E<lt>a.agarwal@jach.hawaii.eduE<gt>

=cut

__DATA__
m07bc01 m07bc17
m07bc16
