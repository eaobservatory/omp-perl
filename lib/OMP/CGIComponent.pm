package OMP::CGIComponent;

=head1 NAME

OMP::CGIComponent - Components for OMP web pages

=head1 SYNOPSIS

  use OMP::CGIComponent;
  $comp = new OMP::CGIComponent(page => $cgipage);

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

  $comp = new OMP::CGIComponent(page => $cgipage);

=cut

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;

  my %args;
  %args = @_ if @_;

  my $c = {
           page => undef,
          };

  my $object = bless $c, $class;

  # Populate object
  for my $key (keys %args) {
    $object->$key($args{$key});
  }

  return $object;
}

=back

=head2 Accessor methods

=over 4

=item B<page>

The OMP::CGIPage object.

  $page = $comp->page;

Argument is an object of the class C<OMP::CGIPage>.

=cut

sub page {
  my $self = shift;
  if (@_) {
    my $page = shift;
    throw OMP::Error::BadArgs("Object must be of class OMP::CGIPage")
      unless (UNIVERSAL::isa($page, 'OMP::CGIPage'));
    $self->{'page'} = $page;
  }
  return $self->{'page'};
}

=item B<cgi>

Obtain the parent CGIPage's CGI object.

  $q = $comp->cgi;

The return value is an object of the class C<CGI>.

=cut

sub cgi {
  my $self = shift;

  my $page = $self->page();
  throw OMP::Error::BadArgs("OMP::CGIComponent has no parent OMP::CGIPage")
    unless defined $page;

  return $page->cgi();
}

=item B<database>

Obtain the parent CGIPage's database backend object.

=cut

sub database {
    my $self = shift;

    my $page = $self->page();
    throw OMP::Error::BadArgs('OMP::CGIComponent has no parent OMP::CGIPage')
        unless defined $page;

    return $page->database();
}

=item B<auth>

Obtain the parent CGIPage's authentication object.

  $auth = $comp->auth;

The return value is an object of the class C<OMP::Auth>.

=cut

sub auth {
  my $self = shift;

  my $page = $self->page();
  throw OMP::Error::BadArgs("OMP::CGIComponent has no parent OMP::CGIPage")
    unless defined $page;

  return $page->auth();
}

=back

=head2 General methods

=over 4

=item B<url_args>

Alter query parameters in the current URL.  Useful for creating links to the
same script but with different parameters.

  $url = $comp->url_args($key, $newvalue);

The first argument is the paramter name.
Last argument is the new value of the paramater. All arguments
are required.

=cut

sub url_args {
  my $self = shift;
  my $key = shift;
  my $newvalue = shift;

  # Clone the CGI object and alter the parameter.
  my $q = $self->cgi->new;
  $q->param($key, $newvalue);

  # Create an "absolute" URL (without path).
  return $q->url(-absolute => 1, -query => 1);
}

=back

=head1 AUTHOR

Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>,

=head1 COPYRIGHT

Copyright (C) 2004 Particle Physics and Astronomy Research Council.
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
