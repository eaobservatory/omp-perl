package OMP::CGI::Weather;

=head1 NAME

OMP::CGI::Weather - Web display of weather information

=head1 SYNOPSIS

  use OMP::CGI::Weather;

  $html = OMP::CGI::Weather::wvm_graph_code;
  $html = OMP::CGI::Weather::tau_plot_code;

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

$| = 1;

=head1 Routines

=over 4

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

  # Convert dates to time objects
  $wvmstart = OMP::General->parse_date($wvmstart);
  $wvmend = OMP::General->parse_date($wvmend);

  my $string;

  if (! $wvmstart) {
    $string .= "Error: No start date for WVM graph provided.";
  } else {
    ($wvmend) or $wvmend = $wvmstart;
    my $wvmformat = "%Y-%m-%d"; # Date format for wvm graph URL
    $string .= "<a name='wvm'></a>";
    $string .= "<br>";
    $string .= "<strong class='small_title'>WVM graph</strong><p>";
    $string .= "<div align=left>";
    $string .= "<img src='http://www.jach.hawaii.edu/JACpublic/JCMT/software/bin/wvm/wvm_graph.pl?datestart=". $wvmstart->strftime($wvmformat) ."&timestart=00:00:00&dateend=". $wvmend->strftime($wvmformat) ."&timeend=23:59:59'><br><br></div>";
  }
  return $string;
}

=cut

=back

=head1 AUTHOR

Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2004 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;

