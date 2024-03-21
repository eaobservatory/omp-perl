package OMP::BaseDB;

=head1 NAME

OMP::BaseDB - Base class for OMP database manipulation

=head1 SYNOPSIS

    $db->_db_begin_trans;

    $db->_db_commit_trans;

=head1 DESCRIPTION

This class has all the generic methods required by the OMP to
deal with database transactions of all kinds that are shared
between subclasses (ie nothing that is different between science
program database and project database).

=cut


use 5.006;
use strict;
use warnings;
use Carp;

# OMP Dependencies
use OMP::Error;
use OMP::Constants qw/:fb :logging/;
use OMP::NetTools;
use OMP::General;
use OMP::FeedbackDB;
use OMP::Mail;

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

Base class for constructing a new instance of a OMP DB connectivity
class.


    $db = OMP::BaseDB->new(
        ProjectID => $project,
        DB => $connection);

See C<OMP::ProjDB> and C<OMP::MSBDB> for more details on the
use of these arguments and for further keys.

If supplied, the database connection object must be of type
C<OMP::DBbackend>.  It is not accepted if that is not the case.
(but no error is raised - this is probably a bug).

=cut

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;

    # Read the arguments
    my %args;
    %args = @_ if @_;

    my $db = {
        InTrans => 0,
        Locked => 0,
        ProjectID => undef,
        DB => undef,
    };

    # create the object (else we cant use accessor methods)
    my $object = bless $db, $class;

    # Populate the object by invoking the accessor methods
    # Do this so that the values can be processed in a standard
    # manner. Note that the keys are directly related to the accessor
    # method name
    for (qw/ProjectID/) {
        my $method = lc($_);
        $object->$method($args{$_}) if exists $args{$_};
    }

    # Check the DB handle
    $object->_dbhandle($args{DB}) if exists $args{DB};

    return $object;
}

=back

=head2 Accessor Methods

=over 4

=item B<projectid>

The project ID associated with this object.

    $pid = $db->projectid;
    $db->projectid("M01BU53");

All project IDs are upper-cased automatically.

=cut

sub projectid {
    my $self = shift;
    if (@_) {
        $self->{ProjectID} = uc(shift);
    }
    return $self->{ProjectID};
}

=item B<_locked>

Indicate whether the system is currently locked.

    $locked = $db->_locked();
    $db->_locked(1);

=cut

sub _locked {
    my $self = shift;
    if (@_) {
        $self->{Locked} = shift;
    }
    return $self->{Locked};
}

=item B<_intrans>

Indicate whether we are in a transaction or not.

    $intrans = $db->_intrans();
    $db->_intrans(1);

Contains the total number of transactions entered into by this
instance. Must be zero or positive.

=cut

sub _intrans {
    my $self = shift;
    if (@_) {
        my $c = shift;
        $c = 0 if $c < 0;
        $self->{InTrans} = $c;
    }
    return $self->{InTrans};
}

=item B<_dbhandle>

Returns database handle associated with this object (the thing used by
C<DBI>).  Returns C<undef> if no connection object is present.

    $dbh = $db->_dbhandle();

Takes a database connection object (C<OMP::DBbackend> as argument in
order to set the state.

    $db->_dbhandle(OMP::DBbackend->new);

If the argument is C<undef> the database handle is cleared.

If the method argument is not of the correct type an exception
is thrown.

=cut

sub _dbhandle {
    my $self = shift;
    if (@_) {
        my $db = shift;
        if (UNIVERSAL::isa($db, "OMP::DBbackend")) {
            $self->{DB} = $db;
        }
        elsif (! defined $db) {
            $self->{DB} = undef;
        }
        else {
            throw OMP::Error::FatalError(
                "Attempt to set database handle in OMP::*DB using incorrect class");
        }
    }
    my $db = $self->{DB};
    if (defined $db) {
        return $db->handle;
    }
    else {
        return undef;
    }
}

=item B<db>

Retrieve the database connection (as an C<OMP::DBbackend> object)
associated with this object.

    $dbobj = $db->db();
    $db->db(OMP::DBbackend->new);

=cut

sub db {
    my $self = shift;
    if (@_) {
        $self->_dbhandle(shift);
    }
    return $self->{DB};
}

=back

=head2 DB methods

=over 4

=item B<_db_begin_trans>

Begin a database transaction. This is defined as something that has
to happen in one go or trigger a rollback to reverse it.

This method is delegated to C<OMP::DBbackend>.

=cut

sub _db_begin_trans {
    my $self = shift;

    my $db = $self->db
        or throw OMP::Error::DBError("Database connection not valid");

    OMP::General->log_message("Begin DB transaction", OMP__LOG_DEBUG);
    $db->begin_trans;

    # Keep a per-class count so that we can control
    # our destructor
    $self->_inctrans;

    OMP::General->log_message("Begun DB transaction", OMP__LOG_DEBUG);
}

=item B<_db_commit_trans>

Commit the transaction. This informs the database that everthing
is okay and that the actions should be finalised.

This method is delegated to C<OMP::DBbackend>.

=cut

sub _db_commit_trans {
    my $self = shift;

    my $db = $self->db
        or throw OMP::Error::DBError("Database connection not valid");

    OMP::General->log_message("Commit DB transaction", OMP__LOG_DEBUG);
    $db->commit_trans;

    # Keep a per-class count so that we can control
    # our destructor
    $self->_dectrans;

    OMP::General->log_message("Committed DB transaction", OMP__LOG_DEBUG);
}

=item B<_db_rollback_trans>

Rollback (ie reverse) the transaction. This should be called if
we detect an error during our transaction.

This method is delegated to C<OMP::DBbackend>.

This method triggers a full rollback of the entire transaction
regradless of whether other classes are using the transaction.
This is meant to be a feature!

=cut

sub _db_rollback_trans {
    my $self = shift;

    my $db = $self->db
        or throw OMP::Error::DBError("Database connection not valid");

    OMP::General->log_message("Rolling back DB transaction", OMP__LOG_DEBUG);
    $db->rollback_trans;

    # Reset the counter
    $self->_intrans(0);

    OMP::General->log_message("Rolled back DB transaction", OMP__LOG_DEBUG);
}

=item B<_inctrans>

Increment the transaction count by one.

=cut

sub _inctrans {
    my $self = shift;
    my $transcount = $self->_intrans;
    $self->_intrans(++ $transcount);
}

=item B<_dectrans>

Decrement the transaction count by one. Can not go lower than zero.

=cut

sub _dectrans {
    my $self = shift;
    my $transcount = $self->_intrans;
    $self->_intrans(-- $transcount);
}

=item B<_dblock>

Lock the MSB database tables (ompobs and ompmsb but not the project table)
so that they can not be accessed by other processes.

NOT IMPLEMENTED.

=cut

sub _dblock {
    my $self = shift;
    $self->_locked(1);
    return;
}

=item B<_dbunlock>

Unlock the system. This will allow access to the database tables and
file system.

For a transaction based database this is a nullop since the lock
is automatically released when the transaction is committed.

NOT IMPLEMENTED.

=cut

sub _dbunlock {
    my $self = shift;
    if ($self->_locked()) {
        $self->_locked(0);
    }
}

=item B<_db_findmax>

Find the maximum value of a column in the specified table using
the supplied WHERE clause.

    $max = $db->_db_findmax($table, $column, $clause);

The WHERE clause is optional (and should not include the "WHERE").

=cut

sub _db_findmax {
    my $self = shift;
    my $table = shift;
    my $column = shift;
    my $clause = shift;

    # Construct the SQL
    my $sql = "SELECT max($column) FROM $table ";
    $sql .= "WHERE $clause" if $clause;

    OMP::General->log_message("FindingMax: $sql", OMP__LOG_DEBUG);

    # Now run the query
    my $dbh = $self->_dbhandle;
    throw OMP::Error::DBError("Database handle not valid")
        unless defined $dbh;

    my $sth = $dbh->prepare($sql)
        or throw OMP::Error::DBError("Error preparing max SQL statment");

    $sth->execute
        or throw OMP::Error::DBError("DB Error executing max SQL: $DBI::errstr");

    my $max = ($sth->fetchrow_array)[0];

    OMP::General->log_message(
        "FoundMax: " . (defined $max ? $max : 0),
        OMP__LOG_DEBUG);

    return (defined $max ? $max : 0);
}

=item B<_db_insert_data>

Insert an array of data values into a database table.

    $db->_db_insert_data($table, @data);

It is assumed that the data is in the array in the same order
it appears in the database table [this method does not support
named inserts].

If an entry in the data array is a reference to a hash with a
key "SQL", then it is assumed to provide a fragment of SQL
which should give the required value.

If an entry in the data array contains a reference to a hash
(rather than a scalar) it is assumed that this indicates
a TEXT field (which is inserted in the same manner
as normal fields) and must have the following keys:

=over 4

=item TEXT
The text to be inserted.

=item COLUMN

The name of the column.

=back

Alternatively, if the second argument is a hash ref containing keys:

=over 4

=item COLUMN

The name of a reference almost uniqe column name.

=item POSN

Position (0 base) into @data for that column.

=item QUOTE

True if the value should be quoted.

=back

    $db->_db_insert_data($table, {
            COLUMN => 'projectid,
            POSN => 2,
        },
        @data);

=cut

sub _db_insert_data {
    my $self = shift;
    my $table = shift;

    # look for hint
    my $hints;
    if (ref($_[0]) eq 'HASH'
            && exists $_[0]->{COLUMN}
            && exists $_[0]->{POSN}) {
        $hints = shift;
    }

    # read the columns
    my @data = @_;

    # Now go through the data array building up the placeholder sql
    # deciding which fields can be stored immediately and which must be
    # insert as text fields

    # The insert place holder SQL
    my $placeholder = '';

    # Data to store now
    my @toinsert;

    # Data to store later
    for my $column (@data) {
        # Prepend a comma
        # if we have already stored something in the variable
        $placeholder .= ',' if $placeholder;

        # Plain text
        if (not ref($column)) {
            # the data we will insert immediately
            push @toinsert, $column;

            # Add a placeholder (the comma should be in already)
            $placeholder .= '?';
        }
        elsif (ref($column) eq 'HASH' and exists $column->{'SQL'}) {
            $placeholder .= sprintf '(%s)', $column->{'SQL'};
        }
        elsif (ref($column) eq "HASH"
                && exists $column->{TEXT}
                && exists $column->{COLUMN}) {
            push @toinsert, $column->{TEXT};
            $placeholder .= '?';
        }
        else {
            throw OMP::Error::DBError(
                "Do not understand how to insert data of class '"
                . ref($column)
                . "' into a database");
        }
    }

    # Construct the SQL
    my $sql = "INSERT INTO $table VALUES ($placeholder)";

    OMP::General->log_message(
        "Inserting DB data and retrieving handle",
        OMP__LOG_DEBUG);

    # Get the database handle
    my $dbh = $self->_dbhandle
        or throw OMP::Error::DBError("Database handle not valid");

    OMP::General->log_message("Inserting DB data: $sql", OMP__LOG_DEBUG);

    # Insert the easy data
    $dbh->do($sql, undef, @toinsert)
        or throw OMP::Error::DBError(
            "Error inserting data into table $table [$sql]: $DBI::errstr");

    OMP::General->log_message("Inserted DB data", OMP__LOG_DEBUG);
}

=item B<_db_retrieve_data_ashash>

Retrieve data from a database table as a reference to
an array containing references to hashes for each row retrieved.
Requires the SQL to be used for the query.

    $ref = $db->_db_retrieve_data_ashash($sql);

Additional arguments are assumed to be "bind values" and are
passed to the DBI method directly.

    $ref = $db->_db_retrieve_data_ashash($sql, @bind_values);

=cut

sub _db_retrieve_data_ashash {
    my $self = shift;
    my $sql = shift;

    # Get the handle
    my $dbh = $self->_dbhandle
        or throw OMP::Error::DBError("Database handle not valid");

    OMP::General->log_message("SQL retrieval: $sql", OMP__LOG_DEBUG);

    # Run query
    my $ref = $dbh->selectall_arrayref($sql, {Columns => {}}, @_)
        or throw OMP::Error::DBError(
            "Error retrieving data using [$sql]:" . $dbh->errstr);

    # Check to see if we only got a partial return array
    throw OMP::Error::DBError("Only retrieved partial dataset: " . $dbh->errstr)
        if $dbh->err;

    OMP::General->log_message(
        "Data retrieved: " . (scalar @$ref) . " rows match",
        OMP__LOG_DEBUG);

    # Return the results
    return $ref;
}

=item B<_db_update_data>

Update the values of specified columns in the table given the
supplied clause.

    $db->_db_update_data($table, \%new, $clause);

The table name must be supplied. The second argument contains a hash
reference where the keywords should match the columns to be changed
and the values should be the new values to insert.  The WHERE clause
should be supplied as SQL (no attempt is made to automatically
generate this information from a hash yet) and should not include the
"WHERE". The WHERE clause can be undefined if you want the update to
apply to all columns.

=cut

sub _db_update_data {
    my $self = shift;

    my $table = shift;
    my $change = shift;
    my $clause = shift;

    # Add WHERE
    $clause = " WHERE " . $clause if $clause;

    # Get the handle
    my $dbh = $self->_dbhandle
        or throw OMP::Error::DBError("Database handle not valid");

    my @change_cols = ();
    my @change_vals = ();

    # Loop over each key
    for my $col (keys %$change) {
        push @change_cols, $col;
        push @change_vals, $change->{$col};
    }

    # Construct the SQL
    my $sql = "UPDATE $table SET "
        . join(", ", map {"$_ = ?"} @change_cols)
        . $clause;

    OMP::General->log_message("Updating DB row: $sql", OMP__LOG_DEBUG);

    # Execute the SQL
    $dbh->do($sql, {}, @change_vals)
        or throw OMP::Error::DBError("Error updating [$sql]: " . $dbh->errstr);

    OMP::General->log_message("Row updated.", OMP__LOG_DEBUG);
}

=item B<_db_delete_data>

Delete the rows in the table given the
supplied clause.

    $db->_db_delete_data($table, $clause);

The table name must be supplied. The WHERE clause should be
supplied as SQL (no attempt is made to automatically generate this
information from a hash [yet) and should not include the "WHERE". The WHERE
clause is not optional.

=cut

sub _db_delete_data {
    my $self = shift;

    my $table = shift;
    my $clause = shift;
    throw OMP::Error::BadArgs("db_delete_data: Must supply a WHERE clause")
        unless $clause;

    # Get the handle
    my $dbh = $self->_dbhandle
        or throw OMP::Error::DBError("Database handle not valid");

    # Construct the SQL
    my $sql = "DELETE FROM $table WHERE $clause";

    OMP::General->log_message("Deleting DB data: $sql", OMP__LOG_DEBUG);

    # Execute the SQL
    $dbh->do($sql)
        or throw OMP::Error::DBError("Error deleting [$sql]: " . $dbh->errstr);

    OMP::General->log_message("Row deleted.", OMP__LOG_DEBUG);
}

=item B<_db_delete_project_data>

Delete all rows associated with the current project
from the specified tables.

    $db->_db_delete_project_data(@TABLES);

It is assumed that the current project is stored in table column
"projectid".  This is a thin wrapper for C<_db_delete_data> but
without having to specify the SQL.

Returns immediately if no project id is defined.

=cut

sub _db_delete_project_data {
    my $self = shift;

    # Get the project id
    my $proj = $self->projectid;
    return unless defined $proj;

    # Loop over each table
    for (@_) {
        $self->_db_delete_data($_, "projectid = '$proj'");
    }
}

=back

=head2 Feedback system

=over 4

=item B<_notify_feedback_system>

Notify the feedback system using the supplied message.

    $db->_notify_feedback_system(%comment);

Where the comment hash includes the keys supported by the
feedback system (see C<OMP::FeedbackDB>) and usually
consist of:

=over 4

=item author

The name of the system/person submitting comment.
Default is to use the current hostname and user
(or REMOTE_ADDR and REMOTE_USER if set).

=item program

The program implementing the change (defaults to
this program [C<$0>]).

=item sourceinfo

IP address of computer submitting comment.
Defaults to the current hostname or $REMOTE_ADDR
if set.

=item subject

Subject of comment. (Required)

=item text

The comment itself. (Required)

=item preformatted

Whether the text is preformatted?

=item status

Whether to mail out the comment or not. Default
is not to mail anyone.

=item msgtype

The type of comment being submitted (any of the
constants defined in OMP::Constants that begin
with OMP__FB_MSG_).

=back

=cut

sub _notify_feedback_system {
    my $self = shift;
    my %comment = @_;

    OMP::General->log_message(
        "BaseDB Notifying feedback system",
        OMP__LOG_DEBUG);

    # We have to share the database connection because we have
    # locked out the project table making it impossible for
    # the feedback system to verify the project
    my $fbdb = OMP::FeedbackDB->new(
        ProjectID => $self->projectid,
        DB => $self->db);

    # text and subject must be present
    throw OMP::Error::FatalError(
        "Feedback message must have subject and text\n")
        unless exists $comment{text} and exists $comment{subject};

    # If the author, program or sourceinfo fields are empty supply them
    # ourselves.
    (undef, my $addr, undef) = OMP::NetTools->determine_host;
    $comment{author} = undef unless exists $comment{author};
    $comment{sourceinfo} = $addr unless exists $comment{sourceinfo};
    $comment{program} = $0 unless exists $comment{program};

    $comment{status} = OMP__FB_HIDDEN unless exists $comment{status};
    $comment{msgtype} = OMP__FB_MSG_COMMENT unless exists $comment{msgtype};

    $comment{'preformatted'} = !! $comment{'preformatted'} if exists $comment{'preformatted'};

    # Add the comment
    $fbdb->addComment({%comment});

    OMP::General->log_message("Feedback message completed.", OMP__LOG_DEBUG);
}

=item B<_mail_information>

Mail some information to some people.

    $db->_mail_information(%details);

Uses C<Net::SMTP> for the mail service so that it can run in a tainted
environment. The argument hash should have the following keys:

=over 4

=item to

Array reference of C<OMP::User> objects.

=item cc

Array reference of C<OMP::User> objects.

=item bcc

Array reference of C<OMP::User> objects.

=item from

An C<OMP::User> object.

=item subject

Subject of the message.

=item message

The actual mail message.

=item headers

Additional mail headers such as Reply-To and Content-Type
in paramhash format.

=back

    $db->_mail_information(
        to => [$user1, $user2],
        from => $user3,
        subject => "hello",
        message => "this is the content\n",
        headers => {
            Reply-To => "you\@yourself.com",
        },
    );

Composes a multipart message with a plaintext attachment if any HTML is in the
message.  Throws an exception on error.

=cut

sub _mail_information {
    my $self = shift;
    my %args = @_;

    my $mailer = OMP::Mail->new();
    my $mess = $mailer->build(%args);
    return $mailer->send($mess);
}

=item B<DESTROY>

When this object is destroyed we need to roll back the transactions
started by this object. Since we do not know whether we are being
destroyed because we have simply gone out of scope (eg this class
instantiated a new DB class for a short while) or because of an error,
only rollback transactions if the internal count of transactions in
this class matches the active transaction count in the
C<OMP::DBbackend> object referenced by this object.

This relies on that object still being in existence (in which
case a rollback here is too late anyway).

If the counts do not match (hopefully because it has more than we
know about) set our count to zero and decrement the C<OMP::DBbackend>
count by the required amount.

=cut

sub DESTROY {
    my $self = shift;

    # Get the OMP::DBbackend
    my $db = $self->db;

    # it may not exist by now (depending on object destruction
    # order)
    if ($db) {
        # Now get the internal count
        my $thiscount = $self->_intrans;

        # Get the external count
        my $thatcount = $db->trans_count;

        if ($thiscount == $thatcount) {
            # fair enough. Rollback (doesnt matter if both == 0)
            OMP::General->log_message(
                "DESTROY: Rollback transaction $thiscount",
                OMP__LOG_DEBUG);
            $self->_db_rollback_trans;
        }
        elsif ($thiscount < $thatcount) {
            # Simply decrement this and that until we hit zero
            while ($thiscount > 0) {
                $self->_dectrans;
                $db->_dectrans;
                $thiscount --;
            }
        }
        else {
            die "Somehow the internal transaction count ($thiscount) is bigger than the DB handle count ($thatcount). This is scary.\n";
        }
    }
}

1;

__END__

=back

=head1 SEE ALSO

For related classes see C<OMP::MSBDB>, C<OMP::ProjDB> and
C<OMP::FeedbackDB>.

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
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
