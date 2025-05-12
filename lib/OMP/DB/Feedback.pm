package OMP::DB::Feedback;

=head1 NAME

OMP::DB::Feedback - Manipulate the feedback database

=head1 SYNOPSIS

    $db = OMP::DB::Feedback->new(
        ProjectID => $projectid,
        DB => $dbconnection);

    $db->addComment($comment);
    $db->getComments(\@status);
    $db->alterStatus($commentid, $status);

=head1 DESCRIPTION

This class manipulates information in the feedback table.  It is the
only interface to the database tables. The table should not be
accessed directly to avoid loss of data integrity.

=cut

use 5.006;
use strict;
use warnings;
use Carp;
use OMP::DateTools;
use Time::Piece;
our $VERSION = '2.000';

use OMP::Display;
use OMP::Query::Feedback;
use OMP::Info::Comment;
use OMP::Project;
use OMP::DB::Project;
use OMP::User;
use OMP::DB::User;
use OMP::Constants;
use OMP::Error;
use OMP::Config;

use base qw/OMP::DB/;

# This is picked up by OMP::DB::MSB
our $FBTABLE = 'ompfeedback';

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

Create a new instance of an C<OMP::DB::Feedback> object.

    $db = OMP::DB::Feedback->new(
        ProjectID => $project,
        DB => $connection);

If supplied, the database connection object must be of type
C<OMP::DB::Backend>.  It is not accepted if that is not the case.
(but no error is raised - this is probably a bug).

=cut

# Use base class constructor

=back

=head2 General Methods

=over 4

=item B<getComments>

Returns an array of C<OMP::Info::Comment> objects containing feedback. If
arguments are given they should be in the form of a hash whos keys are
any of the following:

=over 4

=item B<status>

An array reference containing status types for
the desired comments.  Status types are defined
in C<OMP::Constants>.  Example: OMP__FB_INFO.
Provide undef value for status in order for
this criteria to be ignored.

=item B<order>

Either 'descending' or 'ascending'.

=item B<msgtype>

An array reference containing message types for
the desired comments.  Message types are defined
in C<OMP::Constants>.  Example:
OMP__FB_MSG_COMMENT.  By default this criteria is
ignored.

=item B<date>

Date of message.

=back

Defaults to returning comments with a status of B<OMP__FB_IMPORTANT>
or B<OMP__FB_INFO>, and sorts the comments in ascending order.
Results are returned as a reference to a hash of hashes if there might
be comments for more than one project, otherwise results are returned
as a reference to an array.

    @status = qw/OMP__FB_IMPORTANT OMP__FB_INFO/;
    $comm = $db->getComments(
        status => \@status,
        order => 'descending',
        msgtype => OMP__FB_MSG_COMMENT);

=cut

sub getComments {
    my $self = shift;

    my %defaults = (
        status => [OMP__FB_IMPORTANT, OMP__FB_INFO,],
        msgtype => undef,
        order => 'ascending',
        date => undef,
    );

    my %args = (%defaults, @_);

    # Form status and msgtype portions of query
    my %hash = ();
    for my $part (qw/status msgtype/) {
        $hash{$part} = $args{$part} if defined $args{$part};
    }

    $hash{'projectid'} = $self->projectid if $self->projectid;

    if (defined $args{'date'}) {
        $hash{'date'} = {delta => 1, value => $args{'date'}};
    }

    # Create the query object
    my $query = OMP::Query::Feedback->new(HASH => \%hash);

    # Get the comments
    my $comments = $self->_fetch_comments($query);

    my $sort = $args{'order'} eq 'ascending'
        ? sub {$a->id <=> $b->id}
        : sub {$b->id <=> $a->id};

    # Group by project ID if we might have comments for multiple projects
    unless ($self->projectid) {
        my %project;
        push @{$project{$_->projectid}}, $_ for sort $sort @$comments;
        $comments = \%project;
    }
    else {
        # Just order comments by comment ID if only returning results for a single project
        $comments = [sort $sort @$comments];
    }

    return $comments;
}

=item B<addComment>

Adds a comment to the database.  Takes a hash reference containing the
comment and all of its details.  This method also mails the comment
depending on its status.

    $db->addComment($comment);

=over 4

=item Hash reference should contain the following key/value pairs:

=item B<author>

The comment author provided as an object of class C<OMP::User>

=item B<subject>

The subject of the comment.

=item B<program>

The program used to submit the comment.

=item B<sourceinfo>

The IP address of the machine comment is being submitted from.

=item B<text>

The text of the comment.

=item B<preformatted>

Whether the text is pre-formatted?

=item B<status>

The status of the comment (see OMP::Constants for available statuses).  Defaults
to B<OMP__FB_IMPORTANT>.

=item B<msgtype>

The type of message the comment containts (see OMP::Constants for available types).
Defaults to B<OMP__FB_MSG_COMMENT>.

=back

=cut

sub addComment {
    my $self = shift;
    my $comment = shift;

    throw OMP::Error::BadArgs("Comment was not a hash reference")
        unless UNIVERSAL::isa($comment, "HASH");

    my $t = gmtime;
    my %defaults = (
        subject => 'none',
        date => $t->strftime("%Y-%m-%d %T"),
        program => 'unspecified',
        sourceinfo => 'unspecified',
        status => OMP__FB_IMPORTANT,
        msgtype => OMP__FB_MSG_COMMENT,
        preformatted => 0,
    );

    # Override defaults
    $comment = {%defaults, %$comment};

    # Check for required fields
    for (qw/text/) {
        throw OMP::Error::BadArgs("$_ must be specified")
            unless $comment->{$_};
    }

    # Prepare text for storage and subsequent display
    $comment->{text} = OMP::Display->remove_cr($comment->{text});

    # Must have sourceinfo if we don't have an author
    #  if (! $comment->{author} and ! $comment->{sourceinfo}) {
    #    throw OMP::Error::BadArgs("Sourceinfo must be specified if author is not given");
    #  }

    # Make sure author is an OMP::User object
    if (defined $comment->{author}) {
        throw OMP::Error::BadArgs(
            "Author must be supplied as an OMP::User object")
            unless UNIVERSAL::isa($comment->{author}, "OMP::User");
    }

    # Check that the project actually exists
    my $projdb = OMP::DB::Project->new(
        ProjectID => $self->projectid,
        DB => $self->db,
    );

    $projdb->verifyProject()
        or throw OMP::Error::UnknownProject("Project " . $self->projectid . " not known.");

    # We need to think carefully about transaction management

    # Begin transaction
    $self->_db_begin_trans;
    $self->_dblock;

    # Store comment in the database
    $self->_store_comment($comment);

    # End transaction
    $self->_dbunlock;
    $self->_db_commit_trans;

    # Mail the comment to interested parties
    ($comment->{status} == OMP__FB_IMPORTANT)
        and $self->_mail_comment_important($self->projectid, $comment);

    ($comment->{status} == OMP__FB_INFO)
        and $self->_mail_comment_info($self->projectid, $comment);

    ($comment->{status} == OMP__FB_SUPPORT)
        and $self->_mail_comment_support($self->projectid, $comment);

    return;
}

=item B<alterStatus>

Alters the status of a comment.

    $db->alterStatus($commentid, $status);

Last argument should be a feedback constant as defined in C<OMP::Constants>.

=cut

sub alterStatus {
    my $self = shift;
    my $commentid = shift;
    my $status = shift;

    # Begin trans
    $self->_db_begin_trans;
    $self->_dblock;

    # Alter comment status
    $self->_alter_status($commentid, $status);

    # End trans
    $self->_dbunlock;
    $self->_db_commit_trans;
}

=back

=head2 Internal Methods

=over 4

=item B<_store_comment>

Stores a comment in the database.

    $db->_store_comment($comment);

=cut

sub _store_comment {
    my $self = shift;
    my $comment = shift;

    my $projectid = $self->projectid;

    # Create the comment entry number [SQL prefers single quotes]
    my $clause = "projectid = '$projectid'";
    my $entrynum = $self->_db_findmax($FBTABLE, "entrynum", $clause);

    (defined $entrynum) and $entrynum ++
        or $entrynum = 1;

    # Store the data
    $self->_db_insert_data(
        $FBTABLE,
        {
            COLUMN => 'projectid',
            QUOTE => 1,
            POSN => 0
        },
        undef,
        $projectid,
        (defined $comment->{author}
            ? $comment->{author}->userid
            : undef),
        @$comment{
            'date',
            'subject',
            'program',
            'sourceinfo',
            'status',
        },
        {
            TEXT => $comment->{text},
            COLUMN => 'text',
        },
        $comment->{msgtype},
        $entrynum,
        ($comment->{'preformatted'} ? 1 : 0),
    );
}

=item B<_mail_comment>

Mail the comment to the specified users.

    $db->_mail_comment(
        comment => $comment,
        to => \@to,
        cc => \@cc,
        bcc => \@bcc,
    );

Arguments should be provided in the form of a hash with the following keys:

=over 4

=item comment

A hash reference containing comment details.

=item to

Array reference containing C<OMP::User> objects.

=item cc

Array reference containing C<OMP::User> objects.

=item bcc

Array reference containing C<OMP::User> objects.

=back

=cut

sub _mail_comment {
    my $self = shift;
    my %args = @_;

    my $comment = $args{'comment'};

    my $projectid = $self->projectid;

    # Put projectid in subject header if it isn't already there
    my $subject = ($comment->{'subject'} !~ /\[$projectid\]/i)
        ? (sprintf '[%s] %s', $projectid, $comment->{'subject'})
        : $comment->{'subject'};

    my $from = defined $comment->{'author'}
        ? $comment->{'author'}
        : OMP::User->get_flex();

    # Setup message details
    my %details = (
        message => $comment->{'text'},
        preformatted => (!! $comment->{'preformatted'}),
        to => $args{to},
        from => $from,
        bcc => $args{bcc},
        subject => $subject,
    );

    if ($args{cc}) {
        $details{cc} = $args{cc};
    }

    $self->_mail_information(%details);
}

=item B<_mail_comment_important>

Will send the email to PI, COI and support emails.

    $db->_mail_comment_important($projectid, $comment);

=cut

sub _mail_comment_important {
    my $self = shift;
    my $projectid = shift;
    my $comment = shift;

    my $projdb = OMP::DB::Project->new(
        ProjectID => $projectid,
        DB => $self->db);

    my $proj = $projdb->_get_project_row;

    my @to = $proj->contacts;

    my @cc;
    if (defined $comment->{author}) {
        push(@cc, $comment->{author});
    }

    # Bcc the OMP contact person(s)
    my @ompcontacts = OMP::Config->getData('omp-bcc');
    my @bcc;
    for (@ompcontacts) {
        my $user = OMP::User->new(email => $_);
        push(@bcc, $user);
    }

    $self->_mail_comment(
        comment => $comment,
        to => \@to,
        cc => \@cc,
        bcc => \@bcc,
    );
}

=item B<_mail_comment_support>

Send the email to support only.

    $db->_mail_comment_support($projectid, $comment);

=cut

sub _mail_comment_support {
    my $self = shift;
    my $projectid = shift;
    my $comment = shift;

    my $projdb = OMP::DB::Project->new(
        ProjectID => $projectid,
        DB => $self->db);

    my $project = $projdb->_get_project_row;

    my @to = $project->support;

    # Only mail if there is a support address
    $self->_mail_comment(comment => $comment, to => \@to)
        if ($to[0]);
}

=item B<_mail_comment_info>

Will send the message to PI only.

    $db->_mail_comment_info($projectid, $comment);

=cut

sub _mail_comment_info {
    my $self = shift;
    my $projectid = shift;
    my $comment = shift;

    # Get a OMP::DB::Project object so we can get info from the database
    my $projdb = OMP::DB::Project->new(
        ProjectID => $projectid,
        DB => $self->db);

    # This is an internal method that removes password
    # verification. Since comments are not meant to need password
    # to be added we can not use $projdb->projectDetails [unless
    # we specfy the administrator password here]
    my $proj = $projdb->_get_project_row;

    my @to = ($proj->pi);

    $self->_mail_comment(comment => $comment, to => \@to);
}

=item B<_fetch_comments>

Internal method to retrieve the comments from the database.

The hash argument controls the sort order of the results and the
status of comments to be retrieved.

Only argument is a query represented in the form of an C<OMP::Query::Feedback>
object.

    $db->_fetch_comments($query);

Returns either a reference or a list depending on the calling context.

=cut

sub _fetch_comments {
    my $self = shift;
    my $query = shift;

    # Generate the SQL query
    my $sql = $query->sql($FBTABLE);

    # Run the query
    my $ref = $self->_db_retrieve_data_ashash($sql);

    my $udb = OMP::DB::User->new(DB => $self->db);
    my $users = $udb->getUserMultiple([keys %{{map {
        my $user = $_->{'author'};
        (defined $user)
            ? ($user => 1)
            : ();
    } @$ref}}]);

    my @comments;

    # Replace comment user IDs with OMP::User objects and
    # dates with Time::Piece objects
    for (@$ref) {
        my $id = delete $_->{'commid'};
        my $type = delete $_->{'msgtype'};

        my $user = delete $_->{'author'};
        $user = $users->{$user}
            if defined $user;

        my $date = OMP::DateTools->parse_date(delete $_->{'date'});

        push @comments, OMP::Info::Comment->new(
            id => $id,
            type => $type,
            author => $user,
            date => $date,
            %$_,
        );
    }

    if (wantarray) {
        return @comments;
    }
    else {
        return \@comments;
    }
}

=item B<_alter_status>

Update the status field of an entry.

    _alter_status($commentid, $status);

=cut

sub _alter_status {
    my $self = shift;
    my $commid = shift;
    my $status = shift;

    $self->_db_update_data(
        $FBTABLE, {
            status => $status,
        },
        " commid = $commid ");
}

1;

__END__

=back

=head1 SEE ALSO

This class inherits from C<OMP::DB>.

For related classes see C<OMP::DB::MSB> and C<OMP::DB::Project>.

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research
Council.  All Rights Reserved.

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

=head1 AUTHORS

Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>
Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=cut
