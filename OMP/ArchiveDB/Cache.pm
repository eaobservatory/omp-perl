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
use OMP::Info::Obs;
use OMP::Info::ObsGroup;

use Storable qw/ nstore retrieve /;

our $VERSION = (qw$Revision$)[1];

our $TEMPDIR = "/tmp/archivecache/";

=head1 METHODS

=over 4

=item B<store_archive>

Store information about an C<OMP::ArcQuery> query and an
C<OMP::Info::ObsGroup> object to a temporary file.

  store_archive( $query, $obsgrp );

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

}

=item B<retrieve_archive>

Retrieve information about an C<OMP::ArcQuery> query
from temporary files.

  $obsgrp = retrieve_archive( $query );

Returns an C<OMP::Info::ObsGroup> object, or undef if
no results match the given query.

=cut

sub retrieve_archive {
  my $query = shift;

  if( ! defined( $query ) ) {
    throw OMP::Error::BadArgs( "Must supply a query to retrieve information from cache" );
  }

  my $obsgrp;

  return $obsgrp;

}

=item B<unstored_files>

Return a list of files currently existing on disk that match
the given C<OMP::ArcQuery> query, yet do not have information
about them stored in the cache.

  @files = unstored_files( $query );

Returns a list of strings, or undef if all files on disk that
match the query have information stored in the cache.

=cut

sub unstored_files {
  my $query = shift;

  if( ! defined( $query ) ) {
    throw OMP::Error::BadArgs( "Must supply a query to retrieve list of files not existing in cache" );
  }

  my @files;


  return @files;
}

1;
