#!/local/perl/bin/perl

=head1 NAME

listtargs - List targets from a science programme

=head1 SYNOPSIS

    listtargs -h
    listtargs U/06A/H32
    listtargs h32.xml

=head1 DESCRIPTION

This program extracts all the targets from a science program and
lists them to standard out with details of the RA/Dec and current
airmass. It also checks for internal consistency by comparing targets
that have identical names.

Extremely useful when validating orbital elements.

=head1 OPTIONS

The following options are supported:

=over 4

=item B<science programme>

The main argument is the file containing the science program. If the file does not
exist and the string does not a file extension (.xml) it is assumed to refer to
an actual project ID. In that case the project password is requested and an attempt
is made to retrieve the science programme for target extraction.

=item B<-version>

Report the version number.

=item B<-help>

Display the help information.

=item B<-man>

Display the full manual page.

=item B<-region>

Produce a list of regions to be observed.

=item B<-format> stcs | ast | moc-json | moc-text | moc-fits

Selects the format in which to report the regions.  Only required if
the format cannot be inferred from the output name.

=item B<-output> filename

Output filename for region files.  Write to standard output if not
specified, defaulting to STCS format.

=item B<-mocorder>

Maximum MOC order if writing a region in MOC format.

=item B<-type> new | progress | complete

Outputs only regions in the specified state.

=item B<-plot>

Display a plot of regions instead of outputting a text description.

=item B<-plottingmethod> separate | cmpregion

Allows regions to be plotted separately to avoid problems
plotting AST CmpRegions.

=item B<-plottingsystem> fk5 | gal

Selects coordinate system in which to plot.

Note: when WORKAROUND_BOUNDS is on to avoid problems calculating
the boundaries of AST regions, the bounds are only calculated
for FK5 coordinates.

=item B<-plottingbounds>

Specify explit plotting boundaries, comma separated, in degrees,
eg: -6,6,-4,4.

=back

=cut

# List all targets in a science program
use strict;
use warnings;
use IO::File;
use Pod::Usage;
use Getopt::Long;

# Locate the OMP software through guess work
use FindBin;
use lib "$FindBin::RealBin/../lib";

# Must load AST early to avoid problems with PGPLOT.
# Therefore load OMP::SpRegion now.
use OMP::SpRegion;
use Starlink::ATL::MOC qw/write_moc_fits/;

# External modules
use DateTime;

# OMP classes
use OMP::DB::Backend;
use OMP::DB::MSB;
use OMP::SciProg;
use OMP::DB::Project;

our $VERSION = '2.000';

# Options
my ($format, $mode_type, $plotting_method, $plotting_system,
    $help, $man, $version, $mode_region,
    $mode_plot, $plotting_bounds, $moc_order, $region_output)
= (undef, undef, 'cmpregion', 'fk5');

my $status = GetOptions(
    "help" => \$help,
    "man" => \$man,
    "version" => \$version,
    "region" => \$mode_region,
    "plot" => \$mode_plot,
    'format=s' => \$format,
    'output=s' => \$region_output,
    'mocorder=i' => \$moc_order,
    'type=s' => \$mode_type,
    'plottingmethod=s' => \$plotting_method,
    'plottingsystem=s' => \$plotting_system,
    'plottingbounds=s' => \$plotting_bounds,
);

pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

if ($version) {
    print "omplisttargs - List targets found in science programme\n";
    print "Version: ", $VERSION, "\n";
    exit;
}

my $db = OMP::DB::Backend->new;

# Read the science program in
my $file = shift(@ARGV);

my $sp;
if (-e $file) {
    # looks to be a filename
    $sp = OMP::SciProg->new(FILE => $file);
}
elsif (OMP::DB::Project->new(DB => $db, ProjectID => $file)->verifyProject()) {
    # we have a project ID - we need to get permission
    print STDERR "Retrieving science programme $file\n";
    $sp = OMP::DB::MSB->new(DB => $db, ProjectID => $file)->fetchSciProg(1);
}
else {
    die "Supplied argument ($file) is neither a file nor a project ID\n";
}

# Reference time
my $dt = DateTime->now;

# Determine which type of report is required.
if ($mode_region || $mode_plot) {
    region_report($sp);
    exit(0);
}

# Otherwise fall through to default report type.

my %targets;
my @targnames;

for my $msb ($sp->msb) {
    my $info = $msb->info;
    my @obs = $info->observations;

    for my $o (@obs) {
        my $c = $o->coords;
        $c->datetime($dt);
        next if $c->type eq 'CAL';

        if (exists $targets{$c->name}) {
            # exists so compare
            my $dist = $c->distance($targets{$c->name}->[0]);
            if ($dist->arcsec > 1) {
                print "-->>>> Target "
                    . $c->name
                    . " duplicated but with coordinates that differ by "
                    . sprintf("%.1f", $dist->arcsec)
                    . " arcsec\n";
                push(@{$targets{$c->name}}, $c);
            }
        }
        else {
            push(@targnames, $c->name);
            $targets{$c->name} = [$c];
        }
    }

}

# Now dump the current values
print("Target                RA(J2000)   Dec(J2000)    Airmass   Type\n");
for my $n (@targnames) {
    for my $c (@{$targets{$n}}) {
        my ($ra, $dec) = $c->radec;
        printf("%-20s %s  %s   %6.3f   %s\n",
            $n, $ra, $dec, $c->airmass, $c->type);
    }
}


# Subroutine to produce the region report type.
sub region_report {
    my $sp = shift;

    my $region = OMP::SpRegion->new($sp);
    unless (defined $region) {
        print STDERR "No regions found\n";
        exit(0);
    }

    if ($mode_region) {
        if (defined $format) {
            $format = lc $format;
        }
        else {
            if ((not defined $region_output) or ($region_output =~ /\.stcs/)) {
                $format = 'stcs';
            }
            elsif ($region_output =~ /\.ast/) {
                $format = 'ast';
            }
            elsif ($region_output =~ /\.json/) {
                $format = 'moc-json';
            }
            elsif ($region_output =~ /\.txt/) {
                $format = 'moc-text';
            }
            elsif ($region_output =~ /\.fits/) {
                $format = 'moc-fits';
            }
            else {
                die 'Region output format not specified';
            }
        }

        if ($format eq 'stcs') {
            $region->write_stcs(type => $mode_type, filename => $region_output);
        }
        elsif ($format eq 'ast') {
            $region->write_ast(type => $mode_type, filename => $region_output);
        }
        elsif ($format =~ /^moc-/i) {
            my %moc_opts = (type => $mode_type, order => $moc_order);
            my $moc = $region->get_moc(%moc_opts);

            if (($format eq 'moc-json') or ($format eq 'moc-text')) {
                unless (defined $region_output) {
                    print $moc->GetMocString(($format eq 'moc-json') ? 1 : 0);
                }
                else {
                    my $fh = IO::File->new($region_output, 'w');
                    die 'Could not open output file' unless defined $fh;
                    print $fh $moc->GetMocString(
                        ($format eq 'moc-json') ? 1 : 0);
                    $fh->close();
                }
            }
            elsif ($format eq 'moc-fits') {
                write_moc_fits($moc, ($region_output // '-'));
            }
            else {
                die 'Unknown MOC format ' . $format;
            }
        }
        else {
            die 'Unknown region output format ' . $format;
        }
    }

    if ($mode_plot) {
        require PGPLOT;
        require Starlink::AST::PGPLOT;

        my $pgdev = PGPLOT::pgopen('/xserve');
        PGPLOT::pgwnad(0, 1, 0, 1);
        PGPLOT::pgqwin(my $x1, my $y1, my $x2, my $y2);

        $region->plot_pgplot(
            type => $mode_type,
            method => $plotting_method,
            system => $plotting_system,
            bounds => $plotting_bounds
        );

        PGPLOT::pgend();
    }
}

__END__

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001-2005 Particle Physics and Astronomy Research Council.
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
