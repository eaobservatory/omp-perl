package OMP::Project;

=head1 NAME

OMP::Project - Information relating to a single project

=head1 SYNOPSIS

    $proj = OMP::Project->new(projectid => $projectid);

    $proj->pi("somebody\@somewhere.edu");

    %summary = $proj->summary;
    $xmlsummary = $proj->summary;

=head1 DESCRIPTION

This class manipulates information associated with a single OMP
project.

It is not responsible for storing or retrieving that information from
a project database even though the information stored in that project
database exactly matches that in the class (the database is a
persistent store but the object does not implement that persistence).

=cut

use 5.006;
use strict;
use warnings;
use warnings::register;
use Carp;
use Time::Seconds;
use OMP::SiteQuality;
use OMP::User;

use Scalar::Util qw/looks_like_number/;
use List::Util qw/min max/;

our $VERSION = '2.000';

# Delimiter for co-i strings
our $DELIM = ':';

# Name for the internal cache key. Specify it here since it
# is used in two different methods without having an
# explicit accessor!!
my $TAGPRI_KEY = '__tagpri_cache';

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

Object constructor. Takes a hash as argument, the keys of which can be
used to prepopulate the object. The key names must match the names of
the accessor methods (ignoring case). If they do not match they are
ignored (for now).

    $proj = OMP::Project->new(%args);

Arguments are optional (although at some point a project ID would be
helpful).

=cut

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;

    my $proj = bless {
        Semester => undef,
        Allocated => Time::Seconds->new(0),
        Title => '',
        Telescope => undef,
        ProjectID => undef,

        # weather constrints
        TauRange => undef,
        SeeingRange => undef,
        CloudRange => undef,
        SkyRange => undef,

        # Country and tag priority now
        # can have more than one value
        PrimaryQueue => undef,
        Queue => {},
        TAGAdjustment => {},

        PI => undef,
        CoI => [],

        Remaining => undef,  # so that it defaults to allocated
        Pending => Time::Seconds->new(0),
        Support => [],
        State => 1,
        Contactable => {},
        OMPAccess => {},
        ExpiryDate => undef,
        DirectDownload => 0,
    }, $class;

    # Deal with arguments
    if (@_) {
        my %args = @_;

        # rather than populate hash directly use the accessor methods
        # allow for upper cased variants of keys
        for my $key (keys %args) {
            my $method = lc($key);
            if ($proj->can($method)) {
                $proj->$method($args{$key});
            }
        }

    }

    return $proj;
}

=back

=head2 Accessor Methods

=over 4

=item B<state>

The state of the project. Truth indicates that the project is enabled,
false means that the project is currently disabled. If the project is
disabled you will not be able to do queries on it by default.

=cut

sub state {
    my $self = shift;
    if (@_) {
        my $state = shift;
        # force binary
        $state = ($state ? 1 : 0);
        $self->{State} = $state;
    }
    return $self->{State};
}

=item B<allocated>

The time allocated for the project (in seconds).

    $time = $proj->allocated;
    $proj->allocated($time);

Returned as a C<Time::Seconds> object (this allows easy conversion
to hours, minutes and seconds).

Note that for semesters 02B (SCUBA) no projects were allocated time at
non-contiguous weather bands. In the future this will not be the case
so whilst this method will always return the total allocated time the
internals of the module may be much more complicated.

=cut

sub allocated {
    my $self = shift;
    if (@_) {
        # if we have a Time::Seconds object just store it. Else create one.
        my $time = shift;
        $time = Time::Seconds->new($time)
            unless UNIVERSAL::isa($time, "Time::Seconds");
        $self->{Allocated} = $time;
    }
    return $self->{Allocated};
}

=item B<taurange>

Range of CSO tau in which the observations can be performed (the allocation
is set for this tau range). No observations can be performed when the CSO
tau is not within this range.

    $range = $proj->taurange();

Returns an C<OMP::Range> object.

If a single number is provided it is assumed to be specifying the
upper bound of a new range object.

This interface will change when non-contiguous tau ranges are supported.
(The method may even disappear).

=cut

sub taurange {
    my $self = shift;
    if (@_) {
        my $range = shift;
        if (defined $range && !ref($range) && looks_like_number($range)) {
            $range = OMP::Range->new(Max => $range);
        }
        croak "Tau range must be specified as an OMP::Range object"
            unless UNIVERSAL::isa($range, "OMP::Range");
        $self->{TauRange} = $range;
    }
    return $self->{TauRange};
}

=item B<seeingrange>

Range of seeing conditions (in arcseconds) in which the observations
can be performed. No observations can be performed when the seeing is
not within this range.

    $range = $proj->seeingrange();

Returns an C<OMP::Range> object (or undef).

If a single number is provided it is assumed to be specifying the
upper bound of a new range object.

=cut

sub seeingrange {
    my $self = shift;
    if (@_) {
        my $range = shift;
        if (defined $range && !ref($range) && looks_like_number($range)) {
            $range = OMP::Range->new(Max => $range);
        }
        croak "Seeing range must be specified as an OMP::Range object"
            unless UNIVERSAL::isa($range, "OMP::Range");
        $self->{SeeingRange} = $range;
    }
    return $self->{SeeingRange};
}

=item B<cloudrange>

Cloud constraints as a percentage attenuation variability, stored as an
C<OMP::Range> object. C<undef> indicates no constraints,

    $cloud = $proj->cloudrange();

Special cases values of 0, 1 and 101 to match the old non-percentage
implementation. If a number between 2 and 100 is provided, it is
assumed to be the upper limit.

=cut

sub cloudrange {
    my $self = shift;
    if (@_) {
        my $range = shift;
        if (defined $range && !ref($range) && looks_like_number($range)) {
            $range = OMP::SiteQuality::upgrade_cloud($range);
        }
        croak "Cloud range must be specified as an OMP::Range object"
            unless UNIVERSAL::isa($range, "OMP::Range");
        $self->{CloudRange} = $range;
    }
    return $self->{CloudRange};
}

=item B<skyrange>

Range of sky brightness conditions in which the observations can be
performed. No observations can be performed when the sky is not within
this range. The filter and units for which this sky brightness is
defined is dependent on the telescope implementation with the caveat
that when magnitudes are used the range may be flipped from what was
submitted in the OT in order for the contains() method and stringification
to work correctly.

    $range = $proj->skyrange();

Returns an C<OMP::Range> object (or undef).

If a single number is provided it is assumed to be specifying the
upper bound of a new range object.

=cut

sub skyrange {
    my $self = shift;
    if (@_) {
        my $range = shift;
        if (defined $range && !ref($range) && looks_like_number($range)) {
            $range = OMP::Range->new(Max => $range);
        }
        croak "Sky range must be specified as an OMP::Range object"
            unless UNIVERSAL::isa($range, "OMP::Range");
        $self->{SkyRange} = $range;
    }
    return $self->{SkyRange};
}


=item B<telescope>

The telescope on which the project has been allocated time.

    $time = $proj->telescope;
    $proj->telescope($time);

This is a string and not a C<Astro::Telescope> object.

Telescope is always upper-cased.

=cut

sub telescope {
    my $self = shift;
    if (@_) {$self->{Telescope} = uc(shift);}
    return $self->{Telescope};
}

=item B<coi>

The names of any co-investigators associated with the project.

Return the Co-Is as an arrayC<OMP::User> objects:

    @names = $proj->coi;

Return a colon-separated list of the Co-I user ids:

    $names = $proj->coi;

Provide all the Co-Is for the project as an array of C<OMP::User>
objects. If a supplied name is a string it is assumed to be a user
ID that should be retrieved from the database:

    $proj->coi(@names);
    $proj->coi(\@names);

Provide a list of colon-separated user IDs:

    $proj->coi("name1:name2");

Co-Is are by default non-contactable so no call is made to
the C<contactable> method if the CoI information is updated.

=cut

sub coi {
    my $self = shift;

    my $key = 'CoI';

    if (scalar @_) {
        my @user = $self->_handle_role(lc($key), @_);
        $self->{$key} = [@user];
    }

    my $list = $self->{$key};
    wantarray() and return @{$list};
    return join $DELIM, map $list->[$_]->userid(), 0 .. $#{$list};
}

=item B<support>

The names of any staff contacts associated with the project.

Return the names as an arrayC<OMP::User> objects:

    @names = $proj->support;

Return a colon-separated list of the support user ids:

    $names = $proj->support;

Provide all the staff contacts for the project as an array of
C<OMP::User> objects. If a supplied name is a string it is assumed to
be a user ID that should be retrieved from the database:

    $proj->support(@names);
    $proj->support(\@names);

Provide a list of colon-separated user IDs:

    $proj->support("name1:name2");

By default when a support contact is updated it is made contactable and
granted OMP access. If this is not the case the C<contactable> and
C<omp_access> methods must be called explicitly.

=cut

sub support {
    my $self = shift;

    my $key = 'Support';

    if (scalar @_) {
        my @user = $self->_handle_role(lc($key), @_);

        # Force being contactable and having OMP access.
        for my $userid (map {$_->userid()} @user) {
            $self->contactable($userid => 1);
            $self->omp_access($userid => 1);
        }

        $self->{$key} = [@user];
    }

    my $list = $self->{$key};
    wantarray() and return @{$list};
    #  OMP::User object stringifies to user name not user id!
    return join $DELIM, map $list->[$_], 0 .. $#{$list};
}

sub _handle_role {
    my $self = shift;
    my $role = shift;

    scalar @_ or return;

    my @ok = qw/coi support/;
    my $ok_re = join '|', @ok;
    $ok_re = qr/^(?: $ok_re )$/x;

    unless (defined $role) {
        throw OMP::Error::BadArgs('No role was given.');
    }
    else {$role = lc $role;}

    $role =~ /$ok_re/
        or throw OMP::Error::BadArgs(
        "Unknown role, $role, given; known: " . join ', ', @ok);

    my @names;
    if (ref($_[0]) eq 'ARRAY') {
        @names = @{$_[0]};
    }
    elsif (defined $_[0]) {
        # If the first name isnt valid assume none are
        @names = @_;
    }

    # Now go through the array retrieving the OMP::User
    # objects and strings
    my @users;
    for my $name (@names) {
        if (UNIVERSAL::isa($name, "OMP::User")) {
            push @users, $name;
        }
        else {
            # Split on delimiter
            my @split = split /$DELIM/, $name;

            # Convert them to OMP::User objects
            push @users, map {OMP::User->new(userid => $_)} @split;
        }
    }

    return _uniq_users(@users);
}

# Expects list of OMP::User objects.
sub _uniq_users {
    my (@user) = @_;

    my %seen;
    return map {$_->[1]}
        grep {! $seen{$_->[0]} ++}
        map {[$_->userid(), $_]}
        @user;
}

=item B<coiemail>

The email addresses of co-investigators associated with the project.

    @email = $proj->coiemail;
    $emails = $proj->coiemail;

If this method is called in a scalar context the addresses will be
returned as a single string joined by a comma.

Consider using the C<coi> method to access the C<OMP::User> objects
directly. Email addresses can not be modified using this method.

=cut

sub coiemail {
    my $self = shift;

    # Only use defined emails
    my @email = grep {$_} map {$_->email} $self->coi;

    # Return either the array of emails or a delimited string
    if (wantarray) {
        return @email;
    }
    else {
        # This returns empty string if we dont have anything
        return join($DELIM, @email);
    }
}

=item B<supportemail>

The email addresses of co-investigators associated with the project.

    @email = $proj->supportemail;
    $emails = $proj->supportemail;

If this method is called in a scalar context the addresses will be
returned as a single string joined by a comma.

Consider using the C<support> method to access the C<OMP::User> objects
directly. Email addresses can not be modified using this method.

=cut

sub supportemail {
    my $self = shift;

    my @email = map {$_->email} $self->support;
    # Return either the array of emails or a delimited string
    if (wantarray) {
        return @email;
    }
    else {
        # This returns empty string if we dont have anything
        return join($DELIM, @email);
    }
}

=item B<country>

Country from which project is allocated.

    $id = $proj->country;

Stores the country in a hash, but does not override previous country
entries or assign a priority. Use the C<queue> method for full control
of the contents of the country and priority.

    $proj->country(@countries);
    $proj->country(\@countries);

In scalar context returns simply the primary queue (for backwards
compatibility reasons) unless that is not defined (unlikely) in which
case all the countries are returned as a "/"-separated string. In list
context returns all the countries separately. The country order is
sorted alphabetically.

If this is the first country to be stored and a TAG priority
has been set previously, then that TAG priority is applied to
all the new countries, and the first country is configured as
the primary queue (unless the primary queue is already defined).

Storing a country that has already been stored does not
clear the TAG priority.

=cut

sub country {
    my $self = shift;
    if (@_) {
        # trap array ref
        my @c = (ref($_[0]) ? @{$_[0]} : @_);

        # are we meant to apply a cached tag priority?
        # Yes, if there are no previous countries
        my $tagpri;
        my %queue = $self->queue;

        if (keys %queue) {
            # go through the existing entries, and remove
            # any from the list that already exist. We do not
            # want to clear old tag priorities
            @c = grep {! exists $queue{uc($_)}} @c;
        }
        else {
            $tagpri = $self->{$TAGPRI_KEY};
        }

        # configure primary queue since we know the order
        if (! keys %queue && ! defined $self->primaryqueue) {
            $self->primaryqueue($c[0]);
        }

        # we can store without a TAG priority initially. We have to assume this value will be
        # reinforced later
        $self->queue(
            map {
                uc($_) => (defined $tagpri
                    ? ($tagpri + $self->tagadjustment($_))
                    : undef)
            } @c);

    }

    if (wantarray) {
        return sort keys %{$self->queue};
    }
    else {
        # Return the primary country
        my $country = $self->primaryqueue;
        return (defined $country
            ? $country
            : join("/", sort keys %{$self->queue}));
    }
}

=item B<primaryqueue>

Return or set the primary observing queue associated with this
project. This is the queue/country that will be used to associate
the project progress with a particular country.

Will be set automatically as the first country supplied to the
C<country()> or C<queue()> method [the latter may give a random result
if a hash is supplied].

On set, this queue is automatically added to the C<queue> details.

See C<country> in scalar context for an alternative method of obtaining
this value.

=cut

sub primaryqueue {
    my $self = shift;
    if (@_) {
        my $c = uc(shift);
        $self->{PrimaryQueue} = $c;
        $self->country($c);
    }
    return $self->{PrimaryQueue};
}

=item B<pending>

The amount of time (in seconds) that is to be removed from the
remaining project allocation pending approval by the queue managers.

    $time = $proj->pending();
    $proj->pending($time);

Returns a C<Time::Seconds> object.

=cut

sub pending {
    my $self = shift;
    if (@_) {
        # if we have a Time::Seconds object just store it. Else create one.
        my $time = shift;
        $time = Time::Seconds->new($time)
            unless UNIVERSAL::isa($time, "Time::Seconds");
        $self->{Pending} = $time;
    }
    return $self->{Pending};
}

=item B<pi>

Name of the principal investigator.

    $pi = $proj->pi;

Returned and stored as a C<OMP::User> object.

By default when a PI is updated it is made contactable. If this
is not the case the C<contactable> method must be called explicitly.

=cut

sub pi {
    my $self = shift;
    if (@_) {
        my $pi = shift;
        throw OMP::Error::BadArgs(
            "PI must be of type OMP::User but got '"
            . (defined $pi ? $pi : "<undef>") . "'")
            unless UNIVERSAL::isa($pi, "OMP::User");
        $self->{PI} = $pi;

        # And force them to be contactable
        my $userid = $pi->userid;
        $self->contactable($userid => 1);
        $self->omp_access($userid => 1);
    }
    return $self->{PI};
}

=item B<piemail>

Email address of the principal investigator.

    $email = $proj->piemail;

=cut

sub piemail {
    my $self = shift;
    return (defined $self->pi() ? $self->pi->email : '');
}

=item B<projectid>

Project ID.

    $id = $proj->projectid;

The project ID is always upcased.

=cut

sub projectid {
    my $self = shift;
    if (@_) {$self->{ProjectID} = uc(shift);}
    return $self->{ProjectID};
}


=item B<remaining>

The amount of time remaining on the project (in seconds).

    $time = $proj->remaining;
    $proj->remaining($time);

If the value is not defined, the allocated value is automatically
inserted.  This value never includes the time pending on the
project. To get the time remaining taking into account the time
pending use method C<allRemaining> instead.

Returns a C<Time::Seconds> object.

=cut

sub remaining {
    my $self = shift;
    if (@_) {
        # if we have a Time::Seoncds object just store it. Else create one.
        my $time = shift;
        $time = Time::Seconds->new($time)
            unless UNIVERSAL::isa($time, "Time::Seconds");
        $self->{Remaining} = $time;
    }
    else {
        $self->{Remaining} = $self->allocated
            unless defined $self->{Remaining};
    }
    return $self->{Remaining};
}

=item B<allRemaining>

Time remaining on the project including any time pending. This
is simply that stored in the C<remaining> field minus that stored
in the C<pending> field.

    $left = $proj->allRemaining;

Can be negative.

=cut

sub allRemaining {
    my $self = shift;
    my $all_left = $self->remaining - $self->pending;
    return $all_left;
}

=item B<percentComplete>

The amount of time spent on this project as a percentage of the amount
allocated.

    $completed = $proj->percentComplete;

Result is multiplied by 100 before being returned.

Returns 100% if no time has been allocated.

=cut

sub percentComplete {
    my $self = shift;
    my $alloc = $self->allocated;
    if ($alloc > 0.0) {
        return $self->used / $self->allocated * 100;
    }
    return 100;
}

=item B<used>

The amount of time (in seconds) used by the project so far. This
is calculated as the difference between the allocated amount and
the time remaining on the project (the time pending is assumed to
be included in this calculation).

    $time = $proj->used;

This value can exceed the allocated amount.

=cut

sub used {
    my $self = shift;
    return ($self->allocated - $self->allRemaining);
}

=item B<semester>

The semester for which the project was allocated time.

    $semester = $proj->semester;

Semester is upper-cased.

=cut

sub semester {
    my $self = shift;
    if (@_) {$self->{Semester} = uc(shift);}
    return $self->{Semester};
}

=item B<tagpriority>

The priority of this project relative to all the other projects
in the queue. This priority is determined by the Time Allocation
Group (TAG). Since a project can have different priorities in
different queues, the queue name (aka country) must be supplied.

    $pri = $proj->tagpriority($country);

If multiple countries are specified (using a reference to an array),
corresponding priorities are returned (undef if project is not
associated with that country).

    @pris = $proj->tagpriority(\@countries);

If no country is supplied, all priorities are returned. In scalar
context only the primary queue tag priority is returned unless that is
not defined in which case all priorities are returned as a single
comma-separated string, all are returned in list context. They are
returned in an order corresponding to the alphabetical order of the
countries.

    $pri = $proj->tagpriority;
    @pri = $proj->tagpriority;

If the single argument is a number, it is deemed to be the priority
for all projects. Multiple priorities can be set using a hash in list
form or reference to a hash (an error will be raised if the country
does not exist; this differs from the C<queue()> method.). Differing
priorities can not be set for multiple queues without specifying the
specific queue since the internal ordering of the countries is not
defined.

    $proj->tagpriority(CA => 1, UK => 5);
    $proj->tagpriority(\%update);

Use the queue() method to set priorities and country information.

If this method is called before a country is associated with the
object then, for backwards compatibility reasons, the TAG priority
is cached and applied if a country is set explicitly with the
C<country> method (and only the first time that is used).

Note that this is the TAG priority and any TAG adjustments will not be
included and should not be specified. Note that setting a tagpriority
using this method relies on the tag adjustment being correct at the
time.

=cut

sub tagpriority {
    my $self = shift;
    my $delim = ",";  # for scalar context
    if (@_) {
        if (scalar @_ == 1 && ref($_[0]) ne 'HASH') {
            # if we have a number, it is being set
            if ($_[0] =~ /\d/a) {
                # set every priority
                my @c = $self->country;
                if (@c) {
                    for my $c (@c) {
                        $self->queue($c => ($_[0] + $self->tagadjustment($c)));
                    }
                }
                else {
                    # Store it for later [uncorrected for Adj]
                    $self->{$TAGPRI_KEY} = $_[0];
                }
            }
            else {
                # A country has been requested or more than one
                my @c = (ref($_[0]) ? @{$_[0]} : @_);
                my %queue = $self->queue;
                my @pris = map {$queue{uc($_)} - $self->tagadjustment($_)} @c;
                return (wantarray ? @pris : join($delim, @pris));
            }
        }
        else {
            # More than one argument, assume hash
            my %queue = $self->queue;
            my %args = (ref($_[0]) eq 'HASH' ? %{$_[0]} : @_);
            for my $c (keys %args) {
                my $uc = uc($c);
                # check that the country is supported
                croak "Country $c not recognized"
                    unless exists $queue{$uc};
                $self->queue($c => ($args{$c} + $self->tagadjustment($c)));
            }
        }
    }

    # Return everything as a list or a single string
    my %queue = $self->queue;
    my @countries = sort map {$queue{$_} - $self->tagadjustment($_)} keys %queue;

    if (wantarray) {
        return @countries;
    }
    else {
        my $primary = $self->primaryqueue;
        if (! defined $primary || ! exists $queue{$primary}) {
            return join($delim, @countries);
        }
        else {
            return ($queue{$primary} - $self->tagadjustment($primary));
        }
    }
}

=item B<title>

The title of the project.

    $title = $proj->title;

=cut

sub title {
    my $self = shift;
    if (@_) {$self->{Title} = shift;}
    return $self->{Title};
}

=item investigators

Return user information for all those people with registered
involvement in the project. This is simply an array of PI and
Co-I C<OMP::User> objects.

    my @users = $proj->investigators;

In scalar context acts just like an array. This may change.

=cut

sub investigators {
    my $self = shift;

    # Get all the User objects (forcing list context in coi method)
    my @inv = ($self->pi, $self->coi);
    return @inv;
}

=item contacts

Return an array of C<OMP::User> objects for all those people
associated with the project. This is the investigators and support
scientists who are listed as "contactable".

    my @users = $proj->contacts;

In scalar context acts just like an array. This may change.

=cut

sub contacts {
    my $self = shift;

    # Get all the User objects
    # Store in a hash to weed out duplicates
    my %users = map {$_->userid, $_}
        grep {$self->contactable($_->userid) and $_->email}
        ($self->investigators, $self->support);

    return map {$users{$_}} keys %users;
}

=item B<contactable>

A hash (indexed by OMP user ID) indicating whether a particular person
associated with this project should be sent email notifications concerning
a change in project state. If a particular user is not present in this
hash the assumption should be that they do not want to be contacted.

A case can be made for always contacting the PI and support scientists.

Values can be modified by specifying a set of key value pairs:

    $proj->contactable(TIMJ => 1, JRANDOM => 0);

and the current state for a user can be retrieved by specifying a single
user id:

    $iscontactable = $proj->contactable('TIMJ');

The key is always upper-cased.

Returns a hash reference in scalar context and a list in list context
when no arguments are supplied.

    %contacthash = $proj->contactable;
    $cref = $proj->contactable;

=cut

sub contactable {
    my $self = shift;
    if (@_) {
        if (scalar @_ == 1) {
            # A single key
            return $self->{Contactable}->{uc($_[0])};
        }
        else {
            # key/value pairs
            my %args = @_;
            for my $u (keys %args) {
                # make sure we are case-insensitive
                $self->{Contactable}->{uc($u)} = $args{$u};
            }
        }
    }

    # return something
    if (wantarray) {
        return %{$self->{Contactable}};
    }
    else {
        return $self->{Contactable};
    }
}

=item B<omp_access>

A hash (indexed by OMP user ID) indicating whether a particular person
should have OMP access.  This works in the same way as the C<contactable>
method.

=cut

sub omp_access {
    my $self = shift;
    if (@_) {
        if (scalar @_ == 1) {
            # A single key
            return $self->{OMPAccess}->{uc($_[0])};
        }
        else {
            # key/value pairs
            my %args = @_;
            for my $u (keys %args) {
                # make sure we are case-insensitive
                $self->{OMPAccess}->{uc($u)} = $args{$u};
            }
        }
    }

    # return something
    if (wantarray) {
        return %{$self->{OMPAccess}};
    }
    else {
        return $self->{OMPAccess};
    }
}

=item B<queue>

Queue entries and corresponding priorities (see also C<country> and
C<tagpriority> methods for alternative views). Returns a hash with
keys of "country" and values of priority. Note that the priority here
is the combination of the TAG allocated priority and any TAG
adjustment provided in the queue. See the C<tagpriority> and
C<tagadjustment> methods to obtain the individual parts.

    %queue = $proj->queue;

Returns a hash reference in scalar context:

    $ref = $proj->queue();

Can be used to set countries and priorities:

    $proj->queue(CA => 22, UK => 1);

or

    $proj->queue(\%queue);

or as a special case, the current adjusted priority can be returned
for a single country:

    $pri = $proj->queue('CA');

Other country information is retained. The queue can be cleared with
the C<clearqueue> command.

The primary queue can not be configured automatically using this
method since the hash does not have a guaranteed order.

=cut

sub queue {
    my $self = shift;
    if (@_) {
        # if only a single arg it may be a ref or a queue name
        if (@_ == 1 && not ref($_[0])) {
            my $arg = uc(shift);
            if (exists $self->{Queue}->{$arg}) {
                return $self->{Queue}->{$arg};
            }
            else {
                return undef;
            }
        }
        else {
            # either a hash ref as first arg or a list
            my %args = (ref($_[0]) ? %{$_[0]} : @_);
            for my $c (keys %args) {
                $self->{Queue}->{uc($c)} = $args{$c};
            }
        }
    }

    if (wantarray) {
        return %{$self->{Queue}};
    }
    else {
        return $self->{Queue};
    }
}

=item B<tagadjustment>

Queue entries and corresponding TAG priority adjustments.  (see also
the C<queue> and C<tagpriority> methods).  Returns a hash with keys of
"country" and values of priority.

    %adj = $proj->tagadjustment;

Returns a hash reference in scalar context:

    $ref = $proj->tagadjustment();

Can be used to set adjustments within particular queues: (no check is
made that a particular queue exists in the C<queue>)

    $proj->tagadjustment(CA => -2, UK => +2);

or

    $proj->tagadjustment(\%queue);

If a single non reference is provided as argument it will be assumed to
be the queue name and the corresponding value will be returned. A 0
will be returned if the queue is not recognized.

    $adj = $proj->tagadjustment('CA');

=cut

sub tagadjustment {
    my $self = shift;
    if (@_) {
        # if only a single arg it may be a ref or a queue name
        if (@_ == 1 && not ref($_[0])) {
            my $arg = uc(shift);
            if (exists $self->{TAGAdjustment}->{$arg}) {
                return $self->{TAGAdjustment}->{$arg};
            }
            else {
                return 0;
            }
        }
        else {
            # either a hash ref as first arg or a list
            my %args = (ref($_[0]) ? %{$_[0]} : @_);
            for my $c (keys %args) {
                $args{$c} = 0 if (! defined $args{$c} || ref($args{$c}));
                $self->{TAGAdjustment}->{uc($c)} = $args{$c};
            }
        }
    }

    if (wantarray) {
        # list
        return %{$self->{TAGAdjustment}};
    }
    else {
        # hash ref
        return $self->{TAGAdjustment};
    }
}

=item B<clearqueue>

Clear all queue information (country and priority).

    $proj->clearqueue();

=cut

sub clearqueue {
    my $self = shift;
    %{$self->queue} = ();
    return;
}

=item B<isTOO>

Return true if the project is a Target-Of-Opportunity, else
returns false. Can not be used to set T-O-O status.

Returns true if the project is a T-O-O in any of the queues
it is associated with.

=cut

sub isTOO {
    my $self = shift;
    my @pri = $self->tagpriority;
    for my $p (@pri) {
        return 1 if $p <= 0;
    }
    return 0;
}

=item B<expirydate>

The expiry date of the project.

=cut

sub expirydate {
    my $self = shift;
    if (@_) {
        my $expiry = shift;
        $self->{'ExpiryDate'} = $expiry;
    }
    return $self->{'ExpiryDate'};
}

=item B<directdownload>

Whether direct download of data via the OMP server is allowed.

=cut

sub directdownload {
    my $self = shift;
    if (@_) {
        my $value = shift;
        $self->{'DirectDownload'} = ($value ? 1 : 0);
    }
    return $self->{'DirectDownload'};
}
=back

=head2 General Methods

=over 4

=item B<conditionstxt>

A short textual summary of the site quality constraints associated
with this project.

=cut

sub conditionstxt {
    my $self = shift;

    # currently only interested in the worst cloud conditions
    my $cloud = $self->cloudtxt;
    $cloud = '' if $cloud eq 'any';
    $cloud = substr($cloud, 0, 4) if $cloud;

    # Seeing. Need to fix lower end for prettification
    my $seeing = $self->seeingrange();
    my $seetxt = '';
    if ($seeing) {
        OMP::SiteQuality::undef_to_default('SEEING', $seeing);
        # only put text if we have a range
        unless (! $seeing->min && ! $seeing->max) {
            $seetxt = "s:$seeing";
        }
    }

    # Tau range (fix lower end for prettification)
    my $taurange = $self->taurange();
    my $tautxt = '';
    if ($taurange) {
        OMP::SiteQuality::undef_to_default('TAU', $taurange);
        unless (! $taurange->min && ! $taurange->max) {
            # only create if we have a range defined
            $tautxt = "t:$taurange";
        }
    }

    # Sky brightness
    my $skyrange = $self->skyrange();
    my $skytxt = '';
    if ($skyrange) {
        # map any leftover INF to undef
        $skyrange = OMP::SiteQuality::from_db('SKY', $skyrange);
        unless (! $skyrange->min && ! $skyrange->max) {
            # only create if we have a range defined
            $skytxt = "b:$skyrange";
        }
    }

    # form the text string
    my $txt = join(",", grep {$_} ($tautxt, $seetxt, $skytxt, $cloud));

    return ($txt ? $txt : 'any');
}

=item B<cloudtxt>

Approximate textual description of the cloud constraints. One of:
"any", or a combination of "cirrus", "thick" or "photometric".

    my $text = $proj->cloudtxt;

=cut

my @cloudlut;
sub cloudtxt {
    my $self = shift;
    my $cloud = $self->cloudrange;
    return 'any' unless defined $cloud;

    # initialise the cloud lookup array
    if (! @cloudlut) {
        $cloudlut[0] = 'photometric';
        $cloudlut[$_] = 'cirrus' for (1 .. OMP::SiteQuality::OMP__CLOUD_CIRRUS_MAX);
        $cloudlut[$_] = 'thick' for ((OMP::SiteQuality::OMP__CLOUD_CIRRUS_MAX + 1) .. 100);
    }

    my $min = max(0, int($cloud->min || 0));
    my $max = min(100, int($cloud->max || 100));

    my %text;  # somewhere to count how many times we have seen a key
    my @texts; # somewhere to retain the ordering
    for my $i ($min .. $max) {
        $text{$cloudlut[$i]} ++;
        push(@texts, $cloudlut[$i]) if $text{$cloudlut[$i]} == 1;
    }

    if (@texts == 0) {
        return "????";
    }
    elsif (@texts == 3) {
        return "any";
    }
    else {
        # Start with worse conditions
        return join(" or ", reverse @texts);
    }
}

=item B<summary>

Returns a summary of the project. In list context returns
keys and values of a hash:

    %summary = $proj->summary;

In scalar context returns an XML string describing the
project.

    $xml = $proj->summary;

where the keys match the element names and the project ID
is an ID attribute of the root element:

    <OMPProjectSummary projectid="M01BU53">
        <pi>...</pi>
        <tagpriority>23</tagpriority>
        ...
    </OMPProjectSummary>

=cut

sub summary {
    my $self = shift;

    # retrieve the information from the object
    my %summary;
    for my $key (qw/
            allocated coi coiemail country pending
            pi piemail projectid remaining semester tagpriority
            support supportemail
            /) {
        $summary{$key} = $self->$key;
    }

    if (wantarray) {
        return %summary;
    }
    else {
        # XML
        my $projectid = $summary{projectid};
        my $xml = "<OMPProjectSummary";
        $xml .= " id=\"$projectid\"" if defined $projectid;
        $xml .= ">\n";

        for my $key (sort keys %summary) {
            next if $key eq 'projectid';
            my $value = $summary{$key};
            if (defined $value and length($value) > 0) {
                $xml .= "<$key>$value</$key>";
            }
            else {
                $xml .= "<$key/>";
            }
            $xml .= "\n";
        }
        $xml .= "</OMPProjectSummary>\n";

        return $xml;
    }

}

=item B<science_case_url>

Return a URL pointing to the science case. This could be a simple
URL pointing to a text file or a URL pointing to a CGI script.

Currently the URL is determined using a heuristic rather than be
supplied via the constructor or stored in a database directly.

Since the project class does not yet know the associated telescope
we have to guess the telescope from the project ID.

Returns C<undef> if the location can not be determined from the project ID.

    $url = $proj->science_case_url;

=cut

sub science_case_url {
    my $self = shift;
    my $projid = $self->projectid;

    # Guess telescope
    if ($projid =~ /^m/i) {
        # JCMT
        return undef;
    }
    elsif ($projid =~ /^u/i) {
        # UKIRT
        # Service programs are in a different location
        if ($projid =~ /serv\/(\d+)$/aai) {
            # Get the number
            my $num = $1;
            return "http://www.jach.hawaii.edu/JAClocal/UKIRT/ukirtserv/forms/$num.txt";
        }

        return undef;
    }
    else {
        return undef;
    }
}

=item B<project_number>

Return a string containing only the number portion of the project ID.  Useful for
sorting projects numerically. May return undef.

=cut

sub project_number {
    my $self = shift;

    my $string = $self->projectid;

    my $number;

    if ($string =~ m!^u/\d{2}[ab]/[jhd]?(\d+).*$!aai         # UKIRT
            or $string =~ m!^u/[a-z]+/(\d+)$!aai             # UKIRT serv
            or $string =~ /^[ms]\d{2}[ab][a-z]+(\d+).*$/aai  # JCMT
            or $string =~ /^nls(\d+)$/aai                    # JCMT Dutch service
            or $string =~ /^[LS]X_(\d{2}).*$/aai             # SHADES proposal
            or $string =~ /^[a-z]{2,}(\d{2})$/aai            # Staff projects (TJ02)
            ) {
        $number = $1;
    }

    return $number;

}

=item B<semester_ori>

Return a string containing the original semester for a project.  The original
semester is obtained from the project ID. If this method is unable to obtain
the semester this way, it will return the current semester associated with the
project.

=cut

sub semester_ori {
    my $self = shift;
    my $string = $self->projectid;

    my $sem;

    if ($string =~ m!^u/(\d{2}[ab])/[jhd]?\d+.*$!aai  # UKIRT
            or $string =~ /^[ms](\d{2}[ab])[a-z]+\d+.*$/aai  # JCMT
            ) {
        $sem = $1;
    }

    if ($sem) {
        return $sem;
    }
    else {
        return $self->semester;
    }
}

=item B<fixAlloc>

Force a specific allocation on the project (not an increment), and
correct the remaining time on the project.  Takes number of hours
as an argument.

    $proj->fixAlloc(10);

=cut

sub fixAlloc {
    my $self = shift;
    my $new = shift;

    $new *= 3600;

    # Get the old allocation and time remaining
    my $old = $self->allocated;
    my $rem = $self->remaining;
    my $inc = $new - $old;

    # Fix up the time remaining
    $self->remaining($rem + $inc);
    $self->allocated($new);
}

=item B<incPending>

Increment the value of the C<pending> field by the specified amount.
Units are in seconds.

    $proj->incPending(10);

Returns without action if the supplied value is less than or equal to
0.

=cut

sub incPending {
    my $self = shift;
    my $inc = shift;
    return unless defined $inc and $inc > 0;

    my $current = $self->pending;
    $self->pending($current + $inc);
}

=item B<consolidateTimeRemaining>

Transfer the value stored in C<pending> to the time C<remaining> field
and reset the value of C<pending>

    $proj->consolidateTimeRemaining;

If the time pending is greater than the time remaining the remaining
time is set to zero.

=cut

sub consolidateTimeRemaining {
    my $self = shift;

    # Get the current value for pending
    my $pending = $self->pending;

    # Reset pending
    $self->pending(0);

    # Get the current value remaining.
    my $remaining = $self->remaining;
    my $new = $remaining - $pending;
    $new = 0 if $new < 0;

    # store it
    $self->remaining($new);
}

=item B<noneRemaining>

Force the project to have zero time remaining to be observed.
Also sets pending time to zero.

Used to disable a project. [if this is a common occurrence we
may wish to have an additional flag that disables a project
rather than setting the time to zero. This is important if we
wish to re-enable a project]

=cut

sub noneRemaining {
    my $self = shift;
    $self->remaining(0);
    $self->pending(0);
}

=item B<isScience>

Return true if the project's primary queue is not E&C.

=cut

sub isScience {
    my $self = shift;
    return ($self->primaryqueue eq 'EC' ? 0 : 1);
}

1;

__END__

=back

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001-2005 Particle Physics and Astronomy Research
Council.  All Rights Reserved.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful,but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc., 59 Temple
Place,Suite 330, Boston, MA  02111-1307, USA

=cut
