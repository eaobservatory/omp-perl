package OMP::BaseDB;

=head1 NAME

OMP::BaseDB - Base class for OMP database manipulation

=head1 SYNOPSIS

  $db->_begin_trans;

  $db->_commit_trans;


=head1 DESCRIPTION

This class has all the generic methods required by the OMP to
deal with database transactions of all kinds that are shared
between subclasses (ie nothing that is different between science
program database and project database).

=cut


use 5.006;
use strict;
use warnings;
use Carp;

# OMP Dependencies
use OMP::Error;
use OMP::Constants qw/ :fb /;

use Net::SMTP;

use Net::Domain qw/ hostfqdn /;
use Net::hostent qw/ gethost /;

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

Base class for constructing a new instance of a OMP DB connectivity
class.


  $db = new OMP::BasDB( ProjectID => $project,
			Password  => $passwd
			DB => $connection,
		      );

See C<OMP::ProjDB> and C<OMP::MSBDB> for more details on the
use of these arguments and for further keys.

If supplied, the database connection object must be of type
C<OMP::DBbackend>.  It is not accepted if that is not the case.
(but no error is raised - this is probably a bug).

=cut

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;

  # Read the arguments
  my %args;
  %args = @_ if @_;

  my $db = {
	    InTrans => 0,
	    Locked => 0,
	    Password => undef,
	    ProjectID => undef,
	    DB => undef,
	   };

  # create the object (else we cant use accessor methods)
  my $object = bless $db, $class;

  # Populate the object by invoking the accessor methods
  # Do this so that the values can be processed in a standard
  # manner. Note that the keys are directly related to the accessor
  # method name
  for (qw/Password ProjectID/) {
    my $method = lc($_);
    $object->$method( $args{$_} ) if exists $args{$_};
  }

  # Check the DB handle
  $object->_dbhandle( $args{DB} ) if exists $args{DB};

  return $object;
}


=back

=head2 Accessor Methods

=over 4

=item B<projectid>

The project ID associated with this object.

  $pid = $db->projectid;
  $db->projectid( "M01BU53" );

All project IDs are upper-cased automatically.

=cut

sub projectid {
  my $self = shift;
  if (@_) { $self->{ProjectID} = uc(shift); }
  return $self->{ProjectID};
}

=item B<password>

The password associated with this object.

 $passwd = $db->password;
 $db->password( $passwd );

=cut

sub password {
  my $self = shift;
  if (@_) { $self->{Password} = shift; }
  return $self->{Password};
}

=item B<_locked>

Indicate whether the system is currently locked.

  $locked = $db->_locked();
  $db->_locked(1);

=cut

sub _locked {
  my $self = shift;
  if (@_) { $self->{Locked} = shift; }
  return $self->{Locked};
}

=item B<_intrans>

Indicate whether we are in a transaction or not.

  $intrans = $db->_intrans();
  $db->_intrans(1);

=cut

sub _intrans {
  my $self = shift;
  if (@_) { $self->{InTrans} = shift; }
  return $self->{InTrans};
}


=item B<_dbhandle>

Returns database handle associated with this object (the thing used by
C<DBI>).  Returns C<undef> if no connection object is present.

  $dbh = $db->_dbhandle();

Takes a database connection object (C<OMP::DBbackend> as argument in
order to set the state.

  $db->_dbhandle( new OMP::DBbackend );

If the argument is C<undef> the database handle is cleared.

If the method argument is not of the correct type an exception
is thrown.

=cut

sub _dbhandle {
  my $self = shift;
  if (@_) { 
    my $db = shift;
    if (UNIVERSAL::isa($db, "OMP::DBbackend")) {
      $self->{DB} = $db;
    } elsif (!defined $db) {
      $self->{DB} = undef;
    } else {
      throw OMP::Error::FatalError("Attempt to set database handle in OMP::*DB using incorrect class");
    }
  }
  my $db = $self->{DB};
  if (defined $db) {
    return $db->handle;
  } else {
    return undef;
  }
}


=item B<db>

Retrieve the database connection (as an C<OMP::DBbackend> object)
associated with this object.

  $dbobj = $db->db();
  $db->db( new OMP::DBbackend );

=cut

sub db {
  my $self = shift;
  if (@_) { $self->_dbhandle( shift ); }
  return $self->{DB};
}

=back

=head2 DB methods

=over 4

=item B<_db_begin_trans>

Begin a database transaction. This is defined as something that has
to happen in one go or trigger a rollback to reverse it.

If a transaction is already in progress this method returns
immediately.

=cut

sub _db_begin_trans {
  my $self = shift;
  return if $self->_intrans;

  my $dbh = $self->_dbhandle or
    throw OMP::Error::DBError("Database handle not valid");

  # Begin a transaction
  $dbh->begin_work
    or throw OMP::Error::DBError("Error in begin_work: $DBI::errstr\n");

#  $dbh->do("BEGIN TRANSACTION")
#    or throw OMP::Error::DBError("Error beginning transaction: $DBI::errstr");
  $self->_intrans(1);
}

=item B<_db_commit_trans>

Commit the transaction. This informs the database that everthing
is okay and that the actions should be finalised.

=cut

sub _db_commit_trans {
  my $self = shift;
  my $dbh = $self->_dbhandle;
  throw OMP::Error::DBError("Database handle not valid") unless defined $dbh;

  if ($self->_intrans) {
    $self->_intrans(0);
    $dbh->commit
      or throw OMP::Error::DBError("Error committing transaction: $DBI::errstr");
#    $dbh->do("COMMIT TRANSACTION");

  }
}

=item B<_db_rollback_trans>

Rollback (ie reverse) the transaction. This should be called if
we detect an error during our transaction.

When called it should probably correct any work completed on the
XML data file.

=cut

sub _db_rollback_trans {
  my $self = shift;

  my $dbh = $self->_dbhandle;
  throw OMP::Error::DBError("Database handle not valid") unless defined $dbh;

  if ($self->_intrans) {
    $self->_intrans(0);
    $dbh->rollback
      or throw OMP::Error::DBError("Error rolling back transaction (ironically): $DBI::errstr");
#    $dbh->do("ROLLBACK TRANSACTION");

  }
}


=item B<_dblock>

Lock the MSB database tables (ompobs and ompmsb but not the project table)
so that they can not be accessed by other processes.

=cut

sub _dblock {
  my $self = shift;
  # Wait for infinite amount of time for lock
  # Needs Sybase 12
#  $dbh->do("LOCK TABLE $MSBTABLE IN EXCLUSIVE MODE WAIT")
#    or throw OMP::Error::DBError("Error locking database: $DBI::errstr");
  $self->_locked(1);
  return;
}

=item B<_dbunlock>

Unlock the system. This will allow access to the database tables and
file system.

For a transaction based database this is a nullop since the lock
is automatically released when the transaction is committed.

=cut

sub _dbunlock {
  my $self = shift;
  if ($self->_locked()) {
    $self->_locked(0);
  }
}

=back

=head2 Feedback system

=over 4

=item B<_notify_feedback_system>

Notify the feedback system using the supplied message.

  $db->_notify_feedback_system( %comment );

Where the comment hash includes the keys supported by the
feedback system (see C<OMP::FeedbackDB>) and usually
consist of:

  author      - the name of the system/person submitting comment
                  Default is to use the current hostname and user
                  (or REMOTE_ADDR and REMOTE_USER if set)

  program     - the program implementing the change (defaults to
                this program [C<$0>])
  sourceinfo  - IP address of computer submitting comment
                Defaults to the current hostname or $REMOTE_ADDR 
                if set.

  subject     - subject of comment (Required)
  text        - the comment itself (HTML) (Required)
  status      - whether to mail out the comment or not. Default
                is not to mail anyone.

=cut

sub _notify_feedback_system {
  my $self = shift;
  my %comment = @_;

  # We have to share the database connection because we have
  # locked out the project table making it impossible for
  # the feedback system to verify the project
  my $fbdb = new OMP::FeedbackDB( ProjectID => $self->projectid,
				  DB => $self->db,
				);

  # text and subject must be present
  throw OMP::Error::FatalError("Feedback message must have subject and text\n")
    unless exists $comment{text} and exists $comment{subject};

  # If the author, program or sourceinfo fields are empty supply them
  # ourselves.
  my ($user, $addr, $email) = $self->_determine_host;
  $comment{author} = $email unless exists $comment{author};
  $comment{sourceinfo} = $addr unless exists $comment{sourceinfo};
  $comment{program} = $0 unless exists $comment{program};
  $comment{status} = OMP__FB_HIDDEN unless exists $comment{status};

  # Disable transactions since we can only have a single
  # transaction at any given time with a single handle
  $fbdb->addComment( { %comment },1);

}


=item B<_mail_information>

Mail some information to some people.

  $db->_mail_information( %details );

Uses C<Net::SMTP> for the mail service so that it can run in a tainted
environment. The argument hash should have the following keys:

 to   - array reference or scalar containing addresses to send mail to
 from - the email address of the sender
 subject - subject of the message
 message  - the actual mail message
 headers - additional mail headers such as Reply-To and Content-Type
           as they would appear in the message. Stored as reference to
           an array [optional]

 $db->_mail_information( to => [qw/blah@somewhere.com blah2@nowhere.com/],
                         from => "me@myself.com",
                         subject => "hello",
                         message => "this is the content\n",
                         headers => [ "Reply-To: you\@yourself.com",
                                      "Content-Type: text/html"],
                       );

Throws an exception on error.

=cut

sub _mail_information {
  my $self = shift;
  my %details = @_;

  # Check that we have the correct keys
  for my $key (qw/ to from subject message /) {
    throw OMP::Error::BadArgs("_mail_information: Key $key is required")
      unless exists $details{$key};
  }

  # Get the address list
  # single scalar or array ref
  my @addr = ( ref $details{'to'} ? @{$details{to}} : $details{to} );

  throw OMP::Error::FatalError("Undefined address")
    unless @addr and defined $addr[0];

  # Set up the mail
  my $smtp = new Net::SMTP('mailhost', Timeout => 30);

  $smtp->mail( $details{from} )
    or throw OMP::Error::FatalError("Error sending 'from' information\n");
  $smtp->to(@addr)
    or throw OMP::Error::FatalError("Error constructing 'to' information\n");
  $smtp->data()
    or throw OMP::Error::FatalError("Error beginning data segment of message\n");

  # Mail headers
  if (exists $details{headers}) {
    for my $hdr (@{ $details{headers} }) {
      $smtp->datasend("$hdr\n")
	or throw OMP::Error::FatalError("Error adding '$hdr' header\n");
    }
  }

  # To and subject header are special
  $smtp->datasend("To: " .join(",",@addr)."\n")
    or throw OMP::Error::FatalError("Error adding 'To' header\n");
  $smtp->datasend("Subject: $details{subject}\n")
    or throw OMP::Error::FatalError("Error adding 'subject' header\n");
  $smtp->datasend("\n")
    or throw OMP::Error::FatalError("Error sending header delimiter\n");


  # Actual message
  $smtp->datasend($details{message})
    or throw OMP::Error::FatalError("Error adding mail message\n");

  # Send message
  $smtp->dataend()
    or throw OMP::Error::FatalError("Error finalizing mail message\n");
  $smtp->quit
    or throw OMP::Error::FatalError("Error sending mail message\n");

}

=back

=head2 Verification

=over 4

=item B<_verify_administrator_password>

Compare the password stored in the object (obtainable using the
C<password> method) with the administrator password. Throw an
exception if the two do not match. This safeguard is used to prevent
people from modifying the contents of the project database without
having permission.

Note that the password stored in the object is assumed to be unencrypted.

=cut

sub _verify_administrator_password {
  my $self = shift;
  my $password = $self->password;

  # The encrypted admin password
  # At some point we'll pick this up from somewhere else.
  my $admin = "Fgq1aNqFqOvsg";

  # Encrypt the supplied password using the admin password as salt
  my $encrypted = crypt($password, $admin);

  # A bit simplistic at the present time
  throw OMP::Error::Authentication("Failed to match administrator password\n")
    unless ($encrypted eq $admin);

  return;
}

=item B<_determine_host>

Determine the host and user name of the person either running this task. This
is either determined by using the CGI environment variables (REMOTE_ADDR and
REMOTE_USER) or, if they are not set, the current host running the program
and the associated user name.

  ($user, $host, $email) = $db->_determine_host;

The user name is not always available (especially if running from CGI).
The email address is simply determined as C<$user@$host> and is identical
to the host name if no user name is determined.

=cut

sub _determine_host {
  my $self = shift;

  # Try and work out who is making the request
  my ($user, $addr);

  if (exists $ENV{REMOTE_ADDR}) {
    # We are being called from a CGI context
    my $ip = $ENV{REMOTE_ADDR};

    # Try to translate number to name
    $addr = gethost( $ip );
    $addr = (defined $addr and ref $addr ? $addr->name : '' );

    # User name (only set if they have logged in)
    $user = (exists $ENV{REMOTE_USER} ? $ENV{REMOTE_USER} : '' );

  } else {
    # localhost
    $addr = hostfqdn;
    $user = (exists $ENV{USER} ? $ENV{USER} : '' );

  }

  # Build a pseudo email address
  my $email = '';
  $email = $addr if $addr;
  $email = $user . "@" . $email if $user;

  # Replce space with _
  $email =~ s/\s+/_/g;

  return ($user, $addr, $email);
}


=back

=head1 SEE ALSO

For related classes see C<OMP::MSBDB>, C<OMP::ProjDB> and
C<OMP::FeedbackDB>.

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
