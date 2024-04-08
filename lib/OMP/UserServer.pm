package OMP::UserServer;

=head1 NAME

OMP::UserServer - OMP user information server class

=head1 SYNOPSIS

    OMP::UserServer->getUser($userid);

=head1 DESCRIPTION

This class provides the public server interface for the OMP user
database system.

This class is intended for use as a stateless server. State is
maintained in external databases. All methods are class methods.

=cut

use strict;
use warnings;
use Carp;
use List::Util qw/first/;

# OMP dependencies
use OMP::UserDB;
use OMP::User;
use OMP::UserQuery;
use OMP::Error qw/:try/;

# Inherit server specific class
use base qw/OMP::SOAPServer/;

our $VERSION = '2.000';

=head1 METHODS

=over 4

=item B<verifyUser>

Verify the specified user exists on the system.

    $isthere = OMP::UserServer->verifyUser($userid);

=cut

sub verifyUser {
    my $class = shift;
    my $userid = shift;

    my $status;
    my $E;
    try {
        my $db = OMP::UserDB->new(DB => $class->dbConnection);

        $status = $db->verifyUser($userid);
    }
    catch OMP::Error with {
        # Just catch OMP::Error exceptions
        # Server infrastructure should catch everything else
        $E = shift;
    }
    otherwise {
        # This is "normal" errors. At the moment treat them like any other
        $E = shift;
    };

    # This has to be outside the catch block else we get
    # a problem where we cant use die (it becomes throw)
    $class->throwException($E) if defined $E;

    return $status;
}

=item B<verifyUserExpensive>

Verify the specified user exists on the system, given any one of the
attributes to check.  If more than one attribute is given, then all of
them will be checked independently of each other.

    $isthere = OMP::UserServer->verifyUserExpensive(
        'name' => 'user name',
        'email' => 'email@example.org',
        'userid' => 'userid');

Known attributes are: name, email, userid, alias, cadcid.

=cut

sub verifyUserExpensive {
    my $class = shift;
    my %attr = @_;

    $attr{'cadcuser'} = delete $attr{'cadc'}
        if exists $attr{'cadc'};

    my @status;
    my $E;
    try {
        my $db = OMP::UserDB->new(DB => $class->dbConnection);

        @status = $db->verifyUserExpensive(%attr);
    }
    catch OMP::Error with {
        $E = shift;
    }
    otherwise {
        # This is "normal" errors. At the moment treat them like any other
        $E = shift;
    };

    # This has to be outside the catch block else we get
    # a problem where we cant use die (it becomes throw)
    $class->throwException($E) if defined $E;

    return @status;
}

=item B<getUser>

Get the specified user information.

    $user = OMP::UserServer->getUser($userid);

This is not SOAP friendly. The user information is returned as an C<OMP::User>
object.

=cut

sub getUser {
    my $class = shift;
    my $userid = shift;

    my $user;
    my $E;
    try {
        my $db = OMP::UserDB->new(DB => $class->dbConnection);

        $user = $db->getUser($userid);
    }
    catch OMP::Error with {
        # Just catch OMP::Error exceptions
        # Server infrastructure should catch everything else
        $E = shift;
    }
    otherwise {
        # This is "normal" errors. At the moment treat them like any other
        $E = shift;
    };

    # This has to be outside the catch block else we get
    # a problem where we cant use die (it becomes throw)
    $class->throwException($E) if defined $E;

    return $user;
}

=item B<getUserExpensive>

Verify the specified user exists on the system, given any one of the
attributes to check.  If more than one attribute is given, then all of
them will be checked independently of each other.

    $isthere = OMP::UserServer->getUserExpensive(
        'name' => 'user name',
        'email' => 'email@example.org',
        'userid' => 'userid');

Known attributes are: name, email, userid, alias, cadcid.

=cut

sub getUserExpensive {
    my $class = shift;
    my %attr = @_;

    $attr{'cadcuser'} = delete $attr{'cadc'}
        if exists $attr{'cadc'};

    my @user;
    my $E;
    try {
        my $db = OMP::UserDB->new('DB' => $class->dbConnection);

        @user = $db->getUserExpensive(%attr);
    }
    catch OMP::Error with {
        # Just catch OMP::Error exceptions
        # Server infrastructure should catch everything else
        $E = shift;
    }
    otherwise {
        # This is "normal" errors. At the moment treat them like any other
        $E = shift;
    };

    # This has to be outside the catch block else we get
    # a problem where we cant use die (it becomes throw)
    $class->throwException($E) if defined $E;

    return @user;
}

1;

__END__

=back

=head1 SEE ALSO

L<OMP::ProjServer>, L<OMP::User>, L<OMP::UserDB>.

=head1 COPYRIGHT

Copyright (C) 2001-2008 Science and Technology Facilities Council.
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

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

Anubhav E<lt>a.agarwal@jach.hawaii.eduE<gt>

=cut
