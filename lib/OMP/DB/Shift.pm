package OMP::DB::Shift;

=head1 NAME

OMP::DB::Shift - Shift log database manipulation

=head1 SYNOPSIS

    use OMP::DB::Shift;
    $db = OMP::DB::Shift->new(DB => OMP::DB::Backend->new);

    $db->enterShiftLog($comment, $telescope);
    $comment = $db->getShiftLogs($query);

=head1 DESCRIPTION

The C<OMP::DB::Shift> class is used to manipulate the shift log database.

=cut

use 5.006;
use warnings;
use strict;
use OMP::Info::Comment;
use OMP::Display;
use OMP::Error;
use OMP::DB::User;
use OMP::Query::Shift;
use OMP::DateTools;

use Astro::Telescope;

use Data::Dumper;

use base qw/OMP::DB/;

our $VERSION = '2.000';

our $SHIFTLOGTABLE = 'ompshiftlog';

our $DEBUG = 1;

=head1 METHODS

=head2 Public Methods

=over 4

=item B<enterShiftLog>

Add a comment to the shift log database.

    $db->enterShiftLog($comment, $telescope);

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
    my $udb = OMP::DB::User->new(DB => $self->db);
    unless (defined($author)) {
        throw OMP::Error::BadArgs("Must supply author with comment");
    }
    unless ($udb->verifyUser($author->userid)) {
        throw OMP::Error::BadArgs(
            "Userid supplied with comment not found in database");
    }

    # Ensure that a date is supplied with the comment.
    my $date = $comment->date;
    unless (defined($date)) {
        throw OMP::Error::BadArgs("Date not supplied with comment");
    }

    # Ensure that a telescope is supplied.
    if ((! defined($telescope))
            || (length($telescope . '') == 0)) {
        throw OMP::Error::BadArgs("Telescope not supplied");
    }

    # Lock the database and wrap all this in a transaction
    $self->_db_begin_trans;
    $self->_dblock;

    $self->_insert_shiftlog($comment, $telescope);

    # End transaction
    $self->_dbunlock;
    $self->_db_commit_trans;

    # Add the writing of the comment to the logs
    OMP::General->log_message(
        sprintf 'OMP::DB::Shift: %s %.50s',
        $author->userid, $comment->text);
}

=item B<updateShiftLog>

Update a comment in the shift log database.

    $db->updateShiftLog($comment);

The $comment argument passed to the method is an C<Info::Comment> object,
which must have an "id" attribute identifying the entry to update.

=cut

sub updateShiftLog {
    my $self = shift;
    my $comment = shift;

    my $id = $comment->id;

    $self->_db_begin_trans;
    $self->_dblock;

    $self->_update_shiftlog($id, $comment);

    $self->_dbunlock;
    $self->_db_commit_trans;
}

=item B<getShiftLogs>

Retrieve shift logs given a set of criteria defined in a query.

    @results = $db->getShiftLogs($query);

The argument is a C<OMP::Query::Shift> object, and the method returns
an array of C<Info::Comment> objects, ordered by date.

=cut

sub getShiftLogs {
    my $self = shift;
    my $query = shift;

    my $query_hash = $query->query_hash;

    if (! defined($query_hash->{date})
            && ! defined($query_hash->{author})
            && ! defined($query_hash->{telescope})
            && ! defined($query_hash->{shiftid})) {
        throw OMP::Error::FatalError(
            "Must supply one of shiftid, userid, date, or telescope.");
    }

    my @results = $self->_fetch_shiftlog_info($query);

    my @shiftlogs = $self->_reorganize_shiftlog(\@results);

    return (wantarray ? @shiftlogs : \@shiftlogs);
}

=back

=head2 Private Methods

=over 4

=item B<_fetch_shiftlog_info>

Retrieve the information from the shift log table using
the supplied query.

In scalar reference returns the first match via a reference to
a hash.

    $results = $db->_fetch_shiftlog_info($query);

In list context returns all matches as a list of hash references.

    @results = $db->_fetch_shiftlog_info($query);

=cut

sub _fetch_shiftlog_info {
    my $self = shift;
    my $query = shift;

    # Generate the SQL statement.
    my $sql = $query->sql($SHIFTLOGTABLE);

    # Run the query.
    my $ref = $self->_db_retrieve_data_ashash($sql);

    # If they want all the info just return the ref.
    # Otherwise, return the first entry.
    if (wantarray) {
        return @$ref;
    }
    else {
        my $hashref = (defined $ref->[0] ? $ref->[0] : {});
        return $hashref;
    }
}

=item B<_reorganize_shiftlog>

Given the results from the query (returned as a row per comment)
convert this output to an array of C<Info::Comment> objects.

    @results = $db->_reorganize_shiftlog($query_output);

=cut

sub _reorganize_shiftlog {
    my $self = shift;
    my $rows = shift;

    my @return;

    # Connect to the user database
    my $udb = OMP::DB::User->new(DB => $self->db);

    # Get the User information as an OMP::User object from the author ids
    my $users = $udb->getUserMultiple([keys %{{map {$_->{'author'} => 1} @$rows}}]);

    # For each row returned by the query, create an Info::Comment object
    # out of the information contained within.
    for my $row (@$rows) {
        push @return, OMP::Info::Comment->new(
            text => $row->{text},
            preformatted => $row->{'preformatted'},
            date => OMP::DateTools->parse_date($row->{date}),
            author => $users->{$row->{'author'}},
            relevance => $row->{'relevance'},
            id => $row->{'shiftid'},
            telescope => $row->{'telescope'},
        );
    }

    # Sort them by date.
    my @returnarray = sort {$a->date->epoch <=> $b->date->epoch} @return;

    return @returnarray;
}

=item B<_insert_shiftlog>

Store the given C<Info::Comment> object in the shift log
database.

    $db->_insert_shiftlog($comment, $telescope);

The second parameter can be either a C<Astro::Telescope> object or a string.

=cut

sub _insert_shiftlog {
    my $self = shift;
    my $comment = shift;
    my $telescope = shift;

    if (! defined($comment->date)
            || ! defined($comment->author)) {
        throw OMP::Error::BadArgs(
            "Must supply date and author properties to store a comment in the shiftlog database.");
    }

    unless (defined($telescope)) {
        throw OMP::Error::BadArgs(
            "Must supply a telescope to store a comment in the shiftlog database.");
    }

    my $author = $comment->author;

    my $telstring;
    if (UNIVERSAL::isa($telescope, "Astro::Telescope")) {
        $telstring = uc($telescope->name);
    }
    else {
        $telstring = uc($telescope);
    }

    my $t = $comment->date;  # - $comment->date->sec;
    my $date = $t->strftime("%Y-%m-%d %T");

    my %text = (
        "TEXT" => OMP::Display->remove_cr($comment->text),
        "COLUMN" => "text",
    );

    $self->_db_insert_data(
        $SHIFTLOGTABLE,
        {
            COLUMN => 'author',
            QUOTE => 1,
            POSN => 1,
        },
        undef, $date,
        $author->userid,
        $telstring,
        \%text,
        ($comment->preformatted ? 1 : 0));
}

=item B<_update_shiftlog>

Update the object in the shift log whose ID is given with the
information given in the supplied C<Info::Comment> object.

    $db->_update_shiftlog($id, $comment);

=cut

sub _update_shiftlog {
    my $self = shift;
    my $id = shift;
    my $comment = shift;

    unless (defined($id)) {
        throw OMP::Error::BadArgs("Must supply a shiftlog ID to update");
    }

    my %new = (
        text => OMP::Display->remove_cr($comment->text),
        preformatted => ($comment->preformatted ? 1 : 0),
    );

    $self->_db_update_data(
        $SHIFTLOGTABLE,
        \%new,
        "shiftid = $id");
}

=item B<_delete_shiftlog>

Delete the shiftlog whose ID is given.

    $db->_delete_shiftlog($id);

=cut

sub _delete_shiftlog {
    my $self = shift;
    my $id = shift;

    unless (defined($id)) {
        throw OMP::Error::BadArgs("Must supply a shiftlog ID to delete");
    }

    my $where = "shiftid = $id";
    $self->_db_delete_data($SHIFTLOGTABLE, $where);
}

1;

__END__

=back

=head1 SEE ALSO

This class inherits from C<OMP::DB>.

For related classes see C<OMP::DB::Project> and C<OMP::DB::Feedback>.

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
along with this program; if not, write to the
Free Software Foundation, Inc., 59 Temple Place, Suite 330,
Boston, MA  02111-1307  USA

=cut
