#!perl

# Test the OMP::SciProg class
# and the related MSB classes. Does not interact with the database.

use warnings;
use strict;
use Test;
use Data::Dumper;


BEGIN { plan tests => 139 }

use OMP::SciProg;

# The MSB summary is indexed by checksum
# This information needs to change if the Science program
# is modified by dumping a new data structure.

# Read the data hash 
use vars qw/ $VAR1 /;
$/ = undef;
my $text = <DATA>;
eval "$text";
die "Error evaluating code in DATA handle: $@" if $@;

my %results = %$VAR1;


# Filename - use the test XML that covers all the bases
my $file = "test.xml";

my $obj = new OMP::SciProg( FILE => $file );

ok($obj);

# Check the project ID
ok($obj->projectID, "M01BTJ");

# Now count the number of MSBs
# Should be 9
my @msbs = $obj->msb;
ok(scalar(@msbs), 9);

# Go through the MSBs to see what we can find out about them
for my $msb ($obj->msb) {
  if (exists $results{$msb->checksum}) {
    ok(1);

    my %cmp = %{ $results{ $msb->checksum} };
    my %msbsum = $msb->summary;

    for my $key (keys %cmp) {

      # Special case for the obs array
      # Really need a recursive comparator
      if ($key eq 'obs') {

	foreach my $i (0..$#{$cmp{$key}}) {
	  my %obs = %{$msbsum{$key}[$i]};
	  my %cmpobs = %{$cmp{$key}[$i]};

	  foreach my $obskey (keys %cmpobs) {
	    # Skipping refs prevents comparison of coordinates
	    next if ref($cmpobs{$obskey});

	    ok($obs{$obskey}, $cmpobs{$obskey});
	  }
	}

      } else {

	next if ref( $cmp{$key});
	ok( $msbsum{$key}, $cmp{$key});
	
      }

    }

  } else {
    ok(0);
    # skip the next few tests
    skip("Pointless testing MSB when checksum does not match",1);
  }
}

# Generate a summary
my @summary = $obj->summary;

# make sure the number of summaries matches the number of msbs
# + header
ok( scalar(@summary), 1+scalar(@msbs));

# For information print them all out
# Need to include the "#"
print map { "#$_\n" } @summary;

# Print out in a form that will let us simply cut and paste
# this information to the top of the page for comparison
exit;
if (1) {
  my %summary;
  for my $msb ($obj->msb) {
    my %msbsum = $msb->summary;

    # Remove stuff we aren't interested in
    delete $msbsum{checksum};
    delete $msbsum{summary};
    delete $msbsum{_obssum};

    # Store it
    $summary{ $msb->checksum } = \%msbsum;
  }

  # Now print the result
  print Dumper(\%summary);

}


exit;


# This is the comparison data structure

__DATA__
$VAR1 = {
          '9d96e30de1b6cb6a2e06f793fa85da49' => {
                                                  'seeing' => '1',
                                                  'title' => 'UFTI standards',
                                                  'timeest' => 1,
                                                  'projectid' => 'M01BTJ',
                                                  'remaining' => '2',
                                                  'tauband' => '1',
                                                  'obscount' => 2,
                                                  'obs' => [
                                                             {
                                                               'wavelength' => 'unknown',
                                                               'coordstype' => 'RADEC',
                                                               'target' => 'FS1',
                                                               'obstype' => [
                                                                              'Dark',
                                                                              'Observe'
                                                                            ],
                                                               'filter' => 'Z',
                                                               'coords' => bless( {
                                                                                    'dec2000' => '-0.211752071498212',
                                                                                    'ra2000' => '0.147946251981751'
                                                                                  }, 'Astro::Coords::Equatorial' ),
                                                               'instrument' => 'UFTI'
                                                             },
                                                             {
                                                               'wavelength' => 'unknown',
                                                               'coordstype' => 'RADEC',
                                                               'target' => 'FS2',
                                                               'obstype' => [
                                                                              'Dark',
                                                                              'Observe'
                                                                            ],
                                                               'filter' => 'I',
                                                               'coords' => bless( {
                                                                                    'dec2000' => '0.0125717035648514',
                                                                                    'ra2000' => '0.240704902127233'
                                                                                  }, 'Astro::Coords::Equatorial' ),
                                                               'instrument' => 'UFTI'
                                                             }
                                                           ],
                                                  'priority' => 3
                                                },
          '38dc5ccd06862f24bca0c18257d3b13aA' => {
                                                   'seeing' => '2',
                                                   'title' => '-',
                                                   'timeest' => 1,
                                                   'projectid' => 'M01BTJ',
                                                   'remaining' => '1',
                                                   'tauband' => '2',
                                                   'obscount' => 1,
                                                   'obs' => [
                                                              {
                                                                'wavelength' => 'unknown',
                                                                'target' => 'test',
                                                                'coordstype' => 'RADEC',
                                                                'obstype' => [
                                                                               'Dark',
                                                                               'Observe'
                                                                             ],
                                                                'coords' => bless( {
                                                                                     'dec2000' => '0',
                                                                                     'ra2000' => '0'
                                                                                   }, 'Astro::Coords::Equatorial' ),
                                                                'instrument' => 'IRCAM3'
                                                              }
                                                            ],
                                                   'priority' => 3
                                                 },
          'dfe282baeba181e3a6e5433711fd7286' => {
                                                  'seeing' => '1',
                                                  'title' => 'Array Tests',
                                                  'timeest' => 1,
                                                  'projectid' => 'M01BTJ',
                                                  'remaining' => '1',
                                                  'tauband' => '1',
                                                  'obscount' => 3,
                                                  'obs' => [
                                                             {
                                                               'wavelength' => '2.1',
                                                               'target' => 'CGS4:Bias:Dark',
                                                               'coordstype' => 'CAL',
                                                               'obstype' => [
                                                                              'Bias',
                                                                              'CGS4',
                                                                              'Dark',
                                                                              'CGS4',
                                                                              'Dark',
                                                                              'Dark',
                                                                              'CGS4',
                                                                              'Dark'
                                                                            ],
                                                               'coords' => bless( {}, 'Astro::Coords::Calibration' ),
                                                               'instrument' => 'CGS4'
                                                             },
                                                             {
                                                               'wavelength' => 'unknown',
                                                               'target' => 'Dark',
                                                               'coordstype' => 'CAL',
                                                               'obstype' => [
                                                                              'Dark',
                                                                              'Dark'
                                                                            ],
                                                               'filter' => 'Blank',
                                                               'coords' => bless( {}, 'Astro::Coords::Calibration' ),
                                                               'instrument' => 'UFTI'
                                                             },
                                                             {
                                                               'wavelength' => 'unknown',
                                                               'target' => 'Dark',
                                                               'coordstype' => 'CAL',
                                                               'obstype' => [
                                                                              'Dark',
                                                                              'Dark'
                                                                            ],
                                                               'filter' => 'Blank',
                                                               'coords' => bless( {}, 'Astro::Coords::Calibration' ),
                                                               'instrument' => 'UFTI'
                                                             }
                                                           ],
                                                  'priority' => 3
                                                },
          'c0add034d39c866fe01f92203d8a470d' => {
                                                  'seeing' => '1',
                                                  'title' => 'Copy',
                                                  'timeest' => 1,
                                                  'projectid' => 'M01BTJ',
                                                  'remaining' => '2',
                                                  'tauband' => '1',
                                                  'obscount' => 1,
                                                  'obs' => [
                                                             {
                                                               'wavelength' => '10.5',
                                                               'target' => 'NONE SUPPLIED',
                                                               'coordstype' => 'RADEC',
                                                               'obstype' => [
                                                                              'Observe'
                                                                            ],
                                                               'instrument' => 'Michelle',
                                                               'coords' => bless( {
                                                                                    'dec2000' => '0',
                                                                                    'ra2000' => '0'
                                                                                  }, 'Astro::Coords::Equatorial' )
                                                             }
                                                           ],
                                                  'priority' => 3
                                                },
          '09a49ff69bc1facf1741f40690eb9fddOA' => {
                                                    'seeing' => '1',
                                                    'title' => 'BS5_0h6m_58d_G5V',
                                                    'timeest' => 1,
                                                    'projectid' => 'M01BTJ',
                                                    'remaining' => '1',
                                                    'tauband' => '1',
                                                    'obscount' => 1,
                                                    'obs' => [
                                                               {
                                                                 'wavelength' => '2.2',
                                                                 'target' => 'BS5',
                                                                 'coordstype' => 'RADEC',
                                                                 'obstype' => [
                                                                                'Observe'
                                                                              ],
                                                                 'coords' => bless( {
                                                                                      'dec2000' => '1.01991223722375',
                                                                                      'ra2000' => '0.0273362194093612'
                                                                                    }, 'Astro::Coords::Equatorial' ),
                                                                 'instrument' => 'CGS4'
                                                               }
                                                             ],
                                                    'priority' => 3
                                                  },
          '86fcce791167f6001afbba2c4758a67bOA' => {
                                                    'seeing' => '1',
                                                    'title' => 'BS1532_4h47m_-16d_G1V',
                                                    'timeest' => 1,
                                                    'projectid' => 'M01BTJ',
                                                    'remaining' => '1',
                                                    'tauband' => '1',
                                                    'obscount' => 1,
                                                    'obs' => [
                                                               {
                                                                 'wavelength' => '2.2',
                                                                 'target' => 'BS1532',
                                                                 'coordstype' => 'RADEC',
                                                                 'obstype' => [
                                                                                'Observe'
                                                                              ],
                                                                 'coords' => bless( {
                                                                                      'dec2000' => '-0.295561812551618',
                                                                                      'ra2000' => '1.25490627659436'
                                                                                    }, 'Astro::Coords::Equatorial' ),
                                                                 'instrument' => 'CGS4'
                                                               }
                                                             ],
                                                    'priority' => 3
                                                  },
          'daaf4147b757592f3ebc07b40b48565dO' => {
                                                   'seeing' => '1',
                                                   'title' => 'FS1_00h33m_-12d I-band',
                                                   'timeest' => 1,
                                                   'projectid' => 'M01BTJ',
                                                   'remaining' => '1',
                                                   'tauband' => '1',
                                                   'obscount' => 1,
                                                   'obs' => [
                                                              {
                                                                'wavelength' => 'unknown',
                                                                'target' => 'FS1',
                                                                'coordstype' => 'RADEC',
                                                                'obstype' => [
                                                                               'Dark',
                                                                               'Observe'
                                                                             ],
                                                                'filter' => 'I',
                                                                'instrument' => 'UFTI',
                                                                'coords' => bless( {
                                                                                     'dec2000' => '-0.211752071498212',
                                                                                     'ra2000' => '0.147946251981751'
                                                                                   }, 'Astro::Coords::Equatorial' )
                                                              }
                                                            ],
                                                   'priority' => 3
                                                 },
          '210b74070afcc4b6f5e704edcebb033bO' => {
                                                   'seeing' => '1',
                                                   'title' => 'FS101_00h13m_30d J-band',
                                                   'timeest' => 1,
                                                   'projectid' => 'M01BTJ',
                                                   'remaining' => '2',
                                                   'tauband' => '1',
                                                   'obscount' => 1,
                                                   'obs' => [
                                                              {
                                                                'wavelength' => 'unknown',
                                                                'target' => 'FS101',
                                                                'coordstype' => 'RADEC',
                                                                'obstype' => [
                                                                               'Dark',
                                                                               'Observe'
                                                                             ],
                                                                'filter' => 'J98',
                                                                'coords' => bless( {
                                                                                     'dec2000' => '0.534652042713915',
                                                                                     'ra2000' => '0.0598924277232287'
                                                                                   }, 'Astro::Coords::Equatorial' ),
                                                                'instrument' => 'UFTI'
                                                              }
                                                            ],
                                                   'priority' => 3
                                                 },
          '0ff472509ce854839965add501651718O' => {
                                                   'seeing' => '1',
                                                   'title' => 'Copy',
                                                   'timeest' => 1,
                                                   'projectid' => 'M01BTJ',
                                                   'remaining' => '1',
                                                   'tauband' => '1',
                                                   'obscount' => 1,
                                                   'obs' => [
                                                              {
                                                                'wavelength' => '10.5',
                                                                'target' => 'NONE SUPPLIED',
                                                                'coordstype' => 'RADEC',
                                                                'obstype' => [
                                                                               'Observe'
                                                                             ],
                                                                'instrument' => 'Michelle',
                                                                'coords' => bless( {
                                                                                     'dec2000' => '0',
                                                                                     'ra2000' => '0'
                                                                                   }, 'Astro::Coords::Equatorial' )
                                                              }
                                                            ],
                                                   'priority' => 3
                                                 }
        };
