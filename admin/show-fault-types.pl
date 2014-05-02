#!/local/perl/bin/perl

use strict; use warnings FATAL => 'all';
our $VERSION = '0.00';
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
my ( $category, $system, $type );
my ( $help );
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

    my $sys_o  = make_system( $c, $sys ) or next;
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

  my ( $cat, $sys ) = @_;

  return _make_type_or_sys( $sys, OMP::Fault->faultSystems( $cat ) );
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

=pod

=head1 NAME


=head1 SYNOPSIS


=head1  DESCRIPTION



=head2  OPTIONS

=over 2

=item *


=item *


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


