package OMP::ArchiveDB::Cache;

=head1 NAME

OMP::ArchiveDB::Cache - Provide a cache for the C<OMP::ArchiveDB>
class.

=head1 SYNOPSIS

use OMP::ArchiveDB::Cache;

=head1 DESCRIPTION

This class provides a cache for the C<OMP::ArchiveDB> class, by
taking C<OMP::ArcQuery> queries and C<OMP::Info::ObsGroup> objects
and storing them temporarily on disk, which allows for them to be
quickly retrieved at a later time. This provides a quicker retrieval
of information from data files that are located on disk.

It can also, given an C<OMP::ArcQuery> query, return a list of files
that are not already in the cache.

=cut

use 5.006;
use strict;
use warnings;

use OMP::ArcQuery;
use OMP::Config;
use OMP::Error qw/ :try /;
use OMP::Info::Obs;
use OMP::Info::ObsGroup;
use OMP::Range;

use Fcntl qw/ :DEFAULT :flock /;
use Storable qw/ nstore_fd fd_retrieve /;
use Time::Piece qw/ :override /;
use Time::Seconds;

our $VERSION = (qw$Revision$)[1];

our $TEMPDIR = OMP::Config->getData( 'cachedir' );

require Exporter;

our @ISA = qw/Exporter/;
our @EXPORT = qw( store_archive retrieve_archive cached_on suspect_cache unstored_files
                  simple_query );
our %EXPORT_TAGS = (
                    'all' => [ @EXPORT ]
                    );

Exporter::export_tags( qw/ all / );

=head1 METHODS

=over 4

=item B<store_archive>

Store information about an C<OMP::ArcQuery> query and an
C<OMP::Info::ObsGroup> object to a temporary file.

  store_archive( $query, $obsgrp );

Only queries that are made up only of a combination of
telescope, instrument, date, and projectid
will be cached. Exotic queries (such as ranges other than
date ranges) are not supported.

=cut

sub store_archive {
  my $query = shift;
  my $obsgrp = shift;

  if( ! defined( $query ) ) {
    throw OMP::Error::BadArgs( "Must supply a query to store information in cache" );
  }
  if( ! defined( $obsgrp ) ) {
    throw OMP::Error::BadArgs( "Must supply an ObsGroup object to store information in cache" );
  }

  # Check to make sure the cache directory exists. If it doesn't, create it.
  if( ! -d $TEMPDIR ) {
    mkdir $TEMPDIR;
    chmod 0777, $TEMPDIR;
  }

  # Get the filename.
  my $filename = _filename_from_query( $query );

  # Do a fairly blind untaint
  if ($filename =~ /^([A-Za-z\-:0-9\/]+)$/) {
    $filename = $1;
  } else {
    throw OMP::Error::FatalError("Error untaininting the filename $filename");
  }

  # If the query is for the current day we should remove the last
  # observation from the cache just in case the data have been read
  # whilst the file is open for write (this is true for GSD observations
  # since they are always appended to during acquisition)
  if ($query->istoday) {
    # Get reference to array of observation objects
    my $ref = $obsgrp->obs;
    # remove last
    pop(@$ref);
  }


  # Store the ObsGroup to disk.
  try {
    sysopen( DF, $filename, O_RDWR|O_CREAT, 0666);
    flock(DF, LOCK_EX);
    nstore_fd($obsgrp, \*DF);
    truncate(DF, tell(DF));
    close(DF);
  }
  catch Error with {
    throw OMP::Error::CacheFailure( $! );
  };

  # Chmod the file so others can read and write it.
  chmod 0666, $filename;

}

=item B<retrieve_archive>

Retrieve information about an C<OMP::ArcQuery> query
from temporary files.

  $obsgrp = retrieve_archive( $query );

Returns an C<OMP::Info::ObsGroup> object, or undef if
no results match the given query.

Only queries that are made up of a combination of
telescope, instrument, date, and projectid
will be cached. Exotic queries (such as ranges other than
date ranges) are not supported.

=cut

sub retrieve_archive {
  my $query = shift;

  if( ! defined( $query ) ) {
    throw OMP::Error::BadArgs( "Must supply a query to retrieve information from cache" );
  }

  my $obsgrp;

  # Get the filename of whatever it is we're getting.
  my $filename = _filename_from_query( $query );

  # Retrieve the ObsGroup object, if it exists.
  if( -e $filename ) {
    open(DF, "< " . $filename);
    flock(DF, LOCK_SH);
    $obsgrp = fd_retrieve( \*DF );

    # Because the comments may have changed since the cache
    # was created, we need to get them again.
    $obsgrp->commentScan;
  }

  # And return.
  return $obsgrp;

}

=item B<unstored_files>

Return a list of files currently existing on disk that match
the given C<OMP::ArcQuery> query, yet do not have information
about them stored in the cache, and additionally return the
C<OMP::Info::ObsGroup> object corresponding to the data stored
in the cache.

  ( $obsgrp, @files ) = unstored_files( $query );

Returns an C<OMP::Info::Obsgroup> object, or undef if no
information about the given query is stored in the cache,
and a list of strings, or undef if all files on disk that
match the query have information stored in the cache.

The query must include either a telescope or an instrument.
No sanity checking is done if both are given and the instrument
is not used at that specific telescope. If both are given,
instrument will be used.

=cut

sub unstored_files {
  my $query = shift;

  if( ! defined( $query ) ) {
    throw OMP::Error::BadArgs( "Must supply a query to retrieve list of files not existing in cache" );
  }

  my @difffiles;
  my @files;
  my @ofiles;

  my $obsgrp = retrieve_archive( $query );

  # Get a list of files that are stored in the cache.
  if( defined( $obsgrp ) ) {
    my @obs = $obsgrp->obs;
    @ofiles = map { $_->filename } @obs;
  }

  my $telescope;
  # Need a try block because $query->telescope will throw
  # an exception if there's no telescope, and we want that
  # to fail silently.
  try {
    $telescope = $query->telescope;
  } catch OMP::Error::DBMalformedQuery with { };

  my $instrument = $query->instrument;

  my @insts;
  if( defined( $instrument ) ) {
    if($instrument =~ /^rx/i) {
      push @insts, 'heterodyne';
    } else {
      push @insts, $instrument;
    }
  } elsif( defined( $telescope ) ) {
    # Need to make sure we kluge the rx -> heterodyne conversion
    my @initial = OMP::Config->getData('instruments',
				       telescope => $telescope
				      );

    my $ishet = 0;
    for my $inst (@initial) {
      if ($inst =~ /^rx/i || $inst eq 'heterodyne') {
	$ishet = 1;
	next;
      }
      push(@insts, $inst);
    }
    push(@insts, "heterodyne") if $ishet;

  }

  my @ifiles;
  for(my $day = $query->daterange->min; $day <= $query->daterange->max; $day = $day + ONE_DAY) {

    foreach my $inst ( @insts ) {

      my $tel = OMP::Config->inferTelescope( 'instruments', $inst );
      my $directory = OMP::Config->getData( 'rawdatadir',
                                            telescope => $tel,
                                            instrument => $inst,
                                            utdate => $day,
                                          );

      $directory =~ s/\/dem$// unless $inst =~ /scuba/i;

      next unless -d $directory;

      opendir( FILES, $directory ) or throw OMP::Error( "Unable to open data directory $directory: $!" );
      @ifiles = grep(!/^\./, readdir(FILES));

      closedir(FILES);

      my $regexp = OMP::Config->getData( 'filenameregexp',
                                         telescope => $tel,
                                       );
      @ifiles = grep /$regexp/, @ifiles;
      @ifiles = sort {
        $a =~ /_(\d+)\.(sdf|dat)$/;
        my $a_obsnum = int($1);
        $b =~ /_(\d+)\.(sdf|dat)$/;
        my $b_obsnum = int($1);
        $a_obsnum <=> $b_obsnum; } @ifiles;
      @ifiles = map { $directory . '/' . $_ } @ifiles;

      push @files, @ifiles;
    }
  }

  # At this point we have two arrays, one (@ofiles) containing
  # a list of files that have already been cached, and the
  # other (@files) containing a list of all files applicable
  # to this query. We need to find all the files that exist
  # in the second array but not the first.

  my %seen;
  @seen{@ofiles} = ();

  foreach my $item (@files) {
    push( @difffiles, $item ) unless exists $seen{$item};
  }
  return ( $obsgrp, @difffiles );
}

=item B<cached_on>

Return the UT date on which the cache for the given query was
written.

  $ut = cached_on( $query );

Returns a C<Time::Piece> object if the cache for the given
query exists, otherwise returns undef.

=cut

sub cached_on {
  my $query = shift;

  if( ! defined( $query ) ) {
    throw OMP::Error::BadArgs( "Must supply a query to retrieve a date" );
  }

  my $filename = _filename_from_query( $query );

  my $tp;

  if( -e $filename ) {
    my $time = (stat( $filename ))[9];
    $tp = gmtime( $time );
  }

  return $tp;
}

=item B<suspect_cache>

Is the cache file for the given query suspect?

  $suspect = suspect_cache( $query );

A cache file is suspect if the file was written on the same
UT date as the date (either the date outright or the starting
date in a range) in the query. Returns true if the cache file
is suspect and false if it is not.

=cut

sub suspect_cache {
  my $query = shift;

  if( ! defined( $query ) ) {
    throw OMP::Error::BadArgs( "Must supply a query to retrieve a date" );
  }

  my $filetime = cached_on( $query );
  my $querytime = $query->daterange->min;

  if( ! defined( $filetime ) ) {
    return 1;
  }

  if( abs( $filetime - $querytime ) > ( ONE_DAY * 2 ) ) {
    return 0;
  } else {
    return 1;
  }
}

=item B<simple_query>

Is the query simple enough to be cached?

  $simple = simple_query( $query );

A query is simple if it is made up of a combination of only the
following things: instrument, telescope, projectid, and a date
range. If any accessors other than those four exist in the query,
then the query is not simple and cannot be cached.

Returns true if the query is simple and false otherwise.

=cut

sub simple_query {
  my $query = shift;

  my $isfile = $query->isfile;
  $query->isfile(1);

  my $query_hash = $query->query_hash;

  my $simple = 1;

  foreach my $key ( keys %$query_hash ) {
    if( uc( $key ) ne 'DATE' and
        uc( $key ) ne 'INSTRUMENT' and
        uc( $key ) ne 'TELESCOPE' and
        uc( $key ) ne 'PROJECTID' and
        uc( $key ) ne '_ATTR' ) {
      $simple = 0;
      last;
    }
  }

  $query->isfile($isfile);

  return $simple;
}

=back

=head1 PRIVATE METHODS

=over 4

=item B<_filename_from_query>

Return a standard filename given an C<OMP::ArcQuery> object.

  $filename = _filename_from_query( $query );

The filename will include the path to the file.

Only queries that are made up of a combination of
telescope, instrument, date, and projectid
will be cached. Exotic queries (such as ranges other than
date ranges) are not supported.

=cut

sub _filename_from_query {
  my $query = shift;

  if( ! defined( $query ) ) {
    throw OMP::Error::BadArgs( "Must supply a query to get a filename" );
  }

  my $isfile = $query->isfile;
  $query->isfile(1);

  my $qhash = $query->query_hash;

  my ( $telescope, $instrument, $startdate, $enddate, $projectid );
  my $filename = $TEMPDIR . "/";

  if( defined( $qhash->{'telescope'} ) ) {
    if( ref( $qhash->{'telescope'} ) eq "ARRAY" ) {
      $telescope = $qhash->{telescope}->[0];
    } else {
      $telescope = $qhash->{telescope};
    }
  }

  if( defined( $qhash->{'instrument'} ) ) {
    if( ref( $qhash->{'instrument'} ) eq "ARRAY" ) {
      $instrument = $qhash->{instrument}->[0];
    } else {
      $instrument = $qhash->{instrument};
    }
  }

  if( defined( $qhash->{'projectid'} ) ) {
    if( ref( $qhash->{'projectid'} ) eq "ARRAY" ) {
      $projectid = $qhash->{projectid}->[0];
    } else {
      $projectid = $qhash->{projectid};
    }
  }

  my $daterange;
  if( ref( $qhash->{date} ) eq 'ARRAY' ) {
    if (scalar( @{$qhash->{date}} ) == 1) {
      my $timepiece = new Time::Piece;
      $timepiece = $qhash->{date}->[0];
      my $maxdate;
      if( ($timepiece->hour == 0) && ($timepiece->minute == 0) && ($timepiece->second == 0) ) {
        # We're looking at an entire day, so set up an OMP::Range object with Min equal to this
        # date and Max equal to this date plus one day.
        $maxdate = $timepiece + ONE_DAY - 1; # constant from Time::Seconds
      } else {
        # We're looking at a specific time, so set up an OMP::Range object with Min equal to
        # this date minus one second and Max equal to this date plus one second. These plus/minus
        # seconds are necessary because OMP::Range does an exclusive check instead of inclusive.
        $maxdate = $timepiece + 1;
        $timepiece = $timepiece - 1;
      }
      $daterange = new OMP::Range( Min => $timepiece, Max => $maxdate );
    }
  } elsif( UNIVERSAL::isa( $qhash->{date}, "OMP::Range" ) ) {
    $daterange = $qhash->{date};
    # Subtract one second from the range, because the max date is not inclusive.
    my $max = $daterange->max;
    $max = $max - 1;
    $daterange->max($max);
  }

  if( defined( $daterange ) ) {
    $startdate = $daterange->min->datetime;
    $enddate = $daterange->max->datetime;
  }

  $filename .= ( defined( $startdate ) ? $startdate : "" );
  $filename .= ( defined( $enddate ) ? $enddate : "" );
  $filename .= ( defined( $telescope ) ? $telescope : "" );
  $filename .= ( defined( $instrument ) ? $instrument : "" );
  $filename .= ( defined( $projectid ) ? $projectid : "" );

  $query->isfile($isfile);

  return $filename;
}

=back

=head1 SEE ALSO

For related classes see C<OMP::ArcQuery>, C<OMP::ArchiveDB>, and
C<OMP::Info::Group>.

=head1 AUTHORS

Brad Cavanagh E<lt>b.cavanagh@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
