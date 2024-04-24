#!/local/perl/bin/perl

=head1 NAME

ompspsummary - Show summary of a science program

=head1 SYNOPSIS

    ompspsummary [--verbose] PROJECTID

    ompspsummary [--verbose] filename.xml

=cut

use strict;
use warnings;

use File::Spec;
use FindBin;
use Getopt::Long;
use Pod::Usage;

use constant OMPLIB => "$FindBin::RealBin/../lib";

BEGIN {
    $ENV{'OMP_CFG_DIR'} = File::Spec->catdir(OMPLIB, '../cfg')
        unless exists $ENV{'OMP_CFG_DIR'};
}

use lib OMPLIB;

use OMP::Config;
use OMP::DB::Backend;
use OMP::DB::MSB;
use OMP::SciProg;

my ($verbose);

GetOptions(
    'verbose' => \$verbose,
) or pod2usage(1);

my $db = OMP::DB::Backend->new;

foreach my $project (@ARGV) {
    my $sp;

    if ($project =~ /^([A-Z0-9\/]+)$/i) {
        my $project = uc($1);

        print STDERR 'Fetching project ', $project, "\n" if $verbose;
        $sp = OMP::DB::MSB->new(DB => $db, ProjectID => $project)->fetchSciProg(1);
    }
    elsif (-e $project) {
        print STDERR 'Reading file ', $project, "\n" if $verbose;
        $sp = OMP::SciProg->new(FILE => $project);
    }
    else {
        print STDERR 'Invalid project / not a file: ', $project, "\n";
        exit 1;
    }

    die 'Science program is undefined' unless defined $sp;

    $sp->apply_xslt('toml_summary.xslt');
}

__END__

=head1 COPYRIGHT

Copyright (C) 2018 East Asian Observatory
All Rights Reserved.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful,but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc.,51 Franklin
Street, Fifth Floor, Boston, MA  02110-1301, USA

=cut
