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
use OMP::ProjServer;
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

# Loop over each project and update it
for my $proj (keys %alloc) {

  # First need to get the project information from the database

  # Then need to go through the hash values and update
  # being careful to deal with incalloc

  # Now store the project details back in the database


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
