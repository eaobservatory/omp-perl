package OMP::FBServer;

=head1 NAME

OMP::FBServer - Feedback information Server class

=head1 SYNOPSIS

  OMP::FBServer->addComment( $project, $commentHash );
  OMP::FBServer->getComments( $project, $password, $status );

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
use OMP::FeedbackDB;
use OMP::Constants;
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

=over 4

=item Hash reference should contain the following key/value pairs:

=item B<author>

The name of the author of the comment.

=item B<subject>

The subject of the comment.

=item B<program>

The program used to submit the comment.

=item B<sourceinfo>

The IP address of the machine comment is being submitted from.

=item B<text>

The text of the comment (HTML tags are encouraged).

=back

=cut

sub addComment {
  my $class = shift;
  my $projectid = shift;
  my $comment = shift;

  my $E;
  try {

    my $db = new OMP::FeedbackDB( ProjectID => $projectid,
				  DB => $class->dbConnection, );

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
comments.  The third argument should be an array reference containing the
desired status types of the comments to be returned.  Status types are
defined in C<OMP::Constants>.  Final argument is optional and should be
either 'ascending' or 'descending' depending on the order in which you
want the comments to come back.

    OMP::FBServer->getComments( $project, $password, \@status, [$order]);

=cut

sub getComments {
  my $class = shift;
  my $projectid = shift;
  my $password = shift;
  my $status = shift;
  my $order = shift;

  my %args;
  $args{status} = $status;
  $args{order} = $order
    if (defined $order);

  my $commentref;

  my $E;
  try {

    my $db = new OMP::FeedbackDB( ProjectID => $projectid,
				  Password => $password,
                                  DB => $class->dbConnection, );

    $commentref = $db->getComments( %args );

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

  return $commentref;
}

=item B<alterStatus>

Alter the status of a comment, rendering it either hidden or visible.
Requires an admin password. Last argument should be a feedback constant
as defined in C<OMP::Constants>.

Does not return anything, but will throw an error if it fails to alter
the status.

  OMP::FBServer->alterStatus( $commentid, $adminpass, $status );

=cut

sub alterStatus {
  my $class = shift;
  my $commentid = shift;
  my $adminpass = shift;
  my $status = shift;

  my $E;
  try {

    my $db = new OMP::FeedbackDB( Password => $adminpass,
                                  DB => $class->dbConnection, );

    $db->alterStatus( $commentid, $status );

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


=head1 AUTHORS

Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=cut

1;
