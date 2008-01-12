package OMP::WORF::HET_GSD;

=head1 NAME

OMP::WORF::HET_GSD - Specific functions for WORF for GSD files
taken at JCMT.

=head1 

SYNOPSIS

use OMP::WORF::HET_GSD;

  my $worf = new OMP::WORF::HET_GSD( obs => $obs, suffix => $suffix );

  $worf->plot( group => 1 );

  my @suffices = $worf->suffices;

=head1 DESCRIPTION

This subclass of C<OMP::WORF> supplies specific functions
for WORF for GSD files taken at JCMT, which are observations taken with
any of the heterodyne front-ends (RXA, RXB, RXW) and the DAS, CBE, or IFD
backends. In particular, it allows for plotting of images and retrieving
a list of valid suffices for GSD data.

=cut

use strict;
use warnings;
use Carp;

use OMP::Config;
use OMP::Error qw/ :try /;

use PGPLOT;

use PDL::Lite;
use PDL::Core;
use PDL::IO::GSD;
use PDL::Graphics::PGPLOT;
use PDL::Primitive;
use PDL::Ufunc;

use JCMT::DAS qw/ das_merge /;

use base qw/ OMP::WORF /;

our $VERSION = (qw$Revision$ )[1];

require Exporter;

our @EXPORT = qw( plot suffices );
our %EXPORT_TAGS = (
                    'all' => [ qw( @EXPORT ) ],
                    );

Exporter::export_tags(qw/ all /);

=head1 METHODS

=head2 Accessor Methods

=over 4

=item B<suffices>

The valid suffices for an RXA3I observation.

  @suffices = $worf->suffices( $group );

This method returns a list of valid suffices for reduced RXA3I data, as
reduced by ORAC-DR. If the optional argument is C<true> then suffices
for reduced group data are returned.

This method returns a list if called in list context, or an array
reference if called in scalar context.

=cut

sub suffices {
  my $self = shift;
  my $group = shift;

  my @suffices;

  if( $group ) {
    @suffices = qw/  /;
  } else {
    @suffices = qw/ _das_ /;
  }

  if( wantarray ) { return @suffices; } else { return \@suffices; }

}

=back

=head2 General Methods

=over 4

=item B<plot>

Displays an image.

  $worf->plot;

Options may be passed in a hash, with key-value pairs as described below.

=over 4

=item group - Display the reduced group file for the observation given
in the C<OMP::WORF> object if true. If false or undefined, display the
reduced individual file or, if the suffix in the C<OMP::WORF> object
is undefined, the raw individual file.

=item type - Display an image or a spectrum, and as such, values can be
either 'image' or 'spectrum'. Defaults to 'image'.

=item lut - Colour lookup table to use to display the image. Must be one
of the lookup tables used by C<PDL::Graphics::LUT>. Defaults to 'standard'.

=item size - Size of image to display. Must be one of 'regular' or
'thumb'. Defaults to 'regular'.

=item xstart - Start pixel in x-dimension to display. If undefined, greater
than xend, or greater than the largest extent of the array, will default
to 0. For spectra being formed from images, this is the starting column of
the region of the image to collapse to form a spectrum. For native spectra,
this is the starting position of the spectrum that will be displayed.

=item xend - End pixel in x-dimension to display. If undefined, less
than xstart, or less than the smallest extent of the array, will default to
the largest extent of the array. For spectra being formed from images, this
is the final column of the region of the image to collapse to form a spectrum.
For native spectra, this is the final position of the spectrum that will
be displayed.

=item ystart - Start pixel in y-dimension to display. If undefined, greater
than yend, or greater than the largest extent of the array, will default
to 0. For spectra being formed from images, this is the starting row of the
region of the image to collapse to form a spectrum.

=item yend - End pixel in y-dimension to display. If undefined, less
than ystart, or less than the smallest extent of the array, will default to
the largest extent of the array. For spectra being formed from images, this
is the final row of the region of the image to collapse to form a spectrum.

=item autocut - Scale data by cutting percentages. Can be one of 100, 99,
98, 95, 90, 80, 70, or 50. Defaults to 100.

=item zmin - For spectra, the lowest data number to display. If undefined,
will default to the minimum value in the spectrum minus ten percent of the
dynamic range.

=item zmax - For spectra, the highest data number to display. If undefined,
will default to the maximum value in the spectrum plus ten percent of the
dynamic range..

=item cut - For spectra, the direction of the cut across the array. Can be
either 'horizontal' or 'vertical'. Defaults to 'horizontal'.

=back

=cut

sub plot {
  my $self = shift;

  my %options = @_;

  my $instrument = $self->obs->instrument;
  if( !defined( $instrument ) ) {
    throw OMP::Error("Cannot determine instrument to display image in WORF.");
  }

  my ( $dir, $fileregexp );

  my $ut;
  ( $ut = $self->obs->startobs->ymd ) =~ s/-//g;

#  my $file = $self->get_filename( $options{group} );
  my $file;
  if( defined( $options{input_file} ) && length( $options{input_file} . '' ) > 0 ) {
    $file = $options{input_file};
  } else {
    $file = $self->get_filename( $options{group} );
  }

  my %parsed = $self->parse_display_options( \%options );

  $self->_plot_spectrum( input_file => $file,
                         output_file => $parsed{output_file},
                         xstart => $parsed{xstart},
                         xend => $parsed{xend},
                         zmin => $parsed{zmin},
                         zmax => $parsed{zmax},
                         size => $parsed{size},
                       );

}

=item B<get_filename>

Determine the filename for a given observation.

  $filename = $worf->get_filename( 0 );

The optional parameter determines whether or not the reduced group
file will be used.

If a suffix has been set (see the B<suffix> method) then a reduced
file will be used, else a raw file will be used.

=cut

sub get_filename {
  my $self = shift;
  my $group = shift;

  # No such thing as a group file for DAS observations.
  if( defined( $group ) && $group ) { return undef; }

  my $runnr = sprintf("%04d",$self->obs->runnr);

  my $ut;
  ( $ut = $self->obs->startobs->ymd ) =~ s/-//g;

  my $instrument = "heterodyne";
  my $telescope = "JCMT";
  my $directory = OMP::Config->getData( "rawdatadir",
                                        telescope => $telescope,
                                        instrument => $instrument,
                                        utdate => $ut,
                                      );
################################################################################
# KLUDGE ALERT KLUDGE ALERT KLUDGE ALERT KLUDGE ALERT KLUDGE ALERT KLUDGE ALERT
################################################################################
# Because we cannot get instrument-specific directories from the configuration
# system (yet), we need to remove "/dem" from the directory retrieved for SCUBA
# observations.
################################################################################

        $directory =~ s/\/dem$//;

  my $filename = $directory . "/obs" . $self->suffix . $runnr . ".dat";

  return $filename;

}

=item B<findgroup>

Determines group membership for a given C<OMP::WORF> object.

  $grp = $worf->findgroup;

Returns an integer if a group can be determined, undef otherwise.

=cut

sub findgroup {
  my $self = shift;

  my $grp = $self->obs->group;

  if( ! defined( $grp ) ) {

# Load up the raw file, import that into an Obs object, then
# get the group from there.
    my $newworf = new OMP::WORF( obs => $self->obs );
    my $rawfile = $newworf->get_filename( 0 );
    my $obs = readfile OMP::Info::Obs( $rawfile );

    $grp = $obs->group;

  }

  return $grp;

}

=back

=head2 Private Methods

These methods are private to this module.

=over 4

=item B<_plot_spectrum>

Plots a spectrum for DAS observations.

  $worf->_plot_spectrum( input_file => $file,
                         %args );

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

=cut

sub _plot_spectrum {
  my $self = shift;
  my %args = @_;

  my $file;
  if( defined( $args{input_file} ) ) {
    $file = $args{input_file};
  } else {
    $file = $self->obs->filename;
  }
  if( $file !~ /^\// ) {
    throw OMP::Error("Filename passed to _plot_image must include full path");
  }

  if( exists( $args{size} ) && defined( $args{size} ) && $args{size} eq 'thumb' ) {
    $ENV{'PGPLOT_GIF_WIDTH'} = 120;
    $ENV{'PGPLOT_GIF_HEIGHT'} = 80;
  } else {
    $ENV{'PGPLOT_GIF_WIDTH'} = 480;
    $ENV{'PGPLOT_GIF_HEIGHT'} = 320;
  }
  $ENV{'PGPLOT_BACKGROUND'} = 'black';
  $ENV{'PGPLOT_FOREGROUND'} = 'white';

  # Do caching for thumbnails.
  my $cachefile;
  if( $args{size} eq 'thumb' ) {

    if( ! -d "/tmp/worfthumbs" ) {
      mkdir "/tmp/worfthumbs";
    }

    my $suffix = ( defined( $self->suffix ) ? $self->suffix : '' );

    $cachefile = "/tmp/worfthumbs/" . $self->obs->startobs->ymd . $self->obs->instrument . $self->obs->runnr . $suffix . ".gif";

    # If the cachefile exists, display that. Otherwise, just continue on.
    if( -e $cachefile ) {

      open( my $fh, '<', $cachefile ) or throw OMP::Error("Cannot open cached thumbnail for display: $!");
      binmode( $fh );
      binmode( STDOUT );

      while( read( $fh, my $buff, 8 * 2 ** 10 ) ) { print STDOUT $buff; }

      close( $fh );

      return;
    }

  }

  if(exists($args{output_file}) && defined( $args{output_file} ) ) {
    my $outfile = $args{output_file};
    dev "$outfile/GIF", 1, 1;
  } else {
    dev "-/GIF";
  }

  my $pdl = rgsd( $file );

  # Just grab the first spectrum for now...
  my $spectrum = $pdl->slice(":,(0),0");

  # Get the header information.
  my $hdr = $pdl->gethdr;

  # Grab the centre frequencies and frequency increments from the header.
  my $centfrqs = $hdr->{C12CF};
  my $frqincs = $hdr->{C12FR};

  # Form arrays from the piddles to pass to das_merge.
  my @spectrum = list $spectrum;
  my @f_cen = list $centfrqs;
  my @f_inc = list $frqincs;

  # Merge.
  my ( $out, $frq, $vel ) = das_merge( \@spectrum,
                                       \@f_cen,
                                       \@f_inc,
                                       merge => 1 );

  # Form piddles from the array references.
  my $outpdl = pdl $out;
  my $velpdl = pdl $vel;

  my ( $npts ) = dims $velpdl;

  # Add the relative velocity.
  $velpdl += $hdr->{C7VR};

  # Set up the display boundaries.
  my ( $xstart, $xend, $zstart, $zend );
  if( exists( $args{xstart} ) && defined( $args{xstart} ) ) {
    $xstart = $args{xstart};
  } else {
    $xstart = min $velpdl;
  }
  if( exists( $args{xend} ) && defined( $args{xend} ) ) {
    $xend = $args{xend};
  } else {
    $xend = max $velpdl;
  }
  if( exists( $args{zmin} ) && defined( $args{zmin} ) ) {
    $zstart = $args{zmin};
  } else {
    $zstart = ( min $outpdl ) - 0.05 * ( ( max $outpdl ) - ( min $outpdl ) );
  }
  if( exists( $args{zmax} ) && defined( $args{zmax} ) ) {
    $zend = $args{zmax};
  } else {
    $zend = ( max $outpdl ) + 0.05 * ( ( max $outpdl ) - ( min $outpdl ) );
  }

  if( ( $xstart == 0 && $xend == 0 ) || ( $xstart >= $xend ) ) {
    $xstart = min $velpdl;
    $xend = max $velpdl;
  }
  if( ( $zstart == 0 && $zend == 0 ) || ( $zstart >= $zend ) ) {
    $zstart = ( min $outpdl ) - 0.05 * ( ( max $outpdl ) - ( min $outpdl ) );
    $zend = ( max $outpdl ) + 0.05 * ( ( max $outpdl ) - ( min $outpdl ) );
  }

  # Display.
  env( $xstart, $xend, $zstart, $zend );
  label_axes( "Velocity / km s\\u-1", "Spectrum (K)", $file );
  pgsci(3);
  line $velpdl, $outpdl;
  dev "/null";

  # Also write the cache file if necessary.
  if( defined( $cachefile ) ) {
    dev "$cachefile/GIF";
    env( $xstart, $xend, $zstart, $zend );
    label_axes( "Velocity / km s\\u-1", "Spectrum (K)", $file );
    pgsci(3);
    line $velpdl, $outpdl;
    dev "/null";
  }
}

=back

=head1 SEE ALSO

OMP::WORF

=head1 AUTHOR

Brad Cavanagh E<lt>b.cavanagh@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001-2003 Particle Physics and Astronomy Research Council.
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
