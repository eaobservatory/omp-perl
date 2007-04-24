package OMP::Info::Comment;

=head1 NAME

OMP::Info::Comment - a comment

=head1 SYNOPSIS

  use OMP::Info::Comment;

  $resp = new OMP::Info::Comment( author => $user,
                                  text => $text,
                                  date => $date );
  $resp = new OMP::Info::Comment( author => $user,
                                  text => $text,
                                  status => OMP__DONE_DONE );

  $body = $resp->text;
  $user = $resp->author;

  $tid = $resp->tid;

=head1 DESCRIPTION

This is used to attach comments to C<OMP::Info::MSB> and C<OMP::Info::Obs>
objects. Multiple comments can be stored in each of these objects.

=cut

use 5.006;
use warnings;
use strict;
use Carp;

use OMP::Error;
use Time::Piece qw/ :override /;

our $VERSION = (qw$Revision$)[1];

use base qw/ OMP::Info::Base /;

# Overloading
use overload '""' => "stringify";


=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

Create a new comment object. 
The comment must ideally be supplied in the constructor but this is
not enforced. "author", "status", "tid" and "date" are optional.


  $resp = new OMP::Info::Comment( author => $author,
                                  text => $text,
                                  status => 1 );

If it is not specified the current date will be used. The date must be
supplied as a C<Time::Piece> object and is assumed to be UT. The tid can
be undefined.

=cut

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;

  my $comm = $class->SUPER::new( @_ );

#  $comm->_populate();

  # Return the object
  return $comm;
}

=back

=begin __PRIVATE__

=head2 Create Accessor Methods

Create the accessor methods from a signature of their contents.

=cut

__PACKAGE__->CreateAccessors( _text => '$',
                              author => 'OMP::User',
                              _date => 'Time::Piece',
                              status => '$',
                              runnr => '$',
			      tid => '$',
                              instrument => '$',
                              telescope => '$',
                              startobs => 'Time::Piece',
                              obsid => '$',
                            );

=end __PRIVATE__

=head2 Accessor methods

=over 4

=item B<text>

Text content forming the comment. Should be in plain text.

  $text = $comm->text;
  $comm->text( $text );

Returns empty string if text has not been set. Strips whitespace
from beginning and end of text when used as a constructor.

=cut

sub text {
  my $self = shift;
  if (@_) {
    my $text = shift;
    if (defined $text) {
      $text =~ s/^\s+//s;
      $text =~ s/\s+$//s;
    }
    $self->_text( $text );
  }

  return ( defined $self->_text ? $self->_text : '' );
}

=item B<date>

Date the comment was filed. Must be a Time::Piece object.

  $date = $comm->date;
  $comm->date( $date );

If the date is not defined when the C<Info::Comment> object
is created, it will default to the current time.

=cut

sub date {
  my $self = shift;
  if (@_) {
    my $date = shift;
    $self->_date( $date );
  }

  if( ! defined( $self->_date ) ) {
    my $new = gmtime();
    $self->_date( $new );
  }

  return $self->_date;
}

=head2 General Methods

=over 4

=item <stringify>

Convert comment to plain text for quick display.
This is the default stringification overload.

Just returns the comment text.

=cut

sub stringify {
  my $self = shift;
  return $self->text;
}

=item B<summary>

Summary of the object in different formats.

  $xml = $comm->summary( 'xml' );

=cut

sub summary {
  my $self = shift;
  my $format = lc(shift);

  $format = 'xml' unless $format;

  # Create hash
  my %summary;
  for (qw/ text author status date tid /) {
    $summary{$_} = $self->$_();
  }

  if ($format eq 'hash') {
    return (wantarray ? %summary : \%summary );
  } elsif ($format eq 'xml') {
    my $xml = "<SpComment>\n";
    for my $key (keys %summary) {
      next if $key =~ /^_/;
      next unless defined $summary{$key};
      $xml .= "<$key>$summary{$key}</$key>\n";
    }
    $xml .= "</SpComment>\n";
    return $xml;

  } else {
    throw OMP::Error::FatalError("Unknown format: $format");
  }

}

=back

=head1 SEE ALSO

C<OMP::Info::Obs>, C<OMP::Fault>, C<OMP::User>

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>
Brad Cavanagh E<lt>b.cavanagh@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2002-2004 Particle Physics and Astronomy Research
Council. Copyright (C) 2007 Science and Technology Facilities Council.
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
