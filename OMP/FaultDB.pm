package OMP::FaultDB;

=head1 NAME

OMP::FaultDB - Fault database manipulation

=head1 SYNOPSIS

  use OMP::FaultDB;
  $db = new OMP::FaultDB( DB => new OMP::DBbackend );

  $faultid = $db->fileFault( $fault );
  $db->respondFault( $faultid, $response );
  $db->closeFault( $fault );
  $fault = $db->getFault( $faultid );
  @faults = $db->queryFaults( $query );

=head1 DESCRIPTION

The C<FaultDB> class is used to manipulate the fault database. It is
designed to work with faults from multiple systems at once. The
database consists of two tables: one for general fault information
and one for the text associated with the fault report.

=cut

use 5.006;
use warnings;
use strict;
use OMP::Fault;
use OMP::Fault::Response;
use OMP::FaultQuery;

use base qw/ OMP::BaseDB /;

our $VERSION = (qw$Revision$)[1];

our $FAULTTABLE = "ompfault";
our $FAULTBODYTABLE = "ompfaultbody";


=head1 METHODS

=head2 Public Methods

=over 4


=item B<fileFault>

Create a new fault and return the new fault ID. The fault ID
is unique and can be used to address the fault in future.

  $id = $db->fileFault( $fault );

The details associated with the fault are supplied in the form
of a C<OMP::Fault> object.

=cut

sub fileFault {
  my $self = shift;
  my $fault = shift;

  # Need to lock the database since we are writing
  $self->_db_begin_trans;
  $self->_dblock;

  # Get the next fault id based on the file date
  my $id = $self->_get_next_faultid( $fault->date );

  # Store the id in the fault object
  $fault->id( $id );

  # Now write it to the database
  $self->_store_new_fault( $fault );

  # Mail out the fault

  # End transaction
  $self->_dbunlock;
  $self->_db_commit_trans;

  # Return the id
  return $id;
}

=item B<respondFault>

File a fault response for the specified fault ID.

  $db->respondFault( $faultid, $response );

The response must be a C<OMP::Fault::Response> object.

=cut

sub respondFault {
  my $self = shift;
  my $id = shift;
  my $response = shift;

  # Need to lock the database since we are writing
  $self->_db_begin_trans;
  $self->_dblock;

  # File the response
  $self->_add_new_response( $id, $response);

  # Mail out the response to the correct mailing list

  # End transaction
  $self->_dbunlock;
  $self->_db_commit_trans;

}

=item B<closeFault>

Close the supplied fault object in the database.

  $db->closeFault( $fault );
  $db->closeFault( $id );

The argument can be either an C<OMP::Fault> (so that the fault status
can be changed in the object) or a fault id.

If an object is supplied, raises an exception if no faultid is
present.

=cut

sub closeFault {
  my $self = shift;
  my $fault = shift;

  # Need to lock the database since we are writing
  $self->_db_begin_trans;
  $self->_dblock;

  # Determine the id
  my $id = $fault;
  my $isobj = 0;
  if (UNIVERSAL::isa( $fault, "OMP::Fault")) {
    $isobj = 1;
    $id = $fault->id;
  }

  # File the response
  $self->_close_fault( $id );

  # Send an EMAIL??

  # End transaction
  $self->_dbunlock;
  $self->_db_commit_trans;

  # Change the object status if we have an object
  $fault->close_fault
    if $isobj;

}

=item B<getFault>

Retrieve the specified fault from the database.

  $fault = $db->getFault( $id );

Returned as a C<OMP::Fault> object.

=cut

sub getFault {
  my $self = shift;
  my $id = shift;

  # No transaction required
  # Treat this as a DB query
  my $xml = "<FaultQuery><faultid>$id</faultid></FaultQuery>";
  my $query = new OMP::FaultQuery( XML => $xml );

  my @result = $self->queryFaults( $query );

  throw OMP::FatalError( "Multiple faults match the supplied id [$id] - this is not possible") unless @result == 1;

  # Guaranteed to be only one match
  return $result[0];
}

=item B<queryFaults>

Query the fault database and retrieve the matching fault objects.
Queries must be supplied as C<OMP::FaultQuery> objects.

  @faults = $db->queryFaults( $query );

=cut

sub queryFaults {
  my $self = shift;
  my $query = shift;

  return $self->_query_faultdb( $query );

}

=back

=head2 Internal Methods

=over 4

=item B<_get_next_faultid>

For the supplied date, determine the next fault id.

  $newid = $db->_get_next_faultid( $date );

Fault IDs take the form C<YYYYMMDD.NNN> where NNN increases
by one for each fault filed on day YYYYMMDD.

=cut

sub _get_next_faultid {
  my $self = shift;
  my $date = shift;

  # First get the date (only the day, month and year)
  my $yyyymmdd = $date->strftime("%Y%m%d");

  # Get the current highest value
  my $max = $self->_db_findmax( $FAULTTABLE, "faultid", "floor(faultid) = $yyyymmdd");

  # If we have zero back then this is the first fault of the day
  $max = $yyyymmdd unless $max;

  # Add 0.001 to the result
  $max += 0.001;

  # and format for rounding errors
  return sprintf( "%.3f", $max);
}

=item B<_store_new_fault>

Store the supplied fault in the database.

  $db->_store_new_fault( $fault );

Fault object must contain a pre-allocated fault ID.

Responses are written to a different table to the main fault
information. Note that if we are filing a new fault it is possible
for the fault to contain multiple responses (eg when importing a fault
from another system). This is supported.

=cut

sub _store_new_fault {
  my $self = shift;
  my $fault = shift;

  # Get the DB handle
  my $dbh = $self->_dbhandle or
    throw OMP::Error::DBError("Database handle not valid");

  # First store the main fault information

  # Date must be formatted for sybase
  my $faultdate = $fault->faultdate;
  $faultdate = $faultdate->strftime("%Y%m%d %T")
    if defined $faultdate;

  # Insert the data into the table
  $self->_db_insert_data( $FAULTTABLE,
			  $fault->id, $fault->category, $fault->subject,
			  $faultdate, $fault->type, $fault->system,
			  $fault->status, $fault->urgency,
			  $fault->timelost, $fault->entity);

  # Now loop over responses
  for my $resp ($fault->responses) {

    $self->_add_new_response( $fault->id, $resp);

  }

}

=item B<_add_new_response>

Add the supplied response to the specified fault.

  $db->_add_new_response( $id, $response );

Response must be an C<OMP::Fault::Response> object.

=cut

sub _add_new_response {
  my $self = shift;
  my $id = shift;
  my $resp = shift;

  my $author = $resp->author;
  my $date = $resp->date;
  my $text = $resp->text;

  # Format the date in a way that sybase understands
  $date = $date->strftime("%Y%m%d %T");

  $self->_db_insert_data( $FAULTBODYTABLE,
			  $id, $date, $author, $resp->isfault,
			  {
			   TEXT => $text,
			   COLUMN => 'text',
			  }
			);

}

=item B<_close_fault>

Close the fault with the specified fault ID.

  $db->_close_fault( $id )

=cut

sub _close_fault {
  my $self = shift;
  my $id = shift;
  my %status = OMP::Fault->faultStatus;
  my $close = $status{Closed}; # Dont like bare string

  # Get the database handle from the hash
  my $dbh = $self->_dbhandle or
    throw OMP::Error::DBError("Database handle not valid in _insert_row");

  # Update the status field
  $dbh->do("UPDATE $FAULTTABLE SET status = $close WHERE faultid = $id")
    or throw OMP::Error::DBError("Error closing fault $id: $DBI::errstr");
}

=item B<_query_faultdb>

Query the fault database and retrieve the matching fault objects.
Queries must be supplied as C<OMP::FaultQuery> objects.

  @faults = $db->_query_faultdb( $query );

=cut

sub _query_faultdb {
  my $self = shift;
  my $query = shift;

  my $sql = $query->sql( $FAULTTABLE, $FAULTBODYTABLE);

  # prepare and execute
  my $dbh = $self->_dbhandle;
  throw OMP::Error::DBError("Database handle not valid") unless defined $dbh;

  my $ref = $dbh->selectall_arrayref( $sql, { Columns=>{} } );
  throw OMP::Error::DBError("Error executing fault query:".$DBI::errstr)
    unless defined $ref;

  # Its possible to get an error after some data has been
  # retrieved...
  throw OMP::Error::DBError("Error retrieving fault data ".
				 $dbh->errstr)
    if $dbh->err;

  # Now loop through the faults, creating objects and
  # matching responses. 
  # Use a hash to indicate whether we have already seen a fault
  my %faults;
  for my $faultref (@$ref) {

    # First convert dates to date objects
    # 'Mar 15 2002  7:04AM' is Sybase format
    $faultref->{date} = OMP::General->parse_date( $faultref->{date} );
    $faultref->{faultdate} = OMP::General->parse_date( $faultref->{faultdate})
      if defined $faultref->{faultdate};

    my $id = $faultref->{faultid};

    # Create a new fault
    # One problem is that a new fault *requires* an initial "response"
    if (!exists $faults{$id}) {
      # Get the response
      my $resp = new OMP::Fault::Response( %$faultref );

      # And the fault
      $faults{$id} = new OMP::Fault( %$faultref, fault => $resp);

    } else {
      # Just need the response
      $faults{$id}->respond( new OMP::Fault::Response( %$faultref ) );

    }
  }

  # Now return the values in the hash
  return values %faults;
}

=back

=head1 SEE ALSO

This class inherits from C<OMP::BaseDB>.

For related classes see C<OMP::ProjDB> and C<OMP::FeedbackDB>.

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
