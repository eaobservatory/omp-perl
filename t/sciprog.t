#!perl

# Test the OMP::SciProg class
# and the related MSB classes. Does not interact with the database.

use warnings;
use strict;
use Test;
use Data::Dumper;


BEGIN { plan tests => 199 }

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
ok(scalar(@msbs), 11);

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
	    next if ref($obs{$obskey});

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
          'cdc423f56111e9be173eeda6cc28d49dA' => {
                                                   'seeing' => '1',
                                                   'title' => 'Pol test',
                                                   'timeest' => '49.490668292',
                                                   'projectid' => 'M01BTJ',
                                                   'remaining' => '6',
                                                   'tauband' => '1',
                                                   'obscount' => 3,
                                                   'obs' => [
                                                              {
                                                                'waveband' => bless( {
                                                                                       'Instrument' => 'MICHELLE',
                                                                                       'Cache' => {
                                                                                                    'wavelength' => '10.0'
                                                                                                  }
                                                                                     }, 'Astro::WaveBand' ),
                                                                'wavelength' => '10.0',
                                                                'coordstype' => 'RADEC',
                                                                'target' => 'eek',
                                                                'pol' => 1,
                                                                'obstype' => [
                                                                               'Observe'
                                                                             ],
                                                                'coords' => bless( {
                                                                                     'dec2000' => '0',
                                                                                     'ra2000' => '0'
                                                                                   }, 'Astro::Coords::Equatorial' ),
                                                                'instrument' => 'Michelle',
                                                                'type' => 's'
                                                              },
                                                              {
                                                                'waveband' => bless( {
                                                                                       'Instrument' => 'CGS4',
                                                                                       'Cache' => {
                                                                                                    'wavelength' => '1.0'
                                                                                                  }
                                                                                     }, 'Astro::WaveBand' ),
                                                                'wavelength' => '1.0',
                                                                'coordstype' => 'RADEC',
                                                                'target' => 'mars',
                                                                'pol' => 1,
                                                                'obstype' => [
                                                                               'Observe'
                                                                             ],
                                                                'coords' => bless( {
                                                                                     'dec2000' => '0',
                                                                                     'ra2000' => '0'
                                                                                   }, 'Astro::Coords::Equatorial' ),
                                                                'instrument' => 'CGS4',
                                                                'type' => 's'
                                                              },
                                                              {
                                                                'waveband' => bless( {
                                                                                       'Instrument' => 'IRCAM',
                                                                                       'Cache' => {
                                                                                                    'wavelength' => '3.6',
                                                                                                    'filter' => 'Lp98'
                                                                                                  }
                                                                                     }, 'Astro::WaveBand' ),
                                                                'wavelength' => '3.6',
                                                                'coordstype' => 'RADEC',
                                                                'target' => 'mars',
                                                                'pol' => 1,
                                                                'obstype' => [
                                                                               'Observe'
                                                                             ],
                                                                'coords' => $VAR1->{'cdc423f56111e9be173eeda6cc28d49dA'}{'obs'}[1]{'coords'},
                                                                'instrument' => 'IRCAM3',
                                                                'type' => 'i'
                                                              }
                                                            ],
                                                   'priority' => 2
                                                 },
          '4cbbd5b208c2386866e59fa5225caa1f' => {
                                                  'seeing' => '1',
                                                  'title' => 'Copy',
                                                  'timeest' => '40.501227375',
                                                  'projectid' => 'M01BTJ',
                                                  'remaining' => '1',
                                                  'tauband' => '1',
                                                  'obscount' => 1,
                                                  'obs' => [
                                                             {
                                                               'waveband' => bless( {
                                                                                      'Instrument' => 'MICHELLE',
                                                                                      'Cache' => {
                                                                                                   'wavelength' => '10.5',
                                                                                                   'filter' => 'F105B53'
                                                                                                 }
                                                                                    }, 'Astro::WaveBand' ),
                                                               'wavelength' => '10.5',
                                                               'pol' => 0,
                                                               'target' => 'NONE SUPPLIED',
                                                               'coordstype' => 'RADEC',
                                                               'obstype' => [
                                                                              'Observe'
                                                                            ],
                                                               'instrument' => 'Michelle',
                                                               'type' => 'i',
                                                               'coords' => bless( {
                                                                                    'dec2000' => '0',
                                                                                    'ra2000' => '0'
                                                                                  }, 'Astro::Coords::Equatorial' )
                                                             }
                                                           ],
                                                  'priority' => 3
                                                },
          'ac9e9c8007fad7b8e1073de45e1d8222OA' => {
                                                    'seeing' => '1',
                                                    'title' => 'BS1532_4h47m_-16d_G1V',
                                                    'timeest' => '64.0',
                                                    'projectid' => 'M01BTJ',
                                                    'remaining' => '1',
                                                    'tauband' => '1',
                                                    'obscount' => 1,
                                                    'obs' => [
                                                               {
                                                                 'waveband' => bless( {
                                                                                        'Instrument' => 'CGS4',
                                                                                        'Cache' => {
                                                                                                     'wavelength' => '2.2'
                                                                                                   }
                                                                                      }, 'Astro::WaveBand' ),
                                                                 'wavelength' => '2.2',
                                                                 'target' => 'BS1532',
                                                                 'coordstype' => 'RADEC',
                                                                 'pol' => 0,
                                                                 'obstype' => [
                                                                                'Observe'
                                                                              ],
                                                                 'coords' => bless( {
                                                                                      'dec2000' => '-0.295561812551618',
                                                                                      'ra2000' => '1.25490627659436'
                                                                                    }, 'Astro::Coords::Equatorial' ),
                                                                 'instrument' => 'CGS4',
                                                                 'type' => 's'
                                                               }
                                                             ],
                                                    'priority' => 3
                                                  },
          '77013c6318b6cba06ec7499584f205fd' => {
                                                  'seeing' => '1',
                                                  'title' => 'Copy',
                                                  'timeest' => '40.501227375',
                                                  'projectid' => 'M01BTJ',
                                                  'remaining' => '1',
                                                  'tauband' => '1',
                                                  'obscount' => 1,
                                                  'obs' => [
                                                             {
                                                               'waveband' => bless( {
                                                                                      'Instrument' => 'MICHELLE',
                                                                                      'Cache' => {
                                                                                                   'wavelength' => '10.5',
                                                                                                   'filter' => 'F105B53'
                                                                                                 }
                                                                                    }, 'Astro::WaveBand' ),
                                                               'wavelength' => '10.5',
                                                               'pol' => 0,
                                                               'target' => 'NONE SUPPLIED',
                                                               'coordstype' => 'RADEC',
                                                               'obstype' => [
                                                                              'Observe'
                                                                            ],
                                                               'instrument' => 'Michelle',
                                                               'type' => 'i',
                                                               'coords' => bless( {
                                                                                    'dec2000' => '0',
                                                                                    'ra2000' => '0'
                                                                                  }, 'Astro::Coords::Equatorial' )
                                                             }
                                                           ],
                                                  'priority' => 3
                                                },
          '1d040d928406c17f39f0948136253752A' => {
                                                   'seeing' => '2',
                                                   'title' => '-',
                                                   'timeest' => '0.24',
                                                   'projectid' => 'M01BTJ',
                                                   'remaining' => '1',
                                                   'tauband' => '2',
                                                   'obscount' => 1,
                                                   'obs' => [
                                                              {
                                                                'waveband' => bless( {
                                                                                       'Instrument' => 'IRCAM',
                                                                                       'Cache' => {
                                                                                                    'wavelength' => '3.6',
                                                                                                    'filter' => 'Lp98'
                                                                                                  }
                                                                                     }, 'Astro::WaveBand' ),
                                                                'wavelength' => '3.6',
                                                                'target' => 'test',
                                                                'coordstype' => 'RADEC',
                                                                'pol' => 0,
                                                                'obstype' => [
                                                                               'Dark',
                                                                               'Observe'
                                                                             ],
                                                                'coords' => bless( {
                                                                                     'dec2000' => '0',
                                                                                     'ra2000' => '0'
                                                                                   }, 'Astro::Coords::Equatorial' ),
                                                                'instrument' => 'IRCAM3',
                                                                'type' => 'i'
                                                              }
                                                            ],
                                                   'priority' => 3
                                                 },
          'fff3cfddba9dbed301418bbe75b814a6' => {
                                                  'seeing' => '1',
                                                  'title' => 'UFTI standards',
                                                  'timeest' => '180.0',
                                                  'projectid' => 'M01BTJ',
                                                  'remaining' => '2',
                                                  'tauband' => '1',
                                                  'obscount' => 2,
                                                  'obs' => [
                                                             {
                                                               'waveband' => bless( {
                                                                                      'Instrument' => 'UFTI',
                                                                                      'Cache' => {
                                                                                                   'wavelength' => '1.033',
                                                                                                   'filter' => 'Z'
                                                                                                 }
                                                                                    }, 'Astro::WaveBand' ),
                                                               'wavelength' => '1.033',
                                                               'target' => 'FS1',
                                                               'coordstype' => 'RADEC',
                                                               'pol' => 0,
                                                               'obstype' => [
                                                                              'Dark',
                                                                              'Observe'
                                                                            ],
                                                               'coords' => bless( {
                                                                                    'dec2000' => '-0.211752071498212',
                                                                                    'ra2000' => '0.147946251981751'
                                                                                  }, 'Astro::Coords::Equatorial' ),
                                                               'instrument' => 'UFTI',
                                                               'type' => 'i'
                                                             },
                                                             {
                                                               'waveband' => bless( {
                                                                                      'Instrument' => 'UFTI',
                                                                                      'Cache' => {
                                                                                                   'wavelength' => '0.9',
                                                                                                   'filter' => 'I'
                                                                                                 }
                                                                                    }, 'Astro::WaveBand' ),
                                                               'wavelength' => '0.9',
                                                               'target' => 'FS2',
                                                               'coordstype' => 'RADEC',
                                                               'pol' => 0,
                                                               'obstype' => [
                                                                              'Dark',
                                                                              'Observe'
                                                                            ],
                                                               'coords' => bless( {
                                                                                    'dec2000' => '0.0125717035648514',
                                                                                    'ra2000' => '0.240704902127233'
                                                                                  }, 'Astro::Coords::Equatorial' ),
                                                               'instrument' => 'UFTI',
                                                               'type' => 'i'
                                                             }
                                                           ],
                                                  'priority' => 3
                                                },
          '27ead70fae09e119876dfa78e45b138bO' => {
                                                   'seeing' => '1',
                                                   'title' => 'FS1_00h33m_-12d I-band',
                                                   'timeest' => '240.0',
                                                   'projectid' => 'M01BTJ',
                                                   'remaining' => '1',
                                                   'tauband' => '1',
                                                   'obscount' => 1,
                                                   'obs' => [
                                                              {
                                                                'waveband' => bless( {
                                                                                       'Instrument' => 'UFTI',
                                                                                       'Cache' => {
                                                                                                    'wavelength' => '0.9',
                                                                                                    'filter' => 'I'
                                                                                                  }
                                                                                     }, 'Astro::WaveBand' ),
                                                                'wavelength' => '0.9',
                                                                'target' => 'FS1',
                                                                'coordstype' => 'RADEC',
                                                                'pol' => 0,
                                                                'obstype' => [
                                                                               'Dark',
                                                                               'Observe'
                                                                             ],
                                                                'coords' => bless( {
                                                                                     'dec2000' => '-0.211752071498212',
                                                                                     'ra2000' => '0.147946251981751'
                                                                                   }, 'Astro::Coords::Equatorial' ),
                                                                'instrument' => 'UFTI',
                                                                'type' => 'i'
                                                              }
                                                            ],
                                                   'priority' => 3
                                                 },
          'e459fe51b9ecdea7aae7f755716467cbOA' => {
                                                    'seeing' => '1',
                                                    'title' => 'BS5_0h6m_58d_G5V',
                                                    'timeest' => '64.0',
                                                    'projectid' => 'M01BTJ',
                                                    'remaining' => '1',
                                                    'tauband' => '1',
                                                    'obscount' => 1,
                                                    'obs' => [
                                                               {
                                                                 'waveband' => bless( {
                                                                                        'Instrument' => 'CGS4',
                                                                                        'Cache' => {
                                                                                                     'wavelength' => '2.2'
                                                                                                   }
                                                                                      }, 'Astro::WaveBand' ),
                                                                 'wavelength' => '2.2',
                                                                 'target' => 'BS5',
                                                                 'coordstype' => 'RADEC',
                                                                 'pol' => 0,
                                                                 'obstype' => [
                                                                                'Observe'
                                                                              ],
                                                                 'coords' => bless( {
                                                                                      'dec2000' => '1.01991223722375',
                                                                                      'ra2000' => '0.0273362194093612'
                                                                                    }, 'Astro::Coords::Equatorial' ),
                                                                 'instrument' => 'CGS4',
                                                                 'type' => 's'
                                                               }
                                                             ],
                                                    'priority' => 3
                                                  },
          '759a74449fdd8c8d22227c748d96ac97O' => {
                                                   'seeing' => '1',
                                                   'title' => 'FS101_00h13m_30d J-band',
                                                   'timeest' => '30.0',
                                                   'projectid' => 'M01BTJ',
                                                   'remaining' => '2',
                                                   'tauband' => '1',
                                                   'obscount' => 1,
                                                   'obs' => [
                                                              {
                                                                'waveband' => bless( {
                                                                                       'Instrument' => 'UFTI',
                                                                                       'Cache' => {
                                                                                                    'wavelength' => '1.250',
                                                                                                    'filter' => 'J98'
                                                                                                  }
                                                                                     }, 'Astro::WaveBand' ),
                                                                'wavelength' => '1.250',
                                                                'target' => 'FS101',
                                                                'coordstype' => 'RADEC',
                                                                'pol' => 0,
                                                                'obstype' => [
                                                                               'Dark',
                                                                               'Observe'
                                                                             ],
                                                                'coords' => bless( {
                                                                                     'dec2000' => '0.534652042713915',
                                                                                     'ra2000' => '0.0598924277232287'
                                                                                   }, 'Astro::Coords::Equatorial' ),
                                                                'instrument' => 'UFTI',
                                                                'type' => 'i'
                                                              }
                                                            ],
                                                   'priority' => 3
                                                 },
          '59dc992988a3e66e6f588eff9cfe2c44' => {
                                                  'seeing' => '1',
                                                  'title' => 'Array Tests',
                                                  'timeest' => '60.0',
                                                  'projectid' => 'M01BTJ',
                                                  'remaining' => '1',
                                                  'tauband' => '1',
                                                  'obscount' => 3,
                                                  'obs' => [
                                                             {
                                                               'waveband' => bless( {
                                                                                      'Instrument' => 'CGS4',
                                                                                      'Cache' => {
                                                                                                   'wavelength' => '2.1'
                                                                                                 }
                                                                                    }, 'Astro::WaveBand' ),
                                                               'wavelength' => '2.1',
                                                               'target' => 'CGS4:Bias:Dark',
                                                               'coordstype' => 'CAL',
                                                               'pol' => 0,
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
                                                               'instrument' => 'CGS4',
                                                               'type' => 's'
                                                             },
                                                             {
                                                               'waveband' => bless( {
                                                                                      'Instrument' => 'UFTI',
                                                                                      'Cache' => {
                                                                                                   'filter' => 'Blank'
                                                                                                 }
                                                                                    }, 'Astro::WaveBand' ),
                                                               'wavelength' => undef,
                                                               'target' => 'Dark',
                                                               'coordstype' => 'CAL',
                                                               'pol' => 0,
                                                               'obstype' => [
                                                                              'Dark',
                                                                              'Dark'
                                                                            ],
                                                               'coords' => bless( {}, 'Astro::Coords::Calibration' ),
                                                               'instrument' => 'UFTI',
                                                               'type' => 'i'
                                                             },
                                                             {
                                                               'waveband' => bless( {
                                                                                      'Instrument' => 'UFTI',
                                                                                      'Cache' => {
                                                                                                   'filter' => 'Blank'
                                                                                                 }
                                                                                    }, 'Astro::WaveBand' ),
                                                               'wavelength' => undef,
                                                               'target' => 'Dark',
                                                               'coordstype' => 'CAL',
                                                               'pol' => 0,
                                                               'obstype' => [
                                                                              'Dark',
                                                                              'Dark'
                                                                            ],
                                                               'coords' => bless( {}, 'Astro::Coords::Calibration' ),
                                                               'instrument' => 'UFTI',
                                                               'type' => 'i'
                                                             }
                                                           ],
                                                  'priority' => 3
                                                },
          '3da1576f522f33443dfe5d47f4b11fb2O' => {
                                                   'seeing' => '1',
                                                   'title' => 'Copy',
                                                   'timeest' => '40.501227375',
                                                   'projectid' => 'M01BTJ',
                                                   'remaining' => '1',
                                                   'tauband' => '1',
                                                   'obscount' => 1,
                                                   'obs' => [
                                                              {
                                                                'waveband' => bless( {
                                                                                       'Instrument' => 'MICHELLE',
                                                                                       'Cache' => {
                                                                                                    'wavelength' => '10.5',
                                                                                                    'filter' => 'F105B53'
                                                                                                  }
                                                                                     }, 'Astro::WaveBand' ),
                                                                'wavelength' => '10.5',
                                                                'pol' => 0,
                                                                'target' => 'NONE SUPPLIED',
                                                                'coordstype' => 'RADEC',
                                                                'obstype' => [
                                                                               'Observe'
                                                                             ],
                                                                'instrument' => 'Michelle',
                                                                'type' => 'i',
                                                                'coords' => bless( {
                                                                                     'dec2000' => '0',
                                                                                     'ra2000' => '0'
                                                                                   }, 'Astro::Coords::Equatorial' )
                                                              }
                                                            ],
                                                   'priority' => 3
                                                 }
        };
