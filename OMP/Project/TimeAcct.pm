package OMP::Project::TimeAcct;

=head1 NAME

OMP::Project::TimeAcct - Time spent observing a project for a given UT date

=head1 SYNOPSIS

  use OMP::Project::TimeAcct;

  $t = new OMP::Project::TimeAcct(
                         projectid => 'm02bu104',
                         date    => OMP::General->parse_date('2002-08-15'),
			 time_spent => new Time::Seconds(3600),
                         confirmed => 1);

=head1 DESCRIPTION

This class can be used to specify the amount of time spent on a project
for a given UT date. These objects correspond to rows in a database
table and this allows us to tweak the time accounting for a particular
night or project without affecting other nights (as well as allowing
people to view their project history in more detail).

The project ID does not necessarily have to match a valid OMP project
ID. Special exceptions to this rule for time allocation purposes are:

   FAULT    - time lost in a night to faults
   WEATHER  - time lost to bad weather [ie no observing possible]
   OTHER    - time spent doing other things. If observations are carried
              out outside of the OMP then this could simply be time
              spent doing other observations or it could be genuine
              overhead.

Time spent doing EXTENDED observing should be associated with
a real science project if possible even if it is not charged to the
project (extended observing is "free"). [it may be easier to ignore
this subtlety for now and just treat EXTENDED as a separate "project"]

=cut

use 5.006;
use strict;
use warnings;
use Carp;
use OMP::General;



=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

Object constructor.  Takes a hash as argument, the keys of which can
be used to prepopulate the object. The key names must match the names
of the accessor methods (ignoring case). If they do not match they are
ignored (for now).

  $t = new OMP::Project::TimeAcct( %args );

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
		}, $class;

  # Deal with arguments
  if (@_) {
    my %args = @_;

    # rather than populate hash directly use the accessor methods
    # allow for upper cased variants of keys
    for my $key (keys %args) {
      my $method = lc($key);
      if ($t->can($method)) {
        $t->$method( $args{$key} );
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
      if (defined $date && ! UNIVERSAL::isa( $date, "Time::Piece" ));
    $self->{Date} = $date;
  }
  return $self->{Date};
}

=item B<time_spent>

Time spent observing this project on the specified UT date.
The time is represented by a a Time::Seconds object.

 $time = $t->time_spent;
 $t->time_spent( new Time::Seconds(7200));

=cut

sub time_spent {
  my $self = shift;
  if (@_) {
    # if we have a Time::Seconds object just store it. Else create one.
    my $time = shift;
    $time = new Time::Seconds( $time )
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
    $self->{ProjectID} = shift;
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

=back

=head2 General Methods

=over 4

=item B<incTime>

Increment the time spent by the specified amount.

  $t->incTime( 55.0 );

Units are in seconds. The time can be specified as either
a straight number or as a Time::Seconds object.

=cut

sub incTime {
  my $self = shift;
  my $inc = shift;
  my $cur = $self->time_spent;
  $cur = 0 unless defined $cur;
  $cur += $inc;
  $self->time_spent( $cur );
  return;
}



=back

=head1 COPYRIGHT

Copyright (C) 2002 Particle Physics and Astronomy Research
Council.  All Rights Reserved.

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=cut

1;
