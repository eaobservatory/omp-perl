package OMP::FaultServer;

=head1 NAME

OMP::FaultServer - Fault information Server class

=head1 SYNOPSIS

  OMP::FaultServer->fileFault( $fault );
  OMP::FaultServer->respondFault( $id, $reponse );

=head1 DESCRIPTION

This class provides the public server interface for the OMP Fault system.

This class is intended for use as a stateless server. State is
maintained in external databases. All methods are class methods.

=cut

use strict;
use warnings;
use Carp;

# OMP dependencies
use OMP::FaultDB;
use OMP::Fault;
use OMP::FaultQuery;
use OMP::Error qw/ :try /;

# Inherit server specific class
use base qw/OMP::SOAPServer OMP::DBServer/;

our $VERSION = (qw$Revision$)[1];

=head1 METHODS

=over 4

=item B<fileFault>

  $newid = OMP::FaultServer->fileFault( $fault );

For now the argument is an C<OMP::Fault> object.

=cut

sub fileFault {
  my $class = shift;
  my $fault = shift;

  my $newid;
  my $E;
  try {

    my $db = new OMP::FaultDB(
			     DB => $class->dbConnection,
			    );

    $newid = $db->fileFault($fault);

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

  return $newid;
}

=item B<respondFault>

Given a fault ID and a response object (C<OMP::Fault::Response>),
store the response in the database.

  OMP::FaultServer->respondFault($faultid, $response);

A more SOAP friendly interface could be developed that will accept the
fault user and fault body as separate arguments (with optional date).

=cut

sub respondFault {
  my $class = shift;
  my $faultid = shift;
  my $response = shift;

  my $E;
  try {

    my $db = new OMP::FaultDB(
			     DB => $class->dbConnection,
			    );

    $db->respondFault($faultid, $response);

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

  return;
}

=item B<closeFault>

Close the specified fault.

  OMP::FaultServer->closeFault($faultid);

=cut

sub closeFault {
  my $class = shift;
  my $faultid = shift;

  my $E;
  try {

    my $db = new OMP::FaultDB(
			     DB => $class->dbConnection,
			    );

    $db->closeFault($faultid);

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

  return;
}

=item B<updateFault>

Update details for a fault.  If a second argument (either an C<OMP::User>
object or a string identifying the user who made the update) is included
an email will be sent to the fault owner notifying them of the update.

  OMP::FaultServer->updateFault($fault [, $user ]);

Argument should be supplied as an C<OMP::Fault> object.

=cut

sub updateFault {
  my $class = shift;
  my $fault = shift;
  my $user = shift;

  my $E;
  try {

    my $db = new OMP::FaultDB( DB => $class->dbConnection, );

    # Let the lower level method check the argument
    $db->updateFault($fault, $user);

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

  return;

}
=item B<updateResponse>

Update details for a fault.  If a second argument (either an C<OMP::User>
object or a string identifying the user who made the update) is included
an email will be sent to the fault owner notifying them of the update.

  OMP::FaultServer->updateResponse($faultid, $response);

Argument should be supplied as an C<OMP::Fault> object.

=cut

sub updateResponse {
  my $class = shift;
  my $faultid = shift;
  my $response = shift;

  my $E;
  try {

    my $db = new OMP::FaultDB( DB => $class->dbConnection, );

    # Let the lower level method check the argument
    $db->updateResponse($faultid, $response);

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

  return;

}


=item B<getFault>

Get the specified fault.

  $fault = OMP::FaultServer->getFault($faultid);

This is not SOAP friendly. The fault is returned as an C<OMP::Fault>
object.

=cut

sub getFault {
  my $class = shift;
  my $faultid = shift;

  my $fault;
  my $E;
  try {

    my $db = new OMP::FaultDB(
			     DB => $class->dbConnection,
			    );

    $fault = $db->getFault($faultid);

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

  return $fault;
}

=item B<queryFaults>

Query the fault database using an XML representation of the query.

  $faults = OMP::FaultServer->queryFaults($faultid,
                                        $format );

See C<OMP::FaultQuery> for more details on the format of the XML query.
A typical query could be:

  <FaultQuery>
    <entity>UFTI</entity>
    <author>AJA</author>
  </FaultQuery>

This would return all faults involving UFTI that were filed or responded
to by AJA.

The format of the returned data is controlled by the last argument.
This can either be "object" (a reference to an array containing
C<OMP::Fault> objects), "hash" (reference to an array of hashes), or
"xml" (return data as XML document). The format of the XML is the same
as for C<projectDetails> except that a wrapper element of
C<E<lt>OMPFaultsE<gt>> surrounds the core data. I<Currently only
"object" is implemented>.


=cut

sub queryFaults {
  my $class = shift;
  my $xmlquery = shift;
  my $mode = lc( shift );
  $mode = "object" unless $mode;

  my @faults;
  my $E;
  try {

    my $query = new OMP::FaultQuery( XML => $xmlquery );

    my $db = new OMP::FaultDB(
			     DB => $class->dbConnection,
			    );

    @faults = $db->queryFaults( $query );

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

  return \@faults;
}


=back

=head1 SEE ALSO

L<OMP::ProjServer>, L<OMP::Fault>, L<OMP::FaultDB>.

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


=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=cut

1;
