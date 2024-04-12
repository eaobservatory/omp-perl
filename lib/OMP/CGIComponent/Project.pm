package OMP::CGIComponent::Project;

=head1 NAME

OMP::CGIComponent::Project - Web display of project information

=head1 SYNOPSIS

    use OMP::CGIComponent::Project;

=head1 DESCRIPTION

Helper methods for creating web pages that display project
information.

=cut

use 5.006;
use strict;
use warnings;
use Carp;

use OMP::Config;
use OMP::Display;
use OMP::Error qw/:try/;
use OMP::Constants qw/:status/;
use OMP::DateTools;
use OMP::DB::MSB;
use OMP::General;
use OMP::MSBServer;
use OMP::ProjDB;

use File::Spec;

use base qw/OMP::CGIComponent/;

$| = 1;

=head1 Routines

=over 4

=item B<list_projects_form>

Create a form for taking the semester parameter

    $comp->list_projects_form(telescope => $telescope);

=cut

sub list_projects_form {
    my $self = shift;
    my %opt = @_;

    my $q = $self->cgi;
    my $telescope = $opt{'telescope'};

    my $db = OMP::ProjDB->new(DB => $self->database);

    # get the current semester for the default telescope case
    # so it can be defaulted in addition to the list of all semesters
    # in the database
    my $sem = OMP::DateTools->determine_semester;
    my @sem = $db->listSemesters(telescope => $telescope);

    # Make sure the current semester is a selectable option
    push @sem, $sem unless grep {$_ =~ /$sem/i} @sem;

    my @support =
        sort {$a->[0] cmp $b->[0]}
        map {[$_->userid, $_->name]}
        $db->listSupport;

    # Take serv out of the countries list
    my @countries = grep {$_ !~ /^serv$/i}
        $db->listCountries(telescope => $telescope);
    push @countries, 'PI+IF';

    return {
        target => $self->page->url_absolute(),
        semesters => [sort @sem],
        semester_selected => $sem,
        statuses => [
            [active => 'Time remaining'],
            [inactive => 'No time remaining'],
            [all => 'Both'],
        ],
        states => [
            [1 => 'Enabled'],
            [0 => 'Disabled'],
            [all => 'Both'],
        ],
        supports => \@support,
        countries => [sort @countries],
        orders => [
            [priority => 'Priority'],
            [projectid => 'Project ID'],
            ['adj-priority' => 'Adjusted priority'],
        ],
        values => {
            semester => $sem,
        },
    };
}

=item B<proj_sum_table>

Display details for multiple projects in a tabular format.

    $comp->proj_sum_table($projects, $headings);

If the third argument is true, table headings for semester and
country will appear.

=cut

sub proj_sum_table {
    my $self = shift;
    my $projects = shift;
    my $headings = shift;

    # Count msbs for each project
    my $msbdb = OMP::DB::MSB->new(DB => $self->database);

    my $proj_msbcount = {};
    my $proj_instruments = {};
    try {
        my @projectids = map {$_->projectid} @$projects;
        $proj_msbcount = $msbdb->getMSBCount(@projectids);
        $proj_instruments = $msbdb->getInstruments(@projectids);
    }
    catch OMP::Error with {
    }
    otherwise {
    };

    return {
        results => $projects,
        show_headings => $headings,
        project_msbcount => $proj_msbcount,
        project_instruments => $proj_instruments,
        taurange_is_default => sub {
            return OMP::SiteQuality::is_default('TAU', $_[0]);
        },
    };
}

1;

__END__

=back

=head1 SEE ALSO

C<OMP::CGI::ProjectPage>

=head1 AUTHOR

Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2004 Particle Physics and Astronomy Research Council.
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
