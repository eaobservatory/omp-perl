#!/local/perl/bin/perl

=head1 NAME

disable - Disable or enable a project

=head1 SYNOPSIS

 disable -id u/05a/1
 disable -id u/05a/1 -disable
 disable -id u/05a/1 -enable

=head1 DESCRIPTION

This program can be used to disable or re-enable a project.

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
  print "disable - Disable or enable a project\n";
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
