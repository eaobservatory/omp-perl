package OMP::Auth::Base;

=head1 NAME

OMP::Auth::Base - Base class for user authentication modules

=cut

use strict;
use warnings;

use OMP::Error;

=head1 METHODS

=head2 Class methods

=over 4

=item B<log_in>

Attempt to get an OMP::User object representing the user logging in,
using information from an OMP::CGIPage object.  Returned as a hash, perhaps
including a 'user' key.

    my $user_info = $provider_class->log_in($page);

This base class implementation calls L<log_in_userpass> using the
C<username> and C<password> CGI parameters.

=cut

sub log_in {
    my $cls = shift;
    my $page = shift;

    my $q = $page->cgi;

    my $user_info = $cls->log_in_userpass(
        (scalar $q->param('username')), (scalar $q->param('password')));

    if (exists $user_info->{'user'}) {
        $user_info->{'duration'} = (scalar $q->param('remember_me')
            ? 'remember' : 'default');
    }

    return $user_info;
}

=item B<log_in_userpass>

Attempt to get an OMP::User object representing the user logging in
with a specific user name and password.  Returned as a hash, perhaps
including a 'user' key.

    my $user_info = $provider_class->log_in_userpass($username, $password);

=cut

sub log_in_userpass {
    my $cls = shift;

    throw OMP::Error::Authentication(
        'This authentication method can not use username and password.');
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
