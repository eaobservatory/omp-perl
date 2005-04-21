package OMP::TransServer;

=head1 NAME

OMP::TransServer - Sp translator server

=head1 SYNOPSIS

  use OMP::TransServer;

  $odf = OMP::TransServer->translate( $xml );

=head1 DESCRIPTION

Translation server. Used to convert science program XML to sequences
understandable by the data acquisition systems.

=cut

use 5.006;
use strict;
use warnings;

use OMP::Error qw/ :try /;
use OMP::SciProg;
use OMP::Translator;

# Inherit server specific class
use base qw/ OMP::SOAPServer /;

our $VERSION = (qw$Revision$)[1];


=head1 METHODS

=over 4

=item B<translate>

Translate the specified Science Program into a form understandable by
the observing system.

  $translation = OMP::TransServer->translate( $xml, \%options );

Returns a filename suitable for passing to the queue or the Query Tool,
not the translated configurations themselves.

Only works for JCMT translations. The UKIRT translator is written 
in Java and part of the OT software package.

The location of the directory used to write these files can not be
configured via SOAP for security reasons.

Supported options are:

  simulate : Run the translator for simulated configurations

Note that a reference to a hash is used to simplify the SOAP interface.

=cut

sub translate {
  my $class = shift;
  my $xml = shift;
  my $opts = shift;

  # in some cases the msb attribute of SpObs is incorrect from the QT
  # so we need to fudge it here if we have no SpMSB
  if ($xml !~ /<SpMSB>/) {
    my $old = 'msb="false"';
    my $new = 'msb="true"';
    $xml =~ s/$old/$new/;
  }

  my $E;
  my $result;
  try {
    # expand options
    my %options;
    %options = %$opts if (defined $opts && ref($opts) eq 'HASH');

    # Convert to science program
    my $sp = new OMP::SciProg( XML => $xml );
    $result = OMP::Translator->translate( $sp, %options );
  } catch OMP::Error with {
    # Just catch OMP::Error exceptions
    # Server infrastructure should catch everything else
    $E = shift;
  } otherwise {
    # No difference yet
    $E = shift;
  };

  # This has to be outside the catch block else we get
  # a problem where we cant use die (it becomes throw)
  $class->throwException( $E ) if defined $E;

  return $result;
}


=back

=head1 COPYRIGHT

Copyright (C) 2002-2005 Particle Physics and Astronomy Research Council.
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


=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=cut

1;
