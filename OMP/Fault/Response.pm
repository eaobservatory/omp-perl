package OMP::Fault::Response;

=head1 NAME

OMP::Fault::Response - a fault response

=head1 SYNOPSIS

  use OMP::Fault::Response;

  $resp = new OMP::Fault::Response( user => $user,
                                    text => $text,
                                    date => $date );
  $resp = new OMP::Fault::Response( user => $user, 
                                    text => $text );

  $body = $resp->text;
  $user = $resp->user;


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
response is a true response or the actual fault (via "primary") are
optional.

  $resp = new OMP::Fault::Response( user => $user, 
                                    text => $text,
                                    primary => 1 );

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
	      User => undef,
	      Text => undef,
	      Date => undef,
	      Primary => 0,
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

  # Check that we have user and text
  croak "Must supply a fault user"
    unless $resp->user;
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

=item B<user>

Name of person submitting the response. There is as yet
no lookup to make sure that this person is allowed to submit
or any rules concerning whether this should be a user name
or a real name.

  $user = $resp->user;
  $resp->user( $user );

=cut

sub user {
  my $self = shift;
  if (@_) { $self->{User} = shift; }
  return $self->{User};
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

=item B<primary>

Is this response the original fault (primary = 1) or is it a response
to some other fault (primary = 0).

This flag is usually set automatically when the object is stored in
a C<OMP::Fault>.

=cut

sub primary {
  my $self = shift;
  if (@_) { $self->{Primary} = shift; }
  return $self->{Primary};
}

=back

=head2 General Methods

=over 4

=item <stringify>

Convert response to plain text for quick display.
This is the default stringification overload.

Defaults to the familiar JAC style fault response. Note that the
default stringification style is only helpful for true responses and
not for the initial "response".

=cut

sub stringify {
  my $self = shift;

  my $text = $self->text;
  my $user = $self->user;

  # Get date and format it
  my $date = $self->date->strftime("%Y-%m-%d");


  my $string = 
">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<\n".
"    RESPONSE by : $user\n".
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

=cut

1;
