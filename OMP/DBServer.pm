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

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=cut

1;


