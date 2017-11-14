package OMP::CGIPage::FindTarget;

=head1 NAME

OMP::CGIPage::FindTarget - Find targets in OMP database

=head1 DESCRIPTION

Performs a pencil-beam search for targets around a specified position or
around targets from a specified projects.

Perl wrapper to generate an HTML access page. The actual search is
done by the OMP::FindTarget module.

=cut

use strict;

use CGI;
use CGI::Carp qw/fatalsToBrowser/;

use OMP::DateTools;
use OMP::FindTarget qw/find_and_display_targets/;

=head1 Subroutines

=over 4

=item B<find_targets>

Creates the find targets search page.

=cut

sub find_targets {
    my $q = shift;
    my %cookie = @_;

    _show_input_page($q);
}

=item B<find_targets_output>

Outputs the list of targets.

=cut

sub find_targets_output {
    my $q = shift;
    my %cookie = @_;

    _show_input_page($q);
    _show_output($q);
}

=back

=head2 Internal Subroutines

=over 4

=item _show_input_page

Outputs the input search form.

=cut

sub _show_input_page {
    my $q = shift;

    print
        $q->p(
            'Perform a pencil-beam search for targets around a specified',
            'position or around targets from a specified projects.',
        ),
        $q->start_form(),
        $q->table(
            $q->Tr([
                $q->td([
                    'Project(s)',
                    $q->textfield(-name => 'projid', -size => 16),
                    '(No default)',
                ]),
                $q->td('&nbsp;') .
                    $q->td({-align => 'center'}, 'or') .
                    $q->td('&nbsp;'),
                $q->td([
                    'RA',
                    $q->textfield(-name => 'ra', -size => 16),
                    '(dd:am:as.s No default)',
                ]),
                $q->td([
                    'Dec',
                    $q->textfield(-name => 'dec', -size => 16),
                    '(dd:am:as.s No default)',
                ]),
                $q->td({-colspan => 3}, '&nbsp;'),
                $q->td('Telescope') . $q->td({-colspan => 2},
                    $q->radio_group(
                        -name => 'tel',
                        -values => ['UKIRT', 'JCMT'],
                        -default => 'UKIRT',
                    ),
                ),
                $q->td([
                    'Max. separation',
                    $q->textfield(-name => 'sep', -size => 16),
                    '(600 arcsec)',
                ]),
                $q->td([
                    'Semester',
                    $q->textfield(-name => 'sem', -size => 16),
                    '(current)',
                ]),
            ]),
        ),
        $q->p(
            $q->hidden(-name => 'show_output', -value => 'true'),
            $q->submit(-value => 'Find targets')),
        $q->end_form();
}

=item _show_output

Outputs the search results.

=cut

sub _show_output {
    my $q = shift;

    my @msg = (); # Message buffer.

    my ($ra, $dec, $sep, $proj, $tel, $sem);

    # Project:
    my $prj = $q->param('projid');
    ($prj =~ /^([\w\/\*]+)$/ ) &&  ($proj = "$1") || ($proj = "");

    # RA
    my $rra = $q->param('ra');
    $rra =~ s/\ /\:/g;
    $rra =~ s/^\s+//;
    $rra =~ s/\s+$//;
    ($proj eq "" && $rra =~ /^([\d\:\.\ ]+)$/) && ($ra = "$1") || ($ra = "");

    # Dec
    my $ddec = $q->param('dec');
    $ddec =~ s/\ /\:/g;
    $ddec =~ s/^\s+//;
    $ddec =~ s/\s+$//;
    ($proj eq "" && $ddec =~ /^([\d\-\:\.\ ]+)$/) && ($dec = "$1") || ($dec = "");

    # Telescope
    my $ttel = $q->param('tel');
    ( $ttel =~ /^(\w+)$/ ) && ($tel = $ttel) || ($tel = "");

    # Separation
    my $ssep = $q->param('sep');
    ( $ssep =~ /^(\d+)$/ ) && ($sep = $ssep) || ($sep = "600");

    # Semester
    my $ssem= $q->param('sem');
    ( $ssem =~ /^([\w\d\*]+)$/ ) && ($sem = $ssem) || ($sem = OMP::DateTools->determine_semester(tel => $tel));
    $sem =~ s/^m//i;

    if ( $ra eq "" && $dec eq "" &&  $proj eq "" ) {
      push @msg, "***ERROR*** must specify a valid project or a RA,Dec!";
      push @msg, "RA, dec: '$rra', '$ddec'; Proj: '$prj'";
    }

    if (@msg) {
        print $q->p(\@msg);
    }
    else {
        print $q->start_p(), $q->start_pre();

        find_and_display_targets(
            proj => $proj,
            ra   => $ra,
            dec  => $dec,
            sep  => $sep,
            sem  => $sem,
            tel  => $tel,
        );

        print $q->end_pre(), $q->end_p();
    }
}

1;

__END__

=back

=head1 AUTHOR

Remo Tilanus, Joint Astronomy Centre E<lt>r.tilanus@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2004 Particle Physics and Astronomy Research Council.
Copyright (C) 2015 East Asian Observatory.
All Rights Reserved.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful,but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc., 59 Temple
Place, Suite 330, Boston, MA  02111-1307, USA
