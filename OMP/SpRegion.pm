package OMP::SpRegion;

=head1 NAME

OMP::SpRegion - Create AST regions for Science Programs

=head1 SYNOPSIS

  my $sp = OMP::SpServer->fetchProgram(...);

  my $region = new OMP::SpRegion($sp);

  $region->write_stcs(type => 'all');
  $region->write_ast(type => 'all');

  # Prepare PGPLOT device.
  $region->plot_pgplot(type => 'all', method => 'separate');

=head1 DESCRIPTION

This class can be used to create AST regions for all of the
observations in a Science Programme.

=cut

use strict;
use warnings;

use Starlink::AST;
use Starlink::ATL::Region qw/merge_regions/;
use Astro::Coords;
use Astro::Coords::Offset;
use Astro::PAL;

# Calculate bounds for Polygons and CmpRegions manually?
use constant WORKAROUND_BOUNDS => 1;
# Defer CmpRegion creation until we really need it?
use constant DEFER_CMPREGION => 1;

=head1 DATA

=over 4

=item B<%fov_inst>

Specifies the field of view for each instrument, to be used as the
minimum field size.

=cut

# Data copied from JCMT::Survey::Coverage::RADIUS because
# it is a private variable in that package and adding SCUBA
# to allow older projects to be plotted.
# Also added WFCAM detector size from the OT.
our %fov_inst = (
              HARP      => 60,
              SCUBA     => 2.3 * 60,
              'SCUBA-2' => 5 * 60,
              WFCAM     => 817.2,
            );

# Gap between detectors as a fraction of the detector size.
our $WFCAM_SPACING = 0.94;

=back

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

Reads the specified Science Programme and constructs an object containing
AST regions for the objects within.

  my $region = new OMP::SpRegion($sp);

Returns undef if there are no regions found in the Science Programme.

=cut

sub new {
  my $class = shift;
  my $sp = shift;
  my %opt = @_;


  my $self = {
    'cmp' => {},
    separate => {all => [], 'new' => [], progress => [], complete => []},
    lbnd => [],
    ubnd => [],
    uniq => {all => {}, 'new' => {}, progress => {}, complete => {}},
  };

  bless $self, $class;
  my $skyframe = new Starlink::AST::SkyFrame('SYSTEM=FK5');

  foreach my $msb ($sp->msb) {
    my $remaining = $msb->remaining();
    my $observed  = $msb->observed();

    # Ensure that the obsnum counters are present to avoid errors
    # creating obslabel strings as part of the unrolling.  This is
    # unfortunately necessary because we will have fetched the XML
    # in non-internal mode which will have cleared out the counters
    # (unless the XML was old in which case the fixup method would
    # have resulted in the counters being read from the XML before
    # being cleared).  Please see Trac ticket 130 for discussion.
    $msb->_set_obs_counter();

    foreach my $obs ($msb->unroll_obs()) {
      # Retrieve Astro::Coords object
      my $coords = $obs->{'coords'};
      next if $coords->type() eq 'CAL';
      #use Data::Dumper; print Dumper($obs);

      if (exists $obs->{'OFFSET_DX'} or exists $obs->{'OFFSET_DY'}) {
        my $offset = new Astro::Coords::Offset(
          $obs->{'OFFSET_DX'} || 0,
          $obs->{'OFFSET_DY'} || 0,
          posang   => $obs->{'OFFSET_PA'},
          'system'   => $obs->{'OFFSET_SYSTEM'} || 'J2000',
          projection => 'TAN');

        $coords = $coords->apply_offset($offset);
      }

      my ($ra2000, $dec2000) = $coords->radec2000();
      my $fov = $fov_inst{$obs->{'instrument'}} || 1;
      my $height = $obs->{'MAP_HEIGHT'}    || $fov;
      my $width  = $obs->{'MAP_WIDTH'}     || $fov;
      $height    = $fov if $height < $fov;
      $width     = $fov if $width < $fov;
      my $radius = Astro::PAL::DAS2R
                 * (($height > $width) ? $height : $width) / 2;

      # Create a key so that we can check by uniqueness.
      my $id = sprintf('%.6f %.6f %.6f',
                       $ra2000->radians(),
                       $dec2000->radians(),
                       $radius);

      my $region = undef;

      if ($obs->{'instrument'} eq 'WFCAM') {
        $region = [];
        $id = [];

        foreach my $of ([1, 1], [1, -1], [-1, -1], [-1, 1]) {
          my $subarray_offset = new Astro::Coords::Offset(
                                  $of->[0] * $fov * (1 + $WFCAM_SPACING) / 2,
                                  $of->[1] * $fov * (1 + $WFCAM_SPACING) / 2,
                                  posang => 0,
                                  'system' => 'J2000',
                                  projection => 'TAN');
          my $subarray = $coords->apply_offset($subarray_offset);
          my ($ra2000, $dec2000) = $subarray->radec2000();
          push @$id, sprintf('%.6f %.6f %.6f',
                       $ra2000->radians(),
                       $dec2000->radians(),
                       $radius);
          my @corner = ();

          foreach my $cf ([-1, 1], [1, 1], [1, -1], [-1, -1]) {
            my $offset = new Astro::Coords::Offset(
                             $cf->[0] * $fov / 2, $cf->[1] * $fov / 2,
                             posang     => 0,
                             'system'   => 'J2000',
                             projection => 'TAN');
            push @corner, $subarray->apply_offset($offset);

            WORKAROUND_BOUNDS && $self->_add_bounds(
              map {$_->radians()} $corner[-1]->radec2000());
          }

          my $subregion = new Starlink::AST::Polygon($skyframe,
                                    [map {my ($ra,  undef) = $_->radec2000();  $ra->radians()} @corner],
                                    [map {my (undef, $dec) = $_->radec2000(); $dec->radians()} @corner],
                                    undef, '');

          push @$region, $subregion;
        }
      }
      elsif (not (lc($obs->{'scanPattern'}) eq 'boustrophedon'
               or lc($obs->{'scanPattern'}) eq 'raster')) {
        $region = Starlink::AST::Circle->new(
                             $skyframe, 1, [$ra2000->radians(),
                                        $dec2000->radians()],
                             [$radius], undef, '');

        WORKAROUND_BOUNDS && $self->_add_bounds($region);
      }
      else {
        my @corner = ();
        foreach my $cf ([-1, 1], [1, 1], [1, -1], [-1, -1]) {
          my $system = 'J2000';
          $system = 'GAL' if $coords->native() eq 'glonglat';
          my $offset = new Astro::Coords::Offset(
                             $cf->[0] * $width / 2, $cf->[1] * $height / 2,
                             posang     => $obs->{'MAP_PA'},
                             'system'   => $system,
                             projection => 'TAN');
          push @corner, $coords->apply_offset($offset);

          WORKAROUND_BOUNDS && $self->_add_bounds(
            map {$_->radians()} $corner[-1]->radec2000());
        }

        $region = new Starlink::AST::Polygon($skyframe,
                                    [map {my ($ra,  undef) = $_->radec2000();  $ra->radians()} @corner],
                                    [map {my (undef, $dec) = $_->radec2000(); $dec->radians()} @corner],
                                    undef, '');
      }

      die 'OMP::SpRegion: failed to create region' unless defined $region;

      foreach my $subregion (ref $region eq 'ARRAY' ? @$region : $region) {
        my $subid = ref $id ? shift @$id : $id;

        $self->_add_region('all', $subregion, $subid);

        # Rearranged the if statements into this order to handle the
        # case where the 'observed' field is empty and shows 0 for everything:
        # now in-progress observations appear new rather than complete.
        if (! $remaining > 0) {
          $self->_add_region('complete', $subregion, $subid);
        }
        elsif (! $observed) {
          $self->_add_region('new', $subregion, $subid);
        }
        else {
          $self->_add_region('progress', $subregion, $subid);
        }
      }
    }
  }

  return undef unless scalar @{$self->{'separate'}->{'all'}};
  return $self;
}

=back

=head2 General Methods

=over 4

=item B<write_ast>

Writes an AST CmpRegion file to standard output.  An optional C<type> parameter
can specify the type of MSBs to be included:

=over 4

=item *

all

=item *

new: MSBs which have not been observed

=item *

progress: MSBs which have been observed but are not complete

=item *

complete: MSBs with no repeats remaining

=back

=cut

sub write_ast {
  my $self = shift;
  my %opt = @_;
  my $type = $opt{'type'} || 'all';
  die 'OMP::SpRegion: type must be one of: ' . join ', ', keys %{$self->{'separate'}}
    unless exists $self->{'separate'}{$type};

  DEFER_CMPREGION && $self->_build_cmpregion($type);

  my $cmp = $self->{'cmp'}->{$type};
  return unless $cmp;
  $cmp->Show();
}

=item B<write_stcs>

Writes an STCS description to standard output, taking a C<type> parameter
as for C<write_ast>.

=cut

sub write_stcs {
  my $self = shift;
  my %opt = @_;
  my $type = $opt{'type'} || 'all';
  die 'OMP::SpRegion: type must be one of: ' . join ', ', keys %{$self->{'separate'}}
    unless exists $self->{'separate'}{$type};

  DEFER_CMPREGION && $self->_build_cmpregion($type);

  my $cmp = $self->{'cmp'}->{$type};
  return unless $cmp;
  my $ch = new Starlink::AST::StcsChan(sink => sub {print "$_[0]\n"});
  $ch->Write($cmp);
}


=item B<plot_pgplot>

Plots the region with PGPLOT.  This takes a C<type> parameter as for C<write_ast>
and also a C<method> parameter which can be:

=over 4

=item *

separate: draw each region separately

=item *

cmpregion: plot the whole AST cmpregion

=back

The calling function should already have prepared the PGPLOT device.

  $region->plot_pgplot(type => 'all', method => 'separate');

=cut

sub plot_pgplot {
  my $self = shift;
  my %opt = @_;
  my $type = $opt{'type'} || 'all';
  die 'OMP::SpRegion: type must be one of: ' . join ', ', keys %{$self->{'separate'}}
  unless exists $self->{'separate'}{$type};

  my $wcs = $self->_make_wcs($opt{'system'}, $opt{'bounds'});

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
    next unless exists $self->{'cmp'}->{$colour}
      or DEFER_CMPREGION && scalar @{$self->{'separate'}->{$colour}};
    next unless $type eq 'all' or $type eq $colour;

    if ((defined $opt{'method'}) && ($opt{'method'} eq 'cmpregion')) {

      DEFER_CMPREGION && $self->_build_cmpregion($colour);

      my $cmp = $self->{'cmp'}->{$colour};
      next unless $cmp;

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
      foreach my $cmp (@{$self->{'separate'}->{$colour}}) {
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

=back

=head2 Internal Methods

=over 4

=item B<_add_region>

Adds a region to the object.  It is stored both as a separate region
and added to the CmpRegion for the given type.  A unique ID label must be
given to allow this method to reject duplicate regions.

  $self->_add_region($type, $region, $id);

If the DEFER_CMPREGION constant is set to a true value, we skip adding
the region to the CmpRegion.

=cut

sub _add_region {
  my $self = shift;
  my ($name, $region, $id) = @_;

  return if exists $self->{'uniq'}->{$name}->{$id};
  $self->{'uniq'}->{$name}->{$id} = 1;

  push @{$self->{'separate'}->{$name}}, $region;

  return if DEFER_CMPREGION;

  unless (exists $self->{'cmp'}->{$name}) {
    $self->{'cmp'}->{$name} = $region;
  }
  else {
    $self->{'cmp'}->{$name}
      = $self->{'cmp'}->{$name}->CmpRegion($region,
          Starlink::AST::Region::AST__OR(), '');
  }
}

=item B<_build_cmpregion>

Checks that the given AST CmpRegion has been built.

=cut

sub _build_cmpregion {
  my $self = shift;
  my $name = shift;

  return if exists $self->{'cmp'}->{$name};
  return unless scalar @{$self->{'separate'}->{$name}};

  $self->{'cmp'}->{$name} = merge_regions($self->{'separate'}->{$name});
}

=item B<_add_bounds>

If the bounds are being handled 'manually', extend them to include the
given region or specific point.

  $self->_add_bounds($region);
  $self->_add_bounds($ra2000radians, $dec2000radians);

=cut

sub _add_bounds {
  my $self = shift;
  my $region = shift;

  WORKAROUND_BOUNDS || die 'Calling OMP::SpRegion::_add_bounds unnecessarily';

  my (@l, @u);

  if (ref $region) {
    my ($l, $u) = $region->GetRegionBounds();
    @l = @$l; @u = @$u;
  }
  else {
    @l = ($region, shift);
    @u = @l;
  }

  foreach (0, 1) {
    $self->{'lbnd'}->[$_] = $l[$_] if (! defined $self->{'lbnd'}->[$_]
                                       || $l[$_] < $self->{'lbnd'}->[$_]);
    $self->{'ubnd'}->[$_] = $u[$_] if (! defined $self->{'ubnd'}->[$_]
                                       || $u[$_] > $self->{'ubnd'}->[$_]);
  }
}

=item B<_make_wcs>

Creates a FITS header specifying a region to encompass the bounds of
all the regions in the Science Program, and uses this to return
a suitable AST object.

=cut

sub _make_wcs {
  my $self = shift;
  my $system = shift;
  my $bounds = shift;

  my @lbnd = @{$self->{'lbnd'}};
  my @ubnd = @{$self->{'ubnd'}};

  my ($xaxis, $yaxis);

  if ($system and $system =~ /^gal/i) {
    $xaxis = 'GLON';
    $yaxis = 'GLAT';
    $system = 'GAL';
  }
  else {
    $xaxis = 'RA--';
    $yaxis = 'DEC-';
    $system = 'FK5';
  }

  if ($bounds) {
    my @bounds = split ',', $bounds;
    die 'Wrong number of bounds' unless 4 == scalar @bounds;
    @lbnd = @bounds[0, 2];
    @ubnd = @bounds[1, 3];
  }
  elsif (! WORKAROUND_BOUNDS) {

    DEFER_CMPREGION && $self->_build_cmpregion('all');

    my $all = $self->{'cmp'}->{'all'};
    my ($l, $u);

    if ($system eq 'GAL') {
      my $galframe = new Starlink::AST::SkyFrame('SYSTEM=GALACTIC');
      my $frameset = $all->Convert($galframe, '');
      my $galregion = $all->MapRegion($frameset, $galframe);
      ($l, $u) = $galregion->GetRegionBounds();
    }
    else {
      ($l, $u) = $all->GetRegionBounds();
    }
    @lbnd = @$l; @ubnd = @$u;
  }

  my $width = $lbnd[0] - $ubnd[0];
  my $height = $ubnd[1] - $lbnd[1];

  # Check aspect ratio is going to give a sensible projection
  # Do not apply corrections if user specified explit bounds (in degrees)
  unless ($bounds) {
    my $border_factor = 1.2;

    $width *= Astro::PAL::DR2D * $border_factor;
    $height *= Astro::PAL::DR2D * $border_factor;

    if ($height < 0.5 * -$width) {$height = -$width;};
    if (-$width < 0.5 * $height) {$width  = -$height};
  }

  $height =  180 if $height >  180;
  $width  = -360 if $width  < -360;

  my $xmid = ($lbnd[0] + $ubnd[0]) / 2;
  my $ymid = ($lbnd[1] + $ubnd[1]) / 2;

  unless ($bounds) {
    $xmid *= Astro::PAL::DR2D;
    $ymid *= Astro::PAL::DR2D;
  }

  $ymid = 0 if ($ymid + ($height / 2)) > 90
               || ($ymid - ($height / 2)) < -90;

  # Create FITS header and pass to AST

  my $fchan = new Starlink::AST::FitsChan();
  foreach (
        'NAXIS1  = 1000',
        'NAXIS2  = 1000 ',
        'CRPIX1  = 500 ',
        'CRPIX2  = 500',
        'CRVAL1  = ' . $xmid,
        'CRVAL2  = ' . $ymid,
        'CTYPE1  = \'' . $xaxis . '-MER\'',
        'CTYPE2  = \'' . $yaxis . '-MER\'',
        'CD1_1   = ' . $width / 1000,
        'CD2_2   = ' . $height / 1000,
    ) {$fchan->PutFits($_, 0);}
  $fchan->PutFits('RADESYS = \'' . $system . '\'', 0) unless $system eq 'GAL';
  $fchan->Clear('Card');
  my $wcs = $fchan->Read();
  return $wcs;
}


1;

__END__

=back

=cut
