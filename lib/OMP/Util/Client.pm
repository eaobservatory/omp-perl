package OMP::Util::Client;

=head1 NAME

OMP::Util::Client - Utility methods for OMP client applications

=head1 SYNOPSIS

    use OMP::Util::Client;

=head1 DESCRIPTION

Common methods for clients.

=cut

use strict;
use warnings;
use warnings::register;

use OMP::Config;
use OMP::Error qw/:try/;
use OMP::DB::User;

=head1 METHODS

=over 4

=item B<determine_tel>

Return the telescope name to use in the current environment.
This is usally obtained from the config system but if the config
system returns a choice of telescopes a Tk window will popup
requesting that the specific telescope be chosen.

If no Tk window reference is supplied, and multiple telescopes
are available, returns all the telescopes (either as a list
in list context or an array ref in scalar context). ie, if called
with a Tk widget, guarantees to return a single telescope, if called
without a Tk widget is identical to querying the config system directly.

    $tel = OMP::Util::Client->determine_tel($MW);

Returns undef if the user presses the "cancel" button when prompted
for a telescope selection.

If a Term::ReadLine object is provided, the routine will prompt for
a telescope if there is a choice. This has the same behaviour as for the
Tk option. Returns undef if the telescope was not valid after a prompt.

=cut

sub determine_tel {
    my $class = shift;
    my $w = shift;

    my $tel = OMP::Config->getData('defaulttel');

    my $telescope;
    if (ref($tel) eq "ARRAY") {
        unless (defined $w) {
            # Have no choice but to return the array
            if (wantarray) {
                return @$tel;
            }
            else {
                return $tel;
            }
        }
        elsif (UNIVERSAL::isa($w, "Term::ReadLine")
                || UNIVERSAL::isa($w, "Term::ReadLine::Perl")) {
            # Prompt for it
            my $res = $w->readline("Which telescope [" . join(",", @$tel) . "] : ");
            $res = uc($res);
            if (grep /^$res$/i, @$tel) {
                return $res;
            }
            else {
                # no match
                return ();
            }
        }
        else {
            # Can put up a widget
            require Tk::DialogBox;

            my $newtel;
            my $dbox = $w->DialogBox(
                -title => "Select telescope",
                -buttons => ["Accept", "Cancel"],
            );
            my $txt = $dbox->add(
                'Label',
                -text => "Select telescope for obslog",
            )->pack;

            foreach my $ttel (@$tel) {
                my $rad = $dbox->add(
                    'Radiobutton',
                    -text => $ttel,
                    -value => $ttel,
                    -variable => \$newtel,
                )->pack;
            }

            my $but = $dbox->Show;

            if ($but eq 'Accept' && $newtel ne '') {
                $telescope = uc($newtel);
            }
            else {
                # Pressed cancel
                return ();
            }
        }
    }
    else {
        $telescope = uc($tel);
    }

    return $telescope;
}

=item B<determine_user>

See if the user ID can be guessed from the system environment
without asking for it.

    $user = OMP::Util::Client->determine_user($database);

Uses the C<$USER> environment variable for the first guess. If that
is not available or is not verified as a valid user the method either
returns C<undef> or, if the optional widget object is supplied,
popups up a Tk dialog box requesting input from the user.

    $user = OMP::Util::Client->determine_user($database, $MW);

If the userid supplied via the widget is still not valid, give
up and return undef.

Returns the user as an OMP::User object.

=cut

sub determine_user {
    my $class = shift;
    my $db = shift;
    die 'A database backend must be provided'
        unless (defined $db) && eval {$db->isa('OMP::DB::Backend')};
    my $w = shift;

    my $udb = OMP::DB::User->new(DB => $db);

    my $user;
    if (exists $ENV{USER}) {
        $user = $udb->getUser($ENV{USER});
    }

    unless ($user) {
        # no user so far so if we have a widget popup dialog
        if ($w) {
            require Tk::DialogBox;
            require Tk::LabEntry;

            while (! defined $user) {
                my $dbox = $w->DialogBox(
                    -title => "Request OMP user ID",
                    -buttons => ["Accept", "Don't Know"],
                );
                my $ent = $dbox->add(
                    'LabEntry',
                    -label => "Enter your OMP User ID:",
                    -width => 15
                )->pack;

                my $but = $dbox->Show;

                if ($but eq 'Accept') {
                    my $id = $ent->get;

                    # Catch any errors that might pop up.
                    try {
                        $user = $udb->getUser($id);
                    }
                    catch OMP::Error with {
                        my $Error = shift;

                        my $dbox2 = $w->DialogBox(
                            -title => "Error",
                            -buttons => ["OK"],
                        );
                        my $label =
                            $dbox2->add('Label',
                            -text => "Error: " . $Error->{-text},
                        )->pack;

                        my $but2 = $dbox2->Show;
                    }
                    otherwise {
                        my $Error = shift;

                        my $dbox2 = $w->DialogBox(
                            -title => "Error",
                            -buttons => ["OK"],
                        );
                        my $label =
                            $dbox2->add('Label',
                            -text => "Error: " . $Error->{-text},
                        )->pack;

                        my $but2 = $dbox2->Show;
                    };
                    if (defined($user)) {
                        last;
                    }
                }
                else {
                    last;
                }
            }
        }
    }

    return $user;
}

1;

__END__

=back

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>,
Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>,
Anubhav AgarwalE<lt>a.agarwal@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2007 Science and Technology Facilities Council.
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
