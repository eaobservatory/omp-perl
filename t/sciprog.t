#!perl

# Test the OMP::SciProg class
# and the related MSB classes. Does not interact with the database.

use warnings;
use strict;
use Test;
use Data::Dumper;


BEGIN { plan tests => 258 }

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

	    print "# Comparing: $obskey\n";
	    ok($obs{$obskey}, $cmpobs{$obskey});
	  }
	}

      } else {

	next if ref( $cmp{$key});
	print "# Comparing $key\n";
	ok( $msbsum{$key}, $cmp{$key});
	
      }

    }

  } else {
    ok(0);
    # skip the next few tests
    skip("Pointless testing MSB when checksum does not match [".
	 $msb->checksum. "]",1);
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
    delete $msbsum{latest};
    delete $msbsum{earliest};

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
          '6b0eb4a83e72f6352cb537117f31caddOA' => {
                                                    'telescope' => 'UKIRT',
                                                    'cloud' => 101,
                                                    'remaining' => '1',
                                                    'obscount' => 1,
                                                    'obs' => [
                                                               {
                                                                 'telescope' => 'UKIRT',
                                                                 'waveband' => bless( {
                                                                                        'Instrument' => 'CGS4',
                                                                                        'Cache' => {
                                                                                                     'wavelength' => '2.2'
                                                                                                   }
                                                                                      }, 'Astro::WaveBand' ),
                                                                 'wavelength' => '2.2',
                                                                 'target' => 'BS5',
                                                                 'obstype' => [
                                                                                'Observe'
                                                                              ],
                                                                 'coordstype' => 'RADEC',
                                                                 'pol' => 0,
                                                                 'disperser' => '40lpmm',
                                                                 'coords' => bless( {
                                                                                      'dec2000' => '1.01991223722375',
                                                                                      'ra2000' => '0.0273362194093612'
                                                                                    }, 'Astro::Coords::Equatorial' ),
                                                                 'type' => 's',
                                                                 'instrument' => 'CGS4',
                                                                 'timeest' => '64.0'
                                                               }
                                                             ],
                                                    'seeing' => bless( {
                                                                         'Min' => '0.0',
                                                                         'Max' => '0.4'
                                                                       }, 'OMP::Range' ),
                                                    'title' => 'BS5_0h6m_58d_G5V',
                                                    'timeest' => '64.0',
                                                    'moon' => 101,
                                                    'projectid' => 'M01BTJ',
                                                    'tau' => bless( {
                                                                      'Min' => '0',
                                                                      'Max' => '0.09'
                                                                    }, 'OMP::Range' ),
                                                    'priority' => 3
                                                  },
          '74e50dbd18d725b161a74ce2b67b43d3' => {
                                                  'telescope' => 'UKIRT',
                                                  'cloud' => 101,
                                                  'remaining' => '2',
                                                  'obscount' => 2,
                                                  'obs' => [
                                                             {
                                                               'telescope' => 'UKIRT',
                                                               'waveband' => bless( {
                                                                                      'Instrument' => 'UFTI',
                                                                                      'Cache' => {
                                                                                                   'wavelength' => '1.033',
                                                                                                   'filter' => 'Z'
                                                                                                 }
                                                                                    }, 'Astro::WaveBand' ),
                                                               'wavelength' => '1.033',
                                                               'target' => 'FS1',
                                                               'obstype' => [
                                                                              'Dark',
                                                                              'Observe'
                                                                            ],
                                                               'coordstype' => 'RADEC',
                                                               'pol' => 0,
                                                               'disperser' => undef,
                                                               'coords' => bless( {
                                                                                    'dec2000' => '-0.211752071498212',
                                                                                    'ra2000' => '0.147946251981751'
                                                                                  }, 'Astro::Coords::Equatorial' ),
                                                               'type' => 'i',
                                                               'instrument' => 'UFTI',
                                                               'timeest' => '120.0'
                                                             },
                                                             {
                                                               'telescope' => 'UKIRT',
                                                               'waveband' => bless( {
                                                                                      'Instrument' => 'UFTI',
                                                                                      'Cache' => {
                                                                                                   'wavelength' => '0.9',
                                                                                                   'filter' => 'I'
                                                                                                 }
                                                                                    }, 'Astro::WaveBand' ),
                                                               'wavelength' => '0.9',
                                                               'target' => 'FS2',
                                                               'obstype' => [
                                                                              'Dark',
                                                                              'Observe'
                                                                            ],
                                                               'coordstype' => 'RADEC',
                                                               'pol' => 0,
                                                               'disperser' => undef,
                                                               'coords' => bless( {
                                                                                    'dec2000' => '0.0125717035648514',
                                                                                    'ra2000' => '0.240704902127233'
                                                                                  }, 'Astro::Coords::Equatorial' ),
                                                               'type' => 'i',
                                                               'instrument' => 'UFTI',
                                                               'timeest' => '60.0'
                                                             }
                                                           ],
                                                  'seeing' => bless( {
                                                                       'Min' => '0.0',
                                                                       'Max' => '0.4'
                                                                     }, 'OMP::Range' ),
                                                  'title' => 'UFTI standards',
                                                  'timeest' => '180.0',
                                                  'moon' => 101,
                                                  'projectid' => 'M01BTJ',
                                                  'tau' => bless( {
                                                                    'Min' => '0',
                                                                    'Max' => '0.09'
                                                                  }, 'OMP::Range' ),
                                                  'priority' => 3
                                                },
          'be8787c919d014cbe5a627c02e4e0221O' => {
                                                   'telescope' => 'UKIRT',
                                                   'cloud' => 101,
                                                   'remaining' => '1',
                                                   'obscount' => 1,
                                                   'obs' => [
                                                              {
                                                                'telescope' => 'UKIRT',
                                                                'waveband' => bless( {
                                                                                       'Instrument' => 'UFTI',
                                                                                       'Cache' => {
                                                                                                    'wavelength' => '0.9',
                                                                                                    'filter' => 'I'
                                                                                                  }
                                                                                     }, 'Astro::WaveBand' ),
                                                                'wavelength' => '0.9',
                                                                'target' => 'FS1',
                                                                'obstype' => [
                                                                               'Dark',
                                                                               'Observe'
                                                                             ],
                                                                'coordstype' => 'RADEC',
                                                                'pol' => 0,
                                                                'disperser' => undef,
                                                                'coords' => bless( {
                                                                                     'dec2000' => '-0.211752071498212',
                                                                                     'ra2000' => '0.147946251981751'
                                                                                   }, 'Astro::Coords::Equatorial' ),
                                                                'type' => 'i',
                                                                'instrument' => 'UFTI',
                                                                'timeest' => '240.0'
                                                              }
                                                            ],
                                                   'seeing' => bless( {
                                                                        'Min' => '0.0',
                                                                        'Max' => '0.4'
                                                                      }, 'OMP::Range' ),
                                                   'title' => 'FS1_00h33m_-12d I-band',
                                                   'timeest' => '240.0',
                                                   'moon' => 101,
                                                   'projectid' => 'M01BTJ',
                                                   'tau' => bless( {
                                                                     'Min' => '0',
                                                                     'Max' => '0.09'
                                                                   }, 'OMP::Range' ),
                                                   'priority' => 3
                                                 },
          'f75a6dc58da9273913d3266a1c3f3463A' => {
                                                   'telescope' => 'UKIRT',
                                                   'cloud' => 101,
                                                   'remaining' => '1',
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
                                                                'coordstype' => 'RADEC',
                                                                'pol' => 0,
                                                                'disperser' => undef,
                                                                'instrument' => 'IRCAM3',
                                                                'timeest' => '0.24',
                                                                'telescope' => 'UKIRT',
                                                                'target' => 'test',
                                                                'obstype' => [
                                                                               'Dark',
                                                                               'Observe'
                                                                             ],
                                                                'coords' => bless( {
                                                                                     'dec2000' => '0',
                                                                                     'ra2000' => '0'
                                                                                   }, 'Astro::Coords::Equatorial' ),
                                                                'type' => 'i'
                                                              }
                                                            ],
                                                   'seeing' => bless( {
                                                                        'Min' => '0.0',
                                                                        'Max' => '0.8'
                                                                      }, 'OMP::Range' ),
                                                   'title' => '-',
                                                   'timeest' => '0.24',
                                                   'moon' => 101,
                                                   'projectid' => 'M01BTJ',
                                                   'tau' => bless( {
                                                                     'Min' => 0,
                                                                     'Max' => undef
                                                                   }, 'OMP::Range' ),
                                                   'priority' => 3
                                                 },
          'e1653c1eab69f45393d91fc477e38cb8' => {
                                                  'telescope' => 'UKIRT',
                                                  'cloud' => 101,
                                                  'remaining' => '1',
                                                  'obscount' => 1,
                                                  'obs' => [
                                                             {
                                                               'telescope' => 'UKIRT',
                                                               'waveband' => bless( {
                                                                                      'Instrument' => 'MICHELLE',
                                                                                      'Cache' => {
                                                                                                   'wavelength' => '10.5',
                                                                                                   'filter' => 'F105B53'
                                                                                                 }
                                                                                    }, 'Astro::WaveBand' ),
                                                               'wavelength' => '10.5',
                                                               'target' => 'NONE SUPPLIED',
                                                               'obstype' => [
                                                                              'Observe'
                                                                            ],
                                                               'pol' => 0,
                                                               'coordstype' => 'RADEC',
                                                               'disperser' => undef,
                                                               'type' => 'i',
                                                               'coords' => bless( {
                                                                                    'dec2000' => '0',
                                                                                    'ra2000' => '0'
                                                                                  }, 'Astro::Coords::Equatorial' ),
                                                               'instrument' => 'Michelle',
                                                               'timeest' => '40.501227375'
                                                             }
                                                           ],
                                                  'seeing' => bless( {
                                                                       'Min' => '0.0',
                                                                       'Max' => '0.4'
                                                                     }, 'OMP::Range' ),
                                                  'title' => 'Copy',
                                                  'timeest' => '40.501227375',
                                                  'moon' => 101,
                                                  'projectid' => 'M01BTJ',
                                                  'tau' => bless( {
                                                                    'Min' => '0',
                                                                    'Max' => '0.09'
                                                                  }, 'OMP::Range' ),
                                                  'priority' => 3
                                                },
          '5a2bb69d112adbbb22e993dd336875ee' => {
                                                  'telescope' => 'UKIRT',
                                                  'cloud' => 101,
                                                  'remaining' => '1',
                                                  'obscount' => 3,
                                                  'obs' => [
                                                             {
                                                               'telescope' => 'UKIRT',
                                                               'waveband' => bless( {
                                                                                      'Instrument' => 'CGS4',
                                                                                      'Cache' => {
                                                                                                   'wavelength' => '2.1'
                                                                                                 }
                                                                                    }, 'Astro::WaveBand' ),
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
                                                               'pol' => 0,
                                                               'disperser' => '40lpmm',
                                                               'coords' => bless( {
                                                                                    'Az' => '0',
                                                                                    'El' => '1.5707963267949'
                                                                                  }, 'Astro::Coords::Calibration' ),
                                                               'type' => 's',
                                                               'instrument' => 'CGS4',
                                                               'timeest' => '28.0'
                                                             },
                                                             {
                                                               'telescope' => 'UKIRT',
                                                               'waveband' => bless( {
                                                                                      'Instrument' => 'UFTI',
                                                                                      'Cache' => {
                                                                                                   'filter' => 'Blank'
                                                                                                 }
                                                                                    }, 'Astro::WaveBand' ),
                                                               'wavelength' => undef,
                                                               'target' => 'Dark',
                                                               'coordstype' => 'CAL',
                                                               'obstype' => [
                                                                              'Dark',
                                                                              'Dark'
                                                                            ],
                                                               'pol' => 0,
                                                               'disperser' => undef,
                                                               'coords' => bless( {
                                                                                    'Az' => '0',
                                                                                    'El' => '1.5707963267949'
                                                                                  }, 'Astro::Coords::Calibration' ),
                                                               'type' => 'i',
                                                               'instrument' => 'UFTI',
                                                               'timeest' => '16.0'
                                                             },
                                                             {
                                                               'telescope' => 'UKIRT',
                                                               'waveband' => bless( {
                                                                                      'Instrument' => 'UFTI',
                                                                                      'Cache' => {
                                                                                                   'filter' => 'Blank'
                                                                                                 }
                                                                                    }, 'Astro::WaveBand' ),
                                                               'wavelength' => undef,
                                                               'target' => 'Dark',
                                                               'coordstype' => 'CAL',
                                                               'obstype' => [
                                                                              'Dark',
                                                                              'Dark'
                                                                            ],
                                                               'pol' => 0,
                                                               'disperser' => undef,
                                                               'coords' => bless( {
                                                                                    'Az' => '0',
                                                                                    'El' => '1.5707963267949'
                                                                                  }, 'Astro::Coords::Calibration' ),
                                                               'type' => 'i',
                                                               'instrument' => 'UFTI',
                                                               'timeest' => '16.0'
                                                             }
                                                           ],
                                                  'seeing' => bless( {
                                                                       'Min' => '0.0',
                                                                       'Max' => '0.4'
                                                                     }, 'OMP::Range' ),
                                                  'title' => 'Array Tests',
                                                  'timeest' => '60.0',
                                                  'moon' => 101,
                                                  'projectid' => 'M01BTJ',
                                                  'tau' => bless( {
                                                                    'Min' => '0',
                                                                    'Max' => '0.09'
                                                                  }, 'OMP::Range' ),
                                                  'priority' => 3
                                                },
          '915ae2dea519789174eea4b168bb70d1OA' => {
                                                    'telescope' => 'UKIRT',
                                                    'cloud' => 101,
                                                    'remaining' => '1',
                                                    'obscount' => 1,
                                                    'obs' => [
                                                               {
                                                                 'telescope' => 'UKIRT',
                                                                 'waveband' => bless( {
                                                                                        'Instrument' => 'CGS4',
                                                                                        'Cache' => {
                                                                                                     'wavelength' => '2.2'
                                                                                                   }
                                                                                      }, 'Astro::WaveBand' ),
                                                                 'wavelength' => '2.2',
                                                                 'target' => 'BS1532',
                                                                 'obstype' => [
                                                                                'Observe'
                                                                              ],
                                                                 'coordstype' => 'RADEC',
                                                                 'pol' => 0,
                                                                 'disperser' => '40lpmm',
                                                                 'coords' => bless( {
                                                                                      'dec2000' => '-0.295561812551618',
                                                                                      'ra2000' => '1.25490627659436'
                                                                                    }, 'Astro::Coords::Equatorial' ),
                                                                 'type' => 's',
                                                                 'instrument' => 'CGS4',
                                                                 'timeest' => '64.0'
                                                               }
                                                             ],
                                                    'seeing' => bless( {
                                                                         'Min' => '0.0',
                                                                         'Max' => '0.4'
                                                                       }, 'OMP::Range' ),
                                                    'title' => 'BS1532_4h47m_-16d_G1V',
                                                    'timeest' => '64.0',
                                                    'moon' => 101,
                                                    'projectid' => 'M01BTJ',
                                                    'tau' => bless( {
                                                                      'Min' => '0',
                                                                      'Max' => '0.09'
                                                                    }, 'OMP::Range' ),
                                                    'priority' => 3
                                                  },
          '0c79b58d5737c202a192be9d14c65c4a' => {
                                                  'telescope' => 'UKIRT',
                                                  'cloud' => 101,
                                                  'remaining' => '1',
                                                  'obscount' => 1,
                                                  'obs' => [
                                                             {
                                                               'telescope' => 'UKIRT',
                                                               'waveband' => bless( {
                                                                                      'Instrument' => 'MICHELLE',
                                                                                      'Cache' => {
                                                                                                   'wavelength' => '10.5',
                                                                                                   'filter' => 'F105B53'
                                                                                                 }
                                                                                    }, 'Astro::WaveBand' ),
                                                               'wavelength' => '10.5',
                                                               'target' => 'NONE SUPPLIED',
                                                               'obstype' => [
                                                                              'Observe'
                                                                            ],
                                                               'pol' => 0,
                                                               'coordstype' => 'RADEC',
                                                               'disperser' => undef,
                                                               'type' => 'i',
                                                               'coords' => bless( {
                                                                                    'dec2000' => '0',
                                                                                    'ra2000' => '0'
                                                                                  }, 'Astro::Coords::Equatorial' ),
                                                               'instrument' => 'Michelle',
                                                               'timeest' => '40.501227375'
                                                             }
                                                           ],
                                                  'seeing' => bless( {
                                                                       'Min' => '0.0',
                                                                       'Max' => '0.4'
                                                                     }, 'OMP::Range' ),
                                                  'title' => 'Copy',
                                                  'timeest' => '40.501227375',
                                                  'moon' => 101,
                                                  'projectid' => 'M01BTJ',
                                                  'tau' => bless( {
                                                                    'Min' => '0',
                                                                    'Max' => '0.09'
                                                                  }, 'OMP::Range' ),
                                                  'priority' => 3
                                                },
          '2276a3831343c3be4633c19f639a3d8aO' => {
                                                   'telescope' => 'UKIRT',
                                                   'cloud' => 101,
                                                   'remaining' => '2',
                                                   'obscount' => 1,
                                                   'obs' => [
                                                              {
                                                                'telescope' => 'UKIRT',
                                                                'waveband' => bless( {
                                                                                       'Instrument' => 'UFTI',
                                                                                       'Cache' => {
                                                                                                    'wavelength' => '1.250',
                                                                                                    'filter' => 'J98'
                                                                                                  }
                                                                                     }, 'Astro::WaveBand' ),
                                                                'wavelength' => '1.250',
                                                                'target' => 'FS101',
                                                                'obstype' => [
                                                                               'Dark',
                                                                               'Observe'
                                                                             ],
                                                                'coordstype' => 'RADEC',
                                                                'pol' => 0,
                                                                'disperser' => undef,
                                                                'coords' => bless( {
                                                                                     'dec2000' => '0.534652042713915',
                                                                                     'ra2000' => '0.0598924277232287'
                                                                                   }, 'Astro::Coords::Equatorial' ),
                                                                'type' => 'i',
                                                                'instrument' => 'UFTI',
                                                                'timeest' => '30.0'
                                                              }
                                                            ],
                                                   'seeing' => bless( {
                                                                        'Min' => '0.0',
                                                                        'Max' => '0.4'
                                                                      }, 'OMP::Range' ),
                                                   'title' => 'FS101_00h13m_30d J-band',
                                                   'timeest' => '30.0',
                                                   'moon' => 101,
                                                   'projectid' => 'M01BTJ',
                                                   'tau' => bless( {
                                                                     'Min' => '0',
                                                                     'Max' => '0.09'
                                                                   }, 'OMP::Range' ),
                                                   'priority' => 3
                                                 },
          '3d5cdf6be6996d4d11c18eec2dfca7a3A' => {
                                                   'telescope' => 'UKIRT',
                                                   'cloud' => 101,
                                                   'remaining' => '6',
                                                   'obscount' => 3,
                                                   'obs' => [
                                                              {
                                                                'telescope' => 'UKIRT',
                                                                'waveband' => bless( {
                                                                                       'Instrument' => 'MICHELLE',
                                                                                       'Cache' => {
                                                                                                    'wavelength' => '10.0'
                                                                                                  }
                                                                                     }, 'Astro::WaveBand' ),
                                                                'wavelength' => '10.0',
                                                                'target' => 'eek',
                                                                'obstype' => [
                                                                               'Observe'
                                                                             ],
                                                                'coordstype' => 'RADEC',
                                                                'pol' => 1,
                                                                'disperser' => 'LowN',
                                                                'coords' => bless( {
                                                                                     'dec2000' => '0',
                                                                                     'ra2000' => '0'
                                                                                   }, 'Astro::Coords::Equatorial' ),
                                                                'type' => 's',
                                                                'instrument' => 'Michelle',
                                                                'timeest' => '41.250668292'
                                                              },
                                                              {
                                                                'telescope' => 'UKIRT',
                                                                'waveband' => bless( {
                                                                                       'Instrument' => 'CGS4',
                                                                                       'Cache' => {
                                                                                                    'wavelength' => '1.0'
                                                                                                  }
                                                                                     }, 'Astro::WaveBand' ),
                                                                'wavelength' => '1.0',
                                                                'target' => 'mars',
                                                                'obstype' => [
                                                                               'Observe'
                                                                             ],
                                                                'coordstype' => 'RADEC',
                                                                'pol' => 1,
                                                                'disperser' => '40lpmm',
                                                                'coords' => bless( {
                                                                                     'dec2000' => '0',
                                                                                     'ra2000' => '0'
                                                                                   }, 'Astro::Coords::Equatorial' ),
                                                                'type' => 's',
                                                                'instrument' => 'CGS4',
                                                                'timeest' => '8.0'
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
                                                                'pol' => 1,
                                                                'disperser' => undef,
                                                                'instrument' => 'IRCAM3',
                                                                'timeest' => '0.24',
                                                                'telescope' => 'UKIRT',
                                                                'target' => 'mars',
                                                                'obstype' => [
                                                                               'Observe'
                                                                             ],
                                                                'coords' => $VAR1->{'3d5cdf6be6996d4d11c18eec2dfca7a3A'}{'obs'}[1]{'coords'},
                                                                'type' => 'i'
                                                              }
                                                            ],
                                                   'seeing' => bless( {
                                                                        'Min' => '0.0',
                                                                        'Max' => '0.4'
                                                                      }, 'OMP::Range' ),
                                                   'title' => 'Pol test',
                                                   'timeest' => '49.490668292',
                                                   'moon' => 101,
                                                   'projectid' => 'M01BTJ',
                                                   'tau' => bless( {
                                                                     'Min' => '0',
                                                                     'Max' => '0.09'
                                                                   }, 'OMP::Range' ),
                                                   'priority' => 2
                                                 },
          '3f5f2558b688054f8ed9574f71e290f0O' => {
                                                   'telescope' => 'UKIRT',
                                                   'cloud' => 101,
                                                   'remaining' => '1',
                                                   'obscount' => 1,
                                                   'obs' => [
                                                              {
                                                                'telescope' => 'UKIRT',
                                                                'waveband' => bless( {
                                                                                       'Instrument' => 'MICHELLE',
                                                                                       'Cache' => {
                                                                                                    'wavelength' => '10.5',
                                                                                                    'filter' => 'F105B53'
                                                                                                  }
                                                                                     }, 'Astro::WaveBand' ),
                                                                'wavelength' => '10.5',
                                                                'target' => 'NONE SUPPLIED',
                                                                'obstype' => [
                                                                               'Observe'
                                                                             ],
                                                                'pol' => 0,
                                                                'coordstype' => 'RADEC',
                                                                'disperser' => undef,
                                                                'type' => 'i',
                                                                'coords' => bless( {
                                                                                     'dec2000' => '0',
                                                                                     'ra2000' => '0'
                                                                                   }, 'Astro::Coords::Equatorial' ),
                                                                'instrument' => 'Michelle',
                                                                'timeest' => '40.501227375'
                                                              }
                                                            ],
                                                   'seeing' => bless( {
                                                                        'Min' => '0.0',
                                                                        'Max' => '0.4'
                                                                      }, 'OMP::Range' ),
                                                   'title' => 'Copy',
                                                   'timeest' => '40.501227375',
                                                   'moon' => 101,
                                                   'projectid' => 'M01BTJ',
                                                   'tau' => bless( {
                                                                     'Min' => '0',
                                                                     'Max' => '0.09'
                                                                   }, 'OMP::Range' ),
                                                   'priority' => 3
                                                 }
        };
