#!perl

# Test that we can rotate coordinates correctly in the translators.

# Copyright (C) 2002-2005 Particle Physics and Astronomy Research Council.
# All Rights Reserved.

# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation; either version 2 of the License, or (at your option) any later
# version.

# This program is distributed in the hope that it will be useful,but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
# PARTICULAR PURPOSE. See the GNU General Public License for more details.

# You should have received a copy of the GNU General Public License along with
# this program; if not, write to the Free Software Foundation, Inc., 59 Temple
# Place,Suite 330, Boston, MA  02111-1307, USA

use Test::More tests => 36;
require_ok("OMP::Translator::DAS");
require_ok("OMP::Translator::SCUBA");

# Need to supply the cell definition, the offset coordinates and the
# expected answer

my @inputs = (
	      {
	       cellx => 1,
	       celly => 1,
	       cellpa => 0,
	       offx => 10,
	       offy => 10,
	       offpa => 0,
	       celloffx => 10,
	       celloffy => 10,
	      },
	      {
	       cellx => 5,
	       celly => 2,
	       cellpa => 0,
	       offx => 10,
	       offy => 10,
	       offpa => 0,
	       celloffx => 2,
	       celloffy => 5,
	      },
	      {
	       cellx => 10,
	       celly => 10,
	       cellpa => 0,
	       offx => 30,
	       offy => 40,
	       offpa => 0,
	       celloffx => 3,
	       celloffy => 4,
	      },
	      {
	       cellx => 10,
	       celly => 10,
	       cellpa => 90,
	       offx => 30,
	       offy => 40,
	       offpa => 0,
	       celloffx => -4,
	       celloffy => 3,
	      },
	      {
	       cellx => 10,
	       celly => 10,
	       cellpa => 90,
	       offx => 30,
	       offy => 40,
	       offpa => 90,
	       celloffx => 3,
	       celloffy => 4,
	      },
	      {
	       cellx => 10,
	       celly => 10,
	       cellpa => -45,
	       offx => 30,
	       offy => 40,
	       offpa => -45,
	       celloffx => 3,
	       celloffy => 4,
	      },
	      {
	       cellx => 10,
	       celly => 10,
	       cellpa => 36.87,  # 3,4,5 triangle
	       offx => 30,
	       offy => 40,
	       offpa => 0,
	       celloffx => 0,
	       celloffy => 5,
	      },
	      {
	       cellx => 10,
	       celly => 10,
	       cellpa => 0.0,  # 3,4,5 triangle
	       offx => 0,
	       offy => 50,
	       offpa => 36.87,
	       celloffx => 3,
	       celloffy => 4,
	      },
	      {
	       cellx => 1,
	       celly => 1,
	       cellpa => 0,
	       offx => 50,
	       offy => -126,
	       offpa => -128.0,
	       celloffx => 68.51,
	       celloffy => 116.97,
	      },
	      {
	       cellx => 1,
	       celly => 1,
	       cellpa => 0,
	       offx => -50,
	       offy => 0,
	       offpa => -36.87,
	       celloffx => -40,
	       celloffy => -30,
	      },
	      {
	       cellx => 5,
	       celly => 5,
	       cellpa => 53.13,
	       offx => -50,
	       offy => 0,
	       offpa => -36.87,
	       celloffx => 0,
	       celloffy => -10,
	      },
	     );

# Comparison format
my $f = '%.3f';

# Loop over all inputs
for my $test (@inputs) {
  my ($x,$y) = OMP::Translator::DAS::_convert_to_cell(
						      $test->{cellx},
						      $test->{celly},
						      $test->{cellpa},
						      $test->{offx},
						      $test->{offy},
						      $test->{offpa}
						     );

  # Create a string for tracking errors
  my $str = "Cell: ". $test->{cellx} .",". $test->{celly} ."," .$test->{cellpa} .
    " Offset: ". $test->{offx} . ",". $test->{offy} .",". $test->{offpa};

  # Convert the numbers to something comparable and test
  is(_fmt_float($x), _fmt_float($test->{celloffx}), "compare X with $str");
  is(_fmt_float($y), _fmt_float($test->{celloffy}), "compare Y with $str");

  # Test the SCUBA offsets. These are the same as the heterodyne offsets
  # except that the cell is always 1,1,0
  # For now skip inputs that have non-zero cell
  if ($test->{cellpa} == 0.0) {
    my %mapping = OMP::Translator::SCUBA->getOffsets(
						     OFFSET_PA => $test->{offpa},
						     OFFSET_DX => $test->{offx},
						     OFFSET_DY => $test->{offy},
						    );

    # Format (scaling by cellx and celly to correct)
    is(_fmt_float($mapping{MAP_X}),
       _fmt_float($test->{celloffx}*$test->{cellx}),
       "SCUBA compare X with $str");
    is(_fmt_float($mapping{MAP_Y}),
       _fmt_float($test->{celloffy}*$test->{celly}),
       "SCUBA compare Y with $str");


  }

}

exit;

# Helper routine to format the floating point number
# Also converts -0.00 to 0.00
# Returns a string.

sub _fmt_float {
  my $in = shift;
  my $f = '%.3f';
  my $out = sprintf($f,$in);

  # trap -0.00 by formatting a negative zero
  $out = sprintf($f,0.0) if $out eq sprintf($f,-0.0);
  return $out;
}
