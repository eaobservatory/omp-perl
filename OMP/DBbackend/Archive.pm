package OMP::DBbackend::Archive;

=head1 NAME

OMP::DBbackend::Archive - Database connection to JAC data archives

=head1 SYNOPSIS

  use OMP::DBbackend::Archive;

  $connection = new OMP::DBbackend::Archive;

  $connection->begin_trans();
  $connection->commit_trans();

=head1 DESCRIPTION

Subclass of C<OMP::DBbackend> that knows how to connect to the
JAC data archives. Most methods are inherited from the base class.

This class can be used for UKIRT and JCMT database access since the
C<OMP::ArcQuery> class knows which internal database to access.

=cut

use 5.006;
use strict;
use warnings;

use OMP::Error qw/ :try /;

use base qw/ OMP::DBbackend /;


our $VERSION = (qw$Revision$)[1];

=head1 METHODS

=head2 Connections Details

=over 4

=item B<loginhash>

This class method returns the information required to connect to the
database. The details are returned in a hash with the following
keys:

  server  =>  Database server (e.g. SYB_*)
  database=>  The database to use for the transaction
  user    =>  database login name
  password=>  password for user

This is a class method so that it can easily be subclassed.

  %details = OMP::DBbackend->loginhash;

The following environment variables are recognised to override
these values:

  OMP_ARCDBSERVER - the server to use

In the future this method may well read the details from a config
file rather than hard-wiring the values in the module.

=cut

sub loginhash {
  my $self = shift;

  # Uses a dummy value for database since the query class
  # will choose the correct one.

  my %details = (
		 driver   => 'Sybase',
		 server   => "SYB_LUU",
		 database => "ukirt",
		 user     => "staff",
		 password => "pohoiki",
		);

  # possible override
  if ($details{driver} eq 'Sybase') {
    $details{server} = $ENV{OMP_ARCDBSERVER}
      if (exists $ENV{OMP_ARCDBSERVER} and defined $ENV{OMP_ARCDBSERVER});
  }

  return %details;

}

=back

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research
Council.  All Rights Reserved.

=cut

1;


