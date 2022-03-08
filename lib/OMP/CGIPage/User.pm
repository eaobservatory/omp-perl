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

use OMP::CGIComponent::Helper qw/start_form_absolute url_absolute/;
use OMP::Config;
use OMP::DBbackend;
use OMP::DBbackend::Hedwig2OMP;
use OMP::Display;
use OMP::Error qw(:try);
use OMP::FaultQuery;
use OMP::FaultServer;
use OMP::DateTools;
use OMP::General;
use OMP::ProjDB;
use OMP::ProjServer;
use OMP::User;
use OMP::UserServer;

use base qw/OMP::CGIPage/;

$| = 1;

# Width for HTML tables
our $TABLEWIDTH = '100%';

=head1 Routines

=over 4

=item B<details>

Create a page with all details concerning a user.

  $comp->details();

=cut

sub details {
  my $self = shift;
  my $q = $self->cgi;

  # Get user object
  my $user;
  my $E = undef;
  try {
    $user = OMP::UserServer->getUser($q->url_param('user'));
  } otherwise {
    $E = shift;
  };

  return $self->_write_error("Unable to retrieve user: $E")
    if defined $E;

  return $self->_write_error("Unable to retrieve details for unknown user [".$q->url_param('user')."]")
    unless $user;

  my $hedwig2omp = new OMP::DBbackend::Hedwig2OMP();
  my @hedwigids = map {$_->[0]} @{$hedwig2omp->handle()->selectall_arrayref(
    'SELECT hedwig_id FROM user WHERE omp_id = ?', {}, $user->userid)};

  # Get projects user belongs to
  my @projects;
  my @support;
  try {
    my $db = new OMP::ProjDB(DB => new OMP::DBbackend);

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
    $E = shift;
  };

  return $self->_write_error("Unable to retrieve projects for user: $E")
    if defined $E;

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

  # Query for faults user is associated with
  my $today = OMP::DateTools->today . "T23:59";
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

  return {
    user => $user,
    hedwig_ids => \@hedwigids,
    hedwig_profile => 'https://proposals.eaobservatory.org/person/',
    icon_url => OMP::Config->getData('iconsdir'),
    project_capacities => \%capacities,
    faults => \%faults,
  };
}

=item B<list_users>

Create a page listing all OMP users.

  $page->list_users();

=cut

sub list_users {
  my $self = shift;

  my $q = $self->cgi;

  my $users = OMP::UserServer->queryUsers( "<UserQuery><obfuscated>0</obfuscated></UserQuery>" );

  my $rowclass = 'row_shaded';

  # Set up list of initials
  my %hashTemp = map {uc substr($_->userid, 0, 1) => 1} @$users;
  my @alphabet = sort keys %hashTemp;

  return {
    letters => \@alphabet,
    users => $users,
  };
}

=item B<project_users>

Create a page displaying users associated with a project.

  $page->project_users($projectid);

First argument should be the project ID.

=cut

sub project_users {
  my $self = shift;
  my $projectid = shift;

  my $q = $self->cgi;

  # Get the project info
  my $project = OMP::ProjServer->projectDetails($projectid, "object");

  # Get contacts
  my @contacts = $project->investigators;

  # Get contactables and those with OMP access.
  my %contactable = $project->contactable;
  my %access = $project->omp_access;

  print "<h3>Users associated with project ${projectid}</h3>";

  # Display users in a table along with a checkbox for
  # indicating contactable status
  print start_form_absolute($q);
  print "<table>";
  print "<tr><td>Name (click for details)</td><td>Receive email</td><td>OMP access</td>";

  for (sort @contacts) {
    my $userid = $_->userid;
    print "<tr><td>";
    print "<a href=userdetails.pl?user=$userid>". $_->name ."</a>";
    print "</td><td>";

    #Make sure they have an email address
    if ($_->email) {
      print $q->checkbox(-name => 'email_' . $userid,
                         -checked=>$contactable{$userid},
                         -label=>"",);
    } else {
      print "<small>no email</small>";
    }

    print "</td><td>",
        $q->checkbox(-name => 'access_' . $userid,
                     -checked => $access{$userid},
                     -label => "");
    print "</td>";
  }

  print "<tr><td colspan=2 align=right>";
  print $q->hidden(-name=>'show_output',
                   -default=>1,);
  print $q->submit(-name=>"update_contacts",
                   -value=>"Update",);
  print "</table>";
  print $q->end_form;
}

=item B<project_users_output>

Parse project_users page form and display output.

  $page->project_users_output($projectid);

=cut

sub project_users_output {
  my $self = shift;
  my $projectid = shift;

  my $q = $self->cgi;

  # Get project details
  my $project = OMP::ProjServer->projectDetails($projectid, "object");

  # Get contacts
  my @contacts = $project->investigators;

  if ($q->param('update_contacts')) {
    my %new_contactable;
    my %new_access;

    # Go through each of the contacts and store their new contactable values
    my $count_email;
    my $count_access;
    for (@contacts) {
      my $userid = $_->userid;

      $new_contactable{$userid} = ($q->param('email_' . $userid) ? 1 : 0);
      $count_email += $new_contactable{$userid};

      $new_access{$userid} = ($q->param('access_' . $userid) ? 1 : 0);
      $count_access += $new_access{$userid};
    }

    # Make sure at least 1 person is getting emails
    if ($count_email == 0) {
      print "<h3>The system requires at least 1 person to receive project emails.  Update aborted.</h3>";
      return;
    }
    # Same for OMP access.
    if ($count_access == 0) {
      print "<h3>The system requires at least 1 person to have OMP access.  Update aborted.</h3>";
      return;
    }

    # Store user contactable info to database (have to actually store
    # entire project back to database)
    my $db = new OMP::ProjDB( ProjectID => $projectid,
                              DB => new OMP::DBbackend, );

    try {
      $db->updateContactability( \%new_contactable );
      $db->updateOMPAccess( \%new_access );
      $project->contactable(%new_contactable);
      $project->omp_access(%new_access);

      print "<h3>Contactable / OMP access information for project ${projectid} has been updated</h3>";
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

    print "<br>The following people have OMP access to this project:<br>";

    my @access = grep {$project->omp_access($_->userid)}
        ($project->investigators, $project->support);
    for (@access) {
      my $userid = $_->userid;
      print "<a href=userdetails.pl?user=$userid>". $_->name ."</a><br>";
    }
  }
}

=item B<edit_details>

Edit a user's details.  Takes an C<OMP::Query> object as the only argument.
A URL paramater called B<user> should be used for passing the OMP user ID.

  $page->edit_details();

=cut

sub edit_details {
  my $self = shift;

  my $q = $self->cgi;

  my $userid = $q->url_param("user");

  my $user = OMP::UserServer->getUser($userid);

  unless (defined $user) {
    return $self->_write_error("User [$userid] does not exist in the database.");
  }

  my @messages;

  if ($q->param("edit")) {
    my %from_form;

    # we need to check for validity of input but also note that if there
    # was no value previously and no value now, then we do not need to warn
    # if there is still no value later. Do not allow information to be deleted
    # though (so don't allow a field to be cleared)
    if ( $q->param("name") ) {
      # we were given a value
      if ($q->param("name") =~ /^([\w\s\.\-\(\)']+)$/) {
        $from_form{name} = $1;
        # trim leading space
        $from_form{name} =~ s/^\s*//;
        $from_form{name} =~ s/\s*$//;
      } else {
        # did not pass test so do not update
        push @messages, "The name you provided [".$q->param("name")."] is invalid.";
      }
    } elsif ($user->name) {
      # there is currently a value but none was supplied
      push @messages, "Clearing of name field is not supported by this form.";
    }

    if ( $q->param("email") ) {
      # we were given a value
      if ($q->param("email") =~ /^(.+?@.+?\.\w+)$/) {
        $from_form{email} = $1;
      } else {
        # did not pass test so do not update
        push @messages, "The email you provided [".$q->param("email")."] is invalid.";
      }
    } elsif ($user->email) {
      # there is currently a value but none was supplied
      push @messages, "Clearing of email address field is not supported by this form.";
    }

    if ( $q->param("cadcuser") ) {
      # we were given a value
      if ($q->param("cadcuser") =~ /^(\w+)$/) {
        $from_form{cadcuser} = $1;
      } else {
        # did not pass test so do not update
        push @messages, "The CADC Username you provided [".$q->param("cadcuser")."] is invalid.";
      }
    } elsif ($user->cadcuser) {
      # there is currently a value but none was supplied
      push @messages, "Clearing of CADC user name field is not supported by this form.";
    }

    $from_form{'no_fault_cc'} = $q->param('no_fault_cc') ? 1 : 0;

    unless (scalar @messages) {
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

      # Check boolean options for changes.
      foreach my $key (qw/no_fault_cc/) {
          my $from_db = $user->$key;
          my $new = $from_form{$key};
          if (($new and not $from_db) or ($from_db and not $new)) {
              $user->$key($new);
              $changed = 1;
          }
      }

      # Store changes
      if ($changed) {
        try {
          OMP::UserServer->updateUser( $user );
        } otherwise {
          my $E = shift;
          push @messages, "An error has occurred: $E";
        };
        return $self->_write_redirect('/cgi-bin/userdetails.pl?user=' . $user->userid)
          unless scalar @messages;
      } else {
        push @messages, "No change to supplied details.";
      }
    }
  }

  return {
    messages => \@messages,
    target => url_absolute($q),
    user => $user,
  };
}

sub add_user {
    my $self = shift;

    return $self->_add_user_form(undef);
}

sub add_user_output {
    my $self = shift;

    my $q = $self->cgi;

    my $userid = $q->param('new_user_id');
    my $message = $self->_add_user_try(
        $userid,
        (scalar $q->param('new_user_name')),
        (scalar $q->param('new_user_email')));

    return $self->_add_user_form($message) if defined $message;

    return $self->_write_redirect("/cgi-bin/userdetails.pl?user=$userid");
}

sub _add_user_form {
    my $self = shift;
    my $message = shift;

    my $q = $self->cgi;

    return {
        target => url_absolute($q),
        message => $message,
        new_user_id => ($q->param('new_user_id') // ''),
        new_user_name => ($q->param('new_user_name') // ''),
        new_user_email => ($q->param('new_user_email') // ''),
    };
}

# Attempt to add a new user account.  In the event of a problem,
# a message is returned.
sub _add_user_try {
    my $self = shift;
    my $userid = uc(shift);
    my $name = shift;
    my $email = shift;

    my $q = $self->cgi;

    # Trim leading / trailing spaces.
    foreach my $element (\$userid, \$name, \$email) {
        $$element =~ s/^\s*//;
        $$element =~ s/\s*$//;
    }

    # Check the user ID.
    return 'User ID is not valid.'
        unless $userid =~ /^[A-Z]+[0-9]*$/;

    my $user = OMP::UserServer->getUser($userid);
    return 'User ID already exists.'
        if defined $user;

    # Check the name (using the same pattern as above for in "edit_details").
    return 'Name is not valid.'
        unless $name =~ /^([\w\s\.\-\(\)']+)$/;

    my $expected_userid = OMP::User->infer_userid($name);
    return 'User ID does not follow the expected pattern ("' .
            $expected_userid . '" + an optional number) for the name you entered. ' .
            'If the expected pattern is incorrect for this person, ' .
            'please contact a member of the OMP group for assistance.'
        unless ($userid =~ s/[0-9]+$//r) eq $expected_userid;

    # Check the email (using the same pattern as above for in "edit_details").
    return 'Email address is not valid.'
        unless $email =~ /^(.+?@.+?\.\w+)$/;

    my $omp_user = new OMP::User(
        userid => $userid,
        name => $name,
        email => $email,
    );

    my $message = undef;

    try {
        OMP::UserServer->addUser($omp_user);
    } otherwise {
        my $E = shift;
        $message = 'Unable to add user: ' . $E;
    };

    return $message;
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
along with this program; if not, write to the
Free Software Foundation, Inc., 59 Temple Place, Suite 330,
Boston, MA  02111-1307  USA

=cut

1;
