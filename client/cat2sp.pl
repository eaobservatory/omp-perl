#!/lccal/perl-5.6/bin/perl

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
# availability. With the next release of starlink at least Astro::SLA
# will be widely available so that we can use SrcCatalog::JCMT
use SrcCatalog::JCMT;
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

# These are the tags that we are looking for when we process
# the xml
my $NAMEEL     = "targetName";
my $RAEL       = "c1";
my $DECEL      = "c2";
my $BLANK_NAME = "<$NAMEEL></$NAMEEL>";
my $BLANK_NAME2 = "<$NAMEEL/>";
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
my $sp = new OMP::SciProg( FILE => $template )
  or die "Error opening template file $template";

# now open the coordinates file. The opening and parsing is trivial
# we use SrcCatalog::JCMT for this since it also converts to J2000.
# If we do not want this dependency we will need to do more tweaking
# of the XML since GA and RB require changes to the telescope XML
# that are not currently in place.
my $cat = new SrcCatalog::JCMT( $coords );
my @sources = @{$cat->current};

# Remove any targets that are not RADEC
@sources = grep { $_->type eq 'RADEC'  } @sources;

# Now we need to loop over each MSB
for my $msb ($sp->msb) {

  # If this MSB has a blank target it should be cloned
  # whilst iterating through the source list
  # Quickest way to look for blank is simply to generate
  # XML string and do a pattern match
  next unless isBlank( "$msb" );

  # The number of times we clone this depends on the number of
  # blank entries in the MSB. Easiest to determine that number
  # ahead of the cloning loop.
  my $blanks = countBlanks( $msb->_tree->toString );
  # warn "BLANKS: $blanks\n";
  next if $blanks == 0;

  # Warn if we do not have an exact match
  warn "Number of blank targets in MSB '".$msb->msbtitle."' is not divisible into the number of targets supplied\n Some targets will be missing.\n"
    if scalar(@sources) % $blanks != 0;

  # Calculate the max number we can support [as an index]
  my $max = int(($#sources+1) / $blanks) * $blanks - 1;

  # Now loop over the source list
  for (my $i = 0; ($i+$blanks-1) <= $max; $i+= $blanks) {

    # Okay now we need to deep clone the MSB
    my $clone = $msb->_tree->cloneNode( 1 );

    # There is no method in OMP::MSB (yet) for replacing target
    # XML with other target XML. The only way we can do this
    # currently is to take each MSB, use XPath to locate the
    # telescope components, then find the nodes corresponding to
    # the coordinates and change the values
    # Note that we do not deal with inherited telescope components
    # Note also that _tree is a private method so we really need
    # to provide an explicit OMP::MSB interface for this
    my @tels = $clone->findnodes(".//SpTelescopeObsComp");

    # Now loop over the telescope components
    my $c = 0; # Count number replaced
    for my $tel (@tels) {

      die "Internal error: The number of blank telescope components encountered exceeds the expected number!!!\n" if $c >= $blanks;

      #warn $tel->toString ."\n";

      # Locate the targetName, ra and dec components
      my ($targetnode) = $tel->findnodes(".//$NAMEEL");
      next unless $targetnode;

      # If this is undefined we have to attach a child ourselves
      my $target = $targetnode->firstChild;

      # Either this should be an empty string node or no node at all
      if (defined $target) {
	my $string = $target->toString;
	next if length($string) > 0 && $string =~ /\w/;
      }

      my ($ranode)     = $tel->findnodes(".//$RAEL");
      next unless $ranode;
      next unless $ranode->toString eq $BLANK_RA;

      my ($decnode)    = $tel->findnodes(".//$DECEL");
      next unless $decnode;
      next unless $decnode->toString eq $BLANK_DEC;

      #warn "Target: " .$targetnode->toString."\n";
      #warn "RA:     " .$ranode->toString."\n";
      #warn "Dec:    " .$decnode->toString."\n";

      # Now we know we have a blank target component
      # Get the children
      my $ra = $ranode->firstChild;
      #warn "RA child is $ra\n";
      my $dec = $decnode->firstChild;
      #warn "Dec child is $dec\n";

      # Get the target
      if (($i+$c) > $max) {
	die "Error - we seem to have miscalculated\n";
      }
      my $coords = $sources[ $i + $c];

      # Change the content
      $ra->setData( $coords->ra( format => 'sex'));
      $dec->setData( $coords->dec( format => 'sex'));

      if (defined $target) {
	$target->setData( $coords->name );
      } else {
	my $text = new XML::LibXML::Text( $coords->name );
	$targetnode->appendChild( $text );
      }

      #warn $tel->toString ."\n";

      # increment the tel counter
      $c++;
    }

    die "Internal error: We found fewer blank telescope components than expected!!!\n" unless $c == $blanks;

    # Now we need to attach the clone to the parent
    $msb->_tree->parentNode->insertAfter( $clone, $msb );

  }

  # Now we need to remove the template node
  $msb->_tree->unbindNode;

  #  info message
  warn "Cloning MSB with title " . $msb->msbtitle ."\n"

}

# and send the science programme to stdout
print "$sp\n";

exit;

# make sure the targets are blank
sub isBlank {
  my $string = shift;

  my $blank;
  if ($string =~ /($BLANK_NAME|$BLANK_NAME2)/ && $string =~ /$BLANK_RA/
	  && $string =~ /$BLANK_DEC/) {
    $blank = 1;
  } else {
    $blank = 0;
  }
  return $blank;
}

# Count the number of blank targets in the MSB
# Returns the minimum of number of blank names, number of blank
# RAs and number of blank decs
sub countBlanks {
  my $string = shift;

  my $nnames = ( $string =~ s/($BLANK_NAME|$BLANK_NAME2)/$BLANK_NAME2/g );
  #warn "Got names: $nnames\n";
  my $nra    = ( $string =~ s/$BLANK_RA/$BLANK_RA/g );
  #warn "Got RA: $nra\n";
  my $ndec   = ( $string =~ s/$BLANK_DEC/$BLANK_DEC/g );
  #warn "Got Dec: $ndec\n";

  my $min = $nnames;
  $min = $nra if $nra < $min;
  $min = $ndec if $ndec < $min;

  return $min;
}


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
