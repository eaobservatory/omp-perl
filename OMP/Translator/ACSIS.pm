package OMP::Translator::ACSIS;

=head1 NAME

OMP::Translator::ACSIS - translate ACSIS heterodyne observations to Configure XML

=head1 SYNOPSIS

  use OMP::Translator::ACSIS;
  $config = OMP::Translator::ACSIS->translate( $sp );

=head1 DESCRIPTION

Convert ACSIS MSB into a form suitable for observing. This means
XML suitable for the OCS CONFIGURE action.

=cut

use 5.006;
use strict;
use warnings;
use Carp;

use OMP::Error;

use base qw/ OMP::Translator /;

# Unix directory for writing configs
our $TRANS_DIR = "/observe/ompodf";

# Debugging messages
our $DEBUG = 0;

=head1 METHODS

=over 4

=item B<translate>

Convert the science program object (C<OMP::SciProg>) into
a observing sequence understood by the instrument data acquisition
system (Configure XML).

  $xml = OMP::Translate->translate( $sp );
  $data = OMP::Translate->translate( $sp, 1);
  @data = OMP::Translate->translate( $sp, 1);

By default returns the name of a XML file. If the optional second
argument is true, returns the contents of the XML as a single string.

Backup files are also written that are timestamped to prevent
overwriting.  An accuracy of 1 milli second is used in forming the
unique names.

=cut

sub translate {
  my $self = shift;
  my $sp = shift;
  my $asdata = shift;

  # Project
  my $projectid = $sp->projectID;

  croak "Not yet\n";

  # Need to put DTD in here
  my $xml = "<OCS_CONFIG>\n";

  # First, write the TCS_CONFIG

  # BASE and REFERENCE positions

  # Then obsArea

  # FRONTEND_CONFIG

  # ACSIS_CONFIG

  # HEADER_CONFIG

  # End
  $xml .= "</OCS_CONFIG>\n";

  # Return or write
  if (!$asdata) {
    # Return XML as a string
    return $xml;
  } else {
    # Write the XML to a file
  }

}

=item B<debug>

Method to enable and disable global debugging state.

  OMP::Translator::DAS->debug( 1 );

=cut

sub debug {
  my $class = shift;
  my $state = shift;

  $DEBUG = ($state ? 1 : 0 );
}

=item B<transdir>

Override the translation directory.

  OMP::Translator::DAS->transdir( $dir );

Note that this does not override the VAX name used for processing
inside files since that can not be determined directly from
this directory name.

=cut

sub transdir {
  my $class = shift;
  my $dir = shift;

  $TRANS_DIR = $dir;
}


=back

=head1 NOTES

Usually called indirectly from L<OMP::Translator|OMP::Translator>.

=head1 CONFIGURATION XML

The format of the configuration XML is outlined in JAC document
OCS/ICD/001.

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

Copyright 2003-2004 Particle Physics and Astronomy Research Council.
All Rights Reserved.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful,but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc., 59 Temple
Place,Suite 330, Boston, MA  02111-1307, USA

=cut

1;
