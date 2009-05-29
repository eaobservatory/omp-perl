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

use File::Basename qw[ fileparse ];
use File::Spec;
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

  @files =
    OMP::General->files_on_disk( 'SCUBA-2', $date, $runnr, $subarray );

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

  if( ! UNIVERSAL::isa( $utdate, "Time::Piece" ) ) {
    throw OMP::Error::BadArgs( "Date parameter to OMP::General::files_on_disk must be a Time::Piece object" );
  }

  if( ! defined( $runnr ) ||
      $runnr < 0 ) {
    $runnr = 0;
  }

  my $date = $utdate->ymd;
  $date =~ s/-//g;

  my $sys_config = OMP::Config->new;

  # Retrieve information from the configuration system.
  my $tel = $sys_config->inferTelescope( 'instruments', $instrument );

  my %config =
    (
      telescope  => $tel,
      instrument => $instrument,
      utdate     => $utdate,
      runnr      => $runnr,
      subarray   => $subarray,
    );

  my $directory = $sys_config->getData( 'rawdatadir', %config );
  my $flagfileregexp = $sys_config->getData( 'flagfileregexp',
                                              telescope => $tel,
                                            );

  # getData() throws an exception in the case of missing key.  No point in dying
  # then as default value will be used instead from earlier extraction.
  try {

    $directory = $sys_config->getData( "${instrument}.rawdatadir" , %config );

    $flagfileregexp = $sys_config->getData( "${instrument}.flagfileregexp", %config );
  }
  catch OMP::Error::BadCfgKey with {

    my ( $e  ) = @_;
    throw $e unless $e =~ /^Key.+could not be found in OMP config system/i;
  };

  my ( $use_meta, @return );

  if ( $class->use_raw_meta_opt( $sys_config, %config ) ) {

    @return =
      $class->get_raw_files_from_meta( $sys_config, \%config, $flagfileregexp );
  }
  else {

    @return =
      $class->get_raw_files( $directory,
                              $class->get_flag_files( $directory, $flagfileregexp, $runnr )
                            );
  }

  return wantarray ? @return : \@return ;
}

sub use_raw_meta_opt {

  my ( $class, $omp_config, %config ) = @_;

  my $meta;
  try {

    $meta = $omp_config
            ->getData( qq[$config{'instrument'}.raw_meta_opt], %config );
  }
  # "raw_meta_opt" may be missing entirely, considered same as a false value.
  catch OMP::Error::BadCfgKey with {

    my ( $e  ) = @_;

    throw $e
      unless $e =~ /^Key.+could not be found in OMP config system/i;
  };

  return !!$meta;
}

sub get_raw_files_from_meta {

  my ( $class, $sys_config, $config, $flag_re ) = @_;

  $flag_re = qr{$flag_re};

  # Get meta file list.
  my $inst = $config->{'instrument'};
  my ( $meta_re, $meta_date_re, $meta_dir )
    = map { $sys_config->getData( "${inst}.${_}", %{ $config } ) }
          qw[ metafileregexp
              metafiledateregexp
              metafiledir
            ];

  my $metas;
  try {

    $metas =
      OMP::General->get_directory_contents( 'dir' => $meta_dir,
                                            'filter' => qr/$meta_date_re/,
                                            'sort' => 1
                                            );
  }
  catch OMP::Error::FatalError with {

    my ( $err ) = @_;
    return
      if $err =~ /n[o']t open directory/i;
  };

  # Get flag file list by reading meta files.
  my ( @flag );
  for my $file ( @{ $metas } ) {

    my $flags = OMP::General->get_file_contents( 'file' => $file,
                                                  'filter' => $flag_re,
                                                );
    next unless scalar @{ $flags };

    push @flag, map { File::Spec->catfile( $meta_dir, $_ ) } @{ $flags };
  }

  return $class->get_raw_files( $meta_dir, \@flag );
}

# Go through each flag file, open it, and retrieve the list of files within it.
sub get_raw_files {

  my ( $class, $dir, $flags ) = @_;

  my @raw;

  foreach my $file ( @{ $flags } ) {

    # If the flag file size is 0 bytes, then we assume that the observation file
    # associated with that flag file is of the same naming convention, removing
    # the dot from the front and replacing the .ok on the end with .sdf.
    if ( -z $file ) {

      push @raw, [ $class->make_raw_name_from_flag( $file ) ];
      next;
    }

    my ( $lines, $err );
    try {

      $lines = OMP::General->get_file_contents( 'file' => $file );
    }
    catch OMP::Error::FatalError with {

      ( $err ) = @_;
      throw $err
        unless $err =~ /^Cannot open file/i;
    };
    if ( $err ) {

      warn $err;
      warn "... skipped\n";
      next;
    }

    push @raw, [ map { File::Spec->catfile( $dir, $_ ) } @{ $lines } ];
  }

  return @raw;
}

sub make_raw_name_from_flag {

  my ( $class, $flag ) = @_;

  my $suffix = '.sdf';

  my ( $raw, $dir ) = fileparse( $flag, '.ok' );
  $raw =~ s/^[.]//;

  return File::Spec->catfile( $dir, $raw . $suffix );
}

sub get_flag_files {

  my ( $class, $dir, $filter, $runnr ) = @_;

  my $flags;
  try {

    $flags =
      OMP::General->get_directory_contents( 'dir' => $dir,
                                            'filter' => $filter
                                          );
  }
  catch OMP::Error::FatalError with {

    my ( $err ) = @_;
    return
      if $err =~ /n[o']t open directory/i;
  };

  # Purge the list if runnr is not zero.
  if ( $runnr && $runnr != 0 ) {

    foreach my $f ( @{ $flags } ) {

      $f =~ /$filter/;
      if( int($1) == $runnr ) {

        $flags = [ $f ];
        last;
      }
    }
  }

  return $flags;
}

=back

=head1 AUTHORS

Brad Cavanagh E<lt>b.cavanagh@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2006-2009 Science and Technology Facilities Council.
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
