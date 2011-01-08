package OMP::FileUtils;

=head1 NAME

OMP::FileUtils - File-related utilities for the OMP.

=head1 SYNOPSIS

  use OMP::FileUtils;

  @files =
    OMP::FileUtils->files_on_disk( 'instrument' => $inst, 'date' => $date );

=head1 DESCRIPTION

This class provides general purpose routines that are used for
handling files for the OMP system.

=cut

use 5.006;
use strict;
use warnings::register;

use File::Basename qw[ fileparse ];
use File::Spec;
use List::MoreUtils qw[ any ];
use Scalar::Util qw[ blessed ];
use OMP::Error qw[ :try ];
use OMP::Config;

our $VERSION = (qw$Revision$)[1];
our $DEBUG = 0;

=head1 METHODS

There are no instance methods, only class (static) methods.

=over 4

=item B<files_on_disk>

For a given instrument and UT date, this method returns a list of
observation files.

  my @files =
    OMP::FileUtils->files_on_disk( 'instrument' => 'CGS4',
                                   'date'       => $date,
                                 );

  my $files =
    OMP::FileUtils->files_on_disk( 'instrument' => 'CGS4',
                                   'date'       => $date,
                                   'run'        => $runnr,
                                 );

  @files =
    OMP::FileUtils->files_on_disk( 'instrument' => 'SCUBA-2',
                                   'date'       => $date,
                                   'subarray'   => $subarray,
                                   'recent'     => 2,
                                 );

The   instrument must be  a string.   The date  must be  a Time::Piece
object.  If the date  is  not passed as   a Time::Piece object then an
OMP::Error::BadArgs error  will be thrown.  The run  number must be an
integer. If the run number is not passed or is zero, then no filtering
by run number will be done.

For SCUBA2 files, a subarray must be specified (from '4a' to '4d', or
'8a' to '8d').

Optionally specify number of files older than new ones on second &
later calls to be returned. On first call, all the files will be
returned.

If called in list context, returns a list of array references. Each
array reference points to a list of observation files for a single
observation. If called in scalar context, returns a reference to an
array of array references.

=cut

sub files_on_disk {
  my ( $class, %arg ) = @_;

  my ( $instrument, $utdate, $runnr, $subarray, $old ) =
    @arg{qw[ instrument date run subarry old ]};

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
      $class->get_raw_files_from_meta( $sys_config, \%config, $flagfileregexp, $old );
  }
  else {

    @return =
      $class->get_raw_files( $directory,
                              $class->get_flag_files( $directory, $flagfileregexp, $runnr, $old ),
                              $old,
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

  my ( $class, $sys_config, $config, $flag_re, $old ) = @_;

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

  return unless $metas;

  my $read =
    _get_recent(  'files' => $metas,
                  'old'   => $old,
                  'type'  => "meta-${inst}",
                )
                or return;

  # Get flag file list by reading meta files.
  my ( @flag );
  for my $file ( @{ $read } ) {

    my $flags = OMP::General->get_file_contents( 'file' => $file,
                                                  'filter' => $flag_re,
                                                );
    next unless scalar @{ $flags };

    push @flag, map { File::Spec->catfile( $meta_dir, $_ ) } @{ $flags };
  }

  return
    $class->get_raw_files( $meta_dir,
                            _get_recent(  'files' => \@flag,
                                          'old'   => $old,
                                          'type'  => "flag-${inst}",
                                        ),
                            $old,
                          );
}

# Go through each flag file, open it, and retrieve the list of files within it.
sub get_raw_files {

  my ( $class, $dir, $flags, $old ) = @_;

  return
    unless $flags && scalar @{ $flags };

  my @raw;

  foreach my $file ( @{ $flags } ) {

    # If the flag file size is 0 bytes, then we assume that the observation file
    # associated with that flag file is of the same naming convention, removing
    # the dot from the front and replacing the .ok on the end with .sdf.
    if ( -z $file ) {

      my $raw = $class->make_raw_name_from_flag( $file );

      next unless _sanity_check_file( $raw );

      push @raw, [ $raw ];
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

    my @checked;
    for my $file ( @{ $lines } ) {

      my $f = File::Spec->catfile( $dir, $file );

      next unless _sanity_check_file( $f );

      push @checked, $f;
    }

    push @raw, [ @checked ];
  }

  my $out = _get_recent(  'files' => \@raw,
                          'old'   => $old,
                          'type'  => "raw-${dir}",
                        );
  return @{ $out };
}

sub make_raw_name_from_flag {

  my ( $class, $flag ) = @_;

  my $suffix = '.sdf';

  my ( $raw, $dir ) = fileparse( $flag, '.ok' );
  $raw =~ s/^[.]//;

  return File::Spec->catfile( $dir, $raw . $suffix );
}

sub get_flag_files {

  my ( $class, $dir, $filter, $runnr, $old ) = @_;

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

  return
    _get_recent(  'files' => $flags,
                  'old'   => $old,
                  'type'  => "flag-${dir}",
                );
}

=item B<merge_dupes>

Given an array of hashes containing header object, filename and
frameset, merge into a hash indexed by OBSID where headers have been
merged and filenames have been combined into arrays.

  %merged = OMP::FileUtils->merge_dupes( @unmerged );

In the returned merged version, header hash item will contain an
Astro::FITS::Header object if the supplied entry in @unmerged was a
simple hash reference.

Input keys:

   header - reference to hash or an Astro::FITS::Header object
   filename - single filename (optional)
   frameset - optional Starlink::AST frameset

If the 'filename' is not supplied yet a header translation reports
that FILENAME is available, the value will be stored from the
translation into the filename slot.

Output keys

   header - Astro::FITS::Header object
   filenames - reference to array of filenames
   frameset - optional Starlink::AST frameset (from first in list)

=cut

sub merge_dupes {

  my $self = shift;

  # Take local copies so that we can add information without affecting caller
  my @unmerged = map { {%$_} } @_;

  my %unique;
  for my $info ( @unmerged ) {

    # First need to work out which item corresponds to the unique observation ID
    # We do this via header translation. Since we can in principal have multiple
    # instruments we have to redetermine the class each time round the loop.

    # Convert fits header to hash if required
    my $hdr = $info->{header};
    if (blessed($hdr)) {
      tie my %header, ref($hdr), $hdr;
      $hdr = \%header;
    } else {
      # convert the header hash to a Astro::FITS::Header object so that we can easily
      # merge it later
      $info->{header} = Astro::FITS::Header->new( Hash => $hdr );
    }
    my $class;

    eval {
      $class = Astro::FITS::HdrTrans::determine_class( $hdr, undef, 1);
    };
    if ( $@ ) {

      warn sprintf "Skipped '%s' due to: %s\n",
        $info->{'filename'},
        $@;
    }

    next unless $class;

    my $obsid = $class->to_OBSERVATION_ID( $hdr, $info->{frameset} );

    # check for translated filename
    if (!exists $info->{filename}) {
      my $filename = $class->to_FILENAME( $hdr );
      if (defined $filename) {
        $info->{filename} = $filename;
      }
    }

    # store it on hash indexed by obsid
    $unique{$obsid} = [] unless exists $unique{$obsid};
    push(@{$unique{$obsid}}, $info);
  }

  # Now go through again and merge the headers and filename information for multiple files
  # but identical obsid.
  for my $obsid (keys %unique) {
    # To simplify syntax get array of headers and filenames
    my (@fits, @files, $frameset);
    for my $f (@{$unique{$obsid}}) {
      push(@fits, $f->{header});
      push(@files, $f->{filename});
      $frameset = $f->{frameset} if defined $f->{frameset};
    }

    # Merge if necessary (shift off the primary)
    my $fitshdr = shift(@fits);
    #    use Data::Dumper; print Dumper($fitshdr);
    if (@fits) {
      # need to merge
      #      print "FITS:$_\n" for @fits;
      my ( $merged, @different ) = $fitshdr->merge_primary( { merge_unique => 1 }, @fits );
      #      print Dumper(\@different);

      $merged->subhdrs( @different );
      #      print Dumper({merged => $merged, different => \@different});
      $fitshdr = $merged;
    }

    # Some queries result in duplicate rows for filename so uniqify
    # Do not use a hash directly to get the list because that would scramble
    # the original order and we get upset when the OBSIDSS does not match the filename.
    my %files_uniq;
    my @compressed;
    for my $f (@files) {
      if (!exists $files_uniq{$f}) {
        $files_uniq{$f}++;
        push(@compressed, $f);
      }
    }
    @files = @compressed;

    $unique{$obsid} = {
                       header => $fitshdr,
                       filenames => \@files,
                       frameset => $frameset,
                      };
  }

  return %unique;
}


sub _sanity_check_file {

  my ( $file, $no_warn ) = @_;

  my $read      = -r $file;
  my $exist     = -e _;
  my $non_empty = -s _;

  return 1 if $read && $non_empty;

  return if $no_warn;

  my $text =
    ! $exist
    ? 'does not exist'
    : ! $read
      ? 'is not readable'
      : ! $non_empty
        ? 'is empty'
        : 'has some UNCLASSIFIED PROBLEM'
        ;

  warn qq[$file $text (listed in flag file); skipped\n];
  return;
}

# Given a hash of array reference of file paths and the number of old
# files to return in addition to new ones, returns a list of files
# filerted by recent modification time.
#
{
  my ( %called );

  # It stores time when it was last called; returns only those files which have
  # modification time greater or equal to last called time.  On the first call,
  # it returns all the files.
  sub _get_recent {

    my ( %arg ) = @_;

    my ( $files, $old, $type ) = @arg{qw[files old type]};
    $type ||= '<default>';

    return $files unless $old && $old > 0;

    # On first run, every file is a recently updated file.
    unless ( $called{ $type } ) {

      $called{ $type } = time();
      return $files;
    }

    my $last = $called{ $type };
    # For future calls.
    $called{ $type } = time();

    my %time = _get_mod_epoch( $files )
      or return [];

    my ( @keep, @old );
    for my $time ( sort { $a <=> $b } values %time ) {

      if ( $time >= $last ) {

        push @keep, $time;
        next;
      }
      push @old, $time;
    }

    # Merge older file list.
    if ( scalar @old && $type =~ m/\b(?:flag|raw)/i )  {

      $old = 1 if ! $old || $old < 0;

      @keep = ( reverse( ( reverse @old )[ 0 .. $old - 1 ] ), @keep );
    }

    return [] unless scalar @keep;

    my @out;
    while ( my ( $file, $mod ) = each %time ) {

      push @out, $file
        if any { $mod == $_ } @keep;
    }
    return [ @out ] if scalar @out;
    return [];
  }
}

sub _get_mod_epoch {

  my ( $files ) = @_;

  my %time;
  for my $f ( @{ $files } ) {

    my ( $mod ) = ( stat $f )[9]
      or do {
              warn "Could not get modification time of '$f': $!\n";
              next;
            };

    $time{ $f } = $mod;
  }
  return %time;
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
