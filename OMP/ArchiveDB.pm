package OMP::ArchiveDB;

=head1 NAME

OMP::ArchiveDB - Query the data archive

=head1 SYNOPSIS

  use OMP::ArchiveDB;

  $db = new OMP::ArchiveDB(DB => new OMP::DBbackend::Archive);

=head1 DESCRIPTION

Query the data header archive. This is used to find specific header
information associated with observations. In some cases the
information may be retrieved from data headers rather than the
database (since data headers are only uploaded to the database the day
after observations are taken). Queries are supplied as
C<OMP::ArcQuery> objects.

This class provides read-only access to the header archive.

=cut

use 5.006;
use strict;
use warnings;

use OMP::ArcQuery;
use OMP::ArchiveDB::Cache;
use OMP::Error qw/ :try /;
use OMP::General;
use OMP::Info::Obs;
use OMP::Info::ObsGroup;
use OMP::Config;
use Astro::FITS::Header::NDF;
use Astro::FITS::HdrTrans;
use Astro::WaveBand;
use Astro::Coords;
use Time::Piece;
use Time::Seconds;
use SCUBA::ODF;

use vars qw/ $VERSION $FallbackToFiles /;

use Data::Dumper;
use base qw/ OMP::BaseDB /;

our $VERSION = (qw$Revision$)[1];

# Do we want to fall back to files?
$FallbackToFiles = 1;

=head1 METHODS

=over 4

=item B<getObs>

Get information about a specific observation. The observation
must be specified by date of observation (within
a second) and observation number. A telescope must be provided.
In principal a UT day, run
number and instrument are sufficient but sometimes the acquisition
system reuses observation numbers by mistake. A UT date and
run number stand a much better chance of working.

  $obsinfo = $db->getObs( $telescope, $ut, $run );

Information is returned as a C<OMP::Info::Obs> object (or C<undef>
if no observation matches).

A telescope is required since the information is stored in different
tables and it is possible that a single ut and run number will
match at multiple telescopes. This could be handled via subclassing
if it becomes endemic for the class.

ASIDE - do we do an automatic query to the ObsLog table and attach the
resulting comments?

ASIDE - Should this simply use the unique database ID? That is fine
for the database but leads to trouble with file headers from disk. A
fully specified UT date and run number is unique [in fact a UT date is
unique].

=cut

sub getObs {
  my $self = shift;
  my $tel = shift;
  my $ut = shift;
  my $runnr = shift;

  # Construct a query
  my $xml = "<ArcQuery><telescope>$tel</telescope><date>$ut</date><runnr>$runnr</runnr></ArcQuery>";
  my $query = new OMP::ArcQuery( XML => $xml );

  my @result = $self->queryArc( $query );

  if (scalar(@result) > 1) {
    throw OMP::Error::FatalError( "Multiple observations match the supplied information [Telescope=$tel UT=$ut Run=$runnr] - this is not possible [bizarre]");
  }

  # Guaranteed to be only one match
  return $result[0];

}

=item B<queryArc>

Query the archive using the supplied query (supplied as a
C<OMP::ArcQuery> object). Results are returned as C<OMP::Info::Obs>
objects.

  @obs = $db->queryArc( $query );

This method will first query the database and then look on disk. Note
that a disk lookup will only be performed if the database query
returns zero results (ie this method will not attempt to augment the
database query by adding additional matches from disk).

=cut

sub queryArc {
  my $self = shift;
  my $query = shift;

  my @results;

  # First check if the cached information is suspect.
  if( ! suspect_cache( $query ) && simple_query( $query ) ) {
    @results = retrieve_archive( $query )->obs;
  } else {

    # First the database
    if( $self->db ) {
      @results = $self->_query_arcdb( $query );
    }
    my $date = $query->daterange->min;
    my $currentdate = gmtime;

    if( ( ( $currentdate - $date ) < ONE_WEEK ) &&
        ( $FallbackToFiles ) ) {
      @results = $self->_query_files( $query )
        unless @results;
    }
  }

  # Return what we have
  return @results;
}

=back

=head2 Internal Methods

=over 4

=item B<_query_arcdb>

Query the header database and retrieve the matching observation objects.
Queries must be supplied as C<OMP::ArcQuery> objects.

  @faults = $db->_query_arcdb( $query );

Results are returned sorted by date.

=cut

sub _query_arcdb {
  my $self = shift;
  my $query = shift;

  my @return;

  # Get the SQL
  # It doesnt make sense to specify the table names from this
  # class since ArcQuery is the only class that cares and it
  # has to decide what to do on the basis of the telescope
  # part of the query. It may be possible to supply
  # subclasses for JCMT and UKIRT and put the knowledge in there.
  # since we may have to have a subclass for getObs since we
  # need to know a telescope
  my @sql = $query->sql();

  foreach my $sql (@sql) {
    # Fetch the data
    my $ref = $self->_db_retrieve_data_ashash( $sql );

    # Convert the data from a hash into an array of Info::Obs objects.
    my @reorg = $self->_reorganize_archive( $ref );

    push @return, @reorg;
  }

  if( scalar( @return ) > 0 ) {
    # Push the stuff in the cache, but only if we have results.
    try {
      store_archive( $query, new OMP::Info::ObsGroup( obs => \@return ) );
    }
    catch OMP::Error::CacheFailure with {
      my $Error = shift;
      my $errortext = $Error->{'-text'};
      print "Warning when storing archive: $errortext. Continuing.\n";
      OMP::General->log_message( $errortext );
    };

  }

  return @return;
}

=item B<_query_files>

See if the query can be met by looking at file headers on disk.
This is usually only needed during real-time data acquisition.

Queries must be supplied as C<OMP::ArcQuery> objects.

  @faults = $db->_query_files( $query );

Results are returned sorted by date.

Some queries will take a long time to implement if they require
anything more than examining data from a single night.

ASIDE: Should we provide a timeout? Should we refuse to service
queries that go over a single night?

=cut

sub _query_files {
  my $self = shift;
  my $query = shift;

  my ( $telescope, $daterange, $instrument, $runnr, $filterinst );
  my @returnarray;

  $query->isfile(1);

  my $query_hash = $query->query_hash;

  $daterange = $query->daterange;
  $instrument = $query->instrument;
  $telescope = $query->telescope;

  if( defined( $query_hash->{runnr} ) ) {
    $runnr = $query_hash->{runnr}->[0];
  } else {
    $runnr = 0;
  }

  my @instarray;

  if( defined( $instrument ) && length($instrument . "") != 0) {
    if($instrument =~ /^rx/i) { 
      $filterinst = $instrument;
      $instrument = "heterodyne";
    }
    push @instarray, $instrument;
  } elsif( defined( $telescope ) && length( $telescope . "" ) != 0 ) {
    push @instarray, OMP::Config->getData('instruments',
                                          telescope => $telescope
                                         );
  } else {
    throw OMP::Error::BadArgs( "Unable to return data. No telescope or instrument set." );
  }

  my $obsgroup;
  my @files;
  my @obs;

  # If we have a simple query, go to the cache for stored information and files
  if( simple_query( $query ) ) {
    ( $obsgroup, @files ) = unstored_files( $query );
    if( defined( $obsgroup ) ) {
      @obs = $obsgroup->obs;
    }
  } else {
    # Okay, we don't have a simple query, so get the file list the hard way.

    # We need to loop over every UT day in the date range. Get the start day and the end
    # day from the $daterange object.
    my $startday = $daterange->min->ymd;
    $startday =~ s/-//g;
    my $endday = $daterange->max->ymd;
    $endday =~ s/-//g;

    for(my $day = $startday; $day <= $endday; $day = $day + ONE_DAY) {

      foreach my $inst ( @instarray ) {

################################################################################
# KLUDGE ALERT KLUDGE ALERT KLUDGE ALERT KLUDGE ALERT KLUDGE ALERT KLUDGE ALERT
################################################################################
# We need to have all the different heterodyne instruments in the config system
# so that inferTelescope() will work. Unfortunately, we just want 'heterodyne',
# so we'll just go on to the next one if the instrument name starts with 'rx'.
################################################################################
        next if( $inst =~ /^rx/i );

        my $telescope = OMP::Config->inferTelescope('instruments', $inst);
        my $directory = OMP::Config->getData( 'rawdatadir',
                                              telescope => $telescope,
                                              utdate => $day,
                                              instrument => $inst );

################################################################################
# KLUDGE ALERT KLUDGE ALERT KLUDGE ALERT KLUDGE ALERT KLUDGE ALERT KLUDGE ALERT
################################################################################
# Because we cannot get instrument-specific directories from the configuration
# system (yet), we need to append "/pre" onto the directory retrieved for SCUBA
# observations.
################################################################################

        if( uc($inst) eq 'SCUBA' ) {
          $directory .= "/dem";
        }

        # Get a file list.
        if( -d $directory ) {
          opendir( FILES, $directory ) or throw OMP::Error( "Unable to open data directory $directory: $!" );
          @files = grep(!/^\./, readdir(FILES));
          closedir(FILES);

# INSTRUMENT SPECIFIC CODE
#
# The following line assumes that valid data files end in an observation number
# and have a ".sdf", a ".dat", or a ".gsd" suffix. If this is not the case,
# then this line will have to be modified accordingly.

          @files = grep(/_\d+\.(sdf|gsd|dat)$/, @files);
          @files = sort {

# INSTRUMENT SPECIFIC CODE
#
# The following sorting routine assumes that valid data files end in an
# observation number and have a ".sdf", ".dat", or ".gsd" suffix. If this is not
# the case, then this will have to be modified accordingly. It is possible to use
# ORAC::Frame to do this, but dependencies on ORAC classes are to be minimised.

# The following is ORAC::Frame code which can do the same thing. Slower,
# and more dependant on ORAC classes, but not instrument/telescope specific.
#          my $a_Frm = new ORAC::Frame($directory . "/" . $a);
#          my $a_obsnum = $a_Frm->number;
#          my $b_Frm = new ORAC::Frame($directory . "/" . $b);
#          my $b_obsnum = $b_Frm->number;;

            $a =~ /_(\d+)\.(sdf|gsd|dat)$/;
            my $a_obsnum = int($1);
            $b =~ /_(\d+)\.(sdf|gsd|dat)$/;
            my $b_obsnum = int($1);

            $a_obsnum <=> $b_obsnum; } @files;

          if( $runnr != 0 ) {

# INSTRUMENT SPECIFIC CODE
#
# The following code block assumes that valid data files end in an observation
# number and have a ".sdf" suffix. If this is not the case, then this block
# will have to be modified accordingly. It is possible to use ORAC::Frame to
# retrieve the observation number of a file, but dependencies on ORAC classes
# are to be minimised.

          # find the file with this run number
            $runnr = '0' x (4 - length($runnr)) . $runnr;
            @files = grep(/$runnr\.sdf$/, @files);
          } # if( $runnr != 0 )

          @files = map { $directory . '/' . $_ } @files;

        } # if ( -d $directory )
        else {
          throw OMP::Error::DirectoryNotFound( "Data directory $directory unavailable.\n" );
        }
      } # foreach my $inst ( @instarray )
    } # for( my $day... )
  } # if( simple_query( $query ) ) { } else

  foreach my $file ( @files ) {
    # Create the Obs object.
    my $obs = readfile OMP::Info::Obs( $file );
    if( !defined( $obs ) ) { next; }

    # If the observation's time falls within the range, we'll create the object.
    my $match_date = 0;

    if( $daterange->contains($obs->startobs) ) {
      $match_date = 1;
    } elsif( $daterange->max < $obs->startobs ) {
      last;
    }

    # Filter by keywords given in the query string. Look at filters other than DATE,
    # RUNNR, and _ATTR.
    # Assume a match, and if we find something that doesn't match, remove it (since
    # we'll probably always match on telescope at the very least).

    # We're only going to filter if:
    # - the thing in the query object is an OMP::Range or a scalar, and
    # - the thing in the Obs object is a scalar
    my $match_filter = 1;
    foreach my $filter (keys %$query_hash) {
      if( uc($filter) eq 'RUNNR' or uc($filter) eq 'DATE' or uc($filter) eq '_ATTR') {
        next;
      }
      foreach my $filterarray ($query_hash->{$filter}) {
        if( OMP::Info::Obs->can(lc($filter)) ) {
          my $value = $obs->$filter;
          my $matcher = uc($obs->$filter);
          if( UNIVERSAL::isa($filterarray, "OMP::Range") ) {
            $match_filter = $filterarray->contains( $matcher );
          } elsif( UNIVERSAL::isa($filterarray, "ARRAY") ) {
            foreach my $filter2 (@$filterarray) {
              if($matcher !~ /$filter2/i) {
                $match_filter = 0;
              }
            }
          }
        }
      }
    }

    if( $match_date && $match_filter ) {
      push @returnarray, $obs;
    }
  }

  # Alright. Now we have potentially two arrays: one with cached information
  # and another with uncached information. We need to merge them together. Let's
  # push the cached information onto the uncached information, then sort it, then
  # store it in the cache.
  push @returnarray, @obs;

  # We need to sort the return array by date.
  @returnarray = sort {$a->startobs->epoch <=> $b->startobs->epoch} @returnarray;

  # And store it in the cache.
  try {
    my $obsgroup = new OMP::Info::ObsGroup( obs => \@returnarray );
    store_archive( $query, $obsgroup );
  }
  catch OMP::Error::CacheFailure with {
    my $Error = shift;
    my $errortext = $Error->{'-text'};
    print "Warning: $errortext\n";
   OMP::General->log_message( $errortext );
  };

  return @returnarray;
}

=item B<_reorganize_archive>

Given the results from a database query (returned as a row per
archive item), convert this output to an array of C<Info::Obs>
objects.

  @results = $db->_reorganize_archive( $query_output );

=cut

sub _reorganize_archive {
  my $self = shift;
  my $rows = shift;

  my @return;

# For each row returned by the query, create an Info::Obs object
# out of the information contained within.
  for my $row (@$rows) {

    # Convert all the keys into upper-case.
    my $newrow;
    for my $key (keys %$row) {
      my $uckey = uc($key);
      $newrow->{$uckey} = $row->{$key};
    }
    # Find out which telescope we're dealing with. If it's UKIRT,
    # then we have to run the UKIRTDB translation. If it's JCMT,
    # we can just use the instrument-specific translation.
    my $telescope = $newrow->{TELESCOP};
    my $instrument = $newrow->{INSTRUME};
    if(defined($telescope) && $telescope =~ /UKIRT/i) {

      # We need to temporarily set the instrument header to
      # 'UKIRTDB' so the correct translation can be used.
      $newrow->{INSTRUME} = 'UKIRTDB';
    }

    # Hack to get SCUBA to be recognized.
    if(defined($newrow->{BOLOMS})) {
      $newrow->{INSTRUME} = 'SCUBA';
      $instrument = "SCUBA";
    }

    if(exists($newrow->{FRONTEND}) || exists($newrow->{C1RCV}) ) {
      $newrow->{INSTRUME} = 'HETERODYNE';
      $instrument = (defined($newrow->{FRONTEND}) ? $newrow->{FRONTEND} : $newrow->{C1RCV} );
    }

    # Create an Info::Obs object.
    my $obs = new OMP::Info::Obs( hdrhash => $newrow );

    # If the telescope is UKIRT, set the instrument back to whatever
    # it was before.
    $obs->instrument( $instrument );

    # Check the filename. If it's not set, call file_from_bits and set it.
    if( !defined( $obs->filename ) ) {
      $obs->filename( $obs->file_from_bits );
    }

    # And push it onto the @return array.
    push @return, $obs;
  }

  return @return;

}

=back

=head1 SEE ALSO

This class inherits from C<OMP::BaseDB>.

For related classes see C<OMP::ProjDB> and C<OMP::FeedbackDB>,
C<OMP::ArcQuery>.

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>
Brad Cavanagh E<lt>b.cavanagh@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
