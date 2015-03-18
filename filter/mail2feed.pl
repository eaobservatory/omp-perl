#!/local/perl/bin/perl -XT

BEGIN {
  $ENV{LANG}   = "C";
  $ENV{SYBASE} = "/local/progs/sybase";
  $ENV{PATH}   = "/bin:/usr/bin:/usr/local/bin";
  $ENV{'LD_LIBRARY_PATH'} = "/usr/lib:/usr/lib64:/star64/lib";
}

use strict;
use lib "/jac_sw/omp/msbserver";
use Mail::Audit;

use OMP::FBServer;
use OMP::General;
use OMP::User;
use OMP::UserServer;

our $VERSION = '0.001';

my $mail = new Mail::Audit(
                            loglevel => 4,
                            log => "/tmp/omp-mailaudit.log",
                          );

# See if this was an automated reply
$mail->ignore("Ignore message because X-Loop header exists") if $mail->get("X-Loop");

# Look for project ID
# Note that the act of searching for the projectid forces the
# project ID to become a header itself.
$mail->reject("Sorry. Could not discern project ID from the subject line.")
  unless projectid( $mail );

# Look for spam
$mail->reject("Sorry. This email looks like spam. Rejecting.")
  if $mail->get("X-Spam-Status") =~ /^Yes/;


# looks like we can accept this
accept_feedback( $mail );


exit;


# Process OMP feedback mail messages
# Accept a message and send it to the feedback system
sub accept_feedback {
  my $audit = shift;

  $audit->log(1 => "Accepting [VERSION=$VERSION]");

  # Get the information we need
  my $from = $audit->get("from");
  my $srcip = (  $from =~ /@(.*)\b/ ? $1 : $from );
  my $subject = $audit->get("subject");
  my $text;

  # Get body of email.
  if ( $audit->is_mime) {
      $text = extract_body( $audit );
  } else {
      $text = join('',@{ $audit->body });
  }

  my $project = $audit->get("projectid");

  chomp($project); # header includes newline

  # Try to guess the author
  my $email = undef;
  my $author_guess = OMP::User->extract_user_from_email( $from, \$email );

  my $author = undef;

  # Attempt to retrive user object from the user DB.
  #
  # Try the email address first, because we now have several OMP
  # users with the same first initial and last name.  Inferring
  # the OMP user ID from the name therefore sometimes identifies
  # the wrong user.  See fault 20140717.002.
  if ($email) {
    my $query = "<UserQuery><email>$email</email></UserQuery>";
    my $users = OMP::UserServer->queryUsers($query, 'object');

    if ($users->[0]) {
      $author = $users->[0];
      $audit->log(1 => "Determined OMP user by email address: [EMAIL=".
                        $author->email."]");
    }
  }

  # If we didn't get an email address or failed to look it up, then
  # try the inferred user ID.
  if ((not $author) and $author_guess) {
    my $userid = $author_guess->userid;

    $author = OMP::UserServer->getUser($userid);
  }

  if ($author) {
    $audit->log(1 => "Determined OMP user: $author [ID=".
                      $author->userid."]");
  } else {
    $audit->log(1 => "Unable to determine OMP user from From address");
  }

  # Need to translate the from address to a valid OMP user id
  # if possible. For now we have to just use undef
  $audit->log(1 => "Sending to feedback system with Project $project");

  # Contact the feedback system
  OMP::FBServer->addComment( $project, {
                                        author => $author,
                                        program => $0,
                                        subject => $subject,
                                        sourceinfo => $srcip,
                                        text => $text,
                                       });

  $audit->log(1 => "Sent to feedback system with Project $project");

  # Exit after delivery if required
  if (!$audit->{noexit}) {
    $audit->log(2 => "Exiting with status ".Mail::Audit::DELIVERED);
    exit Mail::Audit::DELIVERED;
  }

}

# Return the body of an email, and a notation about any removed attachments.
sub extract_body {
    my $entity = shift;
    my @bodytexts = ();

    my $num_parts = $entity->parts;

    # If more than one part, call this routine again.
    if ($num_parts > 0) {
        foreach (0..($num_parts-1)) {
            my $part = $entity->parts($_);
            push @bodytexts, extract_body( $part);
        }
    } else {

        # If in final part, return the body if its a text type.
        my $mime_type = $entity->mime_type;

        if ("$mime_type" =~ 'text') {
            my $bh = $entity->bodyhandle;
            my $text = $bh->as_string;
            push @bodytexts, $text;

        } else {
            push @bodytexts, "One attachment of type [$mime_type] was removed.";
        }
    }

    return join("\n\n", @bodytexts);
}


# Determine the project ID from the subject and
# store it in the mail header
# Return 1 if subject found, else false
sub projectid {
  my $audit = shift;
  my $subject = $audit->get("subject");

  # Attempt to match
  my $pid = OMP::General->extract_projectid( $subject );
  if (defined $pid) {
    $audit->put_header("projectid", $pid);
    $audit->log(1 => "Project from subject: $pid");
    return 1;
  } else {
    $audit->log(1 => "Could not determine project from subject line");
    return 0;
  }

}


__END__
=head1 NAME

mail2feedback.pl - Forward mail message to OMP feedback system

=head1 SYNOPSIS

  cat mailmessage | mail2feedback.pl

=head1 DESCRIPTION

This program reads in mail messages from standard input, determines
the project ID from the subject line and forwards the message to
the OMP feedback system. For MIME mail it attempts to only forward
parts in a text MIME-type.

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2002-2005 Particle Physics and Astronomy Research Council.
All Rights Reserved.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful,but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc., 59 Temple
Place,Suite 330, Boston, MA  02111-1307, USA

=cut

