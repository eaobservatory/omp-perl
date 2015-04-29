=head1 NAME

OMP::QStatus::Plot - Observing queue status plotting module

=head1 SUBROUTINES

=over 4

=cut

package OMP::QStatus::Plot;

use strict;

use base 'Exporter';

# Environment settings for PGPLOT.
$ENV{PGPLOT_DIR} = '/star/bin' unless exists $ENV{PGPLOT_DIR};
$ENV{PGPLOT_FONT} = '/star/bin/grfont.dat' unless exists $ENV{PGPLOT_FONT};

use Astro::SourcePlot qw/sourceplot/;
use OMP::DBbackend;
use OMP::ProjAffiliationDB qw/@AFFILIATIONS/;
use OMP::QStatus qw/query_queue_status/;

our @EXPORT_OK = qw/create_queue_status_plot/;

=item create_queue_status_plot(%opts)

Generate a plot showing MSB queue status via Astro::SourcePlot.

Options other than the following are passed on to
OMP::QStatus::query_queue_status.

=over 4

=item affiliation

Affiliation code.

=item outout

Output file (passed on to Astro::SourcePlot::sourceplot).

=item output_header

Text to be printed before the image is output.

=item device

PGPLOT device (passed on to Astro::SourcePlot::sourceplot).

=back

=cut

sub create_queue_status_plot {
    my %opt = @_;

    # Are we searching for a particular affiliation?  If so read the list
    # of project affiliations.
    my $affiliation = delete $opt{'affiliation'};
    my $affiliations = undef;
    if ($affiliation) {
        die 'Unknown affiliation "' . $affiliation .'"'
            unless grep {$_ eq $affiliation} @AFFILIATIONS;

        my $affiliation_db = new OMP::ProjAffiliationDB(
            DB => new OMP::DBbackend());
        $affiliations = $affiliation_db->get_all_affiliations();
    }

    # Extract plotting options from options hash.
    my $output = delete $opt{'output'} || '';
    my $hdevice = delete $opt{'hdevice'} || '/XW';
    my $output_header = delete $opt{'output_header'};

    # Pass remaining options to query_queue_status.
    my ($proj_msb, $utmin, $utmax) = query_queue_status(
        return_proj_msb => 1, %opt);

    # Collect the coordinates from each MSB found.
    my @coords = ();

    foreach my $proj (sort keys %$proj_msb) {
        if (defined $affiliation) {
            next unless exists $affiliations->{$proj}->{$affiliation};
        }

        foreach my $msb (values %{$proj_msb->{$proj}}) {
            foreach my $obs ($msb->observations()) {
                foreach my $coord ($obs->coords()) {
                    # Add project ID to the start of the source name.
                    $coord->name($proj . ': ' . $coord->name());

                    push @coords, $coord;
                }
            }
        }
    }

    # Calculate time plotting range.
    my $time_range = $utmax - $utmin;
    my $time_mid = localtime($utmin->epoch() + $time_range / 2);
    $time_mid = $time_mid->hour() * 3600
              + $time_mid->minute() * 60
              + $time_mid->second();

    $time_mid = 24 * 3600 - $time_mid if $time_mid > 12 * 3600;

    # Output header once we are ready to create the plot.
    if (defined $output_header) {
        local $| = 1;
        print $output_header;
    }

    # Create the plot.
    sourceplot(
        coords => \@coords,
        objdot => 0,
        annotrack => 0,
        start => $utmin,
        end => $utmax,
        plot_center => $time_mid,
        plot_int => $time_range / 2,
        hdevice => $hdevice,
        output => $output,
    );
}


1;

__END__

=back

=head1 COPYRIGHT

Copyright (C) 2015 East Asian Observatory.
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
