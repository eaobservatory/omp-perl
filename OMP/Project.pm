package OMP::Project;

=head1 NAME

OMP::Project - Information relating to a single project

=head1 SYNOPSIS

  $proj = new OMP::Project( projectid => $projectid );

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
use OMP::General;
use OMP::User;

our $VERSION = (qw$Revision$)[1];

# Delimiter for co-i strings
our $DELIM = ":";

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

  $proj = new OMP::Project( %args );

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
		    Encrypted => undef,
		    Password => undef,
		    ProjectID => undef,
		    TauRange => undef,
		    SeeingRange => undef,
		    Cloud => undef,
		    CoI => [],

		    # Country and tag priority now
		    # can have more than one value
		    PrimaryQueue => undef,
		    Queue => {},

		    PI => undef,
		    Remaining => undef, # so that it defaults to allocated
		    Pending => Time::Seconds->new(0),
		    Support => [],
		    State => 1,
		    Contactable => {},
		   }, $class;

  # Deal with arguments
  if (@_) {
    my %args = @_;

    # rather than populate hash directly use the accessor methods
    # allow for upper cased variants of keys
    for my $key (keys %args) {
      my $method = lc($key);
      if ($proj->can($method)) {
	$proj->$method( $args{$key} );
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
    $state = ($state ? 1 : 0 );
    $self->{State} = $state
  };
  return $self->{State};
}

=item B<allocated>

The time allocated for the project (in seconds).

  $time = $proj->allocated;
  $proj->allocated( $time );

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
    # if we have a Time::Seoncds object just store it. Else create one.
    my $time = shift;
    $time = new Time::Seconds( $time )
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

This interface will change when non-contiguous tau ranges are supported.
(The method may even disappear).

=cut

sub taurange {
  my $self = shift;
  if (@_) {
    my $range = shift;
    croak "Tau range must be specified as an OMP::Range object"
      unless UNIVERSAL::isa($range, "OMP::Range");
    $self->{TauRange} = $range;
  }
  return $self->{TauRange};
}

=item B<seerange>

Range of seeing conditions (in arcseconds)  in which the observations can be performed. No observations can be performed when the seeing
is not within this range.

  $range = $proj->seerange();

Returns an C<OMP::Range> object (or undef).

=cut

sub seerange {
  my $self = shift;
  if (@_) {
    my $range = shift;
    croak "Tau range must be specified as an OMP::Range object"
      unless UNIVERSAL::isa($range, "OMP::Range");
    $self->{SeeingRange} = $range;
  }
  return $self->{SeeingRange};
}

=item B<cloud>

Any cloud condition constraints. C<undef> indicates no constraints,
1 indicates "photometric" and 2 indicates "cirrus".

  $cloud = $proj->cloud( 1 );

=cut

sub cloud {
  my $self = shift;
  if (@_) {
    $self->{Cloud} = shift;
  }
  return $self->{Cloud};
}

=item B<telescope>

The telescope on which the project has been allocated time.

  $time = $proj->telescope;
  $proj->telescope( $time );

This is a string and not a C<Astro::Telescope> object.

Telescope is always upper-cased.

=cut

sub telescope {
  my $self = shift;
  if (@_) { $self->{Telescope} = uc(shift); }
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

  $proj->coi( @names );
  $proj->coi( \@names );

Provide a list of colon-separated user IDs:

  $proj->coi( "name1:name2" );

Co-Is are by default non-contactable so no call is made to
the C<contactable> method if the CoI information is updated.

=cut

sub coi {
  my $self = shift;
  if (@_) { 
    my @names;
    if (ref($_[0]) eq 'ARRAY') {
      @names = @{ $_[0] };
    } elsif (defined $_[0]) {
      # If the first name isnt valid assume none are
      @names = @_;
    }

    # Now go through the array retrieving the OMP::User
    # objects and strings
    my @users;
    for my $name (@names) {
      if (UNIVERSAL::isa($name, "OMP::User")) {
	push(@users, $name);
      } else {
	# Split on delimiter
	my @split = split /$DELIM/, $name;

	# Convert them to OMP::User objects
	push(@users, map { new OMP::User( userid => $_ ) } @split);
      }
    }

    # And store the result
    $self->{CoI} = \@users; 
  }

  # Return either the array of name objects or a delimited string
  my @output = @{ $self->{CoI} };
  if (wantarray) {
    return @output;
  } else {
    # This returns empty string if we dont have anything
    return join($DELIM, map { $_->userid } @output);
  }

}

=item B<coiemail>

The email addresses of co-investigators associated with the project.

  @email = $proj->coiemail;
  $emails   = $proj->coiemail;

If this method is called in a scalar context the addresses will be
returned as a single string joined by a comma.

Consider using the C<coi> method to access the C<OMP::User> objects
directly. Email addresses can not be modified using this method.

=cut

sub coiemail {
  my $self = shift;

  # Only use defined emails
  my @email = grep { $_ } map { $_->email } $self->coi ;

  # Return either the array of emails or a delimited string
  if (wantarray) {
    return @email;
  } else {
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

  $proj->country( @countries );
  $proj->country( \@countries );

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
    my @c = ( ref($_[0]) ? @{$_[0]} : @_);

    # are we meant to apply a cached tag priority?
    # Yes, if there are no previous countries
    my $tagpri;
    my %queue = $self->queue;

    if (keys %queue) {
      # go through the existing entries, and remove
      # any from the list that already exist. We do not
      # want to clear old tag priorities
      @c = grep { !exists $queue{uc($_)}  } @c;
    } else {
      $tagpri = $self->{$TAGPRI_KEY};
    }

    # configure primary queue since we know the order
    if (! keys %queue && ! defined $self->primaryqueue) {
      $self->primaryqueue( $c[0] );
    }

    # Store new keys with default or no tag priority
    $self->queue( map { uc($_) => $tagpri } @c );

  }
  if (wantarray) {
    return sort keys %{ $self->queue };
  } else {
    # Return the primary country
    my $country = $self->primaryqueue;
    return (defined $country ? $country : 
	    join( "/", sort keys %{ $self->queue } ) );
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
    $self->country( $c );
  }
  return $self->{PrimaryQueue};
}

=item B<password>

Plain text version of the password (if available). If this object has
been instantiated from a database table it is likely that only the
encrypted password is available (see C<encrypted> method). If this
password is updated the encrypted version is automatically updated.

  $plain = $proj->password;
  $proj->password( $plain );

If the plain password is C<undef>, the plain password is cleared but
the encrypted password will not be cleared.

=cut

sub password {
  my $self = shift;
  if (@_) {
    my $plain = shift;

    # If the password is defined we encrypt it, else
    # just undefine the password without modifying encrypted
    # version. This is also necessary to allow the encrypted()
    # method to clear the plain text password
    if (defined $plain) {
      # Time to encrypt
      # Generate the salt from a random set
      # See the crypt entry in perlfunc
      my $salt = join '', 
	('.', '/', 0..9, 'A'..'Z', 'a'..'z')[rand 64, rand 64];

      # Encrypt and store it
      # Note that we store the plain password after this
      # step to prevent the encrypted() method clearing it
      # and ruining everything [the easy approach is simply 
      # to not use the accessor method]
      $self->encrypted( crypt( $plain, $salt) );

    }

    # Now store the plain password
    $self->{Password} = $plain;

  }

  return $self->{Password};
}


=item B<encrypted>

Encrypted password associated with the project.

  $password = $proj->encrypted;

If available, the plain text password can be obtained using
the C<password> method. The encrypted password is updated
if the plain text password is updated. Also, if the encrypted
password is updated the plain text version is cleared.

=cut

sub encrypted {
  my $self = shift;
  if (@_) {
    $self->{Encrypted} = shift;

    # Clear the plain text password
    # Note that undef is treated as a special case so that
    # we dont get into infinite recursion when password() calls
    # this method.
    $self->password(undef);
  }
  return $self->{Encrypted};
}


=item B<pending>

The amount of time (in seconds) that is to be removed from the
remaining project allocation pending approval by the queue managers.

  $time = $proj->pending();
  $proj->pending( $time );

Returns a C<Time::Seconds> object.

=cut

sub pending {
  my $self = shift;
  if (@_) {
    # if we have a Time::Seoncds object just store it. Else create one.
    my $time = shift;
    $time = new Time::Seconds( $time )
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
    throw OMP::Error::BadArgs("PI must be of type OMP::User")
      unless UNIVERSAL::isa($pi, "OMP::User");
    $self->{PI} = $pi;

    # And force them to be contactable
    $self->contactable( $pi->userid => 1 );

  }
  return $self->{PI};
}

=item B<piemail>

Email address of the principal investigator.

  $email = $proj->piemail;

=cut

sub piemail {
  my $self = shift;
  return ( defined $self->pi() ? $self->pi->email : '' );
}

=item B<projectid>

Project ID.

 $id = $proj->projectid;

The project ID is always upcased.

=cut

sub projectid {
  my $self = shift;
  if (@_) { $self->{ProjectID} = uc(shift); }
  return $self->{ProjectID};
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

  $proj->support( @names );
  $proj->support( \@names );

Provide a list of colon-separated user IDs:

  $proj->support( "name1:name2" );

By default when a support contact is updated it is made contactable. If this
is not the case the C<contactable> method must be called explicitly.

=cut

sub support {
  my $self = shift;
  if (@_) { 
    my @names;
    if (ref($_[0]) eq 'ARRAY') {
      @names = @{ $_[0] };
    } elsif (defined $_[0]) {
      # If the first name isnt valid assume none are
      @names = @_;
    }

    # Now go through the array retrieving the OMP::User
    # objects and strings
    my @users;
    for my $name (@names) {
      if (UNIVERSAL::isa($name, "OMP::User")) {
	push(@users, $name);
      } else {
	# Split on delimiter
	my @split = split /$DELIM/, $name;

	# Convert them to OMP::User objects
	push(@users, map { new OMP::User( userid => $_ ) } @split);
      }
    }

    # make them contactable
    for (@users) {
      $self->contactable( $_->userid => 1 );
    }

    # And store the result
    $self->{Support} = \@users; 
  }

  # Return either the array of name objects or a delimited string
  if (wantarray) {
    return @{ $self->{Support} };
  } else {
    # This returns empty string if we dont have anything
    return join($DELIM, @{ $self->{Support} } );
  }

}

=item B<supportemail>

The email addresses of co-investigators associated with the project.

  @email = $proj->supportemail;
  $emails   = $proj->supportemail;

If this method is called in a scalar context the addresses will be
returned as a single string joined by a comma.

Consider using the C<support> method to access the C<OMP::User> objects
directly. Email addresses can not be modified using this method.

=cut

sub supportemail {
  my $self = shift;

  my @email = map { $_->email } $self->support;
  # Return either the array of emails or a delimited string
  if (wantarray) {
    return @email;
  } else {
    # This returns empty string if we dont have anything
    return join($DELIM, @email);
  }

}

=item B<remaining>

The amount of time remaining on the project (in seconds).

  $time = $proj->remaining;
  $proj->remaining( $time );

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
    $time = new Time::Seconds( $time )
      unless UNIVERSAL::isa($time, "Time::Seconds");
    $self->{Remaining} = $time;
  } else {
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
  if (@_) { $self->{Semester} = uc(shift); }
  return $self->{Semester};
}

=item B<tagpriority>

The priority of this project relative to all the other projects
in the queue. This priority is determined by the Time Allocation
Group (TAG). Since a project can have different priorities in
different queues, the queue name (aka country) must be supplied.

  $pri = $proj->tagpriority( $country );

If multiple countries are specified (using a reference to an array),
corresponding priorities are returned (undef if project is not
associated with that country).

  @pris = $proj->tagpriority( \@countries );

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

  $proj->tagpriority( CA => 1, UK => 5 );
  $proj->tagpriority( \%update );

Use the queue() method to set priorities and country information.

If this method is called before a country is associated with the
object then, for backwards compatibility reasons, the TAG priority
is cached and applied if a country is set explicitly with the
C<country> method (and only the first time that is used).

=cut

sub tagpriority {
  my $self = shift;
  my $delim = ","; # for scalar context
  if (@_) { 
    if (scalar @_ == 1 && ref($_[0]) ne 'HASH') {
      # if we have a number, it is being set
      if ($_[0] =~ /\d/) {
	# set every priority
	my @c = $self->country;
	if (@c) {
	  for my $c (@c) {
	    $self->queue( $c => $_[0]);
	  }
	} else {
	  # Store it for later
	  $self->{$TAGPRI_KEY} = $_[0];
	}
      } else {
	# A country has been requested or more than one
	my @c = ( ref($_[0]) ? @{$_[0]} : @_);
	my %queue = $self->queue;
	my @pris = map { $queue{uc($_)} } @c;
	return (wantarray ? @pris : join($delim,@pris));
      }
    } else {
      # More than one argument, assume hash
      my %queue = $self->queue;
      my %args = (ref($_[0]) eq 'HASH' ? %{$_[0]} : @_);
      for my $c (keys %args) {
	my $uc = uc($c);
	# check that the country is supported
	croak "Country $c not recognized"
	  unless exists $queue{$uc};
	$self->queue( $c => $args{$c});
      }
    }
  }

  # Return everything as a list or a single string
  my @countries = sort values %{ $self->queue };
  if (wantarray) {
    return @countries;
  } else {
    my %queue = $self->queue;
    my $primary = $self->primaryqueue;
    if (!defined $primary || !exists $queue{$primary}) {
      return join($delim,@countries);
    } else {
      return $queue{$primary};
    }
  }
}

=item B<title>

The title of the project.

  $title = $proj->title;

=cut

sub title {
  my $self = shift;
  if (@_) { $self->{Title} = shift; }
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
  my %users = map {$_->userid, $_} grep {$self->contactable($_->userid) and $_->email} ( $self->investigators, $self->support );

  return map {$users{$_}} keys %users;
}

=item B<contactable>

A hash (indexed by OMP user ID) indicating whether a particular person
associated with this project should be sent email notifications concerning
a change in project state. If a particular user is not present in this
hash the assumption should be that they do not want to be contacted.

A case can be made for always contacting the PI and support scientists.

Values can be modified by specifying a set of key value pairs:

  $proj->contactable( TIMJ => 1, JRANDOM => 0);

and the current state for a user can be retrieved by specifying a single
user id:

  $iscontactable = $proj->contactable( 'TIMJ' );

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
    } else {
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
    return %{ $self->{Contactable} };
  } else {
    return $self->{Contactable};
  }
}

=item B<queue>

Queue entries and corresponding TAG priorities (see also C<country>
and C<tagpriority> methods for alternative views). Returns a hash
with keys of "country" and values of TAG priority.

  %queue = $proj->queue;

Returns a hash reference in scalar context:

  $ref = $proj->queue();

Can be used to set countries and priorities:

  $proj->queue( CA => 22, UK => 1 );

or

  $proj->queue( \%queue );

Other country information is retained. The queue can be cleared with
the C<clearqueue> command.

The primary queue can not be configured automatically using this
method since the hash does not have a guaranteed order.

=cut

sub queue {
  my $self = shift;
  if (@_) {
    # either a hash ref as first arg or a list
    my %args = ( ref($_[0]) ? %{$_[0]} : @_);
    for my $c (keys %args) {
      $self->{Queue}->{uc($c)} = $args{$c};
    }
  }
  if (wantarray) {
    return %{ $self->{Queue} };
  } else {
    return $self->{Queue};
  }
}

=item B<clearqueue>

Clear all queue information (country and TAG priority).

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
    return 1 if $p < 0;
  }
  return 0;
}

=back

=head2 General Methods

=over 4

=item B<verify_password>

Verify that the plain text password matches the encrypted
password.

If an argument is supplied it is assumed to be a plain text password
that we are comparing with the encrypted version in the object.

  $verified = 1 if $proj->verify_password();
  $verified = 1 if $proj->verify_password( $plain );

This is useful if we are trying to do password verification with
an externally supplied password (note that if we simply stored
the plain text password in the object using C<password()> the
encrypted password would automatically be regenerated.

Note that because we currently use unix C<crypt> we are limited to 8
characters. We could overcome this by shifting to MD5.

Returns false if either of the passwords are missing.

The password is B<always> compared with the encrypted administrator
password before comparing it to the encrypted project password.  The
encrypted project password is only used if the staff password
fails to verify.

Additionally, each country has a special queue manager password
that is also checked.

=cut

sub verify_password {
  my $self = shift;
  my $plain;
  if (@_) {
    $plain = shift;
  } else {
    $plain = $self->password;
  }

  # First verify against staff and queue manager passwords.
  # Need to turn off exceptions
  # Need to check each country
  for my $c ($self->country) {
    return 1
      if OMP::General->verify_queman_password( $plain, $c,1);
  }

  # Need to verify against this password
  my $encrypted = $self->encrypted;

  # Return false immediately if either are undefined
  return 0 unless defined $plain and defined $encrypted;

  # The encrypted password includes the salt as the first
  # two letters. Therefore we encrypt the plain text password
  # using the encrypted password as salt
  return ( crypt($plain, $encrypted) eq $encrypted );

}

=item B<conditionstxt>

A short textual summary of the site quality constraints associated
with this project.

=cut

sub conditionstxt {
  my $self = shift;

  my $cloud = $self->cloudtxt;
  $cloud = '' if $cloud eq 'any';
  $cloud = substr($cloud,0,4) if $cloud;

  # Seeing. Need to fix lower end for prettification
  my $seeing = $self->seerange();
  my $seetxt = '';
  if ($seeing) {
    my $min = $seeing->min();
    $seeing->min(undef) if defined $min && $min == 0;
    # only put text if we have a range
    unless (!$seeing->min && !$seeing->max) {
      $seetxt = "s:$seeing";
    }
  }

  my $taurange = $self->taurange();
  my $tautxt = '';
  if ($taurange) {
    my $min = $taurange->min;
    $taurange->min(undef) if defined $min && $min == 0;
    unless (!$taurange->min && !$taurange->max) {
      # only create if we have a range defined
      $tautxt = "t:$taurange";
    }
  }

  my $txt = join(",", grep { $_} ($tautxt, $seetxt, $cloud) );

  return ( $txt ? $txt : 'any' );
}

=item B<cloudtxt>

The textual description of the cloud constraints. One of:

  any
  cirrus or photometric
  photometric

 my $text = $proj->cloudtxt;

=cut

sub cloudtxt {
  my $self = shift;
  my $cloud = $self->cloud;
  return "any" unless defined $cloud;

  my %lut = (0 => "photometric",
	     1 => "cirrus or photometric",
	    );

  if (exists $lut{$cloud}) {
    return $lut{$cloud};
  } else {
    return "????";
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
  for my $key (qw/allocated coi coiemail country encrypted password pending
	       pi piemail projectid remaining semester tagpriority
	       support supportemail /) {
    $summary{$key} = $self->$key;
  }

  if (wantarray) {
    return %summary;
  } else {
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
      } else {
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
  } elsif ($projid =~ /^u/i) {
    # UKIRT
    # Service programs are in a different location
    if ($projid =~ /serv\/(\d+)$/i) {
      # Get the number
      my $num = $1;
      return "http://www.jach.hawaii.edu/JAClocal/UKIRT/ukirtserv/forms/$num.txt";
    }

    return undef;
  } else {
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

  if ($string =~ m!^u/\d{2}[ab]/[jhd]?(\d+).*$!i     # UKIRT
      or $string =~ m!^u/[a-z]+/(\d+)$!i             # UKIRT serv
      or $string =~ /^[ms]\d{2}[ab][a-z]+(\d+).*$/i  # JCMT
      or $string =~ /^nls(\d+)$/i                    # JCMT Dutch service
      or $string =~ /^[LS]X_(\d{2}).*$/i             # SHADES proposal
      or $string =~ /^[a-z]{2,}(\d{2})$/i            # Staff projects (TJ02)
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

  if ($string =~ m!^u/(\d{2}[ab])/[jhd]?\d+.*$!i       # UKIRT
	or $string =~ /^[ms](\d{2}[ab])[a-z]+\d+.*$/i  # JCMT
     ) {
    $sem = $1;
  }

  if ($sem) {
    return $sem
  } else {
    return $self->semester;
  }
}

=item B<incPending>

Increment the value of the C<pending> field by the specified amount.
Units are in seconds.

  $proj->incPending( 10 );

Returns without action if the supplied value is less than or equal to
0.

=cut

sub incPending {
  my $self = shift;
  my $inc = shift;
  return unless defined $inc and $inc > 0;

  my $current = $self->pending;
  $self->pending( $current + $inc );
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
  $self->pending( 0 );

  # Get the current value remaining.
  my $remaining = $self->remaining;
  my $new = $remaining - $pending;
  $new = 0 if $new < 0;

  # store it
  $self->remaining( $new );

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
  $self->remaining( 0 );
  $self->pending( 0 );
}

=item B<isScience>

Return true if the project's primary queue is not E&C.

=cut

sub isScience {
  my $self = shift;
  return ($self->primaryqueue eq 'EC' ? 0 : 1);
}

=back

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research
Council.  All Rights Reserved.

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=cut

1;
