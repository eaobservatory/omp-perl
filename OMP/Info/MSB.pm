# Dummy class for constructor and accessors
package OMP::Info::MSBBase;

use Class::Struct;
struct( OMP::Info::MSBBase =>
	{
	 projectid => '$',
         checksum => '$',
	 tau => 'OMP::Range',
         seeing => 'OMP::Range',
         priority => '$',
         moon =>  'OMP::Range',
         timeest => '$',
         title => '$',
         dates => 'OMP::Range',
         telescope => '$',
         cloud => 'OMP::Range',
         observations => '@',
         comments => '@',
	 wavebands => '$',
	 targets => '$',
	 instruments => '$',
        });

#'
# Real work starts here

package OMP::Info::MSB;

=head1 NAME

OMP::Info::MSB - MSB information

=head1 SYNOPSIS

  use OMP::Info::MSB;

  $msb = new OMP::Info::MSB( %hash );

  $checksum = $msb->checksum;
  $projectid = $msb->projectid;

  @observations = $msb->observations;
  @comments = $msb->comments;

  $xml = $msb->summary('xml');
  $html = $msb->summary('html');
  $text = "$msb";

=head1 DESCRIPTION

A compact way of handling information associated with an MSB. This
includes possible comments and information on component observations.


This class should not be confused with C<OMP::MSB>. That class 
is based around the Science Program XML representation of an MSB
and not for general purpose MSB information.

=cut

use 5.006;
use strict;
use warnings;
use Carp;
use OMP::Range;

use base qw/ OMP::Info::MSBBase /;

our $VERSION = (qw$Revision$)[1];

use overload '""' => "stringify";

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

=back

=head2 Accessor Methods

Scalar accessors:

=over 4

=item B<projectid>

=item B<checksum>

=item B<priority>

=item B<timeest>

=item B<title>

=back

Accessors requiring/returning C<OMP::Range> objects:

=over 4

=item B<tau>

=item B<seeing>

=item B<moon>

=item B<cloud>

=item B<dates>

=back

Array accessors:

=over 4

=item B<observations>

=item B<comments>

=back

=head2 General Methods

=over 4

=item B<waveband>

Construct a waveband summary of the MSB. This retrieves the waveband
from each observation and returns a single string. Duplicate wavebands
are ignored.

  $wb = $msb->waveband();

If a waveband string has been stored in C<wavebands()> that value
will be used in preference to looking for constituent observations.

If a value is supplied it is passed onto the C<wavebands> method.

=cut

sub waveband {
  my $self = shift;
  if (@_) {
    my $wb = shift;
    return $self->wavebands( $wb );
  } else {
    my $cache = $self->wavebands;
    if ($cache) {
      return $cache;
    } else {
      # Ask the observations
    }
  }

}

=item B<instrument>

Construct a instrument summary of the MSB. This retrieves the instrument
from each observation and returns a single string. Duplicate instruments
are ignored.

  $targ = $msb->instrument();

If a instruments string has been stored in C<instruments()> that value
will be used in preference to looking for constituent observations.

If a value is supplied it is passed onto the C<instruments> method.

=cut

sub instrument {
  my $self = shift;
  if (@_) {
    my $i = shift;
    return $self->instruments( $t );
  } else {
    my $cache = $self->instruments;
    if ($cache) {
      return $cache;
    } else {
      # Ask the observations
    }
  }

}

=item B<target>

Construct a target summary of the MSB. This retrieves the target
from each observation and returns a single string. Duplicate targets
are ignored.

  $targ = $msb->target();

If a targets string has been stored in C<targets()> that value
will be used in preference to looking for constituent observations.

If a value is supplied it is passed onto the C<targets> method.

=cut

sub target {
  my $self = shift;
  if (@_) {
    my $t = shift;
    return $self->targets( $t );
  } else {
    my $cache = $self->targets;
    if ($cache) {
      return $cache;
    } else {
      # Ask the observations
    }
  }

}

=item B<summary>

Return a summary of this object in the requested format.

=cut

sub summary {

}

=item B<stringify>

=cut

sub stringify {
  my $self = shift;
  return "NOT YET IMPLEMENTED";
}

=back

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
