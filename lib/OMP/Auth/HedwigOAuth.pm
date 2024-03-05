package OMP::Auth::HedwigOAuth;

=head1 NAME

OMP::Auth::HedwigOAuth - User authentication via OAuth and the hedwig2omp database

=cut

use strict;
use warnings;

use IO::File;
use OIDC::Lite::Client::WebServer;
use OIDC::Lite::Model::IDToken;
use URI;
use URI::QueryParam;

use OMP::Config;
use OMP::DBbackend;
use OMP::DBbackend::Hedwig2OMP;
use OMP::Error;
use OMP::UserDB;
use OMP::UserQuery;

sub _get_client {
    my $cls = shift;

    return OIDC::Lite::Client::WebServer->new(
        id => OMP::Config->getData('auth_hedwig.client_id'),
        secret => OMP::Config->getData('auth_hedwig.client_secret'),
        authorize_uri => OMP::Config->getData('auth_hedwig.url_auth'),
        access_token_uri => OMP::Config->getData('auth_hedwig.url_token'));
}

use base qw/OMP::Auth::Base/;

=head1 METHODS

=head2 Class methods

=over 4

=cut

=item B<log_in>

Start the OAuth process by redirecting to Hedwig.

=cut

sub log_in {
    my $cls = shift;
    my $page = shift;

    my $q = $page->cgi;

    my $redirect = $cls->_get_client()->uri_to_redirect(
        redirect_uri => OMP::Config->getData('auth_hedwig.url_redir'),
        scope => 'openid',
        state => $page->url_absolute(
            remember_me => ($q->param('remember_me') ? '1' : '0')),
    );

    return {redirect => $redirect};
}

=item B<log_in_oauth>

Complete the OAuth process by sending the authorization code back to Hedwig
in exchange for an access token.

Since we specify scope "openid", we expect an OIDC ID token including the
user's Hedwig person ID in the "sub" field.

=cut

sub log_in_oauth {
    my $cls = shift;
    my $page = shift;

    my $q = $page->cgi;

    my $code = $q->param('code');

    unless (defined $code) {
        throw OMP::Error::Authentication(
            'Error logging in with Hedwig: ' . $q->param('error_description'))
            if defined $q->param('error_description');

        throw OMP::Error::Authentication(
            'Error logging in with Hedwig: no authorization code or error description received.');
    }

    my $user = $cls->_finish_oauth(
        $code, OMP::Config->getData('auth_hedwig.url_redir'));

    my $redirect_uri = scalar $q->param('state');
    my $duration = 'default';
    unless (defined $redirect_uri) {
        $redirect_uri = 'cgi-bin/projecthome.pl';
    }
    else {
        my $uri = new URI($redirect_uri);
        $duration = 'remember' if scalar $uri->query_param_delete('remember_me');
        $redirect_uri = $uri->as_string;
    }

    return {
        user => $user,
        redirect => $redirect_uri,
        duration => $duration,
    }
}

=item B<log_in_userpass>

Instead of username and password, expect the redirect_uri and authorization
code from an OAuth session initiated by the OT (or other program).

=cut

sub log_in_userpass {
    my $cls = shift;
    throw OMP::Error::Authentication('Invalid username -- should be the redirect URI.')
        unless shift =~ /^(http.*)$/;
    my $redirect_uri = $1;
    my $code = shift;

    return {user => $cls->_finish_oauth($code, $redirect_uri)};
}

sub _finish_oauth {
    my $cls = shift;
    my $code = shift;
    my $redirect_uri = shift;

    my $client = $cls->_get_client();
    my $token = $client->get_access_token(
        code => $code,
        redirect_uri => $redirect_uri);

    throw OMP::Error::Authentication(
        'Error retreiving Hedwig account information: ' .$client->errstr)
        unless $token;

    my $fh = new IO::File(OMP::Config->getData('auth_hedwig.oidc_pub'), 'r');
    my $key;
    do {
        local $/ = undef;
        $key = <$fh>;
    };
    close $fh;

    my $id_token = OIDC::Lite::Model::IDToken->load(
        $token->id_token, $key, 'RS512');

    throw OMP::Error::Authentication(
        'Could not verify ID token retrieved from Hedwig.')
        unless $id_token->verify();

    my $id_info = $id_token->payload();

    my $hedwig_id = $id_info->{'sub'};

    throw OMP::Error::Authentication(
        'ID token retrieved from Hedwig has no identitfier.')
        unless defined $hedwig_id;

    my $omp_id = $cls->_lookup_hedwig_id($hedwig_id);

    my $db = new OMP::UserDB(DB => new OMP::DBbackend());

    my $user = $db->getUser($omp_id);

    throw OMP::Error::Authentication(
        'Your linked OMP account appears not to exist.')
        unless defined $user;

    # Log in as staff if the user has
    # the "staff_access" flag in their OMP account.
    $user->is_staff(1) if $user->staff_access();

    return $user;
}

sub _lookup_hedwig_id {
    my $cls = shift;
    my $hedwig_id = shift;

    my $db = new OMP::DBbackend::Hedwig2OMP();

    my $result = $db->handle()->selectall_arrayref(
        'SELECT omp_id FROM user WHERE hedwig_id = ?', {}, $hedwig_id);

    throw OMP::Error::Authentication(
        'There does not appear to be an OMP account linked to your Hedwig account. ' .
        'Please contact the observatory for assistance.')
        unless 1 == scalar @$result;

    return $result->[0]->[0];
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
