package OMP::CGIComponent;

=head1 NAME

OMP::CGIComponent - Components for OMP web pages

=head1 SYNOPSIS

  use CGI;
  use OMP::CGIComponent;
  $query = new CGI;
  $comp = new OMP::CGIComponent(CGI => $query);

=head1 DESCRIPTION

Provide methods to generate and display components of dynamic OMP
web pages. Methods are also provided for parsing input taken by
forms displayed on the pages.

=cut

use 5.006;
use strict;
use warnings;
use CGI::Carp qw(fatalsToBrowser);

use OMP::Error;

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

Create a new instance of an C<OMP::CGIComponent> object.

  $comp = new OMP::CGIComponent(CGI => $query);

=cut

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;

  my %args;
  %args = @_ if @_;

  my $c = {
	   CGI => undef,
	   Password => undef,
	   ProjectID => undef,
	  };

  my $object = bless $c, $class;

  # Populate object
  for my $key (keys %args) {
    my $method = lc($key);
    $object->method($args{$key});
  }

  return $object;
}

=back

=head2 Accessor methods

=over 4

=item B<cgi>

The CGI object.

  $query = $comp->cgi
  $comp->cgi($query)

Argument is an object of the class C<CGI>.

=cut

sub cgi {
  my $self = shift;
  if (@_) {
    my $q = shift;
    throw OMP::Error::BadArgs ("Object must be of class CGI")
      unless (UNIVERSAL::isa($q, 'CGI'));
    $self->{CGI} = $q;
  }
  return $self->{CGI};
}

=item B<password>

The project password.

  $query = $comp->password
  $comp->password($password)

Argument is a password for an OMP project.

=cut

sub password {
  my $self = shift;
  if (@_) {
    $self->{Password} = shift;
  }
  return $self->{Password};
}

=item B<projectid>

The project ID.

  $query = $comp->projectid
  $comp->cgi($projectid)

Argument is a valid OMP project ID.

=cut

sub projectid {
  my $self = shift;
  if (@_) {
    $self->{ProjectID} = shift;
  }
  return $self->{ProjectID};
}

=back

=head2 General methods

=over 4

=item B<url_args>

Alter query parameters in the current URL.  Useful for creating links to the
same script but with different parameters.

  $url = $fcgi->url_args($key, $oldvalue, $newvalue);

The first argument is the paramter name.  Second argument is that parameter's
current value.  Last argument is the new value of the paramater. All arguments
are required.

=cut

sub url_args {
  my $self = shift;
  my $key = shift;
  my $oldvalue = shift;
  my $newvalue = shift;
  my $q = $self->cgi;

  my $url = $q->self_url;
  $url =~ s/(\;|\?|\&)$key\=$oldvalue//g;
    if ($url =~ /\?/) {
      $url .= "&" . $key . "=" . $newvalue;
    } else {
      $url .= "?" . $key . "=" . $newvalue;
    }

  return $url;
}

=head1 AUTHOR

Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>,

=head1 COPYRIGHT

Copyright (C) 2004 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
