package OMP::FBServer;

=head1 NAME

OMP::FBServer - Feedback information Server class

=head1 SYNOPSIS

  OMP::FBServer->addComment( $project, $commentHash );
  OMP::FBServer->getComments( $project, $password );

=head1 DESCRIPTION

This class provides the public server interface for the OMP feedback
information database server. The interface is specified in document
OMP/SN/006.

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

Add a comment to the feedback database for the specified project and email
the comment to the PI and any others who have registered an interest in
the project.

Does not return anything but will throw an error if the comment should fail
to be added to the feedback database.

   OMP::FBServer->addComment( $project, $commentHash );

   OMP::FBServer::addComment( OMP::FBServer, $project, $commentHash );

=cut

sub addComment {
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


=item B<getComments>

Return comments associated with the specified project.  With just the
project ID and password given this method will default to returning all
comments.  If the third argument specifying a number of comments to be
shown (anything less than 0 will return all comments) is given, then the
fourth argument must be included as well.  Fourth argument should be
'true' or 'false' depending on whether or not you want comments with a
status of 0 (effectively hidden) to be returned.

    OMP::FBServer->getComments( $project, $password, $howMany, $showHidden );

=cut

sub getComments {
  my $class = shift;
  my $projectid = shift;
  my $password = shift;
  my $amount = shift;
  my $showhidden = shift;

  my $E;
  try {

    my $db = new OMP::FBDB(
                           ProjectID => $projectid,
                           Password => $password,
                           Amount => $amount,
                           ShowHidden => $showhidden,
                           DB => $class->dbConnection,
                          );

    $db->getComments( $projectid, $password );

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


}

=item B<deleteComment>

Alter the status of a comment, rendering it either hidden or visible.
Requires an admin password. Third argument should be 'true' or 'false'.

Does not return anything, but will throw an error if it fails to alter
the status.

    OMP::FBServer->deleteComment( $project, $commentid, $adminpass, $status );

=cut

sub deleteComment {
  my $class = shift;
  my $projectid = shift;
  my $comment = shift;
  my $password = shift;
  my $status = shift;

  my $E;
  try {

    my $db = new OMP::FBDB(
                           ProjectID => $projectid,
                           CommentID => $comment,
                           Password => $password,
                           Delete => $status,
                          );

    $db->deleteComment( $comment, $password );

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


}

=back

=head1 SEE ALSO

OMP document OMP/SN/006.

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=head1 AUTHORS

Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=cut

1;
