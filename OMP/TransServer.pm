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

Translate the specified Science Program subset (which must contain a
single SpObs) into a sequence/odf understandable by the observing
system.

  $translation = OMP::TransServer->translate( $xml );

Currently SCUBA specific for demo purposes.

The ODFs (observation definition files) are written to a directory
accessible to the observing system. After translation the full path to
the ODF is returned. This can be used directly by the acquisition
system.  If an SpObs contains more than a single observation (eg from
the use of iterators) the multiple SCUBA ODFs are written but a single
MACRO file is returned.

ASIDE: There is no reason why the translated sequence could not be
returned complete as an array of strings rather than a file name. The
main limitation on this is the OM/QT. The reason it is written to disk
is that the current UKIRT sequencers can only be configured by reading
from disk and not via DRAMA parameters (this has the advantage of
providing debugging facilities).

The location of the directory used to write these files can not be
configured via SOAP for security reasons.

=cut

sub translate {
  my $class = shift;
  my $xml = shift;

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
    # Convert to science program
    my $sp = new OMP::SciProg( XML => $xml );
    $result = OMP::Translator->translate( $sp );
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


=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=cut

1;
