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
		    Encrypted => undef,
		    Password => undef,
		    ProjectID => undef,
		    CoI => [],
		    PIEmail => undef,
		    TagPriority => 999,
		    CoIEmail => [],
		    PI => undef,
		    Remaining => 0,
		    Pending => 0,
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

=cut

sub allocated {
  my $self = shift;
  if (@_) { $self->{Allocated} = shift; }
  return $self->{Allocated};
}

=item B<coi>

The names of any co-investigators associated with the project.

  @names = $proj->coi;
  $names = $proj->coi;
  $proj->coi( @names );
  $proj->coi( \@names );
  $proj->coi( "name1:name2" );

If the strings contain colons it is assumed that the colons are delimeters
for multiple co-investigators. In this case, the names will be
split and stored as separate elements in the array.

If this method is called in a scalar context the names will be returned
as a single string joined by a colon.

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

    # Now split on the delimiter
    @names = map { split /$DELIM/, $_; } @names;

    # And store the result
    $self->{CoI} = \@names; 
  }

  # Return either the array of names or a delimited string
  if (wantarray) {
    return @{ $self->{CoI} };
  } else {
    # This returns empty string if we dont have anything
    return join($DELIM, @{ $self->{CoI} } );
  }

}

=item B<coiemail>

The email addresses of co-investigators associated with the project.

  @email = $proj->coiemail;
  $emails   = $proj->coiemail;
  $proj->coiemail( @email );
  $proj->coiemail( \@email );
  $proj->coiemail( "email1:email2:email3" );

If the input strings contain colons it is assumed that the colons are
delimeters for multiple email addresses. In this case, the names will
be split and stored as separate elements in the array.

If this method is called in a scalar context the addresses will be returned
as a single string joined by a colon.

=cut

sub coiemail {
  my $self = shift;
  if (@_) { 
    my @names;
    if (ref($_[0]) eq 'ARRAY') {
      @names = @{ $_[0] };
    } elsif (defined $_[0]) {
      # If first isnt valid assume none are
      @names = @_;
    }

    # Now split on the delimiter
    @names = map { split /$DELIM/, $_; } @names;

    # And store it
    $self->{CoIEmail} = \@names; 
  }

  # Return either the array of emails or a delimited string
  if (wantarray) {
    return @{ $self->{CoIEmail} };
  } else {
    # This returns empty string if we dont have anything
    return join($DELIM, @{ $self->{CoIEmail} });
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

=cut

sub pending {
  my $self = shift;
  if (@_) { $self->{Pending} = shift; }
  return $self->{Pending};
}

=item B<pi>

Name of the principal investigator.

  $pi = $proj->pi;

=cut

sub pi {
  my $self = shift;
  if (@_) { $self->{PI} = shift; }
  return $self->{PI};
}

=item B<piemail>

Email address of the principal investigator.

  $email = $proj->piemail;

=cut

sub piemail {
  my $self = shift;
  if (@_) { $self->{PIEmail} = shift; }
  return $self->{PIEmail};
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

=item B<remaining>

The amount of time remaining on the project (in seconds).

  $time = $proj->remaining;
  $proj->remaining( $time );

If the value is not defined, the allocated value is automatically inserted.

=cut

sub remaining {
  my $self = shift;
  if (@_) { 
    $self->{Remaining} = shift; 
  } else {
    $self->{Remaining} = $self->allocated
      unless defined $self->{Remaining};
  }
  return $self->{Remaining};
}

=item B<used>

The amount of time (in seconds) used by the project so far. This
is calculated as the difference between the allocated amount and
the time remaining on the project (the time pending is assumed to
be included in this calculation).

  $time = $proj->used;

=cut

sub used {
  my $self = shift;
  return ($self->allocated - $self->remaining - $self->pending);
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

Note that because we use unix C<crypt> we are limited to 8 characters.

Returns false if either of the passwords are missing.

=cut

sub verify_password {
  my $self = shift;
  my $plain;
  if (@_) {
    $plain = shift;
  } else {
    $plain = $self->password;
  }

  my $encrypted = $self->encrypted;

  # Return false immediately if either are undefined
  return 0 unless defined $plain and defined $encrypted;

  # The encrypted password includes the salt as the first
  # two letters. Therefore we encrypt the plain text password
  # using the encrypted password as salt
  return ( crypt($plain, $encrypted) eq $encrypted );

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
	       pi piemail projectid remaining semester tagpriority/) {
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

=back

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research
Council.  All Rights Reserved.

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=cut

1;
