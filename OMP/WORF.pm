package OMP::WORF;

=head1 NAME

OMP::WORF - WWW Observing Remotely Facility non-CGI functions

=head1 SYNOPSIS

use OMP::WORF;

=head1 DESCRIPTION

This class handles all the routines that deal with image creation,
display, and summary for WORF. CGI-related routines for WORF are
handled in OMP::WORF::CGI.

=cut

use strict;
use warnings;
use Carp;

use OMP::Info::Obs;
use OMP::Config;
use OMP::Error qw/ :try /;

use OMP::CGI;

# Bring in PDL modules so we can display the graphic.
use PDL::Lite;
use PDL::Primitive;
use PDL::ImageND;
use PDL::Ufunc;
use PDL::IO::NDF;
use PDL::Graphics::PGPLOT;
#use PDL::Graphics::PGPLOT::Window;
use PDL::Graphics::LUT;

our $VERSION = (qw$Revision$ )[1];

require Exporter;

our @ISA = qw/Exporter/;
our @EXPORTER = qw( );
our @EXPORT = qw/ worf_determine_class new plot obs parse_display_options
                  file_exists /;
our %EXPORT_TAGS = (
                    'all' => [ qw( @EXPORT ) ],
                    );

Exporter::export_tags(qw/ all /);

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

Object constructor. Takes a hash as argument, the keys of which can be
used to prepopulate the object. The key names must match the names of
the accessor methods (ignoring case). If they do not match they are
ignored (for now).

  $worf = new OMP::WORF( %args );

Arguments are optional.

=cut

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;

  my $worf = bless {
                    Obs => undef,
                    Suffix => undef,
                   }, $class;

  if( @_ ) {
    my %args = @_;

    # Use the constructors to populate the hash.
    for my $key (keys %args) {
      my $method = lc($key);
      if ($worf->can($method)) {
        $worf->$method( $args{$key} );
      }
    }
  }

  if( !defined( $worf->obs->inst_dhs ) || length( $worf->obs->inst_dhs . '' ) == 0 ) {
    # We don't have a fully-formed Info::Obs object, so try to
    # form one.
    my $adb = new OMP::ArchiveDB( DB => new OMP::DBbackend::Archive );
    my $instrument = $worf->obs->instrument;
    my $ut = $worf->obs->startobs->ymd;
    my $runnr = $worf->obs->runnr;
    my $newobs = $adb->getObs( instrument => $instrument,
                               ut => $ut,
                               runnr => $runnr );
    $worf->obs( $newobs );
  }

  # Re-bless the object with the right class, which will
  # be OMP::WORF::$inst_dhs
  my $newclass = "OMP::WORF::" . uc( $worf->obs->inst_dhs );
  bless $worf, $newclass;

  # Horrible taint removal step.
  $newclass =~ /(.+)/;
  $newclass = $1;

  eval "require $newclass";
  if( $@ ) { throw OMP::Error::FatalError "Could not load module $newclass: $@"; }

  return $worf;

}

=back

=head2 Accessor Methods

=over 4

=item B<obs>

The C<Info::Obs> object WORF will display.

  $obs = $worf->obs;
  $worf->obs( $obs );

Returned as a C<OMP::Info::Obs> object.

=cut

sub obs {
  my $self = shift;
  if( @_ ) {
    my $obs = shift;
    $self->{Obs} = $obs
      unless (! UNIVERSAL::isa( $obs, "OMP::Info::Obs" ) );
  }
  return $self->{Obs};
}

=item B<suffix>

The "best" file suffix that will be used for display.

  $suffix = $worf->suffix;
  $worf->suffix( $suffix );

When one observation can be associated with a number of reduced files,
WORF must know which of those reduced files to display. This method is
used to set the suffix of the file to display.

This suffix will always be returned in lower-case.

=cut

sub suffix {
  my $self = shift;
  if( @_ ) { $self->{Suffix} = lc(shift); }
  return $self->{Suffix};
}

=back

=head2 Public Methods

=over 4

=item B<plot>

Plots data.

  $worf->plot;

For the base class, this method throws an error. All plotting is handled
by subclasses.

=cut

sub plot {
  my $self = shift;

  my $instrument = $self->obs->instrument;

  throw OMP::Error( "WORF plotting function not defined for $instrument" );
}

=item B<suffices>

Returns suffices.

  @suffices = $worf->suffices( $group );

For the base class this method throws an C<OMP::Error>.

=cut

sub suffices {
  my $self = shift;
  my $group = shift;

  my $instrument = $self->obs->instrument;

  throw OMP::Error "OMP::WORF->suffices not defined for $instrument";

}

=item B<findgroup>

Determines group membership for a given C<OMP::WORF> object.

  $grp = $worf->findgroup;

Returns an integer if a group can be determined, undef otherwise.

=cut

sub findgroup {
  my $self = shift;

  my $grp = $self->obs->group;

  return $grp;

}

=item B<get_filename>

Determine the filename for a given observation.

  $filename = $worf->get_filename( 0 );

The optional parameter determines whether or not the reduced group
file will be used. If no parameter is given, this method will return
the filename for an individual observation. If the parameter is B<true>,
then the group filename will be returned.

If a suffix has been set (see the B<suffix> method) then a reduced
file will be used, else a raw file will be used.

For the base class, this method throws an error. All filename handling
is done by instrument-specific classes.

=cut

sub get_filename {
  my $self = shift;
  my $instrument = $self->obs->instrument;

  throw OMP::Error( "WORF filename handling not defined for $instrument" );

}

=item B<file_exists>

Determine if a file exists matching the given suffix.

  $exists = $worf->file_exists( suffix => $suffix,
                                group => $group );

The two parameters are optional. If the suffix parameter is not given,
the B<suffix> accessor will be used. If the group parameter is not
given, then the method will default to the appropriate individual
observation.

This method returns a logical boolean.

=cut

sub file_exists {
  my $self = shift;
  my %args = @_;

  my ( $suffix, $group );
  if( exists( $args{suffix} ) && defined( $args{suffix} ) ) {
    $suffix = $args{suffix};
  } else {
    $suffix = $self->suffix;
  }

  if( exists( $args{group} ) && defined( $args{group} ) ) {
    $group = $args{group};
  } else {
    $group = 0;
  }

  my $worf = new OMP::WORF( obs => $self->obs,
                            suffix => $suffix,
                          );

  my $file = $worf->get_filename( $group );

  return ( -e $file );

}

=item B<parse_display_options>

Parse display options for use by display methods.

  %parsed = $worf->parse_display_options( \%options );

Takes a reference to a hash as a parameter and returns a parsed
hash.

=cut

sub parse_display_options {
  my $self = shift;
  my $options = shift;

  my %parsed;

  if( exists( $options->{xstart} ) &&
      defined( $options->{xstart} ) &&
      $options->{xstart} =~ /^-?[0-9e\-\.]+$/ ) {
    $parsed{xstart} = $options->{xstart};
  }
  if( exists( $options->{xend} ) &&
      defined( $options->{xend} ) &&
      $options->{xend} =~ /^-?[0-9e\-\.]+$/ ) {
    $parsed{xend} = $options->{xend};
  }
  if( exists( $options->{ystart} ) &&
      defined( $options->{ystart} ) &&
      $options->{ystart} =~ /^-?[0-9e\-\.]+$/ ) {
    $parsed{ystart} = $options->{ystart};
  }
  if( exists( $options->{yend} ) &&
      defined( $options->{yend} ) &&
      $options->{yend} =~ /^-?[0-9e\-\.]+$/ ) {
    $parsed{yend} = $options->{yend};
  }
  if( exists( $options->{autocut} ) &&
      defined( $options->{autocut} ) &&
      $options->{autocut} =~ /^\d+$/ ) {
    $parsed{autocut} = $options->{autocut};
  }
  if( exists( $options->{lut} ) && defined( $options->{lut} ) ) {
    $parsed{lut} = $options->{lut};
  }
  if( exists( $options->{size} ) &&
      defined( $options->{size} ) &&
      $options->{size} =~ /^\w+$/ ) {
    $parsed{size} = $options->{size};
  }
  if( exists( $options->{type} ) &&
      defined( $options->{type} ) ) {
    $parsed{type} = $options->{type};
  }
  if( exists( $options->{zmin} ) &&
      defined( $options->{zmin} ) &&
      $options->{zmin} =~ /^-?[0-9e\-\.]+$/ ) {
    $parsed{zmin} = $options->{zmin};
  }
  if( exists( $options->{zmax} ) &&
      defined( $options->{zmax} ) &&
      $options->{zmax} =~ /^-?[0-9e\-\.]+$/ ) {
    $parsed{zmax} = $options->{zmax};
  }
  if( exists( $options->{cut} ) &&
      defined( $options->{cut} ) ) {
    $parsed{cut} = $options->{cut};
  }
  if( exists( $options->{group} ) &&
      defined( $options->{group} ) ) {
    $parsed{group} = $options->{group};
  }
  if( exists( $options->{output_file} ) &&
      defined( $options->{output_file} ) ) {
    $parsed{output_file} = $options->{output_file};
  }
  if( exists( $options->{xbin} ) &&
      defined( $options->{xbin} ) ) {
    $parsed{xbin} = $options->{xbin};
  }
  if( exists( $options->{ybin} ) &&
      defined( $options->{ybin} ) ) {
    $parsed{ybin} = $options->{ybin};
  }

  return %parsed;

}

=back

=head2 Private Methods

=over 4

=item B<_plot_image>

Plots an image.

  $worf->_plot_image( %args );

The argument is a hash optionally containing the following key-value
pairs:

=over 4

=item input_file - location of data file. If undefined, this method will
use the file returned from the C<filename> method of the Obs object used
in the contructor of the WORF object. If defined, this argument must include
the full path.

=item output_file - location of output graphic. If undefined, this method
will output the graphic to STDOUT.

=item xstart - Start pixel in x-dimension. If undefined, the default will
be the first pixel in the array.

=item xend - End pixel in x-dimension. If undefined, the default will be
the last pixel in the array.

=item ystart - Start pixel in y-dimension. If undefined, the default will
be the first pixel in the array.

=item yend - End pixel in y-dimension. If undefined, the default will be
the last pixel in the array.

=item autocut - Level to autocut the data to display. If undefined, the
default will be 100. Allowable values are 100, 99, 98, 95, 80, 70, 50.

=item size - Size of graphic. If undefined, the default will be 'regular'.
Allowable values are 'regular' or 'thumb'.

=back

=cut

sub _plot_image {
  my $self = shift;
  my %args = @_;

  my $opt = { AXIS => 1,
              JUSTIFY => 1,
              LINEWIDTH => 1,
              DRAWWEDGE => 1 };

  my $lut = ( exists($args{lut}) && defined($args{lut}) ? $args{lut} : 'real' );

  my $file;
  if( defined( $args{input_file} ) ) {
    $file = $args{input_file};
  } else {
    $file = $self->obs->filename;
  }
  if( $file !~ /^\// ) {
    throw OMP::Error("Filename passed to _plot_image ($file) must include full path");
  }

  if( exists( $args{size} ) && defined( $args{size} ) &&
      $args{size} eq 'thumb' ) {
    $ENV{'PGPLOT_GIF_WIDTH'} = 120;
    $ENV{'PGPLOT_GIF_HEIGHT'} = 80;
  } else {
    $ENV{'PGPLOT_GIF_WIDTH'} = 480;
    $ENV{'PGPLOT_GIF_HEIGHT'} = 320;
  }

  # Do caching for thumbnails.
  my $cachefile;
  if( defined( $args{size} ) && $args{size} eq 'thumb' ) {
    my $suffix = ( defined( $self->suffix ) ? $self->suffix : '' );
    $cachefile = "/tmp/worfthumbs/" . $self->obs->startobs->ymd . $self->obs->instrument . $self->obs->runnr . $suffix . ".gif";

    # If the cachefile exists, display that. Otherwise, just continue on.
    if( -e $cachefile ) {

      open( CACHE, "< $cachefile" ) or throw OMP::Error("Cannot open cached thumbnail for display: $!");
      binmode( CACHE );
      binmode( STDOUT );

      while( read( CACHE, my $buff, 8 * 2 ** 10 ) ) { print STDOUT $buff; }

      close( CACHE );

      return;
    }

  }

  $file =~ s/\.sdf$//;

  my $image = rndf($file,1);

  my ($xdim, $ydim, $zdim) = dims $image;

  if(!defined $ydim) {

    # Since _plot_image will fail if it tries to display a 1D image, shunt
    # the image off to _plot_spectrum instead of failing.
    $self->_plot_spectrum( %args );
    return;
  }

  if( defined $zdim ) {

    # Similarly for a 3D image...
    $self->_plot_cube( %args );
    return;
  }

  # We've got everything we need to display the image now.

  # Get the image title.
  my $hdr = $image->gethdr;
  my $title = $file;

  # Fudge to set bad pixels to zero.
  my $bad = -1e-10;
  $image *= ( $image > $bad );

  if( exists( $args{zmin} ) && defined( $args{zmin} ) &&
      exists( $args{zmax} ) && defined( $args{zmax} ) &&
      ( $args{zmin} != 0 || $args{zmax} != 0 ) ) {

    my $zmin = $args{zmin};
    my $zmax = $args{zmax};

    if($zmin > $zmax) { ($zmax, $zmin) = ($zmin, $zmax); }
    $image = $image->clip($zmin, $zmax);
  } elsif( exists( $args{autocut} ) && defined( $args{autocut} ) && $args{autocut} != 100 ) {

    my ($mean, $rms, $median, $min, $max) = stats($image);

    if($args{autocut} == 99) {
      $image = $image->clip(($median - 2.6467 * $rms), ($median + 2.6467 * $rms));
    } elsif($args{autocut} == 98) {
      $image = $image->clip(($median - 2.2976 * $rms), ($median + 2.2976 * $rms));
    } elsif($args{autocut} == 95) {
      $image = $image->clip(($median - 1.8318 * $rms), ($median + 1.8318 * $rms));
    } elsif($args{autocut} == 90) {
      $image = $image->clip(($median - 1.4722 * $rms), ($median + 1.4722 * $rms));
    } elsif($args{autocut} == 80) {
      $image = $image->clip(($median - 1.0986 * $rms), ($median + 1.0986 * $rms));
    } elsif($args{autocut} == 70) {
      $image = $image->clip(($median - 0.8673 * $rms), ($median + 0.8673 * $rms));
    } elsif($args{autocut} == 50) {
      $image = $image->clip(($median - 0.5493 * $rms), ($median + 0.5493 * $rms));
    }
  } else {

    # default to 99% cut
    my ($mean, $rms, $median, $min, $max) = stats($image);
    $image = $image->clip(($median - 2.6467 * $rms), ($median + 2.6467 * $rms));

  }

  my ( $xstart, $xend, $ystart, $yend );
  if( ( exists $args{xstart} ) && ( defined( $args{xstart} ) ) && ( $args{xstart} =~ /^\d+$/ ) && ( $args{xstart} > 0 ) ) {
    $xstart = $args{xstart};
  } else {
    $xstart = 0;
  }
  if( ( exists $args{xend} ) && ( defined( $args{xend} ) ) && ( $args{xend} =~ /^\d+$/ ) && ( $args{xend} < $xdim ) ) {
    $xend = $args{xend};
  } else {
    $xend = $xdim - 1;
  }
  if( ( exists $args{ystart} ) && ( defined( $args{ystart} ) ) && ( $args{ystart} =~ /^\d+$/ ) && ( $args{ystart} > 0 ) ) {
    $ystart = $args{ystart};
  } else {
    $ystart = 0;
  }
  if( ( exists $args{yend} ) && ( defined( $args{yend} ) ) && ( $args{yend} =~ /^\d+$/ ) && ($args{yend} < $ydim ) ) {
    $yend = $args{yend};
  } else {
    $yend = $ydim - 1;
  }

  if( ( ( $xstart == 0 ) && ( $xend == 0 ) ) || ( $xstart >= $xend ) ) {
    $xstart = 0;
    $xend = $xdim - 1;
  }
  if( ( ( $ystart == 0 ) && ( $yend == 0 ) ) || ( $ystart >= $yend ) ) {
    $ystart = 0;
    $yend = $ydim - 1;
  }

  if(exists($args{output_file}) && defined( $args{output_file} ) ) {
    my $file = $args{output_file};
    dev "$file/GIF";
  } else {
    dev "-/GIF";
  }
  env( $xstart, $xend, $ystart, $yend, $opt );
  label_axes( undef, undef, $title );
  ctab( lut_data( $lut ) );
  imag $image;
  dev "/null";

  # Also write the cache file if necessary.
  if( defined( $cachefile ) ) {
    dev "$cachefile/GIF";
    env( $xstart, $xend, $ystart, $yend, $opt );
    label_axes( undef, undef, $title );
    ctab( lut_data( $lut ) );
    imag $image;
    dev "/null";
  }
}

=item B<_plot_spectrum>

Plots a spectrum.

  $worf->_plot_spectrum( %args );

The argument is a hash optionally containing the following key-value
pairs:

=over 4

=item output_file - location of output graphic. If undefined, this method
will output the graphic to STDOUT.

=item xstart - Start pixel in x-dimension. If undefined, the default will
be the first pixel in the array.

=item xend - End pixel in x-dimension. If undefined, the default will be
the last pixel in the array.

=item zmin - Start value in z-dimension (data). If undefined, the default will
be the lowest data in the array.

=item zmax - End pixel in z-dimension (data). If undefined, the default will be
the lowest data in the array.

=item cut - Direction of spectrum for 2D images. If undefined, the default
will be horizontal. Can be either vertical or horizontal.

=item rstart - Start row for spectrum extraction. If the data to be plotted
are in a one-dimensional array, this value is ignored. If undefined, the
default will be the first row on the array.

=item rend - End row for spectrum extraction. If the data to be plotted are
in a one-dimensional array, this value is ignored. If undefined, the default
will be the last row on the array.

=item size - Size of graphic. If undefined, the default will be 'regular'.
Allowable values are 'regular' or 'thumb'.

=back

=cut

sub _plot_spectrum {
  my $self = shift;
  my %args = @_;

  my $opt;

  my $file;
  if( defined( $args{input_file} ) ) {
    $file = $args{input_file};
  } else {
    $file = $self->obs->filename;
  }
  if( $file !~ /^\// ) {
    throw OMP::Error("Filename passed to _plot_image must include full path");
  }

  $file =~ s/\.sdf$//;
  my $image = rndf( $file );

  if( exists( $args{size} ) && defined( $args{size} ) &&
      $args{size} eq 'thumb' ) {
    $ENV{'PGPLOT_GIF_WIDTH'} = 120;
    $ENV{'PGPLOT_GIF_HEIGHT'} = 80;
    $opt = {SYMBOL => 1, LINEWIDTH => 1, PLOTLINE => 0};
  } else {
    $ENV{'PGPLOT_GIF_WIDTH'} = 480;
    $ENV{'PGPLOT_GIF_HEIGHT'} = 320;
    $opt = {SYMBOL => 1, LINEWIDTH => 1, PLOTLINE => 0};
  }

  # Do caching for thumbnails.
  my $cachefile;
  if( $args{size} eq 'thumb' ) {
    my $suffix = ( defined( $self->suffix ) ? $self->suffix : '' );
    $cachefile = "/tmp/" . $self->obs->startobs->ymd . $self->obs->instrument . $self->obs->runnr . $suffix . ".gif";

    # If the cachefile exists, display that. Otherwise, just continue on.
    if( -e $cachefile ) {

      open( CACHE, "< $cachefile" ) or throw OMP::Error("Cannot open cached thumbnail for display: $!");
      binmode( CACHE );
      binmode( STDOUT );

      while( read( CACHE, my $buff, 8 * 2 ** 10 ) ) { print STDOUT $buff; }

      close( CACHE );

      return;
    }

  }

  # Fudge to set bad pixels to zero.
#  my $bad = -1e-10;
#  $image *= ( $image > $bad );

  my $spectrum;
  my ( $xdim, $ydim, $zdim ) = dims $image;

  if( defined $zdim ) {
    $self->_plot_cube( %args );
    return;
  }

# We have to check if the input data is 1D or 2D
  if(defined($ydim)) {

    my $xstart = ( defined ( $args{xstart} ) ?
                   $args{xstart} :
                   1 );
    my $xend = ( defined ( $args{xend} ) ?
                 $args{xend} :
                 ( $xdim - 1 ) );
    my $ystart = ( defined ( $args{ystart} ) ?
                   $args{ystart} :
                   1 );
    my $yend = ( defined ( $args{yend} ) ?
                 $args{yend} :
                 ( $ydim - 1 ) );
    if( ( ( $xstart == 0 ) && ( $xend == 0 ) ) || ( $xstart >= $xend ) ) {
      $xstart = 0;
      $xend = $xdim - 1;
    }
    if( ( ( $ystart == 0 ) && ( $yend == 0 ) ) || ( $ystart >= $yend ) ) {
      $ystart = 0;
      $yend = $ydim - 1;
    }

    if( defined($args{cut}) && $args{cut} eq "vertical" ) {

      my $slice = $image->slice("$xstart:$xend,$ystart:$yend");
      my @stats = $slice->statsover;
      $spectrum = $stats[0];

    } else {

      my $transpose = $image->transpose->copy;
      my $slice = $transpose->slice("$ystart:$yend,$xstart:$xend");
      my @stats = $slice->statsover;
      $spectrum = $stats[0];

    }

  } else {

    $spectrum = $image;

  }

  if(exists($args{output_file}) && defined( $args{output_file} ) ) {
    my $file = $args{output_file};
    dev "$file/GIF";
  } else {
    dev "-/GIF";
  }

# Grab the axis information

  my $hdr = $image->gethdr;
  my $title = ( defined( $hdr->{Title} ) ? $hdr->{Title} : '' );
  my ( $axis, $axishdr, $units, $label );
  if( defined( $hdr->{Axis} ) ) {
    $axis = ${$hdr->{Axis}}[0];
    $axishdr = $axis->gethdr;
    $units = $axishdr->{Units};
    $label = $axishdr->{Label};
  } else {
    $axis = $axishdr = $units = $label = '';
  }

  my ( $xstart, $xend, $zmin, $zmax );

  if( exists $args{xstart} && defined $args{xstart} ) {
    $xstart = $args{xstart};
  } else {
    $xstart = 0;
  }
  if( exists $args{xend} && defined $args{xend} ) {
    $xend = $args{xend};
  } else {
    $xend = $xdim - 1;
  }
  if( exists $args{zmin} && defined $args{zmin} ) {
    $zmin = $args{zmin};
  } else {
    $zmin = min( $spectrum ) - ( max( $spectrum ) - min( $spectrum ) ) * 0.10;
  }
  if( exists $args{zmax} && defined $args{zmax} ) {
    $zmax = $args{zmax};
  } else {
    $zmax = max( $spectrum ) + ( max( $spectrum ) - min( $spectrum ) ) * 0.10;
  }
  if( ( ( $xstart == 0 ) && ( $xend == 0 ) ) || ( $xstart >= $xend ) ) {
    $xstart = 0;
    $xend = $xdim - 1;
  }
  if( ( $zmin == 0 ) && ( $zmax == 0 ) ) {
    $zmin = min( $spectrum ) - ( max( $spectrum ) - min( $spectrum ) ) * 0.10;
    $zmax = max( $spectrum ) + ( max( $spectrum ) - min( $spectrum ) ) * 0.10;
  } elsif( ( $zmax == 0 ) && ( $zmin > $zmax ) ) {
    $zmax = max( $spectrum ) + ( max( $spectrum ) - min( $spectrum ) ) * 0.10;
  }

  env(0, ($xend - $xstart), $zmin, $zmax);
  label_axes( undef, undef, $title);
#  points $spectrum, $opt;
  line $spectrum;
  dev "/null";

  # Also write the cache file if necessary.
  if( defined( $cachefile ) ) {
    dev "$cachefile/GIF";
    env(0, ($xend - $xstart), $zmin, $zmax);
    label_axes( undef, undef, $title);
#    points $spectrum, $opt;
    line $spectrum;
    dev "/null";
  }

}

sub _plot_cube {
  my $self = shift;
  my %args = @_;

  my $file;
  if( defined( $args{input_file} ) ) {
    $file = $args{input_file};
  } else {
    $file = $self->obs->filename;
  }
  if( $file !~ /^\// ) {
    throw OMP::Error("Filename passed to _plot_cube must include full path");
  }

  if( exists( $args{size} ) && defined( $args{size} ) &&
      $args{size} eq 'thumb' ) {
    $ENV{'PGPLOT_GIF_WIDTH'} = 120;
    $ENV{'PGPLOT_GIF_HEIGHT'} = 80;
  } else {
    $ENV{'PGPLOT_GIF_WIDTH'} = 480;
    $ENV{'PGPLOT_GIF_HEIGHT'} = 320;
  }

  $file =~ s/\.sdf$//;
  my $cube = rndf( $file );

  my $spectrum;
  my ( $xdim, $ydim, $zdim ) = dims $cube;
# We have to check if the input data is 1D or 2D
  my ( $xstart, $xend, $ystart, $yend, $zstart, $zend );
  if(defined($zdim)) {

    $xstart = ( defined ( $args{xstart} ) ?
                $args{xstart} :
                1 );
    $xend = ( defined ( $args{xend} ) ?
              $args{xend} :
              ( $xdim - 1 ) );
    $ystart = ( defined ( $args{ystart} ) ?
                $args{ystart} :
                1 );
    $yend = ( defined ( $args{yend} ) ?
              $args{yend} :
              ( $ydim - 1 ) );
    $zstart = ( defined ( $args{zmin} ) ?
                $args{zmin} :
                1 );
    $zend = ( defined ( $args{zmax} ) ?
              $args{zmax} :
              ( $zdim - 1 ) );
    if( ( ( $xstart == 0 ) && ( $xend == 0 ) ) || ( $xstart >= $xend ) ) {
      $xstart = 0;
      $xend = $xdim - 1;
    }
    if( ( ( $ystart == 0 ) && ( $yend == 0 ) ) || ( $ystart >= $yend ) ) {
      $ystart = 0;
      $yend = $ydim - 1;
    }
    if( ( ( $zstart == 0 ) && ( $zend == 0 ) ) || ( $zstart >= $zend ) ) {
      $zstart = 0;
      $zend = $zdim - 1;
    }
  } else {
    throw OMP::Error("Trying to display a 1D or 2D file as a cube.");
  }

  # Set up binning information (in the spatial sense)
  my ( $xbin, $ybin );
  if( exists( $args{xbin} ) && defined( $args{xbin} ) ) {
    $xbin = $args{xbin};
  } else {
    $xbin = 1;
  }
  if( exists( $args{ybin} ) && defined( $args{ybin} ) ) {
    $ybin = $args{ybin};
  } else {
    $ybin = 3;
  }

  # Do the image manipulation so we can rebin.
  $cube->badflag(0);
  my $e = 0 * ($cube < -1e25) + $cube * ($cube >= -1e25);
  my $e1 = $e->xchg(1,2);
  my $e2 = $e1->xchg(0,1);
  my $rebin = $e2->rebin($zdim, $xbin, $ybin);

  # Grab the data information and do scaling
  my ( $dmin, $dmax );

  if( exists $args{dmin} && defined $args{dmin} ) {
    $dmin = $args{dmin};
  } else {
    $dmin = min( $rebin ) - ( max( $rebin ) - min( $rebin ) ) * 0.10;
  }
  if( exists $args{dmax} && defined $args{dmax} ) {
    $dmax = $args{dmax};
  } else {
    $dmax = max( $rebin ) + ( max( $rebin ) - min( $rebin ) ) * 0.10;
  }

  if( ( $dmin == 0 ) && ( $dmax == 0 ) ) {
    $dmin = min( $rebin ) - ( max( $rebin ) - min( $rebin ) ) * 0.10;
    $dmax = max( $rebin ) + ( max( $rebin ) - min( $rebin ) ) * 0.10;
  } elsif( ( $dmax == 0 ) && ( $dmin > $dmax ) ) {
    $dmax = max( $rebin ) + ( max( $rebin ) - min( $rebin ) ) * 0.10;
  }

  if( exists( $args{size} ) && defined( $args{size} ) &&
      $args{size} eq 'thumb' ) {
    $ENV{'PGPLOT_GIF_WIDTH'} = 120 * $xbin;
    $ENV{'PGPLOT_GIF_HEIGHT'} = 80 * $ybin;
  } else {
    $ENV{'PGPLOT_GIF_WIDTH'} = 480 * $xbin;
    $ENV{'PGPLOT_GIF_HEIGHT'} = 320 * $ybin;
  }

  if(exists($args{output_file}) && defined( $args{output_file} ) ) {
    my $file = $args{output_file};
    dev "$file/GIF", $xbin, $ybin;
  } else {
    dev "-/GIF", $xbin, $ybin;
  }

  # Split up the rebinned cube into spectra and display them.
  for (my $x = 1; $x <= $xbin; $x++ ) {

    for ( my $y = 1; $y <= $ybin; $y++ ) {

      my $slice = $rebin->slice(':,(' . ($x - 1) . '),('. ($y - 1) . ')');
      my $xwinpos = $x;
      my $ywinpos = $y;
      env($zstart, $zend, $dmin, $dmax, {Title => "$ywinpos, $xwinpos",});
      line( $slice, { Panel => [ $ywinpos, $xwinpos ],
                    } );
    } # y for-loop

  } # x for-loop

  dev "/null";

}

=back

=head1 SUBROUTINES

=over 4

=item B<worf_determine_class>

  $worfclass = worf_determine_class( $obs );

Used to determine the subclass for a given C<Info::Obs> object. If no subclass
can be determined, returns the base class.

Returns a string.

=cut

sub worf_determine_class {
  my $obs = shift;

  my $inst_dhs = uc( $obs->inst_dhs );

  my $class;

  if( defined( $inst_dhs ) ) {
    $class = "OMP::WORF::$inst_dhs";
  } else {
    $class = "OMP::WORF";
  }

  return $class;

}

=back

=head1 AUTHOR

Brad Cavanagh E<lt>b.cavanagh@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001-2003 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
