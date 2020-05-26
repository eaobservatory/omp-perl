package OMP::Auth::CADCAC;

=head1 NAME

OMP::Auth::CADCAC - User authentication via CADC AC web service

=cut

use strict;
use warnings;

use HTTP::Cookies;
use JSON;
use LWP::UserAgent;

use OMP::Config;
use OMP::DBbackend;
use OMP::Error;
use OMP::UserDB;
use OMP::UserQuery;

use base qw/OMP::Auth::Base/;

=head1 METHODS

=head2 Class methods

=over 4

=item B<log_in_userpass>

Attempt to get a user object by logging in via CADC's Access Control
web service:

=over 4

=item The name and password are checked using CADC AC.

=item The user database is searched for this name as an CADC account.

=back

=cut

sub log_in_userpass {
    my $cls = shift;
    throw OMP::Error::Authentication('Invalid username.')
        unless shift =~ /^([-_0-9a-zA-Z]+)$/;
    my $username = $1;
    my $password = shift;

    my $base_url = 'https://www.cadc-ccda.hia-iha.nrc-cnrc.gc.ca/';

    my $ua = LWP::UserAgent->new();

    my $res = $ua->post($base_url . 'ac/login', {username => $username, password => $password});

    throw OMP::Error::Authentication('Username or password not recognized.')
        if $res->code() =~ /^4\d\d$/;

    throw OMP::Error::Authentication(
        'Error logging in with CADC: could not query access control "login" service.')
        unless $res->is_success;

    my $cookie = $res->content;

    my $jar = HTTP::Cookies->new();
    $jar->set_cookie(0, 'CADC_SSO', '"' . $cookie . '"', '/', '.cadc-ccda.hia-iha.nrc-cnrc.gc.ca', 443, 0, 1, 60, 0);
    $ua->cookie_jar($jar);

    $res = $ua->get($base_url . 'ac/whoami', Accept => 'application/json');

    throw OMP::Error::Authentication(
        'Error logging in with CADC: could not query access control "whoami" service.')
        unless $res->is_success;

    my $json = $res->content;
    my $data = JSON->new->decode($json);

    my $user_verified = undef;
    foreach my $identity (@{$data->{'user'}->{'identities'}->{'$'}}) {
        $user_verified = $identity->{'identity'}->{'$'}
            if $identity->{'identity'}->{'@type'} eq 'HTTP';
    }

    throw OMP::Error::Authentication(
        'Error logging in with CADC: did not receive an HTTP identity from "whoami" service.')
        unless defined $user_verified;

    throw OMP::Error::Authentication(
        'Error logging in with CADC: user name from "whoami" service is invalid.')
        unless $user_verified =~ /^([-_0-9a-zA-Z]+)$/;

    my $cadcuser = $1;

    my $db = new OMP::UserDB(DB => new OMP::DBbackend());
    my @result = $db->queryUsers(new OMP::UserQuery(
        XML => '<UserQuery><cadcuser>' . $cadcuser. '</cadcuser><obfuscated>0</obfuscated></UserQuery>'));

    throw OMP::Error::Authentication('Could not find an OMP account associated with your CADC account "' . $cadcuser . '".')
        unless @result;

    throw OMP::Error::Authentication('Multiple OMP accounts are linked to your CADC account!')
        if 1 < scalar @result;

    my $result = $result[0];
    return {user => $result};
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
