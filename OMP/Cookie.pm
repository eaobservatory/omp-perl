package OMP::Cookie;

=head1 NAME

OMP::Cookie - Cookie management

=head1 SYNOPSIS


  use OMP::Cookie;

  $c = new OMP::Cookie( CGI => $q, Name => $name );

  $c->setCookie( password => $pass, projectid => $projid );
  %contents = $c->getCookie;

  $c->flushCookie;

  $html = $c->sidebar;

=head1 DESCRIPTION

Blah blah

=cut


use 5.006;
use strict;
use warnings;
use Carp;
our $VERSION = (qw$ Revision: 1.2 $ )[1];

use OMP::Error;

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

Create a new instance of an C<OMP::Cookie> object.

  $c = new OMP::Cookie( Name => $name, CGI => $q );

=cut

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;

  # Read the arguments
  my %args;
  %args = @_ if @_;

  my $c = {
	   Name => "OMPFBLOGIN",
	   CGI => undef,
	  };

  # create the object (else we cant use accessor methods)
  my $object = bless $c, $class;

  # Populate object
  for my $key (keys %args) {
    my $method = lc($key);
    $object->$method( $args{$_});
  }

  return $object;
}

=back

=head2 Accessor Methods

=over 4

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
      if UNIVERSAL::isa( $cgi, "CGI");
    $self->{CGI} = $cgi;
  }
  return $self->{CGI};
}

=item B<cookie>

The cookie object.

  $cookie = $c->cookie;
  $c->cookie( $cookie );

=cut

sub cookie {
  my $self = shift;
  if (@_) {
    my $cookie = shift;

    croak "Incorrect type. Must be a CGI object"
      if UNIVERSAL::isa( $cookie, "CGI::Cookie");

    $self->{Cookie} = $cookie;
  }
  return $self->{Cookie};
}

=back

=head2 General Methods

=over 4

=item B<setCookie>

=cut

sub setCookie {
  my $self = shift;
  my $exptime = shift;
  my %contents = @_;

  # Get the CGI object
  my $cgi = $self->cgi
    or throw OMP::Error::FatalError("No CGI object present\n");

  # create the cookie
  my $cookie = $cgi->cookie(-name=>$self->name,
			    -value=>\%contents,
			    -expires=>'+' . $exptime . 'm',);

  $self->cookie($cookie);
  return;
}

=item B<getCookie>

=cut

sub getCookie {
  my $self = shift;
  return $cgi->cookie($self->cookie);
}

=back




=head1 AUTHORS

Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>,
Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;

