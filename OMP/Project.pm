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
use Carp;
use OMP::General;
use OMP::User;

our $VERSION = (qw$Revision$)[1];

# Delimiter for co-i strings
our $DELIM = ":";


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
		    Country => undef,
		    Semester => undef,
		    Allocated => 0,
		    Title => '',
		    Telescope => undef,
		    Encrypted => undef,
		    Password => undef,
		    ProjectID => undef,
		    TauRange => undef,
		    CoI => [],
		    TagPriority => 999,
		    PI => undef,
		    Remaining => undef, # so that it defaults to allocated
		    Pending => 0,
		    Support => [],
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

=cut

sub country {
  my $self = shift;
  if (@_) { $self->{Country} = shift; }
  return $self->{Country};
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

=cut

sub pi {
  my $self = shift;
  if (@_) { 
    my $pi = shift;
    Carp::confess "PI must be of type OMP::User"
      unless UNIVERSAL::isa($pi, "OMP::User");
    $self->{PI} = $pi;
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

=item B<remainingAll>

Time remaining on the project including any time pending. This
is simply that stored in the C<remaining> field minus that stored
in the C<pending> field.

 $left = $proj->allRemaining;

Always returns a number greater than or equal to zero.

=cut

sub allRemaining {
  my $self = shift;
  my $all_left = $self->remaining - $self->pending;
  $all_left = 0 if $all_left < 0.0;
  return $all_left;
}

=item B<used>

The amount of time (in seconds) used by the project so far. This
is calculated as the difference between the allocated amount and
the time remaining on the project (the time pending is assumed to
be included in this calculation).

  $time = $proj->used;

This value can never exceed the total amount of time allocated to the
project.

=cut

sub used {
  my $self = shift;
  return ($self->allocated - $self->allRemaining);
}

=item B<semester>

The semester for which the project was allocated time.

  $semester = $proj->semester;

=cut

sub semester {
  my $self = shift;
  if (@_) { $self->{Semester} = shift; }
  return $self->{Semester};
}

=item B<tagpriority>

The priority of this project relative to all the other projects
in the queue. This priority is determined by the Time Allocation
Group (TAG).

  $pri = $proj->tagpriority;

=cut

sub tagpriority {
  my $self = shift;
  if (@_) { $self->{TagPriority} = shift; }
  return $self->{TagPriority};
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

Return the contact email addresses for all those people with registered
involvement in the project. This is simply a combination of PI and
Co-I email addresses.

  my @email = $proj->investigators;
  my $email = $proj->investigators;

Like C<coiemail> this method returns a list in list context and
a delimited string in scalar context.

B<For now this only returns the PI information. Do this until
we are sure who we should be contacting with Feedback information>

=cut

sub investigators {
  my $self = shift;

  # Get all the email addresses
  my @email = ( $self->piemail, $self->coiemail);
  @email = ($self->piemail);

  # Return either the array of emails or a delimited string
  if (wantarray) {
    return @email;
  } else {
    # This returns empty string if we dont have anything
    return join($DELIM, @email );
  }

}

=item contacts

Return the contact email addresses for all those people associated
with the project. This is the investigators and support scientists.

  my @email = $proj->contacts;
  my $email = $proj->contacts;

Like C<coiemail> this method returns a list in list context and
a delimited string in scalar context.

=cut

sub contacts {
  my $self = shift;

  # Get all the email addresses
  my @email = ( $self->investigators, $self->supportemail);

  # Return either the array of emails or a delimited string
  if (wantarray) {
    return @email;
  } else {
    # This returns empty string if we dont have anything
    return join($DELIM, @email );
  }

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

=cut

sub verify_password {
  my $self = shift;
  my $plain;
  if (@_) {
    $plain = shift;
  } else {
    $plain = $self->password;
  }

  # First verify against staff password.
  # Need to turn off exceptions
  if ( OMP::General->verify_staff_password( $plain, 1) ) {
    return 1;
  } else {

    # Need to verify against this password
    my $encrypted = $self->encrypted;

    # Return false immediately if either are undefined
    return 0 unless defined $plain and defined $encrypted;

    # The encrypted password includes the salt as the first
    # two letters. Therefore we encrypt the plain text password
    # using the encrypted password as salt
    return ( crypt($plain, $encrypted) eq $encrypted );
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

=back

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research
Council.  All Rights Reserved.

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=cut

1;
