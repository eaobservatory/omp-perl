package OMP::FaultDB;

=head1 NAME

OMP::FaultDB - Fault database manipulation

=head1 SYNOPSIS

  use OMP::FaultDB;
  $db = new OMP::FaultDB( DB => new OMP::DBbackend );

  $faultid = $db->fileFault( $fault );
  $db->respondFault( $faultid, $response );
  $db->closeFault( $faultid );
  $fault = $db->getFault( $faultid );
  @faults = $db->queryFault( $query );

=head1 DESCRIPTION

The C<FaultDB> class is used to manipulate the fault database. It is
designed to work with faults from multiple systems at once. The
database consists of two tables: one for general fault information
and one for the text associated with the fault report.

=cut

use 5.006;
use warnings;
use strict;
use OMP::Fault;

our $VERSION = (qw$Revision$)[1];

our $FAULTTABLE = "ompfault";
our $FAULTBODYTABLE = "ompfaultbody";


=head1 METHODS

=head2 Public Methods

=over 4


=item B<fileFault>

Create a new fault and return the new fault ID. The fault ID
is unique and can be used to address the fault in future.

  $id = $db->fileFault( $fault );

The details associated with the fault are supplied in the form
of a C<OMP::Fault> object.

=cut

sub fileFault {
  my $self = shift;
  my $fault = shift;


}

=back

=head2 Internal Methods

=over 4

=item B<blah>

=back

=head1 SEE ALSO

This class inherits from C<OMP::BaseDB>.

For related classes see C<OMP::ProjDB> and C<OMP::FeedbackDB>.

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
