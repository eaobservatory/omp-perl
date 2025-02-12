package OMP::Info::ObsGroup;

=head1 NAME

OMP::Info::ObsGroup - General manipulations of groups of Info::Obs objects

=head1 SYNOPSIS

    use OMP::Info::ObsGroup;

    $grp = OMP::Info::ObsGroup->new(obs => \@obs);

    $grp = OMP::Info::ObsGroup->new(
        DB => $db,
        ADB => $archivedb,
        instrument => 'SCUBA',
        date => '1999-08-15');

    $grp = OMP::Info::ObsGroup->new(
        DB => $db,
        ADB => $archivedb,
        instrument => 'SCUBA',
        projectid => 'm02ac46');

    $grp->obs(@obs);
    @obs = $grp->obs;

    $grp->runQuery($db, $archivedb, $query);
    $grp->populate(
        DB => $db,
        ADB => $archivedb,
        instrument => 'SCUBA',
        projectid => 'M02BU52');

    %summary = $grp->stats;
    $html = $grp->format('html');

    %grouping = $grp->groupby('msbid');
    %grouping = $grp->groupby('instrument');

    # retrieve OMP::Info::MSB objects
    @msbs = $grp->getMSBs;

=head1 DESCRIPTION

This class is a place for general purpose methods that can
dela with groups of observations (as OMP::Info::Obs objects). Including
retrieval of observations for particular dates and obtaining
statistical information and summary from groups of observations.

=cut

use 5.006;
use strict;
use warnings;
use OMP::Constants qw/:timegap :obs/;
use OMP::DateTools;
use OMP::DateSun;
use OMP::DB::Project;
use OMP::Query::Archive;
use OMP::Query::Obslog;
use OMP::DB::Obslog;
use OMP::Info::Obs;
use OMP::Info::Obs::TimeGap;
use OMP::Error qw/:try/;
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
$Data::Dumper::Indent = 1;
$Data::Dumper::Deepcopy = 1;

our $VERSION = 0.02;
our $DEBUG = 0;

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

Object constructor. Accept arguments in hash form with keys:

=over 4

=item obs

Expects to point to array ref of Info::Obs objects.

=item ADB

C<OMP::DB::Archive> object with which to perform query.

=item telescope/instrument/projectid

Arguments recognized by
populate methods are forwarded to the populate method.

=item timegap

Interleaves observations with timegaps if a gap
longer than the value in this hash is detected.

=back

    $grp = OMP::Info::ObsGroup->new(obs => \@obs);

=cut

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my %args = @_;

    my $grp = bless {
        ObsArray => [],
    }, $class;

    # if we have an "obs" arg we just store the objects
    if (exists $args{obs}) {
        $grp->obs($args{obs});
    }
    elsif (@_) {
        # any other args are forwarded to populate
        $grp->populate(%args);
    }

    return $grp;
}

=back

=head2 Accessor Methods

=over 4

=item B<obs>

Retrieve (or set) the array of observations that are to be manipulated
by this class.

    $ref = $grp->obs;
    @obs = $grp->obs;
    $grp->obs(\@obs);
    $grp->obs(@obs);

All elements in the supplied arrays I<must> be of class
C<OMP::Info::Obs> (or subclass thereof).

All previous entries are removed when new observation objects
are stored.

=cut

sub obs {
    my $self = shift;

    if (@_) {
        my @obs;
        # look for ref to array
        if (ref($_[0]) eq 'ARRAY') {
            @obs = @{$_[0]};
        }
        else {
            @obs = @_;
        }

        for (@obs) {
            throw OMP::Error::BadArgs("Observation must be a OMP::Info::Obs")
                unless UNIVERSAL::isa($_, "OMP::Info::Obs");
        }

        @{$self->{ObsArray}} = @obs;
    }

    if (wantarray) {
        return @{$self->{ObsArray}};
    }
    else {
        return $self->{ObsArray};
    }
}

=back

=head2 General Methods

=over 4

=item B<runQuery>

Run a query on the archive (using an OMP::Query::Archive object),
store the results and attach any relevant comments.

    $grp->runQuery($db, $archivedb, $query, $retainhdr, $ignorebad, $nocomments);

Previous observations are overwritten.

=cut

sub runQuery {
    my $self = shift;
    my $db = shift;
    my $adb = shift;
    my $q = shift;
    my $retainhdr = shift;
    my $ignorebad = shift;
    my $nocomments = shift;
    my $search = shift;

    throw OMP::Error::FatalError(
        'runQuery: The DB argument must be an OMP::DB::Backend object')
        unless eval {$db->isa('OMP::DB::Backend')};

    throw OMP::Error::FatalError(
        'runQuery: The ADB argument must be an OMP::DB::Archive object')
        unless eval {$adb->isa('OMP::DB::Archive')};

    throw OMP::Error::FatalError(
        "runQuery: The query argument must be an OMP::Query::Archive class")
        unless UNIVERSAL::isa($q, "OMP::Query::Archive");

    unless (defined $retainhdr) {
        $retainhdr = 0;
    }

    unless (defined $ignorebad) {
        $ignorebad = 0;
    }

    if ($search) {
        $adb->set_search_criteria('header_search' => $search) if $search;
        $adb->use_existing_criteria(1);
    }

    my @result = $adb->queryArc($q, $retainhdr, $ignorebad, $search);

    # Store the results
    $self->obs(\@result);

    # Attach comments
    $self->commentScan($db) unless $nocomments;

    return;
}

=item B<numobs>

Returns the number of observations within the group.

    $num = $grp->numobs;

=cut

sub numobs {
    my $self = shift;
    my $obs = $self->obs;
    return scalar(@$obs);
}

=item B<populate>

Retrieve the observation details and associated comments for
the specified instrument and/or UT date and/or project.
The results are stored in the object and retrievable via
the C<obs> method.

    $grp->populate(
        DB => $db,
        ADB => $archivedb,
        instrument => $inst,
        date => $date,
        projectid => $proj,
        retainhdr => 0,
        nocomments => 1,
        ignorebad => 0);

This requires access to the obs log database (C<OMP::DB::Obslog>) and
also C<OMP::DB::Archive>.

UT date can be either "YYYY-MM-DD" string or a Time::Piece
object from which "YYYY-MM-DD" is extracted.

Currently, only one instrument is supported at a time.
This could be modified to support a telescope and/or instrument
in the future with minor tweaks to the calling arguments.

The method will fail if an instrument is not supplied. It will
also fail if one of "date" or "projectid" are not present (otherwise
the query will not be constrained).

Usually called from the constructor.

If a UT date and projectID are supplied then an additional parameter,
"inccal", can be supplied to indicate whether calibrations should be
included along with the project information. Defaults to false.  Only
calibrations from instruments used for the project are returned.  This
means that no observations are returned if no science observations are
taken regardless of the number of calibrations available in the night.

If "timegap" is true then gaps will be included in the observation
group.  Default is to not include them. The size of the gaps is
specfied as the value to "timegap". If "timegap" is false, a "sort"
key can be used to indicate whether the observations should be sorted
by time order ("sort" is always true when timegaps are calculated).
If "sort" is false and inccal is true, the observations will be sorted
such that the calibrations appear before the science observations
in the list.

If the "retainhdr" value is true (1), then the FITS header will be
retained in each individual OMP::Info::Obs object. Otherwise, the
header will not be retained. This defaults to false (0).

If the "ignorebad" value is true (1), then any files that cannot be
read to form an OMP::Info::Obs object will be skipped. Otherwise,
reading these files will cause an error to be thrown. This defaults to
false (0).

If "nocomments" is true, observation comments will not be automatically
associated with the C<OMP::Info::Obs> objects. Default is false (0);
comments will be attached, for queries with bound dates and true
(no comments) by default for project queries or unbound date
queries. This can be overridden by using an explicit (defined) value
for "nocomments".  If "incjunk" is false, then junk observations
are excluded.  Comments will be retrieved in this case in order
for status to be determined.

A "message_sink" subroutine reference can be provided, and will be
used to report informational messages.

=cut

sub populate {
    my $self = shift;
    my %def = (message_sink => undef, sort => 1);
    my %args = (%def, @_);

    my $retainhdr = 0;
    if (exists $args{retainhdr} ) {
        $retainhdr = $args{retainhdr};
        delete $args{retainhdr};
    }

    my $ignorebad = 0;
    if (exists $args{ignorebad} ) {
        $ignorebad = $args{ignorebad};
        delete $args{ignorebad};
    }

    my $nocomments;
    if (exists $args{nocomments} ) {
        $nocomments = $args{nocomments};
        delete $args{nocomments};
    }

    my $search;
    for ('header_search') {
        $search = delete $args{$_}
            if exists $args{$_};
    }

    throw OMP::Error::BadArgs(
        "Must supply a telescope or instrument or projectid")
        unless exists $args{telescope}
            || exists $args{instrument}
            || exists $args{projectid};

    # if we have a date it could be either object or string
    my %hash;
    if (exists $args{date}) {
        if (ref($args{date})) {
            $args{date} = $args{date}->strftime("%Y-%m-%d");
        }
        $hash{'date'} = {delta => 1, value => "$args{date}"};
    }
    elsif (exists($args{'daterange'})) {
        my $daterange = $args{'daterange'};
        my %datehash;
        if (defined($daterange->min)) {
            $datehash{'min'} = $daterange->min->datetime;
        }
        if (defined($daterange->max)) {
            $datehash{'max'} = $daterange->max->datetime;
        }
        $hash{'date'} = \%datehash;
        # If the range is unbounded, disable comment lookup unless it was
        # specified explicitly.
        unless ($daterange->isbound) {
            $nocomments = 1 unless defined $nocomments;
        }
    }

    # If we have a project ID but no telescope we must determine
    # the telescope from the database
    if (exists $args{projectid} && ! exists $args{telescope}) {
        $args{telescope} = OMP::DB::Project->new(
            DB => $args{'DB'},
            ProjectID => $args{projectid})->getTelescope();
    }
    elsif (exists $args{instrument} && $args{instrument} =~ /^ACSIS/i) {
        $args{telescope} = 'JCMT';
    }

    # List of interesting keys for the query
    my @keys = qw/telescope/;

    # Calibrations?
    # If we have both a UT date and projectID we should look
    # for inccal. If it is true we need to modify the query so that
    # it does not include a projectid by default.
    my $inccal;
    if (exists $args{projectid}
            && exists $args{date}
            && exists $args{inccal}) {
        $inccal = $args{inccal};
    }

    # If we've been given a project ID but no dates, get all
    # observations from the beginning of time for that project. Disable
    # comment lookups for this case though unless we are explicitly
    # told otherwise
    if (exists($args{'projectid'})
            && ! (exists($args{'date'}) || exists($args{'daterange'}))) {
        $hash{'date'} = {min => '20000101'};
        $nocomments = 1 unless defined $nocomments;
    }

    # Junk?  If we want to exclude this, we need to ensure comments are enabled.
    my $incjunk = 1;
    if (exists $args{'incjunk'}) {
        $incjunk = $args{'incjunk'};
        if ($nocomments and not $incjunk) {
            warn "OMP::Info::ObsGroup: must fetch comments to exclude junk";
            $nocomments = 0;
        }
    }

    # if we are including calibrations we should not include projectid
    unless ($inccal) {
        push @keys, "projectid";
    }

    # Expand out and remap heterodyne instruments.
    if (exists $args{instrument}) {
        # Old GSD in jcmt_tms.SCA table has "rxa3i", converted GSD data in
        # jcmt.COMMON has "RXA3".
        my @instrument;
        my @rxa3 = qw/rxa3i rxa3/;

        if ($args{instrument} =~ /^rxa/i) {
            push @instrument, @rxa3;
        }
        elsif ($args{instrument} =~ /^rxb/i) {
            push @instrument, 'rxb';
        }
        elsif ($args{instrument} =~ /^rxw/i) {
            push @instrument ,'rxw';
        }
        elsif ($args{instrument} =~ /^heterodyne/i) {
            push @instrument, @rxa3, qw/rxb rxw/;
        }
        else {
            push @instrument, $args{instrument};
        }

        $hash{'instrument'} = \@instrument;
    }

    # Form the hash. [restrict the keys]
    for my $key (@keys) {
        if (exists $args{$key} && defined $args{$key}) {
            $hash{$key} = "$args{$key}";
        }
    }

    # Form the query.
    my $arcquery = OMP::Query::Archive->new(HASH => \%hash);

    # run the query
    $self->runQuery($args{'DB'}, $args{'ADB'}, $arcquery, $retainhdr, $ignorebad, $nocomments, $search);

    # Apply filter (with "message_sink" if desired to generate message output).
    my %filter_args = (
        sort => (exists $args{timegap} && $args{timegap} ? 0 : $args{sort}),
        incjunk => $incjunk,
        message_sink => $args{'message_sink'},
    );

    # If we are really looking for a single project plus calibrations we
    # have to massage the entries removing other science observations.
    # and instruments that are not important to the project
    if ($inccal && exists $args{projectid}) {
        $filter_args{'projectid'} = $args{projectid};
        $filter_args{'inccal'} = $inccal;
    }
    else {
        $filter_args{'anycal'} = 1;
    }

    $self->filter(%filter_args);

    # Add in timegaps if necessary (not forgetting to sort if asked)
    if (exists $args{timegap}) {
        $self->locate_timegaps($args{'DB'}, $args{timegap});
    }
    elsif ($args{sort}) {
        $self->sort_by_time();
    }
}

=item B<filter>

Filter the current observation list using the rules specified
in the arguments. Observations that do not match the filter
are removed.

If a projectid is specified, only science observations and relevant
calibrations associated with that particular project are retained
(which may be an empty list if no projects observations are present).

    $grp->filter(projectid => $projectid);
    $grp->filter(inccal => 0);

The inccal flag can be used to control the filter. By default, inccal
is true. If inccal is true, calibrations will be included for each
science observation. If inccal is false, calibrations will be removed
from the observation list even if they are tagged as belonging to the
project. However if anycal is true, calibrations will be included
provided they match the other filtering criteria, with no special
treatment. If incjunk is false, junk observations will be removed.

    $grp->filter(projectid => $projectid, inccal => 1);

A "sort" key, indicates whether the observations should be sorted
by time of observations (default=1) or whether all calibrations
observations should be listed before science observations (false).
The latter is useful for pipelining.

A "message_sink" key can be used to provide a subroutine to handle
informational messages.

    $grp->filter(projectid => $projectid, message_sink => sub {...});

=cut

sub filter {
    my $self = shift;
    my %def = (inccal => 1, incjunk => 1, sort => 1, anycal => 0);
    my %args = (%def, @_);

    # Upper case now rather than inside loop
    my $projectid = (exists $args{'projectid'})
        ? uc($args{'projectid'})
        : undef;
    my $inccal = $args{'inccal'};
    my $incjunk = $args{'incjunk'};
    my $anycal = $args{'anycal'};

    # Disable 'inccal' if 'anycal' is specified.
    $inccal = 0 if $anycal;

    if ($inccal) {
        # Sort everything first so that we get the science and calibration
        # observations themselves in time order
        $self->sort_by_time;
    }

    # Step one is to go through all the observations, extracting
    # the science observations associated with this project
    # and generating an array of calibration observations and matching
    # instruments
    my @proj;    # All the science observations
    my @cal;     # Calibration observations

    my %instruments;    # List of all science instruments
    my %obsmodes;       # List of all observing modes
    my %calinst;        # List of all calibration instruments

    for my $obs ($self->obs) {
        next unless $incjunk or $obs->status() != OMP__OBS_JUNK;

        my $obsmode = $obs->mode || $obs->type;

        if ($anycal or $obs->isScience) {
            if ((not defined $projectid) or (uc($obs->projectid) eq $projectid)) {
                $instruments{uc $obs->instrument} ++; # Keep track of instrument
                $obsmodes{$obsmode} ++;               # Keep track of obsmode
                $args{'message_sink'}->("SCIENCE:     "
                        . $obs->instrument . "/" . $obsmode
                        . " [" . $obs->target . "]")
                    if $args{'message_sink'};
                push @proj, $obs;
            }
        }
        elsif ($inccal) {
            $calinst{uc $obs->instrument} ++;    # Keep track of cal instrument
            push @cal, $obs;
        }
    }

    unless ($inccal) {
        $self->obs(\@proj);
    }
    else {
        # Now prune calibrations to remove uninteresting instruments
        # Note: cal array will be empty if we didn't find any science observations;
        # for this reason we store the number of cals before we filter so that we
        # can compare against the number later
        my $ncal = scalar(@cal);
        if (scalar(keys %instruments) == 0) {
            # Don't waste time filtering if we know we aren't going to match anything
            @cal = ();
        }
        else {
            # First we want to make sure that we select out only the instruments we need
            my $match = join("|", keys %instruments);
            @cal = grep {$_->instrument =~ /^$match$/i} @cal;

            # Now we want to make sure that we only keep calibrations that are vaguely of
            # interest to us either because
            #   - They have a matching project ID regardless of mode
            #   - They are a generic calibration
            #   - They are a SciCal that uses the same observing mode as us
            $match = join '|', keys %obsmodes;
            @cal = grep {
                my $obsmode = $_->mode || $_->type;
                uc($_->projectid) eq $projectid
                    || $_->isGenCal
                    || $obsmode =~ /^$match/i
            } @cal;
        }

        # And log calibration matches
        # since we do not want to list a whole load of pointless calibrations
        if ($args{'message_sink'}) {
            for my $obs (@cal) {
                my $obsmode = $obs->mode || $obs->type;
                $args{'message_sink'}->("CALIBRATION: "
                        . $obs->instrument . "/" . $obsmode
                        . " [" . $obs->target . "]");
            }
        }

        # warn if we have cals but no science
        if ($args{'message_sink'} && scalar(@proj) == 0 && $ncal > 0) {
            my $instlist = join(",", keys %calinst);
            my $plural = (keys %calinst > 1 ? "s" : "");
            $args{'message_sink'}->(
                "This request matched calibrations but no science observations (calibrations for instrument$plural $instlist)...");
        }

        # Store
        $self->obs([@proj, @cal]);
    }

    # Sort into time order if applicable
    $self->sort_by_time() if $args{sort};

    return;
}

=item B<sort_by_time>

Sort the observations in the group into time order.

    $grp->sort_by_time;

=cut

sub sort_by_time {
    my $self = shift;

    my @obs = sort {$a->startobs <=> $b->startobs} $self->obs;

    $self->obs(\@obs);

    return;
}

=item B<commentScan>

Ensure that the comments stored in the observations are up-to-date.

    $grp->commentScan($db);

=cut

sub commentScan {
    my $self = shift;
    my $db = shift;

    throw OMP::Error::FatalError(
        'commentScan: The DB argument must be an OMP::DB::Backend object')
        unless eval {$db->isa('OMP::DB::Backend')};

    # Add the comments.
    my $odb = OMP::DB::Obslog->new(DB => $db);

    $odb->updateObsComment(scalar $self->obs);

    return;
}

=item B<projectStats>

Return an array of C<Project::TimeAcct> objects for the given
C<ObsGroup> object and associated warnings.

    my ($warnings, @timeacct) = $obsgroup->projectStats(%options);

This method will determine all the projects in the given
C<ObsGroup> object, then use time allocations in that object
to populate the C<Project::TimeAcct> objects.

The first argument returned is an array of warning messages generated
by the time accounting tool. Usually these will indicate calibrations
that are not required by any science observations, or science
observations that have no corresponding calibration.

Observations taken outside the normal observing periods
are not charged to any particular project but are charged
to project $tel"EXTENDED". This definition of extended time
is telescope dependent.

Does not yet take the observation status (questionable, bad, good)
into account when calculating the statistics. In principal observations
marked as bad should be charged to the general overhead.

Also does not charge for time gaps even if they have been flagged
as WEATHER.

If an observation has a calibration type that matches the project ID
then we assume that the data are self-calibrating rather than
complaining that there is no calibration.

If a time gap associated with an observation is smaller than a certain
threshold (say 5 minutes) then that time is charged to the following
project rather than to OTHER. This will allow us to compensate for
small gaps between data files associated with slewing and tuning.
If a small gap is between calibration observations it is charged
to $telCAL project [they should probably be charged to the project
in proportion to instrument usage but that requires more work].

Options are passed on to the C<projectStatsShared> or C<projectStatsSimple>
method.

=cut

sub projectStats {
    my $self = shift;
    my %opt = @_;

    # Need to determine the telescope to decide which charging
    # scheme is to be used. We assume that the telescope associated
    # with the first observation is the relevant one.
    my @obs = $self->obs;

    # If we do not have any observations we return empty
    return (["No observations for statistics"]) unless @obs;

    my $tel = uc($obs[0]->telescope);
    my $charge_scheme =
        OMP::Config->getData('time_accounting_mode', telescope => $tel);

    if ($charge_scheme =~ /shared/i) {
        print "USING SHARED\n" if $DEBUG;
        return $self->projectStatsShared(%opt);
    }
    else {
        print "USING SIMPLE\n" if $DEBUG;
        return $self->projectStatsSimple(%opt);
    }
}

=item B<projectStatsSimple>

Return an array of C<Project::TimeAcct> objects for the given
C<ObsGroup> object and associated warnings. This implementation
pushes all calibrations and time associated with bad observations
into a calibration project. A science project will only be charged
for its science time. Optionally will divide time accounting by shifttype
or not.

    my ($warnings, @timeacct) = $obsgroup->projectStatsSimple(%options);

This method will determine all the projects in the given
C<ObsGroup> object, then use time allocations in that object
to populate the C<Project::TimeAcct> objects.

Options:

=over 4

=item I<by_shift>

If true, the stats will be produced for each separate shifttype. Else, the key
'ANYSHIFT' will be used in returned the C<Project::TimeAcct> objects, and
only one per night will be produced for each project.

=item I<trace_observations>

Add observation details to the generated time accounting objects.

=back

The first argument returned is an array of warning messages generated
by the time accounting tool. Usually these will indicate calibrations
that are not required by any science observations, or science
observations that have no corresponding calibration.

Observations taken outside the normal observing periods
are not charged to any particular project but are charged
to project $tel"EXTENDED". This definition of extended time
is telescope dependent.

Bad observations are charged to the calibration project.

Also does not charge for time gaps even if they have been flagged
as WEATHER.

If a time gap associated with an observation is smaller than a certain
threshold (say 5 minutes) then that time is charged to the following
project rather than to OTHER. This will allow us to compensate for
small gaps between data files associated with slewing and tuning.
If a small gap is between calibration observations it is charged
to $telCAL project [they should probably be charged to the project
in proportion to instrument usage but that requires more work].

=cut

sub projectStatsSimple {
    my $self = shift;
    my %opt = @_;

    my $by_shift = $opt{'by_shift'} // 0;
    my $trace_observations = $opt{'trace_observations'} // 0;

    my @obs = $self->obs;
    my $numobs = $self->numobs;
    # If we do not have any observations we return empty
    return (["No observations for statistics"])
        unless $numobs > 0;

    # This is the threshold for unspecified gaps
    # Below this threshold we attempt to associate them with the
    # relevant project. Above this threshold we simply charge them
    # to OTHER. This unit is in seconds
    # If this is set to 0, all unallocated gaps will be charged to OTHER
    my $GAP_THRESHOLD = OMP::Config->getData('timegap');

    # We will store all calibrations in a $tel.$CAL_NAME project
    # rather than tracking them in separate hashes.
    my $datesun = OMP::DateSun->new;
    my @warnings;
    my %other;  # Extended time, weather time and OTHER gaps by telescope

    # These are the generic key names for certain cal projects
    my $WEATHER_GAP = "WEATHER";
    my $OTHER_GAP = "OTHER";
    my $CAL_NAME = "CAL";
    my $BAD_OBS = "BADOBS";
    my $EXTENDED_KEY = "EXTENDED";

    # This is a hash indexed by UT and tel shifttype) since we cannot mix them yet)
    # pointing to an array.  This array contains the projects as we
    # encounter them. We use it to make sure we assign small gaps to
    # projects properly. We try to make sure we do not push a project on
    # that is already at the end of the array
    my %gapproj;

    # Keep a list of ALL significant projects. In general this is not
    # much of a problem but is important if we have projects that
    # only consist of calibrations (esp E&C)
    my %sigprojects;

    my %proj_totals;
    my %night_totals;

    # Observation details, if requested via the trace_observations options.
    my %proj_observations;

    # In some cases we need to know the most recent observation
    my $prevobs;

    # Go through all the observations, determining the time spent on
    # each project.
    for my $obs (@obs) {
        my $projectid = $obs->projectid;
        my $tel = uc($obs->telescope);

        my $shifttype;
        if ($by_shift) {
            $shifttype = uc($obs->shifttype);
        }
        else {
            $shifttype = 'ANYSHIFT';
        }
        my $calproj = $tel . $CAL_NAME;
        my $badproj = $tel . $BAD_OBS;
        my $projectid_orig = undef;

        # If we have a TIMEGAP we want to treat it as a special observation
        # that only depends on telescope (like JCMTCAL)
        my $isgap = 0;
        if (UNIVERSAL::isa($obs, "OMP::Info::Obs::TimeGap")) {
            $isgap = 1;

            # The projectid for these things should really be $tel . $type
            # but that is not how these have been implemented so we need to do it ourselves
            # Faults are explicitly calculated elsewhere in the fault system itself
            my $status = $obs->status;

            if ($status == OMP__TIMEGAP_FAULT) {
                # but we include them in the total so that the "length of night" is correct
                my $ymd = $obs->startobs->ymd;
                my $faultlen = $obs->endobs - $obs->startobs;
                $night_totals{$tel}{$ymd}{$shifttype} += $faultlen;
            }

            next if $status == OMP__TIMEGAP_FAULT;

            if ($status == OMP__TIMEGAP_INSTRUMENT
                    || $status == OMP__TIMEGAP_NEXT_PROJECT) {
                # INSTRUMENT and PROJECT gaps are shared amongst the projects. INSTRUMENT
                # gaps are shared by instrument, PROJECT gaps are given to the following
                # project. In both cases we handle it properly in the next section.
                # Simply let the default project ID go through since it will be ignored
                # in a little while.
            }
            elsif ($status == OMP__TIMEGAP_WEATHER) {
                $projectid = $WEATHER_GAP;
            }
            elsif ($status == OMP__TIMEGAP_PREV_PROJECT) {
                # This is time that should be charged to the project
                # preceeding this gap. For now we do not need to do anything
            }
            else {
                $projectid = $OTHER_GAP;
            }
        }

        print "Processing observation from project $projectid (duration "
            . ($obs->endobs - $obs->startobs) . " s)\n"
            if (! $isgap && $DEBUG && $DEBUG > 1);

        # if we have a SCUBA project ID that seems to be a science observation
        # we charge this to projectID JCMTCAL. Clearly SCUBA::ODF should be responsible
        # for this logic but for now we add it here for testing.
        # This should be a rare occurence
        if ($projectid =~ /scuba/i && $obs->isScience) {
            # use JCMTCAL rather than tagging as a calibrator because we don't
            # want other people charged for it
            $projectid = 'JCMTCAL';
        }

        # if this is a calibration observation and not a gap we assign
        # it to the calibration project
        if (! $isgap && ! $obs->isScience) {
            $projectid = $calproj;
        }

        # if somehow we have got a projectid of $CAL_NAME force it to
        # be telescope specific
        $projectid = $calproj
            if $projectid =~ /$CAL_NAME$/;

        my $inst = $obs->instrument;
        my $startobs = $obs->startobs;
        my $endobs = $obs->endobs;
        my $ymd = $obs->startobs->ymd;
        my $timespent;
        my $duration = $obs->duration;

        $sigprojects{$ymd}{$shifttype}{$projectid} ++
            if $projectid !~ /$CAL_NAME$/
            && $projectid !~ /$WEATHER_GAP$/
            && $projectid !~ /$OTHER_GAP$/
            && $projectid !~ /$EXTENDED_KEY$/
            && $projectid !~ /^scuba$/i
            && ! $isgap;

        # if the observation is not a gap and is bad charge it to overhead. What about junk?
        if (! $isgap
                && ($obs->status == OMP__OBS_BAD || $obs->status == OMP__OBS_JUNK)) {
            print "Observation from project $projectid is marked BAD, adding to $badproj\n"
                if $DEBUG;
            $projectid_orig = $projectid;
            $projectid = $badproj;
        }

        # Store the project ID for gap processing
        # In general should make sure we dont get projects that are all calibrations
        unless (exists $gapproj{$ymd}{$tel}{$shifttype}) {
            $gapproj{$ymd}{$tel}{$shifttype} = [];
        }

        # This is the project to store in the gap analysis
        my $gapprojid = $projectid;

        # But we want to make sure that gaps solely between calibration
        # observations are not charged to OTHER when it would be better
        # if they were attached to generic calibration overheadds for the
        # instrument (and apportioned to real data).
        # We therefore must store the instrument as well
        $gapprojid = $calproj if (! $isgap && ! $obs->isScience);

        # Store the array ref with projectid and instrument
        # but only this is the first entry or if we are not repeating
        # the same projectID

        # Always push if we are the first element
        # Also push a projectid on the array if previous isnot an array (ie a gap)
        # OR if the previous project is not the same as the current project
        # We do not want to push a gap onto this array since a gap should be
        # the content [previously we pushed all gaps and then replaced them
        # with the actual gap later on].
        # WARNING: we include $projectid_orig in case this is a bad observation,
        # based on the assumption that we only look at the entry directly after
        # a gap, so that we do not need to check whether this value has changed.
        unless ($isgap) {
            push @{$gapproj{$ymd}{$tel}{$shifttype}}, [$gapprojid, $inst, $projectid_orig]
                if scalar(@{$gapproj{$ymd}{$tel}{$shifttype}}) == 0
                    || (ref($gapproj{$ymd}->{$tel}->{$shifttype}->[-1]) ne 'ARRAY')
                    || (ref($gapproj{$ymd}->{$tel}->{$shifttype}->[-1]) eq 'ARRAY'
                        && $gapproj{$ymd}->{$tel}->{$shifttype}->[-1]->[0] ne $gapprojid);
        }

        # We can calculate extended time so long as we have 2 of startobs, endobs and duration
        if ((defined $startobs && defined $endobs)
                || (defined $startobs && defined $duration)
                || (defined $endobs && defined $duration)) {
            # Get the extended time
            ($timespent, my $extended) = $datesun->determine_extended(
                duration => $duration,
                start => $startobs,
                end => $endobs,
                tel => $tel,
            );

            # And sort out the EXTENDED time UNLESS THIS IS ACTUALLY A TIMEGAP [cannot charge
            # "nothing" to extended observing!]
            # unless the gap is small (less than the threshold)
            # since most people define extended as time from when we really
            # start to when we really end the observing.
            $other{$ymd}{$tel}{$shifttype}{$EXTENDED_KEY} += $extended->seconds
                if defined $extended
                && $extended->seconds > 0
                && (! $isgap || ($isgap && $extended->seconds < $GAP_THRESHOLD));

            # If the duration is negative set it to zero rather than kludging
            # by adding ONE_DAY
            if ($timespent->seconds < 0) {
                $timespent = Time::Seconds->new(0);
            }
        }
        else {
            # We cannot tell whether this was done in extended time or not
            # so assume not.
            $timespent = Time::Seconds->new($obs->duration);
        }

        $night_totals{$tel}{$ymd}{$shifttype} += $timespent->seconds;

        if ($isgap) {
            # Just need to add into the %other hash
            # UNLESS this is an OTHER gap that is smaller than the required threshold
            if ($projectid eq $OTHER_GAP
                    && $timespent->seconds < $GAP_THRESHOLD
                    && $timespent->seconds > 0) {
                # Replace the project entry with a hash pointing to the gap
                # Use a hash ref just to make it easy to spot rather than matching
                # to a digit
                push @{$gapproj{$ymd}->{$tel}->{$shifttype}},
                    {OTHER => $timespent->seconds, OBS => $obs};
            }
            elsif ($obs->status == OMP__TIMEGAP_NEXT_PROJECT) {
                # Always charge PROJECT gaps to the following project (this
                # is the same logic as for short gaps). Keep this separate
                # in case we had different types of accounting (especially
                # if we start to share between previous project or have a POSTPROJECT
                # and PREVPROJECT gap type). In that case will adjust the key here
                # to be PREVIOUS, POST or SHARED
                print "CHARGING " . $timespent->seconds . " TO PROJECT GAP\n"
                    if $DEBUG;

                push @{$gapproj{$ymd}->{$tel}->{$shifttype}},
                    {OTHER => $timespent->seconds, OBS => $obs};
            }
            elsif ($obs->status == OMP__TIMEGAP_PREV_PROJECT) {
                # Must charge the previous project
                print "CHARGING " . $timespent->seconds . " TO PREVIOUS PROJECT\n"
                    if $DEBUG;

                if (defined $prevobs) {
                    my $previnst = $prevobs->instrument;
                    my $prevymd = $prevobs->startobs->ymd;
                    my $prevprojectid = $prevobs->projectid;
                    my $prevtel = uc($prevobs->telescope);
                    my $prevshifttype;

                    if ($by_shift) {
                        $prevshifttype = uc($prevobs->shifttype);
                    }
                    else {
                        $prevshifttype = 'ANYSHIFT';
                    }

                    # This is a horrible hack. Should not be duplicating this code
                    if ($prevobs->isScience) {
                        # Charge to the project
                        $proj_totals{$prevymd}{$prevshifttype}{$prevprojectid}
                            += $timespent->seconds;
                        push @{$proj_observations{$prevymd}{$prevshifttype}{$prevprojectid}}, {
                            obs => $obs,
                            timespent => $timespent->seconds,
                            comment => 'Gap assigned to previous project',
                        } if $trace_observations;
                    }
                    else {
                        $proj_totals{$prevymd}{$prevshifttype}{$calproj}
                            += $timespent->seconds;
                        push @{$proj_observations{$prevymd}{$prevshifttype}{$calproj}}, {
                            obs => $obs,
                            timespent => $timespent->seconds,
                            comment => 'Gap assigned to calibration (previous project not science)',
                        } if $trace_observations;
                    }
                }
            }
            elsif ($obs->status == OMP__TIMEGAP_INSTRUMENT) {
                # Simply treat this as a generic calibration
                print "CHARGING " . $timespent->seconds . " TO INSTRUMENT GAP [$inst]\n"
                    if $DEBUG;

                $proj_totals{$ymd}{$shifttype}{$calproj} += $timespent->seconds;
                push @{$proj_observations{$ymd}{$shifttype}{$calproj}}, {
                    obs => $obs,
                    timespent => $timespent->seconds,
                    comment => 'Gap assigned to calibration (instrument)',
                } if $trace_observations;
            }
            elsif ($timespent->seconds > 0) {
                # Just charge to OTHER [unless we have negative time gap]
                print "CHARGING " . $timespent->seconds . " TO $projectid\n"
                    if $DEBUG;
                $other{$ymd}{$tel}{$shifttype}{$projectid}
                    += $timespent->seconds;
            }
        }
        elsif ($obs->isScience) {
            $proj_totals{$ymd}{$shifttype}{$projectid} += $timespent->seconds;
            push @{$proj_observations{$ymd}{$shifttype}{$projectid}}, {
                obs => $obs,
                timespent => $timespent->seconds,
                comment => 'Observation assigned to project'
                    . (defined $projectid_orig ? " (was $projectid_orig)" : ''),
            } if $trace_observations;
        }
        else {
            $proj_totals{$ymd}{$shifttype}{$calproj} += $timespent->seconds;
            push @{$proj_observations{$ymd}{$shifttype}{$calproj}}, {
                obs => $obs,
                timespent => $timespent->seconds,
                comment => 'Observation assigned to calibration (not science)',
            } if $trace_observations;
        }

        # Log the most recent information
        $prevobs = $obs if ! $isgap;
    }

    if ($DEBUG) {
        if ($DEBUG > 1) {
            print Dumper(\%proj_totals, \%gapproj, \%other);
        }
        else {
            print "Initial Project totals: " . Dumper(\%proj_totals);
        }
    }

    # And any small forgotten leftover time gaps
    # Including charging gaps between calibrations to generic calibrations
    print "Processing gaps:\n" if $DEBUG;

    for my $ymd (keys %gapproj) {
        for my $tel (keys %{$gapproj{$ymd}}) {
            for my $shifttype (keys %{$gapproj{$ymd}{$tel}}) {
                my $calproj = $tel . $CAL_NAME;

                # Now step through the data charging time gaps 50% each to the projects
                # on either side IF an entry exists in the %proj_totals hash
                # If an entry is not there, charge it to OTHER (since it may just have
                # done cals all night)
                my @projects = @{$gapproj{$ymd}{$tel}{$shifttype}};

                # If we only have 1 or 2 entries here then the number of gaps to apportion
                # is tiny and we only have one side. Charge to OTHER
                if (@projects > 2) {
                    for my $i (1 .. $#projects) {
                        # Can not be a gap in the very first entry so start at 1
                        # and can not be one at the end
                        if (ref($projects[$i]) eq 'HASH') {
                            # We have a gap. This should be charged to the following
                            # project
                            my $gap = $projects[$i]->{OTHER};
                            my $obs = $projects[$i]->{'OBS'};

                            # but make sure we do not extend the array indefinitely
                            # This code is more complicated in case we want to apportion
                            # the gap to projects on either side.
                            # NOTE: assignment of $projectid_orig assumes we only look at
                            # the single following entry (see warning above).
                            my @either;
                            push @either, $projects[$i + 1]
                                if $#projects != $i;

                            # if we do not have a project following this
                            # charge to OTHER
                            if (@either) {
                                for my $projdata (@either) {
                                    next unless defined $projdata;
                                    next unless ref($projdata) eq 'ARRAY';

                                    my $proj = $projdata->[0];
                                    my $projectid_orig = $projdata->[2];

                                    # Only charge to the gap if we have already charged to it
                                    # CAL should be charged to shared calibrations
                                    if (exists $proj_totals{$ymd}{$shifttype}{$proj}
                                            && $proj !~ /$CAL_NAME$/) {
                                        $proj_totals{$ymd}{$shifttype}{$proj} += $gap;
                                        push @{$proj_observations{$ymd}{$shifttype}{$proj}}, {
                                            obs => $obs,
                                            timespent => $gap,
                                            comment => 'Gap assigned to project'
                                                . (defined $projectid_orig ? " (was $projectid_orig)" : ''),
                                        } if $trace_observations;

                                        print "Adding $gap to $proj\n"
                                            if $DEBUG;
                                    }
                                    else {
                                        # Charge to calibration regardless
                                        $proj_totals{$ymd}{$shifttype}{$calproj} += $gap;
                                        push @{$proj_observations{$ymd}{$shifttype}{$calproj}}, {
                                            obs => $obs,
                                            timespent => $gap,
                                            comment => 'Gap assigned to calibration',
                                        } if $trace_observations;

                                        print "Adding $gap to CALibration\n"
                                            if $DEBUG;
                                    }
                                }
                            }
                            else {
                                # We should charge this to $tel OTHER
                                # regardless of the project name
                                print "Adding $gap to OTHER\n"
                                    if $DEBUG;

                                $other{$ymd}{$tel}{$shifttype}{$OTHER_GAP} += $gap;
                            }
                        }
                    }
                }
                else {
                    # We should charge this to $tel OTHER
                    # regardless of the project name
                    for my $entry (@projects) {
                        next unless ref($entry) eq 'HASH';
                        $other{$ymd}{$tel}{$shifttype}{$OTHER_GAP} += $entry->{OTHER};

                        print "Adding " . $entry->{OTHER} . " to OTHER[2]\n"
                            if $DEBUG;
                    }
                }
            }
        }
    }

    print "Gaps have been processed. New totals: " . Dumper(\%proj_totals)
        if $DEBUG;

    # Add in the extended/weather and other time
    for my $ymd (keys %other) {
        for my $tel (keys %{$other{$ymd}}) {
            for my $shifttype (keys %{$other{$ymd}{$tel}}) {
                for my $type (keys %{$other{$ymd}{$tel}{$shifttype}}) {
                    my $key = $tel . $type;
                    $proj_totals{$ymd}{$shifttype}{$key}
                        += $other{$ymd}{$tel}{$shifttype}{$type};
                }
            }
        }
    }

    # Now add in the missing projects - forcing an entry
    for my $ymd (keys %sigprojects) {
        for my $shifttype (keys %{$sigprojects{$ymd}}) {
            for my $proj (keys %{$sigprojects{$ymd}{$shifttype}}) {
                $proj_totals{$ymd}{$shifttype}{$proj} += 0;
            }
        }
    }

    print "Final totals: " . Dumper(\%proj_totals) if $DEBUG;

    # Work out the night total
    if ($DEBUG) {
        for my $ymd (keys %proj_totals) {
            my $total = 0;
            for my $shifttype (keys %{$proj_totals{$ymd}}) {
                for my $proj (keys %{$proj_totals{$ymd}{$shifttype}}) {
                    next if $proj =~ /$EXTENDED_KEY$/;
                    $total += $proj_totals{$ymd}{$shifttype}{$proj};
                }

                $total /= 3600.0;
                printf "SHIFT %s $ymd: %.2f hrs (without extended)\n", $shifttype, $total;

                my $refdate = OMP::DateTools->parse_date($ymd . "T12:00");

                for my $tel (keys %night_totals) {
                    my $nightlen = $datesun->determine_night_length(
                        tel => $tel,
                        date => $refdate);

                    printf "From observation data for tel $tel (inc faults): %.2f hrs\n",
                        $night_totals{$tel}{$ymd}{$shifttype} / 3600.0;

                    my $extend = $night_totals{$tel}{$ymd}{$shifttype} - $nightlen;

                    printf "Expected length of night = %.2f hrs (%s)\n",
                        ($nightlen / 3600),
                        ($extend >= 0
                            ? "Extended time = $extend s"
                            : "No extended time");
                }
            }
        }
    }

    # Now create the time accounting objects and store them in an
    # array
    my @timeacct;
    for my $ymd (keys %proj_totals) {
        my $date = OMP::DateTools->parse_date($ymd);
        print "Date: $ymd\n" if $DEBUG;

        for my $shifttype (keys %{$proj_totals{$ymd}}) {
            for my $proj (keys %{$proj_totals{$ymd}{$shifttype}}) {
                printf "Project $proj : %.2f\n", $proj_totals{$ymd}{$shifttype}{$proj} / 3600
                    if $DEBUG;

                my $projacct = OMP::Project::TimeAcct->new(
                    projectid => $proj,
                    date => $date,
                    timespent => Time::Seconds->new($proj_totals{$ymd}{$shifttype}{$proj}),
                    shifttype => $shifttype,
                );

                $projacct->observations($proj_observations{$ymd}{$shifttype}{$proj})
                    if $trace_observations
                    and exists $proj_observations{$ymd}{$shifttype}{$proj};

                push @timeacct, $projacct;
            }
        }
    }

    return (\@warnings, @timeacct);
}

=item B<projectStatsShared>

Return an array of C<Project::TimeAcct> objects for the given
C<ObsGroup> object and associated warnings. This implementation
shares calibrations amongst projects.

    my ($warnings, @timeacct) = $obsgroup->projectStatsShared(%options);

This method will determine all the projects in the given
C<ObsGroup> object, then use time allocations in that object
to populate the C<Project::TimeAcct> objects.

The first argument returned is an array of warning messages generated
by the time accounting tool. Usually these will indicate calibrations
that are not required by any science observations, or science
observations that have no corresponding calibration.

Calibrations are shared amongst those projects that required
them. General calibrations are shared amongst all projects
in proportion to the amount of time used by the project.
Science calibrations that are not required by any project
are stored in the "$telCAL" project (eg UKIRTCAL or JCMTCAL).
These owner-less calibrations do not get allocated their share
of general calibrations. This may be a bug.

Observations taken outside the normal observing periods
are not charged to any particular project but are charged
to project $tel"EXTENDED". This definition of extended time
is telescope dependent.

Does not yet take the observation status (questionable, bad, good)
into account when calculating the statistics. In principal observations
marked as bad should be charged to the general overhead.

Also does not charge for time gaps even if they have been flagged
as WEATHER.

If an observation has a calibration type that matches the project ID
then we assume that the data are self-calibrating rather than
complaining that there is no calibration.

If a time gap associated with an observation is smaller than a certain
threshold (say 5 minutes) then that time is charged to the following
project rather than to OTHER. This will allow us to compensate for
small gaps between data files associated with slewing and tuning.
If a small gap is between calibration observations it is charged
to $telCAL project [they should probably be charged to the project
in proportion to instrument usage but that requires more work].

=cut

sub projectStatsShared {
    my $self = shift;
    my %opt = @_;

    my @obs = $self->obs;

    # If we do not have any observations we return empty
    return (["No observations for statistics"])
        unless @obs;

    # This is the threshold for unspecified gaps
    # Below this threshold we attempt to associate them with the
    # relevant project. Above this threshold we simply charge them
    # to OTHER. This unit is in seconds
    # If this is set to 0, all unallocated gaps will be charged to OTHER
    my $GAP_THRESHOLD = OMP::Config->getData('timegap');

    my $datesun = OMP::DateSun->new;
    my @warnings;
    my %projbycal;
    my %cals;
    my %other;    # Extended time, weather time and OTHER gaps by telescope
    my %instlut;  # Lookup table to map instruments to telescope when sharing
                  # Generic calibrations

    # These are the generic key names for certain cal projects
    my $WEATHER_GAP = "WEATHER";
    my $OTHER_GAP = "OTHER";
    my $CAL_NAME = "CAL";
    my $EXTENDED_KEY = "EXTENDED";

    # This is a hash indexed by UT and tel (since we cannot mix them yet)
    # pointing to an array.  This array contains the projects as we
    # encounter them. We use it to make sure we assign small gaps to
    # projects properly. We try to make sure we do not push a project on
    # that is already at the end of the array
    my %gapproj;

    # Keep a list of ALL significant projects. In general this is not
    # much of a problem but is important if we have projects that
    # only consist of calibrations (esp E&C)
    my %sigprojects;

    # In some cases we need to know the most recent observation
    my $prevobs;

    # Go through all the observations, determining the time spent on
    # each project and the calibration requirements for each observation
    # Note that calibrations are not spread over instruments
    my %night_totals;
    for my $obs (@obs) {
        my $projectid = $obs->projectid;
        my $tel = uc($obs->telescope);

        # If we have a TIMEGAP we want to treat it as a special observation
        # that only depends on telescope (like JCMTCAL)
        my $isgap = 0;
        if (UNIVERSAL::isa($obs, "OMP::Info::Obs::TimeGap")) {
            $isgap = 1;

            # The projectid for these things should really be $tel . $type
            # but that is not how these have been implemented so we need to do it ourselves
            # Faults are explicitly calculated elsewhere in the fault system itself
            my $status = $obs->status;
            next if $status == OMP__TIMEGAP_FAULT;

            if ($status == OMP__TIMEGAP_INSTRUMENT
                    || $status == OMP__TIMEGAP_NEXT_PROJECT) {
                # INSTRUMENT and PROJECT gaps are shared amongst the projects. INSTRUMENT
                # gaps are shared by instrument, PROJECT gaps are given to the following
                # project. In both cases we handle it properly in the next section.
                # Simply let the default project ID go through since it will be ignored
                # in a little while.
            }
            elsif ($status == OMP__TIMEGAP_WEATHER) {
                $projectid = $WEATHER_GAP;
            }
            elsif ($status == OMP__TIMEGAP_PREV_PROJECT) {
                # This is time that should be charged to the project
                # preceeding this gap. For now we do not need to do anything
            }
            else {
                $projectid = $OTHER_GAP;
            }
        }

        # if we have a SCUBA project ID that seems to be a science observation
        # we charge this to projectID JCMTCAL. Clearly SCUBA::ODF should be responsible
        # for this logic but for now we add it here for testing.
        # This should be a rare occurence
        if ($projectid =~ /scuba/i && $obs->isScience) {
            # use JCMTCAL rather than tagging as a calibrator because we don't
            # want other people charged for it
            $projectid = 'JCMTCAL';
        }

        my $inst = $obs->instrument;
        my $startobs = $obs->startobs;
        my $endobs = $obs->endobs;
        my $ymd = $obs->startobs->ymd;
        my $timespent;
        my $duration = $obs->duration;

        # Store the project ID if it is significant
        $sigprojects{$ymd}{$projectid} ++
            if $projectid !~ /$CAL_NAME$/
            && $projectid !~ /$WEATHER_GAP$/
            && $projectid !~ /$OTHER_GAP$/
            && $projectid !~ /$EXTENDED_KEY$/
            && $projectid !~ /^scuba$/i
            && ! $isgap;

        # Store the project ID for gap processing
        # In general should make sure we dont get projects that are all calibrations
        unless (exists $gapproj{$ymd}{$tel}) {
            $gapproj{$ymd}{$tel} = [];
        }

        # This is the project to store in the gap analysis
        my $gapprojid = $projectid;

        # But we want to make sure that gaps solely between calibration
        # observations are not charged to OTHER when it would be better
        # if they were attached to generic calibration overheadds for the
        # instrument (and apportioned to real data).
        # We therefore must store the instrument as well
        $gapprojid = $CAL_NAME
            if (! $isgap && ! $obs->isScience);

        # Store the array ref with projectid and instrument
        # but only this is the first entry or if we are not repeating
        # the same projectID

        # Always push if we are the first element
        # Also push a projectid on the array if previous isnot an array (ie a gap)
        # OR if the previous project is not the same as the current project
        # We do not want to push a gap onto this array since a gap should be
        # the content [previously we pushed all gaps and then replaced them
        # with the actual gap later on]
        unless ($isgap) {
            push @{$gapproj{$ymd}{$tel}}, [$gapprojid, $inst]
                if scalar(@{$gapproj{$ymd}{$tel}}) == 0
                || (ref($gapproj{$ymd}->{$tel}->[-1]) ne 'ARRAY')
                || (ref($gapproj{$ymd}->{$tel}->[-1]) eq 'ARRAY'
                    && $gapproj{$ymd}->{$tel}->[-1]->[0] ne $gapprojid);
        }

        # We can calculate extended time so long as we have 2 of startobs, endobs and duration
        if ((defined $startobs && defined $endobs)
                || (defined $startobs && defined $duration)
                || (defined $endobs && defined $duration)) {
            # Get the extended time
            ($timespent, my $extended) = $datesun->determine_extended(
                duration => $duration,
                start => $startobs,
                end => $endobs,
                tel => $tel,
            );

            # And sort out the EXTENDED time UNLESS THIS IS ACTUALLY A TIMEGAP [cannot charge
            # "nothing" to extended observing!]
            # unless the gap is small (less than the threshold)
            # since most people define extended as time from when we really
            # start to when we really end the observing.
            $other{$ymd}{$tel}{$EXTENDED_KEY} += $extended->seconds
                if defined $extended
                && $extended->seconds > 0
                && (! $isgap || ($isgap && $extended->seconds < $GAP_THRESHOLD));

            # If the duration is negative set it to zero rather than kludging
            # by adding ONE_DAY
            if ($timespent->seconds < 0) {
                $timespent = Time::Seconds->new(0);
            }
        }
        else {
            # We cannot tell whether this was done in extended time or not
            # so assume not.
            $timespent = Time::Seconds->new($obs->duration);
        }

        $night_totals{$ymd} += $timespent->seconds;

        # Create instrument telescope lookup
        $instlut{$ymd}{$inst} = $tel unless exists $instlut{$ymd}{$inst};

        my $cal = $obs->calType;
        if ($isgap) {
            # Just need to add into the %other hash
            # UNLESS this is an OTHER gap that is smaller than the required threshold
            if ($projectid eq $OTHER_GAP
                    && $timespent->seconds < $GAP_THRESHOLD
                    && $timespent->seconds > 0) {
                # Replace the project entry with a hash pointing to the gap
                # Use a hash ref just to make it easy to spot rather than matching
                # to a digit
                push @{$gapproj{$ymd}->{$tel}},
                    {OTHER => $timespent->seconds};
            }
            elsif ($obs->status == OMP__TIMEGAP_NEXT_PROJECT) {
                # Always charge PROJECT gaps to the following project (this
                # is the same logic as for short gaps). Keep this separate
                # in case we had different types of accounting (especially
                # if we start to share between previous project or have a POSTPROJECT
                # and PREVPROJECT gap type). In that case will adjust the key here
                # to be PREVIOUS, POST or SHARED
                print "CHARGING " . $timespent->seconds . " TO PROJECT GAP\n"
                    if $DEBUG;

                push @{$gapproj{$ymd}->{$tel}},
                    {OTHER => $timespent->seconds};
            }
            elsif ($obs->status == OMP__TIMEGAP_PREV_PROJECT) {
                # Must charge the previous project
                print "CHARGING " . $timespent->seconds . " TO PREVIOUS PROJECT\n"
                    if $DEBUG;

                if (defined $prevobs) {
                    my $previnst = $prevobs->instrument;
                    my $prevymd = $prevobs->startobs->ymd;
                    my $prevprojectid = $prevobs->projectid;
                    my $prevtel = uc($prevobs->telescope);
                    my $prevcal = $prevobs->calType;

                    # This is a horrible hack. Should not be duplicating this code
                    if ($prevobs->isScience) {
                        # Charge to the project
                        $projbycal{$prevymd}{$prevprojectid}{$previnst}{$prevcal}
                            += $timespent->seconds;
                    }
                    else {
                        # Charge to calibration
                        if ($prevobs->isGenCal) {
                            $cals{$prevymd}{$previnst}{$CAL_NAME}
                                += $timespent->seconds;
                        }
                        else {
                            $cals{$prevymd}{$previnst}{$prevcal}
                                += $timespent->seconds;
                        }
                    }
                }
            }
            elsif ($obs->status == OMP__TIMEGAP_INSTRUMENT) {
                # Simply treat this as a generic calibration
                print "CHARGING " . $timespent->seconds . " TO INSTRUMENT GAP [$inst]\n"
                    if $DEBUG;

                $cals{$ymd}{$inst}{$CAL_NAME} += $timespent->seconds;
            }
            elsif ($timespent->seconds > 0) {
                # Just charge to OTHER [unless we have negative time gap]
                print "CHARGING " . $timespent->seconds . " TO $projectid\n"
                    if $DEBUG;

                $other{$ymd}{$tel}{$projectid} += $timespent->seconds;
            }

        }
        elsif ($obs->isScience) {
            $projbycal{$ymd}{$projectid}{$inst}{$cal} += $timespent->seconds;
        }
        else {
            if ($obs->isGenCal) {
                # General calibrations are deemed to be instrument
                # specific (if you do a skydip for scuba you should
                # not be charged for it if you use RxA)
                $cals{$ymd}{$inst}{$CAL_NAME} += $timespent->seconds;
            }
            else {
                $cals{$ymd}{$inst}{$cal} += $timespent->seconds;
            }
        }

        # Log the most recent information
        $prevobs = $obs if ! $isgap;
    }

    print Dumper(\%projbycal, \%cals, \%other, \%gapproj) if $DEBUG;

    # Now go through the science observations to find the total
    # of each required calibration regardless of project
    my %cal_totals;
    for my $ymd (keys %projbycal) {
        for my $proj (keys %{$projbycal{$ymd}}) {
            for my $inst (keys %{$projbycal{$ymd}{$proj}}) {
                for my $cal (keys %{$projbycal{$ymd}{$proj}{$inst}}) {
                    $cal_totals{$ymd}{$inst}{$cal}
                        += $projbycal{$ymd}{$proj}{$inst}{$cal};
                }
            }
        }
    }

    print "Science calibration totals:" . Dumper(\%cal_totals) if $DEBUG;

    # Now we need to calculate project totals by apporitoning the
    # actual calibration data in proportion to the total amount
    # of time each project spent requiring these observations
    # This is still done on a per-instrument basis
    my %proj;
    for my $ymd (keys %projbycal) {
        for my $proj (keys %{$projbycal{$ymd}}) {
            for my $inst (keys %{$projbycal{$ymd}{$proj}}) {
                for my $cal (keys %{$projbycal{$ymd}{$proj}{$inst}}) {
                    # Add on the actual observation time
                    $proj{$ymd}{$proj}{$inst}
                        += int($projbycal{$ymd}{$proj}{$inst}{$cal});

                    # This project should be charged for calibrations
                    # as a fraction of the total time spent time on data
                    # that uses the calibration and instrument
                    if (exists $cals{$ymd}{$inst}{$cal}
                            && $cals{$ymd}{$inst}{$cal} > 0
                            && exists $cal_totals{$ymd}{$inst}{$cal}
                            && $cal_totals{$ymd}{$inst}{$cal} > 0) {
                        # We have a calibration
                        my $caltime =
                            $projbycal{$ymd}{$proj}{$inst}{$cal} /
                            $cal_totals{$ymd}{$inst}{$cal} *
                            $cals{$ymd}{$inst}{$cal};

                        # And the calibrations
                        $proj{$ymd}{$proj}{$inst} += int($caltime);
                    }
                    else {
                        # oops, no relevant calibrations...
                        # unless we are self-calibrating
                        push @warnings,
                            "No calibration data of type $cal for project $proj on $ymd\n"
                            if ($cal ne $proj);
                    }
                }
            }
        }
    }

    print "Proj after science calibrations:" . Dumper(\%proj)
        if $DEBUG;

    # And any small forgotten leftover time gaps
    # Including charging gaps between calibrations to generic calibrations
    print "Processing gaps:\n" if $DEBUG;
    for my $ymd (keys %gapproj) {
        for my $tel (keys %{$gapproj{$ymd}}) {
            # Now step through the data charging time gaps 50% each to the projects
            # on either side IF an entry exists in the %proj_totals hash
            # If an entry is not there, charge it to OTHER (since it may just have
            # done cals all night)
            my @projects = @{$gapproj{$ymd}{$tel}};

            # If we only have 1 or 2 entries here then the number of gaps to apportion
            # is tiny and we only have one side. Charge to OTHER
            if (@projects > 2) {
                for my $i (1 .. $#projects) {
                    # Can not be a gap in the very first entry so start at 1
                    # and can not be one at the end
                    if (ref($projects[$i]) eq 'HASH') {
                        # We have a gap. This should be charged to the following
                        # project
                        my $gap = $projects[$i]->{OTHER};

                        # but make sure we do not extend the array indefinitely
                        # This code is more complicated in case we want to apportion
                        # the gap to projects on either side
                        my @either;
                        push @either, $projects[$i + 1]
                            if $#projects != $i;

                        # if we do not have a project following this
                        # charge to OTHER
                        if (@either) {
                            for my $projdata (@either) {
                                next unless defined $projdata;
                                next unless ref($projdata) eq 'ARRAY';

                                my $proj = $projdata->[0];
                                my $inst = $projdata->[1];

                                #$proj = $tel . $proj if $proj =~ /$CAL_NAME$/ && $proj !~ /^$tel/i;

                                # Only charge to the gap if we have already charged to it
                                # CAL should be charged to shared calibrations
                                if (exists $proj{$ymd}{$proj}{$inst}
                                        && $proj !~ /$CAL_NAME$/) {
                                    $proj{$ymd}{$proj}{$inst} += $gap;

                                    print "Adding $gap to $proj with $inst\n"
                                        if $DEBUG;
                                }
                                else {
                                    # We should charge this to the instrument gen cals
                                    # regardless of the project name
                                    $cals{$ymd}{$inst}{$CAL_NAME} += $gap;

                                    print "Adding $gap to CALibration $inst\n"
                                        if $DEBUG;
                                }
                            }
                        }
                        else {
                            # We should charge this to $tel OTHER
                            # regardless of the project name
                            print "Adding $gap to OTHER\n" if $DEBUG;

                            $other{$ymd}{$tel}{$OTHER_GAP} += $gap;
                        }
                    }
                }
            }
            else {
                # We should charge this to $tel OTHER
                # regardless of the project name
                for my $entry (@projects) {
                    next unless ref($entry) eq 'HASH';

                    $other{$ymd}{$tel}{$OTHER_GAP} += $entry->{OTHER};

                    print "Adding " . $entry->{OTHER} . " to OTHER[2]\n"
                        if $DEBUG;
                }
            }
        }
    }

    print Dumper(\%proj, \%cals, \%other) if $DEBUG;
    print "GAPS done\n" if $DEBUG;

    # Now need to apportion the generic calibrations amongst
    # all the projects by instrument
    for my $ymd (keys %proj) {
        # Calculate the total project time for this instrument
        # including calibrations
        my %total;
        for my $proj (keys %{$proj{$ymd}}) {
            for my $inst (keys %{$proj{$ymd}{$proj}}) {
                $total{$inst} += $proj{$ymd}{$proj}{$inst};
            }
        }

        # Add on the general calibrations (for each instrument)
        # if there were any
        for my $proj (keys %{$proj{$ymd}}) {
            for my $inst (keys %{$proj{$ymd}{$proj}}) {
                if ($total{$inst} > 0) {
                    $proj{$ymd}{$proj}{$inst}
                        += int($cals{$ymd}{$inst}{$CAL_NAME} *
                            $proj{$ymd}{$proj}{$inst} /
                            $total{$inst});
                }
            }
        }
    }

    print "Proj after adding $CAL_NAME: " . Dumper(\%proj)
        if $DEBUG;

    # Now go through and create a CAL entry for calibrations
    # that were not used by anyone. Technically the General data
    # should be shared onto CAL as well...For now, CAL is just treated
    # as non-science data that is not useful for anyone else
    for my $ymd (keys %cals) {
        for my $inst (keys %{$cals{$ymd}}) {
            for my $cal (keys %{$cals{$ymd}{$inst}}) {
                # Skip general calibrations
                next if $cal =~ /$CAL_NAME$/;

                # Check specific calibrations
                unless (exists $cal_totals{$ymd}{$inst}{$cal}) {
                    push @warnings,
                        "Calibration $cal is not used by any science observations on $ymd\n";
                    $proj{$ymd}{$CAL_NAME}{$inst} += $cals{$ymd}{$inst}{$cal};
                }
            }
        }
    }

    # If we have some nights without any science calibrations we need
    # to charge it to CAL
    for my $ymd (keys %cals) {
        for my $inst (keys %{$cals{$ymd}}) {
            # Now need to look for this instrument usage on this date
            my $nocal;
            for my $proj (keys %{$projbycal{$ymd}}) {
                if (exists $projbycal{$ymd}{$proj}{$inst}) {
                    # Science data found for this instrument
                    $nocal = 1;
                    last;
                }
            }
            unless ($nocal) {
                # Need to add this to cal
                print "Adding on CAL data for $inst on $ymd of $cals{$ymd}{$inst}{$CAL_NAME}\n"
                    if $DEBUG;

                $proj{$ymd}{$CAL_NAME}{$inst} += $cals{$ymd}{$inst}{$CAL_NAME};
            }
        }
    }

    print "Proj after leftovers: " . Dumper(\%proj)
        if $DEBUG;

    # Now we need to add up all the projects by UT date
    my %proj_totals;
    for my $ymd (keys %proj) {
        for my $proj (keys %{$proj{$ymd}}) {
            for my $inst (keys %{$proj{$ymd}{$proj}}) {
                my $projkey = $proj;

                # If we have some shared calibrations that are not associated
                # with a project we need to associate them with a telescope
                # so that UKIRTCAL and JCMTCAL do not clash in the system
                if ($proj eq $CAL_NAME) {
                    $projkey = $instlut{$ymd}{$inst} . $CAL_NAME;
                }

                $proj_totals{$ymd}{$projkey} += $proj{$ymd}{$proj}{$inst};
            }
        }
    }

    # Add in the extended/weather and other time
    for my $ymd (keys %other) {
        for my $tel (keys %{$other{$ymd}}) {
            for my $type (keys %{$other{$ymd}{$tel}}) {
                my $key = $tel . $type;
                $proj_totals{$ymd}{$key} += $other{$ymd}{$tel}{$type};
            }
        }
    }

    # Now add in the missing projects - forcing an entry
    for my $ymd (keys %sigprojects) {
        for my $proj (keys %{$sigprojects{$ymd}}) {
            $proj_totals{$ymd}{$proj} += 0;
        }
    }

    print "Final totals: " . Dumper(\%proj_totals)
        if $DEBUG;

    # Work out the night total
    if ($DEBUG) {
        for my $ymd (keys %proj_totals) {
            my $total = 0;
            for my $proj (keys %{$proj_totals{$ymd}}) {
                $total += $proj_totals{$ymd}{$proj};
            }
            $total /= 3600.0;

            printf "$ymd: %.2f hrs\n", $total;
            printf "From files: %.2f hrs\n", $night_totals{$ymd} / 3600.0;
        }
    }

    # Now create the time accounting objects and store them in an
    # array
    my @timeacct;
    for my $ymd (keys %proj_totals) {
        my $date = OMP::DateTools->parse_date($ymd);

        print "Date: $ymd\n" if $DEBUG;

        for my $proj (keys %{$proj_totals{$ymd}}) {
            printf "Project $proj : %.2f\n", $proj_totals{$ymd}{$proj} / 3600
                if $DEBUG;

            push @timeacct, OMP::Project::TimeAcct->new(
                projectid => $proj,
                date => $date,
                timespent => Time::Seconds->new($proj_totals{$ymd}{$proj}));
        }
    }

    return (\@warnings, @timeacct);
}

=item B<groupby>

Returns a hash of C<OMP::Info::ObsGroup> objects grouped by accessor.

    %grouped = $grp->groupby('instrument');

The argument must be a valid C<OMP::Info::Obs> accessor. If it is not,
this method will throw an C<OMP::Error::BadArgs> error.

The keys of the returned hash will be the discrete values for the accessor
found in the given C<OMP::Info::ObsGroup> object, and the values will be
C<OMP::Info::ObsGroup> objects corresponding to those keys.

=cut

sub groupby {
    my $self = shift;
    my $method = shift;

    throw OMP::Error::BadArgs(
        "Cannot group by $method in Info::ObsGroup->groupby")
        unless OMP::Info::Obs->can($method);

    my %group;
    foreach my $obs ($self->obs) {
        push @{$group{$obs->$method}}, $obs;
    }

    return map {$_, OMP::Info::ObsGroup->new(obs => $group{$_})}
        keys %group;
}

=item B<locate_timegaps>

Inserts C<OMP::Info::Obs::TimeGap> objects in appropriate locations
and sorts the C<ObsGroup> object by time.

    $obsgrp->locate_timegaps($db, $gap_length);

A timegap is inserted if there are more than C<gap_length> seconds between
the completion of one observation (taken to be the value of the C<end_obs>
accessor) and the start of the next (taken to be the value of the
C<start_obs> accessor). If the second observation is done with a different
instrument than the first, then the timegap will be an B<INSTRUMENT> type.
Otherwise, the timegap will be an B<UNKNOWN> type.

=cut

sub locate_timegaps {
    my $self = shift;
    my $db = shift;
    my $length = shift;

    throw OMP::Error::FatalError(
        'locate_timegapsThe DB argument must be an OMP::DB::Backend object')
        unless eval {$db->isa('OMP::DB::Backend')};

    my @obslist;
    my $counter = 0;
    my $obs_counter = 0;
    my $last_time;
    my @newobs;
    my @timegaps;

    # Get a list of the observations.
    my @obs = $self->obs;

    # Create an array of arrays.
    @obslist = map {[$_->startobs, +1, $_], [$_->endobs, -1, $_]} @obs;

    # Sort according to time.
    @obslist = sort {$a->[0] <=> $b->[0]} @obslist;

    # Get a list of comments
    my $odb = OMP::DB::Obslog->new(DB => $db);

    # Query between first and last observation."

    my %comments;
    if (@obslist) {
        my $start = $obslist[0]->[2]->startobs;
        my $end = $obslist[$#obslist]->[2]->endobs;

        OMP::General->log_message(
            "OMP::DB::Obslog: Querying database for observation comments.\n");

        my $query = OMP::Query::Obslog->new(HASH => {
            date => {
                min => $start->ymd,
                max => $end->ymd . 'T' . $end->hms},
            obsactive => {boolean => 1},
        });
        my @commentresults = $odb->queryComments($query);

        %comments = map {$_->obsid => $_} @commentresults;
    }

    # For each observation in the sorted array...
    foreach my $obs (@obslist) {
        if ($counter == 0 && defined $last_time) {
            # We have a timegap. Let's see if it's longer than our threshold.
            my $gap = $obs->[0] - $last_time;
            if ($gap >= $length) {
                # Get the previous and current observations.
                my $prev_obs = $obslist[$obs_counter - 2]->[2];
                my $curr_obs = $obslist[$obs_counter]->[2];

                # Create the TimeGap.  Assume by default that the location and
                # shifttype come from the succeeeding observation. In time
                # accounting contexts this will need to be manually adjusted,
                # but it will be good for testing.
                my $timegap = OMP::Info::Obs::TimeGap->new;
                $timegap->instrument($curr_obs->instrument);
                $timegap->runnr($curr_obs->runnr);
                $timegap->startobs($prev_obs->endobs);
                $timegap->endobs($curr_obs->startobs - 1);
                $timegap->telescope($prev_obs->telescope);
                $timegap->shifttype($curr_obs->shifttype);
                $timegap->remote($curr_obs->remote);

                # Get the comments for the TimeGap.

                # The -1 is taken from obslogDB.pm: and apepars to be how to
                # match obsids from comments to timegaps.
                my $timegapobsid = OMP::DB::Obslog::_placeholder_obsid(
                    $timegap->instrument,
                    $timegap->runnr,
                    $timegap->endobs - 1);

                if (exists $comments{$timegapobsid}) {
                    $timegap->comments($comments{$timegapobsid});
                }

                # Set the TimeGap status, if necessary.
                unless (defined $timegap->status) {
                    if (uc($prev_obs->instrument) eq uc($curr_obs->instrument)) {
                        $timegap->status(OMP__TIMEGAP_UNKNOWN);
                    }
                    else {
                        $timegap->status(OMP__TIMEGAP_INSTRUMENT);
                    }
                }

                # Push the TimeGap onto the array of TimeGaps.
                push @timegaps, $timegap;
            }
        }

        # Increment counters.
        $counter += $obs->[1];
        $counter == 0 && ($last_time = $obs->[0]);
        $obs_counter ++;
    }

    # Add the TimeGaps to the list of observations.
    push @obs, @timegaps;

    # And now, set $self to use the new observations.
    $self->obs(\@obs);

    # And sort.
    $self->sort_by_time;

    return;
}

=item B<summary>

Returns a text-based summary for observations in an observation
group.

    $summary = $grp->summary;

Currently implements the '72col' version of the C<OMP::Info::Obs::summary>
method.

=cut

sub summary {
    my $self = shift;

    # Create a heading.
    my @headings = ('Obs', 'Start', 'Proj', 'Inst', 'Src', 'Mode', 'State');
    my $heading = sprintf "%4.4s %8.8s %15.15s %8.8s %-14.14s %-11.11s %-5.5s\n",
        @headings;

    if (wantarray) {
        my @summary;
        push @summary, ($heading);
        foreach my $obs ($self->obs) {
            my @obssum = $obs->summary('72col');
            push @summary, @obssum;
        }
        return @summary;
    }
    else {
        my $summary;
        foreach my $obs ($self->obs) {
            $summary .= $obs->summary('72col');
        }
        return $heading . $summary;
    }
}

=item B<shifttypes>

Returns an array containing all the distinct shifttypes of the
observations in the group.

    @shifttypes = $grp->shifttypes;

=cut

sub shifttypes {
    my $self = shift;
    my @observations = $self->obs;

    my %shifthash;
    for my $obs (@observations) {
        my $shifttype = $obs->shifttype;
        $shifthash{$shifttype} = 1;
    }
    my @shifttypes = (keys %shifthash);
    return @shifttypes;
}

=item B<attach_previews>

Takes (a reference to) an array of previews and attempts to attach
them to the matching observations.

    $grp->attach_previews(\@previews);

=cut

sub attach_previews {
    my $self = shift;
    my $previews = shift;

    my %matched = ();
    foreach my $obs ($self->obs) {
        my $obs_utdate = 0 + $obs->startobs->ymd('');

        my @obs_previews = ();
        for (my $i = 0; $i <= $#$previews; $i ++) {
            next if $matched{$i};
            my $preview = $previews->[$i];

            next unless
                ($preview->runnr == $obs->runnr)
                and ($preview->date->ymd('') == $obs_utdate)
                and (uc $preview->instrument eq uc $obs->instrument);

            $matched{$i} = 1;
            push @obs_previews, $preview;
        }

        $obs->previews(\@obs_previews);
    }
}

1;

__END__

=back

=head1 SEE ALSO

For related classes see C<OMP::DB::Archive> and C<OMP::DB::Obslog>.

For information on time gaps see C<OMP::Info::Obs::TimeGap>.

=head1 AUTHORS

Brad Cavanagh E<lt>b.cavanagh@jach.hawaii.eduE<gt>,
Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2002-2004 Particle Physics and Astronomy Research Council.
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
