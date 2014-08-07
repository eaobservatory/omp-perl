package OMP::SCUBA2Acct;

=head1 NAME

OMP::SCUBA2Acct - Collection of functions to help SCUBA2 accounting.

=head1 SYNOPSIS

  use OMP::SCUBA2Acct;

  .
  .
  .

=head1 DESCRIPTION

  .
  .
  .

=cut

use strict; use warnings;

use Carp;
use OMP::Constants qw/ :logging /;
use OMP::Range;
use OMP::DateTools;
use OMP::Error qw/ :try /;

use Fcntl qw/ :flock /;

our $VERSION = 0.01;

our $DEBUG = 0;

my @month_name = (qw[jan feb mar apr may jun jul aug sep oct nov dec]);
my ( %map_month, %rev_map_month );
@map_month{ @month_name } = map { sprintf '%02d' , $_ } ( 1 .. 12 );
@rev_map_month{ values %map_month } = keys %map_month;

=head1 METHODS/FUNCTIONS

  .
  .
  .

=over 4

  .
  .
  .

=back

=cut


# Currently file with multiple months is something like ...
#
#     TSS     UTdate
#
#        2011-10
#
#     JAC ; XYZ :    2
#     "  ; :  3
#     "  ; :  4
#     "  ; :  5
#     WKM ; XYZ :   6
#     "  ; :  7
#     "  ; :  8
#     "  ; :  9
#     "   ; : 10
#     JGW ; : 11
#     "   ; : 12
#     JCH ; : 13
#     "   ; : 14
#     "   ; : 15
#     WKM/JCH ; : 16
#     "   ; : 17
#     JCH ; : 18
#     WKM ; : 19
#     ...
#     none    25
#     ...
#
#  ...and expected output ...
#
#     Totals
#     ------
#     JAC 13
#     JCH 36
#     WKM 37
#     JGW 15
#       ---
#         103  = 31 + 30 + 30 + 12
#                 Oct  Nov  Dec   daytime shift
sub make_schedule {

  my ( $file ) = @_;

  my $ignore_re =
    qr{^
        \s*
        (?:
          # comments;
          \#
          |
          # TSS missing;
          none \s+ \d+
          |
          # empty lines.
          $
        )
      }ix;

  my $date_sep_re = qr{[-./ ]+};

  # Make regex to take care of either month name or number.
  my $month_name_re = join '|', @month_name;
  my $month_num_re  = join '|', sort values %map_month;
  my $month_re      = qr{^\s*
                          ( \d{4}
                            (?:$date_sep_re)?
                            (?:$month_num_re|$month_name_re)
                          )
                          \b
                        }ix;

  my $tss_repeat    = q["];
  my $tss_sep       = q[/];
  my $tss_re        = qr{[a-z]+}i;
  my $tss_duo_re    = qr{$tss_re \s* $tss_sep \s* $tss_re }x;
  my $tss_tri_re    = qr{$tss_duo_re \s* $tss_sep \s* $tss_re }x;
  my $tss_date_re   = qr{^\s*
                          # Primary TSS;
                          ($tss_tri_re|$tss_duo_re|$tss_re|$tss_repeat)
                          \s*
                          ;
                          \s*
                          # Daytime Observing TSS (optional);
                          ($tss_tri_re|$tss_duo_re|$tss_re|$tss_repeat)?
                          \s*
                          :
                          \s*
                          # day.
                          (\d+)
                          \b
                        }x;

  my ( %data, $old_tss, $old_tss_day, $month );

  open my $fh, '<', $file
    or die "Cannot open '$file' to read: $!\n";

  while ( my $line = <$fh> ) {

    next if $line =~ $ignore_re;

    if ( $line =~ $month_re ) {

      ( $month = lc $1 ) =~ s{$date_sep_re}//g;
      next;
    }

    my ( $tss, $tss_day, $day ) =
      ( $line =~ $tss_date_re ) or next;

    #my $use_old = $tss eq $tss_repeat;
    #! $use_old and $old_tss = $tss;

    my $date =
      sprintf "%02d%02d",
        exists $map_month{ $month } ? $map_month{ $month } : $month,
        $day;

    my %list = ( 'regular' => $tss , 'daytime' => $tss_day );
    for my $type ( keys %list ) {

      push @{ $data{ $date }->{ $type } },
        $list{ $type } ? ( split $tss_sep, $list{ $type } ) : ();
    }

  }

  close $fh
    or die "Could not close '$file': $!\n";

  return %data;
}


1;

=head1 AUTHORS

Anubhav AgarwalE<lt>a.agarwal@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2012, 2014 Science and Technology Facilities Council.
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

