#!/local/perl/bin/perl

=head1 NAME

check_md5sums.pl - check MSB checksums

=head1 SYNOPSIS

    check_md5sums [--all] [--verbose] PROJECT...

=head1 DESCRIPTION

This program compares MSB checksums in the OMP database with checksums
calculated from the science program XML.

For each listed project, or all projects if C<--all> is specified,
retrieve the database checksums using C<OMP::MSBDB-E<gt>getSciProgInfo>
and the current science program using C<OMP::MSBDB-E<gt>fetchSciProg>.
The C<msb> method of each result is used to get the MSBs, assuming
that the checksums in the science program will have been automatically
recalculated.

If any problems are found this program should exit with bad status.

=cut

use strict;

use FindBin;
use Getopt::Long;
use Pod::Usage;

use constant OMPLIB => "$FindBin::RealBin/../lib";

BEGIN {
    $ENV{'OMP_CFG_DIR'} = File::Spec->catdir(OMPLIB, '../cfg')
        unless exists $ENV{'OMP_CFG_DIR'};
}

use lib OMPLIB;

use OMP::DBbackend;
use OMP::General;
use OMP::MSBDB;

my ($verbose, $all_projects, $help);
GetOptions(
    all => \$all_projects,
    verbose => \$verbose,
    help => \$help,
) or pod2usage(2);

pod2usage(-exitstatus => 0, -verbose => 2) if $help;

my $db = OMP::DBbackend->new;
my $msbdb = OMP::MSBDB->new(DB => $db);

my @projects;
if ($all_projects) {
    die 'Projects given in --all mode' if scalar @ARGV;

    @projects = $msbdb->listModifiedPrograms();
}
else {
    die 'No projects given when not in --all mode' unless scalar @ARGV;

    foreach (@ARGV) {
        my $projectid = OMP::General->extract_projectid($_);
        die "Project ID '$_' not valid" unless defined $projectid;
        push @projects, uc $projectid;
    }
}

my $n_error = 0;
local $\ = "\n";
foreach my $projectid (@projects) {
    print "Checking $projectid";
    $msbdb->projectid($projectid);

    my $info = $msbdb->getSciProgInfo(with_observations => $verbose);
    my $sciprog = $msbdb->fetchSciProg(1);

    my @db_checksums = map {$_->checksum} $info->msb;
    my %sp_checksums = map {$_->checksum => 1} $sciprog->msb;

    my $n_mismatch = 0;

    foreach my $checksum (sort @db_checksums) {
        if (delete $sp_checksums{$checksum}) {
            print "    OK: $checksum" if $verbose;
        }
        else {
            $n_mismatch ++;
            print "    Mismatch: $checksum (DB)";

            if ($verbose) {
                my $msbinfo = $info->fetchMSB($checksum);
                print "$msbinfo";
            }
        }
    }

    foreach my $checksum (sort keys %sp_checksums) {
        $n_mismatch ++;
        print "    Mismatch: $checksum (SP)";

        if ($verbose) {
            my $msb = $sciprog->fetchMSB($checksum);
            my $msbinfo = $msb->info();
            print "$msbinfo";
        }
    }

    if ($n_mismatch) {
        print "$n_mismatch checksum(s) did not match";
        $n_error ++;
    }
}

if ($n_error) {
    print "Problems found with $n_error project(s)";
    exit 1;
}
else {
    print "All checksums appear correct";
}

__END__

=head1 COPYRIGHT

Copyright (C) 2023 East Asian Observatory
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

=cut
