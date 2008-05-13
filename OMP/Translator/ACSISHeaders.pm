package OMP::Translator::ACSISHeaders;

=head1 NAME

OMP::Translator::ACSISHeaders - Derived header configuration for SCUBA-2

=head1 SYNOPSIS

  use OMP::Translator::ACSISHeaders;
  $msbid = OMP::Translator::ACSISHeaders->getMSBID($cfg, %info );

=head1 DESCRIPTION

This class contains ACSIS specific header configurations. Class methods
are invoked from the JCMT translator.

Some header values are determined through the invocation of methods
specified in the header template XML. These methods are flagged by
using the DERIVED specifier with a task name of TRANSLATOR.

The following methods are in the OMP::Translator::JCMTHeaders
namespace. They are all given the observation summary hash as argument
and the current Config object, and they return the value that should
be used in the header.

  $value = OMP::Translator::ACSISHeaders->getProject( $cfg, %info );

An empty string will be recognized as a true UNDEF header value. Returning
undef is an error.

=cut

use 5.006;
use strict;
use warnings;
use Carp;
use Data::Dumper;

use base qw/ OMP::Translator::JCMTHeaders /;

=head1 HELPER METHODS

=over 4

=item B<default_project>

Returns default E&C project.

=cut

sub default_project {
  return "EC19";
}

=head1 TRANSLATION METHODS

=over 4

=back

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

Copyright (C) 2007-2008 Science and Technology Facilities Council.
Copyright 2003-2007 Particle Physics and Astronomy Research Council.
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
