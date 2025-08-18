package OMP::DB::Fault;

=head1 NAME

OMP::DB::Fault - Fault database manipulation

=head1 SYNOPSIS

    use OMP::DB::Fault;
    $db = OMP::DB::Fault->new(DB => OMP::DB::Backend->new);

    $faultid = $db->fileFault($fault);
    $db->respondFault($faultid, $response);
    $fault = $db->getFault($faultid);
    $faultgroup = $db->queryFaults($query);

=head1 DESCRIPTION

The C<OMP::DB::Fault> class is used to manipulate the fault database. It is
designed to work with faults from multiple systems at once. The
database consists of two tables: one for general fault information
and one for the text associated with the fault report.

=cut

use 5.006;
use warnings;
use strict;
use OMP::Fault;
use OMP::Fault::Response;
use OMP::Query::Fault;
use OMP::Fault::Group;
use OMP::Fault::Util;
use OMP::Error;
use OMP::DB::User;
use OMP::DateTools;
use OMP::General;
use OMP::Config;

use base qw/OMP::DB/;

our $VERSION = '2.000';

our $FAULTTABLE = 'ompfault';
our $FAULTBODYTABLE = 'ompfaultbody';
our $ASSOCTABLE = 'ompfaultassoc';

our $DEBUG = 1;

=head1 METHODS

=head2 Public Methods

=over 4

=item B<fileFault>

Create a new fault and return the new fault ID. The fault ID
is unique and can be used to address the fault in future.

    $id = $db->fileFault($fault);

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
    my $id = $self->_get_next_faultid($fault->filedate);

    # Store the id in the fault object
    $fault->id($id);

    # Now write it to the database
    $self->_store_new_fault($fault);

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

    $db->respondFault($faultid, $response);

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
    $self->_add_new_response($id, $response);

    # End transaction
    $self->_dbunlock;
    $self->_db_commit_trans;

    # Mail out the response to the correct mailing list
    # We do this outside of our transaction since the SMTP server
    # has been known to fail and we don't want the fault lost
    my $fault = $self->getFault($id);

    $self->_mail_fault($fault);
}

=item B<getFault>

Retrieve the specified fault from the database.

    $fault = $db->getFault($id, %options);

Returned as a C<OMP::Fault> object. Returns undef if the fault can not
be found in the database.  C<%options> are as for C<queryFaults>.

=cut

sub getFault {
    my $self = shift;
    my $id = shift;

    # No transaction required
    # Treat this as a DB query
    my $query = OMP::Query::Fault->new(HASH => {
        faultid => $id,
    });

    my $result = $self->_query_faultdb($query, @_);

    if (scalar(@$result) > 1) {
        throw OMP::Error::FatalError(
            "Multiple faults match the supplied id [$id] - this is not possible [bizarre]");
    }

    # Guaranteed to be only one match
    return $result->[0];
}

=item B<queryFaults>

Query the fault database and retrieve the matching fault objects
in an C<OMP::Fault::Group>.

Queries must be supplied as C<OMP::Query::Fault> objects.

    $faultgroup = $db->queryFaults($query, %options);

Options can be given to optimize the query strategy for the
desired purpose:

=over 4

=item no_projects

Do not fetch the list of projects assoicated with each fault.

=item no_text

Do not fetch the full text body of each "response" (including initial filing).

=back

=cut

sub queryFaults {
    my $self = shift;
    my $query = shift;

    return OMP::Fault::Group->new(
        faults => $self->_query_faultdb($query, @_),
    );
}

=item B<getAssociations>

Retrieve the fault IDs (or optionally fault objects) associated
with the specified project ID.

    $faultgroup = $db->getAssociations('M01BU52');
    @faultids = $db->getAssociations('M01BU52', 1);

If the optional second argument is true only the fault IDs
are retrieved.  Otherwise the fault objects are retrieved
(excluding the project list).

Can return an empty group/list if there is no relevant association.

=cut

sub getAssociations {
    my $self = shift;
    my $projectid = shift;
    my $idonly = shift;

    # Cant use standard interface for ASSOCTABLE query since
    # OMP::Query::Fault does not yet know how to query the ASSOCTABLE
    my $ref = $self->_db_retrieve_data_ashash(
        "SELECT faultid FROM $ASSOCTABLE WHERE projectid = ? ORDER BY faultid ASC",
        $projectid);
    my @ids = map {$_->{faultid}} @$ref;

    return @ids if $idonly;

    # Now we have all the fault IDs
    # Do we want to convert to fault object
    return OMP::Fault::Group->new(
        faults => [map {$self->getFault($_, no_projects => 1)} @ids],
    );
}

=item B<updateFault>

Update details for a fault by deleting the entry from the database
and creating a new entry with the updated details.  Second optional argument
is the identity of the user who updated the fault (either a string
or an C<OMP::User> object).  If this is not given no email will be sent.

    $db->updateFault($fault, $user);

Argument should be supplied as an C<OMP::Fault> object.
This method will not update the associated responses.

=cut

sub updateFault {
    my $self = shift;
    my $fault = shift;
    my $user = shift;

    # Get the fault from the DB so we can compare it later with our
    # new fault and notify the "owner" of changes made
    my $oldfault = $self->getFault($fault->id);

    # Begin transaction
    $self->_db_begin_trans;
    $self->_dblock;

    # Do the update
    $self->_update_fault_row($fault);

    # End transaction
    $self->_dbunlock;
    $self->_db_commit_trans;

    # Mail notice to fault "owner"
    $self->_mail_fault_update($fault, $oldfault, $user)
        if $user;
}

=item B<updateResponse>

Update a fault response by deleting the response for the database and then reinserting
it with new values.

    $db->updateResponse($faultid, $response);

The first argument should be the ID of the fault that the response is associated with.
The second argument should be an C<OMP::Fault::Response> object.

=cut

sub updateResponse {
    my $self = shift;
    my $faultid = shift;
    my $response = shift;

    # Begin transaction
    $self->_db_begin_trans;
    $self->_dblock;

    # Do the update
    $self->_update_response_row($faultid, $response);

    # End transaction
    $self->_dbunlock;
    $self->_db_commit_trans;
}

=back

=head2 Internal Methods

=over 4

=item B<_get_next_faultid>

For the supplied date, determine the next fault id.

    $newid = $db->_get_next_faultid($date);

Fault IDs take the form C<YYYYMMDD.NNN> where NNN increases
by one for each fault filed on day YYYYMMDD.

=cut

sub _get_next_faultid {
    my $self = shift;
    my $date = shift;

    # First get the date (only the day, month and year)
    my $yyyymmdd = $date->strftime("%Y%m%d");

    # Get the current highest value
    my $max = $self->_db_findmax(
        $FAULTTABLE,
        "faultid",
        "floor(faultid) = $yyyymmdd");

    # If we have zero back then this is the first fault of the day
    $max = $yyyymmdd unless $max;

    # Add 0.001 to the result
    $max += 0.001;

    # and format for rounding errors
    return sprintf("%.3f", $max);
}

=item B<_store_new_fault>

Store the supplied fault in the database.

    $db->_store_new_fault($fault);

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

    # Insert the data into the table
    $self->_db_insert_data(
        $FAULTTABLE,
        $fault->id,
        $fault->category,
        $fault->subject,
        $fault->type,
        $fault->system,
        $fault->status,
        $fault->urgency,
        $fault->entity,
        $fault->condition,
        $fault->location,
    );

    # Insert the project association data
    # In this case we dont need an entry if there are no projects
    # associated with the fault since we never do a join requiring
    # a fault id to exist.
    $self->_insert_assoc_rows($fault->id, $fault->projects);

    # Now loop over responses
    for my $resp ($fault->responses) {
        $self->_add_new_response($fault->id, $resp);
    }
}

=item B<_add_new_response>

Add the supplied response to the specified fault.

    $db->_add_new_response($id, $response);

Response must be an C<OMP::Fault::Response> object.
An exception of class C<OMP::Error::Authentication> is thrown
if the user ID associated with the response is invalid.

=cut

sub _add_new_response {
    my $self = shift;
    my $id = shift;
    my $resp = shift;

    my $cols = $self->_prepare_response_columns($id, $resp);

    $self->_db_insert_data(
        $FAULTBODYTABLE,
        undef, $id,
        @{$cols}{qw/date author isfault text/},
        {
            SQL => sprintf 'select coalesce(max(respnum) + 1, 0) from %s AS fb2 where faultid = %s',
            $FAULTBODYTABLE, $id
        },
        @{$cols}{qw/flag preformatted faultdate timelost shifttype remote/}
    );
}

=item B<_prepare_response_columns>

Prepare columns for response table which are common between
insert and update operations.

=cut

sub _prepare_response_columns {
    my $self = shift;
    my $id = shift;
    my $resp = shift;

    my $author = $resp->author;
    my $date = $resp->date;
    my $text = $resp->text;

    # Verify user id is valid
    # Create OMP::DB::User object for user determination
    my $udb = OMP::DB::User->new(DB => $self->db);
    my $userid = $udb->verifyUser($author->userid);

    throw OMP::Error::Authentication(
        "Must supply a valid user id for the fault system ['"
        . $author->userid . "' invalid]")
        unless ($userid);

    # Date must be formatted for MySQL
    my $faultdate = $resp->faultdate;
    $faultdate = $faultdate->strftime("%Y-%m-%d %T")
        if defined $faultdate;

    return {
        date => $date->strftime("%Y-%m-%d %T"),
        author => $userid,
        isfault => $resp->isfault,
        text => $text,
        preformatted => $resp->preformatted,
        flag => $resp->flag,
        faultdate => $faultdate,
        timelost => $resp->timelost,
        shifttype => $resp->shifttype,
        remote => $resp->remote,
    };
}

=item B<_query_faultdb>

Query the fault database and retrieve the matching fault objects.
Queries must be supplied as C<OMP::Query::Fault> objects.

    $faults = $db->_query_faultdb($query, %options);

Faults are returned sorted by fault ID.

=cut

sub _query_faultdb {
    my $self = shift;
    my $query = shift;
    my %opt = @_;

    # Get the SQL
    my $sql = $query->sql(
        $FAULTTABLE, $FAULTBODYTABLE,
        no_text => $opt{'no_text'});

    # Fetch the data
    my $ref = $self->_db_retrieve_data_ashash($sql);

    # Create OMP::DB::User object for user determination
    my $udb = OMP::DB::User->new(DB => $self->db);

    # Create a cache for OMP::User objects since it is likely
    # that a single user will be involved in more than a single response
    my $users = $udb->getUserMultiple([keys %{{map {$_->{'author'} => 1} @$ref}}]);

    # Now loop through the faults, creating objects and
    # matching responses.
    # Use a hash to indicate whether we have already seen a fault
    my %faults;
    my @defresponse = ();
    push @defresponse, text => 'NOT RETRIEVED' if $opt{'no_text'};
    for my $faultref (@$ref) {
        # First convert dates to date objects
        $faultref->{date} = OMP::DateTools->parse_date($faultref->{date});
        $faultref->{faultdate} = OMP::DateTools->parse_date($faultref->{faultdate})
            if defined $faultref->{faultdate};

        my $userid = $faultref->{author};

        # Check it
        throw OMP::Error::FatalError(
            "User ID retrieved from fault system [$userid] does not match a valid user id")
            unless defined $users->{$userid};

        $faultref->{author} = $users->{$userid};

        # Fault's system attribute is stored in the database in column 'fsystem',
        # so replace key 'fsystem' with 'system'
        $faultref->{system} = $faultref->{fsystem};
        delete $faultref->{fsystem};

        # Determine the fault id
        my $id = $faultref->{faultid};

        # Create a new fault
        # One problem is that a new fault *requires* an initial "response"
        unless (exists $faults{$id}) {
            # Get the response object
            my $resp = OMP::Fault::Response->new(@defresponse, %$faultref);

            # And the fault
            $faults{$id} = OMP::Fault->new(%$faultref, fault => $resp);

            # Now get the associated projects
            # Note that we are not interested in generating OMP::Project objects
            # Only want to do this once per fault
            unless ($opt{'no_projects'}) {
                my $assocref = $self->_db_retrieve_data_ashash(
                    "SELECT * FROM $ASSOCTABLE  WHERE faultid = ?", $id);
                $faults{$id}->projects(map {$_->{projectid}} @$assocref);
            }
        }
        else {
            # Just need the response
            $faults{$id}->respond(OMP::Fault::Response->new(@defresponse, %$faultref));
        }
    }

    # Sort the keys by faultid
    # [more efficient than sorting the objects by faultid]
    return [map {$faults{$_}} sort {$a <=> $b} keys %faults];
}

=item B<_update_fault_row>

Delete and reinsert fault values.

    $db->_update_fault_row($fault);

where C<$fault> is an object of type C<OMP::Fault>.

=cut

sub _update_fault_row {
    my $self = shift;
    my $fault = shift;

    if (UNIVERSAL::isa($fault, "OMP::Fault")) {
        # Our where clause for the delete
        my $clause = "faultid = " . $fault->id;

        # Delete the row for this fault
        $self->_db_delete_data($FAULTTABLE, $clause);

        # Insert the new values
        $self->_db_insert_data(
            $FAULTTABLE,
            $fault->id,
            $fault->category,
            $fault->subject,
            $fault->type,
            $fault->system,
            $fault->status,
            $fault->urgency,
            $fault->entity,
            $fault->condition,
            $fault->location,
        );

        # Insert the project association data
        # In this case we dont need an entry if there are no projects
        # associated with the fault since we never do a join requiring
        # a fault id to exist.
        $self->_insert_assoc_rows($fault->id, $fault->projects);

    }
    else {
        throw OMP::Error::BadArgs(
            "Argument to _update_fault_row must be of type OMP::Fault\n");
    }
}

=item B<_update_response_row>

Delete and reinsert a fault response.

    $db->_update_response_row($faultid, $response);

where C<$faultid> is the id of the fault the response should be associated with
and C<$response> is an C<OMP::Fault::Response> object.

=cut

sub _update_response_row {
    my $self = shift;
    my $faultid = shift;
    my $resp = shift;

    if (UNIVERSAL::isa($resp, "OMP::Fault::Response")) {
        # Where clause for the update
        my $clause = "respid = " . $resp->id;

        my $cols = $self->_prepare_response_columns($faultid, $resp);

        # Update the response
        $self->_db_update_data($FAULTBODYTABLE, $cols, $clause);
    }
    else {
        throw OMP::Error::BadArgs(
            "Argument to _update_response_row must be of type OMP::Fault::Response\n");
    }
}

=item B<_insert_assoc_rows>

Insert fault project association entries.  Do a delete first to get rid of
any old associations.

    $db->_insert_assoc_rows($faultid, @projects);

Takes a fault ID as the first argument and an array of project IDs as the
second argument

=cut

sub _insert_assoc_rows {
    my $self = shift;
    my $faultid = shift;
    my @projects = @_;

    # Delete clause
    my $clause = "faultid = $faultid";

    # Do the delete
    $self->_db_delete_data($ASSOCTABLE, $clause);

    my @entries = map {[$faultid, $_]} @projects;
    for my $assoc (@entries) {
        $self->_db_insert_data($ASSOCTABLE, undef, $assoc->[0], $assoc->[1]);
    }
}

=item B<_mail_fault>

Mail a fault and its responses to the fault email list and anyone who has previously
responded to the fault, but not to the author of the latest response.

    $db->_mail_response($fault);

=cut

sub _mail_fault {
    my $self = shift;
    my $fault = shift;

    my $faultid = $fault->id;

    my @responses = $fault->responses;

    my $system = $fault->systemText;
    my $type = $fault->typeText;

    # The email subject
    my $subject = "[$faultid] $system/$type - " . $fault->subject;

    # Make it obvious in the subject if fault is urgent
    if ($fault->isUrgent) {
        $subject = "*** URGENT *** $subject";
    }

   # Create a list of users to Cc (but not if they authored the latest response)
    my %cc_seen = ($responses[-1]->author()->userid() => 1);
    my @cc;
    foreach my $response (@responses) {
        my $author = $response->author();
        next if $author->no_fault_cc();
        next if $cc_seen{$author->userid()} ++;
        push @cc, $author;
    }

    my @faultusers = $fault->mail_list_users;

    # If there is no email address associated with author of last response
    # use the fault list "user" for the From header
    my $from;
    if ($responses[-1]->author->email) {
        $from = $responses[-1]->author;
    }
    elsif (scalar @faultusers) {
        $from = $faultusers[0];
    }
    else {
        # No address to send from - do not attempt to mail the fault.
        return;
    }

    # If there is no list, send directly to recipients rather than using CC?
    unless (scalar @faultusers) {
        return unless scalar @cc;
        @faultusers = @cc;
        @cc = ();
    }

    # Get the fault message
    my $msg = OMP::Fault::Util->format_fault(
        $fault, 0,
        max_entries => 10,
    );

    # Mail it off

    # Note: since format_fault will already have wrapped the text, and includes
    # <pre> sections with styling tags, suppress wrapping with wrap_width_preformatted=0
    # and also specify a largish wrap_width value to avoid excessive plain text wrapping.
    $self->_mail_information(
        message => $msg,
        preformatted => 1,
        to => \@faultusers,
        cc => \@cc,
        from => $from,
        subject => $subject,
        reply_to_sender => 1,
        wrap_width => 120,
        wrap_width_preformatted => 0,
    );
}

=item B<_mail_fault_update>

Determine what fault properties have changed and mail current properties
to the fault owner.  First argument is an C<OMP::Fault> object containing
the faults current properties.  Second argument is an C<OMP::Fault> object
containing the faults properties before the update occurred.  Final argument
is a string or C<OMP::User> object identifying the user who updated the
fault.

    $db->_mail_fault_update($currentfault, $oldfault, $user);

=cut

sub _mail_fault_update {
    my $self = shift;
    my $fault = shift;
    my $oldfault = shift;
    my $user = shift;

    # Convert user object to HTML string
    if (UNIVERSAL::isa($user, "OMP::User")) {
        $user = $user->html;
    }

    my $msg = "Fault " . $fault->id . " [" . $oldfault->subject
        . "] has been changed as follows by $user:<br><br>";

    # Map property names to their accessor method names
    my %property = (
        systemText => 'System',
        typeText => 'Type',
        statusText => 'Status',
        subject => 'Subject',
        category => 'Category',
        urgency => 'Urgency',
        condition => 'Condition',
        projects => 'Projects',
        locationText => 'Location',
    );

    # Compare the fault details
    my @details_changed = OMP::Fault::Util->compare($fault, $oldfault);

    # Build up a message
    for (@details_changed) {
        if ($_ =~ /system/) {
            $_ = 'systemText';
        }
        elsif ($_ =~ /^type/) {
            $_ = 'typeText';
        }
        elsif ($_ =~ /status/) {
            $_ = 'statusText';
        }
        elsif ($_ eq 'location') {
            $_ = 'locationText';
        }

        my $property = $property{$_};
        my $oldfault_prop;
        my $newfault_prop;

        if (ref($fault->$_) eq "ARRAY") {
            $oldfault_prop = join(', ', @{$oldfault->$_});
            $newfault_prop = join(', ', @{$fault->$_});
        }
        else {
            $oldfault_prop = $oldfault->$_;
            $newfault_prop = $fault->$_;
        }

        $msg .= "$property updated from <b>$oldfault_prop</b> to <b>$newfault_prop</b><br>";
    }

    my $public_url = OMP::Config->getData('omp-url') . OMP::Config->getData('cgidir');

    $msg .= "<br>You can view the fault <a href='$public_url/viewfault.pl?fault="
        . $fault->id . "'>here</a>";

    my $email = $fault->author;

    my @faultusers = $fault->mail_list_users;

    # Don't want to attempt to mail the fault if author doesn't have an email
    # address (or we don't have an address from which to send).
    if ($fault->author->email and scalar @faultusers) {
        $self->_mail_information(
            message => $msg,
            preformatted => 1,
            to => [$fault->author],
            from => $faultusers[0],
            subject => "Your fault [" . $fault->id . "] has been updated",
        ) unless $fault->author->no_fault_cc();
    }
}

1;

__END__

=back

=head1 SEE ALSO

This class inherits from C<OMP::DB>.

For related classes see C<OMP::DB::Project> and C<OMP::DB::Feedback>.

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

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
along with this program; if not, write to the
Free Software Foundation, Inc., 59 Temple Place, Suite 330,
Boston, MA  02111-1307  USA

=cut
