package OMP::Auth::Legacy;

=head1 NAME

OMP::Auth::Legacy - User authentication via old project passwords

=cut

use strict;
use warnings;

use Net::LDAP;

use OMP::Config;
use OMP::DBbackend;
use OMP::Error;
use OMP::Password;
use OMP::UserDB;
use OMP::UserQuery;

use base qw/OMP::Auth::Base/;

=head1 METHODS

=head2 Class methods

=over 4

=item B<log_in_userpass>

Attempt to get a user object via legacy project passwords in the
archived "ompproj_old" table.

=cut

sub log_in_userpass {
    my $cls = shift;
    throw OMP::Error::Authentication('Invalid project.')
        unless shift =~ /^([a-zA-Z0-9\/]+)$/;
    my $project = uc($1);
    my $password = shift;

    my $db = new OMP::DBbackend();
    my $result = $db->handle()->selectall_arrayref(
        'SELECT pi, encrypted FROM ompproj_old WHERE projectid = ?', {}, $project);

    throw OMP::Error::Authentication('Project or password not found.')
        unless 1 == scalar @$result;

    my ($pi, $encrypted) = @{$result->[0]};

    my $verified = OMP::Password->verify_password($password, $encrypted, 'NONE', 1);

    throw OMP::Error::Authentication('Project or password not found.')
        unless $verified;

    my $udb = new OMP::UserDB(DB => $db);
    my $user = $udb->getUser($pi);

    throw OMP::Error::Authentication('No OMP account found for the PI of this project.')
        unless defined $user;

    return {user => $user, projects => [$project]};
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
