package OMP::ShiftDB;

=head1 NAME

OMP::ShiftDB - Shift log database manipulation

=head1 SYNOPSIS

  use OMP::ShiftDB;
  $db = new OMP::ShiftDB( DB => new OMP::DBbackend );

  $db->enterShiftLog( $comment );
  $comment = $db->getShiftLogs( $query );

=head1 DESCRIPTION

The C<ShiftDB> class is used to manipulate the shift log database.

=cut

use 5.006;
use warnings;
use strict;
use OMP::Info::Comment;
use OMP::Error;
use OMP::UserDB;
use OMP::ShiftQuery;
use OMP::General;

use Data::Dumper;

use base qw/ OMP::BaseDB /;

our $VERSION = (qw$Revision$)[1];

our $SHIFTLOGTABLE = "ompshiftlog";

our $DEBUG = 1;

=head1 METHODS

=head2 Public Methods

=over 4

=item B<enterShiftLog>

Add a comment to the shift log database. A comment is uniquely
identified in the shift log database using a combination of
author and date of entry.

  $db->enterShiftLog( $comment );

The argument passed to the method is an C<Info::Comment> object.

=cut

sub enterShiftLog {
  my $self = shift;
  my $comment = shift;

  # Retrieve any comment that has the same combination of
  # author and date as the current one.

  # Form a query
  my $xml = "<ShiftQuery><author>" . $comment->{Author}->userid . "</author><date>" .
            $comment->{Date}->strftime("%Y-%m-%dT%H:%M:%S") . "</date></ShiftQuery>";
  my $query = new OMP::ShiftQuery( XML => $xml );

  my @result = $self->_fetch_shiftlog_info( $query );
  my $id = $result[0]->{shiftid};

  # Lock the database and wrap all this in a transaction
  $self->_db_begin_trans;
  $self->_dblock;

  if(defined($id)) {

    # We're updating.
    $self->_update_shiftlog( $id, $comment );

  } else {

    # We're inserting.
    $self->_insert_shiftlog( $comment );
  }

  # End transaction
  $self->_dbunlock;
  $self->_db_commit_trans;

}

=item B<getShiftLogs>

Retrieve shift logs given a set of criteria defined in a query.

  @results = $db->getShiftLogs( $query );

The argument is a C<ShiftQuery> object, and the method returns
an array of C<Info::Comment> objects, ordered by date.

=cut

sub getShiftLogs {
  my $self = shift;
  my $query = shift;

  my $query_hash = $query->query_hash;

  if(!defined($query_hash->{date}) && !defined($query_hash->{author})) {
    OMP::Error::FatalError("Must supply one of userid or date");
  }

  my @results = $self->_fetch_shiftlog_info( $query );

  my @shiftlogs = $self->_reorganize_shiftlog( \@results );

  return ( wantarray ? @shiftlogs : \@shiftlogs );

}

=item B<_fetch_shiftlog_info>

Retrieve the information from the shift log table using
the supplied query.

In scalar reference returns the first match via a reference to
a hash.

  $results = $db->_fetch_shiftlog_info( $query );

In list context returns all matches as a list of hash references.

  @results = $db->_fetch_shiftlog_info( $query );

=cut

sub _fetch_shiftlog_info {
  my $self = shift;
  my $query = shift;

  # Generate the SQL statement.
  my $sql = $query->sql( $SHIFTLOGTABLE );

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

=item B<_reorganize_shiftlog>

Given the results from the query (returned as a row per comment)
convert this output to an array of C<Info::Comment> objects.

  @results = $db->_reorganize_shiftlog( $query_output );

=cut

sub _reorganize_shiftlog {
  my $self = shift;
  my $rows = shift;

  my @return;

# For each row returned by the query, create an Info::Comment object
# out of the information contained within.
  for my $row (@$rows) {

    # Get the User information as an OMP::User object from the author id
    my $udb = new OMP::UserDB( DB => new OMP::DBbackend );
    my $user = $udb->getUser( $row->{author} );

    my $obs = new OMP::Info::Comment(
                     text => $row->{text},
                     date => OMP::General->parse_date( $row->{date} ),
                     author => $user
      );

    push @return, $obs;
  }

  # Sort them by date.
  my @returnarray = sort {$a->{Date}->epoch <=> $b->{Date}->epoch} @return;

  return @returnarray;

}

=item B<_insert_shiftlog>

Store the given C<Info::Comment> object in the shift log
database.

  $db->_insert_shiftlog( $comment );

=cut

sub _insert_shiftlog {
  my $self = shift;
  my $comment = shift;

  if( !defined($comment->{Date}) ||
      !defined($comment->{Author}) ) {
    throw OMP::Error::BadArgs("Must supply date and author properties to store a comment in the shiftlog database.");
  }

  my $t = $comment->{Date};
  my $date = $t->strftime("%b %e %Y %T");

  my %text = ( "TEXT" => $comment->{Text},
               "COLUMN" => "text" );

  $self->_db_insert_data( $SHIFTLOGTABLE,
                          $date,
                          $comment->{Author}->userid,
                          \%text
                        );
}

=item B<_update_shiftlog>

Update the object in the shift log whose ID is given with the
information given in the supplied C<Info::Comment> object.

  $db->_update_shiftlog( $id, $comment );

=cut

sub _update_shiftlog {
  my $self = shift;
  my $id = shift;
  my $comment = shift;

  if( !defined($id) ) {
    throw OMP::Error::BadArgs("Must supply a shiftlog ID to update");
  }

  my %new;
  $new{'text'} = $comment->{Text};

  $self->_db_update_data( $SHIFTLOGTABLE,
                          \%new,
                          "shiftid = $id"
                        );
}

=item B<_delete_shiftlog>

Delete the shiftlog whose ID is given.

  $db->_delete_shiftlog( $id );

=cut

sub _delete_shiftlog {
  my $self = shift;
  my $id = shift;

  if( !defined($id) ) {
    throw OMP::Error::BadArgs("Must supply a shiftlog ID to delete");
  }

  my $where = "shiftid = $id";
  $self->_db_delete_data( $SHIFTLOGTABLE, $where );
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
