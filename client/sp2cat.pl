#!/local/perl-5.6/bin/perl

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
use SrcCatalog::JCMT;
use OMP::SciProg;

# Options
my ($help, $man);
my $status = GetOptions("help" => \$help,
                        "man" => \$man,
                       );

pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

# Get the filename [should probably also check stdin]
my $filename = shift(@ARGV);

die "Please supply a filename for processing"
  unless defined $filename;

die "Supplied file [$filename] does not exist"
  unless -e $filename;

# Create new SP object
my $sp = new OMP::SciProg( FILE => $filename );

# Extract all the coordinate objects
my @coords;
for my $msb ( $sp->msb ) {
  for my $obs ( $msb->obssum ) {
    push( @coords, $obs->{coords} );
  }
}

# Create a catalog object
my $cat = new SrcCatalog::JCMT( \@coords );

# And write it to stdout
$cat->writeCatalog( \*STDOUT );


=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut
