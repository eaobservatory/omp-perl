package OMP::Project::TimeAcct;

=head1 NAME

OMP::Project::TimeAcct - Time spent observing a project for a given UT date

=head1 SYNOPSIS

    use OMP::Project::TimeAcct;

    $t = OMP::Project::TimeAcct->new(
        projectid => 'm02bu104',
        date => OMP::DateTools->parse_date('2002-08-15'),
        timespent => Time::Seconds->new(3600),
        confirmed => 1,
        shifttype => 'NIGHT',
        remote => 0);

=head1 DESCRIPTION

This class can be used to specify the amount of time spent on a project
for a given UT date. These objects correspond to rows in a database
table and this allows us to tweak the time accounting for a particular
night or project without affecting other nights (as well as allowing
people to view their project history in more detail).

The project ID does not necessarily have to match a valid OMP project
ID. Special exceptions to this rule for time allocation purposes are:

=over 4

=item FAULT

Time lost in a night to faults.

=item WEATHER

Time lost to bad weather [ie no observing possible].

=item OTHER

Time spent doing other things. If observations are carried
out outside of the OMP then this could simply be time
spent doing other observations or it could be genuine
overhead.

=back

Time spent doing EXTENDED observing should be associated with
a real science project if possible even if it is not charged to the
project (extended observing is "free"). [it may be easier to ignore
this subtlety for now and just treat EXTENDED as a separate "project"]

=cut

use 5.006;
use strict;
use warnings;
use Carp;
use OMP::DateTools;
use OMP::General;

use overload "==" => "isEqual";

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

Object constructor.  Takes a hash as argument, the keys of which can
be used to prepopulate the object. The key names must match the names
of the accessor methods (ignoring case). If they do not match they are
ignored (for now).

    $t = OMP::Project::TimeAcct->new(%args);

Arguments are optional.

=cut

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;

    my $t = bless {
        Date => undef,
        TimeSpent => undef,
        ProjectID => undef,
        Confirmed => 0,
        ShiftType => undef,
        Remote => undef,
        Comment => undef,
        Observations => undef,
        Telescope => undef,
    }, $class;

    # Deal with arguments
    if (@_) {
        my %args = @_;

        # rather than populate hash directly use the accessor methods
        # allow for upper cased variants of keys
        for my $key (keys %args) {
            my $method = lc($key);
            if ($t->can($method)) {
                $t->$method($args{$key});
            }
        }

    }

    return $t;
}

=back

=head1 Accessor Methods

=over 4

=item B<date>

The UT date on which this time was spent on the given project.
[what we do on telescopes that observe through a UT date boundary
is an open question!]

Must be supplied as a Time::Piece object, by convention with the
hours and minutes at zero. [for other locations we could simply specify
a date representative of the start of observing and then use 24 hour
offsets for queries]

=cut

sub date {
    my $self = shift;
    if (@_) {
        my $date = shift;
        croak "Date must be supplied as Time::Piece object"
            if defined $date && !UNIVERSAL::isa($date, "Time::Piece");
        $self->{Date} = $date;
    }
    return $self->{Date};
}

=item B<timespent>

Time spent observing this project on the specified UT date.
The time is represented by a a Time::Seconds object.

    $time = $t->timespent;
    $t->timespent(Time::Seconds->new(7200));

=cut

sub timespent {
    my $self = shift;
    if (@_) {
        # if we have a Time::Seconds object just store it. Else create one.
        my $time = shift;
        $time = Time::Seconds->new($time)
            unless UNIVERSAL::isa($time, "Time::Seconds");
        $self->{TimeSpent} = $time;
    }
    return $self->{TimeSpent};
}

=item B<projectid>

The project ID associated with this time.

Must be either a valid OMP project ID or one of WEATHER, FAULT,
OTHER or EXTENDED.

=cut

sub projectid {
    my $self = shift;
    if (@_) {
        # no verification yet
        $self->{ProjectID} = uc(shift);
    }
    return $self->{ProjectID};
}

=item B<confirmed>

Boolean indicating whether the time spent has been officially
confirmed or whether it is still treated as provisional.

    $confirmed = $t->confirmed();
    $t->confirmed(1);

Defaults to provisional.

=cut

sub confirmed {
    my $self = shift;
    if (@_) {
        # no verification yet
        $self->{Confirmed} = shift;
    }
    return $self->{Confirmed};
}

=item B<shifttype>

String indicating the type of shift (e.g. NIGHT, DAY, EO).

    $shifttype = $t->shifttype();
    $t->shifttype("DAY");

Defaults to undef.

=cut

sub shifttype {
    my $self = shift;
    if (@_) {
        my $shifttype = shift;
        if (! defined $shifttype || $shifttype eq '') {
            $shifttype = 'UNKNOWN';
        }
        $self->{ShiftType} = $shifttype;
    }
    return $self->{ShiftType};
}

=item B<comment>

Optional string commenting on the time accounting value.

Expected to be used when the saved value differs from the autogenerated vaue.

    $comment = $t->comment();
    $t->comment("Half time charged due to bad weather (OMPID)");

Defaults to undef.

=cut

sub comment {
    my $self = shift;
    if (@_) {
        my $comment = shift;
        $self->{Comment} = $comment;
    }
    return $self->{Comment};
}


=item B<remote>

Integer indicating if shift was  remote (1) or non-remote (0)

    $remote = $t->remote();
    $t->remote(0);

Defaults to undef.

=cut

sub remote {
    my $self = shift;
    if (@_) {
        # no verification yet
        $self->{Remote} = shift;
    }
    return $self->{Remote};
}

=item B<observations>

Optional list of observations which contributed to the calculation of
this time spent.

This method does not (yet) check the type of the given value.  However
if C<trace_observations> is specified, C<OMP::Info::ObsGroup> currently stores
a list of hashes containing C<obs> (C<OMP::Info::Obs> object),
C<timespent> (seconds) and C<comment> (text explanation of time charged).

=cut

sub observations {
    my $self = shift;
    if (@_) {
        $self->{'Observations'} = shift;
    }
    return $self->{'Observations'};
}

=item B<telescope>

Name of telescope.

    $tel = $t->telescope();

May only be present if the time accounting record relates to a standard
observing project such that the database was able to determine the telescope
by matching the project ID to an entry in the C<ompproj> table.

=cut

sub telescope {
    my $self = shift;
    if (@_) {
        my $telescope = shift;
        $telescope = uc $telescope if defined $telescope;
        $self->{'Telescope'} = $telescope;
    }
    return $self->{'Telescope'};
}

=back

=head2 General Methods

=over 4

=item B<incTime>

Increment the time spent by the specified amount.

    $t->incTime(55.0);

Units are in seconds. The time can be specified as either
a straight number, a Time::Seconds object I<or> a
C<OMP::Project::TimeAcct> object.

=cut

sub incTime {
    my $self = shift;
    my $inc = shift;

    # try to work out what we have as input
    my $time;
    if (not ref($inc)) {
        $time = $inc;
    }
    elsif (UNIVERSAL::isa($inc, "Time::Seconds")) {
        $time = $inc->seconds;
    }
    elsif (UNIVERSAL::isa($inc, "OMP::Project::TimeAcct")) {
        $time = $inc->timespent;
    }
    else {
        # hope that it numifies
        $time = $inc + 0;
    }

    my $cur = $self->timespent;
    $cur = 0 unless defined $cur;
    #print "************************CUR IS $cur\n";
    $cur += $time;
    #print "INCTIME: Inc is $inc and CUR is now $cur and time is $time\n";
    $self->timespent($cur);
    return;
}

=item B<isEqual>

Compare two C<OMP::Project::TimeAcct> objects for equality.

    $t->isEqual($acct1, $acct2);

This method is invoked by a comparison overload.  Returns
true if the objects are determined to be equal.

=cut

sub isEqual {
    my $acct_a = shift;
    my $acct_b = shift;

    if ($acct_a->projectid ne $acct_b->projectid) {
        return 0;
    }
    elsif ($acct_a->date->epoch != $acct_b->date->epoch) {
        return 0;
    }
    elsif ($acct_a->timespent->seconds != $acct_b->timespent->seconds) {
        return 0;
    }
    else {
        return 1;
    }
}

1;

__END__

=back

=head1 COPYRIGHT

Copyright (C) 2002 Particle Physics and Astronomy Research
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

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=cut
