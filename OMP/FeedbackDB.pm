package OMP::FeedbackDB;

=head1 NAME

OMP::FeedbackDB - Manipulate the feedback database

=head1 SYNOPSIS

  $db = new OMP::feedbackDB( ProjectID => $projectid,
			     Password => $password,
			     DB => $dbconnection );

  $db->addComment( $comment );
  $db->getComments();


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
                             Password => $password,
			     DB => $connection );

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

=item B<getComments>

Returns an array reference containing comments for the project.

  $db->getComments( $password, $amount, $showHidden );

=cut

sub getComments {
  my $self = shift;
  my $amount = shift;
  my $showhidden = shift;

  # Get the comments
  my $commentref = $self->_fetch_comments( $amount, $showhidden );

}

=item B<addComment>

Adds a comment to the database.  Takes a hash reference containing the
comment and all its details as the only argument.

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
  #  $self->_mail_comment( $comment );

  return;
}


=back

=head2 Internal Methods

=over 4

=item B<_store_comment>

Stores a comment in the database.

=cut

sub _store_comment {
  my $self = shift;
  my $ref = shift;

  my $projectid = $self->projectid;
  my @values = @$ref{ 'author',
		      'date',
		      'subject',
		      'program',
		      'sourceinfo',
		      'status',
		      'text', };

  my $dbh = $self->_dbhandle;
  throw OMP::Error::DBError("Database handle not valid") unless defined $dbh;

  # Store the data
  my $sql = "insert into $FBTABLE $projectid , @values";
  $dbh->do( $sql ) or
    throw OMP::Error::DBError("Insert failed");

}

=item B<_mail_comment>

=cut

sub _mail_comment {

}

=item B<_fetch_comments>

Internal method to retrive the comments from the database.  Returns either
a reference or a list depending on what is wanted.

=cut

sub _fetch_comments {
  my $self = shift;
  my $amount = shift;
  my $showhidden = shift;

  my $dbh = $self->_dbhandle;
  throw OMP::Error::DBError("Database handle not valid") unless defined $dbh;

  my $projectid = $self->projectid;

  # Fetch the data
  my $sql = "select * from $FBTABLE where projid = $projectid";
  my $ref = $dbh->selectall_arrayref( $sql, { Columns=>{} });

  throw OMP::Error::UnknownProject( "Unable to retrieve comments for project $projectid" )
    unless @$ref;

  if (wantarray) {
    return @$ref;
  } else {
    return $ref;
  }
}

=back

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research
Council.  All Rights Reserved.

=head1 AUTHORS

Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>
Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=cut

1;
