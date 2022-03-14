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
use OMP::CGIComponent::Helper qw/start_form_absolute url_absolute/;
use OMP::Display;
use OMP::Error qw/ :try /;
use OMP::Constants qw/ :status /;
use OMP::DateTools;
use OMP::General;
use OMP::MSBServer;
use OMP::ProjDB;
use OMP::ProjServer;

use File::Spec;

use base qw/OMP::CGIComponent/;

$| = 1;

=head1 Routines

=over 4

=item B<list_project_form>

Create a form for taking the semester parameter

  $comp->list_projects_form();

=cut

sub list_projects_form {
  my $self = shift;

  my $q = $self->cgi;

  my $db = new OMP::ProjDB( DB => OMP::DBServer->dbConnection, );

  # get the current semester for the default telescope case
  # so it can be defaulted in addition to the list of all semesters
  # in the database
  my $sem = OMP::DateTools->determine_semester;
  my @sem = $db->listSemesters;

  # Make sure the current semester is a selectable option
  push @sem, $sem unless grep {$_ =~ /$sem/i} @sem;

  # Get the telescopes for our popup menu
  my @tel = $db->listTelescopes;

  my @support =
    sort {$a->[0] cmp $b->[0]}
    map {[$_->userid, $_->name]}
    $db->listSupport;

  # Take serv out of the countries list
  my @countries = grep {$_ !~ /^serv$/i} $db->listCountries;
  push @countries, 'PI+IF';

  return {
    target => url_absolute($q),
    semesters => [sort @sem],
    semester_selected => $sem,
    telescopes => [sort @tel],
    statuses => [
        [active => 'Time remaining'],
        [inactive => 'No time remaining'],
        [all => 'Both'],
    ],
    states => [
        [1 =>'Enabled'],
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
  }
}

=item B<proj_status_table>

Creates an HTML table containing information relevant to the status of
a project.

  $comp->proj_status_table( $projectid );

=cut

sub proj_status_table {
  my $self = shift;
  my $projectid = shift;

  my $q = $self->cgi;

  # Get the project details
  my $project = OMP::ProjServer->projectDetails( $projectid,
                                                 'object' );

  # Link to the science case
  my $url = OMP::Config->getData( 'cgidir' );
  my $case_href = qq[<a href="$url/props.pl?project=$projectid">Science Case</a>];

  # Get the CoI email(s)
  my $coiemail = join(", ",map{
    OMP::Display->userhtml($_, $q, $project->contactable($_->userid), $project->projectid,
      affiliation => $_->affiliation(),
      access => $project->omp_access($_->userid))
    } $project->coi);

  # Get the support
  my $supportemail = join(", ",map{OMP::Display->userhtml($_, $q)} $project->support);

  print "<table class='infobox' cellspacing=1 cellpadding=2 width='100%'>",
        "<tr>",
        "<td><b>PI:</b>".OMP::Display->userhtml($project->pi, $q, $project->contactable($project->pi->userid), $project->projectid, affiliation => $project->pi()->affiliation(), access => $project->omp_access($project->pi->userid))."</td>",
        "<td><b>Title:</b> " . $project->title . "</td>",
        "<td> $case_href </td></tr>",
        "<tr><td colspan='2'><b>CoI:</b> $coiemail</td>",
        "<td><b>Staff Contact:</b> $supportemail</td></tr>",
        "<tr><td><b>Time allocated:</b> " . $project->allocated->pretty_print . "</td>",
        "<td><b>Time Remaining:</b> " . $project->allRemaining->pretty_print . "</td>",
        "<td><b>Queue:</b>" . $project->country . "</td></tr>",
        "</table><p>";
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
  my $proj_msbcount = {};
  my $proj_instruments = {};
  try {
    my @projectids = map {$_->projectid} @$projects;
    $proj_msbcount = OMP::MSBServer->getMSBCount(@projectids);
    $proj_instruments = OMP::SpServer->programInstruments(@projectids);
  }
  catch OMP::Error with { }
  otherwise { };

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

=item B<obtain_projectid>

Provide a form for obtaining a project ID, and process the output, catching
invalid project IDs.

  $comp->obtain_projectid();

Returns a project ID.

=cut

sub obtain_projectid {
  my $self = shift;

  my $q = $self->cgi;

  # Obtain project ID from query parameter list, otherwise display a form
  # requesting the project ID.
  unless ($q->param('project')) {
    $self->projectid_form();
    return;
  }

  my $projectid = $q->param('project');

  # Verify project ID
  my $verify = OMP::ProjServer->verifyProject( $projectid );

  # Display project ID form again if given ID was invalid
  unless ($verify) {
    print "The project ID you provided [$projectid] was invalid.<br><br>";
    $self->projectid_form();
    return;
  }

  return $projectid;
}

=item B<projectid_form>

Display a form which takes a project ID.

  $comp->projectid_form();

=cut

sub projectid_form {
  my $self = shift;

  my $q = $self->cgi;

  print start_form_absolute($q);
  print "Project ID: ";
  print $q->textfield(-name=>"project",
                      -size=>12,
                      -maxlength=>32,);
  print "&nbsp;";
  print $q->submit(-name=>"project_submit",
                   -label=>"Submit",);
}

=head1 SEE ALSO

C<OMP::CGI::ProjectPage>

=back

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

1;
