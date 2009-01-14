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

use OMP::Error qw[ :try ];

our $VERSION = (qw$Revision$)[1];
our $DEBUG = 0;

=head1 METHODS

There are no instance methods, only class (static) methods.

=over 4

=item B<files_on_disk>

For a given instrument and UT date, this method returns a list of
observation files.

  my @files = OMP::General->files_on_disk( 'CGS4', $date, $runnr );
  my $files = OMP::General->files_on_disk( 'CGS4', $date, $runnr );

  @files = OMP::General->files_on_disk( 'SCUBA2', $date, $runnr, $subarray );

The   instrument must be  a string.   The date  must be  a Time::Piece
object.  If the date  is  not passed as   a Time::Piece object then an
OMP::Error::BadArgs error  will be thrown.  The run  number must be an
integer. If the run number is not passed or is zero, then no filtering
by run number will be done.

For SCUBA2 files, a subarray must be specified (from '4a' to '4d', or
'8a' to '8d').

If called in list context, returns a list of array references. Each
array reference points to a list of observation files for a single
observation. If called in scalar context, returns a reference to an
array of array references.

=cut

sub files_on_disk {
  my ( $class, $instrument, $utdate, $runnr, $subarray ) = @_;

  my @return;

  if( ! UNIVERSAL::isa( $utdate, "Time::Piece" ) ) {
    throw OMP::Error::BadArgs( "Date parameter to OMP::General::files_on_disk must be a Time::Piece object" );
  }

  if( ! defined( $runnr ) ||
      $runnr < 0 ) {
    $runnr = 0;
  }

  my $date = $utdate->ymd;
  $date =~ s/-//g;

  # Retrieve information from the configuration system.
  my $tel = OMP::Config->inferTelescope( 'instruments', $instrument );

  my %config =
    (
      telescope  => $tel,
      instrument => $instrument,
      utdate     => $utdate,
      runnr      => $runnr,
      subarray   => $subarray,
    );

  my $directory = OMP::Config->getData( 'rawdatadir', %config );
  my $flagfileregexp = OMP::Config->getData( 'flagfileregexp',
                                              telescope => $tel,
                                            );

  # getData() throws an exception in the case of missing key.  No point in dying
  # then as default value will be used instead from earlier extraction.
  try {

    $directory = OMP::Config->getData( "${inst}.rawdatadir" , %config );

    $flagfileregexp = OMP::Config->getData( "${inst}.flagfileregexp", %config );
  }
  catch OMP::Error::BadCfgKey with {

    my ( $e  ) = @_;
    throw $e unless $e =~ /^Key.+could not be found in OMP config system/i;
  };

  # Open the directory.
  opendir( OMP_DIR, $directory );

  # Get the list of files that match the flag file regexp.
  my @flag_files = sort grep ( /$flagfileregexp/, readdir( OMP_DIR ) );

  # Purge the list if runnr is not zero.
  if( $runnr != 0 ) {
    foreach my $flag_file ( @flag_files ) {
      $flag_file =~ /$flagfileregexp/;
      if( int($1) == $runnr ) {
        @flag_files = [];
        push @flag_files, $flag_file;
        last;
      }
    }
  }

  @flag_files = map { File::Spec->catfile( $directory, $_ ) } @flag_files;

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
