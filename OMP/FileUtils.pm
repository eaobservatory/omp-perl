package OMP::FileUtils;

=head1 NAME

OMP::FileUtils - File-related utilities for the OMP.

=head1 SYNOPSIS

  use OMP::FileUtils;

  @files = OMP::FileUtils->files_on_disk( $inst, $date );

=head1 DESCRIPTION

This class provides general purpose routines that are used for
handling files for the OMP system.

=cut

use 5.006;
use strict;
use warnings::register;

our $VERSION = (qw$Revision$)[1];
our $DEBUG = 0;

=head1 METHODS

There are no instance methods, only class (static) methods.

=over 4

=item B<files_on_disk>

For a given instrument and UT date, this method returns a list of
observation files.

  my @files = OMP::General->files_on_disk( 'CGS4', $date );
  my $files = OMP::General->files_on_disk( 'CGS4', $date );

The instrument must be a string. The date must be a Time::Piece
object. If the date is not passed as a Time::Piece object then an
OMP::Error::BadArgs error will be thrown.

If called in list context, returns a list of array references. Each
array reference points to a list of observation files for a single
observation. If called in scalar context, returns a reference to an
array of array references.

=cut

sub files_on_disk {
  my $class = shift;
  my $instrument = shift;
  my $utdate = shift;

  my @return;

  if( ! UNIVERSAL::isa( $utdate, "Time::Piece" ) ) {
    throw OMP::Error::BadArgs( "Date parameter to OMP::General::files_on_disk must be a Time::
Piece object" );
  }

  my $date = $utdate->ymd;
  $date =~ s/-//g;

  # Retrieve information from the configuration system.
  my $tel = OMP::Config->inferTelescope( 'instruments', $instrument );
  my $directory = OMP::Config->getData( 'rawdatadir',
                                        telescope => $tel,
                                        instrument => $instrument,
                                        utdate => $utdate,
                                      );
  my $flagfileregexp = OMP::Config->getData( 'flagfileregexp',
                                             telescope => $tel,
                                           );

  # Remove the /dem from non-SCUBA directories.
  if( uc( $instrument ) ne 'SCUBA' ) {
    $directory =~ s/\/dem$//;
  }

  # Change wfcam to wfcam1 if the instrument is WFCAM.
  if( uc( $instrument ) eq 'WFCAM' ) {
    $directory =~ s/wfcam/wfcam1/;
  }
  # ACSIS directory is actually acsis/acsis00/utdate.
  if( uc( $instrument ) eq 'ACSIS' ) {
    $directory =~ s[(acsis)/(\d{8})][$1/spectra/$2];
  }

  # Open the directory.
  opendir( OMP_DIR, $directory );

  # Get the list of files that match the flag file regexp.
  my @flag_files = map { File::Spec->catfile( $directory, $_ ) } sort grep ( /$flagfileregexp/
, readdir( OMP_DIR ) );

  # Close the directory.
  close( OMP_DIR );

  # Go through each flag file, open it, and retrieve the list of files
  # within it. If the flag file size is 0 bytes, then we assume that
  # the observation file associated with that flag file is of the same
  # naming convention, removing the dot from the front and replacing
  # the .ok on the end with .sdf.
  foreach my $flag_file ( @flag_files ) {

    # Zero-byte filesize.
    if ( -z $flag_file ) {

      $flag_file =~ /(.+)\.(\w+)\.ok$/;
      my $data_file = $1 . $2 . ".sdf";

      my @array;
      push @array, $data_file;
      push @return, \@array;

    } else {

      open my $flag_fh, "<", $flag_file;

      my @array;
      while (<$flag_fh>) {
        chomp;
        push @array, File::Spec->catfile( $directory, $_ );
      }
      push @return, \@array;

      close $flag_fh;

    }

  }

  if( wantarray ) {
    return @return;
  } else {
    return \@return;
  }
}

=back

=head1 AUTHORS

Brad Cavanagh E<lt>b.cavanagh@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2006 Particle Physics and Astronomy Research Council.
All Rights Reserved.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or (at
your option) any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307
USA

=cut

1;
