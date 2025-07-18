package OMP::NightRep;

=head1 NAME

OMP::NightRep - Generalized routines to details from a given night

=head1 SYNOPSIS

    use OMP::NightRep;

    $nr = OMP::NightRep->new(
        DB => $database,
        ADB => $archivedb,
        date => '2002-12-18',
        telescope => 'jcmt');

    $obs = $nr->obs;
    $faultgroup = $nr->faults;
    $timelost = $nr->timelost;
    $acct = $nr->accounting;
    $weather = $nr->weatherLoss;

=head1 DESCRIPTION

A high-level wrapper around routines useful for generating nightly
activity reports. Provides a means to obtain details of observations
taken on a night, faults occuring and project accounting.

=cut

use strict;
use warnings;
use Carp;
our $VERSION = '2.000';

use OMP::Error qw/:try/;
use OMP::Constants;
use OMP::General;
use OMP::Query::Archive;
use OMP::Info::Obs;
use OMP::Info::ObsGroup;
use OMP::DB::TimeAcct;
use OMP::Project::TimeAcct::Group;
use OMP::Query::TimeAcct;
use OMP::DB::Shift;
use OMP::Query::Shift;
use OMP::DateTools;
use OMP::DB::Fault;
use OMP::Query::Fault;
use OMP::Fault::Group;
use OMP::DB::MSBDone;
use OMP::Query::MSBDone;
use Time::Piece qw/:override/;
use OMP::Mail;
use OMP::Display;
use OMP::User;

# This is the key used to specify warnings in result hashes
our $WARNKEY = '__WARNINGS__';

=head1 METHODS

=head2 Constructors

=over 4

=item B<new>

Create a new night report object. Accepts a hash argument specifying
the date, delta and telescope to use for all queries.

    $nr = OMP::NightRep->new(
        DB => $database,
        ADB => $archivedb,
        telescope => 'JCMT',
        date => '2002-12-10',
        delta_day => '7',
    );

The date can be specified as a Time::Piece object and the telescope
can be a Astro::Telescope object.  Default delta is 1 day.

=cut

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my %args = @_;

    my $nr = bless {
        DBAccounts => undef,
        HdrAccounts => undef,
        Faults => undef,
        Observations => undef,
        Warnings => [],
        Telescope => undef,
        UTDate => undef,
        UTDateEnd => undef,
        DeltaDay => 1,
        DB => undef,
        ADB => undef,
        PrivateComments => 0,
        MSBsDone => undef,
        },
        $class;

    # Deal with arguments
    if (@_) {
        my %args = @_;

        # rather than populate hash directly use the accessor methods
        # allow for upper cased variants of keys
        for my $key (keys %args) {
            my $method = lc($key);
            if ($nr->can($method)) {
                $nr->$method($args{$key});
            }
        }
    }

    return $nr;
}

=back

=head2 Accessor Methods

=over 4

=item B<date>

Return the date associated with this object. Returns a Time::Piece
object (in UT format).

    $date = $nr->date();
    $nr->date($date);
    $nr->date('2002-12-10');

Accepts a string or a Time::Piece object. The Hours, minutes and seconds
are stripped. The date is assumed to be UT if supplied as a string.
If supplied as an object the local vs UT time can be inferred.

If no date has been specified, the current day will be returned.

If the supplied date can not be parsed as a date, the method will
throw an exception.

=cut

# Defaulting behaviour is dealt with here rather than the constructor
# in case the UT date changes.

sub date {
    my $self = shift;
    if (@_) {
        # parse_date can handle local time
        my $arg = shift;
        my $date = OMP::DateTools->parse_date($arg);

        throw OMP::Error::BadArgs("Unable to parse $arg as a date")
            unless defined $date;

        $self->{UTDate} = $date;
    }

    unless (defined $self->{UTDate}) {
        return OMP::DateTools->today(1);
    }
    else {
        return $self->{UTDate};
    }
}

=item B<date_end>

Return the end date associated with this object. Returns a Time::Piece
object (in UT format).  If the end date is defined, it, rather than
the B<delta_day> value, will be used when generating the night report.

    $date = $nr->date();
    $nr->date($date);
    $nr->date('2002-12-10');

Accepts a string or a Time::Piece object. The Hours, minutes and seconds
are stripped. The date is assumed to be UT if supplied as a string.
If supplied as an object the local vs UT time can be inferred.

If no date has been specified, the undef value will be returned.

If the supplied date can not be parsed as a date, the method will
throw an exception.

=cut

sub date_end {
    my $self = shift;
    if (@_) {
        # parse_date can handle local time
        my $arg = shift;
        my $date = OMP::DateTools->parse_date($arg);

        throw OMP::Error::BadArgs("Unable to parse $arg as a date")
            unless defined $date;

        $self->{UTDateEND} = $date;
    }

    return $self->{UTDateEND};
}

=item B<db_accounts>

Return time accounts from the time accounting database. Time accounts
are represented by an C<OMP::Project::TimeAcct::Group> object.

    $acct = $nr->db_accounts();
    $nr->db_accounts($acct);

Accepts a C<OMP::Project::TimeAcct::Group> object.  Returns undef if no accounts
were retrieved from the time accounting database.

=cut

sub db_accounts {
    my $self = shift;
    if (@_) {
        my $acctgrp = $_[0];

        throw OMP::Error::BadArgs(
            "Accounts must be provided as an OMP::Project::TimeAcct::Group object")
            unless UNIVERSAL::isa($acctgrp, 'OMP::Project::TimeAcct::Group');

        $self->{DBAccounts} = $acctgrp;
    }
    elsif (! defined $self->{DBAccounts}) {
        # No accounts cached.  Retrieve some
        # Database connection
        my $db = OMP::DB::TimeAcct->new(DB => $self->db);

        # Get our sql query
        my $query = OMP::Query::TimeAcct->new(HASH => {
             date => $self->_get_date_hash(timeacct => 1),
             EXPR__TEL => {or => {
                telescope => $self->telescope,
                projectid => {like => $self->telescope . '%'},
            }},
        });

        # Get the time accounting statistics from
        # the TimeAcct table. These are returned as an
        # OMP::Project::TimeAcct::Group object. Note that there will be more than
        # one per project now that there are multiple shift types etc.

        my $acctgrp = $db->queryTimeSpent($query);

        # Store result
        $acctgrp->telescope($self->telescope);

        $self->{DBAccounts} = $acctgrp;
    }

    return $self->{DBAccounts};
}

=item B<delta_day>

Return the delta in days (24 hour periods, really) associated with this object.
If B<date_end> is defined, this delta will not be used when generating the night
report.

    $delta = $nr->delta_day();
    $nr->delta_day(8);

To retrieve a week long summary a delta of 8 would be used since there are
8 24 hour periods in 7 days.

=cut

sub delta_day {
    my $self = shift;

    if (@_) {
        my $arg = shift;

        $self->{DeltaDay} = $arg;
    }

    return $self->{DeltaDay};
}

=item B<faults>

The faults relevant to this telescope and reporting period.  The faults
are represented by an C<OMP::Fault::Group> object.

    $fault_group = $nr->faults;
    $nr->faults($fault_group);

Accepts and returns an C<OMP::Fault::Group> object.

=cut

sub faults {
    my $self = shift;
    if (@_) {
        my $fgroup = $_[0];
        throw OMP::Error::BadArgs(
            "Must provide faults as an OMP::Fault::Group object")
            unless UNIVERSAL::isa($fgroup, 'OMP::Fault::Group');

        $self->{Faults} = $fgroup;
    }
    elsif (! $self->{Faults}) {
        # Retrieve faults from the fault database
        my $fdb = OMP::DB::Fault->new(DB => $self->db);

        my $query = OMP::Query::Fault->new(HASH => {
            EXPR__DT => {or => {
                EXPR__DTF => {and => {
                    # Faults filed on the dates we are reporting for:
                    date => $self->_get_date_hash(),
                    faultdate => {null => 1},
                }},

                # Faults that occurred on the dates we are reporting for:
                faultdate => $self->_get_date_hash(),
            }},
            category => $self->telescope,
            isfault => {boolean => 1},
        });

        $self->{'Faults'} = $fdb->queryFaults(
            $query, no_text => 1, no_projects => 1);
    }

    return $self->{Faults};
}

=item B<hdr_accounts>

Return time accounts derived from the data headers.  Time accounts are
represented by an C<OMP::Project::TimeAcct::Group> object.

    $acctgrp = $nr->hdr_accounts(%options);
    $nr->hdr_accounts($acctgrp);

Accepts an C<OMP::Project::TimeAcct::Group> object.  Returns undef list if no time
accounts could be obtained from the data headers.

=cut

sub hdr_accounts {
    my $self = shift;

    if (1 == scalar @_) {
        my $acctgrp = $_[0];
        throw OMP::Error::BadArgs(
            "Accounts must be provided as an OMP::Project::TimeAcct::Group object")
            unless UNIVERSAL::isa($acctgrp, 'OMP::Project::TimeAcct::Group');

        $self->{HdrAccounts} = $acctgrp;
    }
    elsif (! defined $self->{HdrAccounts}) {
        my %opt = @_;

        # No accounts cached, retrieve some.
        # Get the time accounting statistics from the data headers
        # Need to catch directory not found

        # gets all observations from that night as Omp::Project::TimeAcct
        # objects. These include shifttype and remote.
        my $obsgrp = $self->obs();

        my ($warnings, @acct);
        if ($obsgrp) {
            # locate time gaps > 1 second when calculating statistics.
            $obsgrp->locate_timegaps($self->db, 1);

            # Get one value per shift.
            ($warnings, @acct) = $obsgrp->projectStats(by_shift => 1, %opt);
        }
        else {
            $warnings = [];
        }

        # Store the result
        my $acctgrp = OMP::Project::TimeAcct::Group->new(
            accounts => \@acct,
            telescope => $self->telescope,
            DB => $self->db);
        $self->{HdrAccounts} = $acctgrp;

        # Store warnings
        $self->warnings($warnings);
    }

    return $self->{HdrAccounts};
}

=item B<telescope>

The telescope to be used for all database queries. Stored as a string
but can be supplied as an Astro::Telescope object.

    $tel = $nr->telescope;
    $nr->telescope('JCMT');
    $nr->telescope($tel);

=cut

sub telescope {
    my $self = shift;
    if (@_) {
        my $arg = shift;
        if (UNIVERSAL::isa($arg, "Astro::Telescope")) {
            $arg = $arg->name;
        }
        throw OMP::Error::BadArgs("Bad argument to telescope method: $arg")
            if ref $arg;

        $self->{Telescope} = uc($arg);
    }

    return $self->{Telescope};
}

=item B<db>

A shared database connection (an C<OMP::DB::Backend> object).

    $db = $nr->db;

=cut

sub db {
    my $self = shift;

    if (@_) {
        my $db = shift;
         throw OMP::Error::FatalError(
             'DB must be an OMP::DB::Backend object')
             unless eval {$db->isa('OMP::DB::Backend')};

        $self->{'DB'} = $db;
    }

    return $self->{DB};
}

=item B<adb>

Archive database object.  An instance of C<OMP::DB::Archive>.

=cut

sub adb {
    my $self = shift;

    if (@_) {
        my $adb = shift;
         throw OMP::Error::FatalError(
             'ADB must be an OMP::DB::Archive object')
             unless eval {$adb->isa('OMP::DB::Archive')};

        $self->{'ADB'} = $adb;
    }

    return $self->{'ADB'};
}

=item B<warnings>

Any warnings that were generated as a result of querying the data
headers for time accounting information.

    $warnings = $nr->warnings;
    $nr->warnings(\@warnings);

Accepts an array reference. Returns an array reference.

=cut

sub warnings {
    my $self = shift;

    if (@_) {
        my $warnings = $_[0];
        throw OMP::Error::BadArgs(
            "Warnings must be provided as an array reference")
            unless ref($warnings) eq 'ARRAY';

        $self->{Warnings} = $warnings;
    }

    return $self->{Warnings};
}

=item B<include_private_comments>

Whether to include private comments or not.

=cut

sub include_private_comments {
    my $self = shift;

    if (@_) {
        $self->{'PrivateComments'} = !! shift;
    }

    return $self->{'PrivateComments'};
}

=back

=head2 General Methods

=over 4

=item B<accounting>

Retrieve all the project accounting details for the night as a hash.
The keys are projects and for each project there is a hash containing
keys "DATA" and "DB" indicating whether the information comes from the
data headers or the time accounting database directly.
All accounting details are C<OMP::Project::TimeAcct> objects.

Optionally this can be limited by SHIFTTYPE and by REMOTE status.

Data from the accounting database may or may not be confirmed time.
For data from the data headers the confirmed status is not relevant.

    $details = $nr->accounting(%options);

A special key, "__WARNINGS__" includes any warnings generated by the
accounting query (a reference to an array of strings). See
L<"NOTES">. This key is in the top level hash and is a combination of
all warnings generated.

=cut

sub accounting {
    my $self = shift;
    my %opt = @_;

    # Hash for the results
    my %results = (
        # Get the time accounting info
        DB => $self->accounting_db(),

        # Get the info from the headers
        DATA => $self->accounting_hdr(%opt),
    );

    # Now generate a combined hash
    my %combo;

    # Assume you have data from multiple shifts. Return $combo{SHIFT/wARNINGKEY}{PROJECT}

    for my $src (qw/DB DATA/) {
        for my $shift (keys %{$results{$src}}) {
            # Special case for warnings
            if ($shift eq $WARNKEY) {
                $combo{$WARNKEY} = [] unless exists $combo{$WARNKEY};

                push @{$combo{$WARNKEY}}, @{$results{$src}->{$shift}};
            }
            else {
                for my $proj (keys %{$results{$src}{$shift}}) {
                    # Store the results in the right place
                    $combo{$shift}{$proj}->{$src} =
                        $results{$src}->{$shift}->{$proj};
                }
            }
        }
    }

    return \%combo;
}

=item B<accounting_db>

Return the time accounting database details for each project observed
this night. A hash is returned indexed by project ID and pointing to
the appropriate C<OMP::Project::TimeAcct> object or hash of accounting
information; alternately it can be indexed by shifttype at the top
level then project ID below that.

This is a cut down version of the C<accounting> method that returns
details from all methods of determining project accounting including
estimates.

    $projects = $nr->accounting_db();
    $projects = $nr->accounting_db($data);

This method takes an optional argument determining the return format. Valid formats are:

=over 4

=item byproject

Returns a hash of hashes for each project with the
keys 'pending', 'total' and 'confirmed'.

=item byshftprj

Returns a hash of hashes; primary keys are shifttype,
secondary are projects. Items in them are OMP::Project::TimeAcct objects.

=item byshftremprj

Returns a hash of hashes, primary keys are combo of
shifttype and remote, secondary are project
names. Inside that are OMP::Project::TimeAcct
objects.

=back

(Previously just took an alternate value that if true returns a hash of
hashes for each project with the keys 'pending', 'total' and 'confirmed'
instead of C<OMP::Project::TimeAcct> objects.)

=cut

sub accounting_db {
    my $self = shift;
    my $return_format = shift;

    my $acctgrp = $self->db_accounts;

    if ($return_format) {
        # Returning data
        # Combine Time accounting info for a multiple nights.  See documentation
        # for summary method in OMP::Project::TimeAcct::Group
        return $acctgrp->summary($return_format);
    }

    # Returning objects
    #  Convert to a hash with keys shifttype and project [since we can guarantee one instance of a
    # project for a single UT date and project]
    # Ensure we get separate time accts for each shift.
    my %results;

    for my $acct ($acctgrp->accounts) {
        $results{$acct->shifttype}{$acct->projectid} = $acct;
    }

    return \%results;
}

=item B<accounting_hdr>

Return time accounting statistics generated from the data headers
for this night.

    $details = $nr->accounting_hdr();

Returned as a hash with top level keys of shift types, and second
level keys are project type.

Also returns a reference to an array of warning information generated
by the scan. The keys in the returned hash are project IDs and the
values are C<OMP::Project::TimeAcct> objects. Warnings are returned
as a reference to an array using key "__WARNINGS__" (See L<"NOTES">).

This results in a subset of the information returned by the C<accounting>
method.

=cut

sub accounting_hdr {
    my $self = shift;
    my %opt = @_;

    my $acctgrp = $self->hdr_accounts(%opt);

    my @hdacct = $acctgrp->accounts;
    my $warnings = $self->warnings;

    # Form a hash
    my %shifts;
    if (@hdacct) {
        for my $acct (@hdacct) {
            $shifts{$acct->shifttype}{$acct->projectid} = $acct;
        }
    }
    $shifts{$WARNKEY} = $warnings;

    return \%shifts;
}

=item B<ecTime>

Return the time spent on E&C projects during this reporting period for
this telescope.  That's time spent observing projects associated with
the E&C queue and during non-extended time.

    my $time = $nr->ecTime();

Returns a C<Time::Seconds> object.

=cut

sub ecTime {
    my $self = shift;
    my $dbacct = $self->db_accounts;

    return $dbacct->ec_time;
}

=item B<shutdownTime>

Return the time spent closed, planned or otherwise, during this reporting period
for this telescope.

    my $time = $nr->shutdownTime();

Returns a C<Time::Seconds> object.

=cut

sub shutdownTime {
    my $self = shift;
    my $dbacct = $self->db_accounts;

    return $dbacct->shutdown_time;
}

=item B<obs>

The observation details relevant to this telescope, night and
UT date. This will include time gaps.

Information is given or returned as an C<OMP::Info::ObsGroup> object.

=cut

sub obs {
    my $self = shift;

    if (@_) {
        my $grp = shift;
        throw OMP::Error::BadArgs(
            'Must provide "obs" as an OMP::Info::ObsGroup')
            unless eval {$grp->isa('OMP::Info::ObsGroup')};

        $self->{'Observations'} = $grp;
    }
    elsif (! $self->{'Observations'}) {
        my $query = OMP::Query::Archive->new(HASH => {
            telescope => $self->telescope,
            date => {
                delta => $self->delta_day,
                value => $self->date->ymd,
            },
        });

        # Get observations
        my @obs = $self->adb->queryArc($query, 0, 1);

        my $grp;
        try {
            $grp = OMP::Info::ObsGroup->new(obs => \@obs);
            $grp->commentScan($self->db);
        };

        $self->{'Observations'} = $grp;
    }

    return $self->{'Observations'};
}

=item B<msbs>

Get or retrieve the MSBs observed.

If MSBs were not provided and are not already present, query the C<MSBDone>
database for relevant activity.  MSBs are fetched with all information
for the matching transaction IDs, which can be retrieved individually using
the C<historyMSBtid> method.

=cut

sub msbs {
    my $self = shift;

    if (@_) {
        my $msbs = shift;

        throw OMP::Error::BadArgs(
            'Must provide MSBs as an array of OMP::Info::MSB')
            unless ('ARRAY' eq ref $msbs
                and not grep {not eval {$_->isa('OMP::Info::MSB')}} @$msbs);

        # NOTE: currently stores the reference to the given array.
        $self->{'MSBsDone'} = $msbs;
    }
    elsif (not defined $self->{'MSBsDone'}) {
        my $db = OMP::DB::MSBDone->new(DB => $self->db);

        my %hash = (
            status => [
                OMP__DONE_DONE,
                OMP__DONE_REJECTED,
                OMP__DONE_SUSPENDED,
                OMP__DONE_ABORTED,
            ],
            date => {delta => $self->delta_day, value => $self->date->ymd},
        );

        if (defined $self->telescope) {
            $hash{'telescope'} = $self->telescope;
        }

        my $query = OMP::Query::MSBDone->new(HASH => \%hash);

        # Request "transactions" so that we get any MSBs comments which
        # may have been added on other days.
        $self->{'MSBsDone'} = $db->queryMSBdone($query, {transactions => 1});
    }

    return $self->{'MSBsDone'};
}

=item B<msbs_by_project>

Retrieve MSB information for the night and telescope in question.

Information is returned in a hash indexed by project ID and with
values of C<OMP::Info::MSB> objects.

=cut

sub msbs_by_project {
    my $self = shift;

    # Index by project id
    my %index;
    for my $msb (@{$self->msbs}) {
        my $proj = $msb->projectid;

        $index{$proj} = [] unless exists $index{$proj};

        push @{$index{$proj}}, $msb;
    }

    return \%index;
}

=item B<historyMSBtid>

Retrieve MSB information by transaction ID.  This should be similar
to the C<OMP::DB::MSBDone-E<gt>historyMSBtid> method, but uses the
MSB information (hopefully cached) from this object's C<msbs> method.

    $msb = $self->historyMSBtid($msbtid);

Returns a shallow clone of the original C<OMP::Info::MSB> object with
the comments list replaced with a list containing only those comments
which match the given C<msbtid> value.

=cut

sub historyMSBtid {
    my $self = shift;
    my $tid = shift;
    return undef unless defined $tid;

    foreach my $msb (@{$self->msbs}) {
        my @comments = $msb->msbtid($tid);
        next unless scalar @comments;

        my $copy = $msb->shallow_copy;
        $copy->comments(\@comments);
        return $copy;
    }

    return undef;
}

=item B<scienceTime>

Return the time spent on science during this reporting period for
this telescope.  That's time spent observing projects not
associated with the E&C queue and during non-extended time.

    my $time = $nr->scienceTime();

Returns a C<Time::Seconds> object.

=cut

sub scienceTime {
    my $self = shift;
    my $dbacct = $self->db_accounts;

    return $dbacct->science_time;
}

=item B<shiftComments>

Retrieve all the shift comments associated with this night and
telescope. Entries are retrieved as an hash by date with arrays
of C<OMP::Info::Comment> objects.

    $comments = $nr->shiftComments;

=cut

sub shiftComments {
    my $self = shift;

    my $sdb = OMP::DB::Shift->new(DB => $self->db);

    my $query = OMP::Query::Shift->new(HASH => {
        date => {delta => $self->delta_day, value => $self->date->ymd},
        telescope => $self->telescope,
        ($self->include_private_comments ? (private => {any => 1}) : ()),
    });

    # These will have HTML comments
    my @result = $sdb->getShiftLogs($query);

    # Organize shift comments by date
    my %comments;
    foreach my $c (@result) {
        my $time = gmtime($c->date->epoch);
        push @{$comments{$time->ymd}}, $c;
    }

    return \%comments;
}

=item B<timelost>

Time lost to faults on this night and telescope, organized by type.

    my $timelost = $nr->timelostbyshift;

Returns a reference to as hash with keys "total", "technical" and
"non-technical" giving the time as a C<Time::Seconds> object.

=cut

sub timelost {
    my $self = shift;

    my $faults = $self->faults;

    return {
        total => $faults->timelost,
        technical => $faults->timelostTechnical,
        'non-technical' => $faults->timelostNonTechnical,
    };
}

=item B<timelostbyshift>

Time lost to faults on this night and telescope, organized by shift
and type.

    my $timelost = $nr->timelostbyshift;

Returns a reference to a hash by shift.  Each entry is another
hash with keys "total", "technical" and "non-technical"
giving the time as a C<Time::Seconds> object.

=cut

sub timelostbyshift {
    my $self = shift;

    my $faults = $self->faults->by_shift;
    my %results;

    for my $shift (keys %$faults) {
        my $shiftfaults = $faults->{$shift};

        # The OMP::Fault::Group object should cache the results for the
        # three types of time lost, so call all three methods while
        # we have the "by_shift" group available.
        $results{$shift} = {
            total => $shiftfaults->timelost,
            technical => $shiftfaults->timelostTechnical,
            'non-technical' => $shiftfaults->timelostNonTechnical,
        };
    }

    return \%results;
}

=item B<timeObserved>

Return the time spent observing on this night.  That's everything
but time lost to weather and faults, and time spent doing "other"
things.

    my $time = $nr->timeObserved();

Returns a C<Time::Seconds> object.

=cut

sub timeObserved {
    my $self = shift;
    my $dbacct = $self->db_accounts;

    return $dbacct->observed_time;
}

=item B<totalTime>

Return total for all time accounting information.

    my $time = $nr->totalTime();

Returns a C<Time::Seconds> object.

=cut

sub totalTime {
    my $self = shift;
    my $dbacct = $self->db_accounts;

    return $dbacct->totaltime;
}

=item B<weatherLoss>

Return the time lost to weather during this reporting period for
this telescope.

    my $time = $nr->weatherLoss();

Returns a C<Time::Seconds> object.

=cut

sub weatherLoss {
    my $self = shift;
    my $dbacct = $self->db_accounts;

    return $dbacct->weather_loss;
}

=back

=head2 Summarizing

=over 4

=item B<astext>

Generate a plain text summary of the night.

    $text = $nr->astext;

In scalar context returns a single string. In list context returns
a collection of lines (without newlines).

=cut

sub astext {
    my $self = shift;

    my $tel = $self->telescope;
    my $date = $self->date->ymd;

    # The start
    my $str = "\n\n    Observing Report for $date at the $tel\n\n";

    # TIME ACCOUNTING

    my $time_summary = $self->get_time_summary();

    my @shifts = map {$_->{'shift'}} @{$time_summary->{'shift'}};
    my $shiftcount = scalar @shifts;

    $str .= "There were shift types of ";
    for my $shift (@shifts) {
        $str .= "$shift ";
    }
    $str .= "in this time period\n";
    $str .= "\n\n";
    $str .= "Overall Project Time Summary\n\n";
    my $format = "  %-25s %5.2f hrs   %s\n";

    # Weather and Extended and UNKNOWN and OTHER
    my %text = (
        WEATHER => "Time lost to weather:",
        OTHER => "Other time:",
        EXTENDED => "Extended Time:",
        CAL => "Calibrations:",
    );

    # 1. Get total time overall for all shifts.
    if ($shiftcount > 1) {
        my $info = $time_summary->{'overall'};

        $str .= sprintf "$format", "Time lost to faults:", $info->{'faultloss'}, "";

        foreach my $entry (@{$info->{'special'}}) {
            $str .= sprintf "$format", $text{$entry->{'name'}}, $entry->{'time'};
        }

        for my $country_info (@{$info->{'country'}}) {
            for my $entry (@{$country_info->{'project'}}) {
                $str .= sprintf "$format", $entry->{'project'} . ':', $entry->{'time'};
            }
        }

        if ($info->{'shut'}) {
            $str .= "\n";
            $str .= sprintf $format, "Closed time:", $info->{'shut'}, '';
        }
        $str .= "\n";
        $str .= sprintf $format, "Project time", $info->{'total'}->{'project'}, "";
        $str .= "\n";
        $str .= sprintf $format, "Total time observed:", $info->{'total'}->{'observed'}, "";
        $str .= "\n";
        $str .= sprintf $format, "Total time:", $info->{'total'}->{'total'}, "";
        $str .= "\n";
    }

    # Now get time by shift if there was more than one type of shift.

    foreach my $info (@{$time_summary->{'shift'}}) {
        my $shift = $info->{'shift'};

        if ($shiftcount > 1) {
            $str .= "\n";
            $str .= "$shift summary\n\n";
        }
        if ($info->{'faultloss'}) {
            $str .= sprintf "$format", "Time lost to faults:", $info->{'faultloss'};
        }

        foreach my $entry (@{$info->{'special'}}) {
            $str .= sprintf "$format", $text{$entry->{'name'}}, $entry->{'time'}, $entry->{'comment'}
                if $entry->{'time'} > 0 || defined $entry->{'comment'};
        }

        for my $country_info (@{$info->{'country'}}) {
            for my $entry (@{$country_info->{'project'}}) {
                $str .= sprintf "$format", $entry->{'project'} . ':', $entry->{'time'}, $entry->{'comment'};
            }
        }

        if ($info->{'shut'}) {
            $str .= sprintf $format, "Closed time:", $info->{'shut'};
        }

        $str .= "\n";
        $str .= sprintf $format, "Project time", $info->{'total'}->{'project'};
        $str .= "\n";
        $str .= sprintf $format, "Total time observed:", $info->{'total'}->{'observed'};
        $str .= "\n";
        $str .= sprintf $format, "Total time:", $info->{'total'}->{'total'};
        $str .= "\n";
    }

    # MSB SUMMARY

    # Add MSB summary here
    $str .= "Observation summary\n\n";

    my $msbs = $self->msbs_by_project;

    for my $proj (keys %$msbs) {
        $str .= "  $proj\n";
        for my $msb (@{$msbs->{$proj}}) {
            $str .= sprintf("    %-30s %s    %s",
                    substr($msb->targets, 0, 30),
                    $msb->waveband,
                    $msb->title)
                . "\n";
        }
    }
    $str .= "\n";

    # Fault summary
    my @faults = $self->faults->faults;

    $str .= "Fault Summary\n\n";

    if (@faults) {
        for my $fault (@faults) {
            my $date = $fault->date;
            my $local = localtime($date->epoch);
            $str .= sprintf "  %s [%s] %s (%s hrs lost)\n",
                ($fault->faultid() || '(No Fault ID)'),
                $local->strftime('%H:%M %Z'),
                ($fault->subject() || '(No Subject)'),
                $fault->timelost();
        }
    }
    else {
        $str .= "  No faults filed on this night.\n";
    }

    $str .= "\n";

    # Shift log summary
    $str .= "Comments\n\n";

    my $comments = $self->shiftComments;

    foreach my $k (sort keys %$comments) {
        foreach my $c (@{$comments->{$k}}) {
            # Use local time
            my $date = $c->date;
            my $local = localtime($date->epoch);
            my $author = $c->author() ? $c->author()->name() : '(Unknown Author)';

            # Get the text and format it as plain text from HTML
            my $text = $c->text;
            $text =~ s/\t/ /g;

            $text = OMP::Display->format_text(
                $text, $c->preformatted, width => 72, indent => 4);

            # Now print the timestamped comment
            $str .= "  " . $local->strftime("%H:%M:%S %Z") . ": $author\n";
            $str .= $text . "\n\n";
        }
    }

    # Observation log
    $str .= "Observation Log\n\n";

    my $grp = $self->obs;
    $grp->locate_timegaps($self->db, OMP::Config->getData("timegap"));
    my $tmp = $grp->summary('72col');
    $str .= defined $tmp ? $tmp : '';

    if (wantarray) {
        return split("\n", $str);
    }

    return $str;
}

=item B<get_time_summary>

Prepare summarized time accounting information as required for
printing reports.

Returns a hashref with "overall" and "shift" keys, where "shift"
is an arrayref of entries.  Each entry is of the form:

    {
        shift => $name,  # not present in "overall" entry
        shut => $time,
        faultloss => $time,
        technicalloss => $technicalloss,
        nontechnicalloss => $nontechnicalloss,
        special => [
            # comment undefined in "overall"
            {name => $name, time => $time, pending => $time, comment => $comment},
        ],
        country => [
            country => $country,
            total => $time,
            project => [
                # comment undefined in "overall"
                {project => $project, time => $time, pending => $time, comment => $comment},
            ],
        ],
        total => {
            observed => $time,
            project => $time,
            total => $time,
            pending => $time,
            clear => $time,
        }
    }

Note: this method contains logic extracted from the astext method
and previous ashtml / projectsummary_ashtml methods.

=cut

sub get_time_summary {
    my $self = shift;

    my $acct = $self->accounting_db();
    my $timelostbyshift = $self->timelostbyshift;

    # Get the details of all projects mentioned in the time accounting.
    my $project_details = $self->db_accounts->project_details;

    my @shifts;
    for my $key (keys %$acct) {
        unless (! defined $key || $key eq '' || $key eq $WARNKEY) {
            push @shifts, $key;
        }
    }
    # Only include faultshifts if time was charged.
    for my $shift (keys %$timelostbyshift) {
        my $losttime = $timelostbyshift->{$shift}->{'total'};
        if ((! exists($acct->{$shift})) && ($shift ne '') && ($losttime > 0)) {
            push @shifts, $shift;
        }
    }

    my $overall_info;
    do {
        my $overallresults = $self->accounting_db("byproject");
        my $timelost = $self->timelost;
        $overall_info = $self->_get_time_summary_shift(
            $overallresults,
            undef,
            $timelost->{'total'},
            $timelost->{'technical'},
            $timelost->{'non-technical'},
            $project_details);
    };

    my $shiftresults = $self->accounting_db('byshftprj');
    my @shift_info;
    foreach my $shift (@shifts) {
        my $result = $self->_get_time_summary_shift(
            ($shiftresults->{$shift} // {}),
            ($acct->{$shift} // {}),
            $timelostbyshift->{$shift}->{'total'},
            $timelostbyshift->{$shift}->{'technical'},
            $timelostbyshift->{$shift}->{'non-technical'},
            $project_details);
        $result->{'shift'} = $shift;
        push @shift_info, $result;
    }

    return {
        overall => $overall_info,
        shift => \@shift_info,
    };
}

=item B<get_time_summary_combined>

Prepare summarized time accounting information, as from
C<get_time_summary_combined>, but where the various entries
are organized by shift.

=cut

sub get_time_summary_combined {
    my $self = shift;
    my $time_summary = $self->get_time_summary();
    my $overall = $time_summary->{'overall'};
    my $shifts = $time_summary->{'shift'};

    my @shift_names = map {$_->{'shift'}} @{$shifts};

    my %combined = ();

    # Top-level entries
    foreach my $key (qw/shut faultloss technicalloss nontechnicalloss/) {
        $combined{$key} = {
            overall => $overall->{$key},
            map {$_->{'shift'} => $_->{$key}} @$shifts,
        } if $overall->{$key} || $key ne 'shut';
    }

    # Totals
    foreach my $key (qw/observed project total clear pending/) {
        $combined{'total'}->{$key} = {
            overall => $overall->{'total'}->{$key},
            map {$_->{'shift'} => $_->{'total'}->{$key}} @$shifts,
        };
    }

    # Special categories
    foreach my $entry (@{$overall->{'special'}}) {
        my $name = $entry->{'name'};
        my %combinedentry = (
            name => $name,
            overall => $entry,
        );
        foreach my $shift (@$shifts) {
            foreach my $shiftentry (@{$shift->{'special'}}) {
                if ($shiftentry->{'name'} eq $name) {
                    $combinedentry{$shift->{'shift'}} = $shiftentry;
                    last;
                }
            }
        }
        push @{$combined{'special'}}, \%combinedentry;
    }

    # Country and project
    foreach my $entry (@{$overall->{'country'}}) {
        my $country = $entry->{'country'};
        my %combinedentry = (
            country => $country,
            total => {overall => $entry->{'total'}},
        );

        foreach my $shift (@$shifts) {
            foreach my $shiftentry (@{$shift->{'country'}}) {
                if ($shiftentry->{'country'} eq $country) {
                    $combinedentry{'total'}->{$shift->{'shift'}} = $shiftentry->{'total'};
                    last;
                }
            }
        }

        foreach my $projectentry (@{$entry->{'project'}}) {
            my $project = $projectentry->{'project'};
            my %combinedproject = (
                project => $project,
                overall => $projectentry,
            );
            foreach my $shift (@$shifts) {
                foreach my $shiftentry (@{$shift->{'country'}}) {
                    if ($shiftentry->{'country'} eq $country) {
                        foreach my $shiftprojectentry (@{$shiftentry->{'project'}}) {
                            if ($shiftprojectentry->{'project'} eq $project) {
                                $combinedproject{$shift->{'shift'}} = $shiftprojectentry;
                                last;
                            }
                        }
                        last;
                    }
                }
            }
            push @{$combinedentry{'project'}}, \%combinedproject;
        }

        push @{$combined{'country'}}, \%combinedentry;
    }

    return {
        combined => \%combined,
        shifts => \@shift_names,
    }
}

sub _get_time_summary_shift {
    my ($self, $shiftresults, $shiftacct,
        $timelost, $timelost_technical, $timelost_nontechnical,
        $project_details) = @_;

    my $tel = $self->telescope;

    # Total time
    my $total = 0.0;
    my $totalobserved = 0.0; # Total time spent observing
    my $totalproj = 0.0;
    my $totalpending = 0.0;
    my $faultloss = 0.0;
    my $technicalloss = 0.0;
    my $nontechnicalloss = 0.0;

    if (defined $timelost) {
        $faultloss = $timelost->hours;
        $total += $faultloss;
    }

    if (defined $timelost_technical) {
        $technicalloss = $timelost_technical->hours;
    }

    if (defined $timelost_nontechnical) {
        $nontechnicalloss = $timelost_nontechnical->hours;
    }

    my @special;
    foreach my $proj (qw/WEATHER OTHER EXTENDED CAL/) {
        my $time = 0.0;
        my $pending;
        my $comment;
        if (exists $shiftresults->{$tel.$proj}) {
            $time = $shiftresults->{$tel.$proj}->{'total'}->hours;
            if ($shiftresults->{$tel.$proj}->{'pending'}) {
                $pending = $shiftresults->{$tel.$proj}->{'pending'}->hours;
                $totalpending += $pending;
            }

            $comment = $shiftacct->{$tel.$proj}->comment
                if defined $shiftacct and exists $shiftacct->{$tel.$proj};

            $total += $time unless $proj eq 'EXTENDED';
            $totalobserved += $time unless $proj =~ /^(OTHER|WEATHER)$/;
        }
        push @special, {
            name => $proj,
            time => $time,
            pending => $pending,
            comment => $comment,
        };
    }

    # Sort project accounting by country
    my %proj_by_country;
    for my $proj (keys %$shiftresults) {
        next if $proj =~ /^$tel/;

        my $country = 'UNKNOWN';

        if (exists $project_details->{$proj}) {
            $country = $project_details->{$proj}->country;
        }

        push @{$proj_by_country{$country}}, $proj;
    }

    my @country;
    for my $country (sort keys %proj_by_country) {
        my $country_total = 0.0;
        my @project;
        for my $proj (sort @{$proj_by_country{$country}}) {
            next if $proj =~ /^$tel/;
            my $time = $shiftresults->{$proj}->{'total'}->hours;

            my $pending;
            if ($shiftresults->{$proj}->{'pending'}) {
                $pending = $shiftresults->{$proj}->{'pending'}->hours;
                $totalpending += $pending;
            }

            my $comment;
            $comment = $shiftacct->{$proj}->comment
                if defined $shiftacct and exists $shiftacct->{$proj};

            push @project, {
                project => $proj, time => $time,
                pending => $pending, comment => $comment};

            $country_total += $time;
            $total += $time;
            $totalobserved += $time;
            $totalproj += $time;
        }
        push @country, {
            country => $country,
            project => \@project,
            total => $country_total,
        };
    }

    my $shuttime = 0.0;
    if (exists $shiftresults->{$tel.'_SHUTDOWN'}) {
        my $time = $shiftresults->{$tel.'_SHUTDOWN'}->{'total'}->hours;
        if ($time > 0) {
            $shuttime = $time;
        }
        # Add shutdown time to total
        $total += $time;
    }

    # Get clear time
    my $cleartime = $total - $shuttime;
    $cleartime -= $shiftresults->{$tel.'WEATHER'}->{'total'}->hours
        if exists $shiftresults->{$tel.'WEATHER'};

    return {
        shut => $shuttime,
        faultloss => $faultloss,
        technicalloss => $technicalloss,
        nontechnicalloss => $nontechnicalloss,
        special => \@special,
        country => \@country,
        total => {
            project => $totalproj,
            observed => $totalobserved,
            total => $total,
            pending => $totalpending,
            clear => $cleartime,
        },
    };
}

=item B<get_obs_summary>

Prepare summarized observation information as required for
printing a table of observations.

    my $summary = $nr->get_obs_summary(%options);

L<%options> is a hash optionally containing the
following keys:

=over 4

=item *

obsgroup - An OMP::Info::ObsGroup to use, otherwise will be obtained
from C<$self-E<gt>obs>.  This must be provided if this routine is
called as a class method.

=item *

ascending - Boolean on if observations should be printed in
chronologically ascending or descending order [true].

=item *

sort - Determines the order in which observations are displayed.
If set to 'chronological', then the observations in the given
C<Info::ObsGroup> object will be displayed in chronological order,
with table breaks occurring whenever an instrument changes. If
set to 'instrument', then one table will be displayed for each
instrument in the C<Info::ObsGroup> object, regardless of the order
in which observations for those instruments were taken. Defaults
to 'chronological'.

=back

=cut

sub get_obs_summary {
    my $self = shift;
    my %options = @_;

    my $obsgroup;
    if (exists $options{'obsgroup'}) {
        $obsgroup = $options{'obsgroup'};
    }
    else {
        $obsgroup = $self->obs();
        $obsgroup->locate_timegaps($self->db, OMP::Config->getData('timegap'));
    }

    my $sort;
    if (exists($options{sort})) {
        if ($options{sort} =~ /^chronological/i) {
            $sort = 'chronological';
        }
        else {
            $sort = 'instrument';
        }
    }
    else {
        $sort = 'chronological';
    }

    my $ascending;
    if (exists($options{ascending})) {
        $ascending = $options{ascending};
    }
    else {
        $ascending = 1;
    }

    my $instrument;
    if (exists($options{instrument})) {
        $instrument = $options{instrument};
    }
    else {
        $instrument = '';
    }

    my @allobs;

    # Make the array of Obs objects.
    if ($sort eq 'instrument') {
        my %grouped = $obsgroup->groupby('instrument');

        foreach my $inst (sort keys %grouped) {
            my @obs;
            if ($ascending) {
                @obs = sort {$a->startobs->epoch <=> $b->startobs->epoch}
                    $grouped{$inst}->obs;
            }
            else {
                @obs = sort {$b->startobs->epoch <=> $b->startobs->epoch}
                    $grouped{$inst}->obs;
            }
            push @allobs, @obs;
        }
    }
    else {
        if ($ascending) {
            @allobs = sort {$a->startobs->epoch <=> $b->startobs->epoch}
                $obsgroup->obs;
        }
        else {
            @allobs = sort {$b->startobs->epoch <=> $a->startobs->epoch}
                $obsgroup->obs;
        }
    }

    unless (@allobs) {
        return undef;
    }

    my %result = (
        block => [],
        status_order => \@OMP::Info::Obs::status_order,
        status_class => \%OMP::Info::Obs::status_class,
        status_label => \%OMP::Info::Obs::status_label,
    );

    my $currentinst = undef;
    my $currentblock = undef;

    my $old_sum = '';
    my $old_tid = '';

    foreach my $obs (@allobs) {
        next
            if (length($instrument . '') > 0)
            && (uc($instrument) ne uc($obs->instrument));

        unless ((defined $currentblock)
                and ($currentinst eq uc $obs->instrument)) {
            $currentinst = uc $obs->instrument;
            push @{$result{'block'}}, $currentblock = {
                instrument => $currentinst,
                ut => $obs->startobs->ymd,
                telescope => $obs->telescope,
                obs => [],
            };
        }

        my %nightlog = $obs->nightlog;
        my $is_time_gap = eval {$obs->isa('OMP::Info::Obs::TimeGap')};

        my $endpoint = $is_time_gap
            ? $obs->endobs
            : $obs->startobs;

        my %entry = (
            is_time_gap => $is_time_gap,
            obs => $obs,
            obsut => (join '-', map {$endpoint->$_} qw/ymd hour minute second/),
            nightlog => \%nightlog,
        );

        unless ($is_time_gap) {
            unless (exists $currentblock->{'heading'}) {
                $currentblock->{'heading'} = \%nightlog;
            }

            # In case msbtid column is missing or has no value (calibration), use checksum.
            my $checksum = $obs->checksum;
            my $msbtid = $obs->msbtid;

            my $has_msbtid = defined $msbtid && length $msbtid;

            my ($is_new_msbtid, $is_new_checksum);

            if ($has_msbtid) {
                $is_new_msbtid = $msbtid ne ''
                    && $msbtid ne $old_tid;

                $old_tid = $msbtid if $is_new_msbtid;

                # Reset to later handle case of 'calibration' since sum 'CAL' never
                # changes.
                $old_sum = '';
            }
            else {
                $is_new_checksum = ! ($old_sum eq $checksum);

                $old_sum = $checksum if $is_new_checksum;
            }

            # If the current MSB differs from the MSB to which this observation belongs,
            # we need to insert as the start of the MSB. Ignore blank MSBTIDS.
            if ($checksum && ($is_new_msbtid || $is_new_checksum)) {
                # Get any activity associated with this MSB accept.
                my $history;
                if ($has_msbtid) {
                    $history = $self->historyMSBtid($msbtid);
                }

                if (defined $history) {
                    my $title = $history->title();
                    undef $title unless 2 < length $title;
                    $entry{'msb_comments'} = {
                        title => $title,
                        comments => [
                            grep {
                                my $text = $_->text();
                                defined $text && length $text;
                            } $history->comments()
                        ],
                    };
                }
            }
        }

        push @{$currentblock->{'obs'}}, \%entry;
    }

    return \%result;
}

=item B<mail_report>

Mail a text version of the report to the relevant mailing list.

    $nr->mail_report();

An optional argument can be used to specify the details of the person
filing the report. Supplied as an OMP::User object. Defaults to
flex if no argument is specified.

=cut

sub mail_report {
    my $self = shift;
    my $user = shift;

    # Get the mailing list
    my @mailaddr = map {
        OMP::User->new(email => $_)
    } OMP::Config->getData(
        'nightrepemail', telescope => $self->telescope);

    # Should CC observers

    # Get the text
    my $report = $self->astext;

    # Who is filing this report (need the email address)
    my $from;
    if (defined $user && defined $user->email) {
        $from = $user;
    }
    else {
        $from = OMP::User->get_flex();
    }

    # and mail it
    my $mailer = OMP::Mail->new();
    my $message = $mailer->build(
        to => \@mailaddr,
        from => $from,
        subject => 'OBS REPORT: ' . $self->date->ymd . ' at the ' . $self->telescope,
        message => $report,
    );
    $mailer->send($message);
}

=back

=head2 Internal Methods

=over 4

=item B<_get_date_hash>

Return the date portion of a query hash.

    $hashpart = $self->_get_date_hash(timeacct => 1);

Arguments are provided in hash form.  If the 'timeacct' key points to a true value,
the query will adjust the delta so that it returns only the correct time accounts.

=cut

sub _get_date_hash {
    my $self = shift;
    my %args = @_;
    my $tag = (defined $args{tag} ? $args{tag} : "date");

    if ($self->date_end) {
        return {
            min => $self->date->ymd,
            max => $self->date_end->ymd,
        };
    }
    else {
        # Use the delta
        # Subtract 1 day from the delta (if we are doing time account query
        # since the time accouting table stores dates with times as 00:00:00
        # and we'll end up getting more back than we expected.
        my $delta = $self->delta_day;

        $delta -= 1
            if (defined $args{timeacct});

        return {
            delta => $delta,
            value => $self->date->ymd,
        };
    }
}

1;

__END__

=back

=head1 NOTES

The key used for warnings from results hashes (eg the C<accounting>
method) can be retrieved in global variable C<$OMP::NightRep::WARNKEY>.

=head1 SEE ALSO

See C<OMP::DB::TimeAcct>, C<OMP::Info::ObsGroup>, C<OMP::DB::Fault>,
C<OMP::DB::Shift>

=head1 COPYRIGHT

Copyright (C) 2002-2003 Particle Physics and Astronomy Research
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

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>,
Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>

=cut
