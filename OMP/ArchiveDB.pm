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
use OMP::Constants qw/ :logging /;
use OMP::Error qw/ :try /;
use OMP::General;
use OMP::Info::Obs;
use OMP::Info::ObsGroup;
use OMP::Config;
use OMP::FileUtils;
use Astro::FITS::Header::NDF;
use Astro::FITS::HdrTrans;
use Astro::WaveBand;
use Astro::Coords;
use Time::Piece;
use Time::Seconds;
use NDF;
use SCUBA::ODF;

use vars qw/ $VERSION $FallbackToFiles $SkipDBLookup $AnyDate /;

use Scalar::Util qw/ blessed /;
use Data::Dumper;
use base qw/ OMP::BaseDB /;

our $VERSION = (qw$Revision$)[1];

search_db_skip_today();
search_files();

# Cache a hash of files that we've already warned about.
our %WARNED;

=head1 METHODS

=over 4

=item B<search_db>

Sets options to search database including current date.  It does not change
existing file search options.

Returns nothing.

=cut

sub search_db {

  $AnyDate = 1;
  $SkipDBLookup = 0;
  return;
}

=item B<search_db_skip_today>

Sets options to search database not including current date.  It does not change
existing file search options.

Returns nothing.

=cut

sub search_db_skip_today {

  $AnyDate = 0;
  $SkipDBLookup = 0;
  return;
}

=item B<search_files>

Sets options to search for files.  It does not change existing database options.

Returns nothing.

=cut

sub search_files {

  $FallbackToFiles = 1;
  return;
}

=item B<search_only_db>

Sets options to search only the database.  It disables file search options.

Returns nothing.

=cut

sub search_only_db {

  search_db();
  $FallbackToFiles = 0;
  return;
}

=item B<search_only_files>

Sets options to search only for the files.  It disables database search options.

Returns nothing.

=cut

sub search_only_files {

  $AnyDate = 0;
  $SkipDBLookup = 1;
  search_files();
  return;
}

=item B<use_existing_criteria>

Given no arguments, returns a truth value indicating if to use
existing search options (or to calculate new ones (see above)).

  $db->set_search_criteria()
    unless $db->use_existing_criteria;

Provide a truth value to inidicate to toggle use of existing criteria.

  $db->search_only_files();
  $db->use_existing_criteria( 1 );

=cut

my $old_criteria;
sub use_existing_criteria {

  my $self = shift @_;

  return $old_criteria unless scalar @_;

  $old_criteria = !! $_[0];
  return;
}

=item B<set_search_criteria>

Returns the search ciretia word found; else return nothing.

Given an optional telescope name and/or optional search criteria, sets
the places to search.  Default is set to search in database (excluding
current date) & for files.

  OMP::ArchiveDB->set_search_criteria();

Sets search criteria by getting I<header_search> option value from
"ini" style configuration file for JCMT ...

  OMP::ArchiveDB->set_search_criteria( 'telescope' => 'jcmt' );

Directly specfiy a search criteria (files only search in this case)
...

  OMP::ArchiveDB->set_search_criteria( 'header_search' => 'files' );

Valid values for I<header_search> are ...

  db       - search only database, including current date

  files    - search only for files

  db-files - search database, and files if database returns nothing

  db-skip-today-files - search both database & files; change from
                        previous criteria is that current date is
                        skipped from database serach

If both, C<telescope> & C<header_search> are sepecifed, then defined
C<header_search> value will bypass telescope configuration file.

=cut

sub set_search_criteria {

  my ( $self, %opt ) = @_;

  my $search_opt = 'header_search';
  my $where = $opt{ $search_opt };

  my $tel = $opt{'telescope'};

  my %search =
    ( 'db'   => \&search_only_db,
      'files' => \&search_only_files,
      'db-files' =>
        sub{ search_db(); return search_files(); },

      'db-skip-today-files' =>
        sub{ search_db_skip_today(); return search_files(); },
    );

  # Default options.
  return $search{'db-skip-today-disk' }->()
    if ! $tel
    && ! defined $where;

  # Search database for current date too.
  search_db() if lc $tel eq 'jcmt';

  unless ( defined $where ) {

    try {

      $where = OMP::Config->getData( $search_opt,
                                      'telescope' => $tel,
                                    );
    }
    catch OMP::Error::BadCfgKey with {

      my ( $e ) = @_;

      my $text = $e->text;

      # Ignore missing key.
      throw $e
        unless $text =~ m/Key.*?\b$search_opt\b.*?could not be found/;
    };
  }

  return
    unless defined $where
      && length $where ;

  throw OMP::Error::BadArgs "Unknown search criteria, '$where', given\n"
    unless exists $search{ $where };

  $search{ $where }->();
  return $where;
}

=item B<getObs>

Get information about a specific observation. The observation
must be specified by date of observation (within
a second) and observation number. A telescope must be provided.
In principal a UT day, run
number and instrument are sufficient but sometimes the acquisition
system reuses observation numbers by mistake. A UT date and
run number stand a much better chance of working.

  $obsinfo = $db->getObs( telescope => $telescope,
                          ut => $ut,
                          runnr => $runnr );

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
  my %args = @_;

  my $xml = "<ArcQuery>";
  if ( defined( $args{telescope} ) && length( $args{telescope} ) ) {
    $xml .= "<telescope>" . $args{telescope} . "</telescope>";
  }
  if ( defined( $args{runnr} ) && length( $args{runnr} ) ) {
    $xml .= "<runnr>" . $args{runnr} . "</runnr>";
  }
  if ( defined( $args{instrument} ) && length( $args{instrument} ) ) {
    $xml .= "<instrument>" . $args{instrument} . "</instrument>";
  }
  if ( defined( $args{ut} ) && length( $args{ut} ) ) {
    $xml .= "<date delta=\"1\">" . $args{ut} . "</date>";
  }

  $xml .= "</ArcQuery>";

  # Construct a query
  my $query = new OMP::ArcQuery( XML => $xml );

  my @result = $self->queryArc( $query );

  # Just return the first result.
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
  my ( $self, $query, $retainhdr, $ignorebad, $search ) = @_;

  my $tel = $query->telescope;

  if ( !defined( $retainhdr ) ) {
    $retainhdr = 0;
  }

  if ( ! defined( $ignorebad ) ) {
    $ignorebad = 0;
  }

  my $grp = retrieve_archive( $query, 1, $retainhdr );

  if (defined($grp)) {
    return $grp->obs;
  }

  # Check to see if the global flags $FallbackToFiles and
  # $SkipDBLookup are set such that neither DB nor file
  # lookup can happen. If that's the case, then throw an
  # exception.
  if ( !$FallbackToFiles && $SkipDBLookup ) {
    throw OMP::Error("FallbackToFiles and SkipDBLookup are both set to return no information.");
  }

  my $date = $query->daterange->min;
  my $currentdate = gmtime;

  # Determine time difference in seconds
  my $tdiff = $currentdate - $date;

  # Determine whether we are "today"
  my $istoday = $query->istoday;

  # Control whether we have queried the DB or not
  # True means we have done a successful query.
  my $dbqueryok = 0;

  my @results;

  unless ( $self->use_existing_criteria() ) {

    $self->set_search_criteria( ref $search ? %{ $search } : (),
                                'telescope' => $tel,
                              );

    # Undo database lookup avoidance as old data will certainly be in database,
    # but possibly missing from disk.
    $SkipDBLookup = 0
      unless $istoday ;
  }

  # First go to the database if we're looking for things that are
  # older than three days and we've been told not to skip the DB
  # lookup.
  if ( ( !$istoday || $AnyDate ) && !$SkipDBLookup) {

    # Check for a connection. If we have one, good, but otherwise
    # set one up.
    if ( ! defined( $self->db ) ) {
      $self->db( new OMP::DBbackend::Archive );
    }

    # Trap errors with connection. If we have fatal error
    # talking to DB we should fallback to files (if allowed)
    try {
      @results = $self->_query_arcdb( $query, $retainhdr );
      $dbqueryok = 1;
    } otherwise {
      my $Error = shift;
      my $errortext = $Error->{'-text'};

      OMP::General->log_message( "Header DB query problem: $errortext", OMP__LOG_WARNING );
      # just need to drop through and catch any exceptions
    };
  }

  # if we do not yet have results we should query the file system
  # unless forbidden to do so for some reason (this was originally
  # because we threw an exception if the directories did not exist).
  if ($FallbackToFiles) {

    # We fallback to files if the query failed in some way
    # (no connection, or error from the query)
    # OR if the query succeded but we can not be sure the data are
    # in the DB yet (ie less than a week)
    if ( !$dbqueryok ||       # Always look to files if query failed
          (!@results)          # look to files if we got no results
        ) {

      # then go to files
      OMP::General->log_message("Querying disk files", OMP__LOG_DEBUG);
      @results = $self->_query_files( $query, $retainhdr, $ignorebad );
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
  my $retainhdr = shift;

  if ( !defined( $retainhdr ) ) {
    $retainhdr = 0;
  }

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
    my @reorg = $self->_reorganize_archive( $ref, $retainhdr );

    push @return, @reorg;
  }

  if ( scalar( @return ) > 0 ) {
    # Push the stuff in the cache, but only if we have results.
    try {
      store_archive( $query, new OMP::Info::ObsGroup( obs => \@return ) );
    }
      catch OMP::Error::CacheFailure with {
        my $Error = shift;
        my $errortext = $Error->{'-text'};
        print STDERR "Warning when storing archive: $errortext. Continuing.\n";
        OMP::General->log_message( $errortext, OMP__LOG_WARNING );
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
  my $retainhdr = shift;
  my $ignorebad = shift;

  if ( !defined( $retainhdr ) ) {
    $retainhdr = 0;
  }

  if ( ! defined( $ignorebad ) ) {
    $ignorebad = 0;
  }

  my ( $telescope, $daterange, $instrument, $runnr, $filterinst );
  my @returnarray;

  $query->isfile(1);

  my $query_hash = $query->query_hash;

  $daterange = $query->daterange;
  $instrument = $query->instrument;
  $telescope = $query->telescope;

  if ( defined( $query_hash->{runnr} ) ) {
    $runnr = $query_hash->{runnr}->[0];
  } else {
    $runnr = 0;
  }

  my @instarray;

  if ( defined( $instrument ) && length($instrument ) != 0) {
    if ($instrument =~ /^rx/i) {
      $filterinst = $instrument;
      $instrument = "heterodyne";
    }
    push @instarray, $instrument;
  } elsif ( defined( $telescope ) && length( $telescope ) != 0 ) {
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
      push(@instarray, $inst);
    }
    push(@instarray, "heterodyne") if $ishet;


  } else {
    throw OMP::Error::BadArgs( "Unable to return data. No telescope or instrument set." );
  }

  my $obsgroup;
  my @files;
  my @obs;

  # If we have a simple query, go to the cache for stored information and files
  if ( simple_query( $query ) ) {
    ( $obsgroup, @files ) = unstored_files( $query );
    if ( defined( $obsgroup ) ) {
      @obs = $obsgroup->obs;
    }
  } else {
    # Okay, we don't have a simple query, so get the file list the hard way.

    # We need to loop over every UT day in the date range. Get the
    # start day and the end day from the $daterange object.
    my $startday = $daterange->min->ymd;
    $startday =~ s/-//g;
    my $endday = $daterange->max->ymd;
    $endday =~ s/-//g;

    for ( my $day = $daterange->min;
          $day <= $query->daterange->max;
          $day = $day + ONE_DAY ) {

      foreach my $inst ( @instarray ) {

        ################################################################################
        # KLUDGE ALERT KLUDGE ALERT KLUDGE ALERT KLUDGE ALERT KLUDGE ALERT KLUDGE ALERT
        ################################################################################
        # We need to have all the different heterodyne instruments in the config system
        # so that inferTelescope() will work. Unfortunately, we just want 'heterodyne',
        # so we'll just go on to the next one if the instrument name starts with 'rx'.
        ################################################################################
        next if( $inst =~ /^rx/i );

        my @tfiles = OMP::FileUtils->files_on_disk( $inst, $day, $runnr );
        foreach my $arr_ref ( @tfiles ) {
          push @files, $arr_ref;
        }

      }                        # foreach my $inst ( @instarray )
    }                          # for( my $day... )
  }                            # if( simple_query( $query ) ) { } else

  OMP::General->log_message( "Found ".@files. " files", OMP__LOG_DEBUG);

  my @allheaders;
  foreach my $arr_ref ( @files ) {

    foreach my $file ( @$arr_ref ) {

      # Read the header, get the OBSERVATION_ID generic header.
      try {
        my $FITS_header;
        my $frameset;
        if ( $file =~ /\.sdf$/ ) {
          $FITS_header = new Astro::FITS::Header::NDF( File => $file );

          # Open the NDF environment.
          my $STATUS = &NDF::SAI__OK;
          err_begin( $STATUS );
          ndf_begin();

          # Retrieve the FrameSet. In cases where the file fails to
          # open but we read the header okay above, simply abort from
          # retrieving the frameset since we know that HDS containers
          # will not usually have a .WCS (especially inside a .HEADER)
          ndf_find( NDF::DAT__ROOT, $file, my $indf, $STATUS );
          if ($STATUS == &NDF::SAI__OK) {
            ndf_state( $indf, "WCS", my $isthere, $STATUS);
            $frameset = ndfGtwcs( $indf, $STATUS ) if $isthere;
            ndf_annul( $indf, $STATUS );
          } else {
            # annul status - we only care about status on reading the WCS
            # not if the file itself is not a real NDF
            err_annul( $STATUS );
          }
          ndf_end( $STATUS );

          # Handle errors.
          if ( $STATUS != &NDF::SAI__OK ) {
            my ( $oplen, @errs );
            do {
              err_load( my $param, my $parlen, my $opstr, $oplen, $STATUS );
              push @errs, $opstr;
            } until ( $oplen == 1 );
            err_annul( $STATUS );
            err_end( $STATUS );
            throw OMP::Error::FatalError( "Error retrieving WCS from NDF:\n" . join "\n", @errs );
          }
          err_end( $STATUS );

        } elsif ( $file =~ /\.(gsd|dat)$/ ) {
          $FITS_header = new Astro::FITS::Header::GSD( File => $file );
        } else {
          throw OMP::Error::FatalError( "Do not recognize file suffix for file $file. Cannot read header" );
        }

        # Push onto array so that we can filter by OBSID later
        push(@allheaders, {
                           header => $FITS_header,
                           filename => $file,
                           frameset => $frameset } );
        OMP::General->log_message("Processed file $file", OMP__LOG_DEBUG);
      }
        catch Error with {
          my $Error = shift;
          OMP::General->log_message( "OMP::Error in OMP::ArchiveDB:\nfile: $file\ntext: " . $Error->{'-text'} . "\nsource: " . $Error->{'-file'} . "\nline: " . $Error->{'-line'}, OMP__LOG_ERROR );

          if ( ! $ignorebad ) {
            throw OMP::Error::ObsRead( "Error reading FITS header from file $file: " . $Error->{'-text'} );
          }
        };
    }
  }

  # merge duplicate information into a hash indexed by obsid
  my %headers = $self->_merge_dupes( @allheaders );

  # and create obs objects
  my @observations = $self->_hdrs_to_obs( $retainhdr, %headers);

  # Now filter
  foreach my $obs ( @observations ) {

    # If the observation's time falls within the range, we'll create the object.
    my $match_date = 0;

    if ( ! defined( $obs->startobs ) ) {
      OMP::General->log_message( "OMP::Error in OMP::ArchiveDB::_query_files: Observation is missing startobs(). Possible error in FITS headers.", OMP__LOG_ERROR );
      $WARNED{$obs->filename}++;

      next;
    }

    if ( ! $daterange->contains($obs->startobs) ) {

      next;
    }

    # Filter by keywords given in the query string. Look at filters
    # other than DATE, RUNNR, and _ATTR.  Assume a match, and if we
    # find something that doesn't match, remove it (since we'll
    # probably always match on telescope at the very least).

    # We're only going to filter if:
    # - the thing in the query object is an OMP::Range or a scalar, and
    # - the thing in the Obs object is a scalar
    my $match_filter = 1;

    foreach my $filter (keys %$query_hash) {
      if ( uc($filter) eq 'RUNNR' or uc($filter) eq 'DATE' or uc($filter) eq '_ATTR') {

        next;
      }

      foreach my $filterarray ($query_hash->{$filter}) {
        if ( OMP::Info::Obs->can(lc($filter)) ) {
          my $value = $obs->$filter;
          my $matcher = uc($obs->$filter);
          if ( UNIVERSAL::isa($filterarray, "OMP::Range") ) {
            $match_filter = $filterarray->contains( $matcher );

          } elsif ( UNIVERSAL::isa($filterarray, "ARRAY") ) {
            foreach my $filter2 (@$filterarray) {

              ################################################################
              # KLUDGE ALERT KLUDGE ALERT KLUDGE ALERT KLUDGE ALERT          #
              # Match against BACKEND header if instrument filter is 'acsis' #
              ################################################################
              if ($filter eq 'instrument' and $filter2 =~ /^acsis$/i) {
                $matcher = uc($obs->backend);

              }
              if ($matcher !~ /$filter2/i) {
                $match_filter = 0;

              }
            }
          }
        }
      }
    }

    if ( $match_filter ) {

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
      print STDERR "Warning: $errortext\n";
      OMP::General->log_message( $errortext, OMP__LOG_WARNING );
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
  my $retainhdr = shift;

  if ( !defined( $retainhdr ) ) {
    $retainhdr = 0;
  }

  # The first thing we have to do is merge related rows based on obsid.
  # We assume that the query has given us a row per useful quantity each with an obsid somewhere
  # first need to create a new array that matches requirement of _merge_dupes
  # Header translation requires that we have upper case keys to match the FITS standard.
  # Since _merge_dupes uses header translation we need to upper case everything at the same time.
  my @rearranged;
  for my $row (@$rows) {
    # upper case
    my %newrow;
    for my $k (keys %$row) {
      $newrow{uc($k)} = $row->{$k};
    }
    push(@rearranged, { header => \%newrow } );
  }
  my %unique = $self->_merge_dupes( @rearranged );

  # now convert into Obs::Info objects
  return $self->_hdrs_to_obs( $retainhdr, %unique);
}

=item B<_merge_dupes>

Given an array of hashes containing header object, filename and frameset, merge into a hash indexed
by OBSID where headers have been merged and filenames have been combined into arrays.

  %merged = $arcdb->_merge_dupes( @unmerged );

In the returned merged version, header hash item will contain an Astro::FITS::Header object
if the supplied entry in @unmerged was a simple hash reference.

Input keys:

   header - reference to hash or an Astro::FITS::Header object
   filename - single filename (optional)
   frameset - optional Starlink::AST frameset

If the 'filename' is not supplied yet a header translation reports that FILENAME
is available, the value will be stored from the translation into the filename slot.

Output keys

   header - Astro::FITS::Header object
   filenames - reference to array of filenames
   frameset - optional Starlink::AST frameset (from first in list)

=cut

sub _merge_dupes {
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

=item B<_hdrs_to_obs>

Convert the result from _merge_dupes() method to an array of C<OMP::Info::Obs> objects.

  @obs = $arcdb->_hdrs_to_obs( $retainhdr, %merged );

=cut

sub _hdrs_to_obs {
  my $self = shift;
  my $retainhdr = shift;
  my %merged = @_;

  my @observations;
  foreach my $obsid ( keys %merged ) {

    # Create the Obs object.
    my $obs = new OMP::Info::Obs( fits => $merged{$obsid}{header},
                                  retainhdr => $retainhdr,
                                  wcs => $merged{$obsid}{frameset},
                                );

    if ( !defined( $obs ) ) {
      print "Error creating obs $obsid\n";next;
    }

    # store the filename information
    $obs->filename( \@{$merged{$obsid}{'filenames'}}, 1 );

    # Ask for the raw data directory
    my $rawdir = $obs->rawdatadir;

    push(@observations, $obs);
  }

  return @observations;
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
