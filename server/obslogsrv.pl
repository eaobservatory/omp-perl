#!/local/perl/bin/perl -XT

=head1 NAME

obslogsrv - Obslog Comment Server

=head1 SYNOPSIS

  my $sp = new SOAP::Lite( uri => 'http://www.jach.hawaii.edu/OMP::ObslogServer',
                           proxy => 'http://www.whereever.edu/cgi-bin/obslogsrv.pl'
                          );

  $sp->addObslogComment( $userid, $password, $obsid, $commentstatus, $commenttext );

=head1 DESCRIPTION

This program implements a CGI-based SOAP server publishing the methods
found in the C<OMP::ObslogServer> perl class.

=cut

use 5.006;
use warnings;
use strict;

BEGIN { $ENV{OMP_CFG_DIR} = "/jac_sw/omp/msbserver/cfg"; }
BEGIN { $ENV{SYBASE} = "/local/progs/sybase"; }

use lib "/jac_sw/omp/msbserver";
use OMP::ObslogServer;

use SOAP::Transport::HTTP;

SOAP::Transport::HTTP::CGI->dispatch_to("OMP::ObslogServer")
  ->options({compress_threshold=>500})
  ->handle;

=head1 INSTALLATION

Copy this program into the CGI directory on your web server.

=head1 SEE ALSO

L<OMP::ObslogServer>

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2011 Science and Technology Facilities Council.
Copyright (C) 2001 Particle Physics and Astronomy Research Council.
All Rights Reserved.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 3 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful,but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc., 59 Temple
Place,Suite 330, Boston, MA  02111-1307, USA

=cut

