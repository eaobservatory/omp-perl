package OMP::ObslogDB;

=head1 NAME

OMP::ObslogDB - Manipulate observation log table.

=head1 SYNOPSIS

  use OMP::ObslogDB;

  $db = new OMP::ObslogDB( ProjectID => 'm01bu05',
                           DB => new OMP::DBbackend );

  $db->addComment( $comment, $instrument, $date, $runnr );

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
use OMP::UserDB;
use Data::Dumper;
use base qw/ OMP::BaseDB /;

our $VERSION = (qw$Revision$)[1];
our $OBSLOGTABLE = "ompobslog";

=head1 METHODS

=head2 Public Methods

=over 4

=item B<addComment>

Add a comment to the database.

  $db->addComment( $comment, $obs, $user );

The supplied parameters are an C<Info::Comment> object or a string as
the comment text, and an C<Info::Obs> object for which the comment was
made. The third paramter is optional, and can either be a string
containing a user ID or an C<OMP::User> object.

If the observation already has comments associated with it, those comments
will be flagged as inactive, and the new comment will be inserted into
the database and flagged as active.

It is possible to supply the comment as a string (anything that is not
a reference will be treated as a string). The default status of such an
comment will be set as OMP__COMMENT_GOOD. See C<OMP::Constants> for
more information on comment status values.

It is also possible to supply the comment as an integer, which will
be assumed to be an index into the comments contained in the
C<OMP::Info::Obs> object.

If no comment is supplied at all, the last comment will be extracted
from the C<OMP::Info::Comment> object (if supplied) and stored.

This method will not update the comments within any passed C<OMP::Info::Obs>
object.

=cut

sub addComment {
  my $self = shift;

  # Simple arguments
  my $comment = shift;
  my $obs = shift;
  my $user = shift;

  # See if we are a blessed reference
  if( ref( $comment ) ) {
    # Fall over if we aren't a comment object.
    throw OMP::Error::BadArgs( "Wrong class for comment object: " . ref( $comment ) )
    unless UNIVERSAL::isa( $comment, "OMP::Info::Comment" );
  } elsif( $comment =~ /^\d+$/ ) {
    # An integer index.
    $comment = ( $obs->comments )[$comment];
  } else {
    # Some other random text. Don't bother to add a status yet.
    $comment = new OMP::Info::Comment( text => $comment );
  }

  # Make sure we have a defined comment.
  throw OMP::Error::BadArgs("Unable to determine comment object")
    unless defined $comment;

  # Make sure we can uniquely identify the observation. This is done by
  # looking for an instrument, a run number, and a UT date in the Obs
  # object.
  throw OMP::Error::BadArgs("Unable to uniquely identify observation")
    unless ( defined $obs->instrument and
             defined $obs->runnr and
             defined $obs->startobs );

  # Grab or verify the user id if it's given.
  my $userobj;
  if( $user ) {
    if(UNIVERSAL::isa( $user, 'OMP::User' ) ) {
      my $udb = new OMP::UserDB( DB => $self->db );
      if(!$udb->verifyUser($user->userid)) {
        throw OMP::Error::BadArgs("Must supply a valid user");
      };
      $userobj = $user;
    } else {
      my $udb = new OMP::UserDB( DB => $self->db );
      $userobj = $udb->getUser( $user );
      if(!defined($userobj)) {
        throw OMP::Error::BadArgs("User id $user is not in database");
      }
    }
    $comment->author($userobj);
  } elsif (UNIVERSAL::isa( $comment, 'OMP::Info::Comment' ) ) {
    my $udb = new OMP::UserDB( DB => $self->db );
    if(!$udb->verifyUser($comment->author->userid)) {
      throw OMP::Error::BadArgs("Must supply a valid user with the comment");
    }
  }

  # Lock the database (since we are writing).
  $self->_db_begin_trans;
  $self->_dblock;

  # Set old observations in the archive to "inactive".
  $self->_set_inactive( $obs, $comment->author->userid );

  # Add the new comment to the current observation.
#  $obs->comments->[scalar($obs->comments)] = $comment;

  # Write the observation to database.
  $self->_store_comment( $obs, $comment );

  # End transaction.
  $self->_dbunlock;
  $self->_db_commit_trans;
}

=item B<getComment>

Retrieve the most recent open comments for a given observation.
Observation must be supplied as an C<OMP::Info::Obs> object.

  @comment = $db->getComment( $obs );

In this case the method returns an array of C<Info::Comment> objects.

  $comment = $db->getComment( $obs );

In this case the method returns a reference to an array of
C<Info::Comment> objects.

An additional optional argument may be supplied to indicate that
all comments for the observation are to be returned.

  @allcomments = $db->getComment( $obs, $allcomments );
  $allcomments = $db->getComment( $obs, $allcomments );

If the value for this argument is 1, then all comments for the
given observation will be returned. In this case an array of
C<Info::Comment> objects will be returned in list context, or
a reference to an array of C<Info::Comment> objects in scalar
context.

Note that the passed C<Info::Obs> object remains unchanged.

=cut

sub getComment {

  my $self = shift;
  my $obs = shift;
  my $allcomments = shift;

  if( !defined($obs->instrument) ||
      !defined($obs->runnr) ||
      !defined($obs->startobs) ) {
    throw OMP::Error::BadArgs("Must supply an Info::Obs object with defined instrument, run number, and date");
  }

  my $startobs = $obs->startobs;

  # If $allcomments is true, then we don't want to limit
  # the query. Otherwise, we want to retrive comments
  # only for which obsactive = 1.
  my $obsactivestring;
  if(defined($allcomments)) {
    $obsactivestring = "";
  } else {
    $obsactivestring = "<obsactive>1</obsactive>";
  }

  # Form a query to retrieve the observation comments.
  my $xml = "<ObsQuery>" .
    "<instrument>" . $obs->instrument . "</instrument>" .
    "<runnr>" . $obs->runnr . "</runnr>" .
    "<date>" . $startobs->ymd . "T" . $startobs->hms . "</date>" .
    $obsactivestring .
    "</ObsQuery>";

  my $query = new OMP::ObsQuery( XML => $xml );
  my @results = $self->queryComments( $query );

  # Return based on context and arguments.
#  if( $allcomments ) {
    return (wantarray ? @results : \@results);
#  } else {
#    return $results[0];
#  }
}

=item B<removeComment>

Remove from the database the comment for the given user id and
C<OMP::Info::Obs> object.

  $db->removeComment( $obs, $userid );

This method does not permanently remove a comment, it flags all
comments for the given user id and C<OMP::Info::Obs> object as
being inactive. It does not update the given C<OMP::Info::Obs>
object.

=cut

sub removeComment {
  my $self = shift;
  my $obs = shift;
  my $userid = shift;

  if(!defined($obs) || !defined($userid)) {
    throw OMP::Error::BadArgs( "Must supply both OMP::Info::Obs object and user ID to ObslogDB->removeComment" );
  }

  $self->_set_inactive( $obs, $userid );

}

=item B<queryComments>

Query the observation comment table. Query must be supplied as
an C<OMP::ObsQuery> object.

  @results = $db->queryComments( $query );

Returns an array of C<Info::Comment> objects in list context, or
a reference to an array of C<Info::Comment> objects in scalar context.

=cut

sub queryComments {

  my $self = shift;
  my $query = shift;

  my $query_hash = $query->query_hash;

# Do some rudimentary checks on the query to make sure we're not
# trying to get every comment from the beginning of time
  if(defined($query_hash->{date})) {
    my $date;
    if(ref($query_hash->{date}) eq 'ARRAY') {
      $date = $query_hash->{date}->[0];
    } else {
      $date = $query_hash->{date};
    }
    if(UNIVERSAL::isa($date, 'OMP::Range')) {
      if($date->isinverted or !$date->isbound) {
        throw OMP::Error::BadArgs("Date range muse be closed and consecutive");
      } elsif( ( $date->{Max} - $date->{Min} ) > ONE_YEAR ) {
        throw OMP::Error::BadArgs("Date range must be less than one year");
      }
    }
  } else {
    throw OMP::Error::BadArgs("Must supply either a date or a date range");
  }

# Send the query off to yet another method.
  my @results = $self->_fetch_comment_info( $query );

# Create an array of Info::Comment objects from the returned
# hash.
  my @comments = $self->_reorganize_comments( \@results );

# And return either the array or a reference to the array.
  return ( wantarray ? @comments : \@comments );

}

=item B<updateObsComment>

Update an C<OMP::Info::Obs> object by adding its associated comment.

  $db->updateObsComment( \@obs_array );

This method takes one argument, a reference to an array of C<OMP::Info::Obs>
objects. This method will update each C<OMP::Info::Obs> object by
adding its associated comment, if one exists.

This method returns nothing.

=cut

sub updateObsComment {

  my $self = shift;

  my $obs_arrayref = shift;

  foreach my $obs ( @$obs_arrayref ) {
    my @comments = $self->getComment( $obs );
    $obs->comments(@comments);
  }

}

=back

=head2 Internal Methods

=over 4

=item B<_fetch_comment_info>

Retrieve the information from the observation log table using
the supplied query.

In scalar context returns the first match via a reference to
a hash.

  $results = $db->_fetch_obslog_info( $query );

In list context returns all matches as a list of hash references.

  @results = $db->_fetch_obslog_info( $query );

=cut

sub _fetch_comment_info {
  my $self = shift;
  my $query = shift;

  # Generate the SQL statement.
  my $sql = $query->sql( $OBSLOGTABLE );
#print $sql;
  # Run the query.
  my $ref = $self->_db_retrieve_data_ashash( $sql );

  # If they want all the info just return the ref.
  # Otherwise, return the first entry.
  if ( wantarray ) {
    return @$ref;
  } else {
    my $hashref = ( defined $ref->[0] ? $ref->[0] : {} );
    return $hashref;
  }
}

=item B<_reorganize_comments>

Given the results from the query (returned as a row per observation)
convert this output to an array of C<Info::Comment> objects.

  @results = $db->_reorganize_comments( $query_output );

=cut

sub _reorganize_comments {
  my $self = shift;
  my $rows = shift;

  my @return;

  # Connect to the user database
  my $db = new OMP::UserDB( DB => $self->db );

# For each row returned by the query, create an Info::Comment object
# out of the information contained within.
  for my $row (@$rows) {
    my $comment = new OMP::Info::Comment(
                text => $row->{commenttext},
                date => OMP::General->parse_date( $row->{commentdate} ),
                status => $row->{commentstatus},
              );
    # Retrieve the user information so we can create the author
    # property.
    my $author = $db->getUser( $row->{commentauthor} );
    $comment->author($author);
    push @return, $comment;
  }

  return @return;

}

=item B<_store_comment>

Store the given C<Info::Comment> object corresponding to the
given C<Info::Obs> object in the observation log database.

  $db->_store_comment( $obs, $comment );

This method will store the comment as being active, i.e. the
"obsactive" flag in the table will be set to 1.

=cut

sub _store_comment {
  my $self = shift;
  my $obs = shift;
  my $comment = shift;

  if( !defined($obs->instrument) ||
      !defined($obs->startobs) ||
      !defined($obs->runnr) ) {
    throw OMP::Error::BadArgs("Must supply instrument, startobs, and runnr properties to store a comment in the database");
  }

  if( !defined($comment) ) {
    throw OMP::Error::BadArgs("Must supply comment to store a comment in the database");
  }

  # Check the comment status. Default it to OMP__OBS_GOOD.
  my $status;
  if(defined($comment->status)) {
    $status = $comment->status;
  } else {
    $status = OMP__OBS_GOOD;
  }

  my $t = $obs->startobs;
  my $date = $t->strftime("%b %e %Y %T");

  my $ct = $comment->date;
  my $cdate = $ct->strftime("%b %e %Y %T");

  my %text = ( "TEXT" => $comment->text,
               "COLUMN" => "commenttext" );

  $self->_db_insert_data( $OBSLOGTABLE,
                          $obs->runnr,
                          $obs->instrument,
                          $obs->telescope,
                          $date,
                          "1",
                          $cdate,
                          $comment->author->userid,
                          \%text,
                          $status
                        );

}

=item B<_set_inactive>

Set all observations to inactive, using the given observation as a template.

  $db->_set_inactive( $obs, $userid );

Passed argument is an C<Info::Obs> object. This method will set all
archived observations in the database with the same run number, instrument,
time of observation, and user ID as the given observation as being inactive.
It will do this by toggling the "obsactive" flag in the database from 1
to 0.

=cut

sub _set_inactive {
  my $self = shift;
  my $obs = shift;
  my $userid = shift;

  # Rudimentary input checking.
  throw OMP::Error::BadArgs("Must supply an Info::Obs object")
    unless ( defined $obs );
  throw OMP::Error::BadArgs("Must supply an Info::Obs object")
    unless UNIVERSAL::isa($obs, 'OMP::Info::Obs');
  throw OMP::Error::BadArgs("Must supply instrument, date, and run number")
    unless (
            defined $obs->instrument &&
            defined $obs->startobs &&
            defined $obs->runnr
           );
  throw OMP::Error::BadArgs("Must supply a user id")
    unless defined $userid;

  my $instrument = $obs->instrument;
  my $runnr = $obs->runnr;
  my $startobs = $obs->startobs;

  my $date = $startobs->strftime("%Y%m%d %T");

  # Form the WHERE clause.
  my $where = "date = '$date' AND instrument = '$instrument' AND runnr = $runnr AND commentauthor = '$userid'";

  # Set up the %new hash (hash of things to be updated)
  my %new = ( obsactive => 0 );

  # And do the update.
  $self->_db_update_data( $OBSLOGTABLE, \%new, $where );

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
