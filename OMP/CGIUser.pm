package OMP::CGIUser;

=head1 NAME

OMP::CGIHelper - Helper for the OMP user details CGI scripts

=head1 SYNOPSIS

  use OMP::CGIUser;
  use OMP::CGIUser qw/details/;

=head1 DESCRIPTION

Provide functions to generate the OMP user details CGI scripts.

=cut

use 5.006;
use strict;
use warnings;
use Carp;
our $VERSION = (qw$ Revision: 1.2 $ )[1];

use OMP::CGI;
use OMP::Config;
use OMP::DBbackend;
use OMP::Error qw(:try);
use OMP::General;
use OMP::ProjDB;
use OMP::ProjServer;
use OMP::UserServer;

use vars qw/@ISA %EXPORT_TAGS @EXPORT_OK/;

require Exporter;

$| = 1;

@ISA = qw/Exporter/;

@EXPORT_OK = (qw/details project_users project_users_output list_users/);

%EXPORT_TAGS = (
		'all' =>[ @EXPORT_OK ],
	       );

Exporter::export_tags(qw/ all /);

# Width for HTML tables
our $TABLEWIDTH = '100%';

=head1 Routines

=over 4

=item B<details>

Create a page with all details concerning a user.

  details( $cgi,\%cookie );

Arguments should be that of C<CGI> object and a hash reference containing cookie details.

=cut

sub details {
  my $q = shift;
  my %cookie = @_;

  # Get user object
  my $user;
  try {
    $user = OMP::UserServer->getUser($q->url_param('user'));
  } otherwise {
    my $E = shift;
    print "Unable to retrieve user:<br>$E";
    return;
  };

  if (! $user) {
    print "Unable to retrieve details for unknown user [".$q->url_param('user')."]";
    return;
  }

  print "<h3>User Details for $user</h3>";
  print $user->html ." (".$user->email.")<br>";

  # Get projects user belongs to
  my @projects;
  my @support;
  try {
    my $db = new OMP::ProjDB(ProjectID => $cookie{projectid},
			     Password => "***REMOVED***",
			     DB => new OMP::DBbackend,);

    my $xml = "<ProjQuery>".
      "<person>".$user->userid."</person>".
	"</ProjQuery>";

    my $query = new OMP::ProjQuery( XML => $xml );

    @projects = $db->listProjects($query);

    # Get projects the user supports
    $xml = "<ProjQuery>".
      "<support>".$user->userid."</support>".
	"</ProjQuery>";

    $query = new OMP::ProjQuery( XML => $xml );

    @support = $db->listProjects($query);

  } otherwise {
    my $E = shift;
    print "Unable to retrieve projects for user:<br>$E";
    return;
  };

  # Sort out user's capacity for each project
  my %capacities;
  $capacities{Support} = \@support
    if (@support);

  for my $project (@projects) {
    if ($project->pi->userid eq $user->userid) {
      push @{$capacities{"Principal Investigator"}}, $project;
    }

    for ($project->coi) {
      if ($_->userid eq $user->userid) {
	push @{$capacities{"Co-Investigator"}}, $project;
      }
    }
  }

  my $ompurl = OMP::Config->getData('omp-url');
  my $url = $ompurl . OMP::Config->getData('cgidir');
  my $iconurl = $ompurl . OMP::Config->getData('iconsdir');

  # List projects by capacity
  for (keys %capacities) {
    if ($capacities{$_}) {
      print "<h3>$_ on</h3>";
      print "<table><tr><td></td><td>Receives email</td>";

      for (@{$capacities{$_}}) {
	print "<tr><td><a href=$url/projecthome.pl?urlprojid=".$_->projectid.">".
	  $_->projectid."</a></td>";

	if ($_->contactable($user->userid)) {
	  print "<td align=center><a href=$url/projusers.pl?urlprojid=".$_->projectid."><img src=$iconurl/mail.gif alt='Receives project emails' border=0></a></td>";
	} else {
	  print "<td align=center><a href=$url/projusers.pl?urlprojid=".$_->projectid."><img src=$iconurl/nomail.gif alt='Ignores project emails' border=0></a></td>";
	}
      }

      print "</table>";
    }
  }

}

=item B<list_users>

=cut

sub list_users {
  print "<h2>OMP users</h2>";

  my $users = OMP::UserServer->queryUsers( "<UserQuery></UserQuery>" );

  if (@$users) {
    my $ompurl = OMP::Config->getData('omp-private') . OMP::Config->getData('cgidir');

    print "<TABLE border='1' width=$TABLEWIDTH>\n";
    for (@$users) {
      print "<tr bgcolor='#7979aa'>";
      print "<TD>" . $_->userid ."</TD>";
      print "<TD><a href=$ompurl/userdetails.pl?user=" . $_->userid .">$_</a></TD>";
      print "<TD>" . $_->email . "</TD>";
      print "<TD><a href=\"update_user.pl?".$_->userid."\">Update</a></TD>";
    }
    print "</TABLE>\n";
  } else {
    print "No OMP users found!<br>\n";
  }
}

=item B<project_users>

Create a page displaying users associated with a project.

  project_users( $cgi, \%cookie );

First argument should be an object of the class C<OMP::CGI>.  Second
argument should be a hash reference representing cookie data.

=cut

sub project_users {
  my $q = shift;
  my %cookie = @_;

  # Get the project info
  my $project = OMP::ProjServer->projectDetails($cookie{projectid}, $cookie{password}, "object");

  # Get contacts
  my @contacts = $project->investigators;

  # Get contactables
  my %contactable = $project->contactable;
  
  print "<h3>Users associated with project $cookie{projectid}</h3>";

  # Display users in a table along with a checkbox for
  # indicating contactable status
  print $q->startform;
  print "<table>";
  print "<tr><td>Name (click for details)</td><td>Receive email</td>";

  for (sort @contacts) {
    my $userid = $_->userid;
    print "<tr><td>";
    print "<a href=userdetails.pl?user=$userid>". $_->name ."</a>";
    print "</td><td>";

    #Make sure they have an email address
    if ($_->email) {
      print $q->checkbox(-name=>$userid,
			 -checked=>$contactable{$userid},
			 -label=>"",);
    } else {
      print "<small>no email</small>";
    }
    print "</td>";
  }

  print "<tr><td colspan=2 align=right>";
  print $q->hidden(-name=>'show_output',
		   -default=>1,);
  print $q->submit(-name=>"update_contacts",
		   -value=>"Update",);
  print "</table>";
  print $q->endform;
}

=item B<project_users_output>

Parse project_users page form and display output.

  project_users_output( $cgi, \%cookie );

Takes an C<OMP::CGI> object and a reference to a hash containing cookie
data as arguments.

=cut

sub project_users_output {
  my $q = shift;
  my %cookie = @_;

  # Get project details
  my $project = OMP::ProjServer->projectDetails($cookie{projectid}, $cookie{password}, "object");

  # Get contacts
  my @contacts = $project->investigators;

  if ($q->param('update_contacts')) {
    my %new_contactable;

    # Go through each of the contacts and store their new contactable values
    my $count;
    for (@contacts) {
      my $userid = $_->userid;
      $new_contactable{$userid} = ($q->param($userid) ? 1 : 0);
      $count += $new_contactable{$userid};
    }

    # Make sure atleast 1 person is getting emails
    if ($count == 0) {
      print "<h3>The system requires atleast 1 person to receive project emails.  Update aborted.</h3>";
      return;
    }

    $project->contactable(%new_contactable);

    # Store user contactable info to database (have to actually store
    # entire project back to database)
    my $db = new OMP::ProjDB( ProjectID => $cookie{projectid},
			      Password => "***REMOVED***",
			      DB => new OMP::DBbackend, );

    try {
      $db->addProject( $project, 1 ); # Overwrite

      print "<h3>Contactable information for project $cookie{projectid} has been updated</h3>";
    } otherwise {
      my $E = shift;
      print "An error prevented the contactable information from being updated:<br>$E";
      return;
    };

    print "The following people will receive emails associated with this project:<br>";

    @contacts = $project->contacts;
    for (@contacts) {
      my $userid = $_->userid;
      print "<a href=userdetails.pl?user=$userid>". $_->name ."</a><br>";
    }
  }
}

=back

=head1 AUTHOR

Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>,

=head1 COPYRIGHT

Copyright (C) 2001-2003 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
