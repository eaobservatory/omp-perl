# Dummy class for automatic constructors and accessors
package OMP::Info::ObsBase;

# Cheat and use automatic accessors. Very lazy
use Class::Struct;
struct(
       projectid => '$',
       checksum => '$',
       waveband => 'Astro::WaveBand',
       instrument => '$',
       disperser => '$',
       coords => 'Astro::Coords',
       target => '$',
       pol => '$',
       timeest => '$',
       type => '$',
       fits => '%',
       comments => '@',
      );


# Real work starts here
package OMP::Info::Obs;

=head1 NAME

OMP::Info::Obs - Observation information

=head1 SYNOPSIS

  use OMP::Info::Obs;

  $obs = new OMP::Info::Obs( %hash );

  $checksum = $obs->checksum;
  $projectid = $obs->projectid;

  @comments = $obs->comments;

  $xml = $obs->summary('xml');
  $html = $obs->summary('html');
  $text = "$obs";

=head1 DESCRIPTION

A compact way of handling information associated with an
Observation. This includes possible comments and information on
component observations.

=cut

use 5.006;
use strict;
use warnings;
use Carp;
use OMP::Range;

use base qw/ OMP::Info::ObsBase /;

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

=item B<instrument>

=item B<timeest>

=item B<target>

=item B<disperser>

=item B<type>

[Imaging or Spectroscopy]

=item B<pol>

=back

Accessors requiring/returning objects:

=over 4

=item B<waveband>

[Astro::WaveBand]

=item B<coords>

[Astro::Coords]

=back

Hash accessors:

=over 4

=item B<fits>

=back

Array Accessors

=over 4

=item B<comments>

=back

=head2 General Methods

=over 4

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
