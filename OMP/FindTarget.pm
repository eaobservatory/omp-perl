=head1 NAME

OMP::FindTarget

=cut

package OMP::FindTarget;

use strict;

use Astro::PAL;
use DBI;
use Math::Trig;

use OMP::DBbackend;

use base qw/Exporter/;
our @EXPORT_OK = qw/find_and_display_targets/;

our $debug = 0;

=head1 SUBROUTINES

=over 4

=item find_and_display_targets

Finds and displays targets.

=cut

sub find_and_display_targets {
    my %opt = @_;

    my $proj  = $opt{'proj'}
              ? '@proj=\'' . $opt{'proj'} . '\''
              : '';
    my $radec = ($opt{'ra'} and $opt{'dec'})
              ? '@ra=\'' . $opt{'ra'} . '\',@dec=\'' . $opt{'dec'} . '\''
              : '';
    my $dsep  = $opt{'sep'};
    my $tel   = '@tel=\'' . $opt{'tel'} . '\'';
    my $sem   = '@sem=\'' . $opt{'sem'} . '\'';

    my $sep    = '@sep=' . $dsep;
    my $sqlcmd = "ompfindtarget ${proj}${radec},${sep},${tel},${sem}";
    $sqlcmd =~ s/(\,)+/\,/g;
    $sqlcmd =~ s/\,$//;
    print "$sqlcmd\n";

    # Get the connection handle

    my $dbs = new OMP::DBbackend();
    my $dbtable = "ompproj";

    my $db = $dbs->handle() || die qq {
    --------------------------------------------------------------
     Error:       Connecting to Db: $DBI::errstr
    --------------------------------------------------------------
    };

    my $row_ref = $db->selectall_arrayref( qq{exec $sqlcmd}) || die qq {
    --------------------------------------------------------------
     Error:       Executing DB procedure: $DBI::errstr
    --------------------------------------------------------------
    };

    # Disconnect from DB server
    $db->disconnect();

    # Print output
    my ($hh, $mm, $ss, $sss, $sign, $dd, $am, $as, $ass );
    my $pi = 4.0*atan(1.0);

    print "----------------------------------------------------------------------------\n";
    if ($#$row_ref < 0 ) {
      print "No targets within $dsep arcsecs from reference.\n";
    } else {

      my $n = 0;
      my $pref = "";
      foreach my $row (@$row_ref) {
        $n++;

        my ($ref, $proj, $target, $sep, $ra, $dec, $instr) = @$row;

        if ($n == 1 || $ref ne $pref ) {
          if ($ref =~ /^\d/) {
            my ($ra_r, $dec_r) = split /\s+/, $ref;
            my ($sign_ra, @hh) = palDr2tf(2, $ra_r);
            my ($sign,    @dd) = palDr2af(2, $dec_r);
            $ref = sprintf "%2.2d %2.2d %2.2d.%2.2d %1.1s%2.2d %2.2d %2.2d.%2.2d",
                         $hh[0], $hh[1], $hh[2], $hh[3],
                         $sign, $dd[0], $dd[1], $dd[2], $dd[3];
          }
          print "Targets within $dsep arcsecs from  ${ref}:\n";
          $pref = $ref;
        }

        my ($sign_ra, @hh) = palDr2tf(2, $ra);
        my ($sign,    @dd) = palDr2af(2, $dec);

        printf qq{%-12s %12s %8d"  %2.2d %2.2d %2.2d.%2.2d %1.1s%2.2d %2.2d %2.2d.%2.2d %8s\n},
          $proj, $target, int($sep+0.5), $hh[0], $hh[1], $hh[2], $hh[3],
                         $sign, $dd[0], $dd[1], $dd[2], $dd[3], $instr;
      }
    }
    print "----------------------------------------------------------------------------\n";
}

1;

__END__

=back

=head1 COPYRIGHT

Copyright (C) 2004 Particle Physics and Astronomy Research Council.
All Rights Reserved.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful,but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc., 59 Temple
Place,Suite 330, Boston, MA  02111-1307, USA

=cut
