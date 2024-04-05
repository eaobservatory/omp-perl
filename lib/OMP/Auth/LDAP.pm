package OMP::Auth::LDAP;

=head1 NAME

OMP::Auth::LDAP - User authentication via LDAP

=cut

use strict;
use warnings;

use Net::LDAP;

use OMP::Config;
use OMP::DB::Backend;
use OMP::Error;
use OMP::UserDB;
use OMP::UserQuery;

use base qw/OMP::Auth::Base/;

=head1 METHODS

=head2 Class methods

=over 4

=item B<log_in_userpass>

Attempt to get a user object by logging in via LDAP:

=over 4

=item The name and password are checked using LDAP.

=item The user database is searched for this name as an alias.

=back

It is assumed that anyone authenticated in this manner
is a staff member.

=cut

sub log_in_userpass {
    my $cls = shift;
    throw OMP::Error::Authentication('Invalid username.')
        unless shift =~ /^([a-zA-Z]+)$/;
    my $username = lc($1);
    my $password = shift;

    my $ldap_url = OMP::Config->getData('auth_ldap.url');
    my $dn = join ',', ('uid=' . $username), OMP::Config->getData('auth_ldap.dn_suffix');
    my $sleep = OMP::Config->getData('auth_ldap.sleep');
    sleep $sleep if $sleep;

    my $ldap = Net::LDAP->new($ldap_url);
    my $mess = $ldap->bind($dn, password => $password);

    throw OMP::Error::Authentication('Username or password not recognized.')
        if $mess->code;

    my $db = OMP::UserDB->new(DB => OMP::DB::Backend->new());
    my @result = $db->queryUsers(OMP::UserQuery->new(HASH => {
        alias => $username,
        obfuscated => {boolean => 0},
    }));

    throw OMP::Error::Authentication('Could not find an OMP alias associated with your account.')
        unless @result;

    throw OMP::Error::Authentication('Multiple OMP aliases were found for your account!')
        if 1 < scalar @result;

    my $result = $result[0];
    $result->is_staff(1);
    return {user => $result};
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
