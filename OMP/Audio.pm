package OMP::Audio;

=head1 NAME

OMP::Audio - methods to play audio files

=head1 SYNOPSIS

  use OMP::Audio;

  OMP::Audio->play( 'alert.wav' );

=head1 DESCRIPTION

This module provides methods for playing audio files in OMP classes and
programs.

=cut

use 5.006;
use strict;
use warnings;

use OMP::Config;

our $VERSION = (qw$Revision$)[1];

our $DEBUG = 0;

=head1 METHODS

There are no instance methods, only class (static) methods.

=over 4

=item B<play>

Play an audio file.

  OMP::Audio->play( 'alert.wav' );

This method takes one argument, a string denoting the file to be played.
The file must be located in the directory pointed to by concatenating
the 'audiodir' configuration system setting to the OMP_DIR environment
variable.

=cut

sub play {
  my $class = shift;
  my $audio_file = shift;

  my $audio_subdir = OMP::Config->getData( 'audiodir' );
  my $file = File::Spec->catfile( $ENV{'OMP_DIR'},
                                  $audio_subdir,
                                  $audio_file );

  return if ! -e $file;

  # Do some rudimentary taint checking on the path. Only allow
  # alpha-numerics, periods, front slashes and underscores.
  $file =~ /^([a-zA-Z0-9\/\._]*)$/;
  $file = $1;

  print "running /usr/bin/esdplay $file\n" if $DEBUG;

  {
    local $ENV{'PATH'} = "/bin:/usr/bin";

    # Do the system call to esdplay.
    system( "/usr/bin/esdplay", "$file" );
  }
}

=back

=head1 AUTHORS

Brad Cavanagh E<lt>b.cavanagh@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2005 Particle Physics and Astronomy Research Council.
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
