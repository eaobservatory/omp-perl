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

use OMP::CGIComponent::Helper qw/url_absolute/;
use OMP::DateTools;
use OMP::FindTarget;

use base qw/OMP::CGIPage/;

=head1 Subroutines

=over 4

=item B<find_targets>

Creates the find targets search page.

=cut

sub find_targets {
    my $self = shift;

    my $q = $self->cgi;

    return $self->_show_input_page()
        unless $q->param('submit_find');

    return {
        %{$self->_show_input_page()},
        %{$self->_show_output()},
    };
}

=back

=head2 Internal Subroutines

=over 4

=item _show_input_page

Outputs the input search form.

=cut

sub _show_input_page {
    my $self = shift;

    my $q = $self->cgi;

    return {
        target => url_absolute($q),
        values => {
            projid => (scalar $q->param('projid')),
            ra => (scalar $q->param('ra')),
            dec => (scalar $q->param('dec')),
            tel => (scalar $q->param('tel')) // 'JCMT',
            sep => (scalar $q->param('sep')),
            sem => (scalar $q->param('sem')),
        },
    };
}

=item _show_output

Outputs the search results.

=cut

sub _show_output {
    my $self = shift;

    my $q = $self->cgi;

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

    if ( $ra eq "" || $dec eq "" and $proj eq "" ) {
      push @msg, "Error: must specify a valid project or a RA,Dec!";
      push @msg, "RA, dec: '$rra', '$ddec'; Proj: '$prj'";
    }

    my ($targets, $results, $result_sep);
    unless (@msg) {
        ($targets, $result_sep) = OMP::FindTarget::find_targets(
            proj => $proj,
            ra   => $ra,
            dec  => $dec,
            sep  => $sep,
            sem  => $sem,
            tel  => $tel,
        );

        unless (scalar @$targets) {
            push @msg, 'No targets found.';
        }
        else {
            $results = [map {
                my ($ref, $proj, $target, $sep, $ra, $dec, $instr) = @$_;
                my $coord = new Astro::Coords(
                    ra => $ra, dec => $dec, type => 'J2000', units=> 'rad');
                {reference => $ref, project => $proj, target => $target, separation => $sep,
                ra => $coord->ra2000, dec => $coord->dec2000, instrument => $instr};
            } @$targets];
        }
    }

    return {
        messages => \@msg,
        results => $results,
        result_sep => $result_sep,
    };
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
