package OMP::DBServer;

=head1 NAME

OMP::DBServer - Base class for servers that talk to the OMP database

=head1 SYNOPSIS

  use base qw/ OMP::DBServer /;

  $db = $class->dbConnection;

=head1 DESCRIPTION

This class should be used as a base class for handling generic
method relating to the OMP database required by the OMP servers.

Currently, this just provides a method for providing the database
connection object.

=cut

use 5.006;
use strict;
use warnings;

use OMP::DBbackend;

our $VERSION = (qw$Revision$)[1];

=head1 METHODS

=over 4

=item B<dbConnection>

The database connection object. This is called by all the methods
that use a C<OMP::MSBDB> object. The connection is automatically
instantiated the first time it is requested.

Returns a connection object of type C<OMP::DBbackend>.

=cut

{
 # Hide the lexical variable
  my $db;
  sub dbConnection {
    my $class = shift;
    if (defined $db) {
      return $db;
    } else {
      $db = new OMP::DBbackend;
      return $db;
    }
  }
}

=back

=head1 SEE ALSO

L<OMP::DBbackend>, L<OMP::MSBServer>, L<OMP::SpServer>.

=head1 NOTES

This is probably a design flaw but as the system has evolved the 
caching of the database connection has worked for the generic
server interfaces but all the DB classes can be independently 
instantiated with their own DB connection object which subverts
the caching since OMP::DBbackend is called directly. This is partly
my fault because I did not publicise the

   OMP::DBServer->dbConnection()

interface enough and everyone used the DBbackend connection. Too
late to change this now so OMP::DBbackend now also does connection
caching. If someone is feeling really keen they could remove 
all the DBbackend references from the code....

=head1 COPYRIGHT

Copyright (C) 2001-2003 Particle Physics and Astronomy Research Council.
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


