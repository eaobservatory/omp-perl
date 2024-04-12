=head1 NAME

OMP::FindTarget

=cut

package OMP::FindTarget;

use strict;

use Astro::Coords;
use Astro::PAL;
use DBI;
use Math::Trig;

use OMP::DB::Backend;
use OMP::DB::Project;
use OMP::DB::MSB;

use base qw/Exporter/;
our @EXPORT_OK = qw/find_and_display_targets find_targets display_targets/;

our $debug = 0;

=head1 SUBROUTINES

=over 4

=item find_and_display_targets

Finds and displays targets.

=cut

sub find_and_display_targets {
    display_targets(find_targets(@_));
}

sub find_targets {
    my %opt = @_;

    my $dsep = undef;
    my $sep_rad = undef;
    my $tel = '%';
    my $sem = '%';
    my $sqlcmd = undef;

    if ($opt{'sep'}) {
        $dsep = $opt{'sep'};
        $sep_rad = $dsep * DD2R / 3600.0;
    }
    else {
        die 'find_and_display_targets: sep not specified'
    }

    if ($opt{'tel'}) {
        die 'find_and_display_targets: invalid telescope'
            unless $opt{'tel'} =~ /^([A-Z0-9]+)$/i;
        $tel = $1;
    }

    if ($opt{'sem'} ) {
        die 'find_and_display_targets: invalid semester'
            unless $opt{'sem'} =~ /^([A-Z0-9]+)$/i;
        $sem = $1;
    }

    # The original "ompfindtarget" stored procedure had two separate
    # queries for project-based cross-match and plain position search.
    # These have been imported separately for now but could be merged.
    if ($opt{'proj'}) {
        die 'find_and_display_targets: invalid project'
            unless $opt{'proj'} =~ /^([A-Z0-9\/]+)$/i;
        my $proj = $1;

        $sqlcmd = "SELECT DISTINCT
                cast(Q2.target AS char(24)) AS reference, P.projectid,
                Q.target AS target,
                3600.0/${\(DD2R)}*abs(acos(round(
                    cos(PI()/2 - Q2.dec2000)*cos(PI()/2 - Q.dec2000)+
                    sin(PI()/2 - Q2.dec2000)*sin(PI()/2 - Q.dec2000)*cos(Q2.ra2000 - Q.ra2000),
                12))) AS separation,
                Q.ra2000, Q.dec2000, Q.instrument
            FROM $OMP::DB::Project::PROJTABLE P, $OMP::DB::MSB::MSBTABLE M, $OMP::DB::MSB::OBSTABLE Q,
                $OMP::DB::Project::PROJTABLE P2, $OMP::DB::MSB::MSBTABLE M2, $OMP::DB::MSB::OBSTABLE Q2
            WHERE P2.projectid LIKE \"$proj\"
                AND M2.projectid = P2.projectid
                AND Q2.msbid = M2.msbid
                AND P2.telescope LIKE \"$tel\"
                AND Q2.coordstype = \"RADEC\"
                AND P.projectid NOT LIKE P2.projectid
                AND P.projectid NOT LIKE '%EC%'
                AND M.projectid = P.projectid
                AND Q.msbid = M.msbid
                AND P.telescope LIKE \"$tel\"
                AND P.semester LIKE \"$sem\"
                AND Q.coordstype = 'RADEC' and P.state=1
                AND abs(acos(round(
                    cos(PI()/2 - Q2.dec2000)*cos(PI()/2 - Q.dec2000)+
                    sin(PI()/2 - Q2.dec2000)*sin(PI()/2 - Q.dec2000)*cos(Q2.ra2000 - Q.ra2000),
                12))) < $sep_rad
            ORDER BY Q2.target";
    }
    elsif ($opt{'ra'} and $opt{'dec'}) {
        my $coord = Astro::Coords->new(
            ra => $opt{'ra'},
            dec => $opt{'dec'},
            type => 'J2000',
            units=> 'sexagesimal');

        my $ra = $coord->ra2000();
        my $dec = $coord->dec2000();

        my $ra_rad = $ra->radians();
        my $dec_rad = $dec->radians();

        my $ref = "$ra $dec";

        $sqlcmd = "SELECT DISTINCT
                \"$ref\" AS reference, P.projectid, Q.target AS target2,
                3600.0/${\(DD2R)}*abs(acos(round(
                    cos(PI()/2 - $dec_rad)*cos(PI()/2 - Q.dec2000)+
                    sin(PI()/2 - $dec_rad)*sin(PI()/2 - Q.dec2000)*cos($ra_rad - Q.ra2000),
                12))) AS separation,
                Q.ra2000, Q.dec2000, Q.instrument
            FROM $OMP::DB::Project::PROJTABLE P, $OMP::DB::MSB::MSBTABLE M, $OMP::DB::MSB::OBSTABLE Q
            WHERE P.projectid NOT LIKE '%EC%'
                AND M.projectid = P.projectid
                AND Q.msbid = M.msbid
                AND P.telescope LIKE \"$tel\"
                AND P.semester LIKE \"$sem\"
                AND Q.coordstype = \"RADEC\" AND P.state=1
                AND abs(acos(round(
                    cos(PI()/2 - $dec_rad)*cos(PI()/2 - Q.dec2000)+
                    sin(PI()/2 - $dec_rad)*sin(PI()/2 - Q.dec2000)*cos($ra_rad - Q.ra2000),
                12))) < $sep_rad
            ORDER BY Q.target";
    }
    else {
        die 'find_and_display_targets: neither proj nor ra and dec specified';
    }

    print "$sqlcmd\n" if $debug;

    # Get the connection handle

    my $dbs = OMP::DB::Backend->new();

    my $db = $dbs->handle() || die qq {
    --------------------------------------------------------------
     Error:       Connecting to Db: $DBI::errstr
    --------------------------------------------------------------
    };

    my $row_ref = $db->selectall_arrayref($sqlcmd) || die qq {
    --------------------------------------------------------------
     Error:       Executing DB query: $DBI::errstr
    --------------------------------------------------------------
    };

    # Disconnect from DB server
    $db->disconnect();

    return $row_ref unless wantarray;
    return ($row_ref, $dsep);
}

sub display_targets {
    my $row_ref = shift;
    my $dsep = shift;

    # Print output
    my ($hh, $mm, $ss, $sss, $sign, $dd, $am, $as, $ass );
    my $pi = 4.0*atan(1.0);

    print "----------------------------------------------------------------------------\n";
    if ($#$row_ref < 0) {
        print "No targets within $dsep arcsecs from reference.\n";
    }
    else {
        my $n = 0;
        my $pref = "";
        foreach my $row (@$row_ref) {
            $n ++;

            my ($ref, $proj, $target, $sep, $ra, $dec, $instr) = @$row;

            if ($n == 1 || $ref ne $pref) {
                print "Targets within $dsep arcsecs from  ${ref}:\n";
                $pref = $ref;
            }

            my ($sign_ra, @hh) = palDr2tf(2, $ra);
            my ($sign, @dd) = palDr2af(2, $dec);

            printf "%-12s %12s %8d\"  %2.2d %2.2d %2.2d.%2.2d %1.1s%2.2d %2.2d %2.2d.%2.2d %8s\n",
                $proj, $target, int($sep + 0.5), $hh[0], $hh[1], $hh[2], $hh[3],
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
