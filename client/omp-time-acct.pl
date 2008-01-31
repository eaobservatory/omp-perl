#!/usr/local/bin/perl

use warnings;
use strict;

use Getopt::Long;
use Pod::Usage;
use List::Util qw/ first /;
use Scalar::Util qw/ blessed openhandle /;

use OMP::DBbackend;
use OMP::TimeAcctDB;
use OMP::TimeAcctQuery;

my %opt =
  ( 'help' => undef,
    'header' => 1,
    'divider' => undef,
    'file' => []
  );

{
  my @file;
  GetOptions(
    'h|help|man' => \$opt{'help'},
    'file=s'     => \@file,
    'header+'    => \$opt{'header'},
    'H|noheader' => sub{ $opt{'header'} = undef },
    'divider!'    => \$opt{'divider'},
  ) or die pod2usage( '-exitval' => 2, '-verbose' => 1 );

  $opt{'file'} = [ @file ] if scalar @file;
}

pod2usage( '-exitval' => 1, '-verbose' => 2 ) if $opt{'help'};

my $db = OMP::TimeAcctDB->new( 'DB' => OMP::DBbackend->new );
my %proj;
for my $id ( get_projects( \%opt, @ARGV ) ) {

  push @{ $proj{ $id } }, $db->queryTimeSpent( make_query( $id ) );
}

Acct::print_header( $opt{'header'} );
Acct::print_csv( $proj{ $_ } ) for sort keys %proj ;
print "\n" if $opt{'divider'};

exit;

BEGIN
{{
  package Acct;

  my @header = qw{ projectid timespent confirmed date } ;

  sub print_csv {

    my ( $acct ) = @_;

    for my $ac ( @${ acct } ) {

      main::print_csv( map { $ac->$_ } @header )  ;
    }

    return;
  }

  sub print_header { return main::print_header( $_[0], @header ); }
}}

{
  my $once;
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

sub print_csv {

  printf "%s\n", join ',', @_;
  return;
}

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

sub make_query {

  my ( $proj ) = @_;

  my $root = 'TimeAcctQuery';
  my $id = 'projectid';
  return
    OMP::TimeAcctQuery->new( 'XML' => wrap( $root => wrap( $id => $proj ) ) );
}

sub wrap {

  my ( $tag, @val ) = @_;

  return qq{<$tag>} . join( ' ' , @val ) . qq{</$tag>};
}

=pod

=head1 NAME

omp-time-acct.pl - Show time spent on a project as CSV

=head1 SYNOPSIS

omp-time-acct.pl I<project-id> [ I<project-id> ... ]

omp-time-acct.pl < I<file-containing-project-ids>

echo I<project-id> | omp-time-acct.pl

=head1 DESCRIPTION


=cut

__DATA__
m07bc01 m07bc17
m07bc16
