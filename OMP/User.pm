package OMP::User;

=head1 NAME

OMP::User - A User of the OMP system

=head1 SYNOPSIS

  use OMP::User;

  $u = new OMP::User( userid => 'xyz',
                      name => 'Mr Z',
                      email => 'xyz@abc.def.com');

  $u->verifyUser;

=head1 DESCRIPTION

This class simply provides details of the name and email address
of an user of the OMP system.

=cut

use 5.006;
use strict;
use warnings;
use Carp;
use OMP::UserServer;

# Overloading
use overload '""' => "stringify",
  fallback => 1;

=head1 METHODS

=head2 Constructors

=over 4

=item B<new>

Create a new C<OMP::User> object.

  $u = new OMP::User( %details );

The initial state of the object can be configured by passing in a hash
with keys: "userid", "email", "alias", "cadcuser" and "name". See the
associated accessor methods for details.

Returns C<undef> if an object can not be created or configured.

=cut

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;

  # Read the arguments
  my %args = @_;

  # Create and bless
  my $user = bless {
		    UserID => undef,
		    Email => undef,
		    Name => undef,
		    Alias => undef,
		    CADC => undef,
		   }, $class;

  # Go through the input args invoking relevant methods
  for my $key (keys %args) {
    my $method = lc($key);
    if ($user->can($method)) {
      # Return immediately if an accessor methods
      # returns undef (unless it was given undef)
      my $retval = $user->$method( $args{$key});
      return undef if (!defined $retval && defined $args{$key});
    }
  }

  return $user;
}

=item B<extract_user>

Attempt to extract a OMP::User object from an email
"From:" line or from a HTML hyperlink. This is simply
a thin layer above B<extract_user_from_email> and
B<extract_user_from_href>. The method tries to
determine which method would be best to use.

  $user = OMP::User->extract_user( $string );

Returns undef if no user information could be extracted.

=cut

sub extract_user {
  my $class = shift;
  my $string = shift;

  # First see if we have a mailto
  my $result;
  if ($string =~ /mailto:/) {
    # looks like HTML
    $result = $class->extract_user_from_href( $string );
  } elsif ($string =~ /@/) {
    # Looks like an email
    $result = $class->extract_user_from_email( $string );
  }

  return $result;

}

=item B<extract_user_from_email>

Attempt to extract a OMP::User object from an email
"From:" line. Assumes the email information is of the
form 

   Name Label <x@a.b.c>

If there is no "comment" attached to the email address itself the text
before the @ will be treated as a full name if it contains a dot. If
no name comment is available and the email address itself does not
look like a I.Surname then this method returns undef (the alternative
is to return simply an object with an email address but that does not
seem to be useful). Also returns undef if a valid user ID can not be
inferred from the name.

  $user = OMP::User->extract_user_from_email( $email_string );

Even though this method is technically a constructor it is not called
directly from the normal constructor because it is forced to guess the
user ID.

=cut

sub extract_user_from_email {
  my $class = shift;

  my $string = shift;

  # Look for  "Name <addr>"
  # [^>] matches any character that is not a ">"
  # This allows us to get all the characters in an email
  # address without having to list every single acceptable
  # character. The presence of a closing ">" is all that matters.
  my ($name, $email);
  if ($string =~ /^\s*([^<]+)\s*<([^>]+)>/) {
    $name = $1;
    $email = $2;

    # Remove trailing spaces and compress spaces
    $name = _clean_string( $name );
    $email = _clean_string( $email );

  } elsif ($string =~ /^\s*<?([^>]+)>?/) {
    $email = $1;

    # Get the to from the email address
    my ($to, $domain) = split(/@/,$email);

    # Treat it as a name if it includes a dot (e.g. t.jenness@jach)
    $name = $to if $to =~ /\./;
  }

  # do not continue if we have no name
  return undef unless defined $name;

  # Attempt to get user id
  my $userid = $class->infer_userid( $name );

  return undef unless defined $userid;

  # Form a valid object
  return $class->new( name => $name,
		      userid => $userid,
		      email => $email);

}

=item B<extract_user_from_href>

Similar to C<extract_user_from_email> except that this method
looks for names and emails in an HTML format hyperlink:

  <a href="mailto:email">Name</a>

If "Name" above happens to also be "email" the non-domain
part of the email address is used to construct the name if
it contains a dot. If it does not contain a dot this method
returns undef. If the "Name" includes an "@" but is not the
same as the mailto email address, also returns undef since
the email addresses must be the same.

  $user = OMP::User->extract_user_from_href( $text );

=cut

sub extract_user_from_href {
  my $class = shift;
  my $string = shift;

  # Try to get the mail to and the name
  my ($email, $name);
  if ($string =~ /mailto:([^\"]+)\"\s*>([^<]+)/) {
    $email = $1;
    $name = $2;

    # clean the string
    $name = _clean_string( $name );
    $email = _clean_string( $email );
  } else {
    return undef;
  }

  # Is the email the same as the name?
  if ($email eq $name) {
    my ($id,$domain) = split(/@/, $name);
    $name = $id if $id =~ /\./;

  } elsif ($name =~ /@/) {
    # we have an email address in the name field
    # but it does not match the actual email address
    $name = undef;
  }

  return undef unless defined $name;

  # Attempt to get user id
  my $userid = $class->infer_userid( $name );

  return undef unless defined $userid;

  # Form a valid object
  return $class->new( name => $name,
		      userid => $userid,
		      email => $email);

}

=back

=head2 Accessors

=over 4

=item B<userid>

The user name. This must be unique.

  $id = $u->userid;
  $u->userid( $id );

The user id is upper cased.

=cut

sub userid {
  my $self = shift;
  if (@_) { $self->{UserID} = uc(shift); }
  return $self->{UserID};
}

=item B<name>

The name of the user.

  $name = $u->name;
  $u->name( $name );

=cut

sub name {
  my $self = shift;
  if (@_) { $self->{Name} = shift; }
  return $self->{Name};
}

=item B<email>

The email address of the user.

  $addr = $u->email;
  $addr->email( $addr );

It must contain a "@". If the email does not look like an email
address the value will not be changed and the method will return
C<undef>.

An undefined or null string email address is allowed.
A null string is treated as undef.

=cut

sub email {
  my $self = shift;
  if (@_) { 
    my $addr = shift;
    if (defined $addr) {
      # Also translate '' to undef
      if (length($addr) == 0) {
	# Need to do this so that we match our input string
	$self->{Email} = undef;
	return '';
      }
      return undef unless $addr =~ /\@/;
    }
    # undef is okay
    $self->{Email} = $addr;
  }
  return $self->{Email};
}

=item B<alias>

Return the user's alias.

  $alias = $u->alias;
  $u->alias( $alias );

=cut

sub alias {
  my $self = shift;
  if (@_) {$self->{Alias} = shift;}
  return $self->{Alias};
}

=item B<alias>

Return the user's CADC user name.

  $cadc = $u->cadcuser;
  $u->cadcuser( $cadc );

=cut

sub cadcuser {
  my $self = shift;
  if (@_) {$self->{CADC} = shift;}
  return $self->{CADC};
}


=back

=head2 General

=over 4

=item B<html>

Generate an HTML representation of the user information.

  $html = $u->html;

Returns a HTML string looking like:

  <a href="mailto:$email">$name</a>

if the email address is defined.

=cut

sub html {
  my $self = shift;
  my $email = $self->email;
  my $name = $self->name;
  my $id = $self->userid;

  my $html;
  if ($email) {
    # We have an email address

    # if no name so use email
    $name = $email unless $name;

    $html = "<A HREF=\"mailto:$email\">$name</A>";

  } elsif ($name) {

    # Just a name
    $html = "<B>$name</B>";

  } elsif ($id) {

    $html = "<B>$id</B>";

  } else {
    # User id

    $html = "<I>No name specified</I>";

  }

  return $html;
}

=item B<text_summary>

[should probably be part of a general summary() method that takes
a "format" as argument]

  $text = $user->text_summary;

=cut

sub text_summary {
  my $self = shift;
  my $email = $self->email;
  my $name = $self->name;
  my $id = $self->userid;
  my $alias = $self->alias;
  my $cadcuser = $self->cadcuser;

  my $text = "USERID: $id\n";

  $text .=   "NAME:   " .(defined $name ? $name : "UNDEFINED")."\n";
  $text .=   "EMAIL:  " .(defined $email ? $email : "UNDEFINED")."\n";
  $text .=   "ALIAS:  " .(defined $alias ? $email : "UNDEFINED")."\n";
  $text .=   "CADC:   " .(defined $cadcuser ? $email : "UNDEFINED")."\n";

  return $text;
}

=item B<stringify>

Stringify overload. Returns the name of the user.

=cut

sub stringify {
  my $self = shift;
  my $name = $self->name;
  $name = '' unless defined $name;
  return $name;
}

=item B<verify>

Verify that the user described in this object is a valid
user of the OMP. This requires a query of the OMP database
tables. All entries are compared.

  $isthere = $u->verify;

Returns true or false.

[simply verifies that the userid exists. Does not yet verify contents]

=cut

sub verify {
  my $self = shift;
  return OMP::UserServer->verifyUser( $self->userid );
}

=item B<domain>

Returns the domain associated with the email address. Returns
undef if no email address is stored in the object.

  $domain = $u->domain;

=cut

sub domain {
  my $self = shift;
  my $email = $self->email;
  return unless $email;

  # chop off the front
  $email =~ s/.*@//;
  return $email;
}

=item B<addressee>

Return the user name associated with the email address. (the
part in front of the "@").

  $to = $u->addressee;

=cut

sub addressee {
  my $self = shift;
  my $email = $self->email;
  return unless $email;

  # use a pattern match in case we have somehow managed
  # to get  "Label <to@domain>
  if ($email =~ /<?(.*)@/) {
    return $1;
  } else {
    return undef;
  }

}

=item B<as_email_hdr>

Return the user name and email address in the format suitable for 
use in an email header. (i.e.: "Kynan Delorey <kynan@jach.hawaii.edu>").

  $email_hdr = $u->as_email_hdr;

=cut

sub as_email_hdr {
  my $self = shift;

  # Done this way to get rid of multiple "Use of uninitialized value in 
  # concatenation (.) or string at msbserver/OMP/User.pm line 477" errors
  # which are annoying me like crazy. Preserves the original functionality
  # of the as_email_hdr() function, which was simply...
  #
  # sub as_email_hdr {
  #     my $self = shift;
  #     return $self->name . " <" . $self->email . ">";
  # }
  #
  # Modified by Alasdair Allan  (20-JUL-2003)
  # Extensive docs due to fact I probably shouldn't be playing with this...
  
  my $name = $self->name;
  my $email = $self->email;
 
  if ( defined $name && defined $email ) {
     return $name . " <" . $email . ">";
  } elsif ( defined $name ) {
     return "$name";
  } elsif ( defined $email ) {
     return "$email";
  } else {
     return "No contact information";         
  }
}

=item B<infer_userid>

Try to guess the user ID from the name. The name can either
be supplied as an argument or from within the object.

This method can be called either as a class or instance method.

  $guess = OMP::User->infer_userid( 'T Jenness' );
  $guess = $user->infer_userid;

Although the latter is only interesting if used to raise
warnings about inconsistent IDs (which is generally not enforced)
or after creating an object and making an inspired guess from the
name. The userid in the object is not updated via this method.

The guess work assumes that the name is "forname surname" (although
"F.Surname" is also okay) or alternatively "surname, forname". A
simplistic attempt is made to catch "Jr" and "Sr" as well as common
prefixes such as "Mr", "Prof" and "Dr". Also, "van", "van der", "le"
and "de" are treated as part of the surname (e.g. "U le Guin" would be
"LEGUINU").

Returns undef if a user ID could not be guessed.

=cut

sub infer_userid {
  my $self = shift;

  my $name;
  if (@_) {
    $name = shift;
  } elsif (UNIVERSAL::can($self,"name")) {
    $name = $self->name
  } else {
    croak "This method must be called with an argument or via a valid user object";
  }

  return undef unless defined $name;
  return undef unless $name =~ /\w/;

  # Remove some common suffixes
  $name =~ s/\b[JS]r\.?//g;

  # and prefixes: Dr Mr Mrs Ms Prof
  $name =~ s/\b[MD]rs\.?\W//;
  $name =~ s/\b[MD][rs]\.?\W//;
  $name =~ s/\bProf\.?\W//;

  # Clean
  $name =~ s/^\s+//;

  # Get the first name and surname
  my ($forname, $surname);
  if ($name =~ /,/) {
    # surname, initial (no need to worry about middle initials here
    ($surname, $forname) = split(/\s*,\s*/,$name,2);
  } else {
    # We want the last word for surname and the first for forname
    # since we do allow middle names
    my @parts = split(/\s+/,$name);

    # if we only got a single match, see what happens if we split
    # on dot (checking for T.Jenness)
    if (scalar(@parts) == 1) {
      @parts = split(/\./, $name);
    }

    return undef if scalar(@parts) < 2;
    $forname = $parts[0];
    $surname = $parts[-1];

    # Note that "le Guin" is surname LEGUIN
    # van der Blah is VANDERBLAH
    if (scalar(@parts) > 2) {
      if ($parts[-2] =~ /^(LE)$/i ||
	  $parts[-2] =~ /^DE$/i ||
	  $parts[-2] =~ /^van$/i
	 ) {
	$surname = $parts[-2] . $surname;
      } elsif (scalar(@parts) > 3 && 
	       $parts[-3] =~ /^van$/i && $parts[-2] =~ /^der$/) {
	$surname = $parts[-3] . $parts[-2] . $surname;
      }

    }

  }

  my $id = $surname . substr($forname,0,1);

  # Remove characters that are not  letter (eg hyphens)
  $id =~ s/\W//g;

  return uc($id);
}

=back

=begin __PRIVATE__

=head2 Internal functions

=over 4

=item B<_clean_string>

Remove trailing and leading space and convert multiple spaces
into single spaces.

 $new = _clean_string( $old );

=cut

sub _clean_string {
  my $in = shift;
  $in =~ s/\s*$//;
  $in =~ s/^\s*//;
  $in =~ s/\s+/ /g;
  return $in;
}

=back

=end __PRIVATE__

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2002 Particle Physics and Astronomy Research Council.
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

1;
