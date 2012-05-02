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

# Must load AST early to avoid problems with PGPLOT.
use Starlink::AST;
use Astro::PAL;

# Locate the OMP software through guess work
use FindBin;
use lib "$FindBin::RealBin/..";

# External modules
use DateTime;
use Term::ReadLine;
use Math::Trig qw/pi/;

# OMP classes
use OMP::SciProg;
use OMP::ProjServer;
use OMP::SpServer;


# Options
my ($format, $mode_type, $plotting_method,
    $help, $man, $version, $mode_region, $mode_plot)
  = ('stcs', 'all', 'cmpregion');
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

  my @regions;

  # Data copied from JCMT::Survey::Coverage::RADIUS because
  # it is a private variable in that package and adding SCUBA
  # to allow older projects to be plotted.
  my %fov = (
              HARP      => 60,
              SCUBA     => 2.3 * 60,
              'SCUBA-2' => 5 * 60,
            );

  my %cmp = ();
  my %uniq = (all => {}, 'new' => {}, progress => {}, complete => {});
  my %separate = (all => [], 'new' => [], progress => [], complete => []);

  my $add_region = sub {
    my ($name, $region) = @_;

    push @{$separate{$name}}, $region;

    unless (exists $cmp{$name}) {
      $cmp{$name} = $region;
    }
    else {
      $cmp{$name} = $cmp{$name}->CmpRegion($region,
        Starlink::AST::Region::AST__OR(), '');
    }
  };

  die 'Type must be one of: '. join ', ', keys %uniq
    unless exists $uniq{$mode_type};

  foreach my $msb ($sp->msb) {
    my $remaining = $msb->remaining();
    my $observed  = $msb->observed();

    foreach my $obs ($msb->unroll_obs()) {
      # Retrieve Astro::Coords object
      my $coords = $obs->{'coords'};
      next if $coords->type() eq 'CAL';
      #use Data::Dumper; print Dumper($obs);

      if (exists $obs->{'OFFSET_DX'} or exists $obs->{'OFFSET_DY'}) {
        my $offset = new Astro::Coords::Offset(
          $obs->{'OFFSET_DX'} || 0,
          $obs->{'OFFSET_DY'} || 0,
          posangle   => $obs->{'OFFSET_PA'},
          'system'   => $obs->{'OFFSET_SYSTEM'} || 'J2000',
          projection => 'TAN');

        $coords = $offset->apply_offset($coords);
      }

      my $fov = $fov{$obs->{'instrument'}} || 1;
      my $height = $obs->{'MAP_HEIGHT'}    || $fov;
      my $width  = $obs->{'MAP_WIDTH'}     || $fov;
      $height    = $fov if $height < $fov;
      $width     = $fov if $width < $fov;
      my $radius = Astro::PAL::DAS2R
                 * (($height > $width) ? $height : $width) / 2;

      # Create a key so that we can check by uniqueness.
      my $id = sprintf('%.6f', $coords->ra2000()->radians())
       . ' ' . sprintf('%.6f', $coords->dec2000()->radians())
       . ' ' . $radius. "\n";

      my $skyframe = new Starlink::AST::SkyFrame('SYSTEM=FK5');

      my $region = Starlink::AST::Circle->new(
                             $skyframe, 1, [$coords->ra2000()->radians(),
                                        $coords->dec2000()->radians()],
                             [$radius], undef, '');

      push @regions, $region;
      $add_region->('all', $region) unless exists $uniq{'all'}->{$id};
      $uniq{'all'}->{$id} = 1;

      # Rearranged the if statements into this order to handle the
      # case where the 'observed' field is empty and shows 0 for everything:
      # now in-progress observations appear new rather than complete.
      if (! $remaining > 0 and ! exists $uniq{'complete'}->{$id}) {
        $add_region->('complete', $region);
        $uniq{'complete'}->{$id} = 1;
      }
      elsif (! $observed and ! exists $uniq{'new'}->{$id}) {
        $add_region->('new', $region);
        $uniq{'new'}->{$id} = 1;
      }
      elsif (! exists $uniq{'progress'}->{$id}) {
        $add_region->('progress', $region);
        $uniq{'progress'}->{$id} = 1;
      }
    }
  }

  if ($mode_region) {
    my $cmp = $cmp{$mode_type};

    if (lc($format) eq 'stcs') {
      my $ch = new Starlink::AST::StcsChan(sink => sub {print "$_[0]\n"});
      $ch->Write($cmp);
    }
    elsif (lc($format) eq 'ast') {
      $cmp->Show();
    }
    else {
      die 'Unknown region output format ' . $format;
    }
  }

  if ($mode_plot) {
    require PGPLOT;
    require Starlink::AST::PGPLOT;

    my (@lbnd, @ubnd);
    $cmp{'all'}->GetRegionBounds(\@lbnd, \@ubnd);

    my $fchan = new Starlink::AST::FitsChan();
    foreach (
        'NAXIS1  = 1000',
        'NAXIS2  = 1000 ',
        'CRPIX1  = 500 ',
        'CRPIX2  = 500',
        'CRVAL1  = ' . Astro::PAL::DR2D * ($lbnd[0] + $ubnd[0]) / 2,
        'CRVAL2  = ' . Astro::PAL::DR2D * ($lbnd[1] + $ubnd[1]) / 2,
        'CTYPE1  = \'RA---TAN\'',
        'CTYPE2  = \'DEC--TAN\'',
        'RADESYS = \'FK5\'',
        'CD1_1   = ' . Astro::PAL::DR2D * ($lbnd[0] - $ubnd[0]) / 1000,
        'CD2_2   = ' . Astro::PAL::DR2D * ($ubnd[1] - $lbnd[1]) / 1000,
      ) {$fchan->PutFits($_, 0);}
    $fchan->Clear('Card');
    my $wcs = $fchan->Read();

    my $pgdev = PGPLOT::pgopen('/xserve');
    PGPLOT::pgwnad(0, 1, 0, 1);
    PGPLOT::pgqwin(my $x1, my $y1, my $x2, my $y2);

    my $plot = new Starlink::AST::Plot($wcs, [0.0, 0.0, 1.0, 1.0],
                                       [0.5, 0.5, 1000.5, 1000.5],
                   'Grid=1,tickall=0,border=1,tol=0.001'
                   . ',colour(border)=4,colour(grid)=3,colour(ticks)=3'
                   . ',colour(numlab)=5,colour(axes)=3');
    $plot->pgplot();
    $plot->Grid();
    $plot->Set('System=FK5');

    my $fitswcsb = $plot->Get('Base');
    my $fitswcsc = $plot->Get('Current');

    my %colour = (
      'new' => 1,     # white
      progress => 2,  # red
      complete => 4); # blue

    foreach my $colour (keys %colour) {
      next unless exists $cmp{$colour};
      next unless $mode_type eq 'all' or $mode_type eq $colour;

      if ($plotting_method eq 'cmpregion') {
        my $cmp = $cmp{$colour};

        my $fs = $plot->Convert($cmp, '');
        $plot->Set('Base='.$fitswcsb);
        my $map = $fs->GetMapping(Starlink::AST::AST__BASE(),
                                  Starlink::AST::AST__CURRENT());
        $plot->AddFrame(Starlink::AST::AST__CURRENT(), $map, $cmp);
        $plot->Set('colour(border)='. $colour{$colour});
        $plot->Border();

        my $current = $plot->Get('Current');
        $plot->RemoveFrame($current);
        $plot->Set('Current='.$fitswcsc);
      }
      else {
        foreach my $cmp (@{$separate{$colour}}) {
          my $fs = $plot->Convert($cmp, '');
          $plot->Set('Base='.$fitswcsb);
          my $map = $fs->GetMapping(Starlink::AST::AST__BASE(),
                                    Starlink::AST::AST__CURRENT());
          $plot->AddFrame(Starlink::AST::AST__CURRENT(), $map, $cmp);
          $plot->Set('colour(border)='. $colour{$colour});
          $plot->Border();

          my $current = $plot->Get('Current');
          $plot->RemoveFrame($current);
          $plot->Set('Current='.$fitswcsc);
        }
      }
    }
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
