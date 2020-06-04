package OMP::Password;

=pod

=head1 NAME

OMP::Password - Password related things.

=head1 SYNOPSIS

  use OMP::Password;
  use OMP::Error qw/ :try /;
  use OMP::Constants qw /:status/;

  #  Single try.
  my $pass =
    OMP::Password->get_password({
      'prompt' => 'Enter password: '
    });


=head1 DESCRIPTION

This module is a collection of password related methods.

=cut

use 5.006;
use strict;
use warnings;

our $VERSION = qw/$REVISION$/[1];

use Term::ReadLine;

use OMP::Error qw/ :try /;
use OMP::Constants qw/ :status /;
use OMP::Config;

=pod

=head1 METHODS

There are no instance methods, only class (static) methods.

=head2 Acquisition

=over 4

=item B<get_userpass>

Attempt to get an OMP::Auth provider name, username and password.

  my ($provider, $username, $password) = OMP::Password->get_userpass();

Currently assumes provider 'staff' and gets the username from C<$ENV{'USER'}>.

=cut

sub get_userpass {
  my $cls = shift;
  my $provider = 'staff';
  my $username = $ENV{'USER'};
  die 'Could not determine your username from the environment'
    unless defined $username;;
  my $password = $cls->get_password({
    prompt => 'Please enter your password: '});
  return $provider, $username, $password;
}

=item B<get_password>

A wrapper around L<Term::ReadLine/"readline"> function to ask for
password; the prompt may be highlighted with underline.

It takes an optional hash reference to set behaviour, and returns the
plaintext password string.  Below is the key-value description of the
hash reference ...

=over 4

=item I<prompt>

The prompt text to show.

Default is "Enter password: ".

=item I<err-prompt>

The prompt text to show when password is incorrect.  (Currently this
is unused by this method.)

Default is "Incorrect password, enter again: ".

=back

=back

=cut

sub get_password {

  my ( $self, $opt ) = @_;

  my $config = _default_password_prompt();
  _copy_new_hash_values( $config, $opt );

  my $term = Term::ReadLine->new( 'Password Entry', *STDERR, *STDERR );

  # Needs Term::ReadLine::Gnu.
  my $attribs = $term->Attribs;
  $attribs->{redisplay_function} = $attribs->{shadow_redisplay};
  my $password = $term->readline( $config->{'prompt'} );
  $attribs->{redisplay_function} = $attribs->{rl_redisplay};

  return $password;
}

sub _default_password_prompt {

  return {
    'prompt' => q/Enter password: /,
    'err-prompt' => q/Incorrect password, enter again: /,
  };
}

sub _copy_new_hash_values {

  my ( $orig, $opt ) = @_;
  for my $k ( keys %{ $orig } ) {

    $orig->{ $k } = $opt->{ $k } if exists $opt->{ $k };
  }
  return;
}

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>,
Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>,
Anubhav A. E<lt>a.agarwal@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2007, 2010 Science and Technology Facilities Council.
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

1;
