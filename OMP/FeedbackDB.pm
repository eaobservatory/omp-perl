package OMP::FeedbackDB;

=head1 NAME

OMP::FeedbackDB - Manipulate the feedback database

=head1 SYNOPSIS

  $db = new OMP::FeedbackDB( ProjectID => $projectid,
			     Password => $password,
			     DB => $dbconnection );

  $db->addComment( $comment );
  $db->getComments( );


=head1 DESCRIPTION

This class manipulates information in the feedback table.  It is the
only interface to the database tables. The table should not be
accessed directly to avoid loss of data integrity.


=cut

use 5.006;
use strict;
use warnings;
use Carp;
use Time::Piece;
our $VERSION = (qw$ Revision: 1.2 $ )[1];

use OMP::Project;
use OMP::ProjDB;
use OMP::Constants;
use OMP::Error;

use Net::SMTP;

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

  # Verify the password
  my $projdb = new OMP::ProjDB( ProjectID => $self->projectid,
			        DB => $self->db );

  throw OMP::Error::Authentication("Supplied password for project " .$self->projectid )
    unless $projdb->verifyPassword( $self->password );

  # Get the comments
  my $comment = $self->_fetch_comments( $amount, $showhidden );
}

=item B<addComment>

Adds a comment to the database.  Takes a hash reference containing the
comment and all of its details. An (optional) second argument can be
used to disable transaction management (important if you are calling
this method from some OMP code that is already in a transaction).  A
true value will disable transactions.  This method also mails the comment
depending on its status.

  $db->addComment( $comment, [ $notrans ] );

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
  my $self = shift;
  my $comment = shift;
  my $notrans = shift;

  throw OMP::Error::BadArgs( "Comment was not a hash reference" )
    unless UNIVERSAL::isa($comment, "HASH");

  my $t = gmtime;
  my %defaults = ( subject => 'none',
		   date => $t->strftime("%b %e %Y %T"),
		   program => 'unspecified',
		   sourceinfo => 'unspecified',
		   status => 1, );

  # Override defaults
  $comment = {%defaults, %$comment};

  # Check for required fields
  for (qw/ author text /) {
    throw OMP::Error::BadArgs("$_ was not specified")
      unless $comment->{$_};
  }

  # Check that the project actually exists
  my $projdb = new OMP::ProjDB( ProjectID => $self->projectid,
                                DB => $self->db, );

  $projdb->verifyProject()
    or throw OMP::Error::UnknownProject("Project " .$self->projectid. " not known.");

  # We need to think carefully about transaction management

  # Begin transaction
  unless ($notrans) {
    $self->_db_begin_trans;
    $self->_dblock;
  }

  # Store comment in the database
  $self->_store_comment( $comment );

  # End transaction
  unless ($notrans) {
    $self->_dbunlock;
    $self->_db_commit_trans;
  }

  # Mail the comment to interested parties
  ($comment->{status} == OMP__FB_IMPORTANT) and
    $self->_mail_comment_important( $self->projectid, $comment );

  ($comment->{status} == OMP__FB_INFO) and
    $self->_mail_comment_info( $self->projectid, $comment );

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
  my $comment = shift;


  my $dbh = $self->_dbhandle;
  throw OMP::Error::DBError("Database handle not valid") unless defined $dbh;

  my $projectid = $self->projectid;

  my @values = @$comment{ 'author',
			  'date',
			  'subject',
			  'program',
			  'sourceinfo',
			  'status',
			  'text', };

  # Store the data
  # Since a text field will [oddly] only store 65536 bytes we will use
  # writetext to insert the text field.  But first a string will be
  # inserted in the text field so we can search on it before replacing
  # it with the proper text.

  my $key = "pwned!1"; # insert this into the text field for now
                       # then search on it when we do the writetext

  my $sql = "insert into $FBTABLE values (?,?,?,?,?,?,?,'$key')";
  $dbh->do( $sql, undef, $projectid, @values[0..5] ) or
    throw OMP::Error::DBError("Insert failed: " .$dbh->errstr);

  # Now replace the text using writetext
  $dbh->do("declare \@val varbinary(16)
select \@val = textptr(text) from $FBTABLE where text like \"$key\"
writetext $FBTABLE.text \@val '$values[-1]'")
    or throw OMP::Error::DBError("Error inserting comment into database: ". $dbh->errstr);

}

=item B<_mail_comment>

Mail the comment to the specified addresses.

  $db->_mail_comment( $comment, \@addresslist );

First argument should be a hash reference.

=cut

sub _mail_comment {
  my $self = shift;
  my $comment = shift;
  my $addrlist = shift;

  # Set up the mail
  my $smtp = new Net::SMTP('mailhost', Timeout => 30);

  $smtp->mail("omp-feedback-system")
    or throw OMP::Error::FatalError("Error constructing mail message\n");
  $smtp->to(@$addrlist)
    or throw OMP::Error::FatalError("Error constructing mail message\n");
  $smtp->data()
    or throw OMP::Error::FatalError("Error constructing mail message\n");

  # Mail headers
  $smtp->datasend("To: " .join(",",@$addrlist)."\n")
    or throw OMP::Error::FatalError("Error constructing mail message\n");
  $smtp->datasend("Reply-To: omp_group\@jach.hawaii.edu\n")
    or throw OMP::Error::FatalError("Error constructing mail message\n");
  $smtp->datasend("Subject: New feedback comment for project " . $self->projectid."\n")
    or throw OMP::Error::FatalError("Error constructing mail message\n");
  $smtp->datasend("\n")
    or throw OMP::Error::FatalError("Error constructing mail message\n");

  # Mail message
  my $msg = "\nAuthor: $comment->{author}\n" .
            "Subject: $comment->{subject}\n\n" .
	    "$comment->{text}\n";

  $smtp->datasend($msg)
    or throw OMP::Error::FatalError("Error constructing mail message\n");

  # Send message
  $smtp->dataend()
    or throw OMP::Error::FatalError("Error constructing mail message\n");
  $smtp->quit
    or throw OMP::Error::FatalError("Error constructing mail message\n");
}

=item B<_mail_comment_important>

Will send the email to PI, COI and support emails.

  $db->_mail_comment_important( $projectid, $comment );

=cut

sub _mail_comment_important {
  my $self = shift;
  my $projectid = shift;
  my $comment = shift;

  my $proj = new OMP::Project( ProjectID => $projectid);

  my @email = $proj->contacts;
  $self->_mail_comment( $comment, \@email );
}

=item B<_mail_comment_info>

Will send the message to support emails

  $db->_mail_comment_info( $projectid, $comment );

=cut

sub _mail_comment_info {
  my $self = shift;
  my $projectid = shift;
  my $comment = shift;

  # Get a ProjDB object so we can get info from the database
  my $projdb = new OMP::ProjDB( ProjectID => $projectid,
				DB => $self->db,
			      );

  # This is an internal method that removes password
  # verification. Since comments are not meant to need password
  # to be added we can not use $projdb->projectDetails [unless
  # we specfy the administrator password here]
  my $proj = $projdb->_get_project_row;

  my @email = $proj->piemail;

  $self->_mail_comment( $comment, \@email );
}

=cut

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
  # Use convert() in select statement to get seconds back with the date field.
  my $sql = "select author, commid, convert(char(32), date, 109) as 'date', program, projectid, sourceinfo, status, subject, text from $FBTABLE where projectid = \"$projectid\"";

  my $ref = $dbh->selectall_arrayref( $sql, { Columns=>{} }) or
    throw OMP::Error::DBError("Select Failed: " .$dbh->errstr);

  if (wantarray) {
    return @$ref;
  } else {
    return $ref;
  }
}

=back

=head1 SEE ALSO

This class inherits from C<OMP::BaseDB>.

For related classes see C<OMP::MSBDB> and C<OMP::ProjDB>.

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research
Council.  All Rights Reserved.

=head1 AUTHORS

Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>
Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=cut

1;
