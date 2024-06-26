package OMP::Auth;

=head1 NAME

OMP::Auth - User authentication and authorization module

=cut

use strict;
use warnings;

use OMP::DB::Auth;
use OMP::Config;
use OMP::Constants qw/:logging/;
use OMP::Error qw/:try/;
use OMP::General;
use OMP::DB::Project;
use OMP::Query::Project;
use OMP::User;

our %PROVIDERS = (
    'staff' => {
        class => 'OMP::Auth::LDAP',
    },
    'hedwig' => {
        class => 'OMP::Auth::HedwigOAuth',
    },
    'omptoken' => {
        class => 'OMP::Auth::OMPToken',
    },
);

=head1 METHODS

=head2 Class methods

=over 4

=item B<log_in>

Attempt to log a user in, using information from an OMP::CGIPage object.

    my $auth = OMP::Auth->log_in($page, %opt);

The L<cookie> method should subsequently be used to obtain the cookie
which must be included in the HTTP header.

    my $cookie = $auth->cookie();
    if (defined $cookie) {
        print $q->header(-cookie => $cookie);
    }
    else {
        ...
    }

=cut

sub log_in {
    my $cls = shift;
    my $page = shift;
    my %opt = @_;

    my $q = $page->cgi;
    my $db = OMP::DB::Auth->new(DB => $page->database);

    my $user = undef;
    my $token = undef;
    my $duration = undef;
    my $message = undef;
    my $abort = undef;
    my $redirect = undef;

    try {
        if ((defined $q->param('submit_log_in')) or (exists $opt{'method'})) {
            my $provider_name = $opt{'provider'} // $q->param('provider');

            throw OMP::Error::Authentication('Authentication method not specified.')
                unless defined $provider_name;

            my $provider_class = $cls->_get_provider($provider_name);

            my $method = $opt{'method'} // 'log_in';
            my $user_info = $provider_class->$method($page);

            $abort = 1 if exists $user_info->{'abort'};
            $redirect = $user_info->{'redirect'} if exists $user_info->{'redirect'};

            if (exists $user_info->{'user'}) {
                $user = $user_info->{'user'};
                ($token, $duration) = $db->issue_token(
                    $user, $q->remote_addr(), $q->user_agent(), $user_info->{'duration'});

                # Redirect back to the current page so it is loaded normally.
                $redirect = $page->url_absolute() unless defined $redirect;
            }
        }
        else {
            my %cookie = $q->cookie(-name => OMP::Config->getData('cookie-name'));

            if (exists $cookie{'token'}) {
                $token = $cookie{'token'};
                ($user, $duration) = $db->verify_token($token);
                undef $token unless defined $user;
            }
        }
    }
    catch OMP::Error::Authentication with {
        my $error = shift;
        $message = $error->text();
    }
    otherwise {
        OMP::General->log_message('Log in error: ' . shift . "\n", OMP__LOG_ERROR);
        $message = 'An unexpected error occurred.';
    };

    my $auth = $cls->new(message => $message);
    $auth->user($user) if defined $user;
    $auth->cookie($cls->_make_cookie($q, $duration, token => $token)) if defined $token;

    if (defined $redirect) {
        my %args = ();
        $args{'-cookie'} = $auth->cookie if defined $token;

        unless (OMP::Config->getData('www-meta-refresh')) {
            print $q->redirect(-uri => $redirect, %args);
        }
        else {
            print $q->header(-expires => '-1d', -charset => 'utf-8', %args);
            print "<html><head><meta http-equiv=\"refresh\" content=\"2; url=$redirect\" /></head><body><p>Redirecting&hellip;</p><p><a href=\"$redirect\">$redirect</a></p></body></html>";
        }

        $abort = 1;
    }

    $auth->abort($abort) if defined $abort;
    return $auth;
}

=item B<log_in_userpass>

Attempt to log a user in, using the given provider, username and password.

    my $auth = OMP::Auth->log_in_userpass($db, $provider, $username, $password);

This is for use outside of the web interface.  Not all providers
may support this method.

=cut

sub log_in_userpass {
    my $cls = shift;
    my $db = shift;
    my $provider = shift;
    my $username = shift;
    my $password = shift;

    die 'An OMP::DB::Backend must be given'
        unless eval {$db->isa('OMP::DB::Backend')};

    my $user = undef;
    my $message = undef;

    try {
        my $provider_class = $cls->_get_provider($provider);

        my $user_info = $provider_class->log_in_userpass($db, $username, $password);

        $user = $user_info->{'user'} if exists $user_info->{'user'};
    }
    catch OMP::Error::Authentication with {
        my $error = shift;
        $message = $error->text();
    }
    otherwise {
        OMP::General->log_message('Log in error: ' . shift . "\n", OMP__LOG_ERROR);
        $message = 'An unexpected error occurred.';
    };

    my $auth = $cls->new(message => $message);
    $auth->user($user) if defined $user;

    return $auth;
}

=item B<log_out>

Log the current user out of their current CGI-based session.

    my $auth = OMP::Auth->log_out($page);

As for L<log_in>, the L<cookie> method must be used for the HTTP header.

=cut

sub log_out {
    my $cls = shift;
    my $page = shift;

    my $q = $page->cgi;
    my %cookie = $q->cookie(-name => OMP::Config->getData('cookie-name'));

    if (exists $cookie{'token'}) {
        my $db = OMP::DB::Auth->new(DB => $page->database);
        $db->remove_token($cookie{'token'});

        return $cls->new(cookie => $cls->_make_cookie($q, '-1d'));
    }

    return $cls->new();
}

=back

=head2 Constructor

=over 4

=item B<new>

Construct a new OMP::Auth object.

    my $auth = OMP::Auth->new();

=cut

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;

    my %args = @_;

    my $c = {
        user => undef,
        projects => undef,
        cookie => undef,
        message => undef,
        abort => undef,
    };

    my $self = bless $c, $class;

    while (my ($method, $value) = each %args) {
        $self->$method($value);
    }

    return $self;
}

=back

=head2 Accessor methods

=over 4

=item B<user>

Access the OMP::User object for the current user, if any.

    my $user = $auth->user();

Note: this may contain only partial information depending on how the
user was authenticated.

=cut

sub user {
    my $self = shift;

    if (@_) {
        my $user = shift;
        throw OMP::Error::BadArgs('OMP::Auth->user must be an OMP::User')
            unless UNIVERSAL::isa($user, 'OMP::User');
        $self->{'user'} = $user;
    }

    return $self->{'user'};
}

=item B<projects>

Access a list of projects to which the user has access.

    my $projects = $auth->projects($db);

=cut

sub projects {
    my $self = shift;
    my $db = shift;

    die 'An OMP::DB::Backend must be given'
        unless eval {$db->isa('OMP::DB::Backend')};

    if (@_) {
        throw OMP::Error::BadArgs('OMP::Auth->projects must be an array ref')
            unless 'ARRAY' eq ref $_[0];
        $self->{'projects'} = shift;
    }
    elsif (not defined $self->{'projects'}) {
        $self->{'projects'} = $self->_fetch_projects($db);
    }

    return $self->{'projects'};
}

=item B<cookie>

Access the cookie stored in this object.

    my $cookie = $auth->cookie();

If the L<log_in> or L<log_out> method was used, then this cookie
must be included in the HTTP header to complete the action.

=cut

sub cookie {
    my $self = shift;

    if (@_) {
        $self->{'cookie'} = shift;
    }

    return $self->{'cookie'};
}

=item B<message>

Access the message stored in this object.

    my $message = $auth->message();

This will normally be set with an authentication failure occurs.

=cut

sub message {
    my $self = shift;

    if (@_) {
        $self->{'message'} = shift;
    }

    return $self->{'message'};
}

=item B<abort>

This is a flag indicating whether the authentication provider wishes
to abort the page rendering processes, e.g. because it has already
generated a redirect.

=cut

sub abort {
    my $self = shift;

    if (@_) {
        $self->{'abort'} = shift;
    }

    return $self->{'abort'};
}

=back

=head2 Utility methods

=over 4

=item B<is_staff>

Determine whether the user is logged in as a staff member.

    my $is_staff = $auth->is_staff();

=cut

sub is_staff {
    my $self = shift;

    my $user = $self->user;

    return 0 unless defined $user;

    return $user->is_staff;
}

=item B<has_project>

Determine whether the user has access to the given projects.

    my $has_project = $auth->has_project($db, $projectid);

Note: this method only checks for projects which list this user -- it does
not consider staff access to projects.

=cut

sub has_project {
    my $self = shift;
    my $db = shift;
    my $project = shift;

    return !! grep {$_ eq $project} @{$self->projects($db)};
}

=back

=head2 Private methods

=over 4

=item B<_fetch_projects>

Query the project database to determine to which projects this user
has access.

=cut

sub _fetch_projects {
    my $self = shift;
    my $db = shift;

    my $user = $self->user;
    return [] unless defined $user;

    my $userid = $user->userid;
    throw OMP::Error('OMP::Auth cannot fetch projects: user object has no userid')
        unless defined $userid;

    my $projdb = OMP::DB::Project->new(DB => $db);

    my $projects = $projdb->listProjects(OMP::Query::Project->new(HASH => {
        person_access => $userid,
    }));

    return [map {$_->projectid} @$projects];
}

=item B<_make_cookie>

Create a cookie using the CGI module.

    $auth->cookie($cls->_make_cookie($q, '+1d', token => $token));

=cut

sub _make_cookie {
    my $cls = shift;
    my $q = shift;
    my $expiry = shift;
    my %values = @_;

    return $q->cookie(
        -name => OMP::Config->getData('cookie-name'),
        -value => \%values,
        -domain => OMP::Config->getData('cookie-domain'),
        -secure => OMP::Config->getData('cookie-secure'),
        -expires => $expiry);
}

=item B<_get_provider>

Load a provider class given the short name.

    my $provider_class = $cls->_get_provider($provider);

=cut

sub _get_provider {
    my $cls = shift;
    my $provider = shift;

    throw OMP::Error::Authentication('Authentication method not recognized.')
        unless exists $PROVIDERS{$provider};

    my $provider_class = $PROVIDERS{$provider}->{'class'};
    throw OMP::Error::Authentication('Could not load authentication method class.')
        unless eval "require $provider_class";

    return $provider_class;
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
