package OMP::DBbackend::JCMTArchive;

=head1 NAME

OMP::DBbackend::JCMTArchive - Database connection to JCMT data archive

=head1 SYNOPSIS

  use OMP::DBbackend::JCMTArchive;

  $connection = new OMP::DBbackend::JCMTArchive;

  $connection->begin_trans();
  $connection->commit_trans();

=head1 DESCRIPTION

Subclass of C<OMP::DBbackend> that knows how to connect to the
JCMT data archive. Most methods are inherited from the base class.

=cut

use 5.006;
use strict;
use warnings;

use base qw/ OMP::DBbackend::UKIRTArchive /;


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

  # Get the parent info
  my %details = $self->SUPER::loginhash();

  # Override the database
  $details{database} = 'jcmt';

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


