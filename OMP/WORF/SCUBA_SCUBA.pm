package OMP::WORF::SCUBA_SCUBA;

=head1 NAME

OMP::WORF::SCUBA_SCUBA - SCUBA-specific functions for WORF

=head1 

SYNOPSIS

use OMP::WORF::SCUBA_SCUBA;

  my $worf = new OMP::WORF::SCUBA_SCUBA( obs => $obs, suffix => $suffix );

  $worf->plot( group => 1 );

  my @suffices = $worf->suffices;

=head1 DESCRIPTION

This subclass of C<OMP::WORF> supplies SCUBA-specific functions
for WORF. In particular, it allows for plotting of images and retrieving
a list of valid suffices for SCUBA data.

=cut

use strict;
use warnings;
use Carp;

use OMP::Config;
use OMP::Error qw/ :try /;

use PGPLOT;

use PDL::Lite;
use PDL::IO::NDF;
use PDL::Primitive;
use PDL::Graphics::PGPLOT;
use PDL::Graphics::LUT;

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

The valid suffices for an SCUBA observation.

  @suffices = $worf->suffices( $group );

This method returns a list of valid suffices for reduced SCUBA data, as
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
    @suffices = qw/ _pht_ _reb_ /;
  } else {
    @suffices = qw/ _reb /;
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

  my $ut;
  ( $ut = $self->obs->startobs->ymd ) =~ s/-//g;

  my @files = $self->get_filename( $options{group} );

  my %parsed = $self->parse_display_options( \%options );

  if( $self->suffix =~ /reb/i ) {

    $self->_plot_images( input_file => \@files,
                         autocut => $parsed{autocut},
                         lut => $parsed{lut},
                         size => $parsed{size},
                       );
  } elsif ( $self->suffix =~ /pht/i ) {

    $self->_plot_photometry( input_file => \@files,
                             size => $parsed{size},
                           );

  } elsif ( $self->suffix =~ /noise/i ) {

    $self->_plot_noise( input_file => \@files,
                        size => $parsed{size},
                      );
  }

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

  if( !defined( $group ) ) { $group = 0; }

  my $instrument = uc( $self->obs->instrument );
  if( !defined( $instrument ) ) {
    throw OMP::Error( "Cannot determine instrument to display image in WORF." );
  }
  my $telescope = OMP::Config->inferTelescope('instruments', $instrument);
  if( !defined( $telescope ) ) {
    throw OMP::Error("Cannot determine telescope to display image in WORF.");
  }

  my ( $directory, @filenames );

  my $ut;
  ( $ut = $self->obs->startobs->ymd ) =~ s/-//g;
#print STDERR "ut: $ut ";
  my $suffix = ( defined( $self->suffix ) && ( length( $self->suffix . '' ) > 0 ) ?
                 $self->suffix :
                 'NOSUFFIX' );
#print STDERR "suffix: $suffix\n";
  if( $group ) {
    $directory = OMP::Config->getData( "reducedgroupdir",
                                       telescope => $telescope,
                                       instrument => $instrument,
                                       utdate => $ut,
                                     );
    my $groupnr = sprintf("%04d",$self->obs->runnr);
    @filenames = ( $directory . "/" . $ut . "_grp_" . $groupnr . $suffix . "short.sdf" ,
                   $directory . "/" . $ut . "_grp_" . $groupnr . $suffix . "long.sdf" );
  } else {
    $directory = OMP::Config->getData( "reduceddatadir",
                                       telescope => $telescope,
                                       instrument => $instrument,
                                       utdate => $ut,
                                     );
    my $runnr = sprintf("%04d", $self->obs->runnr );
    @filenames = ( $directory . "/" . $ut . "_" . $runnr . "_sho" . $suffix . ".sdf" ,
                   $directory . "/" . $ut . "_" . $runnr . "_lon" . $suffix . ".sdf" );
  }

  if( ! wantarray ) {
    foreach my $file ( @filenames ) {
      if( -e $file ) {
        return $file;
      }
    }
    return undef;
  }

  return @filenames;

}

=item B<findgroup>

Determines group membership for a given C<OMP::WORF> object.

  $grp = $worf->findgroup;

Returns an integer if a group can be determined, undef otherwise.

=cut

sub findgroup {
  my $self = shift;

  my $grp = $self->obs->runnr;

  if( ! defined( $grp ) ) {

# Load up the raw file, import that into an Obs object, then
# get the group from there.
    my $newworf = new OMP::WORF( obs => $self->obs );
    my $rawfile = $newworf->get_filename( 0 );
    my $obs = readfile OMP::Info::Obs( $rawfile );

    $grp = $obs->runnr;

  }

  return $grp;

}

=back

=head2 Private Methods

These methods are private to this module.

=over 4

=item B<_plot_images>

Plots a pair of images for SCUBA.

  $worf->_plot_images( input_file => \@files,
                       autocut => '95',
                       lut => 'color' );

=cut

sub _plot_images {
  my $self = shift;
  my %args = @_;

  my $lut = ( exists( $args{lut} ) && defined( $args{lut} ) ? $args{lut} : 'real' );

  my @files = @{$args{input_file}};

  if( exists( $args{size} ) && defined( $args{size} ) &&
      $args{size} eq 'thumb' ) {
    $ENV{'PGPLOT_GIF_WIDTH'} = 120;
    $ENV{'PGPLOT_GIF_HEIGHT'} = 80 * ( $#files + 1 );
  } else {
    $ENV{'PGPLOT_GIF_WIDTH'} = 480;
    $ENV{'PGPLOT_GIF_HEIGHT'} = 320 * ( $#files + 1 );
  }

  if(exists($args{output_file}) && defined( $args{output_file} ) ) {
    my $file = $args{output_file};
    dev "$file/GIF", 1, ( $#files + 1 );
  } else {
    dev "-/GIF", 1, ( $#files + 1 );
  }

  foreach my $input_file ( @files ) {

    next if ( ! -e $input_file );

    my $image = rndf( $input_file, 1 );

    if( exists( $args{autocut} ) && defined( $args{autocut} ) && $args{autocut} != 100 ) {
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

    my ( $xdim, $ydim ) = dims $image;
    my $xstart = 0;
    my $ystart = 0;
    my $xend = $xdim - 1;
    my $yend = $ydim - 1;

    my $title = $input_file;

    env( $xstart, $xend, $ystart, $yend, {JUSTIFY => 1} );
    label_axes( undef, undef, $title );
    ctab( lut_data( $lut ) );
    imag $image, {JUSTIFY=>1};

  }

  dev "/null";

}

=item B<_plot_photometry>

Plots photometry data taken with SCUBA, as per qdraw.

  $worf->_plot_photometry( input_file => \@files );

This method plots photometry data and information as follows. It
first finds the unclipped mean and standard deviation of the data.
Then it finds the 3-sigma clipped mean and standard deviation. These
numbers are presented on the display. When displaying it draws the
data as points, with minimum and maximum bounds set as unclipped
5-sigma from the unclipped mean, and also draws the unclipped mean
and unclipped 3-sigma bounds as dashed red lines. It performs these
steps for all files passed in the input_file parameter.

=cut

sub _plot_photometry {
  my $self = shift;
  my %args = @_;

  my @files = @{$args{input_file}};

  if( exists( $args{size} ) && defined( $args{size} ) &&
      $args{size} eq 'thumb' ) {
    $ENV{'PGPLOT_GIF_WIDTH'} = 120;
    $ENV{'PGPLOT_GIF_HEIGHT'} = 80 * ( $#files + 1 );
  } else {
    $ENV{'PGPLOT_GIF_WIDTH'} = 480;
    $ENV{'PGPLOT_GIF_HEIGHT'} = 320 * ( $#files + 1 );
}

  if(exists($args{output_file}) && defined( $args{output_file} ) ) {
    my $file = $args{output_file};
    dev "$file/GIF", 1, ( $#files + 1 );
  } else {
    dev "-/GIF", 1, ( $#files + 1 );
  }

  foreach my $input_file ( @files ) {

    next if ( ! -e $input_file );

    my $image = rndf( $input_file, 1 );

    my @dims = dims $image;
    my $xdim = $dims[0];

    my ( $mean, $stddev, $median, $min, $max ) = $image->stats;

    my $clipped;
    {
      my $temp = $image->setbadif( $image > ( $mean + 3 * $stddev ) );
      $clipped = $temp->setbadif( $image < ( $mean - 3 * $stddev ) );
    }

    # Find out how many points were unclipped.
    my $unclipped = $clipped / $clipped;
    my $nclipped = sumover $unclipped;

    my @clippedstats = $clipped->stats;

    # Set the environment so the data min/max are +/- 5-sigma.
    # Set the titles and display "results" as well.
    pgsls(1);
    pgscf(1);
    pgsch(1.5);
    my $hdr = $image->gethdr;
    my $title = $hdr->{Title};
    my $clippedmean = sprintf("%.2f", $clippedstats[0] );
    my $clippedrms = sprintf("%.2f", ( $clippedstats[1] * sqrt( $nclipped / ($nclipped - 1) ) ) );
    my $results = "Results: $clippedmean +/- $clippedrms (S/N = " . sprintf("%.2f", $clippedmean / $clippedrms ) . ")";
    env( 0, $xdim, ( $mean - 5 * $stddev ), ( $mean + 5 * $stddev ),
         { Title => $title,
           XTitle => $results,
         } );

    # Draw the points in white.
    pgsci(1);
    points $image;

    # Draw the mean and +/- 3-sigma lines in dashed red.
    pgsci(2);
    pgsls(2);
    pgline( 2, [0, $xdim], [$mean, $mean] );
    pgline( 2, [0, $xdim], [($mean - 3 * $stddev), ($mean - 3 * $stddev)] );
    pgline( 2, [0, $xdim], [($mean + 3 * $stddev), ($mean + 3 * $stddev)] );

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

=cut

1;
