package OMP::DB::MSB;

=head1 NAME

OMP::DB::MSB - A database of MSBs

=head1 SYNOPSIS

    $db = OMP::DB::MSB->new(
        ProjectID => $sp->projectID,
        DB => $connection);

    $sp = OMP::SciProg->new(XML => $xml);
    $status = $db->storeSciProg(SciProg => $sp);

    $msb = $db->fetchMSB(
        msbid => $id,
        checksum => $checksum);

    $sp = $db->fetchSciProg();

    @match = $db->queryMSB($query_object);

=head1 DESCRIPTION

This class is responsible for storing and retrieving science
programs and MSBs to and from the database. Database is loosely
defined in this context.

=cut

use 5.006;
use strict;
use warnings;
use Carp;

# OMP dependencies
use OMP::Config;
use OMP::SciProg;
use OMP::MSB;
use OMP::Error qw/:try/;
use OMP::DateTools;
use OMP::NetTools;
use OMP::General;
use OMP::DB::Feedback;
use OMP::DB::Project;
use OMP::DB::ProjAffiliation;
use OMP::Constants qw/:done :fb :logging/;
use OMP::SiteQuality;
use OMP::Range;
use OMP::Info::MSB;
use OMP::Info::Obs;
use OMP::Info::Comment;
use OMP::Info::SciProg;
use OMP::Project::TimeAcct;
use OMP::DB::TimeAcct;
use OMP::DB::MSBDone;
use OMP::DB::User;
use OMP::Query::MSB;
use OMP::DB::TLE;
use OMP::User;

use Time::Piece qw/:override/;
use Time::Seconds;
use Time::HiRes qw/gettimeofday tv_interval/;

use Astro::Telescope;
use Astro::Coords;
use Astro::Coords::Angle;
use Astro::Coords::TLE;
use Astro::PAL;
use Data::Dumper;
use Number::Interval;

use POSIX qw/log10/;

# Use this for the reliable file opening
use File::Spec;
use Fcntl;
use Errno; # else $!{EEXIST} does not work

use base qw/OMP::DB/;

our $VERSION = '2.000';

# Name of the table containing the MSB data
our $SCITABLE = 'ompsciprog';

# Default number of results to return from a query
our $DEFAULT_RESULT_COUNT = 10;

# Debug messages
our $DEBUG = 0;

# The maximum HA used for calculating the scheduling priority
use constant HAMAX => 4.5;

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

Create a new instance of an C<OMP::DB::MSB> object.

    $db = OMP::DB::MSB->new(
        ProjectID => $project,
        DB => $connection);

The project argument is required for Science Program
access.

If supplied, the database connection object must be of type
C<OMP::DB::Backend>.  It is not accepted if that is not the case.
(but no error is raised - this is probably a bug).

=cut

# Use base class version

=back

=head2 Accessor Methods

=over 4

=item B<projectid>

The project ID associated with this object.

    $pid = $db->projectid;
    $db->projectid("M01BU53");

All project IDs are upper-cased automatically.

=cut

# inherit from base class

=back

=head2 General Methods

=over 4

=item B<storeSciProg>

Store a science program object into the database.

    $status = $db->storeSciProg(SciProg => $sp);

Requires a project identifier. If the FreezeTimeStamp
key is present and set to true timestamp checking is disabled and
the timestamp is not updated when writing XML to disk. This is to
allows the science program to be modified internally without affecting
the external checking but can be dangerous if used without thought
since it will most likely lead to confusion, either because the
PI re-uploads without realising that the program has been modified,
or because the back up system looks at the timestamp to determine whether
to backup the file. Timestamps should be modified when re-uploading
after a MSB accept for this reason. FreezeTimeStamp implies NoFeedback
and NoCache (unless set explicitly).

    $status = $db->storeSciProg(
        SciProg => $sp,
        FreezeTimeStamp => 1,
        NoFeedback => 1,
        NoCache => 1,
        NoConstraintCheck => 0);

The NoFeedback key can be used to disable the writing of an
entry to the feedback table on store. This is useful when an MSB
is being accepted since the MSB acceptance will itself lead
to a feedback entry.

The NoCache switch, if true, can be used to prevent the system
from attempting to write a backup of the submitted science program
to disk. This is important for MSB acceptance etc, since the
purpose for the cache is to track a limited number of PI submissions,
not to track MSB accepts.

The C<Force> key can be used for force the saving of the program
to the database even if the timestamps do not match. This option
should be used with care. Default is false (no force).

The scheduling fields (eg tau and seeing) must be populated.

If the C<NoConstraintCheck> parameter is given then the constraint checking
step (a call to _verify_project_constraints) is omitted.  This should only
be done when updating the science program automatically, such as when
marking an MSB as done, in order to stop this failing unnecessarily.
(See e.g. fault 20140801.005 where automated updating of the scheduling
constraint caused it to fail the check.)  Failure to mark MSBs as done
is a serious problem which has caused time loss because the MSB is then
re-observed when it should not have been (see the above fault and also
20131213.003) and so a blanket exception from the constraint checks is
not unreasonable in this case.

Suspend flags are not touched since now the Observing Tool
has the ability to un-suspend.

Returns true on success and C<undef> on error (this may be
modified to raise an exception). In list context returns
any warning messages associated with sanity checks.

    @warnings = $db->storeSciProg(SciProg => $sp);

=cut

sub storeSciProg {
    my $self = shift;

    # Get the arguments
    my %args = @_;

    # Make sure the project actually exists
    # (in some cases the password will be verified even if the project
    # does not exist)
    $self->_verify_project_exists;

    # Check them
    return undef unless exists $args{SciProg};
    return undef unless UNIVERSAL::isa($args{SciProg}, "OMP::SciProg");

    # Verify constraints since it is much better to tell people on submission
    # than to spend hours debugging query problems.  Do not perform this check
    # if the "NoConstraintCheck" option is given.
    my @cons_warnings = $args{'NoConstraintCheck'}
        ? ()
        : $self->_verify_project_constraints($args{SciProg});

    # Implied states
    $args{NoCache} = 1
        if (! exists $args{NoCache} && $args{FreezeTimeStamp});

    $args{NoFeedback} = 1
        if (! exists $args{NoFeedback} && $args{FreezeTimeStamp});

    # Before we do anything else we connect to the database
    # begin a transaction and lock out the tables.
    # This has the side effect of locking out the tables until
    # we have finished with them (else it will block waiting for
    # access). This allows us to use the DB lock to control when we
    # can write a science program to disk)
    $self->_db_begin_trans;
    $self->_dblock;

    # Write the Science Program to disk
    $self->_store_sci_prog(
        $args{SciProg},
        $args{FreezeTimeStamp},
        $args{Force},
        $args{NoCache},
        ((exists $args{'User'}) ? $args{'User'} : undef))
        or throw OMP::Error::SpStoreFail(
        "Error storing science program into database\n");

    # Get the summaries for each msb as a hash containing observations
    # as arrays of hashes
    my @rows = map {
        my $info = $_->info({check_select_zero_or_folder => 1});

        # Check that tau and seeing are there
        throw OMP::Error::SpBadStructure(
            "No scheduling information in science program. Did you forget to put in a Site Quality component?\n")
            if (! $info->tau() or ! $info->seeing());

        # Return the reference to the array
        $info;
    } $args{SciProg}->msb;

    # Insert the summaries into rows of the database
    $self->_insert_rows(@rows);

    # And file with feedback system unless told otherwise
    unless ($args{NoFeedback}) {
        # Add a little note indicating the user name if given.
        my $note = (exists $args{'User'})
            ? ('[by user ' . $args{'User'}->userid . ']')
            : '';

        $self->_notify_feedback_system(
            subject => "Science program submitted",
            text => "<p>Science program submitted for project <b>"
                . $self->projectid
                . "</b> $note\n</p>",
            preformatted => 1,
            status => OMP__FB_HIDDEN,
            msgtype => OMP__FB_MSG_SP_SUBMITTED,
        );
    }

    # Now disconnect from the database and free the lock
    $self->_dbunlock;
    $self->_db_commit_trans;

    return (wantarray() ? @cons_warnings : 1);
}

=item B<fetchSciProg>

Retrieve a science program from the database.

    $sp = $db->fetchSciProg([$internal[, %opt]])

It is returned as an C<OMP::SciProg> object.
It is assumed that the DB object has already been instantiated
with the relevant project ID.

Note that no file or database locking is involved. This method simply
reads the file that is there and returns it. If it so happens that the
file is about to be updated then there is nothing that can be done to
prevent this. The routine that stores the science program guarantees
to do it in such a way that it will be impossible for a partial
science program to be retrieved (as would happen if the file is read
just as the file is being written).

The optional argument can be used to disable feedback notification (ie if it
is being called from an internal method) if true.

Additional options:

=over 4

=item raw

Return raw science program XML (without constructing
an OMP::SciProg object.

=item user

An OMP::User representing the person making this request.

=back

=cut

sub fetchSciProg {
    my $self = shift;
    my $internal = shift;
    my %opt = @_;

    my $sp = $self->_really_fetch_sciprog(raw => $opt{'raw'});

    my $note = (exists $opt{'user'})
        ? ('[by user ' . $opt{'user'}->userid . ']')
        : undef;

    $self->_clear_counter_add_feedback_post_fetch($sp, $note)
        unless $internal
        or $opt{'raw'};

    return $sp;
}

=item B<removeSciProg>

Remove the science program from the database.

    $db->removeSciProg();

Hopefully this is intentional.

=cut

sub removeSciProg {
    my $self = shift;

    # Before we do anything else we connect to the database
    # begin a transaction and lock out the tables.
    # This has the side effect of locking out the tables until
    # we have finished with them (else it will block waiting for
    # access). This allows us to use the DB lock to control when we
    # can write a science program to disk)
    $self->_db_begin_trans;
    $self->_dblock;

    # Remove the science program
    $self->_remove_old_sciprog();

    # Remove the observation and MSB entries
    $self->_clear_old_rows();

    $self->_notify_feedback_system(
        subject => "Science program deleted",
        text => "<p>Science program for project <b>"
            . $self->projectid
            . "</b> deleted</p>",
        preformatted => 1,
        msgtype => OMP__FB_MSG_SP_DELETED,
    );

    OMP::General->log_message(
        "Science program deleted for project " . $self->projectid());

    # Now disconnect from the database and free the lock
    $self->_dbunlock;
    $self->_db_commit_trans;
}

=item B<getInstruments>

Returns a list of all the instruments currently associated with each
science program.

    \%instruments = $db->getInstruments(@projectids);

=cut

sub getInstruments {
    my $self = shift;
    my @projectids = @_;

    return {} unless @projectids;

    # This needs to be quick. The old way was to simply get the science program
    # and summarise it. Way to slow with the large science programs used in surveys.
    # Simply go straight to the ompobs table.

    # No XML query interface to science programs, so we'll have to do an SQL query
    my $sql = 'SELECT projectid, '
        . 'GROUP_CONCAT(DISTINCT instrument ORDER BY instrument SEPARATOR ",") AS instruments '
        . "FROM $OMP::DB::Project::OBSTABLE WHERE projectid IN ("
        . (join ',', ('?',) x scalar @projectids)
        . ') GROUP BY projectid';

    my $ref = $self->_db_retrieve_data_ashash($sql, @projectids);

    my %results = map {
        $_->{'projectid'} => [split /,/, $_->{'instruments'}]
    } @$ref;

    return \%results;
}

=item B<getSciProgInfo>

Retrieves summary information (an C<OMP::Info::SciProg> object) about a
science program.  This is based on information in OMP database tables
such as C<ompmsb>.  It can be used when some information about the program
is required, but not the full (XML) program itself -- in that case,
the C<fetchSciProg> method should be used instead.

    my $info = $db->getSciProgInfo();

=cut

sub getSciProgInfo {
    my $self = shift;
    my %opt = @_;

    my $projectid = $self->projectid();

    my @msbs = $self->_fetch_row(
        projectid => $projectid,
        with_observations => $opt{'with_observations'}
    );

    return OMP::Info::SciProg->new(
        projectid => $projectid,
        msb => \@msbs,
        timestamp => $self->_get_old_sciprog_timestamp,
    );
}

=item B<getSciProgInfoMultiple>

Retrieves summary information (as C<getSciProgInfo>) for multiple projects,
returning a hash (reference) by project ID.  Assumes that neither observations
nor timestamps are required.

    my $projects = $db->getSciProgInfoMultiple(\@projectids);

=cut

sub getSciProgInfoMultiple {
    my $self = shift;
    my $projects = shift;

    return {} unless scalar @$projects;

    my $sql = sprintf 'SELECT * FROM %s WHERE projectid IN (%s)',
        $OMP::DB::Project::MSBTABLE,
        (join ', ', ('?') x scalar @$projects);

    my $ref = $self->_db_retrieve_data_ashash($sql, @$projects);

    my %result = ();
    foreach my $msb ($self->_msb_row_to_msb_object(@$ref)) {
        push @{$result{$msb->projectid}}, $msb;
    }

    return {
        map {
            $_ => OMP::Info::SciProg->new(
                projectid => $_,
                msb => $result{$_})
        } keys %result};
}

=item B<fetchMSB>

Retrieve an MSB (in the form of an OMP::MSB object) from the database.
The MSB can be identified either explicitly by specifying the index
(msbid) from the table, by specifying the index (msbid) with a
verification checksum or by specifying just the checksum.  If a
checksum and msbid are provided the a check is made on the database
table before even attempting to load the science program.  This allows
some flexibility in retrieving the MSB.

In all cases the project ID is verified (as stored in the object) as a
sanity check if it is present. Once the checksum is determined (either
from the table or supplied by the user) the Science Program is scanned
until the relevant MSB can be located.

Note that the checksum is guaranteed to be unique (partly because
it is used to determine MSBs that are identical when the Science
Program is stored in the DB) so long as the project ID is available.

If the project ID is not available from the object then queries
using just the checksum can not be guaranteed (although statistics
are in your favour).

The OMP will probably always use the index and checksum approach for
remote retrieval since, assuming an MSB has a unique index, this
allows for us to determine when a science program has been resubmitted
since we obtained the information. This is important since we want to
make sure that our query is still valid.

The checksum approach allows us to always retrieve the same MSB
regardless of whether the science program has been resubmitted since
we last looked (this is used when marking an MSB as done).

Just use the index:

    $msb = $db->fetchMSB(msbid => $index);

Use the index and checksum (both are used for the DB query):

    $msb = $db->fetchMSB(msbid => $index, checksum => $checksum);

Use the checksum and the project id (available from the object):

    $msb = $db->fetchMSB(checksum => $checksum);

It is an error for multiple MSBs to match the supplied criteria.

An exception is raised (C<MSBMissing>) if the MSB can not be located.
This may indicate that the science program has been resubmitted or
the checksum was invalid [there is no distinction].

Fetching an MSB does not involve database locking because
an internal consistency check is provided since we compare
checksum (supplied or from the databse) with that in the file.
If the checksum matches in the database but fails to match
in the science program (because it was updated between doing
the query and reading from the science program) then we will still
catch an inconsitency.

Option options:

=over 4

=item internal

Do not log the retrieval in the MSB done table.

=back

=cut

sub fetchMSB {
    my $self = shift;
    my %args = @_;

    my $internal = delete $args{'internal'};

    # The important result is the checksum
    my $checksum;

    # If we are querying the database by MSB ID...
    my $usingmsbid;
    if (exists $args{msbid} && defined $args{msbid}) {
        # Call method to do search on database. This assumes that we
        # can map projectid, checksum and id to valid column names
        # Returns a hash with the row entries
        my %details = $self->_fetch_row(%args);

        # We could not find anything
        throw OMP::Error::MSBMissing(
            "Could not locate requested MSB in database. Maybe you need to resubmit the query?")
            unless %details;

        # Get the checksum
        $checksum = $details{checksum};

        # And the project ID
        $self->projectid($details{projectid});

        # indicate that we used an MSBID
        $usingmsbid = 1;
    }
    elsif (exists $args{checksum}) {
        $checksum = $args{checksum};
    }
    else {
        throw OMP::Error::BadArgs(
            "No checksum or MSBid provided. Unable to retrieve MSB.");
    }

    # Retrieve the relevant science program
    my $sp = $self->fetchSciProg(1);

    # Get the MSB
    my $msb = $sp->fetchMSB($checksum);

    # if we did not get an MSB back this means the checksums
    # are now different to what was stored in the database
    # if the checksum was requested we provide a different error to
    # that triggered if we got an msbid
    unless ($msb) {
        if ($usingmsbid) {
            # used an MSBID
            eval {
                my $checksums = join "\n", map {$_->checksum()} $sp->msb();
                my $projectid = $self->projectid();
                OMP::General->log_message(
                    "Checksum $checksum (for MSB ID $args{msbid}) from DB not found in SP (for project $projectid) which has checksums:\n$checksums");
            };
            throw OMP::Error::FatalError(
                "A checksum was obtained from the database table but there was no corresponding MSB in the science program. This likely means that the checksum calculation has been changed/broken since the Science Program was submitted");
        }
        else {
            # user supplied checksum
            throw OMP::Error::MSBMissing(
                "Unable to retrieve MSB in science program - the required checksum does not match any current MSBs.");
        }
    }

    # Check for "auto" coordinates which must be filled in before the MSB is
    # sent for translation.
    $msb->processAutoCoords(DB => $self->db());

    # To aid with the translation to a sequence we now
    # have to add checksum and projectid as explicit elements
    # in each SpObs in the MSB (since each SpObs is translated
    # independently). We use "msbid" and "project" as tag names
    # since they match the FITS headers.

    # We also need to obtain the project constraints
    my %pconst;
    my $projdb = OMP::DB::Project->new(
        DB => $self->db,
        ProjectID => $sp->projectID,
    );
    my $pobj = $projdb->projectDetails();

    $msb->addFITStoObs($pobj);

    # Update the msb done table to indicate that we have retrieved an
    # MSB.  This is needed so that the done table includes all MSBs that
    # have been retrieved such that the information can be associated
    # with done flags and comments even if the MSB is removed from the
    # science program during the observation. This requires a transaction.
    # Connect to the DB (and lock it out)
    $self->_notify_msb_done(
        $checksum,
        $sp->projectID,
        $msb,
        "MSB retrieved from DB",
        OMP__DONE_FETCH)
        unless $internal;

    return $msb;
}

=item B<queryMSB>

Query the database for the MSBs that match the supplied query.

    @results = $db->queryMSB($query);

The query is represented by an C<OMP::Query::MSB> object.  The result is
returned as an array of C<OMP::Info::MSB> objects.

The results are actually summaries of the table entries rather than
direct summaries of MSBs. It is assumed that the table contains
all the necessary information from the MSB itself so that there is
no need to open each science program to obtain more information.

=cut

sub queryMSB {
    my $self = shift;
    my $query = shift;

    # Run the query and obtain an array of hashes in order up to
    # the maximum number
    my @results = $self->_run_query($query);

    return @results;
}

=item B<doneMSB>

Mark the specified MSB as having been observed.

    $db->doneMSB($checksum);

Optionally takes a second argument, a C<OMP::Info::Comment> object
containing an override comment, transaction ID and associated user.

    $db->doneMSB($checksum, $comment);

The MSB is located using the Project identifier (stored in the object)
and the checksum.  If an MSB can not be located it is likely that the
science program has been reorganized.

This method locks the database since we are modifying the database
tables. We do not want to retrieve a science program, modify it and
store it again if someone has modified the science program between us
retrieving and storing it.

The time remaining on the project is decremented by the estimated
time taken to observe the MSB (via OMP::DB::TimeAcct).

Invokes the C<hasBeenObserved> method on the MSB object.

Configuration arguments can be supplied via a reference to a hash
as the last argument.

The only configuration options are:

    adjusttime => 1/0

    nodecrement => 1/0

    notify_first_accept => 1/0

Default is to adjust the time accounting when accepting an MSB. If this
argument is false the time pending will not be incremented.

    $db->doneMSB($checksum, {adjusttime => 0});
    $db->doneMSB($checksum, $comment, {adjusttime => 1, shifttype => "NIGHT"});

If set to a true value, the "nodecrement" option supresses alteration
of the science program to decrement the MSB's "remaining" counter.

The notify_first_accept controls whether an IMPORTANT level email will
be sent to flex for the first msb accepted for a specific project that
occurs on a given (ut) night. It defaults to 0

=cut

sub doneMSB {
    my $self = shift;
    my $checksum = shift;

    # If last arg is a hash read it off
    my %optargs = (
        adjusttime => 1,
        nodecrement => 0,
        shifttype => "UNKNOWN",
        msbtitle => "UNKNOWN",
        notify_first_accept => 0,
    );

    if (ref($_[-1]) eq 'HASH') {
        # Remove last element from @_
        my $newopt = pop(@_);
        %optargs = (%optargs, %$newopt);
    }

    # Now read the comment assuming any args remain
    my $comment = shift;

    OMP::General->log_message(
        "Attempting to mark MSB for project " . $self->projectid . " as done [$checksum]");

    # Connect to the DB (and lock it out)
    $self->_db_begin_trans;
    $self->_dblock;

    # Work out the reason and user
    my $author;
    my $reason = "MSB marked as done";
    if (defined $comment) {
        $author = $comment->author;  # for logging
        my $text = $comment->text;
        if (defined $text && $text =~ /\w/) {
            # prepend a descriptive comment to current text
            $reason .= ": " . $text;
        }
        $comment->text($reason);
    }
    else {
        $comment = OMP::Info::Comment->new(text => $reason);
    }

    # Force status
    $comment->status(OMP__DONE_DONE);

    my $sp;
    my $result = $self->_apply_msb_operation($checksum, $comment, sub {
            my $msb = shift;

            OMP::General->log_message("Marked MSB as done in the done table");

            # Mark it as observed
            $msb->hasBeenObserved();

            OMP::General->log_message(
                "MSB marked as done in science program object");

            return [$msb->estimated_time];
        },
        sp_reference => \$sp,
        no_store => $optargs{'nodecrement'});

    if (defined $result) {
        my ($estimated_time) = @$result;

        unless ($optargs{'nodecrement'}) {
            OMP::General->log_message("Science program stored back to database");
        }

        # Now decrement the time for the project if required
        if ($optargs{adjusttime}) {
            my $shifttype = $optargs{shifttype};
            my $acctdb = OMP::DB::TimeAcct->new(
                ProjectID => $sp->projectID,
                DB => $self->db);

            # need TimeAcct object
            my $acct = OMP::Project::TimeAcct->new(
                projectid => $sp->projectID,
                confirmed => 0,
                date => scalar(gmtime()),
                timespent => $estimated_time,
                shifttype => $shifttype,
            );

            $acctdb->incPending($acct);
            OMP::General->log_message("Incremented time on project");
        }
    }

    # Might want to send a message to the feedback system at this
    # point
    $reason = '';
    if (defined $comment) {
        $reason = ": " . $comment->text
            if defined $comment->text && $comment->text =~ /\w/;
    }

    my $msbtitle = $optargs{msbtitle};
    my $telescope = $sp->telescope;

    # if notify_first_accept is 1, then we need to check if we should
    # send an email to flex. HOWEVER, we do not send an email for UKIRT,
    # *even if* notify_first_acecept is 1. This is to avoid having to do
    # an extra query in MSBServer to get the telescope name and decide
    # what to set notify-first_accept to.

    unless ($optargs{'notify_first_accept'}) {
        OMP::General->log_message(
            "Not sending first-accept message: not requested");
    }
    elsif ($telescope ne 'JCMT') {
        OMP::General->log_message(
            "Not sending first-accept message: telescope is not JCMT");
    }
    else {
        # Check if we already sent the "first accepted" message for this project tonight.
        my $fdb = OMP::DB::Feedback->new(
            ProjectID => $self->projectid,
            DB => $self->db);

        my $comments = $fdb->getComments(
            date => OMP::DateTools->today,
            status => undef,
            msgtype => OMP__FB_MSG_FIRST_ACCEPTED_MSB_ON_NIGHT,
        );

        # If its the first accepted observation for this night from this project, send an email.
        # (Allow one acceptance -- the one we just performed.)
        if (scalar @$comments) {
            OMP::General->log_message(
                "Not sending first-accept message: message was already sent");
        }
        else {
            my $projectid = $self->projectid;
            my $utdate = OMP::DateTools->today();

            my $omp_url = OMP::Config->getData('omp-url')
                . OMP::Config->getData('cgidir');

            my $message_text =
"The $telescope operator accepted an MSB (title=$msbtitle) from your project $projectid tonight ($utdate). If you want to follow tonight's observing, please go to the remote eavesdropping link in your OMP project page at ${omp_url}/utprojlog.pl?project=$projectid&utdate=$utdate. You should be sent a summary of all of your observations taken tonight within 24 hours of the end of shift.";

            my $message_subject = "$telescope started observing your project on $utdate";

            $self->_notify_feedback_system(
                program => "OMP::DB::MSB",
                subject => $message_subject,
                text => $message_text,
                author => $author,
                msgtype => OMP__FB_MSG_FIRST_ACCEPTED_MSB_ON_NIGHT,
                status => OMP__FB_IMPORTANT,
            );

            OMP::General->log_message("Sent first-accept message");
        }
    }

    $self->_notify_feedback_system(
        program => "OMP::DB::MSB",
        subject => "MSB Observed",
        text => "Marked MSB title=\"$msbtitle \" with checksum"
            . " $checksum as done $reason",
        author => $author,
        msgtype => OMP__FB_MSG_MSB_OBSERVED,
    );

    OMP::General->log_message("Send feedback message and complete transaction");

    # Disconnect
    $self->_dbunlock;
    $self->_db_commit_trans;
}

=item B<undoMSB>

Increment the remaining counter of the MSB by one.

    $db->undoMSB($checksum, $comment);

The MSB is located using the Project identifier (stored in the object)
and the checksum. If an MSB can not be located it is likely that the
science program has been reorganized.

This method locks the database since we are modifying the database
tables. We do not want to retrieve a science program, modify it and
store it again if someone has modified the science program between us
retrieving and storing it.

The time remaining on the project is not adjusted.  In most cases this
is simply the reverse of C<doneMSB> except when AND/OR logic is
involved. Note that C<doneMSB> reorganizes the MSBs to account for
logic but this can not be reversed without having knowledge of what
has changed and whether subsequent observations have occurred (the
science program is only reorganized the first time an MSB in an OR
block is observed).

=cut

sub undoMSB {
    my $self = shift;
    my $checksum = shift;
    my $comment = shift;

    throw OMP::Error::BadArgs(
        'Unexpected comment status for undoMSB')
        unless $comment->status == OMP__DONE_UNDONE;

    # Connect to the DB (and lock it out)
    $self->_db_begin_trans;
    $self->_dblock;

    my $result = $self->_apply_msb_operation($checksum, $comment, sub {
        my $msb = shift;

        # Mark it as not observed
        return $msb->undoObserve;
    });

    if ($result) {
        $self->_notify_feedback_system(
            program => "OMP::DB::MSB",
            subject => "MSB Observe Undone",
            text => "Incremented by 1 the number of remaining "
                . "observations for MSB with checksum"
                . " $checksum",
            msgtype => OMP__FB_MSG_MSB_UNOBSERVED,
        );
    }

    # Disconnect
    $self->_dbunlock;
    $self->_db_commit_trans;
}

=item B<unremoveMSB>

Restore the remaining counter of the MSB which has previously been marked
as removed.

    $db->unremoveMSB($checksum, $comment);

This methods functions like the C<undoMSB> method except that
it it undoes "removed" status rather than MSB observation.

=cut

sub unremoveMSB {
    my $self = shift;
    my $checksum = shift;
    my $comment = shift;

    throw OMP::Error::BadArgs(
        'Unexpected comment status for unremoveMSB')
        unless $comment->status == OMP__DONE_UNREMOVED;

    # Connect to the DB (and lock it out)
    $self->_db_begin_trans;
    $self->_dblock;

    my $result = $self->_apply_msb_operation($checksum, $comment, sub {
        my $msb = shift;

        # Mark it as not removed
        return $msb->unRemove;
    });

    if ($result) {
        $self->_notify_feedback_system(
            program => "OMP::DB::MSB",
            subject => "MSB Unremoved",
            text => "Restored the number of remaining "
                . "observations for MSB with checksum"
                . " $checksum",
            msgtype => OMP__FB_MSG_MSB_UNREMOVED,
        );
    }

    # Disconnect
    $self->_dbunlock;
    $self->_db_commit_trans;
}

=item B<alldoneMSB>

Mark the specified MSB as having been completely observed. The number
of repeats remaining is set to the magic value indicating it has
been removed (see C<OMP::MSB::REMOVED>).

    $db->doneMSB($checksum);

The MSB is located using the Project identifier (stored in the object)
and the checksum.  If an MSB can not be located it is likely that the
science program has been reorganized.

This method locks the database since we are modifying the database
tables. We do not want to retrieve a science program, modify it and
store it again if someone has modified the science program between us
retrieving and storing it.

No time is removed from the project since this action is not associated
with observing.

Invokes the C<hasBeenCompletelyObserved> method on the relevant MSB
object.

=cut

sub alldoneMSB {
    my $self = shift;
    my $checksum = shift;

    my $comment = OMP::Info::Comment->new(
        text => 'MSB removed from consideration',
        status => OMP__DONE_REMOVED);

    # Connect to the DB (and lock it out)
    $self->_db_begin_trans;
    $self->_dblock;

    my $result = $self->_apply_msb_operation($checksum, $comment, sub {
        my $msb = shift;

        $msb->hasBeenCompletelyObserved();

        return 1;
    });

    if ($result) {
        # Might want to send a message to the feedback system at this
        # point
        $self->_notify_feedback_system(
            program => "OMP::DB::MSB",
            subject => "MSB All Observed",
            text => "Marked MSB with checksum" . " $checksum as completely done",
            msgtype => OMP__FB_MSG_MSB_ALL_OBSERVED,
        );
    }

    # Disconnect
    $self->_dbunlock;
    $self->_db_commit_trans;
}

=item B<suspendMSB>

Cause the MSB to go into a "suspended" state such that the next
time it is translated only some of the files will be sent to
the sequencer.

The "suspended" flag is cleared only when an MSB is marked
as "done".

    $db->suspendMSB($checksum, $label);

The label must match the observation labels generated by the
C<unroll_obs> method in C<OMP::MSB>. This label is used by the
translator to determine which observation to start at.

Nothing happens if the MSB can no longer be located since this
simply indicates that the science program has been reorganized
or the MSB modified.

An optional comment object can be supplied to associate the
action with a particular reason and observer.

    $db->suspendMSB($checksum, $label, $comment);

The comment can be used to specify a transaction ID.

=cut

sub suspendMSB {
    my $self = shift;
    my $checksum = shift;
    my $label = shift;
    my $comment = shift;

    # Work out the reason and user and transaction ID
    my $author;
    my $msbtid;
    if (defined $comment) {
        $author = $comment->author;
        $msbtid = $comment->tid;
    }

    my $msg = "MSB suspended at observation $label.";

    my $donecomment = OMP::Info::Comment->new(
        text => $msg,
        status => OMP__DONE_SUSPENDED,
        author => $author,
        tid => $msbtid);

    # Connect to the DB (and lock it out)
    $self->_db_begin_trans;
    $self->_dblock;

    my $result = $self->_apply_msb_operation($checksum, $donecomment, sub {
        my $msb = shift;

        # Mark it as observed
        $msb->hasBeenSuspended($label);

        return 1;
    });

    unless ($result) {
        $msg = "Attempted to suspend MSB at observation $label but the MSB is no longer in the science program.",
    }

    if ((defined $comment) and (defined $comment->text) and ($comment->text =~ /\w/)) {
        $msg .= ": " . $comment->text;
    }

    $self->_notify_feedback_system(
        program => "OMP::DB::MSB",
        subject => "MSB suspended",
        text => "$msg : checksum is $checksum",
        author => $author,
        msgtype => OMP__FB_MSG_MSB_SUSPENDED,
    );

    # Disconnect
    $self->_dbunlock;
    $self->_db_commit_trans;
}

=item B<suspendMSB_comment>

Convenience method to automatically construct a comment and
then call C<suspendMSB>.  (This provides the interface previously
provided by the C<OMP::MSBServer> module.)

    $db->suspendMSB_comment($checksum, $label);

Optionally, a user ID and reason for the suspension can be supplied.

    $db->suspendMSB_comment($checksum, $label, $userid, $reason, $msbtid);

Reason is optional. User id is mandatory if a reason is supplied.
MSB transaction ID requires that reason and userid are specified (or are
at least set explicitly to undef).

B<Note>: this is the interface used by the Queue.  (Or it would be
if suspend was implemented.)

=cut

sub suspendMSB_comment {
    my $self = shift;
    my $checksum = shift;
    my $label = shift;
    my $userid = shift;
    my $reason = shift;
    my $msbtid = shift;

    my $reastr = (defined $reason ? $reason : '<None supplied>');
    my $ustr = (defined $userid ? $userid : "<No User>");
    my $tidstr = (defined $msbtid ? $msbtid : '<No MSBTID>');

    my $project = $self->projectid;

    OMP::General->log_message(
        "suspendMSB: $project $checksum $label\n"
        . "User: $ustr Reason: $reastr\nTransaction ID: $msbtid\n");

    # Create a comment object for suspendMSB
    # We are allowed to specify a user regardless of whether there
    # is a reason
    my $user;
    if ($userid) {
        $user = OMP::User->new(userid => $userid);
        my $userdb = OMP::DB::User->new(DB => $self->db);
        unless ($userdb->verifyUser($user->userid)) {
            throw OMP::Error::InvalidUser(
                "The userid [$userid] is not a valid OMP user ID. Please supply a valid id.");
        }
    }

    # We must have a valid user if there is an explicit reason
    if ($reason && ! defined $user) {
        throw OMP::Error::BadArgs(
            "A user ID must be supplied if a reason for the rejection is given");
    }

    # Form the comment object
    my $comment = OMP::Info::Comment->new(
        status => OMP__DONE_SUSPENDED,
        text => $reason,
        author => $user,
        tid => $msbtid,
    );

    $self->suspendMSB($checksum, $label, $comment);
}

=item B<rejectMSB_comment>

Convenience method to add a comment
indicating that the MSB has been partially observed but has been
rejected by the observer rather than being marked as complete.

    $db->rejectMSB_comment($checksum, $userid, $reason, $msbtid);

This method simply places an entry in the MSB history - it is a
wrapper around addMSBComment method. The optional reason string can be
used to specify a particular reason for the rejection. The userid
is optional unless a reason is supplied (in which case it must be defined
and must match a valid user ID). The MSB transaction ID can be specified.

B<Note>: this is the interface used by the Queue.

=cut

sub rejectMSB_comment {
    my $self = shift;
    my $checksum = shift;
    my $userid = shift;
    my $reason = shift;
    my $msbtid = shift;

    my $reastr = (defined $reason ? $reason : "<None supplied>");
    my $ustr = (defined $userid ? $userid : "<No User>");
    my $tidstr = (defined $msbtid ? $msbtid : '<No MSBTID>');

    my $project = $self->projectid;

    OMP::General->log_message(
        "rejectMSB: $project $checksum User: $ustr Reason: $reastr MSBtid=$msbtid");

    # We are allowed to specify a user regardless of whether there
    # is a reason
    my $user;
    if ($userid) {
        $user = OMP::User->new(userid => $userid);
        my $userdb = OMP::DB::User->new(DB => $self->db);
        unless ($userdb->verifyUser($user->userid)) {
            throw OMP::Error::InvalidUser(
                "The userid [$userid] is not a valid OMP user ID. Please supply a valid id.");
        }
    }

    # We must have a valid user if there is an explicit reason
    if ($reason && ! defined $user) {
        throw OMP::Error::BadArgs(
            "A user ID must be supplied if a reason for the rejection is given");
    }

    # Default comment
    $reason = "This MSB was observed but was not accepted by the observer/TSS. No reason was given."
        unless defined $reason;

    # Add prefix
    $reason = "MSB rejected: $reason";

    # Form the comment object
    my $comment = OMP::Info::Comment->new(
        status => OMP__DONE_REJECTED,
        text => $reason,
        author => $user,
        tid => $msbtid,
    );

    # Add the comment
    my $db = OMP::DB::MSBDone->new(DB => $self->db, ProjectID => $project);
    $db->addMSBcomment($checksum, $comment);
}

=item B<getMSBCount>

Return the total number of MSBs, and the total number of active MSBs, for a
given list of projects.

    \%projectid = $db->getMSBCount(@projectids);

The only argument is a list (or reference to a list) of project IDs.
Returns a hash of hashes indexed by project ID where the second-level
hashes contain the keys 'total' and 'active' (each points to a number).
If a project has no MSBs, not key is included for that project.  If
a project has no MSBs with remaining observations, no 'active' key
is returned for that project.

=cut

sub getMSBCount {
    my $self = shift;
    my @projectids = (ref($_[0]) eq 'ARRAY' ? @{$_[0]} : @_);
    return $self->_get_msb_count(@projectids);
}

=item B<getMSBtitle>

Obtain the title of an MSB given its checksum. This is a convenience
wrapper function.

 $title = $db->getMSBtitle( $checksum );

=cut

sub getMSBtitle {
    my $self = shift;
    my $checksum = shift;

    throw OMP::Error::BadArgs("No checksum supplied to getMSBtitle")
        unless $checksum;

    # can either do this through the query system or directly through
    # SQL since we only want one value from the table... The method approach
    # is a lot more prone to problems and increased overhead for such a simple
    # value
    my $query = OMP::Query::MSB->new(HASH => {
        checksum => $checksum,
        disableconstraint => 'all',
    });
    my @results = $self->queryMSB($query);
    if (@results) {
        return $results[0]->title;
    }
    return undef;
}

=item B<listModifiedPrograms>

Return an array of project IDs for projects whose programs have been modified
since the given date.

    @projects = $db->listModifiedPrograms($time);

Only argument is a C<Time::Piece> object.  If called without arguments all
programs will be returned.  Returns undef if no projects have been modified.

=cut

sub listModifiedPrograms {
    my $self = shift;
    my $date = shift;

    # No XML query interface to science programs, so we'll have to do an SQL query
    my $sql = "SELECT projectid FROM $SCITABLE WHERE timestamp > " . ($date ? $date->epoch : 0);
    my $ref = $self->_db_retrieve_data_ashash($sql);

    my @results = map {$_->{projectid}} @$ref;
}

=back

=head2 Internal Methods

=over 4

=item B<_store_sci_prog>

Store the science program to the "database"

    $status = $db->_store_sci_prog($sp, $freeze, $force, $nocache, $user);

The XML is stored in the database. Transaction management deals with the
case where the upload fails part way through.

If a entry already exists in the database the timestamp is retrieved
and compared with the current version of the science program.
(using the C<timestamp> attribute of the SpProg). If they
differ the new file is not stored (the new science program should
have the timestamp of the old science program).

A timestamp is added to the science program automatically just before
it is written to the database. The overhead in fetching the timestamp
from the database is minimal compared with having to read the old
science program and instantiate a science program object in order to
read the timestamp.

If the optional second argument is present and true, timestamp
checking is disabled and the timestamp is not modified. This is to
allow internal reorganizations to use this routine without affecting
external checking.

A third (optional) argument [presence of which requires the second
argument to be supplied] can be used to disable time stamp checking
completely whilst still generating a new timestamp. This option should
be used with care and should not be used without explicit request
of the owner of the science program. Default is false.

The fourth (optional) argument [requiring the previous two optional args]
controls whether the file is written to the backup file cache or not. By
default the cache file is written unless the timestamp is to be frozen.
ie default is true is freeze is true but false otherwise.

Returns good status or throws exception on error (!!).

=cut

sub _store_sci_prog {
    my $self = shift;
    throw OMP::Error::BadArgs('Usage: $db->_store_sci_prog($sp)') unless @_;
    my $sp = shift;

    my $freeze = shift;
    my $force = shift;

    # Default to freeze state if not defined
    my $nocache;
    if (@_) {
        $nocache = shift;
    }
    else {
        $nocache = $freeze;
    }

    my $user = shift;

    # Check to see if sci prog exists already (if it does it returns
    # the timestamp else undef)
    my $tstamp = $self->_get_old_sciprog_timestamp;

    # If we have a timestamp we need to compare it with what we
    # have now
    if (defined $tstamp) {
        # Disable timestamp checks if freeze is set
        # or we are forcing the store
        unless ($freeze or $force) {
            # Get the timestamp from the current file (we have the old one
            # already)
            my $spstamp = $sp->timestamp;
            if (defined $spstamp) {
                throw OMP::Error::SpChangedOnDisk(
                    "Science Program has changed on disk\n")
                    unless $tstamp == $spstamp;
            }
            else {
                throw OMP::Error::SpChangedOnDisk(
                    "A science program is already in the database with a timestamp but this science program does not include a timestamp at all.\n");
            }
        }

        # Clear the old science program
        $self->_remove_old_sciprog;
    }

    # Put a new timestamp into the science program prior to writing
    $sp->timestamp(time()) unless $freeze;

    # and store it
    my $exstat = $self->_db_store_sciprog($sp);

    # For initial safety purposes, store a text version on disk
    # dont care about exit status - do not call this if we are
    # not caching
    unless ($nocache) {
        try {
            $self->_store_sciprog_todisk($sp);
        }
        catch OMP::Error::CacheFailure with {
            my $E = shift;
            # Trigger email

            # Construct a simple error message
            my $projectid = uc($sp->projectID);

            my $err = "Error writing science program ($projectid) to disk\n";
            $err .= "Request from " . $user->userid . "\n" if defined $user;
            $err .= "Reason:\n\n" . $E->text;

            OMP::General->log_message($err, OMP__LOG_ERROR);

            my %deferr = (
                to => [OMP::User->get_omp_group()],
                from => OMP::User->get_flex(),
                subject => 'failed to write sci prog to disk'
            );
            $self->_mail_information(%deferr, message => $err);
        };
    }

    return $exstat;
}


=item B<_remove_old_sciprog>

Remove an existing science program XML from the database.

    $db->_remove_old_sciprog;

Raises SpStoreFail exception on failure.

=cut

sub _remove_old_sciprog {
    my $self = shift;
    my $proj = $self->projectid;

    $self->_db_delete_data($SCITABLE, "projectid = '$proj' ");
}

=item B<_get_old_sciprog_timestamp>

This retrieves the timestamp of a science program as stored
in the "database". If no such science program exists returns
undef.

This can be used to check existence.

Currently we retrieve the timestamp from a database table.

=cut

sub _get_old_sciprog_timestamp {
    my $self = shift;
    my $proj = $self->projectid;

    # Construct and run the query
    my $sql = "SELECT timestamp FROM $SCITABLE WHERE projectid = '$proj'";
    my $ref = $self->_db_retrieve_data_ashash($sql);

    # Assume that no $ref means no entry in db
    return undef unless defined $ref;

    # Assume that an emptry array means no entry in db
    return undef unless @$ref;

    my $tstamp = $ref->[0]->{timestamp};
    return $tstamp;
}

=item B<_db_store_sciprog>

Store a science program in the database. Assumes the database is ready
to accept an insert.

    $self->_db_store_sciprog($sp, $timestamp);

The optional second argument is a timestamp to store in the database.
If no timestamp is provided, the science program's timestamp will be
used. Return true on success or throws an exception on failure.

=cut

sub _db_store_sciprog {
    my $self = shift;
    my $sp = shift;
    my $timestamp = shift;
    my $proj = $self->projectid;

    unless (defined $timestamp) {
        $timestamp = $sp->timestamp;
    }

    print "Entering _db_store_sciprog\n" if $DEBUG;
    print "Timestamp: ", $timestamp, "\n" if $DEBUG;
    print "Project:   ", $proj, "\n" if $DEBUG;

    # Escape characters
    # For some reason the DB upload does not allow single quotes
    # even when they are escaped. We get around this by replacing
    # a single quote with literal &apos;. Ironically this is what is
    # in the XML saved by the OT - for some reason the XML::LibXML parser
    # manages to translate the &apos; to a single quote for me
    # "automagically". This is a KLUGE until I can work out how to deal
    # with single quotes properly.
    my $spxml = "$sp";
    $spxml =~ s/\'/\&apos;/g;

    # Insert the data into the science program
    $self->_db_insert_data(
        $SCITABLE,
        {
            COLUMN => 'projectid',
            QUOTE => 1,
            POSN => 0,
        },
        $proj,
        $timestamp,
        {
            TEXT => $spxml,
            COLUMN => 'sciprog',
        },
    );

    # Now check for truncation issues
    my $dbh = $self->_dbhandle;
    my $chk_statement = 'SELECT projectid FROM ' . $SCITABLE . ' '
        . 'WHERE projectid = "' . $proj . '" '
        . 'AND sciprog LIKE "%</SpProg>%"';

    my @chk_row = $dbh->selectrow_array($chk_statement);

    # Fetch the whole program back if it was truncated
    unless (defined $chk_row[0]) {
        my $xml = $self->_db_fetch_sciprog();
        $xml =~ s/\&apos;/\'/g;  # level the playing field
        my $orilen = length("$sp");
        my $newlen = length($xml);
        my $retrvtxt = "";
        $retrvtxt = "['$xml']" if $newlen < 30;
        throw OMP::Error::SpTruncated(
            "Science program was truncated during store (now $newlen $retrvtxt rather than $orilen)\n");
    }

    return 1;
}

=item B<_store_sciprog_todisk>

Write the science program to disk. A new version is created for each
submission.

    $db->_store_sciprog_todisk($sp);

This method exists simply to store old versions of science programmes
as backups in case the database goes down. Once we feel confident
with the database backup system we will remove this overhead.

If we can not open the file send an email.

This method is not meant to be JAC-agnostic.

Filename separators (/) are replaced with underscores.

=cut

sub _store_sciprog_todisk {
    my $self = shift;
    my $sp = shift;

    # Directory for writing
    my $cachedir;
    try {
        $cachedir = OMP::Config->getData("sciprog_cachedir");
    }
    catch OMP::Error::BadCfgKey with {
        # no problem. This is an optional key
    };
    # allowed to not specify one
    return unless $cachedir;

    # Get the project ID and replace '/' with '_'
    my $projectid = uc($sp->projectID);
    $projectid =~ s/\//_/g;

    # Check we have a directory
    throw OMP::Error::CacheFailure("Cache directory $cachedir not present")
        unless -d $cachedir;

    # Open a unique output file named "projectid_NNN.xml"
    # Code stolen from SCUBA::ODF
    # First read the disk to get the number
    my $guess = $projectid . '_(\d\d\d)';
    opendir my $DIRH, $cachedir
        or throw OMP::Error::CacheFailure("Error reading directory $cachedir: $!");

    my @numbers = sort {$a <=> $b}
        map {/$guess/ && $1}
        grep /$guess$/,
        readdir($DIRH);

    closedir($DIRH)
        or throw OMP::Error::CacheFailure("Error closing directory $cachedir: $!");

    # First index to try
    my $start = 1 + (@numbers ? $numbers[-1] : 0);

    # Get current umask and set to known umask
    my $umask = umask;

    # Allow anybody in "software" group to do back up of science program files
    # (parent directory has permissions of "drwxrws--x").
    umask(022);

    # Now try to open the file up to 20 times
    # The looping is not really required if combined with the
    # readdir (it simply allows for a number of concurrent accesses
    # by different threads).
    # If we turn off the readdir we will need to make sure this number
    # matches the number of digits supported in INDEX.
    my $MAX_TRIES = 20;
    my $fmt = '%s_%03d';
    my ($fh, $file);
    my $end = $MAX_TRIES + $start;
    for (my $i = $start; $i < $end; $i ++) {
        # Create the file name
        my $file = File::Spec->catfile($cachedir, sprintf($fmt, $projectid, $i));

        my $open_success = sysopen($fh, $file, O_CREAT | O_RDWR | O_EXCL, 0644);

        if ($open_success) {
            # abort the loop
            last;
        }
        else {
            # Abort with error if there was some error other than
            # EEXIST
            unless ($!{EEXIST}) {
                umask($umask);
                throw OMP::Error::CacheFailure(
                    "Could not create temp file $file: $!");
            }
            # clear the file handle so that we can know on exit of the loop
            # whether we did a good open.
            undef $fh;
        }
    }

    # reset umask
    umask($umask);

    # if we do not have a filehandle we need to abort
    unless ($fh) {
        throw OMP::Error::CacheFailure(
            "Could not create temp file after $MAX_TRIES attempts!!!");
    }

    # Now write the science program and return
    print $fh "$sp";
    close $fh;

    # And remove old numbers
    if (@numbers > 3) {
        my $last = $#numbers - 3;
        for my $n (@numbers[0 .. $last]) {
            my $file = File::Spec->catdir($cachedir, sprintf($fmt, $projectid, $n));
            # do not test return value
            unlink($file);
        }
    }

    return;
}

=item B<_really_fetch_sciprog>

Returns C<OMP::SciProg> object after checking for truncation in XML
retrieved from database.

    $sciprog = $db->_really_fetch_sciprog;

It throws C<OMP::Error::UnknownProject> error if science program is
unavailable;
throws C<OMP::Error::SpTruncated> error if XML is truncated;
throws C<OMP::Error::SpRetrieveFail> error if retrieval from database
fails or science program cannot be parsed.

=cut

sub _really_fetch_sciprog {
    my ($self, %opt) = @_;

    # Test to see if the file exists first so that we can
    # raise a special UnknownProject exception.
    my $pid = $self->projectid;
    $pid = '' unless defined $pid;
    throw OMP::Error::UnknownProject(
        "No science program available for \"$pid\"")
        unless $self->_get_old_sciprog_timestamp;

    # Get the science program XML
    my $xml = $self->_db_fetch_sciprog()
        or throw OMP::Error::SpRetrieveFail("Unable to fetch science program\n");

    # Verify for truncation
    if ($xml !~ /SpProg>$/) {
        throw OMP::Error::SpTruncated(
            "Science program for $pid is present in the database but is truncated!!! This should not happen");
    }

    return $xml if $opt{'raw'};

    # Instantiate a new Science Program object
    # The file name is derived automatically
    my $sp = OMP::SciProg->new(XML => $xml)
        or throw OMP::Error::SpRetrieveFail("Unable to parse science program\n");

    return $sp;
}

=item B<_db_fetch_sciprog>

Retrieve the XML from the database and return it.

    $xml = $db->_db_fetch_sciprog();

Note this does not return a science program object since it is used to verify
that the stored program has not been truncated (and the verification routines
like to report the expected size vs the actual size).

This routine does not check for program truncation.

=cut

sub _db_fetch_sciprog {
    my $self = shift;
    my $proj = $self->projectid;
    my $dbh = $self->_dbhandle;
    throw OMP::Error::DBError("Database handle not valid") unless defined $dbh;

    my $sql = "SELECT sciprog FROM $SCITABLE WHERE projectid = '$proj'";

    # Run the query
    my $ref = $self->_db_retrieve_data_ashash($sql);

    # It is not there!
    throw OMP::Error::SpRetrieveFail(
        "Science program does not seem to be in database")
        unless @$ref;

    return $ref->[0]->{sciprog};
}

=item B<_clear_counter_add_feedback_post_fetch>

Remove the observations lables and file feedback about science program
retrieval given an C<OMP::SciProg> object.  It is meant to be run when
science program is fetched for non-internal use (as in C<fetchSciProg>).

    $db->_clear_counter_add_feedback_post_fetch($sciprog);

It takes an optional string argument to append to feedback.

=cut

sub _clear_counter_add_feedback_post_fetch {
    my ($self, $sciprog, $note) = @_;

    # remove any obs labels here since the OT does not use them
    # and it is best that they are regenerated on submission
    # [They are retained only when an MSB is retrieved]
    # Note that we do not strip them when we are doing an internal
    # fetch of the science program since fetchMSB has to fetch
    # a science program in order to obtain the labels
    for my $msb ($sciprog->msb) {
        $msb->_clear_obs_counter;
    }

    $note = '' unless defined $note;
    $self->_notify_feedback_system(
        subject => "Science program retrieved",
        text => "<p>Science program retrieved for project <b>"
            . $self->projectid
            . "</b> $note</p>",
        preformatted => 1,
        msgtype => OMP__FB_MSG_SP_RETRIEVED,
    );

    return;
}

=item B<_verify_project_exists>

Looks in the project database to determine whether the project ID
defined in this object really does exist.

Throws OMP::Error::UnknownProject exception.

=cut

sub _verify_project_exists {
    my $self = shift;

    # Ask the project DB class
    my $proj = OMP::DB::Project->new(
        ProjectID => $self->projectid,
        DB => $self->db);

    my $there = $proj->verifyProject();

    throw OMP::Error::UnknownProject(
        "Project " . $self->projectid
        . " does not exist. Please try another project id")
        unless $there;

    return 1;
}

=item B<_verify_project_constraints>

Given the supplied science program object, obtain the corresponding
project object and compare site quality constraints to make sure they
intersect. Also verifies that scheduling contraints are the correct way
round.

    @warnings = $msbdb->_verify_project_constraints;

Throws an exception of OMP::Error::MSBBadConstraint if there is a constraint
problem. Returns an array of warning strings that can be used to provide
non-fatal feedback to the person submitting the program.

See also the C<verifyMSBs()> method in the C<OMP::SciProg> class for general
MSB warnings.

=cut

sub _verify_project_constraints {
    my $self = shift;
    my $sciprog = shift;

    my @warnings;

    unless (defined $sciprog) {
        throw OMP::Error::FatalError(
            "Attempting to verify constraints but no science program supplied");
    }

    # Ask the project DB class for project object
    my $projdb = OMP::DB::Project->new(
        ProjectID => $self->projectid,
        DB => $self->db);

    my $proj = $projdb->_get_project_row();

    unless (defined $proj) {
        throw OMP::Error::FatalError(
            "Attempting to verify constraints but project '"
            . $self->projectid
            . "' is not available");
    }

    # this will take some time if there are lots of MSBs...
    for my $msb ($sciprog->msb) {
        # get the summary of the MSB
        my %weather = $msb->weather;

        # note that moon is MSB only
        for my $attr (qw/seeing tau cloud sky/) {
            # if we do not have an MSB attribute defined we can ignore
            # it since we will be using the project info
            next unless defined $weather{$attr};

            # method for project object
            my $pmethod = $attr . "range";
            my $prange = $proj->$pmethod();
            $prange = $prange->copy;  # need to make sure we modify a copy

            # does it intersect? Inverted intervals will be caught here since they
            # may well result in two intervals (hence the eval to catch this).
            my $istat;
            eval {$istat = $prange->intersection($weather{$attr});};
            unless ($istat) {
                # failure to intersect
                my $inv = ($weather{$attr}->isinverted
                    ? "($attr constraint is inverted)"
                    : "");
                throw OMP::Error::MSBBadConstraint(
                    "Specified $attr constraint of '" . $weather{$attr}
                    . "' for MSB titled '" . $msb->msbtitle
                    . "' is not consistent with TAG constraint of '"
                    . $prange . "' $inv");
            }

            # need to warn for case where the intersection is an equality
            # note that $prange will have been modified above
            if (($attr eq 'seeing' || $attr eq 'tau')
                    && defined $prange->min
                    && defined $prange->max
                    && $prange->min == $prange->max) {
                push @warnings,
                    "WARNING: $attr constraint is only matched for a single exact value of "
                    . $prange->min
                    . " for MSB titled '" . $msb->msbtitle . "'";
            }

            # it is possible for an inverted range to not be fatal so issue a warning
            if ($weather{$attr}->isinverted) {
                push @warnings,
                    "WARNING: $attr constraint for MSB titled '"
                    . $msb->msbtitle . "' is inverted";
            }
        }

        # check that the allowed date range is not inverted
        my %schedcon = $msb->sched_constraints;
        if ($schedcon{datemin}->epoch > $schedcon{datemax}->epoch) {
            throw OMP::Error::MSBBadConstraint(
                "Scheduling constraint for MSB titled '"
                . $msb->msbtitle
                . "' is such that this MSB can "
                . "never be scheduled (earliest > latest)");
        }
    }

    return @warnings;
}

=item B<_apply_msb_operation>

Wrapper method to retrieve a science program from the database, find an
MSB, apply the given function to it, and then store the updated program
back to the database.

Returns the result from the given function (evaluated in scalar context)
or nothing (undef) if the MSB could not be found.

    $result = $msbdb->_apply_msb_operation($checksum, $comment, sub { ... });

Additional options:

=over 4

=item I<sp_reference>

If given, should be a scalar reference to which the SciProg object should be
assigned (even if the specified MSB is not found).

=item I<no_store>

Skip MSB locate and SciProg store steps.

=back

=cut

sub _apply_msb_operation {
    my $self = shift;
    my $checksum = shift;
    my $comment = shift;
    my $function = shift;
    my %opt = @_;

    # We could use the OMP::DB::MSB::fetchMSB method if we didn't need the science
    # program object. Unfortunately, since we intend to modify the
    # science program we need to get access to the object here
    # Retrieve the relevant science program
    my $sp = $self->fetchSciProg(1);

    ${$opt{'sp_reference'}} = $sp if defined $opt{'sp_reference'};

    # Get the MSB
    my $msb = _find_msb_tolerant($sp, $checksum);

    # Give up if we dont have a match
    return unless defined $msb;

    if (defined $comment) {
        # Update the msb done table (need to do this even if the MSB
        # no longer exists in the science program
        $self->_notify_msb_done($checksum, $sp->projectID, $msb, $comment);
    }

    my $result = $function->($msb);

    unless ($opt{'no_store'}) {
        # Recompute MSB checksums.
        $sp->locate_msbs();

        # Now need to store the MSB back to disk again
        # since this has the advantage of updating the database table
        # and making sure reorganized Science Program is stored.
        # Note that we need the timestamp to change but do not want
        # feedback table notification of this (since we have done that
        # already).
        $self->storeSciProg(
            SciProg => $sp,
            NoCache => 1,
            NoFeedback => 1,
            NoConstraintCheck => 1);
    }

    return $result;
}

=back

=head2 DB Connectivity

These methods connect directly to the database. If the database is changed
(for example to move to DB_File or even Storable) then these are the
only routines that need to be modified.

=over 4

=item B<_insert_rows>

Insert all the rows into the MSB and Obs database using the information
provided in the array of hashes:

    $db->_insert_rows(@summaries);

where @summaries contains elements of class C<OMP::Info::MSB>.

This method extracts basic information from the database to determine whether
each MSB can simply be updated, or whether it needs to be re-inserted.
The following fields can be updated without re-insertion:

=over 4

=item * remaining

=back

Since the scheduler depends on the observations being in the right order,
if the MSB has changed we delete it and its observations, and
re-insert them.

=cut

sub _insert_rows {
    my $self = shift;
    my @summaries = @_;

    # Get the DB handle
    my $dbh = $self->_dbhandle
        or throw OMP::Error::DBError("Database handle not valid");

    # Get the current database status.
    my $sth = $dbh->prepare(
        'SELECT msbid, checksum, remaining'
        . ' FROM ' . $OMP::DB::Project::MSBTABLE
        . ' WHERE projectid=?')
        or throw OMP::Error::DBError('Error preparing MSB check SQL: ' . $DBI::errstr);

    $sth->execute($self->projectid())
        or throw OMP::Error::DBError('Error executing MSB check: ' . $DBI::errstr);

    my $dbhash = $sth->fetchall_hashref('checksum');
    throw OMP::Error::DBError('Error fetching from MSB check: ' . $DBI::errstr)
        if $sth->err();

    # Now loop over each summary and compare the information.  We remove the
    # entries from $dbhash as we go so that it will only include entries no
    # longer in the programme.
    for my $summary (@summaries) {
        my $checksum = $summary->checksum();

        if (exists $dbhash->{$checksum}) {
            my $dbrow = $dbhash->{$checksum};

            # This comparison must check all fields which are accessible in the
            # database but are not included in the checksum.  These should be
            # the same fields we update with _db_update_data.  Note: these fields
            # must also be checked / updated in the OR folder special case below!
            if ($dbrow->{'remaining'} != $summary->remaining()) {
                $DEBUG && print "Insert Rows: updating $checksum\n";

                my $msbid = $dbrow->{'msbid'};
                throw OMP::Error::DBError("MSB ID not defined")
                    unless defined $msbid;

                $self->_db_update_data(
                    $OMP::DB::Project::MSBTABLE,
                    {
                        remaining => $summary->remaining(),
                    },
                    'msbid=' . $msbid);
            }
            else {
                $DEBUG && print "Insert Rows: no action for $checksum\n";
            }

            delete $dbhash->{$checksum};
        }
        # Check whether the entry has been moved out of an OR folder.  We can
        # do this by seeing if the database had the same checksum with an O
        # suffix because md5_hex returns a fixed length string as the checksum.
        # Since we need to execute one UPDATE statement on the MSB table
        # anyway, we might as well update the remaining counter as it probably changed.
        elsif (exists $dbhash->{$checksum . 'O'}) {
            print "Insert Rows: moving out of OR folder $checksum\n" if $DEBUG;

            my $oldchecksum = $checksum . 'O';
            my $dbrow = $dbhash->{$oldchecksum};
            my $msbid = $dbrow->{'msbid'};
            throw OMP::Error::DBError("MSB ID not defined")
                unless defined $msbid;

            $self->_db_update_data(
                $OMP::DB::Project::MSBTABLE,
                {
                    remaining => $summary->remaining(),
                    checksum => $checksum,
                },
                'msbid=' . $msbid);

            delete $dbhash->{$oldchecksum};
        }
        else {
            print "Insert Rows: inserting $checksum\n" if $DEBUG;

            $self->_insert_row($summary, dbh => $dbh,);
        }
    }

    # Entries remaining in $dbhash must have been removed/altered in the science
    # programme, so we delete the old versions in the database.
    for my $checksum (keys %$dbhash) {
        print "Insert Rows: deleting $checksum\n" if $DEBUG;

        my $dbrow = $dbhash->{$checksum};
        my $msbid = $dbrow->{'msbid'};
        throw OMP::Error::DBError("MSB ID not defined")
            unless defined $msbid;

        $self->_db_delete_data(
            $_,
            'msbid=' . $msbid)
            foreach ($OMP::DB::Project::MSBTABLE, $OMP::DB::Project::OBSTABLE);
    }
}


=item B<_insert_row>

Insert a row into the database using the information provided in the
C<OMP::Info::MSB> object.

    $db->_insert_row($info, %config);

The contents of the hash are usually obtained by calling the
C<info> method of the C<OMP::MSB> class.

This method inserts MSB data into the MSB table and the observation
summaries into the observation table.

Usually called from C<_insert_rows>. Expects the config hash to include
special keys:

=over 4

=item dbh

The database handle>

=back

that are used to share state between row inserts. This provides
quite a large optimization over obtaining the index from the database
each time. Note that DBI can not support multiple statement
handles and rollbacks simultaneously. Therefore we can not prepare
the MSB insert in advance whilst also supporting an MSBOBS statement
handle. Since there will be more MSBOBS inserts than MSB inserts
(in general) we only use a statement handle for the MSBOBS table.

=cut

sub _insert_row {
    my $self = shift;
    my $msbinfo = shift;
    my %config = @_;

    print "Entering _insert_row\n" if $DEBUG;

    # Get the database handle from the hash
    my $dbh = $config{dbh}
        or throw OMP::Error::DBError("Database handle not valid in _insert_row");

    # Get the MSB summary
    my %data = $msbinfo->summary('hashlong_noast_norem');
    $data{obscount} = $msbinfo->obscount;

    # Throw an exception if we are missing tau or seeing
    throw OMP::Error::SpBadStructure(
        "There seems to be no site quality information. Unable to schedule MSB.\n")
        unless (defined $data{seeing} and defined $data{tau});

    # Throw an exception if we are missing observations
    throw OMP::Error::MSBMissingObserve(
        "1 or more of the MSBs is missing an Observe\n")
        if $data{obscount} == 0;

    # Store the data
    my $proj = $self->projectid;
    print "Inserting row\n" if $DEBUG;
    OMP::General->log_message("Inserting MSB row [$proj]");

    # Convert the ranges to database values
    my ($taumin, $taumax) = OMP::SiteQuality::to_db('TAU', $data{tau});
    my ($seeingmin, $seeingmax) = OMP::SiteQuality::to_db('SEEING', $data{seeing});
    my ($cloudmin, $cloudmax) = OMP::SiteQuality::to_db('CLOUD', $data{cloud});
    my ($skymin, $skymax) = OMP::SiteQuality::to_db('SKY', $data{sky});
    my ($moonmin, $moonmax) = OMP::SiteQuality::to_db('MOON', $data{moon});

    # If a max or minimum elevation has not been supplied we do not care.
    # A NULL can be stored in the table. We will calculate a suitable
    # minimum elevation when we fetch the entries from the database.
    my ($maxel, $minel);
    if ($data{elevation}) {
        ($minel, $maxel) = $data{elevation}->minmax;
    }

    # cloud and moon are implicit ranges

    # Insert the MSB data
    $self->_db_insert_data(
        $OMP::DB::Project::MSBTABLE,
        undef,
        $proj,
        $data{remaining},
        $data{checksum},
        $data{obscount},
        $data{tau}->min, $taumax,
        $data{seeing}->min, $seeingmax,
        $data{priority},
        $data{telescope},
        int($moonmax),
        int($cloudmax),
        $data{timeest},
        $data{title},
        "$data{datemin}", "$data{datemax}",
        $minel, $maxel, $data{approach},
        int($moonmin),
        int($cloudmin),
        $skymin, $skymax,
    );

    my $index = $dbh->last_insert_id(undef, undef, undef, undef);

    # Now the observations.  Prepare the rows for insert and then insert
    # them all at the end.  This is in case we need to look up any AUTO-TLE
    # targets, since we will need to prepare a different SQL query for that.
    my @obsrows = ();

    for my $obs (@{$data{observations}}) {
        # If coordinates have not been set then we need to raise an exception
        # since we can not schedule this. Note that calibrations
        # will come back as Astro::Coords::Calibration
        unless (exists $obs->{coords}
                and defined $obs->{coords}
                and UNIVERSAL::isa($obs->{coords}, "Astro::Coords")) {
            throw OMP::Error::SpBadStructure(
                "Coordinate information could not be found in an MSB. Unable to schedule.\n");
        }
        my @coords = $obs->{coords}->array;

        # If we dont have an instrument we raise an exception
        unless (exists $obs->{instrument} and defined $obs->{instrument}) {
            throw OMP::Error::SpBadStructure(
                "No instrument defined in MSB. Unable to schedule.\n");
        }

        # Wavelength must be a number (just check for presence of any number)
        $obs->{wavelength} = $obs->{waveband}->wavelength if $obs->{waveband};
        $obs->{wavelength} = -1
            unless (defined $obs->{wavelength}
            and $obs->{wavelength} =~ /\d/a);

        # Retrieve coordstype and target name, so that if the coordstype
        # requires validation of the target name, we can apply that.
        my $coordstype = $obs->{'coords'}->type();
        my $target = $obs->{'target'};
        if ($coordstype eq 'AUTO-TLE') {
            my $tledb = OMP::DB::TLE->new(DB => $self->db());

            # AUTO-TLE requires standardized target names.  This subroutine
            # throws an error if the target name is invalid.
            $target = $tledb->standardize_tle_name($target);

            # Before storing the AUTO-TLE observation, check whether we already
            # have the target in the TLE database.  If so, use its elements.
            my $autocoord = $tledb->get_coord($target);
            if (defined $autocoord) {
                @coords = $autocoord->array();
            }
        }

        push @obsrows, [
            $index,
            $proj,
            uc($obs->{instrument}),
            $obs->{type},
            $obs->{pol},
            $obs->{wavelength},
            $obs->{disperser},
            $coordstype, $target, @coords[1 .. 10],
            $obs->{timeest},
        ];

    }

    # We dont use the generic interface here since we want to
    # reuse the statement handle.
    my $obsst = $dbh->prepare(
        "INSERT INTO $OMP::DB::Project::OBSTABLE VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,NULL)")
        or throw OMP::Error::DBError("Error preparing MSBOBS insert SQL: $DBI::errstr\n");

    foreach my $obsrow (@obsrows) {
        $obsst->execute(@$obsrow)
            or throw OMP::Error::DBError("Error inserting new obs rows: $DBI::errstr");
    }
}


=item B<_clear_old_rows>

Remove all rows associated with the current project ID.

If this is combined with an insert then care should be taken
to make sure that a single database transaction is being used
(see C<_db_begin_trans>). This will guarantee that the old rows
can not be removed without inserting new ones.

=cut

sub _clear_old_rows {
    my $self = shift;

    # Get the DB handle
    my $proj = $self->projectid;

    # Remove the old data
    print "Clearing old msb and obs rows for project ID $proj\n" if $DEBUG;
    $self->_db_delete_project_data(
        $OMP::DB::Project::MSBTABLE,
        $OMP::DB::Project::OBSTABLE);
}

=item B<_fetch_row>

Retrieve a row of information from the database table.

    %result = $db->_fetch_row(msbid => $key);

The information is returned as a hash with keys identical to
the database column names.

The query will be formed by using any or all of C<checksum>,
C<id> and C<projectid> depending on whether they are set in the
argument hash or in the object. If the projectid is not specified,
it is automatically inserted into the query from the object state.

Returns empty list if no match can be found.

If projectid is specified without explicitly specifiying an MSB id
or checksum, all results are returned in a list containing an
C<OMP::Info::MSB> object for each matching row. In scalar context,
returns the first matching MSB object.

    @objects = $db->_fetch_row(projectid => $p);

No attempt is made to retrieve the corresponding observation information
unless an option C<with_observations> is specified.

=cut

sub _fetch_row {
    my $self = shift;
    my %query = @_;

    my $with_observations = delete $query{'with_observations'};

    # Get the project id if it is here and not specified already
    $query{projectid} = $self->projectid
        if (! exists $query{projectid} && defined $self->projectid);

    # We are in multiple match mode if we only have one key (the projectid)
    my $multi = (scalar keys %query == 1 && exists $query{projectid} ? 1 : 0);

    # Assume that query keys match column names
    my @substrings = map {" $_ = ? "} sort keys %query;

    # and construct the SQL command using bind variables so that
    # we dont have to worry about quoting
    my $sql = "SELECT * FROM $OMP::DB::Project::MSBTABLE WHERE" . join("AND", @substrings);
    print "STATEMENT: $sql\n" if $DEBUG;

    # Run the query
    my $ref = $self->_db_retrieve_data_ashash(
        $sql,
        map {$query{$_}} sort keys %query);

    # Dont throw an error here. It is up to the caller to decide whether
    # to do or not.
    # throw OMP::Error::DBError("Error fetching specified row - no matches for [$sql]")
    #     unless @$ref;

    if ($with_observations) {
        $sql = "SELECT * FROM $OMP::DB::Project::OBSTABLE WHERE "
            . join("AND", @substrings)
            . " ORDER BY obsid ASC";
        print "STATEMENT: $sql\n" if $DEBUG;

        my $obsref = $self->_db_retrieve_data_ashash(
            $sql,
            map {$query{$_}} sort keys %query);

        my %msb_obs = ();
        foreach (@$obsref) {
            $_->{'waveband'} = Astro::WaveBand->new(
                Instrument => $_->{instrument},
                Wavelength => $_->{wavelength}
            );
            $_->{'coords'} = _obs_row_to_coord($_, 0);
            push @{$msb_obs{delete $_->{'msbid'}}}, $_;
        }
        $_->{'observations'} = $msb_obs{$_->{'msbid'}} foreach @$ref;
    }

    # if we are returning multiple results create OMP::Info::MSB objects
    if ($multi) {
        my @objects = $self->_msb_row_to_msb_object(@$ref);
        return (wantarray ? @objects : $objects[1]);
    }
    else {
        # one result, the first entry in @$ref
        my %result;
        %result = %{$ref->[0]} if @$ref;
        return %result;
    }
}

=item B<_run_query>

Run a query on the database table using an C<OMP::Query::MSB> object and
return the matching rows (up to a maximum number) as an array of hash
references.

    @results = $db->_run_query($query);

The query object controls the maximum number of results that
can be retrieved (see L<OMP::Query::MSB/maxCount>).

=cut

# List of priority kludges to apply.  This list maps project patterns
# to the amount by which to increase the priority value (lowering the
# priority) and the tau interval over which to apply this.  Only one
# (the first matching) tweak will be applied to any MSB.
my @priority_tweaks = (
    [qr/^TJ01$/, 100, Number::Interval->new(
        Min => 0.05, Max => 0.08, IncMin => 1, IncMax => 0)],
);

sub _run_query {
    my $self = shift;
    my $query = shift;

    my $t0 = [gettimeofday];

    # Get the sql
    my $sql = $query->sql(
        $OMP::DB::Project::MSBTABLE,
        $OMP::DB::Project::OBSTABLE,
        $OMP::DB::Project::PROJTABLE,
        $OMP::DB::Project::PROJQUEUETABLE,
        $OMP::DB::Project::PROJUSERTABLE);

    print "SQL: $sql\n" if $DEBUG;

    # Obtain tau value from the query in order to check for priority adjustments
    # for survey projects being observed out of band.
    my $tau = $query->tau();

    # Run the initial query
    my $ref = $self->_db_retrieve_data_ashash($sql);

    my $t1 = [gettimeofday];
    OMP::General->log_message(
        "Query complete: " . @$ref . " MSBs in "
        . tv_interval($t0, $t1) . " seconds\n",
        OMP__LOG_DEBUG);
    $t0 = $t1;

    # print Dumper($ref);
    # No point hanging around if nothing retrieved
    return () unless @$ref;

    throw OMP::Error::MSBMalformedQuery(
        "Result of query did not include msbid field!")
        unless exists $ref->[0]->{msbid};

    # Now for each MSB we need to retrieve all of the Observation
    # information and store it in the results hash
    # Convention dictates that this information ...???
    # We can not simply extract all the MSBIDs in one go since we
    # will overflow the query buffer. Need to split the list into
    # chunks and query each in turn. Abort the loop once we hit
    # the requisite number of matches.

    # For now kluge it so that we do the fetch for all the MSBIDs
    # even if we know that we only need the first few from the first
    # query (assuming they match the observability constraints). When
    # we have time we should either think of a better way of doing this
    # in the SQL or at least expand the loop to include the observability
    # tests, jumping out when we have enough matches.
    my $MAX_ID = 250;
    my @observations;
    foreach my $chunk (OMP::General->array_in_chunks([map {$_->{'msbid'}} @$ref], $MAX_ID)) {
        $sql = "SELECT * FROM $OMP::DB::Project::OBSTABLE WHERE msbid IN ("
            . join(', ', @$chunk)
            . ") ORDER BY obsid ASC";

        my $obsref = $self->_db_retrieve_data_ashash($sql);

        push @observations, @$obsref;
    }

    $t1 = [gettimeofday];
    OMP::General->log_message(
        "Obs retrieval: " . @observations . " obs in  "
        . tv_interval($t0, $t1) . " seconds\n",
        OMP__LOG_DEBUG);
    $t0 = $t1;

    # Now loop over the results and store the observations in the
    # correct place. First need to create the obs arrays by msbid
    # (using msbid as key)
    my %msbs;
    my %instruments_used = ();
    for my $row (@observations) {
        my $msb = $row->{msbid};
        if (exists $msbs{$msb}) {
            push(@{$msbs{$msb}}, $row);
        }
        else {
            $msbs{$msb} = [$row];
        }
        delete $row->{msbid};  # not needed

        # Create the waveband objects
        # Only create the coordinate object if required since there is
        # some overhead involved and we don't want to do it for every single
        # row since there could be thousands of observations even though
        # we only need the first 10
        $row->{waveband} = Astro::WaveBand->new(
            Instrument => $row->{instrument},
            Wavelength => $row->{wavelength}
        );

        # Record which instruments are used for this MSB (because instrument
        # is a property of the observation rather than MSB).
        if (exists $instruments_used{$msb}) {
            $instruments_used{$msb}->{$row->{'instrument'}} ++;
        }
        else {
            $instruments_used{$msb} = {$row->{'instrument'} => 1};
        }
    }

    $t1 = [gettimeofday];
    OMP::General->log_message(
        "Create obs hash indexed by MSB ID "
        . tv_interval($t0, $t1) . " seconds\n",
        OMP__LOG_DEBUG);
    $t0 = $t1;

    # And now attach it to the relevant MSB
    # If there are no observations this will store undef (will happen
    # if a dummy science program is uploaded)
    for my $row (@$ref) {
        my $msb = $row->{msbid};
        $row->{observations} = $msbs{$msb};

        # and move the newpriority column over the priority since
        # I have not yet worked out how to force PostGres to order by
        # a new column that matches a previous column
        $row->{priority} = $row->{newpriority} if exists $row->{newpriority};
        delete $row->{newpriority};

        # Attach the set of instruments used.
        $row->{'instruments_used'} = $instruments_used{$msb};
    }

    $t1 = [gettimeofday];
    OMP::General->log_message(
        "Attach obs to MSB: " . tv_interval($t0, $t1) . " seconds\n",
        OMP__LOG_DEBUG);
    $t0 = $t1;

    # Now to limit the number of matches to return
    # Determine how many MSBs we have been asked to return
    my $max = $query->maxCount;

    # An array to store the successful matches
    my @observable;

    # max and min priority in all acceptable results
    my $primin = 1E30;
    my $primax = -1E30;

    # Have we tweaked any priority values?  If so we'll need
    # to re-sort the results at the end.
    my $priority_tweaked = 0;

    # Decide whether to do an explicit check for observability
    if (0) {
        # Slice if necessary
        if (defined $max) {
            $max --;  # convert to index
            $max = ($max < $#$ref && $max > -1 ? $max : $#$ref);
        }
        else {
            $max = $#$ref;
        }
        @observable = @$ref[0 .. $max];
    }
    else {
        # KLUGE *******************************
        # Since we do not yet have a stored procedure to calculate whether
        # the target is observable we have to do it by hand for each
        # observation in an MSB
        # Note that we have to be careful about the following:
        #  1. Checking that the observation is above that requested
        #     in SpSchedConstraint
        #  2. Checking that the target is within the allowed range
        #     (between 10 and 87 deg el at JCMT and
        #      HA = +/- 4.5h and dec > -42 and dec < 60 deg at UKIRT )
        #  3. Check that it stays within that range for the duration
        #     of the observation
        #  4. As a final check make sure that the last target in an MSB
        #     has not set by the time the first has finished.
        #     (this happens automatically since we increment the reference
        #     date by the estimated duration of each observation)

        # The reference date is obtained from the query. It will either
        # be the current time or a time that was specified in the query.
        my $refdate = $query->refDate;

        # Determine whether we are interested in checking for
        # observability. We cant jump out the for loop because
        # the person receiving the query will still want to
        # know hour angle and things
        my %qconstraints = $query->constraints;

        # Get the elevation/airmass and hour angle constraints
        my $amrange = $query->airmass;
        my $harange = $query->ha;
        my $seeing = $query->seeing;
        my $qhash = $query->query_hash;
        my $qphase = 0;
        if (exists($qhash->{'moonmax'})
                && defined($qhash->{'moonmax'})) {
            $qphase = $qhash->{'moonmax'}->min;
        }

        # Count how many we actual checked
        my $msb_count;
        my $obs_count;

        # Set up seeing variables.
        my $seeing_coderef;
        my $perform_seeing_calc = defined($seeing);
        my $obs_wavelength;
        my $obs_airmass;

        # Set up zone-of-avoidance variables
        my $zoa_coords;
        my $zoa_phase;
        my $zoa_target;
        my $zoa_radius;
        my $zoa_azdist;

        my $zoa_targetrise;
        my $zoa_targetset;
        my $zoa_targetup = 0;

        # Loop over each MSB in order
        for my $msb (@$ref) {
            $msb_count ++;

            # Reset the reference time for this msb
            my $date = $refdate;

            # Get the telescope name from the MSB and create a telescope object
            my $telescope = Astro::Telescope->new($msb->{telescope});

            # Get the seeing limits for this MSB and set up a range.
            my $msb_seeingrange = OMP::SiteQuality::from_db(
                "seeing", $msb->{seeingmin}, $msb->{seeingmax});

            OMP::SiteQuality::undef_to_default("seeing", $msb_seeingrange);

            if ($msb_seeingrange->isinverted) {
                # seeing values are null set so if we are checking seeing no
                # MSB can match
                $msb_seeingrange = undef;
                OMP::General->log_message(
                    "Unable to match MSB " . $msb->{checksum}
                    . " of project " . $msb->{projectid}
                    . " because the seeing bounds do not intersect",
                    OMP__LOG_ERROR);
            }

            my $zoa = $qconstraints{zoa};

            # Retrieve zone-of-avoidance information from the config system
            # for this telescope if we don't already have it.
            if ($zoa) {
                unless (defined($zoa_phase)) {
                    # missing key is allowed
                    try {
                        $zoa_phase = OMP::Config->getData('zoa_phase',
                            telescope => $msb->{telescope});
                    }
                    catch OMP::Error with {
                        # ignore
                    };
                }
                unless (defined($zoa_target)) {
                    try {
                        $zoa_target = OMP::Config->getData('zoa_target',
                            telescope => $msb->{telescope});
                    }
                    catch OMP::Error with {
                        # ignore
                    };
                }
                unless (defined($zoa_radius)) {
                    try {
                        $zoa_radius = OMP::Config->getData('zoa_radius',
                            telescope => $msb->{telescope});
                    }
                    catch OMP::Error with {
                        # ignore
                        $zoa_radius = 0;
                    };
                }
                unless (defined $zoa_azdist) {
                    try {
                        $zoa_azdist = OMP::Config->getData('zoa_azdist',
                            telescope => $msb->{'telescope'});
                    }
                    catch OMP::Error with {
                        $zoa_azdist = 0;
                    };
                }
                # The config file could specify a blank target if there is nothing to avoid
                unless ($zoa_target) {
                    $zoa = 0;
                }

                if ($zoa && ! defined($zoa_coords)) {
                    $zoa_coords = Astro::Coords->new(planet => $zoa_target);
                    $zoa_coords->telescope(Astro::Telescope->new($msb->{telescope}));
                    $zoa_coords->datetime($refdate);
                    if ($zoa_coords->el > 0) {
                        $zoa_targetup = 1;
                    }
                    $zoa_targetrise = $zoa_coords->rise_time;
                    $zoa_targetset = $zoa_coords->set_time;
                    unless (defined($zoa_targetrise)) {
                        $zoa_coords->datetime($refdate + 12 * ONE_HOUR);
                        $zoa_targetrise = $zoa_coords->rise_time;
                        $zoa_coords->datetime($refdate);
                    }
                }
            }

            # Retrieve seeing calculation information from the config system
            # for this telescope if we don't already have it and if it's
            # possible to do it.
            if ($perform_seeing_calc && ! defined($seeing_coderef)) {
                try {
                    my $seeingeq_str = OMP::Config->getData('seeing_eq',
                        telescope => $msb->{telescope});

                    # Replace any placeholders with the variables we've set
                    # up. +_SEEING_+ will be replaced with $seeing,
                    # +_WAVELENGTH_+ will be replaced with $obs_wavelength, and
                    # +_AIRMASS_+ will be replaced with $obs_airmass.
                    $seeingeq_str =~ s/\+_SEEING_\+/\$seeing/g;
                    $seeingeq_str =~ s/\+_WAVELENGTH_\+/\$obs_wavelength/g;
                    $seeingeq_str =~ s/\+_AIRMASS_\+/\$obs_airmass/g;

                    # Generate an anonymous coderef.
                    my $anon_sub = "sub { $seeingeq_str };";
                    $seeing_coderef = eval "$anon_sub";
                }
                catch OMP::Error::BadCfgKey with {
                    $perform_seeing_calc = 0;
                }
                otherwise {
                    $perform_seeing_calc = 0;
                };
                unless ($perform_seeing_calc) {
                    # put an error message in the log
                    OMP::General->log_message(
                        "Error decoding adjusted seeing formula",
                        OMP__LOG_ERROR);
                }
            }

            # Do not do ZOA calculations if the current phase is smaller
            # than the requested phase, but only if the current phase is not
            # zero (the QT sends a phase of zero if the moon is set at the
            # current time, but the moon could rise during an observation,
            # so we want to check the moon's position anyhow).
            if ($zoa
                    && $zoa_target eq 'MOON'
                    && $zoa_phase > $qphase
                    && $qphase != 0) {
                $zoa = 0;
            }

            # Use a flag variable to indicate whether all
            # the observations are observable
            # Begin by assuming all is okay so that we can drop out the
            # loop and unset it on failure
            my $isObservable = 1;

            # in the current design minimum elevation constraints are a function
            # of the MSB and not the Observation itself. The hope is that most
            # people will be happy with defaults and that most MSBs contain
            # a single science target anyway.
            # For now default the min elevation to 0 degrees if it has not
            # been stored in the table.  In the final version we should default
            # to some value corresponding the minimum of 30 degrees and the
            # the elevation required for the source to be available at least 50
            # per cent of the time it is above the horizon. This will require
            # we run through all the observations to determine this. Hope that
            # overhead is not too great given that this quantity could be
            # calculated as a static value at submission time.
            # [and we may well do that eventually]
            # THIS MUST BE IN DEGREES
            my $minel = $msb->{minel};
            $minel = 30 unless defined $minel;  # use 30 for now as min
            $minel *= Astro::PAL::DD2R;         # convert to radians

            my $maxel = $msb->{maxel};
            # Use 75 degrees as the default maximum elevation for SCUBA-2
            # as agreed at the JCMT meeting of 2/13/14.
            # (Implemented for any observation including SCUBA-2 to avoid having
            # multiple elevation constraints because at present switching
            # instruments is time consuming so there won't be many MSBs with a
            # mixture of instruments.)
            $maxel = 75
                if (not defined $maxel)
                and (exists $msb->{'instruments_used'}->{'SCUBA-2'});
            $maxel *= Astro::PAL::DD2R if defined $maxel;

            # create the range object
            my $elconstraint = OMP::Range->new(Max => $maxel, Min => $minel);

            # Rising or setting can be done simply by multiplying
            # the hour angle by the approach value. If they are the
            # same sign we get a positive number and so match,
            # If we have no preference simply use zero
            my $approach = $msb->{approach};
            $approach = 0 unless defined $approach;

            # In order to calculate the scheduling priority we need
            # calculate the mean Hour Angle for each of the observations
            # in the results
            my $nh = 0;
            my $hasum = 0;

            # Loop over each observation.
            # We have to keep track of the reference time
            OBSLOOP: for my $obs (@{$msb->{observations}}) {
                $obs_count ++;

                # Create the coordinate object in order to calculate
                # observability.
                my $coords = _obs_row_to_coord($obs, 1);
                unless (defined $coords) {
                    $isObservable = 0;
                    last OBSLOOP;
                }

                $obs->{'coords'} = $coords;

                # Set the teelscope
                $coords->telescope($telescope);

                # Loop over two times. The current time and the current time
                # incremented by the observation time estimate Note that we do
                # not test for the case where the source is not observable
                # between the two reference times except for additionally
                # checking transit if it transited between the start and
                # end times.  The transit test is preformed by adding the
                # special string 'TRANSIT' as a "$delta", in order to avoid
                # having to duplicate all the logic from the loop for the
                # transit test.  If sources dipping below the minimum elevation
                # at some point during the observation becomes a problem,
                # then the transit test could replaced with one that tests
                # at the source's lower as well as upper culmination.
                my @is_rising = ();
                for my $delta (0, $obs->{timeest}, 'TRANSIT') {
                    my $test_date = undef;

                    unless ($delta eq 'TRANSIT') {
                        # Increment the date (which persists between observations which
                        # we are checking).
                        $date += $delta;

                        # Perform the test at the same date.
                        $test_date = $date;
                    }
                    else {
                        throw OMP::Error::FatalError(
                            'Source rising/setting '
                            . 'information missing for determination of whether a transit '
                            . 'check is necessary')
                            unless 2 == scalar @is_rising;

                        # Skip the transit test for TLE coordinates until meridian_time
                        # is implemented for Astro::Coords::TLE, if it turns out that
                        # this test would be useful for TLEs.
                        next if $coords->type() eq 'TLE'
                            or $coords->type() eq 'AUTO-TLE';

                        # Skip the transit check unless the source was rising at
                        # the start of the observation and setting at the end.
                        next unless $is_rising[0] && ! $is_rising[1];

                        # Since we will have just checked the end of the
                        # observation, ask Astro::Coords to find the closest
                        # transit before the current time.
                        $test_date = $coords->meridian_time(event => -1);
                    }

                    # Set the time in the coordinates object
                    $coords->datetime($test_date);

                    # Record whether the source was rising at this time
                    # by checking the sign of the hour angle.
                    my $n_is_rising = eval {
                        push @is_rising, ($coords->ha(normalize => 1) < 0);
                    };
                    # Push should return the new length of @is_rising, but if there is
                    # an error, eval will return undef.  In that case we print an error
                    # message and assume the observation is not observable.
                    unless (defined $n_is_rising) {
                        print STDERR
                            "Error calculating HA of source for project:\n",
                            $msb->{'projectid'}, ' ',
                            $msb->{'checksum'}, ' ',
                            $obs->{'target'}, "\n",
                            $msb->{'title'}, "\n",
                            'Message: ', $@, "\n";
                        $isObservable = 0;
                        last OBSLOOP;
                    }

                    # If we are a CAL observation just skip
                    # make sure to add the time estimate though!
                    next if $obs->{coordstype} eq 'CAL';

                    # Now see if we are observable (dropping out the loop if not
                    # since there is no point checking further) This knows about
                    # different telescopes automatically Also check that we are
                    # above the minimum elevation (which is not related to the
                    # queries but is a scheduling constraint) In some cases we
                    # dont even want to test for observability
                    if ($qconstraints{observability}) {
                        my $unobservable = eval {
                            ! $coords->isObservable
                                or ! $elconstraint->contains($coords->el)
                                or ! ($coords->ha(normalize => 1) * $approach >= 0);
                        };
                        unless (defined $unobservable) {
                            print STDERR
                                "Error calculating observability of source for project:\n",
                                $msb->{'projectid'}, ' ',
                                $msb->{'checksum'}, ' ',
                                $obs->{'target'}, "\n",
                                $msb->{'title'}, "\n",
                                'Message: ', $@, "\n";
                            $isObservable = 0;
                            last OBSLOOP;
                        }
                        elsif ($unobservable) {
                            $isObservable = 0;
                            last OBSLOOP;
                        }
                    }

                    # Now check for hour angle and elevation constraints
                    # imposed from the query.
                    if ($harange) {
                        unless ($harange->contains(
                                $coords->ha(format => 'h', normalize => 1))) {
                            $isObservable = 0;
                            last OBSLOOP;
                        }
                    }
                    if ($amrange) {
                        unless ($amrange->contains($coords->airmass)) {
                            $isObservable = 0;
                            last OBSLOOP;
                        }
                    }

                    if ($perform_seeing_calc) {
                        unless ($msb_seeingrange) {
                            $isObservable = 0;
                            last OBSLOOP;
                        }

                        # Get the wavelength and airmass.
                        $obs_wavelength = $obs->{waveband}->wavelength;
                        if ($obs_wavelength != 0) {
                            $obs_airmass = $coords->airmass;

                            # Calculate the new seeing.
                            my $new_seeing = &$seeing_coderef;
                            OMP::General->log_message(
                                "Testing Seeing of $new_seeing against "
                                . $msb_seeingrange,
                                OMP__LOG_DEBUG
                            );

                            unless ($msb_seeingrange->contains($new_seeing)) {
                                $isObservable = 0;
                                last OBSLOOP;
                            }
                        }
                    }

                    # Do zone-of-avoidance filtering. Need to use Modified
                    # Julian Day for comparison so we can compare Time::Piece
                    # with DateTime objects.
                    if (($zoa) && (
                            ($zoa_targetup && $test_date->mjd < $zoa_targetset->mjd)
                            || (! $zoa_targetup && $test_date->mjd > $zoa_targetrise->mjd))) {
                        # Calculate the position of the zone-of-avoidance target.
                        $zoa_coords->datetime($test_date);

                        # Find the distance between our observation and the zoa
                        # target. If it's less than the radius (which is in
                        # degrees) then the observation is not observable.
                        my $distance = $coords->distance($zoa_coords);
                        if (defined $distance && $distance->degrees < $zoa_radius) {
                            $isObservable = 0;
                            last OBSLOOP;
                        }

                        # If a ZOA azimuth distance has been set, also check it.
                        if ($zoa_azdist) {
                            my $azimuth = $coords->az(format => 'deg');
                            my $zoa_azimuth = $zoa_coords->az(format => 'deg');

                            if ((defined $azimuth) and (defined $zoa_azimuth)) {
                                my $azdist = abs($zoa_azimuth - $azimuth);
                                $azdist = 360.0 - $azdist if $azdist > 180.0;
                                if ($azdist < $zoa_azdist) {
                                    $isObservable = 0;
                                    last OBSLOOP;
                                }
                            }
                        }
                    }

                    unless ($delta eq 'TRANSIT') {
                        # Include the HA for the start and end of the observation
                        $nh ++;
                        $hasum += abs($coords->ha(format => 'radians'));
                    }
                }
            }

            # If the MSB is observable store it in the output array
            if ($isObservable) {
                push(@observable, $msb);

                # Check whether any of the priority kludges apply to this
                # MSB.
                foreach my $tweak (@priority_tweaks) {
                    my ($projpattern, $tweakval, $tauinterval) = @$tweak;

                    next unless ($msb->{'projectid'} =~ $projpattern)
                        and $tauinterval->contains($tau);

                    $msb->{'priority'} += $tweakval;
                    $priority_tweaked = 1;
                    last;
                }

                # check priority [TAG range]
                my $pri = int($msb->{priority});
                if ($pri > $primax) {
                    $primax = $pri;
                }
                elsif ($pri < $primin) {
                    $primin = $pri;
                }

                # calculate mean hour angle
                my $hamean = 0;

                $hamean = $hasum / $nh if $hasum > 0;

                # and convert to hours
                $hamean *= Astro::PAL::DR2H;

                # Store the mean hour angle for later
                $msb->{hamean} = $hamean;

                # Jump out the loop if we have enough matches
                # A negative $max will never match
                last if scalar(@observable) == $max;
            }
        }

        $t1 = [gettimeofday];
        OMP::General->log_message(
            "Observability filtered: checked $msb_count MSBs and $obs_count obs in "
            . tv_interval($t0, $t1) . " seconds and got "
            . @observable . " matching MSBs\n",
            OMP__LOG_DEBUG);
        $t0 = $t1;
    }

    # calculate the priority scale factor
    # but only if we have priorities larger than 10 (since we need
    # a dynamic range of 10 in the final number
    my $dynrange = 10;
    my $priscale = 1;
    my $prioff = 0;
    my $prirange = $primax - $primin;
    if ($prirange > $dynrange) {
        $prioff = $primin;
        $priscale = $prirange / $dynrange;
    }
    elsif ($primax > $dynrange) {
        # if the max priority is greater than 10, but the
        # separation between min and max is less than 10,
        # make sure the offset brings everything to a 0 to 10
        # range
        $prioff = $primax - $dynrange;
    }

    # calculate the scheduling priority for the observable MSBs
    for my $msb (@observable) {
        # hour angle contribution
        my $hapart = (1 + ($msb->{hamean} / HAMAX))**2;
        delete $msb->{hamean};

        # Completion component.
        # Need the log of the time remaining. Sometimes a project
        # can have 0 time remaining so provide an upper limit
        my $comppart;
        if ($msb->{completion} > 99.99) {
            $comppart = 2;
        }
        else {
            $comppart = -log10(100 - $msb->{completion});
        }

        # the priority component, scales from 1 to 10
        my $pripart = ($msb->{priority} - $prioff) / $priscale;

        # calculate the scheduling priority
        $msb->{schedpri} = $hapart + $comppart + $pripart;
    }

    $t1 = [gettimeofday];
    OMP::General->log_message(
        "Scheduling priority: " . tv_interval($t0, $t1) . " seconds\n",
        OMP__LOG_DEBUG);
    $t0 = $t1;

    # At this point we need to resort by schedpri
    # Note that because we ORDER BY PRIORITY and jump out the
    # loop when we have enough matches, it's possible that some
    # MSBs will be missed that have a relatively low priority but
    # higher relative schedpri. The only way to be sure is to
    # work out the observability constraints for all matching
    # MSBs and then filter.

    # Get the sort type based on the first telescope name
    if (@observable) {
        my $telescope = $observable[0]->{telescope};
        my $sortby;
        try {
            $sortby = OMP::Config->getData('sortby', telescope => $telescope);
        }
        catch OMP::Error with {
            # Default behaviour
            $sortby = 'priority';
        };

        if ($sortby eq 'priority') {
            # Already done unless we tweaked the priorities.
            @observable = sort {$a->{'priority'} <=> $b->{'priority'}} @observable
                if $priority_tweaked;
        }
        elsif ($sortby eq 'schedpri') {
            @observable = sort {$a->{schedpri} <=> $b->{schedpri}} @observable;
        }
        elsif ($sortby eq 'completion') {
            # Sorting priority for EAO pilot science semester: consider
            # completion (least complete first) and user priority only.
            @observable = sort {
                $a->{'completion'} <=> $b->{'completion'}
                || $a->{'userpriority'} <=> $b->{'userpriority'}
            } @observable;
        }
        elsif ($sortby eq 'time_observed') {
            # Another possible scheme for EAO pilot science semester: consider
            # allocation usage by affiliation,
            # time observed (least time first) and user priority only.
            my $affiliation_db = OMP::DB::ProjAffiliation->new(DB => $self->db());
            my $proj_affiliation = $affiliation_db->get_all_affiliations();
            my $sem_affiliation = $affiliation_db->get_all_affiliation_allocations($telescope);

            # Compute affiliation allocation usage for each MSB.  This is:
            # usage = sum_affiliation fraction_affiliation * completion_affiliation
            # Where:
            # completion_affiliation = observed_affiliation / allocation_affiliation
            foreach my $msb (@observable) {
                my $usage = 0.0;
                my $affiliations = $proj_affiliation->{$msb->{'projectid'}};
                unless (scalar keys %$affiliations) {
                    $usage = 1.0;
                }
                else {
                    my $semester = $sem_affiliation->{$msb->{'semester'}};
                    while (my ($affiliation, $fraction) = each %$affiliations) {
                        my $allocation = $semester->{$affiliation};
                        $usage += 1.0 * $fraction * $allocation->{'observed'}
                            / $allocation->{'allocation'};
                    }
                }
                $msb->{'affiliation_usage'} = $usage;

                # Write the affiliations into the MSB so that they can be shown in
                # the query results.
                $msb->{'affiliation'} = join('/',
                    sort {$affiliations->{$b} <=> $affiliations->{$a}}
                        keys %$affiliations);
            }

            # 1st pass sort: time observed and user priority.
            @observable = sort {
                $a->{'time_observed'} <=> $b->{'time_observed'}
                || $a->{'userpriority'} <=> $b->{'userpriority'}
            } @observable;

            # 2nd pass sort: affiliation usage with 10% tolerance.
            stable_fuzzy_sort(sub {
                $_[0]->{'affiliation_usage'}
            }, 0.1, \@observable);
        }
        else {
            throw OMP::Error::FatalError("Unknown sorting scheme: $sortby");
        }
    }

    $t1 = [gettimeofday];
    OMP::General->log_message(
        "Sorted: " . tv_interval($t0, $t1) . " seconds\n",
        OMP__LOG_DEBUG);
    $t0 = $t1;

    # Convert the rows to MSB info objects
    return $self->_msb_row_to_msb_object(@observable);
}

=item B<_obs_row_to_coord>

Extract an Astro::Coords object based on a row from the ompobs table.

Returns undef if the coordinate cannot be processed (e.g. Pluto),
and may throw exceptions in the case of other problems.

=cut

sub _obs_row_to_coord {
    my $obs = shift;
    my $radec_as_interp = shift;

    my $coords = undef;

    my $coordstype = $obs->{coordstype};
    if ($coordstype eq 'CAL') {
        $coords = Astro::Coords->new();
    }
    elsif ($coordstype eq 'RADEC') {
        if ($radec_as_interp) {
            # Prepare to create an Astro::Coords::Interpolated
            # object which will have the effect of treating
            # the coordinates as apparent coordiates.
            $coords = Astro::Coords->new(
                name => $obs->{'target'},
                ra1 => $obs->{ra2000},
                ra2 => $obs->{ra2000},
                dec1 => $obs->{dec2000},
                dec2 => $obs->{dec2000},
                mjd1 => 50000,
                mjd2 => 50000,
                units => 'radians',
            );
        }
        else {
            $coords = Astro::Coords->new(
                name => $obs->{'target'},
                ra => $obs->{ra2000},
                dec => $obs->{dec2000},
                type => 'J2000',
                units => 'radians',
            );
        }
    }
    elsif ($coordstype eq 'PLANET') {
        if ($obs->{'target'} eq 'pluto') {
            # Astro::Coords not longer supports Pluto so we cannot calculate
            # whether or not it is observable.
            return undef;
        }

        $coords = Astro::Coords->new(planet => $obs->{target});
    }
    elsif ($coordstype eq 'ELEMENTS') {
        print "Got ELEMENTS: " . $obs->{target} . "\n" if $DEBUG;

        # Use the array constructor since the columns were
        # populated using array() method and we do not want to
        # repeat the logic
        $coords = Astro::Coords->new(
            name => $obs->{'target'},
            elements => [
                'ELEMENTS',
                undef,
                undef,
                $obs->{el1}, $obs->{el2}, $obs->{el3}, $obs->{el4},
                $obs->{el5}, $obs->{el6}, $obs->{el7}, $obs->{el8},
            ],
        );
    }
    elsif ($coordstype eq 'FIXED') {
        $coords = Astro::Coords->new(
            name => $obs->{'target'},
            az => $obs->{ra2000},
            el => $obs->{dec2000},
            units => 'radians',
        );

    }
    elsif ($coordstype eq 'TLE' or $coordstype eq 'AUTO-TLE') {
        # Check for NULL TLE elements.  This should only happen for
        # AUTO-TLE before the elements have been inserted, but we might
        # as well do this check for regular TLE elements too.
        if (grep {not defined $obs->{$_}} qw/el1 el2 el3 el4 el5 el6 el7 el8/) {
            # If the elements haven't been inserted, assume that we just
            # don't have them, and so the target is unobservable.
            return undef;
        }

        $coords = OMP::DB::TLE->tle_row_to_coord($obs);
    }
    else {
        throw OMP::Error::FatalError('Unknown coordinate type: ' . $coordstype);
    }

    # throw if we have a problem
    throw OMP::Error::FatalError(
        'Major problem generating coordinate object from ' . Dumper($obs))
        unless defined $coords;

    return $coords;
}

=item B<_msb_row_to_msb_object>

Convert a row hash from the C<ompmsb> table into an OMP::Info::MSB
object.

    @objects = $msb->_msb_row_to_msb_object(@rows);

The rows must be supplied as references to the row hash.
If the hash includes a key "observations" containing an
array of observation information, those are converted to
OMP::Info::Obs objects.

=cut

sub _msb_row_to_msb_object {
    my $self = shift;
    my @observable = @_;

    my $t0 = [gettimeofday];

    # Now fix up the site quality entries so that they
    # are OMP::Range objects rather than max and min
    for my $msb (@observable) {
        # For old table design, we promote cloud and moon (without min/max)
        # cloud fix up for old usage
        # It is probably cleaner to adjust from_db() so that it
        # recognizes an old style number for cloud or moon
        if (exists $msb->{cloud}) {
            my $range = OMP::SiteQuality::upgrade_cloud($msb->{cloud});
            $msb->{cloudmin} = $range->min;
            $msb->{cloudmax} = $range->max;
            delete $msb->{cloud};
        }
        if (exists $msb->{moon}) {
            my $range = OMP::SiteQuality::upgrade_moon($msb->{moon});
            $msb->{moonmin} = $range->min;
            $msb->{moonmax} = $range->max;
            delete $msb->{moon};
        }

        # loop over each xxxmin xxxmax component
        for my $key (qw/tau seeing cloud sky moon/) {
            # Determine the key names
            my $maxkey = $key . "max";
            my $minkey = $key . "min";

            # convert to range object
            $msb->{$key} = OMP::SiteQuality::from_db(
                $key, $msb->{$minkey}, $msb->{$maxkey});

            # ensure that we have the correct handling in case some nulls
            # crept into the table
            OMP::SiteQuality::undef_to_default($key, $msb->{$key});

            # Remove old entries from hash
            delete $msb->{$maxkey};
            delete $msb->{$minkey};

            # inverted range is bad news
            $msb->{$key} = undef if $msb->{$key}->isinverted;
        }

        # Fix up date objects - should be OMP::Range
        for (qw/datemax datemin/) {
            $msb->{$_} = OMP::DateTools->parse_date($msb->{$_});
        }

        # Now convert Observations to OMP::Info::Obs objects
        if (exists $msb->{observations}) {
            for my $obs (@{$msb->{observations}}) {
                $obs = OMP::Info::Obs->new(%$obs);
            }
        }

        # Now convert the hashes to OMP::Info objects
        $msb = OMP::Info::MSB->new(%$msb);

        # Change INTERP coordstypes to RADEC because interpolated
        # coordinates do not appear in the database -- they are only
        # present because they have been used to represent apparent
        # RA and Dec.  Since the list is 'compressed' we should only
        # need to replace one instance, not globally.
        my $coordstype = $msb->coordstype();
        $coordstype =~ s/INTERP/RADEC/;
        $msb->coordstype($coordstype);
    }

    my $t1 = [gettimeofday];
    OMP::General->log_message(
        "Row converted to objects: " . tv_interval($t0, $t1) . " seconds\n",
        OMP__LOG_DEBUG);
    $t0 = $t1;

    return @observable;
}

=back

=head2 Done table

=over 4

=item B<_notify_msb_done>

Send a message to the MSB done system so that the message can be
stored in the done table.

    $self->_notify_msb_done(
        $checksum, $projectid, $msb,
        "MSB retrieved from DB",
        OMP__DONE_FETCH,
        $user);

The arguments are:

=over 4

=item checksum

MSB checksum (determined from msb if undef).

=item projectid

Associated project ID (determined from object if undef).

=item msb

The MSB object. (optional)

=item message

The required message.

=item status

The type of message (see OMP::Constants).

=item user

OMP::User object. [optional]

=item msbtid

MSB transaction ID. [optional]

=back

This is a thin wrapper around C<OMP::DB::MSBDone::addMSBcomment>.

Alternatively, the comment information can be supplied in the form
of an OMP::Info::Comment object. The arguments would then be:

=over 4

=item checksum

=item projectid

=item msb (can be undef)

=item comment object

=back

The caller is responsible for configuring the comment object so that it
includes a valid status.

=cut

sub _notify_msb_done {
    my $self = shift;
    my ($checksum, $projectid, $msb, $text, $status, $user, $msbtid) = @_;

    $projectid = $self->projectid
        unless defined $projectid;

    my $done = OMP::DB::MSBDone->new(
        ProjectID => $projectid,
        DB => $self->db);

    # If we have an msb object, get the info object
    # else just have the checksum
    my $info = ($msb ? $msb->info() : $checksum);

    # if the 'text' argument is already a comment object we do not
    # need to make a comment object
    my $comment;
    if (defined $text && UNIVERSAL::isa($text, "OMP::Info::Comment")) {
        $comment = $text;
    }
    else {
        # Create a comment object
        $comment = OMP::Info::Comment->new(
            text => $text,
            status => $status);

        # Add the author if supplied
        $comment->author($user) if defined $user;

        # Add msbtid if supplied
        $comment->tid($msbtid) if defined $msbtid;
    }

    # Add the comment
    $done->addMSBcomment($info, $comment);
}

=item B<_validate_msb_tid>

Ensure that the supplied MSB transaction ID has been used previously
for this MSB. Throws an exception if it has not.

    $db->_validate_msb_tid($checksum, $msbtid);

=cut

sub _validate_msb_tid {
    my $checksum = shift;
    my $msbtid = shift;

    my $done = OMP::DB::MSBDone->new(DB => self->db);

    my $result = $done->validateMSBTID($checksum, $msbtid);

    return if $result;

    throw OMP::Error::MSBMissingTID(
        "Supplied transaction ID ($msbtid) is not associated with MSB $checksum");
}

=item B<_get_msb_count>

Query the database for the total number of MSBs, and the total number
of active MSBs, for a given list of projects.

    %projectid = $db->_get_msb_count(@projectids);

The only argument is a list (or reference to a list) of project IDs.
Returns a hash of hashes indexed by project ID where the second-level
hashes contain the keys 'total' and 'active' (each points to a number).
If a project has no MSBs, not key is included for that project.  If
a project has no MSBs with remaining observations, no 'active' key
is returned for that project.

=cut

sub _get_msb_count {
    my $self = shift;
    my @projectids = (ref($_[0]) eq 'ARRAY' ? @{$_[0]} : @_);

    return {} unless @projectids;

    # SQL query
    my $sql = "SELECT projectid, COUNT(*) AS \"count\" FROM $OMP::DB::Project::MSBTABLE\n"
        . "WHERE projectid IN ("
        . join(",", map {"\"" . uc($_) . "\""} @projectids)
        . ")\n";

    my $groupby_sql = "GROUP BY projectid";

    my %projectid;
    for my $msbcount (qw/total active/) {
        # Add AND clause to the query if we are looking for active msbs
        my $query = $sql
            . ($msbcount eq 'active'
                ? "AND remaining > 0\n" . $groupby_sql
                : $groupby_sql);

        my $ref = $self->_db_retrieve_data_ashash($query);

        for my $row (@$ref) {
            $projectid{$row->{projectid}}->{$msbcount} = $row->{count};
        }
    }

    return \%projectid;
}

=back

=head1 SUBROUTINES

=over 4

=item stable_fuzzy_sort(\&key, $tolerance, \@array)

Sort array (in place) via (numerical) comparison of the values returned
by the key subroutine applied to each member, with the given tolerance.
Intended to be a stable sort, i.e. the original order is only changed
where necessary.  There are multiple ways in which such an sort could
be performed -- this one works by bringing forward any member which
originally appeared behind a member which was greater by more than the
given tolerance.  To sort in descending order, have the key function
return -1.0 times the actual keys.

=cut

sub stable_fuzzy_sort {
    my $key = shift;
    my $tol = shift;
    my $arr = shift;

    foreach my $i (1 .. $#$arr) {
        for (my $j = 0; $j < $i; $j ++) {
            # Move element $i before element $j if it belongs before it.
            splice @$arr, $j, 0, splice @$arr, $i, 1
                if $key->($arr->[$i]) + $tol < $key->($arr->[$j]);
        }
    }
}


=item _find_msb_tolerant($science_program, $checksum)

Find an MSB in a science program by its checksum, but allow some
tolerance:

=over 4

=item

If the MSB was moved out of an OR folder, a trailing 'O' may have
been removed from the checksum.

=back

=cut

sub _find_msb_tolerant {
    my $sp = shift;
    my $checksum = shift;

    my $msb = $sp->fetchMSB($checksum);

    OMP::General->log_message("MSB Retrieved successfully")
        if $msb;

    unless ($msb) {
        if ($checksum =~ s/O//) {
            OMP::General->log_message("Checking for MSB outside OR folder");

            $msb = $sp->fetchMSB($checksum);

            OMP::General->log_message("MSB found with checksum [$checksum]")
                if $msb;
        }
    }

    OMP::General->log_message("Unable to retrieve corresponding MSB")
        unless $msb;

    return $msb;
}

1;

__END__

=back

=head1 SEE ALSO

This class inherits from C<OMP::DB>.

For related classes see C<OMP::DB::Project> and C<OMP::DB::Feedback>.

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>
Brad Cavanagh E<lt>b.cavanagh@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001-2006 Particle Physics and Astronomy Research Council.
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
