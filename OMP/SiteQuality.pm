package OMP::SiteQuality;

=head1 NAME

OMP::SiteQuality - Site quality helper functions

=head1 SYNOPSIS

  use OMP::SiteQuality;

  ($dbmin, $dbmax) = to_db( 'TAU', $skyrange );
  $range = from_db( 'SEEING', $dbskymin, $dbskymax );
  $range = default_range( 'SKY' );
  print "default" if is_default( 'TAU', $range );

  check_posdef( 'TAU', $range );
  undef_to_default( 'TAU', $range );

  $range = upgrade_cloud( $oldcloud );
  $range = upgrade_moon( $oldmoon );

  $range = get_tauband_range('JCMT', @bands);
  $band  = determine_tauband( TELESCOPE => 'JCMT', TAU => 0.05);

=head1 DESCRIPTION

Helper functions for handling site quality issues.

=cut

use 5.006;
use strict;
use warnings;
use warnings::register;
use Carp;

use OMP::Error;
use OMP::Range;

use vars qw/ $VERSION %DBRANGES %OMPRANGES %CLOUDTERMS/;
$VERSION = sprintf("%d", q$Revision$ =~ /(\d+)/);


=head1 CONSTANTS

Constants for backwards compatibility conversions of cloud and
moon integers to explicit ranges.

=over 4

=item B<OMP__CLOUD_CIRRUS_MAX>

The %age attenuation variability associated with cirrus conditions.

=cut

use constant OMP__CLOUD_CIRRUS_MAX => 20;

=item B<OMP__MOON_GREY_MAX>

The %age moon illumination when transitioning from grey to bright.

=cut

use constant OMP__MOON_GREY_MAX    => 25;

=item B<OMP__SKYBRIGHT_INF>

Definition of infinite sky brightness to be used in the database
table instead of NULL.

=cut

use constant OMP__SKYBRIGHT_INF => 1E9;

=item B<OMP__TAU_INF>

Definition of infinite tau to be used in the database table instead
of NULL.

=cut

use constant OMP__TAU_INF => 101;

=item B<OMP__SEEING_INF>

Definition of infinite seeing to be used in the database table instead
of NULL.

=cut

use constant OMP__SEEING_INF => 5000;

=back

=cut

# look up table

# These are the infinite ranges from the viewpoint of the database
# if these suddenly become floating point numbers the from_db
# routine needs to be made cleverer.
%DBRANGES = (
	     TAU => [ 0, OMP__TAU_INF ],
	     SEEING => [ 0, OMP__SEEING_INF ],
	     SKY => [ -1 * OMP__SKYBRIGHT_INF,
		      OMP__SKYBRIGHT_INF ],
	     CLOUD => [ 0, 100],
	     MOON => [ 0, 100 ],
	    );

# these are the default min/max ranges from the viewpoint of the user
%OMPRANGES = (
	      TAU => [ 0, undef ],
	      SEEING => [ 0, undef ],
	      SKY => [ undef, undef ],
	      CLOUD => [ 0, 100],
	      MOON => [ 0, 100 ],
	     );

# These are the textual descriptions of the common cloud ranges
%CLOUDTERMS = (
	       Photometric => [0, 0],
	       Cirrus => [1, OMP__CLOUD_CIRRUS_MAX],
	       Thick => [OMP__CLOUD_CIRRUS_MAX+1, 100],
	      );

=head1 FUNCTIONS

=over 4

=item B<to_db>

Given a site quality category and either a range object or a min and max,
return back numbers suitable for insertion into a database. Any unbounded
ranges will be converted to bound ranges for the database.

 ($dbmin, $dbmax) = to_db( 'TAU', $range );
 ($dbmin, $dbmax) = to_db( 'SEEING', $minin, $maxin );

undef is allowed as the lone second argument rather than an OMP::Range
object.

Allowed categories are "TAU", "SEEING", "CLOUD", "MOON", and "SKY".

=cut


sub to_db {
  my $cat = uc(shift);
  throw OMP::Error::BadArgs("Unrecognized site quality")
    if !exists $DBRANGES{$cat};

  # read the arguments as either list or range object
  my ($minin, $maxin);
  if (scalar(@_) == 1) {
    my $r = shift;
    ($minin, $maxin) = $r->minmax if defined $r;
  } elsif (scalar(@_) == 2) {
    ($minin, $maxin) = @_;
  } else {
    throw OMP::Error::BadArgs("to_db() requires 2 or 3 args");
  }

  # convert undefs to these values
  my $min = ( defined $minin ? $minin : $DBRANGES{$cat}->[0]);
  my $max = ( defined $maxin ? $maxin : $DBRANGES{$cat}->[1]);

  return ( $min, $max );
}

=item B<from_db>

Convert from database format to standard form. Takes a site quality
type (as described in C<to_db>) and an upper and lower limit from the
database, and returns an OMP::Range object. Values that have the DB
value will be converted to the equivalent non-DB limit.

  $range = from_db( 'TAU', $min, $max );

If an C<OMP::Range> object is supplied, it is modified in place
and also returned.

Only processes defined values so will not replace an undefined
taumin with the default value (0). Use C<undef_to_default()> to
fixup undefs.

=cut

sub from_db {
  my $cat = uc(shift);
  throw OMP::Error::BadArgs("Unrecognized site quality")
    if !exists $OMPRANGES{$cat};

  my $range;
  if (!scalar(@_)) {
    throw OMP::Error::BadArgs("from_db() requires more than 1 arg");
  } elsif (scalar(@_) == 1) {
    $range = shift;
  } elsif (scalar(@_) == 2) {
    $range = new OMP::Range( Min => $_[0], Max => $_[1]);
  } else {
    throw OMP::Error::BadArgs("from_db() requires 2 or 3 args");
  }

  # convert +/-INF to undef
  # We have to be careful with precision in numeric equality from
  # the REAL types used in the database tables

  # format everything before doing comparison
  my $fmt = '%.7f';
  my $i = 0;
  for my $m (qw/ min max / ) {
    # change the value if the current value is defined and matches
    # the reference value to the formatted precision
    # note that we format and then convert to number for equality test
    $range->$m( $OMPRANGES{$cat}->[$i] )
       if (defined $range->$m() &&
	   sprintf($fmt,$range->$m()) == sprintf($fmt,$DBRANGES{$cat}->[$i]));

    # increment index into DBRANGES array
    $i++;
  }

  # Round the numbers coming from the database so that, say
  # 0.0500000112323 comes out as 0.05 when we store it in a perl Double
  # loop over min max
  for my $m (qw/ min max /) {
    my $val = $range->$m();
    next unless defined $val;

    # convert to string and back to number
    $val = sprintf( $fmt, $val) + 0;

    # store it back
    $range->$m( $val );
  }

  # if the default min range is 0, set the pos_def flag
  $range->pos_def( 1 ) if (defined $OMPRANGES{$cat}->[0] &&
			   $OMPRANGES{$cat}->[0] == 0);

  return $range;
}

=item B<default_range>

Given a site quality type (see list described in C<to_db>) return an
C<OMP::Range> object using the default settings.

  $range = default_range( 'TAU' );

In list context simply returns the min and max values.

  ($min, $max) = default_range( 'SEEING' );

=cut

sub default_range {
  my $cat = uc(shift);
  throw OMP::Error::BadArgs("Unrecognized site quality")
    if !exists $OMPRANGES{$cat};

  my $def = new OMP::Range( Min => $OMPRANGES{$cat}->[0],
			    Max => $OMPRANGES{$cat}->[1],
			    PosDef => ( defined $OMPRANGES{$cat}->[0] && $OMPRANGES{$cat}->[0] == 0 ? 1 : 0),
			  );

  return (wantarray ? $def->minmax : $def );
}

=item B<check_posdef>

Given a site quality category and a range object, set the positive
definite status.

 check_posdef( 'TAU', $range );

=cut

sub check_posdef {
  my $cat = uc(shift);
  throw OMP::Error::BadArgs("Unrecognized site quality")
    if !exists $OMPRANGES{$cat};

  my $range = shift;
  return if !defined $range;
  return if !defined $OMPRANGES{$cat}->[0];

  $range->pos_def( $OMPRANGES{$cat}->[0] == 0 ? 1 : 0);
}

=item B<is_default>

Given a OMP::Range object, returns true if the range contains the
default limits.

  print "default" if is_default( 'TAU', $range );

=cut

sub is_default {
  my $cat = uc(shift);
  throw OMP::Error::BadArgs("Unrecognized site quality")
    if !exists $OMPRANGES{$cat};
  my $range = shift;

  # create the default range
  my $def = new OMP::Range( Min => $OMPRANGES{$cat}->[0],
			    Max => $OMPRANGES{$cat}->[1],
			  );

  return $range->equate( $def );
}

=item B<undef_to_default>

Given a site quality type and a range object, convert any
undefs to the default constraint (which may also be undef).

  undef_to_default( 'TAU', $range );

This can be called immediately after from_db() to fix up
problems with unbound limits that were read from a NULL
column in the database.

=cut

sub undef_to_default {
  my $cat = uc(shift);
  throw OMP::Error::BadArgs("Unrecognized site quality")
    if !exists $OMPRANGES{$cat};
  my $range = shift;
  throw OMP::Error::BadArgs("undef_to_default:Must provide a range object")
    if !defined $range;

  $range->min( $OMPRANGES{$cat}->[0] ) if !defined $range->min;
  $range->max( $OMPRANGES{$cat}->[1] ) if !defined $range->max;
  return;
}

=item B<upgrade_cloud>

Convert a single moon parameter as used in the old system
(0=photometric, 1=cirrus, 101=inf) to an OMP::Range object
using percentage illumination variability.

  $range = upgrade_cloud( $oldcloud );

If the supplied number is greater than 100 or less than 0 it is
brought into the range 0 to 100%. If the supplied number is greater than
1 and less than 101 it is assumed to be an explicit percentage.

=cut

sub upgrade_cloud {
  my $old = shift;

  my ($min,$max);
  if ($old <= 0) {
    ($min,$max) = ( 0, 0 );
  } elsif ($old == 1) {
    ($min,$max) = (0, OMP__CLOUD_CIRRUS_MAX);
  } elsif ($old >= 101) {
    ($min,$max) = (0,100);
  } else {
    ($min,$max) = (0, $old);
  }
  return new OMP::Range( Min => $min, Max => $max, posdef => 1 );
}

=item B<upgrade_moon>

Convert a single moon parameter as used in the old system (0=dark,
1=grey,101=inf) to an OMP::Range object using percentage illumination.

  $range = upgrade_moon( $oldmoon );

If the supplied number is greater than 100 or less than 0 it is
brought into the range 0 to 100%. If the supplied number is greater than
1 and less than 101 it is assumed to be an illumination.

=cut

sub upgrade_moon {
  my $old = shift;

  my ($min,$max);
  if ($old <= 0) {
    ($min,$max) = ( 0, 0 );
  } elsif ($old == 1) {
    ($min,$max) = (0, OMP__MOON_GREY_MAX);
  } elsif ($old >= 101) {
    ($min,$max) = (0,100);
  } else {
    ($min,$max) = (0, $old);
  }
  return new OMP::Range( Min => $min, Max => $max, posdef => 1 );
}

=item B<determine_tauband>

Determine the tau allocation band(s) corresponding to specific tau values.

  $band = determine_tauband( %details );

The band is determined from the supplied details. Recognized
keys are:

  TAU       - a single CSO tau
  TAURANGE  - OMP::Range object containing a tau range
  TELESCOPE - name of the telescope

Currently TAU or TAURANGE are only used if TELESCOPE=JCMT. In all
other cases (and if TELESCOPE is not supplied) the band returned is 0.
If TELESCOPE=JCMT either TAU or TAURANGE must be present. An exception
is thrown if neither TAU nor TAURANGE are present.

From a single tau value it is not possible to distinguish a split band
(e.g. "2*") from a "normal" band (e.g. "2"). In these cases the normal
band is always returned.

If a tau range is supplied, this method will return an array of all
bands present in that range (including partial bands). In this
case starred bands will be recognized correctly.

  $band = determine_tauband( TELESCOPE => 'JCMT', TAU => 0.06 );

=cut

sub determine_tauband {
  my %details = @_;

  # JCMT is the only interesting one
  my $band;
  if (exists $details{TELESCOPE} and $details{TELESCOPE} eq 'JCMT') {

    if (exists $details{TAU}) {
      my $cso = $details{TAU};
      throw OMP::Error::FatalError("CSO TAU supplied but not defined. Unable to determine band")
	unless defined $cso;

      # do not use the OMP::Range objects here (yet KLUGE) because
      # OMP::Range can not yet do >= with the contains method
      if ($cso >= 0 && $cso <= 0.05) {
	$band = 1;
      } elsif ($cso > 0.05 && $cso <= 0.08) {
	$band = 2;
      } elsif ($cso > 0.08 && $cso <= 0.12) {
	$band = 3;
      } elsif ($cso > 0.12 && $cso <= 0.2) {
	$band = 4;
      } elsif ($cso > 0.2 && $cso <= 0.32) {
	$band = 5;
      } elsif ($cso > 0.32) {
	$band = 6;
      } else {
	throw OMP::Error::FatalError("CSO tau out of range: $cso\n");
      }

    } elsif (exists $details{TAURANGE}) {

      croak "Sorry. Not yet supported. Please write\n";

    } else {
      throw OMP::Error::FatalError("Unable to determine band for JCMT without TAU");
    }


  } else {
    # Everything else is boring
    $band = 0;
  }

  return $band;
}

=item B<get_tauband_range>

Given a band name, return the OMP::Range object that defines the band.
The use of a tau band simplifies the allocation process by allowing a
single integer to refer to a tau range.  The band definitions are
telescope specific.

  $range = get_tauband_range($telescope, @bands);

If multiple bands are supplied the range will include the extreme values.
(BUG: no check is made to determine whether the bands are contiguous)

Only defined for JCMT. Returns an unbounded range (lowe limit zero) for
any other telescope.

Returns undef if the band is not known.

=cut

{
  # Specify the bands
  my %bands = (
	       0   => new OMP::Range( Min => 0 ),
	       1   => new OMP::Range( Min => 0,    Max => 0.05),
	       2   => new OMP::Range( Min => 0.05, Max => 0.08),
	       3   => new OMP::Range( Min => 0.08, Max => 0.12),
	       4   => new OMP::Range( Min => 0.12, Max => 0.20),
	       5   => new OMP::Range( Min => 0.20, Max => 0.32),
	       6   => new OMP::Range( Min => 0.32 ),
	       '2*' => new OMP::Range( Min => 0.05, Max => 0.10),
	       '3*' => new OMP::Range( Min => 0.10, Max => 0.12),
	      );

  sub get_tauband_range {
    my $tel = shift;
    my @bands = @_;

    my ($defmin, $defmax) = default_range("TAU");

    if (defined $tel && $tel eq 'JCMT') {

      my ($min, $max) = (50,-50);
      for my $band (@bands) {
	if (exists $bands{$band}) {
	  my ($bmin, $bmax) = $bands{$band}->minmax;
	  $min = $bmin if $bmin < $min;
	  # Take into account unbounded upper limit
	  $max = $bmax if (!defined $bmax || $bmax > $max);
	} else {
	  return undef;
	}

      }

      # trap case where there were no inputs
      $min = $defmin if (defined $min && $min == 50);
      $max = $defmax if (defined $max && $max == -50);


      return new OMP::Range( Min => $min, Max => $max );


    } else {
      return $bands{"0"};
    }

  }
}

=item B<get_cloud_text>

Return the textual descriptions associated with the common cloud ranges.
The ranges are represented by C<OMP::Range> objects.

  %cloudtxt = cloud_text();

=cut

sub get_cloud_text {
  my %cloudtxt = map {$_, new OMP::Range( Min => $CLOUDTERMS{$_}->[0],
					  Max => $CLOUDTERMS{$_}->[1])} keys %CLOUDTERMS;
  return %cloudtxt;
}



=back

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2005 Particle Physics and Astronomy Research
Council.  All Rights Reserved.

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

1;
