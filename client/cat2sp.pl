#!/local/perl/bin/perl

=head1 NAME

cat2sp - Make a science programme from a template and source catalogue

=head1 SYNOPSIS

  cat2sp -h
  cat2sp template.xml catalogue.dat

=head1 DESCRIPTION

This program can be used to insert target information into template
MSBs contained in a science program. For each MSB containing a blank
telescope component (ie one inserted into the science program but
without being edited) that MSB will be cloned for each target in the
catalogue. If there are multiple blank telescope components in a
single MSB sources will be inserted in turn. That is, with two
telescope components in the MSB and 10 targets, the output science
program will contain 5 cloned MSBs.

=head1 ARGUMENTS

The following arguments are required:

=over 4

=item B<template>

The name of the template science program. If the science program
contains no blank telescope components an error will be sent to
standard error.

=item B<catalogue>

Name of a catalogue file containing the target information. This
should be in JCMT catalogue format (see L<"CATALOGUE">). A warning
will be issued to standard error if the number of telescope components
in an MSB is not divisible into the number of targets provided.

=back

=head1 OPTIONS

The following options are supported:

=over 4

=item B<-version>

Report the version number.

=item B<-help>

Display the help information.

=item B<-man>

Display the full manual page.

=back

=head1 CATALOGUE

The input file should follow the JCMT catalogue format (although
the column positions are not enforced). The format is:

 * My catalogue
 Target1   05 06 23.4  - 23 42 06.5   RJ
 Target2   12 20 15.0  + 16 32 22.5   GA

The target name should not have spaces, "*" is a comment character
and the sign should not be abutted against the declination degrees.

The allowed abbreviations for coordinate frames are:

=over 4

=item RJ

FK5 J2000.

=item RB

FK4 B1950.

=item GA

Galactic coordinates.

=back

Coordinates are converted to FK5 J2000 prior to inserting them into
the science program. Coordinates in AZ frame, planets or orbital
elements are not supported.

=cut

use strict;
use Pod::Usage;
use Getopt::Long;

# Locate the OMP software through guess work
use FindBin;
use lib "$FindBin::RealBin/..";

# This code will be much much more complicated if we have to do it
# without Astro::Coords and without XML::LibXML [aka OMP::SciProg]
# For now we assume the script is being run locally so we can guarantee
# availability.
use Astro::Catalog;
use OMP::SciProg;

# Options
my ($help, $man, $version);
my $status = GetOptions("help" => \$help,
                        "man" => \$man,
			"version" => \$version,
                       );

pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

if ($version) {
  my $id = '$Id$ ';
  print "cat2sp - catalogue to science program importer\n";
  print " CVS revision: $id\n";
  exit;
}

# Read the useful arguments
my ($template, $coords) = @ARGV;
unless (defined $template && defined $coords) {
  warn "Must specify MSB xml and catalogue file.\n";
  pod2usage(1);
}

# Open the science program template
my $sp = new OMP::SciProg( FILE => $template )
  or die "Error opening template file $template";

# now open the coordinates file. The opening and parsing is trivial
# we use SrcCatalog::JCMT for this since it also converts to J2000.
# If we do not want this dependency we will need to do more tweaking
# of the XML since GA and RB require changes to the telescope XML
# that are not currently in place.
my $cat = new Astro::Catalog(Format => 'JCMT',
			     File => $coords );
my @sources = map { $_->coords } $cat->allstars;

# Now clone the msbs
my @info = $sp->cloneMSBs( @sources );

# And print out warnings
foreach (@info) {
  warn $_ . "\n";
}

# and send the science programme to stdout
print "$sp\n";

exit;

=head1 NOTES

This routine does not touch inherited telescope components. Each
MSB that you wish to process must contain an explicit telescope
component.

If the number of telescopes in your MSB is not divisible into
the number of supplied target positions some targets will not be
included in the output science program (the routine only provides
output for complete MSBs). This does mean that if you have an
MSB requiring 2 target positions and a catalogue containing only
one target then that MSB will not be output at all.

=head1 DEPENDENCIES

Requires the availability of the OMP infrastructure modules
(specifically L<OMP::SciProg|OMP::SciProg> which depends on the CPAN
module L<XML::LibXML|XML::LibXML> which requires a modern version of
the C<libxml2> library from C<www.xmlsoft.org>) as well as the
C<SrcCatalog::JCMT> module (which depends on the CPAN modules
L<Astro::SLA|Astro::SLA> and L<Astro::Coords|Astro::Coords>).

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=cut
