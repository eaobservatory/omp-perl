package OMP::FeedbackDB;

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
our $VERSION = (qw$ Revision: 1.2 $ )[1];

use OMP::Error;

use base qw/ OMP::BaseDB /;

# This is picked up by OMP::MSBDB
our $FBTABLE = "ompfeedback";

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

Create a new instance of an C<OMP::FeedbackDB> object.

  $db = new OMP::FeedbackDB( ProjectID => $project,
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

=item B<verifyPassword>

Verify that the supplied plain text password matches the password
stored in the project database.

  $verified = 1 if $db->verifyPassword( $plain_password );

Returns true if the passwords match.

=cut

sub verifyPassword {
  my $self = shift;
  my $password = shift;

  # Retrieve the contents of the table
  my $project = $self->_get_project_row();

  # Now verify the passwords
  return $self->_verify_password( $password, $project->password);

}

=item B<addComment>

Note that there are no arguments and no return values. It either
succeeds or fails.

=cut

sub addComment {
  my $self = shift;
  my $comment = shift;

  throw OMP::Error::BadArgs( "Comment was not a hash reference" )
    unless UNIVERSAL::isa($comment, "HASH");

  # We need to think carefully about transaction management

  # Begin transaction
  $self->_db_begin_trans;
  $self->_dblock;

  # Store comment in the database
  $self->_store_comment( $comment );

  # End transaction
  $self->_dbunlock;
  $self->_db_commit_trans;

  # Mail the comment to interested parties
  $self->_mail_comment( $comment );

  return;
}


=back

=head2 Internal Methods

=over 4

=item B<_store_comment>

=cut

sub _store_comment {


}

=item B<_mail_comment>

=cut

sub _mail_comment {

}


=back

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research
Council.  All Rights Reserved.

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=cut

1;
