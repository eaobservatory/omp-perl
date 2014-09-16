#!/local/perl/bin/perl

use strict; use warnings;
our $VERSION = '0.01';
use 5.010;

use OMP::DateTools;

use Getopt::Long    qw[ :config gnu_compat no_ignore_case require_order ];
use Pod::Usage;

my ( $tel, $proj );
my ( $help );
GetOptions( 'h|help|man' => \$help ,
           'telescope=s' => \$tel ,
          )
  or pod2usage( '-exitval'  => 2 , '-verbose'  => 1 ) ;

$help and pod2usage( '-exitval' => 0 , '-verbose' => 3 );

my @sem =
  map { prefix_zero( $_ ) } @ARGV
    or die qq[Give at least one semester to find the dates.\n];

$tel && $tel =~ m{^(?:ukirt|jcmt)$}i
  or die qq[Do specify a known telescope name (UKIRT or JCMT).\n];

my @range =
  map( +{ $_ =>
          [ OMP::DateTools->semester_boundary( 'tel' => $tel , 'semester' => $_) ]
        },
        @sem
      ) ;
show( $tel, @range );

exit;

sub prefix_zero {

  my ( $sem ) = @_;

  $sem or return;

  $sem = uc $sem;

  my ( $num , $alph ) =
    ( $sem =~ m/^ ([0-9]+) ([A-Z]+) $/x ) or return $sem ;

  return sprintf "%02d%s" , $num , $alph;
}

sub show {

  my ( $tel , @range ) = @_;

  my $range_f = qq[%-8s  %-10s  %-10s\n];

  printf "  %s\n=========\n" , uc $tel ;
  printf $range_f , qw[ semester start end ];
  print qq[------------------------------------\n];

  for my $r ( @range ) {

    printf $range_f , simplify( $r );
  }

  return;
}

sub simplify {

  my ( $range ) = @_;

  my ( $sem ) = keys %{ $range };

  return ( $sem , map { $_->ymd() } @{ $range->{ $sem } } );
}


__END__

=pod

=head1 NAME

semester-dates.pl - Show date range of a semester

=head1 SYNOPSIS

  semester-dates.pl -tel jcmt 14a

=head1  DESCRIPTION

Given a list of semester and a telescope, prints a table of date-ranges for each
semester.

=head2  OPTIONS

=over 2

=item B<help>

Shows this message.

=item B<telescope>

Specify a telescope: UKIRT or JCMT; B<required>.

=back

=head1 COPYRIGHT

Copyright (C) 2014 Science and Technology Facilities Council.
All Rights Reserved.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the
Free Software Foundation, Inc., 59 Temple Place, Suite 330,
Boston, MA  02111-1307  USA

=cut


