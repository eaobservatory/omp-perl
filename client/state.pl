#!/local/perl/bin/perl

=head1 NAME

state - Disable or enable a project

=head1 SYNOPSIS

 state -id u/05a/1
 state -id u/05a/1 -disable
 state -id u/05a/1 -enable

=head1 DESCRIPTION

This program can be used to disable or re-enable a project, or to view the
current state of a project.

=head1 OPTIONS

The following options are supported:

=over 4

=item B<-disable>

Disable project.

=item B<-enable>

Re-enable project.

=item B<-help>

A help message.

=item B<-id>

An OMP project ID.

=item B<-man>

This manual page

=item B<-version>

Report the version number.

=back

When called with only the -id option, the current state of the
project is displayed.

=cut

use 5.006;
use strict;
use warnings;

$| = 1; # Make unbuffered

use Getopt::Long;
use Pod::Usage;
use Term::ReadLine;

# Locate the OMP software through guess work
use FindBin;
use lib "$FindBin::RealBin/..";

# OMP Classes
use OMP::DBbackend;
use OMP::General;
use OMP::ProjDB;

# Options
my ($help, $man, $version, $id, $enable, $disable);
my $status = GetOptions("help" => \$help,
                        "man" => \$man,
                        "version" => \$version,
                        "id=s" => \$id,
                        "enable" => \$enable,
			"disable" => \$disable,
                       );

pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

if ($version) {
  my $id = '$Id$ ';
  print "state - Disable or enable a project\n";
  print " CVS revision: $id\n";
  exit;
}

# Die if options clash
if ($enable and $disable) {
  die "Use either -disable or -enable, not both.\n";
}

# Setup term
my $term = new Term::ReadLine 'Disable or enable a project';

# Get administrator password
my $attribs = $term->Attribs;
$attribs->{redisplay_function} = $attribs->{shadow_redisplay};
my $password = $term->readline( "Please enter the staff password: ");
$attribs->{redisplay_function} = $attribs->{rl_redisplay};

print "\n";

# Connect to the database
my $dbconnection = new OMP::DBbackend;

my $projdb = new OMP::ProjDB( ProjectID => $id,
			      DB => $dbconnection,
			      Password => $password, );

# Get project
my $proj = $projdb->projectDetails( 'object' );

# Display project state
print "Project " . $proj->projectid . " is currently " . ($proj->state ? "enabled" : "disabled") ."\n";

if ($enable or $disable) {
  if ($enable) {
    print "Enabling project ". $proj->projectid ."... ";

    # Set state to enabled
    $projdb->enableProject();
  } else {
    print "Disabling project ". $proj->projectid ."... ";

    # Set state to enabled
    $projdb->disableProject();
  }

  print "done.\n";
}

=head1 AUTHOR

Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2005 Particle Physics and Astronomy Research Council.
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
Place,Suite 330, Boston, MA  02111-1307, USA

=cut

