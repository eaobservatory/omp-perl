package OMP::Project::TimeAcct::Group;

=head1 NAME

OMP::Project::TimeAcct::Group - Information on a group of OMP::Project::TimeAcct objects

=head1 SYNOPSIS

    use OMP::Project::TimeAcct::Group;

    $tg = OMP::Project::TimeAcct::Group->new(
        DB => $database,
        telescope => $telescope,
        accounts => \@accounts);

    @stats = $tg->timeLostStats();

=head1 DESCRIPTION

This class can be used to generate time accounting statistics, based
on a group of C<OMP::Project::TimeAcct> objects.  A group is just an
array of C<OMP::Project::TimeAcct> objects.

=cut

use 5.006;
use strict;
use warnings;
use Carp;

our $VERSION = '2.000';

use OMP::Config;
use OMP::Error qw/:try/;
use OMP::DateTools;
use OMP::General;
use OMP::PlotHelper;
use OMP::DB::Project;
use OMP::Query::Project;
use OMP::DB::TimeAcct;
use OMP::Query::TimeAcct;

use Time::Seconds;

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

Object constructor. Takes a hash as an argument, the keys of which can
be used to populate the object.  The keys must match the names of the
accessor methods (ignoring case).

    $tg = OMP::Project::TimeAcct::Group->new(
        DB => $database,
        telescope => $telescope,
        accounts => \@accounts);

Arguments are optional.

=cut

sub new {
    my $proto = shift;
    my %args = @_;
    my $class = ref($proto) || $proto;

    my $tg = bless {
        Accounts => [],
        TotalTime => undef,
        TotalTimeNonExt => undef,
        CalTime => undef,
        ClearTime => undef,
        ConfirmedTime => undef,
        ECTime => undef,
        ExtTime => undef,
        FaultLoss => undef,
        ObservedTime => undef,
        OtherTime => undef,
        ScienceTime => undef,
        ShutdownTime => undef,
        Telescope => undef,
        WeatherLoss => undef,
    }, $class;

    if (@_) {
        $tg->populate(%args);
    }

    return $tg;
}

=back

=head2 Accessor Methods

=over 4

=item B<accounts>

Retrieve (or specify) the group of accounts.

    @accounts = $tg->accounts;
    $accountref = $tg->accounts;
    $tg->accounts(@accounts);
    $tg->accounts(\@accounts);

All previous accounts are removed when new accounts are stored.
Takes either an array, or reference to an array, of
C<OMP::Project::TimeAcct> objects.

=cut

sub accounts {
    my $self = shift;

    if (@_) {
        # Store new accounts
        my @accounts;
        if (ref($_[0]) eq 'ARRAY') {
            @accounts = @{$_[0]};
        }
        else {
            @accounts = @_;
        }

        # Make sure these are OMP::Project::TimeAcct objects
        # with a defined epoch
        for (@accounts) {
            throw OMP::Error::BadArgs(
                "Account must be an object of class OMP::Project::TimeAcct")
                unless UNIVERSAL::isa($_, "OMP::Project::TimeAcct");

            throw OMP::Error::BadArgs(
                "Account must have a valid date, not undef")
                unless defined $_->date;
        }

        # Store accounts, sorted
        @{$self->{Accounts}} = sort {
            $a->date->epoch <=> $b->date->epoch
        } @accounts;

        # Clear cached values
        $self->totaltime(undef);
        $self->confirmed_time(undef);
        $self->totaltime_non_ext(undef);
        $self->cal_time(undef);
        $self->clear_time(undef);
        $self->ext_time(undef);
        $self->fault_loss(undef);
        $self->observed_time(undef);
        $self->other_time(undef);
        $self->weather_loss(undef);
        $self->science_time(undef);
        $self->ec_time(undef);
    }

    if (wantarray) {
        return @{$self->{Accounts}};
    }
    else {
        return $self->{Accounts};
    }
}

=item B<totaltime>

The total time spent according to all accounts (this includes
weather loss, other time, faults, and extended time).This
value is represented by a C<Time::Seconds> object.

    $time = $tg->totaltime();
    $tg->totaltime($time);

Call with a either a number of seconds or a C<Time::Seconds>
object to set this value.  Call with an undef value to unset
this value.  Returns a C<Time::Seconds> object with a value
of 0 seconds if undefined.

=cut

sub totaltime {
    my $self = shift;
    if (@_) {
        $self->_mutate_time('TotalTime', $_[0]);
    }
    elsif (! defined $self->{TotalTime}) {
        # Calculate total time since it isn't cached
        my @accounts = $self->accounts;
        my $timespent = Time::Seconds->new(0);
        my $confirmed = Time::Seconds->new(0);
        for my $acct (@accounts) {
            $timespent += $acct->timespent;
            $confirmed += $acct->timespent if $acct->confirmed;
        }
        # Store total
        $self->{TotalTime} = $timespent;
        $self->confirmed_time($confirmed);
    }

    unless (defined $self->{TotalTime}) {
        return Time::Seconds->new(0);
    }
    else {
        return $self->{TotalTime};
    }
}

=item B<confirmed_time>

Total time which is marked as confirmed.  Returned as a
C<Time::Seconds> object.

    $confirmed = $tg->confirmed_time();

Can be passed a value or undef to set/unset the time, otherwise
calls C<totaltime> to ensure a value is available.

=cut

sub confirmed_time {
    my $self = shift;
    if (@_) {
        $self->_mutate_time('ConfirmedTime', $_[0]);
    }
    elsif (! defined $self->{'ConfirmedTime'}) {
        # Call "totaltime" since it will also cache the confirmed time.
        $self->totaltime();
    }

    return $self->{'ConfirmedTime'};
}

=item B<unconfirmed_time>

Return the total unconfirmed time.

B<Note:> this method can not be used to set the time.  It simply returns
the value C<totaltime> - C<confirmed_time>.

=cut

sub unconfirmed_time {
    my $self = shift;

    return $self->totaltime - $self->confirmed_time;
}

=item B<totaltime_non_ext>

The total time spent, except for extended time.  This
value is represented by a C<Time::Seconds> object.

    $time = $tg->totaltime_non_ext();
    $tg->totaltime_non_ext($time);

Call with a either a number of seconds or a C<Time::Seconds>
object to set this value.  Call with an undef value to unset
this value.

=cut

sub totaltime_non_ext {
    my $self = shift;
    if (@_) {
        $self->_mutate_time('TotalTimeNonExt', $_[0]);
    }
    elsif (! defined $self->{TotalTimeNonExt}) {
        # Get total and extended time
        my $total = $self->totaltime;
        my $extended = $self->ext_time;

        # Subtract extended time
        my $nonext = $total - $extended;

        # Store to cache
        $self->{TotalTimeNonExt} = $nonext;
    }

    return $self->{TotalTimeNonExt};
}

=item B<cal_time>

The total time spent on calibrations.  This value is represented by a
C<Time::Seconds> object.

    $time = $tg->cal_time();
    $tg->cal_time($time);

Call with a either a number of seconds or a C<Time::Seconds>
object to set this value.  Call with an undef value to unset
this value.

=cut

sub cal_time {
    my $self = shift;
    if (@_) {
        $self->_mutate_time('CalTime', $_[0]);
    }
    elsif (! defined $self->{CalTime}) {
        # Calculate CAL time since it isn't cached

        # Get just CAL accounts
        my @accounts = $self->_get_special_accts("CAL");

        my $timespent = Time::Seconds->new(0);
        for my $acct (@accounts) {
            $timespent += $acct->timespent;
        }
        # Store total
        $self->{CalTime} = $timespent;
    }

    return $self->{CalTime};
}

=item B<clear_time>

The amount of time where conditions were observable (everything
but weather loss and extended time).  This value is represented
by a C<Time::Seconds> object.

    $time = $tg->clear_time();
    $tg->clear_time($time);

Call with a either a number of seconds or a C<Time::Seconds>
object to set this value.  Call with an undef value to unset
this value.

=cut

sub clear_time {
    my $self = shift;
    if (@_) {
        $self->_mutate_time('ClearTime', $_[0]);
    }
    elsif (! defined $self->{ClearTime}) {
        # Get total non-extended and weather time
        my $nonext = $self->totaltime_non_ext;
        my $weather = $self->weather_loss;

        my $clear = $nonext - $weather;

        # Store to cache
        $self->{ClearTime} = $clear;
    }

    return $self->{ClearTime};
}

=item B<ec_time>

Non-extended Time spent observing projects that are associated
with the E&C queue.

    $time = $tg->ec_time();
    $tg->ec_time($time);

Call with a either a number of seconds or a C<Time::Seconds>
object to set this value.  Call with an undef value to unset
this value.  Returns 0 seconds if undefined.

=cut

sub ec_time {
    my $self = shift;
    if (@_) {
        $self->_mutate_time('ECTime', $_[0]);
    }
    elsif (! defined $self->{ECTime}) {
        # Get EC accounts
        my @acct = $self->_get_accts('eng');

        # Add it up
        my $ectime = Time::Seconds->new(0);
        for my $acct (@acct) {
            $ectime += $acct->timespent;
        }

        # Store to cache
        $self->{ECTime} = $ectime;
    }

    return $self->{ECTime};
}

=item B<ext_time>

The total extended time spent.  This value is represented by a
C<Time::Seconds> object.

    $time = $tg->ext_time();
    $tg->ext_time($time);

Call with a either a number of seconds or a C<Time::Seconds>
object to set this value.  Call with an undef value to unset
this value.

=cut

sub ext_time {
    my $self = shift;
    if (@_) {
        $self->_mutate_time('ExtTime', $_[0]);
    }
    elsif (! defined $self->{ExtTime}) {
        # Calculate extended time since it isn't cached

        # Get just EXTENDED accounts
        my @accounts = $self->_get_special_accts("EXTENDED");

        my $timespent = Time::Seconds->new(0);
        for my $acct (@accounts) {
            $timespent += $acct->timespent;
        }
        # Store total
        $self->{ExtTime} = $timespent;
    }

    return $self->{ExtTime};
}

=item B<fault_loss>

The total time lost to faults.  This value is represented by a
C<Time::Seconds> object.

    $time = $tg->fault_loss();
    $tg->fault_loss($time);

Call with a either a number of seconds or a C<Time::Seconds>
object to set this value.  Call with an undef value to unset
this value.  Returns 0 seconds if the value is undefined.

=cut

sub fault_loss {
    my $self = shift;
    if (@_) {
        $self->_mutate_time('FaultLoss', $_[0]);
    }
    elsif (! defined $self->{FaultLoss}) {
        # Calculate fault loss time since it isn't cached

        # Get just the fault accounts
        my @acct = grep {$_->projectid eq '__FAULT__'} $self->accounts;

        my $timespent = Time::Seconds->new(0);
        for my $acct (@acct) {
            $timespent += $acct->timespent;
        }
        # Store total
        $self->{FaultLoss} = $timespent;
    }

    return $self->{FaultLoss};
}

=item B<observed_time>

The amount of time spent observing (everything but time lost to
weather and time spent doing "OTHER" things).  This value is
represented by a C<Time::Seconds> object.

    $time = $tg->observed_time();
    $tg->observed_time($time);

Call with a either a number of seconds or a C<Time::Seconds>
object to set this value.  Call with an undef value to unset
this value. Returns a C<Time::Seconds> object with a value
of 0 seconds if undefined.

=cut

sub observed_time {
    my $self = shift;
    if (@_) {
        $self->_mutate_time('ObservedTime', $_[0]);
    }
    elsif (! defined $self->{ObservedTime}) {
        # Get total, other, and weather time
        my $total = $self->totaltime;
        my $other = $self->other_time;
        my $weather = $self->weather_loss;

        # Subtract weather and other from total
        my $observed = $total - $weather - $other;

        # Store to cache
        $self->{ObservedTime} = $observed;
    }

    unless (defined $self->{ObservedTime}) {
        return Time::Seconds->new(0);
    }
    else {
        return $self->{ObservedTime};
    }
}

=item B<other_time>

The total time spent doing other things.  This value is represented by a
C<Time::Seconds> object.

    $time = $tg->other_time();
    $tg->other_time($time);

Call with a either a number of seconds or a C<Time::Seconds>
object to set this value.  Call with an undef value to unset
this value.

=cut

sub other_time {
    my $self = shift;
    if (@_) {
        $self->_mutate_time('OtherTime', $_[0]);
    }
    elsif (! defined $self->{OtherTime}) {
        # Calculate other time since it isn't cached

        # Get just OTHER accounts
        my @accounts = $self->_get_special_accts("OTHER");
        my $timespent = Time::Seconds->new(0);
        for my $acct (@accounts) {
            $timespent += $acct->timespent;
        }
        # Store total
        $self->{OtherTime} = $timespent;
    }

    return $self->{OtherTime};
}

=item B<science_time>

Non-extended Time spent observing projects not associated
with the E&C queue.

    $time = $tg->science_time();
    $tg->science_time($time);

Call with a either a number of seconds or a C<Time::Seconds>
object to set this value.  Call with an undef value to unset
this value.  Returns 0 seconds if undefined.

=cut

sub science_time {
    my $self = shift;
    if (@_) {
        $self->_mutate_time('ScienceTime', $_[0]);
    }
    elsif (! defined $self->{ScienceTime}) {
        # Get non-EC accounts
        my @acct = $self->_get_accts('sci');

        # Add it up
        my $scitime = Time::Seconds->new(0);
        for my $acct (@acct) {
            $scitime += $acct->timespent;
        }

        # Store to cache
        $self->{ScienceTime} = $scitime;
    }

    return $self->{ScienceTime};
}

=item B<shutdown_time>

Time spent on a planned shutdown.

    $time = $tg->shutdown_time();
    $tg->shutdown_time($time);

Call with a either a number of seconds or a C<Time::Seconds>
object to set this value.  Call with an undef value to unset
this value.  Returns 0 seconds if undefined.

=cut

sub shutdown_time {
    my $self = shift;
    if (@_) {
        $self->_mutate_time('ShutdownTime', $_[0]);
    }
    elsif (! defined $self->{ShutdownTime}) {
        # Get SHUTDOWN accounts
        my @accts = $self->_get_special_accts('_SHUTDOWN');

        # Add it up
        my $shuttime = Time::Seconds->new(0);
        for my $acct (@accts) {
            $shuttime += $acct->timespent;
        }

        # Store to cache
        $self->{ShutdownTime} = $shuttime;
    }

    return $self->{ShutdownTime};
}

=item B<weather_loss>

The total time lost to weather.  This value is represented by a
C<Time::Seconds> object.

    $time = $tg->weather_loss();
    $tg->weather_loss($time);

Call with a either a number of seconds or a C<Time::Seconds>
object to set this value.  Call with an undef value to unset
this value.  Returns 0 seconds if the value is undefined.

=cut

sub weather_loss {
    my $self = shift;
    if (@_) {
        $self->_mutate_time('WeatherLoss', $_[0]);
    }
    elsif (! defined $self->{WeatherLoss}) {
        # Calculate weather time since it isn't cached

        # Get just the weather accounts
        my @accounts = $self->_get_special_accts("WEATHER");

        my $timespent = Time::Seconds->new(0);
        for my $acct (@accounts) {
            $timespent += $acct->timespent;
        }
        # Store total
        $self->{WeatherLoss} = $timespent;
    }

    return $self->{WeatherLoss};
}

=item B<telescope>

The telescope that the time accounts are associated with.

    $tel = $tg->telescope();
    $tg->telescope($tel);

Returns a string. If a telescope is requested but has not been defined,
an attempt will be made to derive it from the first science project ID
in the group.

=cut

sub telescope {
    my $self = shift;
    if (@_) {
        my $tel = shift;
        $self->{Telescope} = uc($tel) if defined $tel;
    }
    else {
        # we have a request
        unless (defined $self->{Telescope}) {
            $self->{Telescope} = $self->_get_telescope();
        }
    }

    return $self->{Telescope};
}

=item B<shifttypes>

The shifttype that the time accounts are associated with.

    $shifttypes = $tg->shifttypes;

Returns an array

=cut

sub shifttypes {
    my $self = shift;
    my @accts = $self->accounts;

    my %shifthash;
    for my $acct (@accts) {
        my $shifttype = $acct->shifttype;
        $shifthash{$shifttype} = 1;
    }

    my @shifttypes = (keys %shifthash);

    return @shifttypes;
}


=item B<db>

A shared database connection (an C<OMP::DB::Backend> object).

    $db = $tg->db;

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

    return $self->{'DB'};
}

=back

=head2 General Methods

=over 4

=item B<completion_stats>

Produce statistics suitable for use in a time-series plot.

    %stats = $tg->completion_stats;

Returns a hash containing the following keys:

=over 4

=item science

Contains an array reference of coordinates where
X is an integer MJD date and Y is the completion
percentage on that date.  No binning is done on
these values.

=item weather

Contains an array reference of coordinates where
X is a modified Julian date and Y is the hours lost
to weather on that date. These values are binned up
by 7 day periods.

=item ec

Contains an array reference of coordinates where
X is a modified Julian date and Y is the hours spent
on E&C projects on that date. These values are binned
up by 7 day periods

=item fault

Contains an array reference of coordinates where
X is a modified Julian date and Y is the hours lost
to faults on that date. These values are binned up
by 7 day periods.

=item __ALLOC__

Contains the total time allocated to projects
during the semesters spanned by the accounts in
this group.  Value is represented by an
C<OMP::Seconds> object.

=item __OFFSET__

Contains the total time spent during previous
semesters on projects associated with the accounts
in this group.  Value is represented by an
C<OMP::Seconds> object.

=back

=cut

sub completion_stats {
    my $self = shift;

    my $telescope = $self->telescope();
    my @semesters = $self->_get_semesters();
    my $lowdate = $self->_get_low_date();

    # Get total TAG allocation for semesters
    my $projdb = OMP::DB::Project->new(DB => $self->db);
    my $alloc = 0;
    for my $sem (@semesters) {
        $alloc += $projdb->getTotalAlloc($telescope, $sem);
    }

    # DEBUG
    printf "\nTotal allocation: [%.1f] hours\n", $alloc->hours;

    # Offset correction: get total time spent on the projects
    # we have accounts for, prior to date of the first account.
    # Subtract this number from the total allocation.
    # Do not bother if no low date, implying no science projects
    my $offset = Time::Seconds->new(0);
    if (defined $lowdate) {
        $lowdate -= 1;  # Yesterday
        my @accts = $self->_get_non_special_accts();
        my %projectids = map {$_->projectid, undef} @accts;
        my $tdb = OMP::DB::TimeAcct->new(DB => $self->db);
        my $query = OMP::Query::TimeAcct->new(HASH => {
            date => {max => $lowdate->datetime},
            projectid => [keys %projectids],
        });
        my $offset_grp = $tdb->queryTimeSpent($query);
        $offset_grp->telescope($telescope);

        #DEBUG
        printf "Offset (time spent on these projects in previous semesters): [%.1f] hours\n",
            $offset_grp->science_time->hours;

        $offset = $offset_grp->science_time;
    }

    my $final_alloc = $alloc - $offset;

    #DEBUG
    printf "Total allocation minus offset: [%.1f] hours\n", $final_alloc->hours;

    # Get all accounts grouped by UT date
    my $groups = $self->by_date(1);

    # Map Y values to X (date)
    my $sci_total = 0;
    my (@sci_cumul, @fault, @weather, @ec);
    for my $x (sort keys %$groups) {
        $sci_total += $groups->{$x}->science_time;

        push @sci_cumul, [$x, $sci_total / $final_alloc * 100];
        push @weather, [$x, $groups->{$x}->weather_loss->hours];
        push @ec, [$x, $groups->{$x}->ec_time->hours];
        push @fault, [$x, $groups->{$x}->fault_loss->hours];
    }

    my %returnhash = (
        science => \@sci_cumul,
        fault => \@fault,
        ec => \@ec,
        weather => \@weather,
        __ALLOC__ => $alloc,
        __OFFSET__ => $offset,
    );

    for my $stat (keys %returnhash) {
        next if $stat eq 'science' or $stat =~ /^__/;
        @{$returnhash{$stat}} = OMP::PlotHelper->bin_up(
            size => 7,
            method => 'sum',
            values => $returnhash{$stat}
        );
    }

    return %returnhash;
}

=item B<by_date>

Group all the C<OMP::Project::TimeAcct> objects by UT date.  Store
each group in an C<OMP::Project::TimeAcct::Group> object.  Return a hash indexed
by UT date where each key points to an C<OMP::Project::TimeAcct::Group> object.

    $groups = $tg->by_date(1);

If the optional argument is true, The returned hash is indexed by
an integer modified Julian date.

=cut

sub by_date {
    my $self = shift;
    my $mjd = shift;
    my @acct = $self->accounts;

    my $method = ($mjd ? 'mjd' : 'ymd');
    # Group by UT date
    my %accts;
    for my $acct (@acct) {
        push @{$accts{$acct->date->$method}}, $acct;
    }

    # Convert each group into an OMP::Project::TimeAcct::Group object
    for my $ut (keys %accts) {
        $accts{$ut} = $self->new(
            accounts => $accts{$ut},
            telescope => $self->telescope,
            DB => $self->db,
        );
    }

    return \%accts;
}

=item B<populate>

Populate the object.

    $tg->populate(
        accounts => \@accounts,
        telescope => $tel);

Arguments are to be given in hash form, with the keys being the names
of the accessor methods.

=cut

sub populate {
    my $self = shift;
    my %args = @_;

    for my $key (keys %args) {
        my $method = lc($key);
        if ($self->can($method)) {
            $self->$method($args{$key});
        }
    }
}

=item B<pushacct>

Add more accounts to the group.

    $tg->pushacct(@acct);
    $tg->pushacct(\@acct);

Takes either an array or a reference to an array of C<OMP::Project::TimeAcct>
objects.  Returns true on success.

=cut

sub pushacct {
    my $self = shift;
    my @addacct = @_;
    my @currentacct = $self->accounts;
    $self->accounts([@currentacct, @addacct]);
    return 1;
}

=item B<remdupe>

Remove duplicate accounts from the group.

    $tg->remdupe();

=cut

sub remdupe {
    my $self = shift;
    my @acct = $self->accounts;

    my @unique_acct;
    for my $old (@acct) {
        my $exists = 0;
        for my $unique (@unique_acct) {
            if ($old == $unique) {
                $exists = 1;
            }
        }
        push @unique_acct, $old
            unless ($exists);
    }

    $self->accounts(@unique_acct);

    return 1;
}

=item B<summary>

Summarize the contents of the time accounting records.

    $summary = $tg->summary($format);

where C<$format> controls the contents of the hash returned
to the user. Valid formats are:

=over 4

=item all

Return a hash with keys "total", "confirmed", "pending"
regardless of the mix of projects or dates.

=item bydate

Hash includes primary keys of UT date (YYYY-MM-DD)
where each sub-hash contains keys as for "all".

=item byproject

Hash includes primary keys of project ID where
where each sub-hash contains keys as for "all".

=item byprojdate

Hash includes primary keys of project and each
project hash contains keys of UT date. The corresponding
sub-hash contains keys as for "all".

=item byshftprj

Hash includes primary keys of $shifttype", and each
sub-hash contains keys of project. Their sub-hashes
have keys of UT date, and theirs have keys as for
"all".

=item byshftremprj

Hash includes primary keys made by combining
ShiftType and Remote stauts, and each sub-hash
contains keys of project, then UTDATE belwo that. Their sub-hashes have keys
as for "all".

=back

The UT hash key is of the form "YYYY-MM-DD". Project ID is upper cased.

ShiftType-Remote hash key is always a combination of UPPERCASED "$shifttype_$remote"

=cut

sub summary {
    my $self = shift;
    my $format = lc shift;

    my @acct = $self->accounts;

    # loop over each object populating a results hash
    my %results;
    for my $acct (@acct) {
        # extract the information
        my $p = $acct->projectid;
        my $t = $acct->timespent;
        my $ut = $acct->date->strftime('%Y-%m-%d');
        my $c = $acct->confirmed;
        my $shft = $acct->shifttype;
        $shft = 'UNKNOWN' unless defined $shft;
        my $rem = $acct->remote;
        unless (defined $rem) {
            $rem = "UNKNOWN";
        }
        my $shftrem = "$shft" . "_" . "$rem";

        # big switch statement
        my $ref;
        if ($format eq 'all') {
            # top level hash
            $ref = \%results;
        }
        elsif ($format eq 'bydate') {
            # store using UT date
            unless (exists $results{$ut}) {
                $results{$ut} = {};
            }
            $ref = $results{$ut};
        }
        elsif ($format eq 'byproject') {
            # store using project ID
            unless (exists $results{$p}) {
                $results{$p} = {};
            }
            $ref = $results{$p};
        }
        elsif ($format eq 'byprojdate') {
            # store using project ID AND ut date
            unless (exists $results{$p}{$ut}) {
                $results{$p}{$ut} = {};
            }
            $ref = $results{$p}{$ut};
        }
        elsif ($format eq 'byshftprj') {
            # store using shifttype AND  projectID
            unless (exists $results{$shft}{$p}) {
                $results{$shft}{$p} = {};
            }
            $ref = $results{$shft}{$p};

        }
        elsif ($format eq 'byshftremprj') {
            unless (exists $results{$shftrem}{$p}) {
                $results{$shftrem}{$p} = {};
            }
            $ref = $results{$shftrem}{$p};
        }
        else {
            throw OMP::Error::FatalError(
                "Unknown format for TimeAcct summarizing: $format");
        }

        $ref->{pending} = Time::Seconds->new(0) unless exists $ref->{pending};
        $ref->{confirmed} = Time::Seconds->new(0) unless exists $ref->{confirmed};
        $ref->{total} = Time::Seconds->new(0) unless exists $ref->{total};

        # now store/increment the time
        if ($c) {
            $ref->{confirmed} += $t;
        }
        else {
            $ref->{pending} += $t;
        }
        $ref->{total} += $t;
    }

    return \%results;
}

=back

=head2 Internal Methods

=over 4

=item B<_get_non_special_accts>

Return only non-special accounts.

    @accts = $self->_get_non_special_accts();

=cut

sub _get_non_special_accts {
    my $self = shift;

    # Create regexp to filter out special projects
    my $telpart = join('|', OMP::Config->getData('defaulttel'));
    my $specpart = join('|', qw/CAL EXTENDED OTHER WEATHER _SHUTDOWN/);
    my $regexp = qr/^(${telpart})(${specpart})$/;

    # Filter out "__FAULT__" accounts and accounts that are named
    # something like TELESCOPECAL, etc.
    my @acct = grep {$_->projectid !~ $regexp and $_->projectid ne '__FAULT__'}
        $self->accounts;

    if (wantarray) {
        return @acct;
    }
    else {
        return \@acct;
    }
}

=item B<_get_accts>

Return either science accounts (accounts that are not associated with
projects in the E&C queue) or E&C.  Special
accounts are not returned (WEATHER, CAL, EXTENDED, OTHER, _SHUTDOWN, __FAULT__).

    @accts = $self->_get_accts('sci'|'eng');

Argument is a string that is either 'sci' or 'eng'.  Returns either
an array or an array reference.  Returns an empty list if no accounts
could be returned.

=cut

sub _get_accts {
    my $self = shift;
    my $arg = shift;

    throw OMP::Error::BadArg("Argument must be either 'sci' or 'eng'")
        unless ($arg eq 'sci' or $arg eq 'eng');

    # Get the regular accounts
    my @acct = $self->_get_non_special_accts;

    # Return immediately if we didn't get any accounts back
    return unless defined $acct[0];

    # Get project objects, using a different query depending on whether
    # we are returning science or engineering accounts
    my $db = OMP::DB::Project->new(DB => $self->db);
    my %hash = ();

    my $telescope = $self->telescope;
    $hash{'telescope'} = $telescope if defined $telescope;

    if ($arg eq 'sci') {
        # Get all the projects in the semesters that we have time
        # accounts for.
        $hash{'semester'} = $self->_get_semesters();
    }
    else {
        # Get projects in the EC queue
        $hash{'country'} = 'EC';
        $hash{'isprimary'} = 1;
    }

    my $query = OMP::Query::Project->new(HASH => \%hash);
    my $projects = $db->listProjects($query);
    my %projects = map {$_->projectid, $_} @$projects;

    if ($arg eq 'sci') {
        # Only keep non-EC projects
        @acct = grep {
            exists $projects{$_->projectid}
                and $projects{$_->projectid}->isScience
        } @acct;
    }
    else {
        # Only keep EC projects
        @acct = grep {exists $projects{$_->projectid}} @acct;
    }

    if (wantarray) {
        return @acct;
    }
    else {
        return \@acct;
    }
}

=item B<_get_special_accts>

Return only accounts with project IDs that begin with a telescope
name and end with the given string.  Does not return the special
accounts with the project ID '__FAULT__'.

    @accts = $self->_get_special_accts("CAL");

If a telescope can not be determined, returns no accounts.

=cut

sub _get_special_accts {
    my $self = shift;
    my $proj = shift;

    my @accounts = $self->accounts;
    my $regexpart = $self->telescope;

    # if telescope is not defined that means there were no science
    # accounts (else _get_telescope would have worked something out)
    # and we were not told the telescope explicitly at construction
    if (! defined $regexpart) {
        return ();
    }

    # Now look for matching projects
    @accounts = grep {$_->projectid =~ /^(${regexpart})${proj}$/} @accounts;
    if (wantarray) {
        return @accounts;
    }
    else {
        return \@accounts;
    }
}

=item B<_get_low_date>

Retrieve the date of the first non-special account object.

    $date = $self->_get_low_date();

Returns undef if all accounts are special.

=cut

sub _get_low_date {
    my $self = shift;
    my @accts = $self->_get_non_special_accts;
    if (@accts) {
        return $accts[0]->date;
    }
    return undef;
}

=item B<_get_semesters>

Retrieve the list of semesters that the science time accounts span.

    @sems = $self->_get_semesters();

Returns a list, or reference to a list.

=cut

sub _get_semesters {
    my $self = shift;
    my @accts = $self->_get_non_special_accts;
    my $tel = $self->telescope;
    my %sem = map {
        OMP::DateTools->determine_semester(date => $_->date, tel => $tel),
            undef
    } @accts;

    if (wantarray) {
        return keys %sem;
    }
    else {
        return [keys %sem];
    }
}

=item B<_get_telescope>

Retrieve the telescope name associated with the first time account object
which has one, or retrieve from the database the telescope name for the
project ID of the first non-special account object.

    $tel = $self->_get_telescope();

B<Note:> the C<telescope> method should be used in preference to this as it
will store the telescope name in the object.

=cut

sub _get_telescope {
    my $self = shift;

    foreach my $acct (@{$self->accounts}) {
        my $telescope = $acct->telescope;
        return $telescope if defined $telescope;
    }

    my @accts = $self->_get_non_special_accts;
    if (@accts) {
        my $db = OMP::DB::Project->new(
            DB => $self->db);

        return $db->getTelescope($accts[0]->projectid);
    }

    return undef;
}

=item B<_mutate_time>

Reset the time or store a new time for one of the object properties.

    $self->_mutate_time("WeatherLoss", 32000);

=cut

sub _mutate_time {
    my $self = shift;
    my $key = shift;
    my $time = shift;

    unless (defined $time) {
        $self->{$key} = undef;
    }
    else {
        # Set the new value
        $time = Time::Seconds->new($time)
            unless UNIVERSAL::isa($time, "Time::Seconds");

        $self->{$key} = $time;
    }
}

1;

__END__

=back

=head1 AUTHOR

Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2004 Particle Physics and Astronomy Research Council.
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
