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
use OMP::CGIComponent::Helper qw/start_form_absolute/;
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
  my @a = grep {$_ =~ /$sem/i} @sem;
  (!@a) and unshift @sem, $sem;

  # Add "Any" to semester list.
  unshift @sem, 'Any';

  # Get the telescopes for our popup menu
  my @tel = $db->listTelescopes;
  unshift @tel, "Any";

  my @support = $db->listSupport;
  my @sorted = sort {$a->userid cmp $b->userid} @support;
  my @values = map {$_->userid} @sorted;

  my %labels = map {$_->userid, $_} @support;
  $labels{dontcare} = "Any";
  unshift @values, 'dontcare';

  my @c = $db->listCountries;

  # Take serv out of the countries list
  my @countries = grep {$_ !~ /^serv$/i} @c;
  unshift @countries, 'Any';

  print "<table border=0><tr><td align=right>Semester: </td><td>";
  print start_form_absolute($q);
  print $q->hidden(-name=>'show_output',
                   -default=>1,);
  print $q->popup_menu(-name=>'semester',
                       -values=>\@sem,
                       -default=>uc($sem),);
  print "</td></tr><tr><td align='right'>Telescope: </td><td>";
  print $q->popup_menu(-name=>'telescope',
                       -values=>\@tel,
                       -default=>'Any',);
  print "</td></tr><tr><td align='right'>Show: </td><td>";
  print $q->radio_group(-name=>'status',
                        -values=>['active', 'inactive', 'all'],
                        -labels=>{active=>'Time remaining',
                                  inactive=>'No time remaining',
                                  all=>'Both',},
                        -default=>'active',);
  print "<br>";
  print $q->radio_group(-name=>'state',
                        -values=>[1,0,'all'],
                        -labels=>{1=>'Enabled',
                                  0=>'Disabled',
                                  all=>'Both',},
                        -default=>1,);
  print "</td></tr><tr><td align='right'>Support: </td><td>";
  print $q->popup_menu(-name=>'support',
                       -values=>\@values,
                       -labels=>\%labels,
                       -default=>'dontcare',);
  print "</td></tr><tr><td align='right'>Queue: </td><td>";
  print $q->popup_menu(-name=>'country',
                       -values=>\@countries,
                       -default=>'Any',);
  print "</td></tr><tr><td align='right'>Order by:</td><td colspan=2>";
  print $q->radio_group(-name=>'order',
                        -values=>['priority', 'projectid', 'adj-priority'],
                        -labels=>{priority => 'Priority',
                                  projectid => 'Project ID',
                                  'adj-priority' => 'Adjusted priority',},
                        -default=>'priority',);
  print "</td></tr><tr><td colspan=2>";
  print $q->checkbox(-name=>'table_format',
                     -value=>1,
                     -label=>'Display using tabular format',
                     -checked=>'true',);
  print "&nbsp;&nbsp;&nbsp;";
  print $q->submit(-name=>'Submit');
  print $q->end_form();
  print "</td></tr></table>";
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

  my $q = $self->cgi;

  my $url = OMP::Config->getData('cgidir');

  print <<'TABLE';
  <table cellspacing=0>
  <tr align=center>
  <td>Enabled(v) / Disabled(x)</td>
  <td>Project ID</td>
  <td>PI</td>
  <td>PI affiliation</td>
  <td>Support</td>
  <td># MSBs</td>
  <td>Priority</td>
  <td>Adjusted priority</td>
  <td>Allocated</td>
  <td>Completed</td>
  <td>Instruments</td>
  <td>Tau range</td>
  <td>Title</td>
  </tr>
TABLE

  my %bgcolor = (dark => "#6161aa",
                 light => "#8080cc",
                 disabled => "#e26868",
                 heading => "#c2c5ef",);

  # Images, with width & height, to distinguish between enabled & disabled
  # projects more easily than just by background colors.
  my $img_dir = OMP::Config->getData( 'iconsdir' );
  my %images = ( 'enabled' => [qw( tick-green-24.png 23 24 )],
                  'disabled' => [qw( cross-red-24.png 23 24 )]
                );

  my $rowclass = 'row_shaded';

  my $hsem;
  my $hcountry;

  # Count msbs for each project
  my @projectids = map {$_->projectid} @$projects;
  my %msbcount = OMP::MSBServer->getMSBCount(@projectids);

  #  XXX Just catch any errors thrown by OMP::SpServer->programInstruments.
  #  This try-catch should really be around the acutal usage of
  #  programInstruments(), but that may cause a slowdown when looped over many
  #  times.
  try {
    foreach my $project (@$projects) {

      if ($headings) {
        # If the country or semester for this project are different
        # than the previous project row, create a new heading

        if ($project->semester_ori ne $hsem or $project->country ne $hcountry) {
          $hsem = $project->semester_ori;
          $hcountry = $project->country;
          print "<tr bgcolor='$bgcolor{heading}'><td colspan=13>Semester: $hsem, Queue: $hcountry</td></td></tr>\n";
        }
      }

      # Get MSB counts
      my $nmsb = $msbcount{$project->projectid}{total};
      my $nremaining = $msbcount{$project->projectid}{active};
      (! defined $nmsb) and $nmsb = 0;
      (! defined $nremaining) and $nremaining = 0;

      my $adj_priority = '--';
      for ( $project ) {

        # Suppress printing of adjusted priority when it will be the same as
        # already assigned priority.
        if ( my $adj = $_->tagadjustment( $_->primaryqueue ) ) {

          $adj_priority = $_->tagpriority() + $adj;
        }
      }

      # Get seeing and tau info
      my $taurange = $project->taurange;

      $taurange = '--' if OMP::SiteQuality::is_default( 'TAU',$taurange );

      # programInstruments() may return empty array reference.
      my $instruments = OMP::SpServer->programInstruments( $project->projectid );

      my $support = join(", ", map {$_->userid} $project->support);

      # Make it noticeable if the project is disabled
      (! $project->state) and $rowclass = 'row_disabled';

      print "<tr class=${rowclass} valign=top>";

      my $status = !! $project->state ? 'enabled' : 'disabled';
      printf <<'STATUS',
        <td align="center" valign="top"><img
          alt="%s" src="%s" width="%d" height="%d"></td>
STATUS
        $status,
        File::Spec->catfile( $img_dir, $images{ $status }->[0] ),
        map { $images{ $status }->[ $_ ] } ( 1, 2 )
        ;

      print "<td><a href='$url/projecthome.pl?project=". $project->projectid ."'>". $project->projectid ."</a></td>";
      print "<td>". OMP::Display->userhtml($project->pi, $q, $project->contactable($project->pi->userid), $project->projectid) ."</td>";
      print '<td>'. ($project->pi->affiliation // '&nbsp;') . '</td>';
      print "<td>". $support ."</td>";
      print "<td align=center>$nremaining/$nmsb</td>";
      print "<td align=center>". $project->tagpriority ."</td>";
      print "<td align=center>". $adj_priority ."</td>";
      print "<td align=center>". $project->allocated->pretty_print ."</td>";
      print "<td align=center>". sprintf("%.0f",$project->percentComplete) . "%</td>";

      printf '<td align="center">%s</td>',
        scalar @{ $instruments } ? join '<br />', @{ $instruments }
          : '--' ;

      print "<td align=center>$taurange</td>";
      print "<td>". $project->title ."</td>";

      print "</tr>\n";

      # Alternate row class style
      ($rowclass eq 'row_shaded') and $rowclass = 'row_clear'
        or $rowclass = 'row_shaded';
    }
  }
  catch OMP::Error with { }
  otherwise { };

  print "</table>";

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
