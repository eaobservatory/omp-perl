#!/local/perl/bin/perl -XT

=head1 NAME

msbsrv - MSB Server

=head1 SYNOPSIS

  my $msb = new SOAP::Lite( uri => 'http://www.jach.hawaii.edu/OMP::MSBServer',
                           proxy => 'http://www.whereever.edu/cgi-bin/msbsrv.pl'
                          );

  $sp->storeProgram( $xml, $password );

=head1 DESCRIPTION

This program implements a CGI-based SOAP server publishing the methods
found in the C<OMP::MSBServer> perl class.

=cut

use 5.006;
use warnings;
use strict;

BEGIN { $ENV{OMP_CFG_DIR} = "/jac_sw/omp/msbserver/cfg"; }
BEGIN { $ENV{SYBASE} = "/local/progs/sybase"; }

use lib "/jac_sw/omp/msbserver";
use OMP::MSBServer;

use SOAP::Transport::HTTP;

SOAP::Transport::HTTP::CGI->dispatch_to("OMP::MSBServer")
  ->options({compress_threshold=>500})
  ->handle;


=head1 INSTALLATION

Copy this program into the CGI directory on your web server. Usually
the MSB server is installed on an internal web server to prevent
public access to MSB status.

=head1 SEE ALSO

L<OMP::MSBServer>

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

