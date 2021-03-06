package OMP::FaultStats;

=head1 NAME

OMP::FaultStats - Statistics for faults.

=head1 SYNOPSIS

  use OMP::FaultStats;

  $f = new OMP::FaultStats( ut => '2002-08-15' );
  $f = new OMP::FaultStats( faults => \@faults );

  $f->summary('html');

=head1 DESCRIPTION

This class can be used to determine statistics for a given
group of faults. A group can be specified by a given UT date
or by an array of faults.

=cut

use 5.006;
use strict;
use warnings;
use Carp;

our $VERSION = (qw$ Revision: $ )[1];

use OMP::Fault;
use OMP::FaultDB;
use Time::Seconds;

$| = 1;

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

Object constructor. Takes a hash as an argument, the keys of which can
be used to populate the object. The key names must match the names of
the accessor methods (ignoring case). If they do not match they are
ignored (for now).

  $f = new OMP::FaultStats( %args );

Arguments are optional.

Additionally, a key named 'faults' pointing to an array reference
containing C<OMP::Fault> objects may be passed as an argument. If
this is the case, then the C<OMP::FaultStats> object will be a summary
of all of the faults passed.

=cut

sub new {
  my $proto = shift;
  my %args = @_;
  my $class = ref($proto) || $proto;

  my $f = bless {
                 Date => undef,
                 TimeLost => undef,
                 TimeLostTechnical => undef,
                 TimeLostNonTechnical => undef,
                }, $class;

  # If we have a "faults" argument we grab the information
  # from all the faults and stick them in the Date and
  # TimeLost accessors (but what to do for multiple nights
  # of faults?)
  if( exists( $args{faults} ) ) {
    my $timelost;
    my $timelost_technical;
    my $timelost_nontech;
    my $date;

    foreach my $fault ( @{$args{faults}} ) {
      my $loss = new Time::Seconds($fault->timelost * ONE_HOUR);
      if ($fault->typeText =~ /human/i or $fault->statusText =~ /not a fault/i) {
        # Fault is non-technical
        $timelost_nontech += $loss;
      } else {
        $timelost_technical += $loss;
      }
      $timelost += $loss;
      $date = $fault->faultdate;
    }
    $f->date( $date );
    $f->timelost( $timelost );
    $f->timelostTechnical( $timelost_technical );
    $f->timelostNonTechnical( $timelost_nontech );
  } elsif( @_ ) {
    $f->populate( %args );
  }

  return $f;
}

=back

=head1 Accessor Methods

=over 4

=item B<date>

The UT date for which the fault statistics are calculated.

Must be supplied as a Time::Piece object, by convention with the
hours and minutes at zero.

=cut

sub date {
  my $self = shift;
  if (@_) {
    my $date = shift;
    croak "Date must be supplied as Time::Piece object"
      if (defined $date && ! UNIVERSAL::isa( $date, "Time::Piece" ));
    $self->{Date} = $date;
  }
  return $self->{Date};
}

=item B<timelost>

Time lost to faults on the specified UT date. The time is
represented by a Time::Seconds object.

  $time = $f->timespent;
  $f->timelost( new Time::Seconds( 3600 ) );

=cut

sub timelost {
  my $self = shift;
  if(@_) {
    my $time = shift;
    $time = new Time::Seconds( $time )
      unless UNIVERSAL::isa($time, "Time::Seconds");
    $self->{TimeLost} = $time;
  }
  return $self->{TimeLost};
}

=item B<timelostTechnical>

Time lost to technical faults (those with type that is not "human" or status other than "Not a fault").
The time is represented by a Time::Seconds object.

  $time = $f->timelostTechnical;
  $f->timelostTechnical( new Time::Seconds( 3600 ) );

=cut

sub timelostTechnical {
  my $self = shift;
  if(@_) {
    my $time = shift;
    $time = new Time::Seconds( $time )
      unless UNIVERSAL::isa($time, "Time::Seconds");
    $self->{TimeLostTechnical} = $time;
  }
  return $self->{TimeLostTechnical};
}

=item B<timelostNonTechnical>

Time lost to non-technical faults (those with type that is "human" or status of "Not a fault").  The time is represented by a Time::Seconds object.

  $time = $f->timelostNonTechnical;
  $f->timelostNonTechnical( new Time::Seconds( 3600 ) );

=cut

sub timelostNonTechnical {
  my $self = shift;
  if(@_) {
    my $time = shift;
    $time = new Time::Seconds( $time )
      unless UNIVERSAL::isa($time, "Time::Seconds");
    $self->{TimeLostNonTechnical} = $time;
  }
  return $self->{TimeLostNonTechnical};
}

=back

=head2 General Methods

=over 4

=item B<populate>

Store the UT date and/or time lost in the object.

  $f->populate( date => $date,
                timelost => $timelost,
              );

The UT date must be a Time::Piece object.

The timelost must be either a C<Time::Seconds> object or an
integer number of seconds.

=cut

sub populate {
  my $self = shift;
  my %args = @_;

  for my $key (keys %args) {
    my $method = lc($key);
    if ($self->can($method)) {
      $self->$method( $args{$key} );
    }
  }
};

=item B<summary>

Presents a summary of the information contained in the
C<OMP::FaultStats> object.

  $summary = $f->summary('html');

Valid parameters are 'html' or 'text'. Default is 'text'.

=cut

sub summary {
  my $self = shift;
  my $type = shift || 'text';

  my $date = $self->date;
  my $timelost = $self->timelost;

  if( !defined( $date ) ||
      !defined( $timelost ) ) {
    return;
  }

  my $return;
  if($type =~ /^html$/i) {
    $return .= sprintf("(%s hours from fault system)<br>\n", $timelost->hours);
  } elsif( $type =~ /^text$/i) {
    $return = sprintf("Time lost to faults on %s: %s hours\n", $date->ymd, $timelost->hours);
  }

  return $return;
}

=back

=head1 AUTHOR

Brad Cavanagh E<lt>b.cavanagh@jach.hawaii.eduE<gt>

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
