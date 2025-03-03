package OMP::DB::Obslog;

=head1 NAME

OMP::DB::Obslog - Manipulate observation log table

=head1 SYNOPSIS

    use OMP::DB::Obslog;

    $db = OMP::DB::Obslog->new(
        ProjectID => 'm01bu05',
        DB => OMP::DB::Backend->new);

    $db->addComment($comment, $instrument, $date, $runnr);

    @output = $db->queryObslog($query);

=head1 DESCRIPTION

The observation log table exists to allow us to associate user-supplied
comments with observations. It does this by having a simple logging table
where a new row is added each time an observation is commented upon.

=cut

use 5.006;
use warnings;
use strict;

use Carp;
use OMP::Error qw/:try/;
use OMP::Constants qw/:obs :logging/;
use OMP::DateTools;
use OMP::General;
use OMP::Info::Obs;
use OMP::Info::Obs::TimeGap;
use OMP::Info::Comment;
use OMP::Query::Obslog;
use Time::Piece;
use Time::Seconds;
use OMP::User;
use OMP::DB::User;
use Data::Dumper;

use base qw/OMP::DB/;

our $VERSION = '2.000';

our $OBSLOGTABLE = 'ompobslog';

=head1 METHODS

=head2 Public Methods

=over 4

=item B<addComment>

Add a comment to the database.

    $db->addComment($comment, $obs, $user);

The supplied parameters are an C<OMP::Info::Comment> object or a string as
the comment text, and an C<OMP::Info::Obs> object for which the comment was
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
    if (ref($comment)) {
        # Fall over if we aren't a comment object.
        throw OMP::Error::BadArgs(
            "Wrong class for comment object: " . ref($comment))
            unless UNIVERSAL::isa($comment, "OMP::Info::Comment");
    }
    elsif ($comment =~ /^\d+$/a) {
        # An integer index.
        $comment = ($obs->comments)[$comment];
    }
    else {
        # Some other random text. Don't bother to add a status yet.
        $comment = OMP::Info::Comment->new(text => $comment);
    }

    # Make sure we have a defined comment.
    throw OMP::Error::BadArgs("Unable to determine comment object")
        unless defined $comment;

    # Make sure we can uniquely identify the observation. This is done by
    # looking for an instrument, a run number, and a UT date in the Obs
    # object.
    if (UNIVERSAL::isa($obs, "OMP::Info::Obs::TimeGap")) {
        throw OMP::Error::BadArgs("Unable to uniquely identify observation")
            unless defined $obs->instrument
            and defined $obs->runnr
            and defined $obs->endobs;
    }
    else {
        throw OMP::Error::BadArgs("Unable to uniquely identify observation")
            unless defined $obs->instrument
            and defined $obs->runnr
            and defined $obs->startobs;
    }

    # Grab or verify the user id if it's given.
    my $userobj;
    if ($user) {
        if (UNIVERSAL::isa($user, 'OMP::User')) {
            my $udb = OMP::DB::User->new(DB => $self->db);
            unless ($udb->verifyUser($user->userid)) {
                throw OMP::Error::BadArgs("Must supply a valid user");
            }
            $userobj = $user;
        }
        else {
            my $udb = OMP::DB::User->new(DB => $self->db);
            $userobj = $udb->getUser($user);
            unless (defined($userobj)) {
                throw OMP::Error::BadArgs("User id $user is not in database");
            }
        }
        $comment->author($userobj);
    }
    elsif (UNIVERSAL::isa($comment, 'OMP::Info::Comment')) {
        my $udb = OMP::DB::User->new(DB => $self->db);
        unless ($udb->verifyUser($comment->author->userid)) {
            throw OMP::Error::BadArgs(
                "Must supply a valid user with the comment");
        }
    }

    OMP::General->log_message(
        "OMP::DB::Obslog: Preparing for observation comment insert.\n");

    # Lock the database (since we are writing).
    $self->_db_begin_trans;
    $self->_dblock;

    OMP::General->log_message(
        "OMP::DB::Obslog: Database locked. Setting old observation comments to inactive.\n");

    # Set old observations in the archive to "inactive".
    $self->_set_inactive($obs, $comment->author->userid);

    OMP::General->log_message(
        "OMP::DB::Obslog: Old observation comments set to inactive. Inserting comment.\n");

    # Write the observation to database.
    $self->_store_comment($obs, $comment);

    OMP::General->log_message(
        "OMP::DB::Obslog: Comment inserted. Unlocking database.\n");

    # End transaction.
    $self->_dbunlock;
    $self->_db_commit_trans;

    OMP::General->log_message("OMP::DB::Obslog: Database unlocked.\n");

    return $self->_mail_staff_no_good($obs, $comment);
}

sub _mail_staff_no_good {
    my ($self, $obs, $comment) = @_;

    my $status = $comment->status();

    my @cond = (OMP__OBS_REJECTED());
    defined $status && scalar grep {$status == $_} @cond
        or return;

    my ($tel, $proj, $obsid) = map {$obs->$_()} qw/telescope projectid obsid/;

    my $obsref = join ': ', grep {defined $_} $obsid, $proj, $tel;

    OMP::General->log_message(
        "OMP::DB::Obslog: Preparing to send mail about obs ($obsref) no good.\n");

    my $to_key = 'mail.to-obs-rejected';
    my @to = grep {/./} OMP::Config->getData($to_key, 'telescope' => $tel);

    unless (scalar @to) {
        OMP::General->log_message(
            "OMP::DB::Obslog: No recipient email address ($to_key) found in $tel configuration.\n",
            OMP__LOG_WARNING);
        return;
    }

    my $from = OMP::Config->getData('mail.from-obs-rejected', 'telescope' => $tel)
        || OMP::User->get_flex()->email();

    # Only for useful Subject: header.
    my $com_user = $comment->author();
    my ($com_name, $com_addr);
    if ($com_user) {
        ($com_name, $com_addr) = map {$com_user->$_()} qw/name email/;
    }
    $com_name ||= ($com_addr || '<Comment User Not Found!>');

    ($from, @to) = map {OMP::User->new('email' => $_)} ($from, @to);

    my $subj = "$obsref: obs status changed, via $com_name";

    my $body = "Obs summary:\n"
        . $obs->summary('text')
        . "\n\n"
        . "Comment:\n"
        . $comment->summary('text');

    return $self->_mail_information(
        'from' => $from,
        'to' => \@to,
        'subject' => $subj,
        'message' => $body
    );
}

=item B<getComment>

Retrieve the most recent open comments for a given observation.
Observation must be supplied as an C<OMP::Info::Obs> object.

    @comment = $db->getComment($obs);

In this case the method returns an array of C<Info::Comment> objects.

    $comment = $db->getComment($obs);

In this case the method returns a reference to an array of
C<Info::Comment> objects.

An additional optional argument may be supplied to indicate that
all comments for the observation are to be returned.

    @allcomments = $db->getComment($obs, $allcomments);
    $allcomments = $db->getComment($obs, $allcomments);

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

    my %hash;
    my %options;

    # If $allcomments is true, then we don't want to limit
    # the query. Otherwise, we want to retrive comments
    # only for which obsactive = 1.
    unless ($allcomments) {
        $hash{'obsactive'} = {boolean => 1};
    }

    if (UNIVERSAL::isa($obs, "OMP::Info::Obs::TimeGap")) {
        if (! defined($obs->instrument)
                || ! defined($obs->runnr)
                || ! defined($obs->endobs)) {
            throw OMP::Error::BadArgs(
                "Must supply an Info::Obs::TimeGap object with defined instrument, run number, and date");
        }
        my $t = $obs->endobs - 1;

        # Query the old way for timegap comments
        %hash = (
            %hash,
            instrument => $obs->instrument,
            runnr => $obs->runnr,
            date => $t->ymd . 'T' . $t->hms,
        );
    }
    else {
        unless (defined($obs->obsid)) {
            throw OMP::Error::BadArgs(
                "Must supply an Info::Obs object with defined observation ID (obsid)");
        }

        # Query only on obsid for normal comments
        $hash{'obsid'} = $obs->obsid;

        $options{'allow_dateless'} = 1;
    }

    my $query = OMP::Query::Obslog->new(HASH => \%hash);
    my @results = $self->queryComments($query, \%options);

    # Return based on context and arguments.
    return (wantarray ? @results : \@results);
}

=item B<removeComment>

Remove from the database the comment for the given user id and
C<OMP::Info::Obs> object.

    $db->removeComment($obs, $userid);

This method does not permanently remove a comment, it flags all
comments for the given user id and C<OMP::Info::Obs> object as
being inactive. It does not update the given C<OMP::Info::Obs>
object.

=cut

sub removeComment {
    my $self = shift;
    my $obs = shift;
    my $userid = shift;

    if (! defined($obs) || ! defined($userid)) {
        throw OMP::Error::BadArgs(
            "Must supply both OMP::Info::Obs object and user ID to OMP::DB::Obslog->removeComment");
    }

    $self->_set_inactive($obs, $userid);
}

=item B<queryComments>

Query the observation comment table. Query must be supplied as
an C<OMP::Query::Obslog> object.

    @results = $db->queryComments($query, {allow_dateless => 0});

The query must constrain the date unless C<allow_dateless>
is set.

Returns an array of C<Info::Comment> objects in list context, or
a reference to an array of C<Info::Comment> objects in scalar context.

=cut

sub queryComments {
    my $self = shift;
    my $query = shift;
    my $opts = shift || {};

    my $query_hash = $query->query_hash;

    # Do some rudimentary checks on the query to make sure we're not
    # trying to get every comment from the beginning of time
    if ($opts->{'allow_dateless'}) {
    }
    elsif (defined($query_hash->{date})) {
        my $date;
        if (ref($query_hash->{date}) eq 'ARRAY') {
            $date = $query_hash->{date}->[0];
        }
        else {
            $date = $query_hash->{date};
        }
        if (UNIVERSAL::isa($date, 'OMP::Range')) {
            if ($date->isinverted or ! $date->isbound) {
                throw OMP::Error::BadArgs(
                    "Date range must be closed and consecutive");
            }
        }
    }
    else {
        throw OMP::Error::BadArgs("Must supply either a date or a date range");
    }

    # Send the query off to yet another method.
    my @results = $self->_fetch_comment_info($query);

    # Create an array of Info::Comment objects from the returned
    # hash.
    my @comments = $self->_reorganize_comments(\@results);

    # And return either the array or a reference to the array.
    return (wantarray ? @comments : \@comments);
}

=item B<updateObsComment>

Update an C<OMP::Info::Obs> object by adding its associated comment.

    $db->updateObsComment(\@obs_array);

This method takes one argument, a reference to an array of C<OMP::Info::Obs>
objects. This method will update each C<OMP::Info::Obs> object by
adding its associated comment, if one exists.

This method returns nothing.

=cut

sub updateObsComment {
    my $self = shift;

    my $obs_arrayref = shift;
    # Check to see if we actually have observations before doing this.
    # If we don't, just return the array.
    return @$obs_arrayref if scalar(@$obs_arrayref) < 1;

    # What we're going to do is sort the array by time, then
    # get the start and end dates of the whole shmozzle, then
    # form a query that spans that range. Then when we get
    # all the comments back we can stick them onto the
    # appropriate Obs objects.

    my @obsarray = map {$_->[0]}
        sort {$a->[1] <=> $b->[1]}
        map {[$_, ($_->startobs // $_->endobs)->epoch]}
        @$obs_arrayref;

    my $start;
    my $end;
    if (UNIVERSAL::isa($obsarray[0], "OMP::Info::Obs::TimeGap")) {
        $start = $obsarray[0]->endobs - 1;
    }
    else {
        $start = $obsarray[0]->startobs;
    }
    if (UNIVERSAL::isa($obsarray[-1], "OMP::Info::Obs::TimeGap")) {
        $end = $obsarray[-1]->endobs - 1;
    }
    else {
        $end = $obsarray[-1]->startobs;
    }

    # Print a message in the log.
    OMP::General->log_message(
        "OMP::DB::Obslog: Querying database for observation comments.\n");

    my $query = OMP::Query::Obslog->new(HASH => {
        date => {
            min => $start->ymd . "T" . $start->hms,
            max => $end->ymd . "T" . $end->hms,
        },
        obsactive => {boolean => 1},
    });
    my @commentresults = $self->queryComments($query);

    OMP::General->log_message(
        "OMP::DB::Obslog: Finished query for observation comments.\n");

    my %commhash;

    foreach my $comment (@commentresults) {
        unless (exists($commhash{$comment->obsid})) {
            $commhash{$comment->obsid} = [];
        }
        push @{$commhash{$comment->obsid}}, $comment;
    }

    foreach my $obs (@$obs_arrayref) {
        my $obsid = $obs->obsid;
        unless (defined $obsid
                or not eval {$obs->isa('OMP::Info::Obs::TimeGap')}) {
            # Subtract another second to match how timegaps seem to be stored,
            # and generate placeholder OBSID for matching, using the function
            # used by _reorganize_comments.
            $obsid = _placeholder_obsid(
                $obs->instrument,
                $obs->runnr,
                $obs->endobs - 1);
        }
        if (exists($commhash{$obsid})) {
            $obs->comments($commhash{$obsid});
        }
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

    $results = $db->_fetch_comment_info($query);

In list context returns all matches as a list of hash references.

    @results = $db->_fetch_comment_info($query);

=cut

sub _fetch_comment_info {
    my $self = shift;
    my $query = shift;

    # Generate the SQL statement.
    my $sql = $query->sql($OBSLOGTABLE);

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

=item B<_reorganize_comments>

Given the results from the query (returned as a row per observation)
convert this output to an array of C<Info::Comment> objects.

    @results = $db->_reorganize_comments($query_output);

=cut

sub _reorganize_comments {
    my $self = shift;
    my $rows = shift;

    my @return;

    # Connect to the user database
    my $db = OMP::DB::User->new(DB => $self->db);
    my $users = $db->getUserMultiple([keys %{{
        map {$_->{'commentauthor'} => 1}
        @$rows
    }}]);

    # For each row returned by the query, create an Info::Comment object
    # out of the information contained within.
    for my $row (@$rows) {
        my $date = OMP::DateTools->parse_date($row->{commentdate});
        throw OMP::Error(
            "Unable to parse comment date (" . $row->{commentdate} . ")")
            unless defined $date;

        my $startobs = OMP::DateTools->parse_date($row->{date});
        throw OMP::Error(
            "Unable to parse observation start date (" . $row->{date} . ")")
            unless defined $startobs;

        my $obsid;
        unless (defined($row->{obsid})) {
            $obsid = _placeholder_obsid(
                $row->{instrument},
                $row->{runnr},
                $startobs);
        }
        else {
            $obsid = $row->{obsid};
            $obsid =~ /^(\w+)_(\w+)_(\w+)$/;
            (my $ymd, my $hms) = split 'T', $3;
            my $inst = $1;
            if ($inst =~ /^rx(?!h3)/i && $ymd >= 20060901) {
                $obsid =~ s/^(\w+?)_/acsis_/;
            }
        }

        push @return, OMP::Info::Comment->new(
            text => $row->{commenttext},
            date => $date,
            status => $row->{commentstatus},
            runnr => $row->{runnr},
            instrument => $row->{instrument},
            telescope => $row->{telescope},
            startobs => $startobs,
            obsid => $obsid,
            author => $users->{$row->{'commentauthor'}},
            relevance => $row->{relevance},
        );
    }

    return @return;
}

=item B<_placeholder_obsid>

Create placeholder OBSID for entries which don't have one, such as
time gaps.  This is the function used by _reorganize_comments
to generate these placeholders, so can also be used to generate
values to match with the results of comment queries.

Note: for time gaps, values in the database seem to be stored with
-1 extra second, so it may be necessary to call this function with
the third argument being C<$time_gap-E<gt>endobs - 1>.

=cut

sub _placeholder_obsid {
    my $instrument = shift;
    my $runnr = shift;
    my $ut = shift;

    return join '_', lc($instrument), $runnr, $ut->strftime("%Y%m%dT%H%M%S");
}

=item B<_store_comment>

Store the given C<Info::Comment> object corresponding to the
given C<Info::Obs> object in the observation log database.

    $db->_store_comment($obs, $comment);

This method will store the comment as being active, i.e. the
"obsactive" flag in the table will be set to 1.

=cut

sub _store_comment {
    my $self = shift;
    my $obs = shift;
    my $comment = shift;

    my %data = _extract_data($obs, $comment);

    $self->_db_insert_data(
        $OBSLOGTABLE,
        {
            'COLUMN' => 'commentauthor',
            'QUOTE' => 1,
            'POSN' => 6
        },
        undef,
        @data{qw/runnr instrument telescope obs-date/},
        '1',
        @data{qw/comment-date userid/},
        {
            'COLUMN' => 'commenttext',
            'TEXT' => $data{text},
        },
        @data{qw/status obsid/}
    );
}

sub _extract_data {
    my ($obs, $comment, $as_text) = @_;

    my ($t, %data);

    # For now, store comments the usual way, but include the obsid
    # in the insert (NULL obsid if it's a timegap comment).  Eventually,
    # the instrument and run number will be excluded from the insert.

    if (UNIVERSAL::isa($obs, "OMP::Info::Obs::TimeGap")) {
        if (! defined($obs->instrument)
                || ! defined($obs->endobs)
                || ! defined($obs->runnr)) {
            throw OMP::Error::BadArgs(
                "Must supply instrument, endobs, and runnr properties to store a comment in the database");
        }
        $t = $obs->endobs - 1;
    }
    else {
        if (! defined($obs->instrument)
                || ! defined($obs->startobs)
                || ! defined($obs->runnr)) {
            throw OMP::Error::BadArgs(
                "Must supply instrument, startobs, and runnr properties to store a comment in the database");
        }
        $t = $obs->startobs;
        $data{'obsid'} = $obs->obsid;
    }

    unless (defined($comment)) {
        throw OMP::Error::BadArgs(
            "Must supply comment to store a comment in the database");
    }

    # Check the comment status. Default it to OMP__OBS_GOOD.
    if (defined($comment->status)) {
        $data{'status'} = $comment->status;
    }
    else {
        $data{'status'} = OMP__OBS_GOOD;
    }

    $data{'obs-date'} = $t->strftime("%Y-%m-%d %T");

    my $ct = $comment->date;
    $data{'comment-date'} = $ct->strftime("%Y-%m-%d %T");

    $data{'text'} = $comment->text();
    $data{'userid'} = $comment->author()->userid();

    $data{$_} = $obs->$_() for (qw/runnr instrument telescope/);

    $as_text or return %data;

    my $format = sub {sprintf qq[%11s: %s\n], @_[0, 1]};

    my @order_obs = qw/
        telescope
        instrument
        obs-date
        runnr
    /;

    my $out = join '', map {$format->($_, $data{$_})} @order_obs;
    $out .= "\n";

    my $author_str = join ' ',
        grep {defined $_} map {$comment->author()->$_()} qw/name email/;

    $author_str and $out .= $format->('author', $author_str);

    $out .= $format->($_, $data{$_}) for qw/comment-date text/;

    return $out;
}


=item B<_set_inactive>

Set all observations to inactive, using the given observation as a template.

    $db->_set_inactive($obs, $userid);

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

    my $t;

    # Rudimentary input checking.
    throw OMP::Error::BadArgs("Must supply an Info::Obs object")
        unless (defined $obs);

    throw OMP::Error::BadArgs("Must supply an Info::Obs object")
        unless UNIVERSAL::isa($obs, 'OMP::Info::Obs');

    if (UNIVERSAL::isa($obs, "OMP::Info::Obs::TimeGap")) {
        throw OMP::Error::BadArgs(
            "Must supply instrument, date, and run number")
            unless defined $obs->instrument
            && defined $obs->endobs
            && defined $obs->runnr;

        $t = $obs->endobs - 1;
    }
    else {
        throw OMP::Error::BadArgs(
            "Must supply instrument, date, and run number")
            unless defined $obs->instrument
            && defined $obs->startobs
            && defined $obs->runnr;

        $t = $obs->startobs;
    }

    throw OMP::Error::BadArgs("Must supply a user id")
        unless defined $userid;

    my $instrument = $obs->instrument;
    my $runnr = $obs->runnr;

    my $date = $t->strftime("%Y-%m-%d %T");

    # Form the WHERE clause.
    my $where = "date = '$date' AND instrument = '$instrument' AND runnr = $runnr AND commentauthor = '$userid'";

    # Set up the %new hash (hash of things to be updated)
    my %new = (obsactive => 0);

    # And do the update.
    $self->_db_update_data($OBSLOGTABLE, \%new, $where);
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
