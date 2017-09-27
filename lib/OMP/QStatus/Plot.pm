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
use OMP::QStatus qw/query_queue_status/;

our @EXPORT_OK = qw/create_queue_status_plot/;

=item create_queue_status_plot($proj_msb, $utmin, $utmax, %opts)

Generate a plot showing MSB queue status via Astro::SourcePlot.

Takes the 3 arguments from OMP::QStatus::query_queue_status
(in "return_proj_msb" mode), plus the following options:

=over 4

=item output

Output file (passed on to Astro::SourcePlot::sourceplot).

=item hdevice

PGPLOT device (passed on to Astro::SourcePlot::sourceplot).

=back

=cut

sub create_queue_status_plot {
    my $proj_msb = shift;
    my $utmin = shift;
    my $utmax = shift;
    my %opt = @_;

    # Extract plotting options from options hash.
    my $output = $opt{'output'} || '';
    my $hdevice = $opt{'hdevice'} || '/XW';

    # Collect the coordinates from each MSB found.
    my @coords = ();

    foreach my $proj (sort keys %$proj_msb) {
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

    die 'No observations found' unless @coords;

    # Calculate time plotting range.
    my $time_range = $utmax - $utmin;
    my $time_mid = localtime($utmin->epoch() + $time_range / 2);
    $time_mid = $time_mid->hour() * 3600
              + $time_mid->minute() * 60
              + $time_mid->second();

    $time_mid = 24 * 3600 - $time_mid if $time_mid > 12 * 3600;

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
