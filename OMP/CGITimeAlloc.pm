package OMP::CGITimeAlloc;

use 5.006;
use strict;
use warnings;
use Carp;
our $VERSION = (qw$ Revision: $ )[1];

use OMP::CGI;
use OMP::TimeAcctDB;
use OMP::Project::TimeAcct;
use OMP::Error qw(:try);

use vars qw/@ISA %EXPORT_TAGS @EXPORT_OK/;

require Exporter;

$| = 1;

@ISA = qw/Exporter/;

@EXPORT_OK = (qw/timealloc timealloc_output/);

%EXPORT_TAGS = (
                'all' => [ @EXPORT_OK ],
               );

Exporter::export_tags(qw/ all /);

=head1 Routines

=over 4

=item B<timealloc>

Creates a page with a form for filling in time allocations for a night.

  timealloc( $cgi );

Only argument should be the C<CGI> object.

=cut

sub timealloc {
  my $q = shift;
  my %cookie = @_;

  display_form( $q );

}

=item B<timealloc_output>

Submits time allocations for a night, and creates a page with a form for
filling in time allocations for a night time allocations.

  timealloc_output( $cgi );

Only argument should be the C<CGI> object.

=cut

sub timealloc_output {
  my $q = shift;
  my %cookie = @_;

  submit_allocations( $q );

  display_form( $q );

}

=item B<display_form>

Display a form for time allocations.

  display_form( $q );

The optional parameter should be the C<CGI> object.

=cut

sub display_form {
  my $q = shift;

  my $faultproj;
  my $weatherproj;
  my $otherproj;

  # Retrieve the projects displayed on the UT date given in the query
  # object. If no such UT date is given, use the current UT date.
  my $ut;
  if( defined( $q->{'ut'} ) &&
     $q->{'ut'} =~ /(\d{4}-\d\d-\d\d)/ ) {
    $ut = $1; # This removes taint from the UT date given.
  } else {
    my ($sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdist) = gmtime(time);
    $ut = ($year + 1900) . "-" . pad($month + 1, "0", 2) . "-" . pad($day, "0", 2);
  }

$ut = "2002-08-29";

  my $dbconnection = new OMP::DBbackend;
  my $db = new OMP::TimeAcctDB( DB => $dbconnection );
  my @accounts = $db->getTimeSpent( utdate => $ut );

  # Print a header.
  print "For UT $ut the following projects were observed:<br>\n";
  print $q->startform;
  print "<table>";
  print "<tr><th>Project</th><th>Hours</th><th>Status</th></tr>\n";
  # For each TimeAcct object, print a form entry.
  my $i = 1;
  foreach my $timeacct (@accounts) {
    if($timeacct->projectid =~ /FAULT/) {
      $faultproj = $timeacct;
      next;
    }
    if($timeacct->projectid =~ /WEATHER/) {
      $weatherproj = $timeacct;
      next;
    }
    if($timeacct->projectid =~ /OTHER/) {
      $otherproj = $timeacct;
      next;
    }
    print "<tr><td>";
    print $timeacct->projectid;
    print "</td><td>";
    print $q->textfield( -name => 'hour' . $i,
                         -size => '8',
                         -maxlength => '16',
                         -default => $timeacct->timespent->hours,
                       );
    print "</td><td>";
    print ($timeacct->confirmed ? "Confirmed" : "Estimated");
    print $q->hidden( -name => 'project' . $i,
                      -default => $timeacct->projectid,
                    );
    print "</td></tr>\n";
    $i++;
  }
  print "</table>";
  print $q->submit( -name => 'CONFIRM APPORTIONING' );
  print $q->endform;

  # Display miscellaneous time form (faults, weather, other).
  print "Time lost to faults: ";
  print ( defined( $faultproj ) ? $faultproj->timespent->hours : "0" );
  print " hours<br>\n";
  print "Time lost to weather: ";
  print ( defined( $weatherproj ) ? $weatherproj->timespent->hours : "0" );
  print " hours<br>\n";
  print "Other time lost: ";
  print ( defined( $otherproj ) ? $otherproj->timespent->hours : "0" );
  print " hours<br>\n";

}

sub submit_allocations {
  my $q = shift;

  # Grab the UT date from the query object. If it does not exist,
  # default to the current UT date.
  my $ut;
  if( defined( $q->{'ut'} ) &&
     $q->{'ut'} =~ /(\d{4}-\d\d-\d\d)/ ) {
    $ut = $1; # This removes taint from the UT date given.
  } else {
    my ($sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdist) = gmtime(time);
    $ut = ($year + 1900) . "-" . pad($month + 1, "0", 2) . "-" . pad($day, "0", 2);
  }

  # Build a hash with keys of project IDs and values of hours
  # allocated to those project IDs.
  my %timealloc;
  my $i = 1;
  while ( defined( $q->{'project' . $i} ) ) {
    $timealloc{$q->{'project' . $i}} = $q->{'hour' . $i};
    $i++;
  }

  # Create an array of OMP::Project::TimeAcct objects
  my @acct;
  foreach my $projectid (keys %timealloc) {
    my $t = new OMP::Project::TimeAcct( projectid => $projectid,
                                        date => OMP::General->parse_date($ut),
                                        timespent => new Time::Seconds( $timealloc{$projectid} * 3600 ),
                                      );
    push @acct, $t;
  }
  my $dbconnection = new OMP::DBbackend;
  my $db = new OMP::TimeAcctDB( DB => $dbconnection );
  $db->setTimeSpent( @acct );
}

sub pad {
  my ($string, $character, $endlength) = @_;
  my $result = ($character x ($endlength - length($string))) . $string;
}

1;
