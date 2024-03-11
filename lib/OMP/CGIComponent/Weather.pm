package OMP::CGIComponent::Weather;

=head1 NAME

OMP::CGIComponent::Weather - Web display of weather information

=head1 SYNOPSIS

    use OMP::CGIComponent::Weather;
    my $comp = OMP::CGIComponent::Weather->new(page => $page);
    my ($title, $url) = $comp->wvm_graph;
    my ($title, $url) = $comp->tau_plot;

=head1 DESCRIPTION

Helper methods for displaying web pages that include weather
information.

=cut

use 5.006;
use strict;
use warnings;
use Carp;

use OMP::Config;
use OMP::DateTools;
use OMP::General;
use Time::Seconds qw/ONE_DAY/;

use base qw/OMP::CGIComponent/;

$| = 1;

=head1 Routines

=over 4

=item B<extinction_plot>

Return information for displaying an extinction plot.

    my ($title, $url) = $comp->extinction_plot($utdate);

Takes a UT date string as the only argument.

=cut

sub extinction_plot {
    my $self = shift;
    my $utdate = shift;

    my $extinction_plot_dir = OMP::Config->getData('extinction-plot-url');

    my $gifdate = $utdate;
    $gifdate =~ s/-//g;
    $gifdate = substr($gifdate, 0, 8);

    return 'WFCAM atmospheric extinction for camera 1',
        "$extinction_plot_dir/trans_${gifdate}_cam1.png";
}

=item B<forecast_plot>

Return information for displaying a forecast plot.

    my ($title, $url) = $comp->forecast_plot($utdate);

Takes a UT date string as the only argument.

=cut

sub forecast_plot {
    my $self = shift;
    my $utdate = shift;

    my $forecast_plot_dir = OMP::Config->getData('forecast-plot-url');

    my $gifdate = $utdate;
    $gifdate =~ s/-//g;
    $gifdate = substr($gifdate, 0, 8);
    $gifdate =~ /(\d{4})(\d\d)(\d\d)/a;
    $gifdate = "$1-$2-$3";

    return 'MKWC forecast',
        "$forecast_plot_dir/${gifdate}.jpg";
}

=item B<meteogram_plot>

Return information for displaying a meteogram plot.

    my ($title, $url) = $comp->meteogram_plot($utdate);

Takes a UT date string as the only argument.

=cut

sub meteogram_plot {
    my $self = shift;
    my $utdate = shift;

    my $gifdate = $utdate;
    $gifdate =~ s/-//g;
    $gifdate = substr($gifdate, 0, 8);
    $gifdate =~ /(\d{4})(\d\d)(\d\d)/a;
    $gifdate = "$1-$2-$3";

    my $meteogram_plot_dir = OMP::Config->getData('meteogram-plot-url');

    return 'EAO meteogram',
        "$meteogram_plot_dir/${gifdate}.png";
}

=item B<opacity_plot>

Return information for displaying an opacity plot.

    my ($title, $url) = $comp->opacity_plot($utdate);

Takes a UT date string as the only argument.

=cut

sub opacity_plot {
    my $self = shift;
    my $utdate = shift;

    my $opacity_plot_dir = OMP::Config->getData('opacity-plot-url');

    my $gifdate = $utdate;
    $gifdate =~ s/-//g;
    $gifdate = substr($gifdate, 0, 8);
    $gifdate =~ /(\d{4})(\d\d)(\d\d)/a;
    $gifdate = "$1-$2-$3";

    return 'Maunakea opacity',
        "$opacity_plot_dir/${gifdate}.png";
}


=item B<seeing_plot>

Return information for displaying a seeing plot.

  my ($title, $url) = $comp->seeing_plot( $utdate );

Takes a UT date string as the only argument.

=cut

sub seeing_plot {
    my $self = shift;
    my $utdate = shift;

    my $seeing_plot_dir = OMP::Config->getData('seeing-plot-url');

    my $gifdate = $utdate;
    $gifdate =~ s/-//g;
    $gifdate = substr($gifdate, 0, 8);

    return 'K-band seeing corrected to zenith',
        "$seeing_plot_dir/$gifdate.png";
}

=item B<tau_plot>

Return information for displaying a tau plot.

    my ($title, $url) = $comp->tau_plot($utdate);

Takes a UT date string as the only argument.  Returns undef if no tau plot
exists for the given date.

=cut

sub tau_plot {
    my $self = shift;
    my $utdate = shift;

    # Setup tau fits image info
    my $dir = "/WWW/omp/data/taufits";
    my $www = "/data/taufits";
    my $calibpage = "https://www.eaobservatory.org/jcmt/instrumentation/continuum/scuba-2/calibration/";
    my $gifdate = $utdate;
    $gifdate =~ s/-//g;
    $gifdate = substr($gifdate, 0, 8);

    my $gif;
    if (-e "$dir/$gifdate" . "new.gif") {
        $gif = $gifdate . "new.gif";
    }
    elsif (-e "$dir/$gifdate" . "new350.gif") {
        $gif = $gifdate . "new350.gif";
    }

    if ($gif) {
        return 'Opacity fit', "$www/$gif";
    }
    else {
        return undef, undef;
    }
}

=item B<transparency_plot>

Return information for displaying a transparency plot.

    my ($title, $url) = $comp->transparency_plot($utdate);

Takes a UT date string as the only argument.

=cut

sub transparency_plot {
    my $self = shift;
    my $utdate = shift;

    my $transparency_plot_dir = OMP::Config->getData('transparency-plot-url');

    my $gifdate = $utdate;
    $gifdate =~ s/-//g;
    $gifdate = substr($gifdate, 0, 8);
    $gifdate =~ /(\d{4})(\d\d)(\d\d)/a;
    $gifdate = "$1-$2-$3";

    return 'CFHT transparency',
        "$transparency_plot_dir/${gifdate}.png";
}

=item B<wvm_graph>

Return information for displaying a wvm graph.  Takes UT start and end dates as
the only arguments

    my ($title, $url) = $comp->wvm_graph('2003-03-22', '2003-03-25');

UT end date is optional and if not provided the graph will display for
a 24 hour period beginning on the UT start date.

=cut

sub wvm_graph {
    my $self = shift;
    my $wvmstart = shift;
    my $wvmend = shift;

    # Get WVM script URL
    my $wvm_url = OMP::Config->getData('wvm-url');

    # Convert dates to time objects
    $wvmstart = OMP::DateTools->parse_date($wvmstart);
    $wvmend = OMP::DateTools->parse_date($wvmend);

    unless ($wvmstart) {
        return undef, undef;
    }
    # End date default is the end of the start date
    ($wvmend) or $wvmend = $wvmstart + (ONE_DAY - 1);

    return 'WVM graph',
        "${wvm_url}?datestart=" . $wvmstart->datetime . "&dateend=" . $wvmend->datetime;
}

=item B<zeropoint_plot>

Return information for displaying a zeropoint plot.

  my ($title, $url) = zeropoint_plot( $utdate );

Takes a UT date string as the only argument.

=cut

sub zeropoint_plot {
  my $utdate = shift;

  my $zeropoint_plot_dir = OMP::Config->getData( 'zeropoint-plot-url' );

  my $gifdate = $utdate;
  $gifdate =~ s/-//g;
  $gifdate = substr( $gifdate, 0, 8 );

  return 'WFCAM zero points for camera 1',
    "$zeropoint_plot_dir/zero_${gifdate}_cam1.png";
}

1;

__END__

=back

=head1 AUTHOR

Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2004 Particle Physics and Astronomy Research Council.
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
