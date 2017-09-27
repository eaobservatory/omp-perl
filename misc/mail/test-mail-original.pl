#!/local/perl/bin/perl

use strict; use warnings; use Carp qw[ carp croak confess ];
use 5.016;
select \*STDERR ; $| = 1;
select \*STDOUT ; $| = 1;

our $VERSION = '0.05';

use Getopt::Long   qw[ :config gnu_compat no_ignore_case require_order ];
use Pod::Usage;
use Data::Dumper   qw[ Dumper ];
use File::Basename qw[ fileparse ];

use FindBin;

use constant OMPLIB => "$FindBin::RealBin/../..";

BEGIN {
    $ENV{OMP_CFG_DIR} = File::Spec->catdir(OMPLIB, "cfg")
        unless exists $ENV{OMP_CFG_DIR};
}

use lib OMPLIB;

use OMP::User ;
use OMP::Mail::Original;

my $MY_NAME = ( fileparse( $0 ) )[0];

my ( @cc ,
      $debug ,
      $debug_mail_orig , $debug_net_smtp
    );
GetOptions( 'h|help|man' => \( my $help ) ,

            'cc=s@' => \@cc ,

            'd|debug!'            => \$debug ,
            'DM|debug-mail-orig!' => \$debug_mail_orig ,
            'DS|debug-smtp!'      => \$debug_net_smtp ,
          )
  or pod2usage( '-exitval'  => 2 , '-verbose'  => 1 ) ;

$help and pod2usage( '-exitval' => 0 , '-verbose' => 3 );


my $to_addr = $ARGV[0]
  or die qq[Give an email address to send mail to.\n];

my $flex = q[flex@eaobservatory.org];
my $from_user = make_user( $flex )->[0];
$from_user->name( $MY_NAME );

my $to_user  = make_user( $to_addr );
my $cc_users = make_user( @cc );

local $OMP::Mail::Original::DEBUG         = $debug_mail_orig;
local $OMP::Mail::Original::DEBUG_NetSMTP = $debug_net_smtp;
my $mailer = OMP::Mail::Original->new();
my $mess = $mailer->build(  'to'      => $to_user ,
                            'from'    => $from_user ,
                            'headers' => { 'Sender' => $flex } ,
                            ( $cc_users ? ( 'cc' => $cc_users ) : () ) ,
                            'subject' => 'test mail, ' . lc( scalar localtime()) ,
                            'message' => qq[testing separate mailing code...\n]
                          );

$debug and warn Dumper( $mess );

my @sent = $mailer->send( $mess );
$debug && scalar @sent and warn Dumper( @sent );

warn qq[  ... finished ($MY_NAME)\n];
exit;


sub make_user {

  my ( @addr ) = @_ or return;

  return [ map { OMP::User->new( 'email' => $_ ) } @addr ];
}


__END__

=pod

=head1 NAME

test-mail-original.pl - Driver to test original mail-only functionality.

=head1 SYNOPSIS

Send an email to C<someone@example.com> ...

  test-mail-original.pl  someone@example.com


See progress ...

  test-mail-original.pl -debug-mail-orig  someone@example.com

=head1  DESCRIPTION

It is a driver to test original mail-only functionality contained in
L<OMP::Mail::Original>; database is not
touched.

An email message is build with L<MIME::Entity>. It is then send via its
c<smtpsend> method, which uses L<Mail::Internet> module which uses L<Net::SMTP>
to actually send out the mail via SMTP connection.

=head2  OPTIONS

=over 2

=item B<-help>

Show this message

=item B<-cc> <mail@address>

Specify recipeint email addresses to "carbon copy" to. Repeat the option for
multiple addresses.

=item B<-debug> | B<-d>

Dumps L<MIME::Entity> object and any return value after sending the email.

=item B<-debug-mail-orig> | B<-DM>

Turn on debug option of L<OMP::Mail::Original>. Currently it behaves as progress
indicator.

=item B<-debug-smtp> | B<-DS>

Turn on debug option of L<Net::SMTP>.

=back

=head1 SEE ALSO

=over 2

=item * L<OMP::BaseDB>, L<OMP::Mail::Original>

=item * L<MIME::Entity>, L<Mail::Internet>, L<Net::SMTP>

=back

=head1 COPYRIGHT

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


