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

use OMP::ArcQuery;

use base qw/ OMP::BaseDB /;

our $VERSION = (qw$Revision$)[1];

=head1 METHODS

=over 4

=item B<getObs>

Get information about a specific observation. The observation
must be specified by date of observation (within
a minute) and observation number. A telescope must be provided.
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

  return @$ref;
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

  return ();
}


=back

=head1 SEE ALSO

This class inherits from C<OMP::BaseDB>.

For related classes see C<OMP::ProjDB> and C<OMP::FeedbackDB>,
C<OMP::ArcQuery>.

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
