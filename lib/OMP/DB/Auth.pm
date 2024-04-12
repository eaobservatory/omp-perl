package OMP::DB::Auth;

=head1 NAME

OMP::DB::Auth - Manipulate the user authentication table

=cut

use strict;
use warnings;

use IO::File;
use MIME::Base64 qw/encode_base64/;
use Time::Piece qw//;
use Time::Seconds;

use OMP::DateTools;
use OMP::Error;
use OMP::User;
use OMP::UserDB;

use base qw/OMP::DB/;

our $AUTHTABLE = 'ompauth';
our %DURATION = (
    default => Time::Seconds->new(8 * ONE_HOUR),
    remember => Time::Seconds->new(ONE_WEEK),
);
our $REFRESH_SECONDS = 600;

=head1 METHODS

=head2 Authentication token management

=over 4

=item B<issue_token>

Create a token for the given user, store it in the database, and return it.

    my $token = $db->issue_token($user, $addr, $agent, $duration_type);

The C<$duration_type> should be one of the types named in the C<%DURATION>
hash, i.e. "default" or "remember".

In array context, also returns the duration used for the given type
in a form suitable for generating HTTP cookies.

=cut

sub issue_token {
    my $self = shift;
    my $user = shift;
    my $addr = shift;
    my $agent = shift;
    my $duration_type = shift;

    my $is_staff = !! $user->is_staff();
    my $userid = $user->userid();
    throw OMP::Error::BadArgs('Invalid userid')
        unless $userid =~ /^[A-Z0-9]+$/;

    $addr = substr $addr, 0, 64 if defined $addr;
    $agent = substr $agent, 0, 255 if defined $agent;

    throw OMP::Error::BadArgs('Duration type not specified')
        unless defined $duration_type;
    throw OMP::Error::BadArgs('Unknown duration type')
        unless exists $DURATION{$duration_type};
    my $expiry = Time::Piece::gmtime() + $DURATION{$duration_type};

    my $token = $self->_make_token();

    $self->_db_begin_trans();
    $self->_dblock();

    $self->_db_insert_data($AUTHTABLE,
        $userid, $token, $expiry->strftime('%Y-%m-%d %T'),
        $addr, $agent, $is_staff, $duration_type);

    $self->_dbunlock();
    $self->_db_commit_trans();

    return $token unless wantarray;
    return $token, _duration_description($duration_type);
}

=item B<verify_token>

If the given token is valid, return a partial OMP::User object.
The database record is refreshed if necessary to extend its expiry.

    my $user = $db->verify_token($token);

In array context, also returns the token duration
in a form suitable for generating HTTP cookies.

=cut

sub verify_token {
    my $self = shift;
    my $token = shift;

    throw OMP::Error::BadArgs('Invalid token')
        unless $token =~ /^[A-Za-z0-9+\/=]+$/;

    $self->_expire_tokens();

    my $result = $self->_db_retrieve_data_ashash(
        'select A.userid, A.expiry, A.is_staff, A.duration, U.uname, U.email' .
        ' from ' . $AUTHTABLE .
        ' as A join ' . $OMP::UserDB::USERTABLE .
        ' as U on A.userid = U.userid where token = ?',
        $token);

    return unless @$result;

    throw OMP::Error::DBError('Multiple key matches found')
        if 1 < scalar @$result;

    $result = $result->[0];

    my $duration_type = $result->{'duration'};
    my $duration = $DURATION{$duration_type};

    my $expiry = OMP::DateTools->parse_date($result->{'expiry'}) - Time::Piece::gmtime();
    if (($duration->seconds() - $expiry->seconds()) > $REFRESH_SECONDS) {
        my $new_expiry = Time::Piece::gmtime() + $duration;

        $self->_db_begin_trans();
        $self->_dblock();

        $self->_db_update_data($AUTHTABLE,
            {expiry => $new_expiry->strftime('%Y-%m-%d %T')},
            'token = "' . $token . '"');

        $self->_dbunlock();
        $self->_db_commit_trans();
    }

    my $user = OMP::User->new(
        userid => $result->{'userid'},
        name => $result->{'uname'},
        email => $result->{'email'},
        is_staff => $result->{'is_staff'});

    return $user unless wantarray;
    return $user, _duration_description($duration_type);
}

=item B<remove_token>

Remove the given token from the database, logging the user out of one session.

    $db->remove_token($token);

=cut

sub remove_token {
    my $self = shift;
    my $token = shift;

    throw OMP::Error::BadArgs('Invalid token')
        unless $token =~ /^[A-Za-z0-9+\/=]+$/;

    $self->_db_begin_trans;
    $self->_dblock;

    $self->_db_delete_data($AUTHTABLE,
        'token = "' . $token . '"');

    $self->_dbunlock;
    $self->_db_commit_trans;
}

=item B<remove_all_tokens>

Remove all tokens for the given user, logging them out of all sessions.

    $db->remove_all_tokens($userid);

=cut

sub remove_all_tokens {
    my $self = shift;
    my $userid = shift;

    throw OMP::Error::BadArgs('Invalid userid')
        unless $userid =~ /^[A-Z0-9]+$/;

    $self->_db_begin_trans;
    $self->_dblock;

    $self->_db_delete_data($AUTHTABLE,
        'userid = "' . $userid . '"');

    $self->_dbunlock;
    $self->_db_commit_trans;
}

=item B<get_token_info>

Fetch information about all tokens for the given user.

    my $info = $db->get_token_info($userid);

=cut

sub get_token_info {
    my $self = shift;
    my $userid = shift;

    throw OMP::Error::BadArgs('Invalid userid')
        unless $userid =~ /^[A-Z0-9]+$/;

    $self->_expire_tokens();

    return $self->_db_retrieve_data_ashash(
        'select expiry, addr, agent, duration from ' . $AUTHTABLE .
        ' where userid = ?',
        $userid);
}

=back

=head2 Private methods

=over 4

=item B<_expire_tokens>

Clear expired tokens.  This should be done before attempting authentication.

    $db->_expire_tokens();

=cut

sub _expire_tokens {
    my $self = shift;

    $self->_db_begin_trans;
    $self->_dblock;

    $self->_db_delete_data($AUTHTABLE,
        'expiry < "' . Time::Piece::gmtime()->strftime("%Y-%m-%d %T") . '"');

    $self->_dbunlock;
    $self->_db_commit_trans;
}

=item B<_make_token>

Generate a new token string.

    my $token = $db->_make_token();

=cut

sub _make_token {
    my $self = shift;

    my $fh = IO::File->new('/dev/random', 'r');
    read $fh, (my $bytes), 21;
    close $fh;

    throw OMP::Error('Could not get random bytes for auth token')
        unless defined $bytes;

    return encode_base64($bytes, '');
}

=item B<_duration_description>

Create a description of a token duration of a form
suitable for use with CGI->cookie.

=cut

sub _duration_description {
    my $duration_type = shift;

    die 'Unknown duration type'
        unless exists $DURATION{$duration_type};

    my $duration = $DURATION{$duration_type};

    my $days = int($duration->days);
    return sprintf '+%id', $days if $days > 0;

    my $hours = int($duration->hours);
    return sprintf '+%ih', $hours if $hours > 0;

    my $seconds = int($duration->seconds);
    return sprintf '+%is', $seconds;
}

1;

__END__

=back

=head1 COPYRIGHT

Copyright (C) 2020 East Asian Observatory
All Rights Reserved.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful,but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc.,51 Franklin
Street, Fifth Floor, Boston, MA  02110-1301, USA

=cut
