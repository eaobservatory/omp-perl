package OMP::Cookie;

=head1 NAME

OMP::Cookie - Cookie management

=head1 SYNOPSIS


  use OMP::Cookie;

  $c = new OMP::Cookie( CGI => $q, Name => $name );

  $c->setCookie( $exptime, %contents);

  print $q->header($c->cookie);

  %contents = $c->getCookie;

  $c->flushCookie;

=head1 DESCRIPTION

This class provides cookie management for the OMP feedback tool.

=cut


use 5.006;
use strict;
use warnings;
use Carp;
our $VERSION = (qw$ Revision: 1.2 $ )[1];

use OMP::Config;
use OMP::Error;

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

Create a new instance of an C<OMP::Cookie> object.

  $c = new OMP::Cookie( Name => $name, CGI => $q );

The cookie name defaults to "OMPFBLOGIN", thus the Name parameter is 
optional in the constructor.


=cut

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;

  # Read the arguments
  my %args;
  %args = @_ if @_;

  my $c = {
	   Name => $class->default_name,
	   CGI => undef,
	   Cookie => undef,
	  };

  # create the object (else we cant use accessor methods)
  my $object = bless $c, $class;

  # Populate object
  for my $key (keys %args) {
    my $method = lc($key);
    $object->$method( $args{$key});
  }

  return $object;
}

=back

=head2 Accessor Methods

=over 4

=item B<cgi>

Return the CGI object associated with the cookies.

  $cgi = $c->cgi;
  $c->cgi( $q );

The argument must be in class C<CGI>.

=cut

sub cgi {
  my $self = shift;
  if (@_) {
    my $cgi = shift;
    croak "Incorrect type. Must be a CGI object"
      unless UNIVERSAL::isa( $cgi, "CGI");
    $self->{CGI} = $cgi;
  }
  return $self->{CGI};
}

=item B<cookie>

Return the cookie object.  This is what you would give to the C<CGI>
header() method.

  $cookie = $c->cookie;
  $c->cookie( $cookie );

=cut

sub cookie {
  my $self = shift;
  if (@_) {
    my $cookie = shift;

    croak "Incorrect type. Must be a CGI object"
      unless UNIVERSAL::isa( $cookie, "CGI::Cookie");

    $self->{Cookie} = $cookie;
  }
  return $self->{Cookie};
}

=item B<default_name>

Return the default cookie name.

  $name = $c->default_name;
  $c->default_name($name);

=cut

{
  my $DEFAULT_NAME = 'OMPLOGIN';
  sub default_name {
    my $self = shift;
    if (@_) {
      throw OMP::Error::BadArgs("Value can't be a reference")
	unless (not ref($_[0]));
      $DEFAULT_NAME = $_[0];
    }
    return $DEFAULT_NAME;
  }
}

=item B<name>

The name of the cookie. Defaults to "OMPFBLOGIN" if none supplied.

  $name = $c->name;
  $c->name( "COOKIE" );

=cut

sub name {
  my $self = shift;
  if (@_) { $self->{Name} = shift; }
  return $self->{Name};
}

=back

=head2 General Methods

=over 4

=item B<flushCookie>

Delete the cookie by setting an expiry time in the past.

  $c->flushCookie();

=cut

sub flushCookie {
  my $self = shift;

  # Get the domain
  my $domain = OMP::Config->getData('cookie-domain');

  # Get the CGI object
  my $cgi = $self->cgi
    or throw OMP::Error::FatalError("No CGI object present\n");

  # create the cookie
  my $cookie = $cgi->cookie(-name=>$self->name,
			    -value=>'null',
			    -domain=>$domain,
			    -expires=>'-5m',);

  $self->cookie($cookie);
  return;
}

=item B<getCookie>

Calls the C<CGI> method to retrieve the cookie from the browser and return
the name=value pairs.

  %contents = $c->getCookie;

=cut

sub getCookie {
  my $self = shift;

  #Get the CGI object
  my $cgi = $self->cgi
    or throw OMP::Error::FatalError("No CGI object present\n");

  my %contents;
  my $cookie = $self->cookie;
  if (defined $cookie) {
    # First try to obtain the cookie stored in this object
    # since it's values might be more current than the cookie
    # contained by the browser
    %contents = $cookie->value;
  } else {
    # No cookie was stored to this object, take the
    # cookie from the browser instead
    %contents = $cgi->cookie(-name=>$self->name);
  }

  # Strip white space
  for (keys %contents) {
    $contents{$_} =~ s/^\s+//;
    $contents{$_} =~ s/\s+$//;
  }

  return %contents;
}

=item B<setCookie>

Creates the CGI cookie object. Name=value pairs should be in the form of a
hash. The expiry time can be specified as either a plain number (in which
case the expire time is set to N minutes in the future) or more explicitly
as a string such as "+4h" which would set the expiry time to four hours in
the future.

  $c->setCookie(2, %contents);

=cut

sub setCookie {
  my $self = shift;
  my $exptime = shift;
  my %contents = @_;

  # If expire time is just a number default to minutes in the future
  $exptime =~ /^\d+$/ and $exptime = '+' . $exptime . 'm';

  # Get the domain
  my $domain = OMP::Config->getData('cookie-domain');

  # Get the CGI object
  my $cgi = $self->cgi
    or throw OMP::Error::FatalError("No CGI object present\n");

  # Strip white space
  for (keys %contents) {
    $contents{$_} =~ s/^\s+//;
    $contents{$_} =~ s/\s+$//;
  }

  # create the cookie
  my $cookie = $cgi->cookie(-name=>$self->name,
			    -value=>\%contents,
			    -domain=>$domain,
			    -expires=>$exptime);

  $self->cookie($cookie);
  return;
}

=back

=head1 AUTHORS

Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>,
Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
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

