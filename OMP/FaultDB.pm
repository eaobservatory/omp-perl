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
use OMP::Error;
use OMP::UserDB;

use base qw/ OMP::BaseDB /;

our $VERSION = (qw$Revision$)[1];

our $FAULTTABLE = "ompfault";
our $FAULTBODYTABLE = "ompfaultbody";
our $ASSOCTABLE = "ompfaultassoc";

our $DEBUG = 1;

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

  # End transaction
  $self->_dbunlock;
  $self->_db_commit_trans;

  # Mail out the fault
  # We do this outside of our transaction since the SMTP server
  # has been known to fail and we don't want the fault lost
  $self->_mail_fault($fault);

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

  # End transaction
  $self->_dbunlock;
  $self->_db_commit_trans;

  # Mail out the response to the correct mailing list
  # We do this outside of our transaction since the SMTP server
  # has been known to fail and we don't want the fault lost
  my $fault = $self->getFault($id);
  $self->_mail_fault($fault);
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

Returned as a C<OMP::Fault> object. Returns undef if the fault can not
be found in the database.

=cut

sub getFault {
  my $self = shift;
  my $id = shift;

  # No transaction required
  # Treat this as a DB query
  my $xml = "<FaultQuery><faultid>$id</faultid></FaultQuery>";
  my $query = new OMP::FaultQuery( XML => $xml );

  my @result = $self->queryFaults( $query );

  if (scalar(@result) > 1) {
    throw OMP::Error::FatalError( "Multiple faults match the supplied id [$id] - this is not possible [bizarre]");
  }

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

=item B<getAssociations>

Retrieve the fault IDs (or optionally fault objects) associated
with the specified project ID.

  @faults = $db->getAssociations( 'm01bu52' );
  @faultids = $db->getAssociations( 'm01bu52', 1);

If the optional second argument is true only the fault IDs
are retrieved.

Can return an empty list if there is no relevant association.

=cut

sub getAssociations {
  my $self = shift;
  my $projectid = shift;
  my $idonly = shift;

  # Cant use standard interface for ASSOCTABLE query since
  # OMP::FaultQuery does not yet know how to query the ASSOCTABLE
  my $ref = $self->_db_retrieve_data_ashash( "SELECT faultid FROM $ASSOCTABLE WHERE projectid = '$projectid'" );
  my @ids = map { $_->{faultid} } @$ref;

  # Now we have all the fault IDs
  # Do we want to convert to fault object
  @ids = map { $self->getFault( $_ ) } @ids
    unless $idonly;

  return @ids;
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

  # Insert the project association data
  # In this case we dont need an entry if there are no projects
  # associated with the fault since we never do a join requiring
  # a fault id to exist.
  my @entries = map { [ $fault->id, $_ ]  } $fault->projects;
  for my $assoc (@entries) {
    $self->_db_insert_data( $ASSOCTABLE, $assoc->[0], $assoc->[1] );
  }

  # Now loop over responses
  for my $resp ($fault->responses) {

    $self->_add_new_response( $fault->id, $resp);

  }

}

=item B<_add_new_response>

Add the supplied response to the specified fault.

  $db->_add_new_response( $id, $response );

Response must be an C<OMP::Fault::Response> object.
An exception of class C<OMP::Error::Authentication> is thrown
if the user ID associated with the response is invalid.

=cut

sub _add_new_response {
  my $self = shift;
  my $id = shift;
  my $resp = shift;

  my $author = $resp->author;
  my $date = $resp->date;
  my $text = $resp->text;

  # Verify user id is valid
  # Create UserDB object for user determination
  my $udb = new OMP::UserDB( DB => $self->db );
  $udb->verifyUser($author->userid)
    or throw OMP::Error::Authentication("Must supply a valid user id for the fault system ['".$author->userid."' invalid]");

  # Format the date in a way that sybase understands
  $date = $date->strftime("%Y%m%d %T");

  $self->_db_insert_data( $FAULTBODYTABLE,
			  $id, $date, $author->userid, $resp->isfault,
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

  # Update the status field
  $self->_db_update_data( $FAULTTABLE, 
			  { status => $close },
			  " faultid = $id");

}

=item B<_query_faultdb>

Query the fault database and retrieve the matching fault objects.
Queries must be supplied as C<OMP::FaultQuery> objects.

  @faults = $db->_query_faultdb( $query );

Faults are returned sorted by fault ID.

=cut

sub _query_faultdb {
  my $self = shift;
  my $query = shift;

  # Get the SQL
  my $sql = $query->sql( $FAULTTABLE, $FAULTBODYTABLE );

  # Fetch the data
  my $ref = $self->_db_retrieve_data_ashash( $sql );

  # Create UserDB object for user determination
  my $udb = new OMP::UserDB( DB => $self->db );

  # Create a cache for OMP::User objects since it is likely
  # that a single user will be involved in more than a single response
  my %users;

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

    # Generate a user object [hope the multiple Sybase accesses
    # are not too much of an overhead. Else will have to do a join
    # in the initial fault query.] and cache it
    my $userid = $faultref->{author};
    if (!exists $users{$userid} ) {
      $users{$userid} = $udb->getUser( $userid );
    }
    $faultref->{author} = $users{$userid};

    # Check it
    throw OMP::Error::FatalError("User ID retrieved from fault system [$userid] does not match a valid user id")
      unless defined $users{$userid};

    # Determine the fault id
    my $id = $faultref->{faultid};

    # Create a new fault
    # One problem is that a new fault *requires* an initial "response"
    if (!exists $faults{$id}) {
      # Get the response object
      my $resp = new OMP::Fault::Response( %$faultref );

      # And the fault
      $faults{$id} = new OMP::Fault( %$faultref, fault => $resp);

      # Now get the associated projects
      # Note that we are not interested in generating OMP::Project objects
      # Only want to do this once per fault
      my $assocref = $self->_db_retrieve_data_ashash( "SELECT * FROM $ASSOCTABLE  WHERE faultid = $id" );
      $faults{$id}->projects( map { $_->{projectid} } @$assocref);

    } else {
      # Just need the response
      $faults{$id}->respond( new OMP::Fault::Response( %$faultref ) );

    }
  }

  # Sort the keys by faultid
  # [more efficient than sorting the objects by faultid]
  my @faults = sort { $a <=> $b } keys %faults;

  # Now return the values in the hash
  # as a hash slice
  return @faults{@faults};
}

=item B<_mail_fault>

Mail a fault and its responses to the fault email list and anyone who has previously
responded to the fault, but not to the author of the latest response.

  $db->_mail_response( $fault );

=cut

sub _mail_fault {
  my $self = shift;
  my $fault = shift;

  my $faultid = $fault->id;

  # Get the fault response(s)
  my @responses = $fault->responses;

  # The email subject
  my $subject = "[$faultid] " . $fault->subject;

  # Store fault meta info to strings
  my $system = $fault->systemText;
  my $type = $fault->typeText;
  my $loss = $fault->timelost;
  my $category = $fault->category;

  # Only show the status if this isn't the initial filing
  my $status = "<b>Status:</b> " . ($fault->isOpen ? "Open" : "Closed")
    if $responses[1];

  my $faultdatetext = "hrs at ". $fault->faultdate . " UT"
    if $fault->faultdate;

  my $faultauthor = $fault->author->html;

  # Create the fault meta info portion of our message
  my $meta =
"<pre>".
sprintf("%-58s %s","<b>System:</b> $system","<b>Fault type:</b> $type<br>").
sprintf("%-58s %s","<b>Time lost:</b> $loss" . "$faultdatetext","$status ").
"</pre><br>";

  my @msg;
  my @addr;

  # Use the address of the user that filed the latest response for the 'From:'
  my $from = $responses[-1]->author->email;

  # Create the message
  # We format the message using HTML since the _mail_information method will
  # provide a plain text version on it's own
  if ($responses[1]) {
    my %authors;

    # Make it noticeable if this fault is urgent
    push(@msg, "<div align=center><b>* * * * * URGENT * * * * *</b></div>")
      if $fault->isUrgent;

    # This is a response to a fault so arrange the responses in reverse order
    # followed by the meta info
    for (reverse @responses) {
      my $user = $_->author;

      my $author = $user->html; # This is an html mailto
      my $date = $_->date->ymd . " " . $_->date->hms;
      my $text = $_->text;

      # Store the author's email address
      $authors{$user->userid} = $_->author->email;

      # Once we get to the bottom (the initial report) add in the fault meta info
      if ($_->isfault) {
	 push(@msg, "$category fault filed by $author on $date<br><br>$text<br><br>");
	 push(@msg, "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~<br>$meta");
       } else {

	 push(@msg, "Response filed by $author on $date<br><br>$text<br><br>");
	 push(@msg, "--------------------------------------------------------------------------------<br>");
       }
    }

    # Add the addresses of the response authors to our address list
    # so we can mail them this response, provided they aren't the author
    # of this response.
    @addr = map {$authors{$_}} 
      grep {$authors{$_} ne $responses[-1]->author->email} keys %authors;

  } else {

    # This is an initial filing so arrange the message with the meta info first
    # followed by the initial report
    my $author = $responses[0]->author->html; # This is an html mailto
    my $date = $responses[0]->date->ymd . " " . $responses[0]->date->hms;
    my $text = $responses[0]->text;

    push(@msg, "$category fault filed by $author on $date<br><br>");

    # Make it noticeable if this fault is urgent
    push(@msg, "<div align=center><b>* * * * * URGENT * * * * *</b></div>")
      if $fault->isUrgent;
    push(@msg, "$meta~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~<br>$text<br><br>");
  }

  # Set link to response page
  my $responselink = "<a href='http://www.ukirt.jach.hawaii.edu/cgi-bin/viewfault.pl?id=$faultid'>here</a>";

  # Add the response link to the bottom of our message
  push(@msg, "--------------------------------<br>To respond to this fault go $responselink");

  # Our address list will start with the fault category's mailing list
  # COMMENTED OUT DURING TESTING
  # In order to get this partially working I have deleted the mailing lists
  # in OMP::Fault except for the OMP mailing list - TJ
  # add test here for undef mail_list
  my $fault_list = $fault->mail_list;
  unshift(@addr, $fault_list)
    if defined $fault_list;

#  if (! $addr[0]) {
#    # There's no one to send this thing to so let's just return
#    return;
#  }

  push(@addr, $from);

  # Mail it off
  $self->_mail_information(message => join('',@msg),
			   to => join(", ",@addr),
			   from => $from,
			   subject => $subject);

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
