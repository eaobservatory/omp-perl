#!/local/perl/bin/perl -XT

=head1 NAME

spsrv - Science Program Server

=head1 SYNOPSIS

  my $sp = new SOAP::Lite( uri => 'http://www.jach.hawaii.edu/OMP::SpServer',
                           proxy => 'http://www.whereever.edu/cgi-bin/spsrv.pl'
                          );

  $sp->storeProgram( $xml, $password );

=head1 DESCRIPTION

This program implements a CGI-based SOAP server publishing the methods
found in the C<OMP::SpServer> perl class.

=cut

use 5.006;
use warnings;
use strict;

BEGIN { $ENV{OMP_CFG_DIR} = "/jac_sw/omp/msbserver/cfg"; }
BEGIN { $ENV{SYBASE} = "/local/progs/sybase"; }

use lib "/jac_sw/omp/msbserver";
use OMP::SpServer;

use SOAP::Transport::HTTP;

SOAP::Transport::HTTP::CGI->dispatch_to("OMP::SpServer")
  ->options({compress_threshold=>500})
  ->handle;

=head1 INSTALLATION

Copy this program into the CGI directory on your web server.

=head1 SEE ALSO

L<OMP::SpServer>

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

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

