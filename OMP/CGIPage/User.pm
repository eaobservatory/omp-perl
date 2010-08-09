package OMP::CGIPage::User;

=head1 NAME

OMP::CGIPage::User - Display OMP user details web pages

=head1 SYNOPSIS

  use OMP::CGIPage::User;

=head1 DESCRIPTION

Provide functions to display the OMP user details web pages.

=cut

use 5.006;
use strict;
use warnings;
use Carp;
our $VERSION = (qw$ Revision: 1.2 $ )[1];

use OMP::Config;
use OMP::DBbackend;
use OMP::Display;
use OMP::Error qw(:try);
use OMP::FaultQuery;
use OMP::FaultServer;
use OMP::General;
use OMP::ProjDB;
use OMP::ProjServer;
use OMP::UserServer;

use vars qw/@ISA %EXPORT_TAGS @EXPORT_OK/;

require Exporter;

$| = 1;

@ISA = qw/Exporter/;

@EXPORT_OK = (qw/details project_users project_users_output list_users edit_details/);

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
  print $user->html;
  print " (".$user->email .")"
    if ($user->email);
  if ($user->cadcuser) {
    print " (<a href=\"http://cadcwww.dao.nrc.ca/\">CADC UserID</a>: ". $user->cadcuser.")\n";
  }
  print "<BR>\n";

  # Get projects user belongs to
  my @projects;
  my @support;
  try {
    my $db = new OMP::ProjDB(ProjectID => $cookie{projectid},
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

  # Query for faults user is associated with
  my $today = OMP::General->today . "T23:59";
  my $xml = "<FaultQuery>".
    "<author>".$user->userid."</author>".
      "<date delta=\"-14\">$today</date>".
	"</FaultQuery>";
  my $faultquery = new OMP::FaultQuery(XML => $xml);

  my $faults = OMP::FaultServer->queryFaults($faultquery,
					     "object");

  # Sort by category
  my %faults;
  map {push @{$faults{$_->category}}, $_} @$faults;

  if (%faults) {
    print "<h4>User associated faults for the past 2 weeks</h4>";
    print "<table>";
    print "<td>Category</td><td align=center>Subject</td>";
    for my $category (sort keys %faults) {
      for (@{$faults{$category}}) {
	print "<tr><td>" . $_->category ."</td>";
	print "<td><a href=\"viewfault.pl?id=".$_->faultid."\">".$_->subject."</a></td></tr>";
      }
    }
    print "</table><br>";
  }
}

=item B<list_users>

Create a page listing all OMP users.

  list_users($q);

Takes an C<OMP::CGI> object as an argument.

=cut

sub list_users {
  my $q = shift;

  print "<h2>OMP users</h2>";

  my $users = OMP::UserServer->queryUsers( "<UserQuery></UserQuery>" );

  my $rowclass = 'row_shaded';

  if (@$users) {

    # Set up list of initials
    my @temparray;
    for (@$users) {
       push @temparray, uc substr($_->userid,0,1);
    }
    my %hashTemp = map { $_ => 1 } @temparray;
    my @alphabet = sort keys %hashTemp;

    my $ompurl = OMP::Config->getData('omp-private') . OMP::Config->getData('cgidir');

    # Print list of initials for anchors
    print "<p>\n| ";
    foreach my $letter (@alphabet) {
       print qq{<a href="#${letter}">${letter}</a> |};
     }
    print "</p>\n";

    my $letnr = 0;
    my $letter = $alphabet[$letnr];

    print "<p>\n";
    print "<TABLE border='0' cellspacing='0' width=$TABLEWIDTH>\n";
    print qq{<a name="${letter}"></a>\n};

    for (@$users) {

      while ( $_->userid !~ /^${letter}/i && $letnr < $#alphabet ) {
        $letnr++;
        $letter = $alphabet[$letnr];
        print qq{<a name="${letter}"></a>\n};
      }

      print "<tr class='${rowclass}'>";
      print "<TD>" . $_->userid ."</TD>";
      print "<TD>". OMP::Display->userhtml($_, $q) ."</TD>";
      print "<TD>" . $_->email . "</TD>";
      print "<TD>" . $_->cadcuser . "</TD>";
      print "<TD><a href=\"update_user.pl?user=".$_->userid."\">Update</a></TD>";
      print "</TR>\n";

      # Alternate row style
      $rowclass = ($rowclass eq 'row_shaded' ? 'row_clear' : 'row_shaded');
    }
    print "</TABLE>\n";

    print "<p>\n| ";
    foreach $letter (@alphabet) {
       print qq{<a href="#${letter}">${letter}</a> |};
    }
    print "</p>\n";

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

    # Store user contactable info to database (have to actually store
    # entire project back to database)
    my $db = new OMP::ProjDB( ProjectID => $cookie{projectid},
                              'Password' => $cookie{'password'},
			      DB => new OMP::DBbackend, );

    try {

      $db->updateContactability( \%new_contactable );
      $project->contactable(%new_contactable);

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

=item B<edit_details>

Edit a user\'s details.  Takes an C<OMP::Query> object as the only argument.
A URL paramater called B<user> should be used for passing the OMP user ID.

  edit_details($q);

=cut

sub edit_details {
  my $q = shift;

  my $userid = $q->url_param("user");

  my $user = OMP::UserServer->getUser($userid);

  if (!defined $user) {
    print "User [$userid] does not exist in the database.<br>";
    return;
  }

  if ($q->param("edit")) {
    my %from_form;

    # we need to check for validity of input but also note that if there
    # was no value previously and no value now, then we do not need to warn
    # if there is still no value later. Do not allow information to be deleted
    # though (so don't allow a field to be cleared)
    my $doupdate = 1; # allow updates
    if ( $q->param("name") ) {
      # we were given a value
      if ($q->param("name") =~ /^([\w\s\.\-\(\)]+)$/) {
	$from_form{name} = $1;
        # trim leading space
        $from_form{name} =~ s/^\s*//;
        $from_form{name} =~ s/\s*$//;
      } else {
	# did not pass test so do not update
	$doupdate = 0;
	print "The name you provided [".$q->param("name")."] is invalid.<br>";
      }  
    } elsif ($user->name) {
      # there is currently a value but none was supplied
      $doupdate = 0;
      print "Clearing of name field is not supported by this form.<br>";
    }

    if ( $q->param("email") ) {
      # we were given a value
      if ($q->param("email") =~ /^(.+?@.+?\.\w+)$/) {
	$from_form{email} = $1;
      } else {
	# did not pass test so do not update
	$doupdate = 0;
	print "The email you provided [".$q->param("email")."] is invalid.<br>";
      }  
    } elsif ($user->email) {
      # there is currently a value but none was supplied
      $doupdate = 0;
      print "Clearing of email address field is not supported by this form.<br>";
    }

    if ( $q->param("cadcuser") ) {
      # we were given a value
      if ($q->param("cadcuser") =~ /^(\w+)$/) {
	$from_form{cadcuser} = $1;
      } else {
	# did not pass test so do not update
	$doupdate = 0;
	print "The CADC Username you provided [".$q->param("cadcuser")."] is invalid.<br>";
      }  
    } elsif ($user->cadcuser) {
      # there is currently a value but none was supplied
      $doupdate = 0;
      print "Clearing of CADC user name field is not supported by this form.<br>";
    }

    if (!$doupdate) {
      print "User details were not updated.";
    } else {

      # see if anything changed, and update the object if it has
      my $changed;
      for my $key (qw/ name email cadcuser /) {
         my $from_db = $user->$key;
         my $new = $from_form{$key};
         $new = undef if !$new;
         if (!defined $from_db && !defined $new) {
            # both undef so no change
         } elsif (defined $from_db && !defined $new) {
            # differ
            $changed = 1;
         } elsif (!defined $from_db && defined $new) {
            # differ
            $changed = 1;
         } elsif ($from_db ne $new) {
            $changed = 1;
         }
         $user->$key( $from_form{$key} );
      }

      # Store changes
      if ($changed) {
        try {
  	  OMP::UserServer->updateUser( $user );
	  print "User details for ".$user->userid." have been updated.<br>";
        } otherwise {
	  my $E = shift;
	  print "An error has occurred: $E<br>";
	  print "User details were not updated.";
        };
      } else {
        print "No change to supplied details.<br>\n";
      }
    }
  }

  print "<table><td align=right>User ID:</td><td>".$user->userid."</td>";
  print $q->startform;
  print "<tr><td>Name:</td><td colspan=2>";
  print $q->textfield(-name=>"name",
		      -default=>$user->name,
		      -size=>24,
		      -maxlength=>255,);
  print "</td><tr><td>Email:</td><td>";
  print $q->textfield(-name=>"email",
		      -default=>$user->email,
		      -size=>32,
		      -maxlength=>64,);
  print "</td><tr><td>CADC ID:</td><td>";
  print $q->textfield(-name=>"cadcuser",
		      -default=>$user->cadcuser,
		      -size=>32,
		      -maxlength=>64,);
  print "</td><td>";
  print $q->submit(-name=>"edit", -label=>"Change Details");
  print $q->endform;
  print "</td></table>";

}

=back

=head1 AUTHOR

Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>,
Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001-2003,2007 Particle Physics and Astronomy Research Council.
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
along with this program (see SLA_CONDITIONS); if not, write to the
Free Software Foundation, Inc., 59 Temple Place, Suite 330,
Boston, MA  02111-1307  USA

=cut

1;
