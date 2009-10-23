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
use OMP::FileUtils;
use Starlink::AST;
use Carp;

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

# In-memory cache
my %MEMCACHE;

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
  my $retainhdr = shift;

  if( ! defined( $query ) ) {
    throw OMP::Error::BadArgs( "Must supply a query to store information in cache" );
  }
  if( ! defined( $obsgrp ) ) {
    throw OMP::Error::BadArgs( "Must supply an ObsGroup object to store information in cache" );
  }

  $retainhdr = ( defined( $retainhdr ) ? $retainhdr : 0 );

  # Check to make sure the cache directory exists. If it doesn't, create it.
  if( ! -d $TEMPDIR ) {
    mkdir $TEMPDIR
      or throw OMP::Error::CacheFailure( "Error creating temporary directory for cache: $!" );
    chmod 0777, $TEMPDIR;
  }

  # Get the filename.
  my $filename = _filename_from_query( $query );

  # Do a fairly blind untaint
  if ($filename =~ /^([A-Za-z\-:0-9\/_]+)$/) {
    $filename = $1;
  } else {
    throw OMP::Error::FatalError("Error untaininting the filename $filename");
  }

  # Should probably strip all comments to save space (since in general
  # we can not trust the comments when we re-read the cacche at a later date)
  # Should we make sure we work on copies here?
  # It seems that comments are already gone by this point
  for my $obs ($obsgrp->obs) {
    @{$obs->comments} = ();
  }

  # If the query is for the current day we should remove the last
  # observation for each instrument from the cache just in case the data
  # have been read whilst the file is open for write (this is true for
  # GSD observations since they are always appended to during acquisition)
  if ($query->istoday) {

    my @all_obs;
    my %grouped = $obsgrp->groupby('instrument');
    foreach my $inst (keys %grouped) {
      # $grouped{$inst} is an ObsGroup object of only that instrument.
      # They're not sorted, of course, so sort by time.
      $grouped{$inst}->sort_by_time;

      # Grab all of the Obs objects.
      my @obs = $grouped{$inst}->obs;

      # Remove the last one.
      pop(@obs);

      # And push it onto our holding array.
      push(@all_obs, @obs);
    }

    # Re-form our ObsGroup object.
    $obsgrp->obs( @all_obs );
  }

  # Store in memory cache (using a new copy) [if we have some observations]
  $MEMCACHE{$filename} = new OMP::Info::ObsGroup( obs => scalar( $obsgrp->obs ),
                                                  retainhdr => $retainhdr )
    if scalar(@{$obsgrp->obs}) > 0;

  # Store the ObsGroup to disk.
  try {
    sysopen( my $df, $filename, O_RDWR|O_CREAT, 0666)
      or croak "Unable to write to cache file: $filename: $!";

    flock($df, LOCK_EX);
    nstore_fd($obsgrp, $df)
      or croak "Cannot store to $filename";
    truncate($df, tell($df));
    close($df);
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

  $obsgrp = retrieve_archive( $query, $return_if_suspect );

Returns an C<OMP::Info::ObsGroup> object, or undef if
no results match the given query.

The second optional argument is a boolean determining whether
or not the method should return with C<undef> if the cache
is suspect. See the C<suspect_cache> method for further
information. If this argument is not given, this method
will return C<undef> if the cache is suspect.

Only queries that are made up of a combination of
telescope, instrument, date, and projectid
will be cached. Exotic queries (such as ranges other than
date ranges) are not supported.

Observation comments are not added by this routine since they are
probably invalid anyway (they can be changed at any time, whereas the
data headers are constant once written). Use the C<commentScan> method
of C<OMP::Info::ObsGroup> to add the comments.

=cut

sub retrieve_archive {
  my $query = shift;
  my $return_if_suspect = shift;
  my $retainhdr = shift;

  if( ! defined( $query ) ) {
    throw OMP::Error::BadArgs( "Must supply a query to retrieve information from cache" );
  }

  $return_if_suspect = ( defined( $return_if_suspect ) ? $return_if_suspect : 1 );

  $retainhdr = ( defined( $retainhdr ) ? $retainhdr : 0 );

  my $obsgrp;

  # Is this a simple query?
  if( !simple_query( $query ) ) { return; }

  # Is this a suspect cache?
  if( $return_if_suspect && suspect_cache( $query ) ) { return; }

  # Check to see

  # Get the filename of whatever it is we're getting.
  my $filename = _filename_from_query( $query );

  # Retrieve the ObsGroup object, if it exists. Prefer in memory version
  if (exists $MEMCACHE{$filename}) {

    $obsgrp = $MEMCACHE{$filename};
  } else {

    # Try to grab the ObsGroup object from on-disk cache.
    try {

      # Try to open the file. If there's an error, throw an exception.
      open(my $df, '<', $filename)
        or throw OMP::Error::CacheFailure("Failure to open cache $filename: $!");

      # We've opened the file, so lock it for reading.
      flock($df, LOCK_SH);

      # Grab the last-written time for the file and the start time
      # of the query. If they're different by less than two days, return
      # because the cache will be suspect, and we'll just resort to
      # database or files.
      my $filetime = gmtime( (stat( $filename ))[9] );
      my $querytime = $query->daterange->min;
      if( abs( $filetime - $querytime ) < ( ONE_DAY * 2 ) ) { return; }

      # It's all good, so retrieve the cache from the file.
      $obsgrp = fd_retrieve( $df );
    }
    catch OMP::Error::CacheFailure with {

      # Just write the error to log.
      my $Error = shift;
      my $errortext = $Error->{'-text'};

      OMP::General->log_message( "Error in archive cache read: $errortext" );
    };

    # Return if we didn't get an ObsGroup from the cache, since we can't return
    # inside the catch block.
    if(!defined($obsgrp)) {

      return;
    }

    # Store in memory cache for next time around
    $MEMCACHE{$filename} = new OMP::Info::ObsGroup( obs => scalar( $obsgrp->obs ),
                                                    retainhdr => $retainhdr )
      if scalar(@{$obsgrp->obs}) > 0;
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

  my @ofiles;

  # We want to have a cache returned for us, even if it's suspect.
  my $return_if_suspect = 0;
  my $obsgrp = retrieve_archive( $query, $return_if_suspect );

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

  my $runnr;
  my $query_hash = $query->query_hash;
  if( defined( $query_hash->{runnr} ) ) {
    $runnr = $query_hash->{runnr}->[0];
  } else {
    $runnr = 0;
  }

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

      next if( $inst =~ /^rx/i );

      my @files = OMP::FileUtils->files_on_disk( $inst, $day, $runnr );

      push @ifiles, @files;
    }
  }

  # At this point we have two arrays, one (@ofiles) containing
  # a list of files that have already been cached, and the
  # other (@ifiles) containing a list of all files applicable
  # to this query. We need to find all the files that exist
  # in the second array but not the first.

  my %seen;
  @seen{@ofiles} = ();

  my @return;
  foreach my $arr_ref (@ifiles) {
    my @difffiles;
    foreach my $item ( @$arr_ref ) {
      push( @difffiles, $item ) unless exists $seen{$item};
    }
    push @return, \@difffiles;
  }

  return ( $obsgrp, @return );
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
    $projectid =~ s!\/!!g;
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
    $enddate = ( $daterange->max != -1 ? $daterange->max->datetime : undef );
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
