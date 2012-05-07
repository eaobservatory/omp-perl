#!/local/perl/bin/perl

=head1 NAME

listtargs - List targets from a science programme

=head1 SYNOPSIS

  listtargs -h
  listtargs U/06A/H32
  listtargs h32.xml

=head1 DESCRIPTION

This program extracts all the targets from a science program and
lists them to standard out with details of the RA/Dec and current
airmass. It also checks for internal consistency by comparing targets
that have identical names.

Extremely useful when validating orbital elements.

=head1 OPTIONS

The following options are supported:

=over 4

=item B<science programme>

The main argument is the file containing the science program. If the file does not
exist and the string does not a file extension (.xml) it is assumed to refer to
an actual project ID. In that case the project password is requested and an attempt
is made to retrieve the science programme for target extraction.

=item B<-version>

Report the version number.

=item B<-help>

Display the help information.

=item B<-man>

Display the full manual page.

=item B<-region>

Produce a list of regions to be observed.

=item B<-format> stcs | ast

Selects the format in which to report the regions.

=item B<-type> new | progress | complete

Outputs only regions in the specified state.

=item B<-plot>

Display a plot of regions instead of outputting a text description.

=back

=cut

# List all targets in a science program
use strict;
use warnings;
use Pod::Usage;
use Getopt::Long;

# Locate the OMP software through guess work
use FindBin;
use lib "$FindBin::RealBin/..";

# Must load AST early to avoid problems with PGPLOT.
# Therefore load OMP::SpRegion now.
use OMP::SpRegion;

# External modules
use DateTime;
use Term::ReadLine;

# OMP classes
use OMP::SciProg;
use OMP::ProjServer;
use OMP::SpServer;


# Options
my ($format, $mode_type, $plotting_method,
    $help, $man, $version, $mode_region, $mode_plot)
  = ('stcs', undef, 'cmpregion');
my $status = GetOptions("help" => \$help,
                        "man" => \$man,
                        "version" => \$version,
                        "region" => \$mode_region,
                        "plot" => \$mode_plot,
                        'format=s' => \$format,
                        'type=s' => \$mode_type,
                        'plottingmethod=s' => \$plotting_method,
                       );

pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

if ($version) {
  my $id = '$Id$ ';
  print "omplisttargs - List targets found in science programme\n";
  print " Source code revision: $id\n";
  exit;
}

# Read the science program in
my $file = shift(@ARGV);

my $sp;
if (-e $file) {
  # looks to be a filename
  $sp = new OMP::SciProg( FILE => $file);
} elsif ( OMP::ProjServer->verifyProject( $file ) ) {
  # we have a project ID - we need to get permission

  my $term = new Term::ReadLine 'Retrieve Science Programme';

  # Needs Term::ReadLine::Gnu
  my $attribs = $term->Attribs;
  $attribs->{redisplay_function} = $attribs->{shadow_redisplay};
  my $password = $term->readline( "Please enter project or staff password: ");
  $attribs->{redisplay_function} = $attribs->{rl_redisplay};

  print "Retrieving science programme $file\n";
  $sp = OMP::SpServer->fetchProgram( $file, $password, "OBJECT" );

} else {
  die "Supplied argument ($file) is neither a file nor a project ID\n";
}


# Reference time
my $dt = DateTime->now;

# Determine which type of report is required.
if ($mode_region || $mode_plot) {region_report($sp); exit(0);}
# Otherwise fall through to default report type.

my %targets;
my @targnames;

for my $msb ( $sp->msb ) {
  my $info = $msb->info;
  my @obs = $info->observations;

  for my $o (@obs) {
    my $c = $o->coords;
    $c->datetime( $dt );
    next if $c->type eq 'CAL';
    if (exists $targets{$c->name}) {
      # exists so compare
      my $dist = $c->distance( $targets{$c->name}->[0] );
      if ($dist->arcsec > 1) {
	print "-->>>> Target " .$c->name ." duplicated but with coordinates that differ by ". sprintf("%.1f",$dist->arcsec) ." arcsec\n";
	push(@{ $targets{$c->name} }, $c);
      }
    } else {
      push(@targnames, $c->name);
      $targets{$c->name} = [ $c ];
    }
  }

}

# Now dump the current values
print("Target                RA(J2000)   Dec(J2000)    Airmass   Type\n");
for my $n (@targnames) {
  for my $c (@{$targets{$n}}) {
    my ($ra,$dec) = $c->radec;
    printf("%-20s %s  %s   %6.3f   %s\n",
	   $n,
	   $ra, $dec,
	   $c->airmass,
	   $c->type);
  }
}


# Subroutine to produce the region report type.

sub region_report {
  my $sp = shift;

  my $region = new OMP::SpRegion($sp);

  if ($mode_region) {
    if (lc($format) eq 'stcs') {
      $region->write_stcs(type => $mode_type);
    }
    elsif (lc($format) eq 'ast') {
      $region->write_ast(type => $mode_type);
    }
    else {
      die 'Unknown region output format ' . $format;
    }
  }

  if ($mode_plot) {
    require PGPLOT;
    require Starlink::AST::PGPLOT;

    my $pgdev = PGPLOT::pgopen('/xserve');
    PGPLOT::pgwnad(0, 1, 0, 1);
    PGPLOT::pgqwin(my $x1, my $y1, my $x2, my $y2);

    $region->plot_pgplot(type => $mode_type,
                         method => $plotting_method);
  }
}


=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001-2005 Particle Physics and Astronomy Research Council.
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
