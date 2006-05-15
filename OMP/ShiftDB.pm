package OMP::ShiftDB;

=head1 NAME

OMP::ShiftDB - Shift log database manipulation

=head1 SYNOPSIS

  use OMP::ShiftDB;
  $db = new OMP::ShiftDB( DB => new OMP::DBbackend );

  $db->enterShiftLog( $comment, $telescope );
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
use Astro::Telescope;

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

  $db->enterShiftLog( $comment, $telescope );

The $comment argument passed to the method is an C<Info::Comment> object,
and the $telescope argument can be either an C<Astro::Telescope> object
or a string.

=cut

sub enterShiftLog {
  my $self = shift;
  my $comment = shift;
  my $telescope = shift;

  # Ensure that a valid user is supplied with the comment.
  my $author = $comment->author;
  my $udb = new OMP::UserDB( DB => $self->db );
  if( !defined( $author ) ) {
    throw OMP::Error::BadArgs( "Must supply author with comment" );
  }
  if( !$udb->verifyUser( $author->userid ) ) {
    throw OMP::Error::BadArgs( "Userid supplied with comment not found in database" );
  }

  # Ensure that a date is supplied with the comment.
  my $date = $comment->date;
  if( !defined( $date ) ) {
    throw OMP::Error::BadArgs( "Date not supplied with comment" );
  }

#  $date -= $date->sec;

  # Ensure that a telescope is supplied.
  if( ( !defined( $telescope ) ) ||
      ( length( $telescope . '' ) == 0 ) ) {
    throw OMP::Error::BadArgs( "Telescope not supplied" );
  }

  # Retrieve any comment that has the same combination of
  # author, date and telescope as the current one.

  # Form a query
  my $xml = "<ShiftQuery><author>" . $author->userid . "</author><date>" .
            $date->strftime("%Y-%m-%dT%H:%M:%S") . "</date><telescope>";
  if(UNIVERSAL::isa($telescope, "Astro::Telescope")) {
   $xml .= uc($telescope->name);
  } else {
   $xml .= uc($telescope);
  }
  $xml .= "</telescope></ShiftQuery>";
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
    $self->_insert_shiftlog( $comment, uc($telescope) );
  }

  # End transaction
  $self->_dbunlock;
  $self->_db_commit_trans;

  # Add the writing of the comment to the logs
  my $logmessage = sprintf("ShiftDB: %s %.50s", $author->userid, $comment->text);
  OMP::General->log_message( $logmessage );

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

  if(! defined( $query_hash->{date} ) &&
     ! defined( $query_hash->{author} ) &&
     ! defined( $query_hash->{telescope} ) ) {
    OMP::Error::FatalError("Must supply one of userid, date, or telescope.");
  }

  my @results = $self->_fetch_shiftlog_info( $query );

  my @shiftlogs = $self->_reorganize_shiftlog( \@results );

  return ( wantarray ? @shiftlogs : \@shiftlogs );

}

=back

=head2 Private Methods

=over 4

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

  # Connect to the user database
  my $udb = new OMP::UserDB( DB => $self->db );

# For each row returned by the query, create an Info::Comment object
# out of the information contained within.
  for my $row (@$rows) {

    # Get the User information as an OMP::User object from the author id
    my $user = $udb->getUser( $row->{author} );

    my $obs = new OMP::Info::Comment(
                     text => $row->{text},
                     date => OMP::General->parse_date( $row->{longdate} ),
                     author => $user
      );

    push @return, $obs;
  }

  # Sort them by date.
  my @returnarray = sort {$a->date->epoch <=> $b->date->epoch} @return;

  return @returnarray;

}

=item B<_insert_shiftlog>

Store the given C<Info::Comment> object in the shift log
database.

  $db->_insert_shiftlog( $comment, $telescope );

The second parameter can be either a C<Astro::Telescope> object or a string.

=cut

sub _insert_shiftlog {
  my $self = shift;
  my $comment = shift;
  my $telescope = shift;

  if( !defined($comment->date) ||
      !defined($comment->author) ) {
    throw OMP::Error::BadArgs("Must supply date and author properties to store a comment in the shiftlog database.");
  }

  if( ! defined( $telescope ) ) {
    throw OMP::Error::BadArgs("Must supply a telescope to store a comment in the shiftlog database.");
  }

  my $author = $comment->author;

  my $telstring;
  if(UNIVERSAL::isa($telescope, "Astro::Telescope")) {
    $telstring = uc($telescope->name);
  } else {
    $telstring = uc($telescope);
  }

  my $t = $comment->date; # - $comment->date->sec;
  my $date = $t->strftime("%b %e %Y %T");

  my %text = ( "TEXT" => OMP::General->preify_text( $comment->text ),
               "COLUMN" => "text" );

  $self->_db_insert_data( $SHIFTLOGTABLE,
			  { COLUMN => 'author',
			    QUOTE => 1,
			    POSN => 1
			  },
                          $date,
                          $author->userid,
                          $telstring,
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
  $new{'text'} = OMP::General->prepare_for_insert( $comment->text );

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
