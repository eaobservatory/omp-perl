#!/local/perl/bin/perl

=head1 NAME

sp2cat - Extract target information from OMP science program

=head1 SYNOPSIS

  sp2cat program.xml

=head1 DESCRIPTION

Converts the target information in an OMP science program into
a catalogue file suitable for reading into the JCMT control
system or the C<sourceplot> application.

The catalog contents are written to standard output.

=head1 ARGUMENTS

The following arguments are allowed:

=over 4

=item B<sciprog>

The science program XML.

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

=cut

use 5.006;
use warnings;
use strict;

use Getopt::Long;
use Pod::Usage;
use Astro::Catalog;
use Astro::Catalog::Star;

# Locate the OMP software through guess work
use FindBin;
use lib "$FindBin::RealBin/..";

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
  print "sp2cat - science program source extractor\n";
  print " CVS revision: $id\n";
  exit;
}

# Get the filename [should probably also check stdin]
my $filename = shift(@ARGV);

die "Please supply a filename for processing"
  unless defined $filename;

die "Supplied file [$filename] does not exist"
  unless -e $filename;

# Create new SP object
my $sp = new OMP::SciProg( FILE => $filename );

# Get the project ID
my $projectid = $sp->projectID;

# Extract all the coordinate objects
my @coords;
for my $msb ( $sp->msb ) {
  for my $obs ( $msb->obssum ) {
    push( @coords, $obs->{coords} );
  }
}

# Set the comment field to the projectid
for (@coords) {
  $_->comment($projectid);
}

# Create a catalog object
my @stars = map { new Astro::Catalog::Star(Coords=>$_) } @coords;
my $cat = new Astro::Catalog(Stars => \@stars);
$cat->origin("OMP sp2cat");

# And write it to stdout
$cat->write_catalog( File => \*STDOUT, Format => 'JCMT' );

=back

=head1 DEPENDENCIES

Requires the availability of the OMP infrastructure modules
(specifically L<OMP::SciProg|OMP::SciProg> which depends on the CPAN
module L<XML::LibXML|XML::LibXML> which requires a modern version of
the C<libxml2> library from C<www.xmlsoft.org>) as well as the
C<SrcCatalog::JCMT> module (which depends on the CPAN modules
L<Astro::SLA|Astro::SLA> and L<Astro::Coords|Astro::Coords>).

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2002-2005 Particle Physics and Astronomy Research Council.
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
