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
use PDL;
use PDL::IO::NDF;
use PDL::Graphics::PGPLOT;
use PDL::Graphics::LUT;

our $VERSION = (qw$Revision$ )[1];

require Exporter;

our @ISA = qw/Exporter/;
our @EXPORTER = qw( );
our @EXPORT = qw/ worf_determine_class new plot obs parse_display_options /;
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

  # Re-bless the object with the right class, which will
  # be OMP::WORF::$instrument
  my $newclass = "OMP::WORF::" . uc( $worf->obs->instrument );
  bless $worf, $newclass;

  eval "require $newclass";
  if( $@ ) { throw OMP::FatalError "Could not load module $newclass: $@"; }

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

  $filename = $worf->get_filename( group => 0 );

The optional parameter determines whether or not the reduced group
file will be used.

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
      $options->{xstart} =~ /^\d+$/ ) {
    $parsed{xstart} = $options->{xstart};
  }
  if( exists( $options->{xend} ) &&
      defined( $options->{xend} ) &&
      $options->{xend} =~ /^\d+$/ ) {
    $parsed{xend} = $options->{xend};
  }
  if( exists( $options->{ystart} ) &&
      defined( $options->{ystart} ) &&
      $options->{ystart} =~ /^\d+$/ ) {
    $parsed{ystart} = $options->{ystart};
  }
  if( exists( $options->{yend} ) &&
      defined( $options->{yend} ) &&
      $options->{yend} =~ /^\d+$/ ) {
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
      $options->{size} =~ /^\d+$/ ) {
    $parsed{size} = $options->{size};
  }
  if( exists( $options->{type} ) &&
      defined( $options->{type} ) ) {
    $parsed{type} = $options->{type};
  }
  if( exists( $options->{zmin} ) &&
      defined( $options->{zmin} ) &&
      $options->{zmin} =~ /^\d+$/ ) {
    $parsed{zmin} = $options->{zmin};
  }
  if( exists( $options->{zmax} ) &&
      defined( $options->{zmax} ) &&
      $options->{zmax} =~ /^\d+$/ ) {
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

=item width - Width of output graphic, in pixels. If undefined, the default
will be 640.

=item height - Height of output graphic, in pixels. If undefined, the
default will be 480.

=back

=cut

sub _plot_image {
  my $self = shift;
  my %args = @_;

  my $opt = {AXIS => 1,
             JUSTIFY => 1,
             LINEWIDTH => 1};

  my $lut = 'heat';

  my $file;
  if( defined( $args{input_file} ) ) {
    $file = $args{input_file};
  } else {
    $file = $self->obs->filename;
  }
  if( $file !~ /^\// ) {
    throw OMP::Error("Filename passed to _plot_image ($file) must include full path");
  }

  if( exists( $args{width} ) && $args{width} =~ /^\d+$/) {
    $ENV{'PGPLOT_GIF_WIDTH'} = $args{width};
  } else {
    $ENV{'PGPLOT_GIF_WIDTH'} = 640;
  }

  if( exists( $args{height} ) && $args{height} =~ /^\d+$/) {
    $ENV{'PGPLOT_GIF_HEIGHT'} = $args{height};
  } else {
    $ENV{'PGPLOT_GIF_HEIGHT'} = 480;
  }

  $file =~ s/\.sdf$//;

  my $image = rndf($file,1);

  my ($xdim, $ydim) = dims $image;

  if(!defined $ydim) {

    # Since _plot_image will fail if it tries to display a 1D image, shunt
    # the image off to _plot_spectrum instead of failing.
    $self->_plot_spectrum( %args );
    return;
  }

  # We've got everything we need to display the image now.

  # Get the image title.
  my $hdr = $image->gethdr;
  my $title = $file;

  # Fudge to set bad pixels to zero.
  my $bad = -1e-10;
  $image *= ( $image > $bad );

  # Do autocutting, if necessary.
  if( exists( $args{autocut} ) && defined( $args{autocut} ) && $args{autocut} != 100 ) {

    my ($mean, $rms, $median, $min, $max) = stats($image);

    my $stddev = sqrt($rms);

    if($args{autocut} == 99) {
      $image = $image->clip(($median - 2.6467 * $stddev), ($median + 2.6467 * $stddev));
    } elsif($args{autocut} == 98) {
      $image = $image->clip(($median - 2.2976 * $stddev), ($median + 2.2976 * $stddev));
    } elsif($args{autocut} == 95) {
      $image = $image->clip(($median - 1.8318 * $stddev), ($median + 1.8318 * $stddev));
    } elsif($args{autocut} == 90) {
      $image = $image->clip(($median - 1.4722 * $stddev), ($median + 1.4722 * $stddev));
    } elsif($args{autocut} == 80) {
      $image = $image->clip(($median - 1.0986 * $stddev), ($median + 1.0986 * $stddev));
    } elsif($args{autocut} == 70) {
      $image = $image->clip(($median - 0.8673 * $stddev), ($median + 0.8673 * $stddev));
    } elsif($args{autocut} == 50) {
      $image = $image->clip(($median - 0.5493 * $stddev), ($median + 0.5493 * $stddev));
    }
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
  label_axes( "lut=$lut", undef, $title );
  ctab( lut_data( $lut ) );
  imag $image;
  dev "/null";

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

=item width - Width of output graphic, in pixels. If undefined, the default
will be 640.

=item height - Height of output graphic, in pixels. If undefined, the
default will be 480.

=back

=cut

sub _plot_spectrum {
  my $self = shift;
  my %args = @_;

  my $opt = {SYMBOL => 1, LINEWIDTH => 10, PLOTLINE => 0};

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
print "Loading $file\n";
  my $image = rndf( $file );

  # Fudge to set bad pixels to zero.
  my $bad = -1e-10;
  $image *= ( $image > $bad );

  my $spectrum;
  my ( $xdim, $ydim ) = dims $image;
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
  if( ( ( $zmin == 0 ) && ( $zmax == 0 ) ) || ( $zmin >= $zmax ) ) {
    $zmin = min( $spectrum ) - ( max( $spectrum ) - min( $spectrum ) ) * 0.10;
    $zmax = max( $spectrum ) + ( max( $spectrum ) - min( $spectrum ) ) * 0.10;
  }

  env(0, ($xend - $xstart), $zmin, $zmax);
  label_axes( "$label ($units)", undef, $title);
  points $spectrum, $opt;
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

  my $instrument = uc( $obs->instrument );

  my $class;

  if( defined( $instrument ) ) {
    $class = "OMP::WORF::$instrument";
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
