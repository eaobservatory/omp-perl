package OMP::ArchiveDB;

=head1 NAME

OMP::ArchiveDB - Query the data archive

=head1 SYNOPSIS

  use OMP::ArchiveDB;

  $db = new OMP::ArchiveDB(DB => new OMP::DBbackend::JCMTArchive);


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

use lib '/home/bradc/development/perlmods/';
use lib '/home/bradc/development/oracdr/lib/perl5/';

use OMP::ArcQuery;
use OMP::General;
use OMP::Info::Obs;
use Astro::FITS::Header::NDF;
use Astro::FITS::HdrTrans;
use Astro::WaveBand;
use Astro::Coords;
use Time::Piece;
use Time::Seconds;
use ORAC::Inst::Defn qw/ orac_configure_for_instrument /;
use ORAC::Frame;

use base qw/ OMP::BaseDB /;

use Data::Dumper;

our $VERSION = (qw$Revision$)[1];

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

  # First the database
  my @results = $self->_query_arcdb( $query );

  # If nothing so far, look on disk
  @results = $self->_query_files( $query )
    unless @results;

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

  # Get the SQL
  # It doesnt make sense to specify the table names from this
  # class since ArcQuery is the only class that cares and it
  # has to decide what to do on the basis of the telescope
  # part of the query. It may be possible to supply 
  # subclasses for JCMT and UKIRT and put the knowledge in there.
  # since we may have to have a subclass for getObs since we
  # need to know a telescope
  my $sql = $query->sql();

  # Fetch the data
  my $ref = $self->_db_retrieve_data_ashash( $sql );

  # Convert the data from a hash into an array of Info::Obs objects.
  my @return = $self->_reorganize_archive( \@ref );

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

  my ( $telescope, $daterange );
  my @returnarray;

  $query->isfile(1);

  my $query_hash = $query->query_hash;

  if( defined( $query_hash->{telescope}->[0] ) ) {
    if( $query_hash->{telescope}->[0] !~ /ukirt|jcmt/i ) {
      throw OMP::Error::FatalError("Telescope parameter must be either UKIRT or JCMT");
    } else {
      $telescope = $query_hash->{telescope}->[0];
      }
    } else {
    throw OMP::Error::FatalError("Telescope parameter not defined in query object");
  }

# If we have an array of dates (there should be only one), then we use that as the date.
# Otherwise, we should have an OMP::Range object.
  if( ref( $query_hash->{date} ) eq 'ARRAY' ) {
    if (scalar( @{$query_hash->{date}} ) == 1) {
      my $timepiece = new Time::Piece;
      $timepiece = $query_hash->{date}->[0];
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
  } elsif( $query_hash->{date}->isa('OMP::Range') ) {
    $daterange = $query_hash->{date};
print "Offset: " . $daterange->{Max}->tzoffset . "\n";
  }

  my ( $instrument, $runnr );

  if( defined( $query_hash->{instrument} ) ) {
    $instrument = $query_hash->{instrument};
  } else {
    $instrument = "";
  }
  if( defined( $query_hash->{runnr} ) ) {
    $runnr = $query_hash->{runnr}->[0];
  } else {
    $runnr = 0;
  }

  my @instarray;

  if(length($instrument . "") != 0) {
    push @instarray, $instrument;
  } else {
    if( uc( $telescope ) eq 'UKIRT' ) {
      push @instarray, 'cgs4', 'ufti', 'ircam', 'michelle', 'uist';
    } else {
      push @instarray, 'scuba';
    }
  }

# We need to loop over every UT day in the date range. Get the start day and the end
# day from the $daterange object.

  my $startday = $daterange->{Min}->ymd;
  $startday =~ s/-//g;
  my $endday = $daterange->{Max}->ymd;
  $endday =~ s/-//g;

  for(my $day = $startday; $day <= $endday; $day++) {

    foreach my $inst ( @instarray ) {
      my %options;
      $options{'ut'} = $day;
      orac_configure_for_instrument( uc( $inst ), \%options );
      my $directory = $ENV{"ORAC_DATA_IN"};

      # Get a file list.
      if( -d $directory ) {
        opendir( FILES, $directory);
        my @files = grep(!/^\./, readdir(FILES));
        closedir(FILES);

# INSTRUMENT SPECIFIC CODE
#
# The following line assumes that valid data files end in an observation number
# and have a ".sdf" suffix. If this is not the case, then this line will have
# to be modified accordingly.

        @files = grep(/_\d+\.sdf$/, @files);
        @files = sort {

# INSTRUMENT SPECIFIC CODE
#
# The following sorting routine assumes that valid data files end in an
# observation number and have a ".sdf" suffix. If this is not the case, then
# this will have to be modified accordingly. It is possible to use ORAC::Frame
# to do this, but dependencies on ORAC classes are to be minimised.

# The following is ORAC::Frame code which can do the same thing. Slower,
# and more dependant on ORAC classes, but not instrument/telescope specific.
#          my $a_Frm = new ORAC::Frame($directory . "/" . $a);
#          my $a_obsnum = $a_Frm->number;
#          my $b_Frm = new ORAC::Frame($directory . "/" . $b);
#          my $b_obsnum = $b_Frm->number;;

          $a =~ /_(\d+)\.sdf$/;
          my $a_obsnum = int($1);
          $b =~ /_(\d+)\.sdf$/;
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
          $runnr = '0' x (5 - length($runnr)) . $runnr;
          @files = grep(/$runnr\.sdf$/, @files);
        }

        foreach my $file ( @files ) {

          # Open up the header
          my $fullfile = $directory . "/" . $file;
          $fullfile =~ s/\.sdf$/\.header/;

          my $FITS_header = new Astro::FITS::Header::NDF( File => $fullfile );
          tie my %header, ref($FITS_header), $FITS_header;
          my %generic_header = Astro::FITS::HdrTrans::translate_from_FITS(\%header);

          # If the observation's time falls within the range, we'll create the object.
          my $match_date = 0;
          my $startobs = OMP::General->parse_date($generic_header{UTSTART});
          if( $daterange->contains($startobs) ) {
            $match_date = 1;
          } elsif( $daterange->{Max} < $startobs ) {
            last;
          }

          # Filter by keywords given in the query string. Look at filters other than DATE,
          # RUNNR, and _ATTR.
          my $match_filter = 0;
          foreach my $filter (keys %$query_hash) {
            if( uc($filter) eq 'RUNNR' or uc($filter) eq 'DATE' or uc($filter) eq '_ATTR') {
              next;
            }
            foreach my $filterarray ($query_hash->{$filter}) {
              my $matcher = uc($generic_header{uc($filter)});
              $match_filter = grep /$matcher/i, @$filterarray;
            }
          }

          if( $match_date && $match_filter ) {

            # get the header information, form an Info::Obs object, and push that onto the array

            # For Info::Obs objects, we need to get the projectid, instrument, exposure time,
            # the target name, the disperser, the type of observation
            # (imaging or spectroscopy), polarimetry, the waveband (as an Astro::WaveBand object),
            # the coordinates (as an Astro::Coords object), the FITS headers (as a hash), and an
            # array of Info::Comment comment objects.
            my %args;
            $args{projectid} = $generic_header{PROJECT};
            $args{checksum} = $generic_header{MSBID};
            $args{instrument} = $generic_header{INSTRUMENT};
            $args{duration} = $generic_header{EXPOSURE_TIME};
            $args{target} = $generic_header{OBJECT};
            $args{disperser} = $generic_header{GRATING_NAME};
            $args{type} = $generic_header{OBSERVATION_TYPE};
            $args{telescope} = $generic_header{TELESCOPE};

            # Build the Astro::WaveBand object

            if ( length( $generic_header{WAVELENGTH} . "" ) != 0 ) {
              $args{waveband} = new Astro::WaveBand( Wavelength => $generic_header{WAVELENGTH},
                                                     Instrument => $inst );
            } elsif ( length( $generic_header{FILTER} . "" ) != 0 ) {
              $args{waveband} = new Astro::WaveBand( Filter     => $generic_header{FILTER},
                                                     Instrument => $inst );
            }

            # Build the Time::Piece startobs and endobs objects
            if(length($generic_header{UTSTART} . "") != 0) {
              my $startobs = Time::Piece->strptime($generic_header{UTSTART}, '%Y-%m-%dT%T');
              $args{startobs} = $startobs;
            }
            if(length($generic_header{UTEND} . "") != 0) {
              my $endobs = Time::Piece->strptime($generic_header{UTEND}, '%Y-%m-%dT%T');
              $args{endobs} = $endobs;
            }

            # Build the Astro::Coords object

            # Default the equinox to J2000, but if it's 1950 change to B1950. Anything else will be
            # converted to J2000.
            my $type = "J2000";
            if ( $generic_header{EQUINOX} =~ /1950/ ) {
              $type = "B1950";
            }
            $args{coords} = new Astro::Coords( ra   => $generic_header{RA_BASE},
                                               dec  => $generic_header{DEC_BASE},
                                               type => $type );

            # Build the Astro::FITS::Header object

            $args{fits} = $FITS_header;

            # Build the array of Info::Comment objects

            # Create the Info::Obs object and push it onto the return array

            my $object = new OMP::Info::Obs( %args );
            push @returnarray, $object;
          }
        }
      }
    }

  }

  # We need to sort the return array by date.

  @returnarray = sort {$a->startobs->epoch <=> $b->startobs->epoch} @returnarray;

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
  for my $row (%$rows) {
    my $obs = new OMP::Info::Obs(
      instrument => $row->{instrument},
      startobs => OMP::General->parse_date( $row->{startobs} ),
      runnr => $row->{runnr},
      msbid => $row->{msbid},
      projectid => $row->{projectid},
      disperser => $row->{disperser},
      target => $row->{target},
      timeest => $row->{timeest},
      type => $row->{type},
      pol => $row->{pol},
      comments => [
                   new OMP::Info::Comment(
                     text => $row->{comment},
                     date => $row->{date},
                     status => $row->{status} )
                   ],
      );
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
