package OMP::Mail;

=head1 NAME

OMP::Mail - Email functionality taken from OMP::BaseDB

=head1 SYNOPSIS

...

=head1 DESCRIPTION

This class has the original email composition & mailing from
OMP::BaseDB module. It does not store anything in database.
Purpose is to test various email composition & mailing out methods.

=cut


use 5.8.7;
use strict;
use warnings;
use Carp ();

our $VERSION = '0.06';

# OMP Dependencies
use OMP::Error;
use OMP::Constants qw/:logging/;
use OMP::Display;
use OMP::DateTools;
use OMP::General;

use DateTime;
use Digest::MD5 qw/md5_hex/;
use Encode qw/decode encode find_encoding/;
use Mail::Internet;
use MIME::Entity;
use Time::HiRes qw/gettimeofday/;

our $DEBUG = 0;
our $DEBUG_NetSMTP = 0;

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

Construct L<OMP::Mail> object; accepts no arguments.

    $email = OMP::Mail->new();

=cut

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;

    my $list = {
        'to' => undef,
        'cc' => undef,
        'bcc' => undef
    };

    return bless $list, $class;
}

=item B<build>

Returns a L<MIME::Entity> object, given the following as a hash ...

=over 4

=item to

Array reference of C<OMP::User> objects.

=item cc

Array reference of C<OMP::User> objects.

=item bcc

Array reference of C<OMP::User> objects.

=item from

An C<OMP::User> object.

=item subject

Subject of the message.

=item message

The actual mail message.

=item headers

Additional mail headers such as Reply-To and Content-Type
in paramhash format.

=item reply_to_sender

Add a Reply-To header giving the "from" user's
address, if they have one.

=back

    $mess = $email->build(
        to => [$user1, $user2],
        from => $user3,
        subject => "hello",
        message => "this is the content\n",
        headers => {
            Reply-To => "you\@yourself.com",
        },
    );

=cut

sub build {
    my $self = shift @_;
    my %args = @_;

    # Check that we have the correct keys
    for my $key (qw/to from subject message/) {
        throw OMP::Error::BadArgs("mail_information: Key $key is required")
            unless exists $args{$key};
    }

    # Avoid Encode::MIME::Header and Mail::Header both folding the header.
    my $std_header_encoding = find_encoding('MIME-Header');
    my $header_encoding = bless {
        %$std_header_encoding,
        Name => 'MIME-Header-Long',
        bpl => 900,
    }, ref $std_header_encoding;

    my $sender = $args{'from'};

    # Decide if we'll have attachments or not and set the MIME type accordingly
    # by checking for the presence of HTML in the message
    my $type = ($args{message} =~ m!(</|<br>|<p>)!im
        ? "multipart/alternative"
        : "text/plain");

    # Setup the message
    my $charset = 'utf-8';
    my %recipient = $self->process_addr(
        $header_encoding,
        map {$_ => $args{$_}} qw/to cc bcc/);

    my %details = (
        From => $sender->as_email_hdr_via_flex($header_encoding),
        Subject => encode_if_necessary($header_encoding, $args{subject}),
        'Message-ID' => make_message_id($args{subject}),
        Type => $type,
        %recipient,
    );

    throw OMP::Error::MailError(
        "Undefined address [we have nobody to send the email to]")
        unless $details{To};

    # No HTML in message so we won't be attaching anything.  Just include the
    # message content
    if ($type eq "text/plain") {
        $details{'Encoding'} = 'quoted-printable';
        $details{'Charset'} = $charset;
        $details{'Data'} = encode($charset, $args{message});
    }
    else {
        $details{'Encoding'} = '7bit';
    }

    # Create the message
    my $mess = MIME::Entity->build(%details);

    # Create a Date header since the mail server might not create one
    $args{headers}->{date} = OMP::DateTools->mail_date;

    # Create a Reply-To header if requested.
    if ($args{'reply_to_sender'}) {
        $args{'headers'}->{'Reply-To'} = $sender->as_email_hdr($header_encoding)
            if defined $sender->email();
    }

    # Add any additional headers
    for my $hdr (keys %{$args{headers}}) {
        $mess->add($hdr => $args{headers}->{$hdr});
    }

    # Convert the HTML to plain text and attach it to the message if we're
    # sending a multipart/alternative message
    if ($type eq "multipart/alternative") {
        # Convert the HTML to text and store it
        my $text = $args{message};
        my $plaintext = OMP::Display->html2plain($text);

        # Attach the plain text message
        $mess->attach(
            Charset => $charset,
            Encoding => 'quoted-printable',
            'Type' => "text/plain",
            'Data' => encode($charset, $plaintext),
        ) or throw OMP::Error::MailError("Error attaching plain text message\n");

        # Now attach the original message (it should come up as the default message
        # in the mail reader)
        $mess->attach(
            Charset => $charset,
            Encoding => 'quoted-printable',
            'Type' => "text/html",
            'Data' => encode($charset, $args{message}),
        ) or throw OMP::Error::MailError("Error attaching HTML message\n");
    }

    # Increase header folding length because our mail system apparently has trouble
    # with wrapped headers.  RFC2822 says lines should be no more than 78
    # but must be no more than 998.
    $mess->head->fold_length(318);

    return $mess;
}

sub process_addr {
    my ($self, $header_encoding, %list) = @_;

    #  Convert OMP::User objects to suitable mail headers.
    my (%out, %seen);

    for my $hdr (qw/To Cc Bcc/) {
        my $alt = lc $hdr;
        my $users = $list{$alt};
        my @tmp;
        for my $user (@{$users}) {
            my $addr = $user->email();
            $addr && length $addr or next;
            $seen{$addr} ++ and next;

            push @tmp, $user->as_email_hdr($header_encoding);
            push @{$self->{$alt}}, $addr;
        }
        scalar @tmp and $out{$hdr} = join ', ', @tmp;
    }

    return %out;
}

=item B<make_message_id>

Attempt to create a unique value for a Message-ID header.

    $message_id = make_message_id($subject);

This contains (the start of) the MD5 sum of the given subject,
the date and time, the current microseconds and the process ID.

=cut

sub make_message_id {
    my $subject = shift // 'no subject';

    my $checksum = md5_hex(encode('UTF-8', $subject));

    my $dt = DateTime->now(time_zone => 'UTC');
    my $time = $dt->strftime('%Y%m%d%H%M%S');
    (undef, my $microseconds) = gettimeofday;

    my $url = OMP::Config->getData('omp-url');
    (undef, my $domain) = split /:\/\//, $url, 2;

    return sprintf '<%s.%s.%06d.%d@%s>',
        (substr $checksum, 0, 8), $time, $microseconds, $$, $domain;
}

=item B<encode_if_necessary>

Encode an unstructured header (e.g. Subject) if needed.

    $encoded = encode_if_necessary($encoding, $value);

=cut

sub encode_if_necessary {
    my $header_encoding = shift;
    my $value = shift;

    return $header_encoding->encode($value)
        if $value =~ /[^ -~]/;

    return $value;
}

sub remove_empty {
    my ($list) = @_;

    $list or return;

    # Generates address & O::User pair.
    return map {
        $_ && $_->email()
            ? ($_->email() => $_)
            : ()
    } @{$list};
}

# All of get_* methods rely on process_addr() being called before hand.
sub get_all_addr {
    my ($self) = @_;

    return map {$self->$_()} qw/get_to_addr get_cc_addr get_bcc_addr/;
}

sub get_to_addr {
    my ($self) = @_;
    return $self->_get_header_addr('to');
}

sub get_cc_addr {
    my ($self) = @_;
    return $self->_get_header_addr('cc');
}

sub get_bcc_addr {
    my ($self) = @_;
    return $self->_get_header_addr('bcc');
}

sub _get_header_addr {
    my ($self, $header) = @_;

    my $list = $self->{$header} or return;

    return @{$list};
}

=item B<send>

Mail some information to some people.  Composes a multipart message with a
plaintext attachment if any HTML is in the message.  Throws an exception on
error.

    $email->send($mime_entity_obj);

Uses L<Net::SMTP> for the mail service so that it can run in a tainted
environment.

=cut

sub send {
    my ($self, $mess) = @_;

    my @addr = $self->get_all_addr();
    unless (scalar @addr) {
        _logger('No addresses found.', OMP__LOG_WARNING);
        return;
    }

    # Send message (via Net::SMTP)
    my $mailhost = OMP::Config->getData("mailhost");

    my @sent;
    _logger("Connecting to mailhost: $mailhost", OMP__LOG_INFO);

    Carp::carp("Trying to send mail to: " . join ' ', @addr)
        if $DEBUG;

    eval {
        # Net::SMTP is used via Mail::Internet via MIME::Entity.
        @sent = $mess->smtpsend(
            Host => $mailhost,
            MailFrom => q[flex@eaobservatory.org],
            Debug => $DEBUG_NetSMTP
        );
    };

    throw OMP::Error::MailError("$@\n")
        if $@;

    _logger("Mail message sent to " . join(', ', @sent), OMP__LOG_INFO)
        if @sent;

    log_mail_missed(\@sent, @addr);

    return;
}

sub log_mail_missed {
    my ($sent, @all) = @_;

    return unless scalar @all;

    my %miss;
    @miss{@all} = ();

    if ($sent && ref $sent) {
        delete $miss{$_} for @{$sent};
    }

    return if 0 == scalar keys %miss;

    _logger("Mail message NOT sent to " . join(',', sort keys %miss), OMP__LOG_WARNING);

    return;
}

sub _logger {
    my ($mess, $level) = @_;

    Carp::carp($mess) if $DEBUG;

    OMP::General->log_message($mess, $level);

    return;
}

=item B<extract_body_text>

Return the body of an email with notations about any removed attachments
and parts other than alternatives.

    $text = OMP::Mail->extract_body_text($entity);

Recursively searches a MIME entity for suitable text parts.  In a
multipart/alternative, prefers text/plain to text/html.  In other
structures, either of these types is used.  Parts of other types
are removed with a notation added.  Attachments are counted by
type to allow a summary notation to be added.

Any HTML parts processed are converted to plain text using
C<OMP::Display-E<gt>html2plain> - see C<_extract_part_text>
for more details of text extraction.

=cut

sub extract_body_text {
    my $cls = shift;
    my $entity = shift;

    my @bodytexts = ();

    my $type = $entity->effective_type;

    my $num_parts = $entity->parts;

    if ($num_parts > 0) {
        if ($type eq 'multipart/alternative') {
            my %alternative = ();
            my @multipart = ();

            for (my $i = 0; $i < $num_parts; $i ++) {
                my $part = $entity->parts($i);

                if ($part->is_multipart) {
                    push @multipart, $part;
                }
                else {
                    $alternative{$part->effective_type} = $part;
                }
            }

            if (exists $alternative{'text/plain'}) {
                push @bodytexts, $cls->_extract_part_text($alternative{'text/plain'}, 0);
            }
            elsif (exists $alternative{'text/html'}) {
                push @bodytexts, $cls->_extract_part_text($alternative{'text/html'}, 1);
            }
            elsif (@multipart) {
                # No preferred type: search inside further multiparts.
                # (Should select preferred alternative but for now include all
                # or issue a notation if there were no multiparts to search.)
                push @bodytexts, $cls->extract_body_text($_) foreach @multipart;
            }
            else {
                push @bodytexts, 'No suitable alternative part found.';
            }
        }
        else {
            my %attachment = ();
            for (my $i = 0; $i < $num_parts; $i ++) {
                my $part = $entity->parts($i);
                my $part_type = $part->effective_type;

                my $head = $entity->head;
                my $disposition = $part->get('Content-Disposition');

                if ((defined $disposition) and $disposition =~ /^attachment/i) {
                    # Count attachments of each type.
                    $attachment{$part_type} ++;
                }
                else {
                    # Continue processing non-attachments.
                    push @bodytexts, $cls->extract_body_text($part);
                }
            }

            if (scalar %attachment) {
                push @bodytexts, join "\n", map {
                    sprintf '%d attachment(s) of type [%s] removed.', $attachment{$_}, $_;
                }
                sort keys %attachment;
            }
        }
    }
    else {
        # There is a single part.  Extract text/plain or text/html,
        # and issue a note for other types.
        if ($type eq 'text/plain') {
            push @bodytexts, $cls->_extract_part_text($entity, 0);
        }
        elsif ($type eq 'text/html') {
            push @bodytexts, $cls->_extract_part_text($entity, 1);
        }
        else {
            push @bodytexts, sprintf 'A part of type [%s] was removed.', $type;
        }
    }

    return join "\n\n", @bodytexts;
}

=item B<_extract_part_text>

Extract the text from a part.  If C<$is_html> is specified, use
C<OMP::Display-E<gt>html2plain> to convert it to plain text.

=cut

sub _extract_part_text {
    my $cls = shift;
    my $entity = shift;
    my $is_html = shift;

    my $head = $entity->head;
    my $charset = $head->mime_attr('content-type.charset');

    my $bh = $entity->bodyhandle;
    my $text = $bh->as_string;

    if (defined $charset) {
        $text = decode($charset, $text);
    }

    # Remove "object replacement character".
    $text =~ s/\x{FFFC}//g;

    # Remove CR.
    $text =~ s/\015//g;

    if ($is_html) {
        $text = OMP::Display->html2plain($text);
    }

    # Remove leading and trailing whitespace.
    $text =~ s/^\s*//;
    $text =~ s/\s*$//;

    return $text;
}

1;

__END__

=back

=head1 SEE ALSO

For related classes see L<OMP::BaseDB>, L<OMP::FeedbackDB>, L<OMP::User>.

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
Copyright (C) 2015 East Asian Observatory.
All Rights Reserved.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the
Free Software Foundation, Inc., 59 Temple Place, Suite 330,
Boston, MA  02111-1307  USA

=cut
