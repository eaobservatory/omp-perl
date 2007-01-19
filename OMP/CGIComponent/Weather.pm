package OMP::CGIComponent::Weather;

=head1 NAME

OMP::CGIComponent::Weather - Web display of weather information

=head1 SYNOPSIS

  use OMP::CGIComponent::Weather;

  $html = OMP::CGIComponent::Weather::wvm_graph_code;
  $html = OMP::CGIComponent::Weather::tau_plot_code;

=head1 DESCRIPTION

Helper methods for displaying web pages that include weather
information.

=cut

use 5.006;
use strict;
use warnings;
use Carp;

use OMP::Config;
use OMP::General;
use Time::Seconds qw(ONE_DAY);

$| = 1;

=head1 Routines

=over 4

=item B<seeing_plot_code>

Return HTML snippet for displaying a seeing plot.

  $html = seeing_plot_code( $utdate );

Takes a UT date string as the only argument.

=cut

sub seeing_plot_code {
  my $utdate = shift;

  my $seeing_plot_dir = OMP::Config->getData( 'seeing-plot-url' );

  my $gifdate = $utdate;
  $gifdate =~ s/-//g;
  $gifdate = substr( $gifdate, 0, 8 );

  my $URL = "$seeing_plot_dir/$gifdate.png";

  my $string = "<a name='seeing'></a>\n";
  $string .= "<br>";
  $string .= "<strong class='small_title'>K-band seeing corrected to zenith</strong><p>";
  $string .= "<div align=left>";
  $string .= "<img src='$URL'><br><br></p>";

  return $string;
}

=item B<tau_plot_code>

Return HTML snippet for displaying a tau plot.

  $html = tau_plot_code($utdate);

Takes a UT date string as the only argument.  Returns undef if no tau plot
exists for the given date.

=cut

sub tau_plot_code {
  my $utdate = shift;

  # Setup tau fits image info
  my $dir = "/WWW/omp/data/taufits";
  my $www = OMP::Config->getData('omp-url') . "/data/taufits";
  my $calibpage = "http://www.jach.hawaii.edu/JACpublic/JCMT/Continuum_observing/SCUBA/astronomy/calibration/calib.html";
  my $gifdate = $utdate;
  $gifdate =~ s/-//g;
  $gifdate = substr($gifdate,0,8);

  my $gif;
  if (-e "$dir/$gifdate" . "new.gif") {
    $gif = $gifdate . "new.gif";
  } elsif (-e "$dir/$gifdate" . "new350.gif") {
    $gif = $gifdate . "new350.gif";
  }

  if ($gif) {
    return "<a name='taufits'></a>"
      ."<a href='$calibpage'><img src='$www/$gif'>"
	."<br>Click here to visit the calibration page</a>";
  } else {
    return undef;
  }
}

=item B<wvm_graph_code>

Return HTML snippet for displaying a wvm graph.  Takes UT start and end dates as
the only arguments

  $wvm_html = wvm_graph_code('2003-03-22', '2003-03-25');

UT end date is optional and if not provided the graph will display for
a 24 hour period beginning on the UT start date.

=cut

sub wvm_graph_code {
  my $wvmstart = shift;
  my $wvmend = shift;

  # Get WVM script URL
  my $wvm_url = OMP::Config->getData('wvm-url');

  # Convert dates to time objects
  $wvmstart = OMP::General->parse_date($wvmstart);
  $wvmend = OMP::General->parse_date($wvmend);

  my $string;

  if (! $wvmstart) {
    $string .= "Error: No start date for WVM graph provided.";
  } else {
    # End date default is the end of the start date
    ($wvmend) or $wvmend = $wvmstart + (ONE_DAY - 1);

    $string .= "<a name='wvm'></a>";
    $string .= "<br>";
    $string .= "<strong class='small_title'>WVM graph</strong><p>";
    $string .= "<div align=left>";
    $string .= "<img src='${wvm_url}?datestart=". $wvmstart->datetime ."&dateend=". $wvmend->datetime ."'><br><br></div>";
  }
  return $string;
}

=item B<zeropoint_plot_code>

Return HTML snippet for displaying a zeropoint plot.

  $html = zeropoint_plot_code( $utdate );

Takes a UT date string as the only argument.

=cut

sub zeropoint_plot_code {
  my $utdate = shift;

  my $zeropoint_plot_dir = OMP::Config->getData( 'zeropoint-plot-url' );

  my $gifdate = $utdate;
  $gifdate =~ s/-//g;
  $gifdate = substr( $gifdate, 0, 8 );

  my $URL = "$zeropoint_plot_dir/zero_${gifdate}_cam1.png";

  my $string = "<a name='zeropoint'></a>\n";
  $string .= "<br>";
  $string .= "<strong class='small_title'>WFCAM zeropoints for camera 1</strong><p>";
  $string .= "<div align=left>";
  $string .= "<img src='$URL'><br><br></p>";

  return $string;
}

=cut

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
along with this program (see SLA_CONDITIONS); if not, write to the
Free Software Foundation, Inc., 59 Temple Place, Suite 330,
Boston, MA  02111-1307  USA

=cut

1;

