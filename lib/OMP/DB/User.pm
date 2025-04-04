package OMP::DB::User;

=head1 NAME

OMP::DB::User - OMP user database manipulation

=head1 SYNOPSIS

    use OMP::DB::User;
    $db = OMP::DB::User->new(DB => OMP::DB::Backend->new);

    $db->addUser($user);
    $db->updateUser($user);
    $db->verifyUser($userid);
    $user = $db->getUser($userid);
    @users = $db->queryUser($query);

=head1 DESCRIPTION

The C<OMP::DB::User> class is used to manipulate the user database.

=cut

use 5.006;
use warnings;
use strict;

use List::Util qw/first/;

use OMP::User;
use OMP::Error;
use OMP::Query::User;

use base qw/OMP::DB/;

our $VERSION = '2.000';

our $USERTABLE = 'ompuser';

=head1 METHODS

=over 4

=item B<addUser>

Add a new user to the database.

    $db->addUser($user);

The argument must be of class C<OMP::User>.

Throws an exception if the user already exists in the database
(since all user IDs must be unique). Use C<updateUser> if you wish
to change the user details.

=cut

sub addUser {
    my $self = shift;
    my $user = shift;

    # Need to lock the database since we are writing
    $self->_db_begin_trans;
    $self->_dblock;

    # Make sure the user is not there already
    $self->verifyUser($user->userid)
        and throw OMP::Error::FatalError(
            "This user [" . $user->userid
            . "] already exists. Use updateUser to modify the information");

    # Make sure user's alias is not already in use
    if ($user->alias) {
        $self->verifyUser($user->alias)
            and throw OMP::Error::FatalError(
                "The alias [" . $user->alias
                . "] is already in use.  Use updateUser to modify the information");
    }

    # Add the user
    $self->_add_user($user);

    # End transaction
    $self->_dbunlock;
    $self->_db_commit_trans;

    return;
}

=item B<updateUser>

Update the details in the table associated with the
supplied user.

    $db->updateUser($user);

The argument should be of class C<OMP::User>.

=cut

sub updateUser {
    my $self = shift;
    my $user = shift;

    # Need to lock the database since we are writing
    $self->_db_begin_trans;
    $self->_dblock;

    # Make sure user's alias is not already in use by another user
    if ($user->alias) {
        my $userid = $self->verifyUser($user->alias);
        if ($userid and $userid ne $user->userid) {
            throw OMP::Error::FatalError(
                "The alias [" . $user->alias . "] is already in use.");
        }
    }

    # Modify
    $self->_update_user($user);

    # End transaction
    $self->_dbunlock;
    $self->_db_commit_trans;
}

=item B<verifyUser>

Verify that the user exists in the database. This is a thin wrapper
around B<getUser>. Returns user`s ID if user exists, else returns false.

    $isthere = $db->verifyUser($userid);

=cut

sub verifyUser {
    my $self = shift;
    my $userid = shift;

    my $user = $self->getUser($userid);

    return ($user ? $user->userid : undef);
}

=item B<verifyUserExpensive>

Verify that the user exists in the database. This is a thin wrapper
around B<getUserExpensive>. Returns user id list if users exist, else
an empty list.

    @id = $db->verifyUserExpensive($userid);

=cut

sub verifyUserExpensive {
    my $self = shift;
    my %args = @_;

    my @user = $self->getUserExpensive(%args);

    return map {$_->userid} @user;
}

=item B<getUser>

Retrieve information on the specified user name, where the user name is
either a user ID or an alias.

    $user = $db->getUser($username);

Returned as an C<OMP::User> object. Returns C<undef> if the
user can not be found.

=cut

sub getUser {
    my $self = shift;
    my $username = shift;

    return undef unless $username;

    # Create a query string
    my $query = OMP::Query::User->new(HASH => {userid => $username});

    my $result = $self->queryUsers($query);

    # If our query didn't match any user IDs try matching to an alias
    unless (@$result) {
        $query = OMP::Query::User->new(HASH => {alias => $username});
        $result = $self->queryUsers($query);
    }

    if (scalar(@$result) > 1) {
        throw OMP::Error::FatalError(
            "Multiple users match the supplied id [$username] - this is not possible [bizarre]");
    }

    # Guaranteed to be only one match
    return $result->[0];
}

=item B<getUserMultiple>

Method to retrieve multiple user records simultaneously.
This is intended to be used when matching with retrieve database entries,
so no fallback to alias is performed.  Returns a reference to a hash
by user ID.

    \%result = $db->getUserMultiple(\@user_ids);

=cut

sub getUserMultiple {
    my $self = shift;
    my $usernames = shift;

    # Avoid fetching everyone if no-one is specified.
    return {} unless @$usernames;

    return {
        map {$_->userid => $_} @{$self->queryUsers(
            OMP::Query::User->new(HASH => {userid => $usernames}))}
    };
}

=item B<getUserExpensive>

Returns a list of C<OMP::User> objects, given at least one of user
name, email, user id, cadc user id, and alias.

    @user = $db->getUserExpensive(
        'name' => 'Entity Example',
        'userid' => 'EXMPALE',
        'alias' => 'EXMPALES',
        'cadcuser' => 'exam',
        'email' => 'entity@example.org',
    );

=cut

sub getUserExpensive {
    my $self = shift;
    my %attr = @_;

    return unless keys %attr;

    # Change to actual column names.
    my %convert = (
        'name' => 'uname',
        'cadc' => 'cadcuser',
    );

    for (keys %convert) {
        $attr{$convert{$_}} = delete $attr{$_}
            if exists $attr{$_};
    }

    my $msg = '';
    for my $k (keys %attr) {
        $msg .= "(getUserExpensive) Unknown key: $k\n"
            unless first {$k eq $_} qw[ uname email userid alias cadcuser ];
    }
    $msg and throw OMP::Error $msg;

    my $users = $self->_query_userdb_expensive(%attr);
    return unless $users;

    _convert_columns($users);

    return map OMP::User->new(%{$_}), @{$users};
}

=item B<queryUsers>

Query the user database table and retrieve the matching user objects.
Queries must be supplied as C<OMP::Query::User> objects.

    $users = $db->queryUsers($query);

=cut

sub queryUsers {
    my $self = shift;
    my $query = shift;

    return $self->_query_userdb($query);
}

=item B<deleteUser>

Delete the specified user from the system.

    $db->deleteUser($userid);

=cut

sub deleteUser {
    my $self = shift;
    my $userid = shift;

    # Need to lock the database since we are writing
    $self->_db_begin_trans;
    $self->_dblock;

    # Delete the user
    $self->_db_delete_data($USERTABLE, "userid = '$userid'");

    # End transaction
    $self->_dbunlock;
    $self->_db_commit_trans;
}

=item B<inferValidUser>

Given a string (either from an email "From:" header or from
an HTML snippet), extract user information (name, user ID and
email address) and match it to a valid OMP user present in the
system.

If a valid user exists in the system with the same user ID
as the extracted user, the email address is compared to confirm
the match. If the email addresses have the same domain but differ
in the details of the user-specific part it is still treated
as a match (consider "t.jenness" and "timj") since the chances of
having a valid user ID from the same domain are slim (hopefully).
Also, if we do not have a valid user ID but we have an exact email
match we treat that as a match (we may simply have encountered
a non-standard user ID).

    $user = $db->inferValidUser($string);

Returns undef if a valid user can not be extracted from the string,
if the derived user ID is not present in the system, if the
extracted email address domain does not match or if an exact
match on email address is not possible for the entire database.

Note that this method cannot easily deal with the case where we
have a non-standard user ID linked to an email address that has
been rewritten by a mail server since it is not attempting
to compare names.

=cut

sub inferValidUser {
    my $self = shift;
    my $string = shift;

    # First guess who we are dealing with
    my $guess = OMP::User->extract_user($string);
    return unless defined $guess;

    # Now see if we have a user with that ID in the system
    my $valid = $self->getUser($guess->userid);

    # If we have a valid user for comparison, compare email domains
    if (defined $valid && $valid->domain eq $guess->domain) {
        return $valid;
    }

    # Could not find a match, look for an exact match on email
    my $query = OMP::Query::User->new(HASH => {email => $guess->email});

    my $result = $self->queryUsers($query);

    # hopefully we have only 1 match
    if (@$result) {
        return $result->[0];
    }
    else {
        return;
    }
}

=back

=head2 Internal Methods

=over 4

=item B<_add_user>

Add an C<OMP::User> object to the database (assuming it is
not in there already).

=cut

sub _add_user {
    my $self = shift;
    my $user = shift;

    # In some cases an email address is undefined
    # for now allow this by defining it (eventually we will allow
    # null fields)
    my $email = $user->email;

    $self->_db_insert_data(
        $USERTABLE,
        $user->userid,
        $user->name,
        $email,
        $user->alias,
        $user->cadcuser,
        $user->is_obfuscated(),
        $user->no_fault_cc(),
        0,  # staff_access
    );
}

=item B<_update_user>

Update the details of the supplied user. The user
must already exist (else nothing changes).

    $db->_update_user($user);

The details must be supplied as an C<OMP::User> object.

=cut

sub _update_user {
    my $self = shift;
    my $user = shift;

    # Update the fields
    $self->_db_update_data(
        $USERTABLE,
        {
            email => $user->email,
            uname => $user->name,
            alias => $user->alias,
            cadcuser => $user->cadcuser,
            obfuscated => $user->is_obfuscated(),
            no_fault_cc => $user->no_fault_cc(),
        },
        " userid = '" . $user->userid . "' "
    );
}

=item B<_query_userdb>

Query the user database table.

    $results = $db->_query_userdb($query);

Query must be an C<OMP::Query::User> object.

=cut

sub _query_userdb {
    my $self = shift;
    my $query = shift;

    # TODO: obtain table names from DB classes (preferably without circular imports)
    my $sql = $query->sql($USERTABLE, 'ompprojuser', 'ompfaultbody', 'ompobslog', 'ompshiftlog');

    # Fetch
    my $ref = $self->_db_retrieve_data_ashash($sql);

    # The user name attribute is stored in the database in column 'uname',
    # so replace key 'uname' with 'name'.  (And convert 'obfuscated'.)
    _convert_columns($ref);

    # Return the object equivalents
    return [map {
        $_->{email} = undef
            if (defined $_->{email} && length($_->{email}) eq 0);
        OMP::User->new(%$_)
    } @$ref];
}

=item B<_query_userdb_expensive>

Main purpose is to verify a user name, proposed user id, and email
address before adding user in the database, in turn to avoid
duplicates.

Returns an array reference of query results from the OMP users table.
It is expensive (than I<_query_userdb()>) in that it does inexact
search against almost all the columns (user name, email address,
alias, CADC user id).  The parameters are taken in as a hash.

    $result = $db->_query_userdb_expensive(
        'name' => 'Entity Example',
        'userid' => 'EXAMPLE',
        'alias' => 'EXAMPLES',
        'cadcuser' => 'exam',
        'email' => 'entity@example.org',
    );

Throws I<OMP::Error::FatalError> exception on query error.

=cut

sub _query_userdb_expensive {
    my ($self, %attr) = @_;

    my @col = qw/uname email userid alias cadcuser/;
    my @up_case = qw/userid alias/;

    my %check;
    for my $k (@col) {
        next unless exists $attr{$k} && defined $attr{$k};

        $attr{$k} = uc $attr{$k} if first {$k eq $_} @up_case;
        $check{$k} = $attr{$k};

        # Try a bit relaxed name search.
        $check{$k} =~ tr/. /%/
            if $k eq 'name';
    }

    my $sql = 'SELECT DISTINCT '
        . join(', ', (@col, 'obfuscated'))
        . " FROM $OMP::DB::User::USERTABLE "
        . ' WHERE '
        . join(' OR ', map {" $_ LIKE ? "} keys %check)
        . ' ORDER BY userid , email , uname';

    my $dbh = $self->_dbhandle;

    $dbh->trace(0);

    my $result = $dbh->selectall_arrayref($sql, {'Slice' => {}}, values %check)
        or throw OMP::Error::FatalError $dbh->errstr;

    return $result;
}

=item B<_convert_columns>

Returns nothing.  Takes in an array reference of hash reference with
entries as found in the database and renames them to match the fields
of OMP::User objects.

    $result = [{'name' => 'Entity Example'}];

    $db->_convert_columns($result);

    # $result now is "[{'uname' => 'Entity Example'}]".

=cut

{
    my %conversion = (
        name => 'uname',
        is_obfuscated => 'obfuscated',
    );

    sub _convert_columns {
        my $aref = shift;

        foreach my $entry (@$aref) {
            while (my ($to, $from) = each %conversion) {
                $entry->{$to} = delete $entry->{$from}
                    if exists $entry->{$from};
            }
        }
    }
}

1;

__END__

=back

=head1 SEE ALSO

This class inherits from C<OMP::DB>. It stores C<OMP::User>
objects

For related classes see C<OMP::DB::Project> and C<OMP::DB::Feedback>.

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

Anubhav E<lt>a.agarwal@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2002,2007-2008 Science and Technology Facilities Council.
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
