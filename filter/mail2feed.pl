#!/local/perl/bin/perl -XT

=head1 NAME

mail2feedback.pl - Forward mail message to OMP feedback system

=head1 SYNOPSIS

    cat mailmessage | mail2feedback.pl

=head1 DESCRIPTION

This program reads in mail messages from standard input, determines
the project or fault ID from the subject line and forwards the message to
the OMP feedback system. For MIME mail it attempts to only forward
parts in a text MIME-type.

=over 4

=item B<-help>

Show this message.

=item B<-dry-run> | B<-n>

Do everything except to actually send out mail or touch database.

=back

=cut

use strict;
use FindBin;

BEGIN {
    $ENV{'LANG'} = 'C';
    $ENV{'PATH'} = '/bin:/usr/bin:/usr/local/bin';
    $ENV{'LD_LIBRARY_PATH'} = '/usr/lib:/usr/lib64:/star64/lib';

    # Taint mode is selected, so we must validate the path before using it.
    die 'Invalid path to mail2feed script'
        unless $FindBin::RealBin =~ /^([-_a-zA-Z0-9\/\.]+)$/;
    unshift @INC, "$1/../lib";
}

use Getopt::Long qw/:config gnu_compat no_ignore_case require_order/;
use Pod::Usage;
use Mail::Audit;
use Encode qw/decode/;
# Add extra encoding support (e.g. for GB18030).  This is supposed to be
# loaded automatically, but doesn't seem to be -- perhaps because this
# module is installed in "site_perl".
use Encode::HanExtra;

use OMP::DB::Backend;
use OMP::Display;
use OMP::Fault::Response;
use OMP::DB::Fault;
use OMP::DB::Feedback;
use OMP::Mail;
use OMP::General;
use OMP::User;
use OMP::DB::User;
use OMP::UserQuery;

our $VERSION = '0.003';

# Address to which we send rejected messages for inspection.
my $REJECT_ADDRESS = OMP::User->get_omp_group()->as_email_hdr();

# Address from which we send rejected messages.
my $REJECT_FROM_ADDRESS = OMP::User->get_flex()->as_email_hdr_via_flex();

my ($help, $DRY_RUN);
GetOptions(
    'help|man'  => \$help,
    'n|dry-run' => \$DRY_RUN,
) or pod2usage('-exitval' => 2, '-verbose' => 1);

pod2usage('-exitval' => 0, '-verbose' => 3) if $help;

# Give Mail::Audit object & text, the given text is logged in dry run mode,
# followed by exit with error. Else. a "ignore" or "reject" method is called.
my @checks = (
    # X-Loop: check for an automated reply.
    {
        'text'   => 'Ignore message because X-Loop header exists',
        'test'   => sub { $_[0]->get('X-Loop') },
        'action' => sub { $_[0]->ignore($_[1]) },
    },

    # X-Spam-Status
    {
        'text'   => 'Sorry. This email looks like spam. Rejecting.',
        'test'   => sub { $_[0]->get('X-Spam-Status') =~ /^Yes/i },
        'action' => sub { $_[0]->reject($_[1]) },
    },

    # Check for messages which Mail::Audit thinks are from a mailer
    # or a daemon process.
    {
        'text'   => 'Message appears to be from a mailer / daemon.',
        'test'   => sub { $_[0]->from_mailer() || $_[0]->from_daemon() },
        'action' => sub {
            $_[0]->put_header('X-OMP-Subject' => $_[0]->get_header('Subject'));
            $_[0]->put_header('X-OMP-From' => $_[0]->get_header('From'));
            $_[0]->put_header('X-OMP-Error' => $_[1]);
            $_[0]->replace_header('Subject' => 'Message rejected by flex (mailer/daemon)');
            $_[0]->replace_header('From' => $REJECT_FROM_ADDRESS);
            $_[0]->replace_header('To' => $REJECT_ADDRESS);
            $_[0]->resend($REJECT_ADDRESS);
        },
    },
);

my $logfile = '/tmp/omp-mailaudit.log';
my $mail = Mail::Audit->new(
    loglevel => 4,
    log => $logfile
);

print "Mail audit log: $logfile\n" if $DRY_RUN;

foreach my $check (@checks) {
    if ($check->{'test'}->($mail)) {
        unless ($DRY_RUN) {
            $check->{'action'}->($mail, $check->{'text'})
        }
        else {
            log_exit($mail, $check->{'text'});
        }
    }
}

$mail->log(1 => 'Basic checks complete, attempting to identify target');

my $target = identify_target($mail);

unless (defined $target) {
    my $text = 'Sorry. Could not discern project or fault ID from the subject line.';
    unless ($DRY_RUN) {
        $mail->reject($text);
    }
    else {
        log_exit($mail, $text);
    }
}

# looks like we can accept this
accept_message($mail, $target);

exit;


# Process OMP feedback mail messages
# Accept a message and send it to the feedback system
sub accept_message {
    my $audit = shift;
    my $args = shift;

    my $database = OMP::DB::Backend->new();
    my $udb = OMP::DB::User->new(DB => $database);

    $audit->log(1 => "Accepting [VERSION=$VERSION]");

    # Get the information we need
    my $from = decode('MIME-Header', $audit->get('from'));
    my $srcip = ($from =~ /@(.*)\b/ ? $1 : $from);
    my $subject = decode('MIME-Header', $audit->get('subject'));

    # Get body of email.
    my $text;
    if ($audit->is_mime) {
        $text = OMP::Mail->extract_body_text($audit);
    }
    else {
        $text = join('', @{$audit->body});
    }

    # Try to guess the author
    my $email = undef;
    my $author_guess = OMP::User->extract_user_from_email($from, \$email);

    my $author = undef;

    # Attempt to retrive user object from the user DB.
    #
    # Try the email address first, because we now have several OMP
    # users with the same first initial and last name.  Inferring
    # the OMP user ID from the name therefore sometimes identifies
    # the wrong user.  See fault 20140717.002.
    if ($email) {
        my $users = $udb->queryUsers(OMP::UserQuery->new(HASH => {
            email => $email,
        }));

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

        $author = $udb->getUser($userid);
    }

    if ($author) {
        $audit->log(1 => "Determined OMP user: $author [ID=".
                          $author->userid."]");
    }
    else {
        $audit->log(1 => "Unable to determine OMP user from From address");
    }

    # Send the message to the appropriate system.
    if (exists $args->{'projectid'}) {
        accept_feedback($database, $audit, $subject, $args->{'projectid'}, $author, $text, $srcip);
    }
    elsif (exists $args->{'faultid'}) {
        accept_fault($database, $audit, $subject, $args->{'faultid'}, $author, $text);
    }
    else {
        my $text = 'Sorry. Could not determine how to store message.';
        $audit->log(1 => $text);
        $audit->reject($text) unless $DRY_RUN;
        return;
    }

    # Exit after delivery if required
    unless ($audit->{'noexit'}) {
        $audit->log(2 => "Exiting with status " . Mail::Audit::DELIVERED);
        exit Mail::Audit::DELIVERED;
    }
}


sub accept_feedback {
    my ($database, $audit, $subject, $project, $author, $text, $srcip) = @_;

    $audit->log(1 => "Sending to feedback system with Project $project");

    # Contact the feedback system
    my @order = qw/author program subject sourceinfo text/;
    my %data  = (
        author     => $author,
        program    => $0,
        subject    => $subject,
        sourceinfo => $srcip,
        text       => $text,
    );

    unless ($DRY_RUN) {
        my $fdb = OMP::DB::Feedback->new(ProjectID => $project, DB => $database);
        $fdb->addComment(\%data);
        $audit->log(1 => "Sent to feedback system with Project $project");
    }
    else {
        show_comment('project', (uc $project), \@order, \%data);
        $audit->log(1 => "DRY RUN: Not actually sent to feedback system for project $project");
    }
}


sub accept_fault {
    my ($database, $audit, $subject, $faultid, $author, $text) = @_;

    $audit->log(1 => "Sending to fault system for fault $faultid");

    unless (defined $author) {
        my $text = 'Sorry. Could not determine OMP user ID.';
        $audit->log(1 => $text);
        $audit->reject($text) unless $DRY_RUN;
        return;
    }

    my @order = qw/author text/;
    my %data = (
        author => $author,
        text => OMP::Display->remove_cr($text),
    );

    unless ($DRY_RUN) {
        my $fdb = OMP::DB::Fault->new(DB => $database);
        $fdb->respondFault($faultid, OMP::Fault::Response->new(%data));
    }
    else {
        show_comment('fault', $faultid, \@order, \%data);
        $audit->log(1 => "DRY RUN: Not actually sent to fault system for fault $faultid");
    }
}


sub show_comment {
    my ($type, $ident, $order, $data) = @_;

    my $format = "==> %s: %s\n";
    # Start long text on its own line.
    my $text_format = "==> %s:\n%s\n";

    printf $format, $type, $ident;

    foreach my $field (@$order) {
        printf
            $field ne 'text' ? $format : $text_format,
            $field,
            $data->{$field};
    }
}

# Determine the project or fault ID from the subject and
# store it in the mail header
# Return 1 if subject found, else false
sub identify_target{
    my $audit = shift;
    my $subject = decode('MIME-Header', $audit->get('subject'));

    # Attempt to match
    my $pid = OMP::General->extract_projectid($subject);
    if (defined $pid) {
        $audit->log(1 => "Project from subject: $pid");
        return {projectid => $pid};
    }

    my $fid = OMP::General->extract_faultid($subject);
    if (defined $fid) {
        $audit->log(1 => "Fault from subject: $fid");
        return {faultid => $fid};
    }

    $audit->log(1 => 'Could not determine project or fault from subject line');
    return undef;
}


sub log_exit {
    my ($mail, @text) = @_;

    $mail->log(1 => join "\n", @text);

    exit 2;
}

__END__

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2002-2005 Particle Physics and Astronomy Research Council.
Copyright (C) 2015-2019 East Asian Observatory.
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
