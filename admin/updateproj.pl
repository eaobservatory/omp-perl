#!/usr/local/bin/perl

=head1 NAME

updateproj - Update information associated with some project(s)

=head1 SYNOPSIS

  updateproj details.ini

=head1 DESCRIPTION

This program reads in a file containing the project information, and
updates the details to the OMP database. If a project does not exist
in the database a warning is issued.  See L<"FORMAT"> for details on
the file format.

=head1 ARGUMENTS

The following arguments are allowed:

=over 4

=item B<defines>

The project update definitions file name. See L<"FORMAT"> for details
on the file format.

=back

=head1 OPTIONS

The following options are supported:

=over 4

=item B<-version>

Report the version number.

=item B<-help>

A help message.

=item B<-man>

This manual page.

=back

=cut

use warnings;
use strict;

use OMP::Error qw/ :try /;
use Config::IniFiles;
use OMP::ProjDB;
use OMP::DBbackend;
use OMP::General;
use Pod::Usage;
use Getopt::Long;

# Options
my ($help, $man, $version,$force);
my $status = GetOptions("help" => \$help,
                        "man" => \$man,
                        "version" => \$version,
                       );

pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

if ($version) {
  my $id = '$Id$ ';
  print "updateproj - update project details from file\n";
  print " CVS revision: $id\n";
  exit;
}

# Read the file
my $file = shift(@ARGV);
my %alloc;
tie %alloc, 'Config::IniFiles', ( -file => $file );

# Connect to the database
my $projdb = new OMP::ProjDB( DB => new OMP::DBbackend );

# Loop over each project and update it
for my $proj (keys %alloc) {

  # Set the project ID in the DB object
  $projdb->projectid( $proj );

  # First check that the project exists
  if (! $projdb->verifyProject) {
    warn "Project $proj does not exist in DB so can not update it!\n";
    next;
  }

  # Then need to get the project information from the database
  my $project = $projdb->_get_project_row();

  # Then need to go through the hash values and update
  # being careful to deal with incalloc
  for my $mod (keys %{ $alloc{$proj} }) {
    if ($project->can($mod)) {
      print "Changing $mod from ".$project->$mod ." ";
      $project->$mod( $alloc{$proj}->{$mod} );
      print " to " .$alloc{$proj}->{$mod} ."\n";
    } elsif ($mod eq 'incalloc') {
      # Special case
      my $inc = $alloc{$proj}->{$mod} * 3600;

      print "Changing allocation from ".$project->allocated ." ";

      # The allocation should be the time spent plus
      # the new increment (converted to hours)
      my $newtotal = $project->used + $inc;
      $project->allocated( $newtotal );

      # The time remaining on the project is now the increment
      $project->remaining( $inc );
      $project->pending(0);

      print "to $newtotal seconds\n";
    } else {
      warn "Unrecognized key in project $proj: $mod\n";
    }

  }


  # Now store the project details back in the database
  $projdb->_update_project_row( $project );

  print "Update details for project $proj\n";

}


=head1 FORMAT

The input project definitions file is in the C<.ini> file format with
the following layout. Individual projects are specified in sections,
indexed by project ID. The column names in this file must match
accessor method names in an C<OMP::Project> object.

 [m01bu32]
 tagpriority=1
 semester=03A
 incalloc=40.0

The exception to this rule is C<incalloc>. This key is taken to imply
that the specified time (in hours) should be added to the allocation
such that that time is the new time remaining on the project (this is
used for carry over of one project from one semester to another).

If you are overriding normal time-based entries, the values should be
in seconds to match the C<OMP::Project> interface.


=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2003 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut
