package OMP::Auth::OMPToken;

=head1 NAME

OMP::Auth::OMPToken - User authentication for SOAP clients via token

=cut

use strict;
use warnings;

use OMP::AuthDB;
use OMP::DBbackend;
use OMP::Error;

use base qw/OMP::Auth::Base/;

=head1 METHODS

=head2 Class methods

=over 4

=item B<log_in>

This method should not be used with this class.

=cut

sub log_in {
    my $cls = shift;

    throw OMP::Error::Authentication(
        'This authentication method can not be used for regular log in.');
}

=item B<log_in_userpass>

Attempt to get a partial user object by logging in via an exising OMP token.

This is intended to allow SOAP clients to maintain a user session.

=cut

sub log_in_userpass {
    my $cls = shift;
    my $username = shift;
    my $token = shift;

    my $db = new OMP::AuthDB(DB => new OMP::DBbackend());

    my $user_info = $db->verify_token($token);

    throw OMP::Error::Authentication('Your session may have expired.')
        unless defined $user_info;

    my $user = $user_info->{'user'};

    # Double-check user ID (should not be necessary).
    throw OMP::Error::Authentication('User name does not match session.')
        unless $username eq $user->userid();

    my %result = (user => $user);

    $result{'projects'} = $user_info->{'projects'} if exists $user_info->{'projects'};

    return \%result;
}

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

1;
