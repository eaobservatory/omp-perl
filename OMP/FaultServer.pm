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


=back

=head1 SEE ALSO

L<OMP::ProjServer>, L<OMP::Fault>, L<OMP::FaultDB>.

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=cut

1;
