package OMP::CGIHelper;

=head1 NAME

OMP::CGIHelper - Helper for the OMP feedback system CGI scripts

=head1 SYNOPSIS

  use OMP::CGIHelper;
  use OMP::CGIHelper qw/proj_status_table/;

=head1 DESCRIPTION

Provide functions to generate commonly displayed items for the feedback
system CGI scripts, such as a table containing information on the current
status of a project.

=cut

use 5.006;
use strict;
use warnings;
use Carp;
our $VERSION = (qw$ Revision: 1.2 $ )[1];

use lib qw(/jac_sw/omp/msbserver);
use OMP::ProjServer;
use OMP::SpServer;
use OMP::FBServer;

use vars qw/@ISA %EXPORT_TAGS @EXPORT_OK/;

require Exporter;

@ISA = qw/Exporter/;

@EXPORT_OK = (qw/fb_output/);

%EXPORT_TAGS = (
		'all' =>[ @EXPORT_OK ],
	       );

Exporter::export_tags(qw/ all /);

=head1 Routines

=over 4

=item B<proj_status_table>

Creates an HTML table containing information relevant to the status of
a project.

proj_status_table( $cgi, %cookie);

First argument should be the C<CGI> object.  The second argument
should be a hash containing the contents of the C<OMP::Cookie> cookie
object.

=cut

sub proj_status_table {
  my $q = shift;
  my %cookie = @_;

  # Get the project details
  my $project = OMP::ProjServer->projectDetails( $cookie{projectid},
						 $cookie{password},
						 'object' );

  my %summary;
  foreach (qw/pi piemail title projectid coi coiemail allocated remaining country/) {
    $summary{$_} = $project->$_;
  }

  print $q->h2("Current project status"),
        "<table border='1' width='100%'><tr bgcolor='#7979aa'>",
	"<td><b>PI:</b> <a href='mailto:$summary{piemail}'>$summary{pi}</a></td>",
	"<td colspan=2><b>Title:</b> $summary{title}</td>",
	"<td><b>Science Case:</b> </td>",
	"<tr bgcolor='#7979aa'><td><b>CoI: </b> <a href='mailto:$summary{coiemail}'>$summary{coi}</a></td>",
        "<td><b>Time allocated:</b> $summary{allocated}</td>",
	"<td><b>Time Remaining:</b> $summary{remaining}",
	"<td><b>Country:</b> $summary{country} </td>",
        "</table><p>";
}

=item B<msb_sum_hidden>

Creates text showing current number of msbs, but not actually display the
program details.

msb_sum_hidden($cgi, %cookie);

=cut

sub msb_sum_hidden {
  my $q = shift;
  my %cookie = @_;

  my $sp;
  eval {
    $sp = OMP::SpServer->programDetails($cookie{projectid},
					$cookie{password},
					'data' );
  };

  if ($@) {
    print "Error obtaining science program details<$@>";
    $sp = [];
  }

  print $q->h2("Current MSB status"),
        scalar(@$sp). " MSBs currently stored in database. Click <a href='feedback.pl?msb=1'>here</a> to list them all.",
	$q->hr;

}

=item B<fb_entries>

Get the feedback entries and display them

fb_entries($cgi, %cookie);

=cut

sub fb_entries {
  my $q = shift;
  my %cookie = @_;

  my $comments = OMP::FBServer->getComments( $cookie{projectid},
					     $cookie{password} );

  print $q->h2("Feedback entries"),
        "<a href='feedback.pl?comment=1'>Add a comment</a>",
	$q->p;

  my $i = 1;
  foreach my $row (@$comments) {
    print "<font size=+1>Entry $i (on $row->{'date'} by $row->{'author'})</b></font>",
          $q->p,
          "$row->{'text'}",
	  $q->p;
    $i++;
  }

}

=item B<fb_output>

Creates the page showing feedback entries.

fb_output($cgi, %cookie);

=cut

sub fb_output {
  my $q = shift;
  my %cookie = @_;

  print  $q->h1("Feedback for project $cookie{projectid}");

  proj_status_table($q, %cookie);
  msb_sum_hidden($q, %cookie);
  fb_entries($q, %cookie);
}


=back

=head1 AUTHORS

Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>,
Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=cut

1;
