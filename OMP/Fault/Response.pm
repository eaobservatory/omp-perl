package OMP::Fault::Response;

=head1 NAME

OMP::Fault::Response - a fault response

=head1 SYNOPSIS

  use OMP::Fault::Response;

  $resp = new OMP::Fault::Response( author => $user,
                                    text => $text,
                                    date => $date );
  $resp = new OMP::Fault::Response( author => $user, 
                                    text => $text );

  $body = $resp->text;
  $user = $resp->author;


=head1 DESCRIPTION

This is used for fault responses (including the initial fault
message).  Multiple fault responses can be stored in a single
C<OMP::Fault> object.

=cut

use 5.006;
use warnings;
use strict;
use Carp;

use Time::Piece;

our $VERSION = (qw$Revision$)[1];

# Overloading
use overload '""' => "stringify";


=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

Create a new fault response object. The name of the person submitting
the response and the response itself must be supplied to the
constructor. The response date and an indication of whether the
response is a true response or the actual fault (via "isfault") are
optional.

  $resp = new OMP::Fault::Response( author => $author, 
                                    text => $text,
                                    isfault => 1 );

If it is not specified the current date will be used. The date must be
supplied as a C<Time::Piece> object and is assumed to be UT.

=cut

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;

  # Arguments
  my %args = @_;

  # initialize the hash
  my $resp = {
	      Author => undef,
	      Text => undef,
	      Date => undef,
	      IsFault => 0,
	      RespID => undef,
	     };

  bless $resp, $class;

  # if a date has not been supplied get current
  $args{date} = gmtime() unless (exists $args{date} or exists $args{Date});

  # Invoke accessors to configure object
  for my $key (keys %args) {
    my $method = lc($key);
    if ($resp->can($method)) {
      $resp->$method( $args{$key});
    }
  }

  # Check that we have author and text
  croak "Must supply a fault author"
    unless ref($resp->author);
  croak "Must supply a fault response (text)"
    unless $resp->text;

  # Return the object
  return $resp;
}

=back

=head2 Accessor methods

=over 4

=item B<text>

Text content forming the response. Should be in HTML (but can simply
be plain text surround by C<PRE> tags).

  $text = $resp->text;
  $resp->text( $text );

=cut

sub text {
  my $self = shift;
  if (@_) { $self->{Text} = shift; }
  return $self->{Text};
}

=item B<author>

OMP::User object describing the person submitting the response. There
is as yet no lookup to make sure that this person is allowed to submit
a fault or whether their details exist in the OMP system.

  $author = $resp->author;
  $resp->author( $author );

=cut

sub author {
  my $self = shift;
  if (@_) {
    my $user = shift;
    die "Author must be supplied as OMP::User object"
      unless UNIVERSAL::isa( $user, "OMP::User" );
    $self->{Author} = $user;
  }
  return $self->{Author};
}

=item B<date>

The date the response was filed. Returned (and must be supplied) as a
C<Time::Piece> object.

  $date = $resp->date;
  $resp->date( $date );

=cut

sub date {
  my $self = shift;
  if (@_) {
    my $date = shift;
    croak "Date must be supplied as Time::Piece object"
      unless UNIVERSAL::isa( $date, "Time::Piece" );
    $self->{Date} = $date;
  }
  return $self->{Date};
}

=item B<isfault>

Is this response the original fault (isfault = 1) or is it a response
to some other fault (isfault = 0).

This flag is usually set automatically when the object is stored in
a C<OMP::Fault>.

=cut

sub isfault {
  my $self = shift;
  if (@_) { $self->{IsFault} = shift; }
  return $self->{IsFault};
}

=item B<id>

Retrieve or store an ID that uniquely identifies a fault response.  This ID
is derived from the database once the response is stored to the database.

  $id = $resp->id;
  $resp->id( $id );

=cut

sub id {
  my $self = shift;
  if (@_) { $self->{RespID} = shift; }
  return $self->{RespID};
}

=item B<respid>

A synonym for C<id> described elsewhere in this document.

  $respid = $resp->respid;
  $resp->respid($respid);

=cut

sub respid {
  my $self = shift;
  return $self->id(@_);
}

=back

=head2 General Methods

=over 4

=item <stringify>

Convert response to plain text for quick display.
This is the default stringification overload.

Defaults to the familiar JAC style fault response. Note that the
default stringification style is only helpful for true responses and
not for the initial "response" (we could use C<isfault> but then the
stringifcation would simply be the text).

=cut

sub stringify {
  my $self = shift;

  my $text = $self->text;
  my $author = $self->author;

  # Get date and format it
  my $date = $self->date;
  $date = (defined $date ? $date->strftime("%Y-%m-%d") : "ERROR");


  my $string = 
">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<\n".
"    RESPONSE by : $author\n".
"                                      date : $date\n".
"\n".
"$text\n";

  return $string;

}

=back

=head1 SEE ALSO

C<OMP::Fault>, C<OMP::FaultDB>.

=head1 AUTHORS

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
along with this program (see SLA_CONDITIONS); if not, write to the
Free Software Foundation, Inc., 59 Temple Place, Suite 330,
Boston, MA  02111-1307  USA

=cut

1;
