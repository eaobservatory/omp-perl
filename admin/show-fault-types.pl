#!/local/perl/bin/perl

=head1 NAME

show-fault-types.pl - Show fault types avialable.

=head1 SYNOPSIS

List everything ...

  show-fault-types.pl

List only the matching "Category" and associated "System" and "Type"
choices ...

  show-fault-types.pl -category vehicle

=head1  DESCRIPTION

Main purpose of this program is to show the fault classification
information to help move a fault from one "Category" to the other.
Else it comes handy as reference without having to wade the source
code.

=head2  OPTIONS

=over 2

=item B<-help>

Show this message.

=item <category> string

Search fault "Category" for the given string.

=item B<end>

Search for given word near the end of possibilities.
It is mutually exclusive with I<start> and I<word> options.

=item B<start>

Search for given word at start of possibilities.
It is mutually exclusive with I<end> and I<word> options.

=item <system> string

Search fault "System" for the given string.

=item <type> string

Search fault "Type" for the given string.

=item B<word>

Search for given string as a whole word.
It is mutually exclusive with I<start> and I<end> options.

=item B<hidden>

Include hidden entries.

=back

=cut

use strict; use warnings FATAL => 'all';

use FindBin;
use constant OMPLIB => "$FindBin::RealBin/../lib";

use lib OMPLIB;

BEGIN {
  $ENV{OMP_CFG_DIR} = File::Spec->catdir( OMPLIB, "../cfg" )
    unless exists $ENV{OMP_CFG_DIR};
};

our $VERSION = '0.01';
use v5.10;
use autodie         qw[ :2.13 ];
use Carp            qw[ carp croak confess ];
use Try::Tiny;

use Getopt::Long    qw[ :config gnu_compat no_ignore_case require_order ];
use Pod::Usage;
use List::Util      qw[ max ];
use Scalar::Util    qw[ looks_like_number ];

use OMP::Fault;


my ( $match_any, $match_word, $match_start, $match_end ) = ( 1 );
my ( $category, $system, $type, $help, $hidden );
GetOptions( 'help'     => \$help,

            'start' =>
              sub { $match_start = 1; $match_end   = $match_word = $match_any = 0; },
            'end'   =>
              sub { $match_end   = 1; $match_start = $match_word = $match_any = 0; },
            'word'  =>
              sub { $match_word  = 1; $match_start = $match_end  = $match_any = 0; },

            'category=s' => \$category,
            'system=s'   => \$system,
            'type=s'     => \$type,
            'hidden'     => \$hidden,
          )
  or pod2usage( '-exitval'  => 2 , '-verbose'  => 1 ) ;

$help and pod2usage( '-exitval' => 0 , '-verbose' => 3 );

show( $category, $system, $type );
exit;

sub show {

  my ( $cat, $sys, $type ) = @_;

  my @cat  = sort OMP::Fault->faultCategories();
  my $cats = choose_data( $cat, { map { $_ => undef } @cat } );

  for my $c ( sort keys %{ $cats } ) {

    my $sys_o  = make_system( $c, $sys, $hidden ) or next;
    my $type_o = make_type( $c, $type ) or next;

    printf "\n%s: %s\n",
      term_bold( 'Category' ),
      term_reverse( term_bold( $c ) );

    printf "%s\n", term_underline( 'System' );
    print $sys_o;

    printf "%s\n", term_underline( 'Type' );
    print $type_o;

  }
  return;
}


sub make_system {

  my ( $cat, $sys, $hidden ) = @_;

  return _make_type_or_sys( $sys, OMP::Fault->faultSystems( $cat, include_hidden => $hidden ) );
}

sub make_type {

  my ( $cat, $type ) = @_;

  return  _make_type_or_sys( $type, OMP::Fault->faultTypes( $cat ) );
}

sub _make_type_or_sys {

  my ( $chosen, $data ) = @_;

  $data = choose_data( $chosen, $data )
    or return;

  my @key = sort keys %{ $data };

  my $max_key = max map { defined $_ && length $_ } @key;
  my $max_val = max map { defined $_ && length $_ } values %{ $data };
  my $format = qq/  %-${max_key}s : %${max_val}s\n/;

  my $out = '';
  for my $k ( @key ) {

    $out .= sprintf $format, $k, $data->{ $k };
  }
  return $out;
}

sub choose_data {

  my ( $key, $data ) = @_;

  ! defined $key and return $data;

  my $alt = quotemeta( $key );
  my $re =
    $match_any ? qr[$alt]i
    : $match_start ? qr[\b $alt]ix
      : $match_end ? qr[$alt \b]ix
        : qr[\b $alt \b]ix
        ;

  my $out;
  for my $k ( keys %{ $data } ) {

    $k =~ $re
    || ( defined $data->{ $k } && $data->{ $k } =~ $re )
      and $out->{ $k } = $data->{ $k };
  }
  return $out;
}

BEGIN
{
  my ( $norm, $bold, $under, $reverse ) =
    map qq/\e[${_}m/, 0, 1, 4, 7 ;

  sub term_bold      { return map { join '' , $bold,    $_ , $norm  } @_; }
  sub term_underline { return map { join '' , $under,   $_ , $norm  } @_; }
  sub term_reverse   { return map { join '' , $reverse, $_ , $norm  } @_; }
}

__END__

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
