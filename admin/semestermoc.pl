#!/local/perl/bin/perl

=head1 NAME

semestermoc - Generate MOC for a semester's MSBs

=head1 SYNOPSIS

    semestermoc --semester 23B --queue PI --out coverage.fits

=head1 DESCRIPTION

This program searches for projects with the given semester and queue.  It then
generates combined coverage information for their MSBs and writes it to the
specific MOC FITS file.

=cut

use strict;
use warnings;

use Pod::Usage;
use Getopt::Long;

use FindBin;
use lib "$FindBin::RealBin/../lib";

use OMP::SpRegion;
use Starlink::AST;
use Starlink::ATL::MOC qw/write_moc_fits/;

use OMP::DBbackend;
use OMP::Error qw/:try/;
use OMP::MSBDB;
use OMP::ProjDB;
use OMP::ProjQuery;

my ($semester, $queue, $filename, $help);
GetOptions(
    'semester=s' => \$semester,
    'queue=s' => \$queue,
    'out=s' => \$filename,
    help => \$help,
) or pod2usage(2);

pod2usage(-exitstatus => 0, -verbose => 2) if $help;

die 'Semester not specified' unless defined $semester;
die 'Queue not specified' unless defined $queue;
die 'Output filename not specified' unless defined $filename;

my $order = 12;

my $db = OMP::DBbackend->new();
my $projdb = OMP::ProjDB->new(DB => $db);
my $msbdb = OMP::MSBDB->new(DB => $db);

my @projects = $projdb->listProjects(OMP::ProjQuery->new(XML => sprintf
    '<ProjQuery>' .
    '<state>1</state><telescope>JCMT</telescope>' .
    '<semester>%s</semester><country>%s</country>' .
    '</ProjQuery>',
    $semester, $queue,
));

my $combined = undef;

foreach my $project (@projects) {
    my $projectid = $project->projectid;
    $msbdb->projectid($projectid);

    printf "Fetching program for %s\n", $projectid;

    try {
        my $sp = $msbdb->fetchSciProg(1);
        my $spr = OMP::SpRegion->new($sp);
        my $moc = $spr->get_moc(order => $order);

        if (defined $moc) {
            unless (defined $combined) {
                $combined = $moc;
            }
            else {
                $combined->AddRegion(Starlink::AST::Region::AST__OR(), $moc);
            }
        }
    }
    catch OMP::Error::UnknownProject with {
    };
}

unless (defined $combined) {
    printf "No region data obtained\n";
}
else {
    unlink $filename if -e $filename;
    write_moc_fits($combined, $filename);
}

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
