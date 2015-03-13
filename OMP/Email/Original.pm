package OMP::Email::Original;

=head1 NAME

OMP::Email::Original - Email functionality taken from OMP::BaseDB.

=head1 SYNOPSIS

...

=head1 DESCRIPTION

This class has the original email composition & mailing from
OMP::BaseDB module. It does not store anything in database.
Purpose is to test various email composition & mailing out methods.

=cut


use 5.016;
use strict;
use warnings;
use Carp ();

# OMP Dependencies
use OMP::Error;
use OMP::Constants qw/ :logging /;
use OMP::Display;
use OMP::DateTools;
use OMP::General;

use Mail::Internet;
use MIME::Entity;

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

Construct L<OMP::Email::Original> object; accepts no arguments.

  $email = OMP::Email::Original->new();

=cut

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;

  my $object = 'Nothing Stored';
  return bless \$object , $class;
}

=item B<build>

Returns a L<MIME::Entity> object, given the following as a hash ...

  to   - array reference of C<OMP::User> objects
  cc   - array reference of C<OMP::User> objects
  bcc  - array reference of C<OMP::User> objects
  from - an C<OMP::User> object
  subject - subject of the message
  message - the actual mail message
  headers - additional mail headers such as Reply-To and Content-Type
            in paramhash format

  $mess = $email->build(  to   => [$user1, $user2],
                          from => $user3,
                          subject => "hello",
                          message => "this is the content\n",
                          headers => { Reply-To => "you\@yourself.com",
                                      },
                        );

=cut

sub build {

  my $class = shift @_;
  my %args  = @_;

  # Check that we have the correct keys
  for my $key (qw/ to from subject message /) {
    throw OMP::Error::BadArgs("mail_information: Key $key is required")
      unless exists $args{$key};
  }

  # Decide if we'll have attachments or not and set the MIME type accordingly
  # by checking for the presence of HTML in the message
  my $type = ($args{message} =~ m!(</|<br>|<p>)!im ? "multipart/alternative" : "text/plain");

  my %utf8 = ( 'Charset' => 'utf-8' );
  # Setup the message
  my %details = ( %utf8,
                  From    => $args{from}->as_email_hdr(),
                  Subject => $args{subject},
                  Type     => $type,
                  Encoding =>'8bit',
                  process_address( $args{to} , $args{cc} )
                );


  throw OMP::Error::MailError("Undefined address [we have nobody to send the email to]")
    unless ($details{To});

  # No HTML in message so we won't be attaching anything.  Just include the
  # message content
  ($type eq "text/plain") and $details{Data} = $args{message};

  # Create the message
  my $mess = MIME::Entity->build(%details);

  # Create a Date header since the mail server might not create one
  $args{headers}->{date} = OMP::DateTools->mail_date;

  # Add any additional headers
  for my $hdr (keys %{ $args{headers} }) {
    $mess->add($hdr => $args{headers}->{$hdr});
  }

  # Convert the HTML to plain text and attach it to the message if we're
  # sending a multipart/alternative message
  if ($type eq "multipart/alternative" ) {

    # Convert the HTML to text and store it
    my $text = $args{message};
    my $plaintext = OMP::Display->html2plain($text);

    # Attach the plain text message
    $mess->attach(  %utf8,
                    'Type' => "text/plain",
                    'Data' => $plaintext,
                  )
      or throw OMP::Error::MailError("Error attaching plain text message\n");

    # Now attach the original message (it should come up as the default message
    # in the mail reader)
    $mess->attach(  %utf8,
                    'Type'=>"text/html",
                    'Data' => $args{message},
                 )
      or throw OMP::Error::MailError("Error attaching HTML message\n");
  }

  return $mess;
}

sub process_address {

  my ( $to , $cc ) = @_;

  # Get rid of duplicate users
  my %users;
  %{$users{to}} = remove_empty( $to );

  if ( $cc ) {

    %{$users{cc}} =
      remove_empty( [ grep {! $users{to}{$_->email}} @{$cc} ] ) ;
  }

  #  Convert OMP::User objects to suitable mail headers.
  my %out;
  for my $hdr (qw/ To Cc /) {

    my $alt = lc $hdr;
    if (defined $users{ $alt } ) {

      $out{ $hdr } =
        join ',', map
                  { $users{ $alt }{ $_ }->as_email_hdr() }
                  keys %{ $users{ $alt } }
                  ;
    }
  }
  return %out;
}

sub remove_empty {

  my ( $list ) = @_;

  $list // return;
  return
    map
    { $_->email()
      ? ( $_->email() => $_ )
      : ()
    }
    @{ $list } ;
}



=item B<send>

Mail some information to some people.  Composes a multipart message with a
plaintext attachment if any HTML is in the message.  Throws an exception on
error.

  $email->send( $mime_entity_obj );

Uses C<Net::SMTP> for the mail service so that it can run in a tainted
environment.

=cut

sub send {

  my $class = shift;

  my ( $mess ) = @_;

  # Send message (via Net::SMTP)
  my $mailhost = OMP::Config->getData("mailhost");

  my @sent;
  my @addr =
    map
    { my $e = $_->email();
      defined $e && length $e ? $e : ()
    }
    @{$args{to}}, @{$args{cc}}, @{$args{bcc}};

  return unless scalar @addr;

  OMP::General->log_message("Connecting to mailhost: $mailhost", OMP__LOG_INFO);
  eval {
    @sent = $mess->smtpsend( Host => $mailhost,
                              To  => [ @addr ],
                            );
  };
  $@ and throw OMP::Error::MailError("$@\n");

  scalar @sent
    and OMP::General->log_message(  "Mail message sent to " . join( ',', @sent ),
                                    OMP__LOG_INFO
                                  );

  log_mail_missed( \@sent, @addr );

  return;
}

sub log_mail_missed {

  my ( $sent, @all ) = @_;

  return unless scalar @all;

  my %miss;
  @miss{ @all } = ();

  if ( $sent && ref $sent ) {

    delete $miss{ $_ } for @{ $sent };
  }
  return if 0 == scalar keys %miss;

  OMP::General->log_message(  "Mail message NOT sent to " . join( ',', sort keys %miss ),
                              OMP__LOG_WARNING
                            );
  return;
}

1;

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
