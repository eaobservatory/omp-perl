#!/local/perl-5.6/bin/perl
#
# WWW Observing Remotely Facility (WORF)
#  Graphic Creation and Delivery tool
#
# http://www.jach.hawaii.edu/JACpublic/UKIRT/software/worf/
#
# Requirements:
#  TBD
#
# Author: Brad Cavanagh (b.cavanagh@jach.hawaii.edu)

# Set up the environment for PGPLOT

BEGIN {
  $ENV{'PGPLOT_DIR'} = '/star/bin';
  $ENV{'PGPLOT_FONT'} = '/star/bin/grfont.dat';
  $ENV{'PGPLOT_GIF_WIDTH'} = 640;
  $ENV{'PGPLOT_GIF_HEIGHT'} = 480;
  $ENV{'PGPLOT_BACKGROUND'} = 'white';
  $ENV{'PGPLOT_FOREGROUND'} = 'black';
  $ENV{'HDS_SCRATCH'} = "/tmp";
}

# Bring in CGI module to allow us to change the MIME type and
# send all fatal error messages back to the browser.

use CGI;
use CGI::Carp qw/fatalsToBrowser/;

# Bring in OMP modules for user verification.

use lib qw( /jac_sw/omp/test/omp/msbserver );
#use OMP::CGI;

# Bring in ORAC module so we can figure out where the data
# files are, depending on the instrument and UT date.

use lib qw( /ukirt_sw/oracdr/lib/perl5 );
use ORAC::Inst::Defn qw/orac_configure_for_instrument/;

# Bring in PDL modules so we can display the graphic.

use PDL;
use PDL::IO::NDF;
use PDL::Graphics::PGPLOT;
use PDL::Graphics::LUT;

# Set up various variables.

$| = 1; # Make output unbuffered.
my @instruments = ( "cgs4", "ircam", "michelle", "ufti", "scuba" );
my @ctabs = lut_names();
my $query = new CGI;

my $ut;
  {
    my ($sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdist) = gmtime(time);
    $ut = ($year + 1900) . pad($month + 1, "0", 2) . pad($day, "0", 2);

# For demo purposes only.
#    $ut = "20020310";
  }

# Set up and verify $query variables.

my ( $q_file, $q_instrument, $q_obstype, $q_rstart, $q_rend, $q_cut,
     $q_xscale, $q_xstart, $q_xend, $q_yscale, $q_ystart, $q_yend,
     $q_type, $q_autocut, $q_xcrop, $q_xcropstart, $q_xcropend,
     $q_ycrop, $q_ycropstart, $q_ycropend, $q_lut);

  if($query->param('file')) {

# The 'file' parameter must be just a filename. No pipes, slashes, or other weird
# characters that can allow for shell manipulation. If it doesn't match the proper
# format, set it to an empty string.

    # first, strip out anything that's not a letter, a digit, an underscore, or a period
    
    my $t_file = $query->param('file');
    $t_file =~ s/[^a-zA-Z0-9\._]//g;
    
    # now check to make sure it's in some sort of format -- one or two letters, eight digits,
    # an underscore, and ending with .sdf
    
    if($t_file =~ /^[a-zA-Z]{1,2}\d{8}_\w+\.sdf$/) {
      $q_file = $t_file;
    } else {
      $q_file = '';
    }
  } else {
    $q_file = '';
  }

  if($query->param('instrument')) {

# The 'instrument' parameter must match one of the strings listed in the @instruments
# array. If it doesn't, set it to an empty string.
  
    # first, strip out anything that's not a letter or a number
    
    my $t_instrument = $query->param('instrument');
    $t_instrument =~ s/[^a-zA-Z0-9]//g;
    
    # this parameter needs to match exactly one of the strings listed in @instruments
    
    my $match = 0;
    
    foreach my $t_inst (@instruments) {
      if($t_instrument eq $t_inst) {
        $q_instrument = $t_inst;
        $match = 1;
      }
    }
    if ($match == 0) {
      $q_instrument = "";
    }
  } else {
    $q_instrument = '';
  }

  if($query->param('obstype')) {

# The 'obstype' parameter must be either 'raw' or 'reduced'.
# Default to 'reduced'.

    if($query->param('obstype') eq 'raw') {
      $q_obstype = 'raw';
    } else {
      $q_obstype = 'reduced';
    }
  } else {
    $q_obstype = 'reduced';
  }

  if($query->param('rstart')) {
    
# The 'rstart' parameter must be digits.

    $q_rstart = $query->param('rstart');
    $q_rstart =~ s/[^0-9]//g;
  } else {
    $q_rstart = 0;
  }

  if($query->param('rend')) {

# The 'rend' parameter must be digits.
    
    $q_rend = $query->param('rend');
    $q_rend =~ s/[^0-9]//g;
  } else {
    $q_rend = 0;
  }

  if($query->param('cut')) {

# The 'cut' parameter must be either 'horizontal' or 'vertical'.
# Default to 'horizontal'.
    
    if($query->param('cut') eq 'vertical') {
      $q_cut = 'vertical';
    } else {
      $q_cut = 'horizontal';
    }
  } else {
    $q_cut = 'horizontal';
  }
  
  if($query->param('xscale')) {

# The 'xscale' parameter must be either 'autoscaled' or 'set'.
# Default to 'autoscaled'.

    if($query->param('xscale') eq 'set') {
      $q_xscale = 'set';
    } else {
      $q_xscale = 'autoscaled';
    }
  } else {
    $q_xscale = 'autoscaled';
  }
  
  if($query->param('xstart')) {

# The 'xstart' parameter must be digits.
    
    $q_xstart = $query->param('xstart');
    $q_xstart =~ s/[^0-9\.]//g;
  } else {
    $q_xstart = 0;
  }
  
  if($query->param('xend')) {

# The 'xend' parameter must be digits.

    $q_xend = $query->param('xend');
    $q_xend =~ s/[^0-9\.]//g;
  } else {
    $q_xend = 0;
  }

  if($query->param('yscale')) {

# The 'yscale' parameter must be either 'autoscaled' or 'set'.
# Default to 'autoscaled'.

    if($query->param('yscale') eq 'set') {
      $q_yscale = 'set';
    } else {
      $q_yscale = 'autoscaled';
    }
  } else {
    $q_yscale = 'autoscaled';
  }
  
  if($query->param('ystart')) {

# The 'ystart' parameter must be digits.

    $q_ystart = $query->param('ystart');
    $q_ystart =~ s/[^0-9\.e\-]//g;
  } else {
    $q_ystart = 0;
  }

  if($query->param('yend')) {

# The 'yend' parameter must be digits.

    $q_yend = $query->param('yend');
    $q_yend =~ s/[^0-9\.e\-]//g;
  } else {
    $q_yend = 0;
  }
  
  if($query->param('type')) {

# The 'type' parameter must be either 'image' or 'spectrum'.
# Default to 'image'.

    if($query->param('type') eq 'spectrum') {
      $q_type = 'spectrum';
    } else {
      $q_type = 'image';
    }
  } else {
    $q_type = 'image';
  }
  
  if($query->param('autocut')) {

# The 'autocut' parameter must be digits.
# Default to '100'.

    $q_autocut = $query->param('autocut');
    $q_autocut =~ s/[^0-9\.]//g;
  } else {
    $q_autocut = 100;
  }
  
  if($query->param('xcrop')) {

# The 'xcrop' parameter must be either 'full' or 'crop'.
# Default to 'full'.

    if($query->param('xcrop') eq 'crop') {
      $q_xcrop = 'crop';
    } else {
      $q_xcrop = 'full';
    }
  } else {
    $q_xcrop = 'full';
  }
  
  if($query->param('xcropstart')) {

# The 'xcropstart' parameter must be digits.
# Default to '0'.

    $q_xcropstart = $query->param('xcropstart');
    $q_xcropstart =~ s/[^0-9\.]//g;
  } else {
    $q_xcropstart = 0;
  }
  
  if($query->param('xcropend')) {

# The 'xcropend' parameter must be digits.
# Default to '0'.

    $q_xcropend = $query->param('xcropend');
    $q_xcropend =~ s/[^0-9\.]//g;
  } else {
    $q_xcropend = 0;
  }
  
  if($query->param('xcrop')) {

# The 'ycrop' parameter must be either 'full' or 'crop'.
# Default to 'full'.

    if($query->param('ycrop') eq 'crop') {
      $q_ycrop = 'crop';
    } else {
      $q_ycrop = 'full';
    }
  } else {
    $q_ycrop = 'full';
  }
  
  if($query->param('ycropstart')) {

# The 'ycropstart' parameter must be digits.
# Default to '0'.

    $q_ycropstart = $query->param('ycropstart');
    $q_ycropstart =~ s/[^0-9\.]//g;
  } else {
    $q_ycropstart = 0;
  }
  
  if($query->param('ycropend')) {
    
# The 'ycropend' parameter must be digits.
# Default to '0'.

    $q_ycropend = $query->param('ycropend');
    $q_ycropend =~ s/[^0-9\.]//g;
  } else {
    $q_ycropend = 0;
  }
  
  if($query->param('lut')) {

# The 'lut' parameter must be one of the standard lookup tables.
# Default is 'standard'.
    
    # first, strip out anything that's not a letter or a number
    
    my $t_lut = $query->param('lut');
    $t_lut =~ s/[^a-zA-Z0-9]//g;
    
    # this parameter needs to match exactly one of the strings listed in @ctabs
    
    my $match = 0;
    
    foreach my $t_ctab (@ctabs) {
      if($t_lut eq $t_ctab) {
        $q_lut = $t_ctab;
        $match = 1;
      }
    }
    if ($match == 0) {
      $q_lut = 'heat';
    }
  } else {
    $q_lut = 'heat';
  }
  
  if($query->param('size')) {

# The 'size' parameter must be [128 | 640 | 960 | 1280]
# Default is '640'.

    my $t_size = $query->param('size');
    $t_size =~ s/[^0-9]//;
    $ENV{'PGPLOT_GIF_WIDTH'} = $t_size;
    $ENV{'PGPLOT_GIF_HEIGHT'} = $t_size * 3 / 4; # sorry, it's not 16x9. =)
  } else {
    $ENV{'PGPLOT_GIF_WIDTH'} = 640;
    $ENV{'PGPLOT_GIF_HEIGHT'} = 480;
  }

# And display the observation.

display_observation($q_file, $q_cut, $q_rstart, $q_rend, $q_xscale, $q_xstart, $q_xend,
                    $q_yscale, $q_ystart, $q_yend, $q_instrument, $q_type, $q_obstype,
                    $q_autocut, $q_xcrop, $q_xcropstart, $q_xcropend, $q_ycrop, $q_ycropstart,
                    $q_ycropend, $q_lut, $q_instrument);

sub display_observation {

# This subroutine displays a given observation.
#
# IN: $file: filename of observation to be displayed
#     $cut: whether the cut is horizontal or vertical (spectrum)
#     $rstart: starting row for cut (spectrum)
#     $rend: ending row for cut (spectrum)
#     $xscale: whether the x-dimension is autoscaled or set (spectrum)
#     $xstart: starting position for x-dimension (spectrum)
#     $xend: ending position for x-dimension (spectrum)
#     $yscale: whether the y-dimension is autoscaled or set (spectrum)
#     $ystart: starting position for y-dimension (spectrum)
#     $yend: ending position for y-dimension (spectrum)
#     $instrument: name of instrument
#     $type: type of display (image or spectrum)
#     $obstype: type of observaton (raw or reduced)
#     $autocut: scale data by cutting percentages (image)
#     $xcrop: whether the x-dimension is cropped or set (full or crop) (image)
#     $xcropstart: starting position for x-dimension (image)
#     $xcropend: ending position for x-dimension (image)
#     $ycrop: whether the y-dimension is cropped or set (full or crop) (image)
#     $ycropstart: starting position for y-dimension (image)
#     $ycropend: ending position for y-dimension (image)
#     $lut: look up table for colour tables (image)
#     $instrument: name of instrument
#
# OUT:
# none

  my($file, $cut, $rstart, $rend, $xscale, $xstart, $xend, $yscale, $ystart, $yend, $instrument, $type, $obstype, $autocut, $xcrop, $xcropstart, $xcropend, $ycrop, $ycropstart, $ycropend, $lut, $instrument) = @_;


  if($obstype eq 'raw') {
    # for the raw file, we need to look at the .i1 NDF (just giving the filename
    # will only get us the HDS container and not the NDF)
    $file =~ s/\.sdf$/\.i1/;
    $file = get_raw_directory($instrument, $ut) . "/" . $file;
  } else {
    $file = get_reduced_directory($instrument, $ut) . "/" . $file;
  }

  my $image = rndf($file);
  my ($xdim, $ydim) = dims $image;
  if(!defined($ydim) && ($type eq "image")) {
    $type = "spectrum";
  }
  undef $image;
  undef $xdim;
  undef $ydim;

  print $query->header(-type=>'image/gif');

  ($type eq "spectrum") ? plot_spectrum($file, $cut, $rstart, $rend, $xscale, $xstart, $xend, $yscale, $ystart, $yend) : plot_image($file, $autocut, $xcrop, $xcropstart, $xcropend, $ycrop, $ycropstart, $ycropend, $lut);

} # end sub display_observation

sub plot_image {

# This subroutine plots an image
#
# IN: $file: full filename to be displayed.
#     $autocut: scale data by cutting percentages
#     $xcrop: whether the x-dimension is cropped or set (full or crop)
#     $xcropstart: starting position for x-dimension
#     $xcropend: ending position for x-dimension
#     $ycrop: whether the y-dimension is cropped or set (full or crop)
#     $ycropstart: starting position for y-dimension
#     $ycropend: ending position for y-dimension
#     $lut: lookup table for colour table
#
# OUT: none

  my ($file, $autocut, $xcrop, $xcropstart, $xcropend, $ycrop, $ycropstart, $ycropend, $lut) = @_;
  my ($xdim, $ydim);
  my $gif = "$gifdir" . "tmp$$.gif";
  my $image = rndf($file, 1);

  my $opt = {AXIS => 1,
             JUSTIFY => 1,
             LINEWIDTH => 1};

  ($xdim, $ydim) = dims $image;

  if(!defined($ydim)) {

# This should actually never happen, since this check is also done just before the
# call to plot_spectrum(), but it never hurts to make sure, since this subroutine
# will fail if a 1D image is sent to it.

    plot_spectrum($file, "horizontal", 1, $xdim--, "autoscaled", undef, undef, "autoscaled", undef, undef);
    return;
  }

  my $hdr = $image->gethdr;
  my $title = $$hdr{Title};

  $xdim--;
  $ydim--;

  if($autocut != 100) {
    my ($mean, $rms, $median, $min, $max) = stats($image);
    if($autocut == 99) {
      $image = $image->clip(($mean - 2.6467 * $rms), ($mean + 2.6467 * $rms));
    } elsif($autocut == 98) {
      $image = $image->clip(($mean - 2.2976 * $rms), ($mean + 2.2976 * $rms));
    } elsif($autocut == 95) {
      $image = $image->clip(($mean - 1.8318 * $rms), ($mean + 1.8318 * $rms));
    } elsif($autocut == 90) {
      $image = $image->clip(($mean - 1.4722 * $rms), ($mean + 1.4722 * $rms));
    } elsif($autocut == 80) {
      $image = $image->clip(($mean - 1.0986 * $rms), ($mean + 1.0986 * $rms));
    } elsif($autocut == 70) {
      $image = $image->clip(($mean - 0.8673 * $rms), ($mean + 0.8673 * $rms));
    } elsif($autocut == 50) {
      $image = $image->clip(($mean - 0.5493 * $rms), ($mean + 0.5493 * $rms));
    }
  }

  if($xcrop eq 'crop') {
    if((($xcropstart == 0) && ($xcropend == 0)) || ($xcropstart >= $xcropend)) {
      $xcropstart = 0;
      $xcropend = $xdim;
    } else {
    }
  } else {
    $xcropstart = 0;
    $xcropend = $xdim;
  }

  if($ycrop eq 'crop') {
    if((($ycropstart == 0) && ($ycropend == 0)) || ($ycropstart >= $ycropend)) {
      $ycropstart = 0;
      $ycropend = $ydim;
    } else {
    }
  } else {
    $ycropstart = 0;
    $ycropend = $ydim;
  }
  
  dev "-/GIF";
  env($xcropstart, $xcropend, $ycropstart, $ycropend, $opt);
  label_axes(undef, undef, $title);
  ctab(lut_data($lut));
  imag $image;
  dev "/null";

} # end sub plot_image

sub plot_spectrum {

# This subroutine plots a spectrum.
#
# IN: $file: full pathname to be displayed.
#     $cut: direction of cut (horizontal || vertical)
#     $rstart: start row of cut
#     $rend: end row of cut
#     $xscale: type of scaling in x-direction (autoscaled || set)
#     $xstart: lower bound of units in x-direction
#     $xend: upper bound of units in x-direction
#     $yscale: type of scaling in y-direction (autoscaled || set)
#     $ystart: lower bound of units in y-durection
#     $yend: upper bound of units in y-direction
#
# OUT: none

  my ($file, $cut, $rstart, $rend, $xscale, $xstart, $xend, $yscale, $ystart, $yend) = @_;
  my $line;
  my $templine;
  my $xdim;
  my $ydim;
  my $image = rndf($file);
  my $gif = "$gifdir" . "tmp$$.gif";

  my $opt = {LINEWIDTH => 1};

  ($xdim, $ydim) = dims $image;

# We have to check if the input data is 1D or 2D
  if(!defined($ydim)) {

# It's 1D

    dev "-/GIF";

# Grab the axis information

    my $hdr = $image->gethdr;
    my $title = $$hdr{Title};
    my $axis = ${$$hdr{Axis}}[0];
    my $axishdr = $axis->gethdr;
    my $units = $$axishdr{Units};
    my $label = $$axishdr{Label};

    if($xscale eq 'set') {
      if((($xstart == 0) && ($xend == 0)) || ($xstart >= $xend)) {
        $xstart = min($axis);
        $xend = max($axis);
      } else {
      }
    } else {
      $xstart = min($axis);
      $xend = max($axis);
    }
  
    if($yscale eq 'set') {
      if((($ystart == 0) && ($yend == 0)) || ($ystart >= $yend)) {
        $ystart = min($image);
        $yend = max($image);
      } else {
      }
    } else {
      $ystart = min($image);
      $yend = max($image);
    }
  
    env($xstart, $xend, $ystart, $yend);
    label_axes( "$label ($units)", undef, $title);
    line $axis, $image, $opt;
    dev "/null";

  } else {

# It's 2D

    $xdim--;
    $ydim--;
    
    my $hdr = $image->gethdr;
    my $title = $$hdr{Title};
    label_axes(undef, undef, $title);

    if ($cut eq "vertical") {
      for(my $i = $rstart; $i <= $rend; $i++) {
        $templine = $image->slice("$i,")->copy;
        $line += $templine;
      }
      $line = $line / ($rend - $rstart + 1);
    } else {
      for(my $i = $rstart; $i <= $rend; $i++) {
        $templine = $image->slice(",$i")->copy;
        $line += $templine;
      }
      $line = $line / ($rend - $rstart + 1);
    };
    
    if($xscale eq 'set') {
      if((($xstart == 0) && ($xend == 0)) || ($xstart >= $xend)) {
        $xstart = 0;
        $xend = $xdim;
      } else {
      }
    } else {
      $xstart = 0;
      $xend = $xdim;
    }
    
    if($yscale eq 'set') {
      if((($ystart == 0) && ($yend == 0)) || ($ystart >= $yend)) {
        $ystart = min($line);
        $yend = max($line);
      } else {
      }
    } else {
      $ystart = min($line);
      $yend = max($line);
    }
    
    dev "-/GIF";
    env ($xstart, $xend, $ystart, $yend);
    line $line, $opt;
    dev "/null";
    
  }

} # end sub plot_spectrum

sub get_raw_directory {
# A simplified way to retrieve the raw data directory given an
# instrument and a UT date.

  my $instrument = shift;
  my $ut = shift;

  my %options;
  $options{'ut'} = $ut;
  orac_configure_for_instrument( uc( $instrument ), \%options );

  return $ENV{"ORAC_DATA_IN"};
}

sub get_reduced_directory {
# A simplified way to retrieve the reduced data directory given an
# instrument and a UT date.

  my $instrument = shift;
  my $ut = shift;

  my %options;
  $options{'ut'} = $ut;
  orac_configure_for_instrument( uc( $instrument ), \%options );

  return $ENV{"ORAC_DATA_OUT"};
}

sub pad {
  my ($string, $character, $endlength) = @_;
  my $result = ($character x ($endlength - length($string))) . $string;
}

