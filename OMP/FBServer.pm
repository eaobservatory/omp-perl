package OMP::FBServer;

=head1 NAME

OMP::FBServer - Feedback information Server class

=head1 SYNOPSIS

  OMP::FBServer->addComment( $project, $commentHash );
  OMP::FBServer->getComments( $project, $password );

=head1 DESCRIPTION

This class provides the public server interface for the OMP feedback
information database server. The interface is specified in document
OMP/SN/005.

This class is intended for use as a stateless server. State is
maintained in external databases. All methods are class methods.

=cut

use strict;
use warnings;
use Carp;

# OMP dependencies
use OMP::Error qw/ :try /;

# Inherit server specific class
use base qw/OMP::SOAPServer OMP::DBServer/;

our $VERSION = (qw$Revision$)[1];

=head1 METHODS

=over 4

=item B<addComment>

Kynan puts in some stuff here

Does it send an email to the PI automatically?

   OMP::FBServer->addComment( $project, $commentHash );

   OMP::FBServer::addComment( OMP::FBServer, $project, $commentHash );

=cut

sub addComments {
  my $class = shift;
  my $projectid = shift;
  my $comment = shift;

  my $E;
  try {

    my $db = new OMP::FBDB(
			   ProjectID => $projectid,
			   DB => $class->dbConnection,
			  );

    $db->addComment( $comment );

  } catch OMP::Error with {
    # Just catch OMP::Error exceptions
    # Server infrastructure should catch everything else
    $E = shift;

  } otherwise {
    # This is "normal" errors. At the moment treat them like any other
    $E = shift;

  };

  # This has to be outside the catch block else we get
  # a problem where we cant use die (it becomes throw)
  $class->throwException( $E ) if defined $E;

  return 1;
}



=back

=head1 SEE ALSO

OMP document OMP/SN/005.

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=head1 AUTHOR

Kynan Delorey E<lt>kynan@jach.hawaii.eduR<gt>
Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=cut

1;
