#!/local/perl/bin/perl

=head1 NAME

list-md5sums - Generate md5sum check files from md5sum values in files table

=head1 SYNOPSIS

    list-md5sums.pl --utdate 20220808 --backend ACSIS | md5sum -c -

=head1 DESCRIPTION

Searches the C<COMMON> table for observations with the given C<utdate>
and optionally the given C<backend>.  For corresponding entries
in the C<files> table, writes out the md5sum and pathname in the format
required for md5sum's "check" (C<-c>) mode.  The output can be
redirected to a file or piped directly to md5sum for checking.

=cut

use strict;

use FindBin;
use File::Spec;

use constant OMPLIB => File::Spec->catdir(
    "$FindBin::RealBin", File::Spec->updir, 'lib');
use lib OMPLIB;

BEGIN {
    $ENV{'OMP_CFG_DIR'} = File::Spec->catdir(OMPLIB, '../cfg')
        unless exists $ENV{'OMP_CFG_DIR'};
}

use Getopt::Long;
use Pod::Usage;

use OMP::DBbackend::Archive;

my $help;
my $utdate = undef;
my $backend = undef;

GetOptions(
    'help' => \$help,
    'utdate=s' => \$utdate,
    'backend=s' => \$backend,
) or die 'Error parsing arguments';

pod2usage('-exitval' => 1, '-verbose' => 1) if $help;

die 'Date not specified' unless defined $utdate;

my $db = new OMP::DBbackend::Archive();

my $dbh = $db->handle();

my $sql = 'SELECT f.file_id, f.md5sum'
    . ' FROM jcmt.COMMON AS c JOIN jcmt.FILES AS f ON c.obsid = f.obsid'
    . ' WHERE c.utdate=?';
my @bind = ($utdate);

if (defined $backend) {
    $sql .= ' AND c.backend=?';
    push @bind, $backend;
 }

my $result = $dbh->selectall_arrayref($sql, {}, @bind)
    or die $dbh->errstr;

foreach my $row (@$result) {
    my ($file, $md5sum) = @$row;

    my $dir;
    if ($file =~ /^a(\d{8})_(\d{5})_(\d{2})_(\d{4})\.sdf$/) {
        $dir = sprintf '/jcmtdata/raw/acsis/spectra/%s/%s', $1, $2;

    }
    elsif ($file =~ /^(s[48][abcd])(\d{8})_(\d{5})_(\d{4})\.sdf$/) {
        $dir = sprintf '/jcmtdata/raw/scuba2/%s/%s/%s', $1, $2, $3;
    }
    else {
        die 'Unexpected pattern: ' . $file;
    }

    printf "%s  %s/%s\n", $md5sum, $dir, $file;
}

__END__

=head1 COPYRIGHT

Copyright (C) 2022 East Asian Observatory
All Rights Reserved.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful,but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc.,51 Franklin
Street, Fifth Floor, Boston, MA  02110-1301, USA
