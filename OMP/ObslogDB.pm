package OMP::ObslogDB;

=head1 NAME

OMP::ObslogDB - Manipulate observation log table.

=head1 SYNOPSIS

  use OMP::ObslogDB;

  $db = new OMP::ObslogDB( ProjectID => 'm01bu05',
                           DB => new OMP::DBbackend );

  $db->addObslog( $comment, $instrument, $date, $runnr );

  @output = $db->queryObslog( $query );

=head1 DESCRIPTION

The observation log table exists to allow us to associate user-supplied
comments with observations. It does this by having a simple logging table
where a new row is added each time an observation is commented upon.

=cut

use 5.006;
use warnings;
use strict;

use Carp;
use OMP::Error qw/ :try /;
use OMP::Constants qw/ :obs /;
use OMP::Info::Obs;
use OMP::Info::Comment;
use OMP::ObsQuery;
use Time::Piece;
use Time::Seconds;

use base qw/ OMP::BaseDB /;

our $VERSION = (qw$Revision$)[1];
our $OBSLOGTABLE = "ompobslog";

=head1 METHODS

=head2 Public Methods

=over 4

=item B<addObslog>

Add an observation to the database.

  $db->addObslog( $comment, $instrument, $utdate, $runnr, $status );

The comment is supplied as an C<OMP::Info::Comment> object (and will
therefore include a status and a date).

If the observation has not yet been observed this command will succeed,
adding the comment to the table.

Optionally, an object of class C<OMP::Info::Obs> can be supplied instead
of the telescope, instrument, UT date, and run number.

  $db->addObslog( $comment, $obs );

If the observation already has a comment associated with it, that old
comment will be deleted and replaced with the new comment.

It is possible to supply the comment as a string (anything that is not
a reference will be treated as a string). The default status of such an
comment will be set as OMP__COMMENT_GOOD.

  $db->addObslog( $comment_string, $instrument, $utdate, $runnr );

It is also possible to supply the comment as an integer, which will
be assumed to be an index into the comments contained in the
C<OMP::Info::Obs> object.

If no comment is supplied at all, the last comment will be extracted
from the C<OMP::Info::Comment> object (if supplied) and stored.

If the observation does not specifiy a status, default behaviour is to treat
the observation status as OMP__OBS_GOOD. See C<OMP::Constants> for more
information on the different observation statuses.

=cut

sub addObslog {
  my $self = shift;

  # Simple arguments
  my $comment = shift;
  my $instrument = shift;
  my $utdate = shift;
  my $runnr = shift;

  my $obsinfo;

  if( UNIVERSAL::isa( $instrument, "OMP::Info::Obs" ) ) {
    $obsinfo = $instrument; # So we don't get confused later on
    my $projectid = $self->projectid;
    my $obsproj = $obsinfo->projectid;
    if( defined $projectid and !defined $obsproj ) {
      $obsproj->projectid( $projectid );
    } elsif( !defined $projectid and !defined $objproj ) {
      throw OMP::Error::FatalError( "Unable to determine projectid" );
    } elseif( defined $obsproj and !defined $projectid ) {
      $self->projectid( $obsproj );
    }
  } else {
    my $projectid = $self->projectid;
    if( !defined $projectid ) {
      throw OMP::Error::FatalError( "Project ID not available." );
    }
    $obsinfo = new OMP::Info::Obs( projectid => $projectid,
                                   instrument => $instrument,
                                   runnr => $runnr,
                                   utdate => $utdate
                                 );
  }

  # Do we have a comment or an index (or no comment at all)?

  if( $comment ) {
    # See if we are a blessed reference
    if( ref( $comment ) ) {
      # Fall over if we aren't a comment object.
      throw OMP::Error::BadArgs( "Wrong class for comment object: " . ref( $comment ) )
           unless UNIVERSAL::isa( $comment, "OMP::Info::Comment" );
    } elsif( $comment =~ /^\d+$/ ) {
      # An integer index.
      $comment = ( $obsinfo->comments )[$comment];
    } else {
      # Some other random text. Don't bother to add a status yet.
      $comment = new OMP::Info::Comment( text => $comment );
    }
  } else {
    # Assume last index
    $comment = ( $obsinfo->comments )[-1];
  }

  # Make sure we have a defined comment.
  throw OMP::Error::BadArgs("Unable to determine comment object")
    unless defined $comment;

  # Make sure we can uniquely identify the observation. This is done by
  # looking for an instrument, a run number, and a UT date in the Obs
  # object.
  throw OMP::Error::BadArgs("Unable to uniquely identify observation")
    unless ( defined $obsinfo->instrument and
             defined $obsinfo->runnr and
             defined $obsinfo->startobs );

  # Lock the database (since we are writing).
  $self->_db_begin_trans;
  $self->_dblock;

  # Delete old observations.
  $self->_delete_obslog($obsinfo);

  # Add the new comment to the current observation.
  $obsinfo->{comments}->[0] = $comment;

  # Write the observation to database.
  $self->_store_obslog($obsinfo);

  # End transaction.
  $self->_dbunlock;
  $self->_db_commit_trans;

}

=item B<retrieveObslog>

Retrieve comments for a given observation. Observation must be
supplied as an C<OMP::Info::Obs> object.

  @results = $db->retrieveObslog( $obs );
  $results = $db->retrieveObslog( $obs );

The method returns either an array of C<Info::Comment> objects or
reference to an array of C<Info::Comment> objects.

=cut

sub retrieveObslog {

  my $self = shift;
  my $obs = shift;

  # First check to see if the observation object actually has
  # comments associated with it. If it does, then we don't have
  # to make a costly database call.
  if(defined($obs->comments)) {
    return $obs->comments;
  }

  # Form a query to retrieve the observation comments.
  my $xml = "<ObsQuery>" .
    ( $obs->instrument ? "<instrument>" . $obs->instrument . "</instrument>" : "" ) .
    ( $obs->runnr ? "<runnr>" . $obs->runnr . "</runnr>" : "" ) .
    ( $obs->startobs ? "<startobs>" . $obs->startobs->ymd . "T" . $obs->startobs->hms . "</startobs>" : "" ) .
    "</ObsQuery>";

  my $query = new OMP::ObsQuery( XML => $xml );
  my @results = $self->queryObslog( $query );

  return (wantarray ? @results : \@results);
}

=item B<queryObslog>

Query the observation comment table. Query must be supplied as
an C<OMP::ObsQuery> object.

  @results = $db->queryObslog( $query );

Returns an array of C<Info::Obs> objects in list context, or
a reference to an array of C<Info::Obs> objects in scalar context.

=cut

sub queryObslog {

  my $self = shift;
  my $query = shift;

# Do some rudimentary checks on the query to make sure we're not
# trying to get every comment from the beginning of time
  if(defined($query->date)) {
    if(UNIVERSAL::isa($query->date) eq 'OMP::Range') {
      if($query->date->isinverted or !$query->date->isbound) {
        throw OMP::Error::BadArgs("Date range muse be closed and consecutive");
      } elsif( ( $query->date->{Max} - $query->date->{Min} ) > ONE_YEAR ) {
        throw OMP::Error::BadArgs("Date range must be less than one year");
      }
    }
  } else {
    throw OMP::Error::BadArgs("Must supply either a date or a date range");
  }

# Send the query off to yet another method.
  my @results = $self->_fetch_obslog_info( $query );

# Create an array of Info::Obs objects from the returned
# hash.
  my @obs = $self->_reorganize_obslog( \@results );

# And return either the array or a reference to the array.
  return ( wantarray ? @obs : \@obs );

}

=back

=head2 Internal Methods

=over 4

=item B<_fetch_obslog_info>

Retrieve the information from the observation log table using
the supplied query.

In scalar context returns the first match via a reference to
a hash.

  $results = $db->_fetch_obslog_info( $query );

In list context returns all matches as a list of hash references.

  @results = $db->_fetch_obslog_info( $query );

=cut

sub _fetch_obslog_info {
  my $self = shift;
  my $query = shift;

  # Generate the SQL statement.
  my $sql = $self->sql( $OBSLOGTABLE );

  # Run the query.
  my $ref = $self->_retrieve_data_ashash( $sql );

  # If they want all the info just return the ref.
  # Otherwise, return the first entry.
  if ( wantarray ) {
    return @$ref;
  } else {
    my $hashref = ( defined $ref->[0] ? $ref->[0] : {} );
    return $hashref;
  }
}

=item B<_reorganize_obslog>

Given the results from the query (returned as a row per observation)
convert this output to an array of C<Info::Obs> objects.

  @results = $db->_reorganize_obslog( $query_output );

=cut

sub _reorganize_obslog {
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

=item B<_store_obslog>

Store the given C<Info::Obs> object in the observation log
database..

  $db->_store_obslog( $obs );

=cut

sub _store_obslog {
  my $self = shift;
  my $obs = shift;

  if( !defined($obs->instrument) ||
      !defined($obs->startobs) ||
      !defined($obs->runnr) ) {
    throw OMP::Error::BadArgs("Must supply instrument, startobs, and runnr properties to store an observation in the database");
  }

  # Check the comment status. Default it to OMP__OBS_GOOD.
  my $status;
  if(defined($obs->comments->[0]->status)) {
    $status = $obs->comments->[0]->status;
  } else {
    $status = OMP__OBS_GOOD;
  }

  my $t = $obs->startobs;
  my $date = $t->strftime("%b %e %Y %T");

  my $ct = $obs->comments->[0]->date;
  my $cdate = $ct->strftime("%b %e %Y %T");

  $self->_db_insert_data( $OBSLOGTABLE,
                          $obs->instrument,
                          $date,
                          $obs->runnr,
                          $obs->comments->[0]->text,
                          $obs->comments->[0]->status,
                          $obs->comments->[0]->user,
                          $cdate
                        );

}

=item B<_delete_obslog>

Delete the observation matching that passed as a parameter
from the database.

  $db->_delete_obslog( $obs );

The given observation must have instrument, date, and run number
defined in order to uniquely identify an observation in the
database.

=cut

sub _delete_obslog {
  my $self = shift;
  my $obs = shift;

  throw OMP::Error::BadArgs("Must supply an observation object")
    unless $obs;

  throw OMP::Error::BadArgs("Must supply instrument, date, and run number")
    unless (
            defined $obs->instrument &&
            defined $obs->startobs &&
            defined $obs->runnr
           );

  my $instrument = $obs->instrument;
  my $startobs = $obs->startobs;
  my $runnr = $obs->runnr;

  # Translate the date into a Sybase-compliant date.
  my $date = $startobs->strftime("%Y%m%d %T");

  # Form the WHERE clause.
  my $where = "date = $date AND instrument = $instrument AND runnr = $runnr";

  # And delete the data from the database.
  $self->_db_delete_data( $OBSLOGTABLE, $where );
}

=back

=head1 SEE ALSO

This class inherits from C<OMP::BaseDB>.

For related classes see C<OMP::ProjDB> and C<OMP::FeedbackDB>.

=head1 AUTHORS

Brad Cavanagh E<lt>b.cavanagh@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
