#!perl

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
should be in JCMT catalogue format (see L<CATALOGUE>). A warning
will be issued to standard error if the number of telescope components
in an MSB is not divisible into the number of targets provided.

=back

=head1 OPTIONS

The following options are supported:

=over 4

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
the science program.

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
# availability. With the next release of starlink at least Astro::SLA
# will be widely available so that we can use SrcCatalog::JCMT
use SrcCatalog::JCMT;
use OMP::SciProg;

# Options
my ($help, $man);
my $status = GetOptions("help" => \$help,
                        "man" => \$man,
                       );

pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;


# These are the tags that we are looking for when we process
# the xml
my $NAMEEL     = "targetName";
my $RAEL       = "c1";
my $DECEL      = "c2";
my $BLANK_NAME = "<$NAMEEL></$NAMEEL>";
my $BLANK_RA   = "<$RAEL>0:00:00</$RAEL>";
my $BLANK_DEC  = "<$DECEL>0:00:00</$DECEL>";

my ($template, $coords) = @ARGV;
unless (defined $template && defined $coords) {
  warn "Must specify MSB xml and catalogue file.\n";
  pod2usage(1);
}

# Doing this without any of the classes that will make it easy
# If only I could use OMP::SciProg it would be easy to get the
# first MSB, find all the targets and replace the coordinates.


# Open the science program template
open(my $fh, "<$template") 
  or die "Error opening template file $template: $!\n";

# Slurp in the file
local $/ = undef;
my $refxml = <$fh>;
close($fh) or die "error closing template file $msb: $!\n";
local $/ = "\n";

die "No target in supplied XML"
  unless $refxml =~ /SpTelescopeObsComp/;

die "No blank target entries"
  unless isBlank($refxml);

# now open the coordinates file


# loop over each line
my $xml = $refxml;
my $continue = 0;
while (defined (my $line = <$fh>)) {
  # replace comments
  $line =~ s/\#.*$//;
  $line =~ s/\s*$//;
  next unless $line;

  my ($name, $ra, $dec) = split(/\s+/,$line);

  # replace the entries (but only once)
  $xml =~ s/$BLANK_NAME/<$NAMEEL>$name<\/$NAMEEL>/;
  $xml =~ s/$BLANK_RA/<$RAEL>$ra<\/$RAEL>/;
  $xml =~ s/$BLANK_DEC/<$DECEL>$dec<\/$DECEL>/;

  # if the xml still has blank entries we skip
  # else we dump to stdout and reset the xml string
  unless (isBlank($xml)) {
    print $xml;
    $xml = $refxml;
  }
}

# should probably trap for case where we did not dump the
# last xml because only partial replacement


exit;

# make sure the targets are blank
sub isBlank {
  my $string = shift;

  my $blank;
  if ($string =~ /$BLANK_NAME/ && $string =~ /$BLANK_RA/
	  && $string =~ /$BLANK_DEC/) {
    $blank = 1;
  } else {
    $blank = 0;
  }
  return $blank;
}

=head1 DEPENDENCIES

Requires the availability of the OMP infrastructure modules
(specifically L<OMP::SciProg|OMP::SciProg> which depends on the CPAN
module L<XML::LibXML> which requires a modern version of the
C<libxml2> library from C<www.xmlsoft.org>) as well as the
C<SrcCatalog::JCMT> module (which depends on the CPAN modules
L<Astro::SLA|Astro::SLA> and L<Astro::Coords|Astro::Coords>).

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=cut
