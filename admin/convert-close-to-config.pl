#!/local/perl/bin/perl

=pod

=head1 NAME

convert-close-to-config.pl - Converts project definition to Config::Ini syntax

=head1 SYNOPSIS

  convert-close-to-config.pl project-definition-file > converted.ini

=cut

use strict;
use warnings;

use Pod::Usage;
use Getopt::Long ( qw[ :config gnu_compat no_ignore_case no_debug ] );
use List::Util ( qw[ first ] );
use List::MoreUtils ( qw[ any ] );

my $help;
GetOptions( 'h|m|help|man' => \$help )
    or die pod2usage( '-exitval'  => 2 , '-verbose'  => 1 );

pod2usage( '-exitval' => 0 , '-verbose' => 3 ) if $help;

my $file = shift @ARGV
  or die "No file was given to convert.\n";

my $parse_line_re =
  qr{^\s*
      ( co-?is? | pi | support
        # Not a bona fied key but is needed to mark section heading.
        | proj(?:ect)
        | title | allocations? | tagpriority
        | semester | telescope | country
        | taurange | band | seeing | cloud | sky
      )
      \s* [=:] \s*
      (.+?)
      \s*$
    }xi;

my $skip_val = qr{^\s* (?:none | $) }ix;

my @user = (qw[ coi pi support ]);

my %alt_key =
  ( 'cois'  => 'coi',
    'co-is' => 'coi',
    'allocations' => 'allocation'
  );

my %user_map =
  ( 'TOM KERR'     => 'kerrt'
  , 'WATSON'       => 'varricattw'
  , 'MYUNGSHIN IM' => 'imm'
  );

my @uppercase = ( @user , qw[ project ] );

{
  local $/ = '';

  open my $fh, '<', $file or die "Cannot open file, '$file': $!\n";

  while ( my $block = <$fh> )
  {
    ( my $copy = $block ) =~ s/^/##  /gm;
    $copy =~ s/[ ]+$//;
    print "$copy\n";

    process_block( $block );

    print "\n";
  }

  close $fh or die "Cannot close file, '$file': $!\n";
}


sub process_block
{
  my ( $block ) = @_;

  my @block = split /\n+/ , $block;
  chomp @block;

  for my $line ( @block )
  {
    if ( $line =~ /^#/ || $line =~ /^\s*$/ )
    {
      next;
    }

    if ( $line =~ /^\[info\]/i )
    {
      print "$line\n";
      next;
    }

    my ( $key , $val ) = ( $line =~ $parse_line_re );

    unless ( $key && defined $val )
    {
      next;
    }

    ( $key , $val ) = format_key_val( $key , $val );

    $val =~ $skip_val and next;

    if ( $key =~ /^proj/ )
    {
      printf "[%s]\n" , $val;
      next;
    }

    printf "%s= %s\n" , $key , $val;
  }

  return;
}

sub format_key_val
{
  my ( $k , $v ) = @_;

  for ( $k )
  {
    $_ = lc $_;
    tr/-//d;

    exists $alt_key{ $_ } and $_ = $alt_key{ $_ };
  }

  if ( any { $k eq $_ } @uppercase )
  {
    $v = uc $v;
  }

  if ( $k eq 'allocation' )
  {
    $v =~ s/\s*h(?:ou)?rs?\s*//i
  }
  elsif ( any { $k eq $_ } @user )
  {
    $v = format_users( $v );
  }

  return ( $k , $v );
}

sub format_users
{
  my ( $users ) = @_;

  return unless $users && length $users;

  my @user = split /\s*,\s*/ , $users;

  for my $u ( @user )
  {
    my $k = first { $u =~ /$_/ } keys %user_map ;
    if ( defined $k )
    {
      $u = $user_map{ $k };
    }
  }

  return join ' , ' , @user;
}

__END__

=pod

=head1  DESCRIPTION

Converts project definitions given in a file to L<Config::Ini>
parsable syntax given in similar-to-but-not-quite syntax for
L<Config::Ini>. See also F</jac_sw/omp/msbserver/admin/mkproj.pl>.

So far only three user names, when matched exactly, are converted to
user ids: Myungshin Im, Tom Kerr, Watson.

Note that this program B<relies on having completely blank lines>
(without any spaces) between any two program definitions and/or
comment lines.

Original input is copied in output preceded with C<##  >.  This is to
verify the conversion and to take care unmatched user names manually.

Output is sent to standard output.

For example, given (note that line 4 has only a single space) ...

  ,----------
  | #More projects for the OMP. All semester 11B, country "KR" (Korea),
  | #priority 50.
  | #
  | 
  |
  | #IMM : Myungshin Im
  |
  |
  | Project: U/11B/K1
  | Title: CEOU time in 11B - block 1
  | Allocation: 110 hrs
  | PI: Myungshin Im <myungshin.im@gmail.com>
  | Co-I:
  | Support: Watson, Tom Kerr
  |
  | Project: U/11B/K2
  | Title: CEOU time in 11B - block 2
  | Allocation: 55 hrs
  | PI: Myungshin Im <myungshin.im@gmail.com>
  | Co-I:
  | Support: Tom Kerr, Watson
  `----------

... is changed to ...

  ,----------
  | ##  #More projects for the OMP. All semester 11B, country "KR" (Korea),
  | ##  #priority 50.
  | ##  #
  | ## 
  |
  |
  | ##  #IMM : Myungshin Im
  |
  |
  | ##  Project: U/11B/K1
  | ##  Title: CEOU time in 11B - block 1
  | ##  Allocation: 110 hrs
  | ##  PI: Myungshin Im <myungshin.im@gmail.com>
  | ##  Co-I:
  | ##  Support: Watson, Tom Kerr
  |
  | [U/11B/K1]
  | title= CEOU time in 11B - block 1
  | allocation= 110
  | pi= imm
  | support= varricattw , kerrt
  |
  | ##  Project: U/11B/K2
  | ##  Title: CEOU time in 11B - block 2
  | ##  Allocation: 55 hrs
  | ##  PI: Myungshin Im <myungshin.im@gmail.com>
  | ##  Co-I:
  | ##  Support: Tom Kerr, Watson
  |
  | [U/11B/K2]
  | title= CEOU time in 11B - block 2
  | allocation= 55
  | pi= imm
  | support= kerrt , varricattw
  `----------

=head1 OPTIONS

=over 2

=item B<-man> | B<-help>

Show help message.

=back

=head1 AUTHOR

Anubhav <a.agarwal@jach.hawaii.edu>

=head1 COPYRIGHT

Copyright (C) 2011 Science and Technology Facilities Council.
All Rights Reserved.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or (at
your option) any later version.

This program is distributed in the hope that it will be useful,but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place,Suite 330, Boston, MA  02111-1307,
USA.

=cut

