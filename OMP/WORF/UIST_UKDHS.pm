package OMP::WORF::UIST_UKDHS;

=head1 NAME

OMP::WORF::UIST_UKDHS - UIST_UKDHS (UIST with ORAC DHS) specific
functions for WORF

=head1 

SYNOPSIS

use OMP::WORF::UIST_UKDHS;

  my $worf = new OMP::WORF::UIST_UKDHS( obs => $obs, suffix => $suffix );

  $worf->plot( group => 1 );

  my @suffices = $worf->suffices;

=head1 DESCRIPTION

This subclass of C<OMP::WORF> supplies UIST-specific functions
for WORF. In particular, it allows for plotting of images and retrieving
a list of valid suffices for UIST data. This subclass is meant for
UIST data taken with the ORAC data handling system.

=cut

use strict;
use warnings;
use Carp;

use OMP::Config;
use OMP::Error qw/ :try /;

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

The valid suffices for an UIST observation.

  @suffices = $worf->suffices( $group );

This method returns a list of valid suffices for reduced UIST data, as
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
    @suffices = qw/ _mos _dbs _dbsi _fci _dbsc _fc _cub/;
  } else {
    @suffices = qw/ _ff _raw _wce /;
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

=item size - Size of image to display. Must be one of 'regular' or 'thumb'.
Defaults to 'regular'.

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

  my $file = $self->get_filename( $options{group} );

  my %parsed = $self->parse_display_options( \%options );

  if( exists( $parsed{type} ) &&
      defined( $parsed{type} ) &&
      $parsed{type} =~ /spectrum/i ) {

    $self->_plot_spectrum( input_file => $file,
                           %parsed,
                         );

  } elsif( exists( $parsed{type} ) &&
           defined( $parsed{type} ) &&
           $parsed{type} =~ /cube/i ) {

    $self->_plot_cube( input_file => $file,
                       %parsed,
                     );

  } else {

    $self->_plot_image( input_file => $file,
                        %parsed,
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
    throw OMP::Error("Cannot determine instrument to display image in WORF.");
  }
  my $telescope = OMP::Config->inferTelescope('instruments', $instrument);
  if( !defined( $telescope ) ) {
    throw OMP::Error("Cannot determine telescope to display image in WORF.");
  }

  my ( $directory, $filename );

  my $ut;
  ( $ut = $self->obs->startobs->ymd ) =~ s/-//g;

  my $runnr = $self->obs->runnr;

  # If we are going for a group, get the reduced group directory.
  if( $group ) {
    $directory = OMP::Config->getData( "reducedgroupdir",
                                       telescope => $telescope,
                                       instrument => $instrument,
                                       utdate => $ut,
                                     );
    my $groupnr = $self->findgroup;
    $filename = "gu" . $ut . "_" . $groupnr;
    $filename .= ( defined $self->suffix ? $self->suffix : "" );

  } elsif ( defined( $self->suffix ) && length( $self->suffix . '' ) > 0 ) {
    $directory = OMP::Config->getData( "reduceddatadir",
                                       telescope => $telescope,
                                       instrument => $instrument,
                                       utdate => $ut,
                                     );
    $filename = "u" . $ut . "_" . sprintf("%05d", $runnr) . $self->suffix;

  } else {
    $directory = OMP::Config->getData( "rawdatadir",
                                       telescope => $telescope,
                                       instrument => $instrument,
                                       utdate => $ut,
                                     );
    $filename = "u" . $ut . "_" . sprintf("%05d", $runnr);

  }

  return $directory . "/" . $filename . ".sdf";

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

=head1 SEE ALSO

OMP::WORF

=head1 AUTHOR

Brad Cavanagh E<lt>b.cavanagh@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001-2003 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
