package OMP::ProjDB;

=head1 NAME

OMP::ProjDB - Manipulate the project database

=head1 SYNOPSIS

  $projdb = new OMP::ProjDB( ProjectID => $projectid,
			     DB => $dbconnection );

  $projdb->issuePassword();


=head1 DESCRIPTION

This class manipulates information in the project database.  It is the
only interface to the database tables. The tables should not be
accessed by directly to avoid loss of data integrity.


=cut

use 5.006;
use strict;
use warnings;
use Carp;
our $VERSION = (qw$Revision$)[1];

use OMP::Error;
use OMP::Project;

use base qw/ OMP::BaseDB /;

# This is picked up by OMP::MSBDB
our $PROJTABLE = "ompproj";

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

Create a new instance of an C<OMP::ProjDB> object.

  $db = new OMP::ProjDB( ProjectID => $project,
                         DB => $connection);

If supplied, the database connection object must be of type
C<OMP::DBbackend>.  It is not accepted if that is not the case.
(but no error is raised - this is probably a bug).

=cut

# Use base class constructor

=back

=head2 Accessor Methods

=over 4



=back

=head2 General Methods

=over 4

=item B<summary>


=cut

sub summary {
  my $self = shift;

}

=back

=head1 COPYRIGHT

Copyright (C) 2001 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=cut

1;
