#!perl

# Test the OMP::SciProg class
# and the related MSB classes. Does not interact with the database.

use warnings;
use strict;
use Test::More tests => 273;
use Data::Dumper;

require_ok( 'OMP::SciProg' );

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

ok($obj,"We got an object");
isa_ok( $obj, "OMP::SciProg");

# Check the project ID
is($obj->projectID, "TJ01","Verify projectid");

# Now count the number of MSBs
# Should be 11
my @msbs = $obj->msb;
is(scalar(@msbs), 11, "Count number of MSBs");

# check each msb
for (@msbs) {
  isa_ok($_, "OMP::MSB");
}

# Check that an MSB exists
ok( $obj->existsMSB( $msbs[10]->checksum),"verify MSB existence");
# or not
ok( ! $obj->existsMSB( "blahblah" ), "Check nonexistence");


# Go through the MSBs to see what we can find out about them
for my $msb ($obj->msb) {
  if (exists $results{$msb->checksum}) {
    ok(1, "MSB exists");

    my %cmp = %{ $results{ $msb->checksum} };
    my $info = $msb->info;
    my %msbsum = $info->summary('hashlong');
    $msbsum{obscount} = $info->obscount;

    for my $key (keys %cmp) {

      # Special case for the observations array
      # Really need a recursive comparator
      if ($key eq 'observations') {

	foreach my $i (0..$#{$cmp{$key}}) {
	  my %obs = %{$msbsum{$key}[$i]};
	  my %cmpobs = %{$cmp{$key}[$i]};

	  # If we have waveband, generate a wavelength
	  if (!exists $obs{wavelength}) {
	    $obs{wavelength} = $obs{waveband}->wavelength
	      if $obs{waveband};
	  }
	  if (!exists $cmpobs{wavelength}) {
	    $cmpobs{wavelength} = $cmpobs{waveband}->wavelength
	      if $cmpobs{waveband};
	  }

	  # Coords type
	  if (!exists $obs{coordstype}) {
	    $obs{coordstype} = $obs{coords}->type
	      if $obs{coords};
	  }
	  if (!exists $cmpobs{coordstype}) {
	    $cmpobs{coordstype} = $cmpobs{coords}->type
	      if $cmpobs{coords};
	  }

	  foreach my $obskey (keys %cmpobs) {
	    # Skipping refs prevents comparison of coordinates
	    next if ref($cmpobs{$obskey});
	    next if ref($obs{$obskey});

	    is($obs{$obskey}, $cmpobs{$obskey}, "Comparing obs: $obskey");
	  }
	}

      } else {

	next if ref( $cmp{$key});
	is( $msbsum{$key}, $cmp{$key}, "Comparing $key");
	
      }

    }

  } else {
    ok(0);
    # skip the next few tests
    skip("Pointless testing MSB when checksum does not match [".
	 $msb->checksum. "] [title=".$msb->msbtitle."]",1);
  }
}

# Generate a summary
my @summary = $obj->summary;

# make sure the number of summaries matches the number of msbs
# + header
is( scalar(@summary), 1+scalar(@msbs), "Count MSBs");

# For information print them all out
# Need to include the "#"
print map { "#$_\n" } @summary;

# Print out in a form that will let us simply cut and paste
# this information to the top of the page for comparison
exit;
if (1) {
  my %summary;
  for my $msb ($obj->msb) {
    my %msbsum = $msb->info->summary('hashlong');

    # Remove stuff we aren't interested in
    delete $msbsum{checksum};
    delete $msbsum{summary};
    delete $msbsum{_obssum};
    delete $msbsum{datemin};
    delete $msbsum{datemax};

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
#          'f75a6dc58da9273913d3266a1c3f3463A' => {
	   '455c01c9b8309d014dc81271c45fe75fA' => {
                                                   'telescope' => 'UKIRT',
                                                   'cloud' => 101,
                                                   'remaining' => '1',
                                                   'obscount' => 1,
                                                   'observations' => [
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
                                                   'projectid' => 'TJ01',
                                                   'moon' => 101,
                                                   'tau' => bless( {
                                                                     'Min' => 0,
                                                                     'Max' => undef
                                                                   }, 'OMP::Range' ),
                                                   'priority' => 99
                                                 },
#	 'b4822233821bd8f53ab1a3c95b327c28O' => {
         '9be325e8058efc658e3e04cda69fa4abO' => {                                                 'telescope' => 'UKIRT',
                                                   'telescope' => 'UKIRT',
                                                   'cloud' => 101,
                                                   'remaining' => '2',
                                                   'obscount' => 1,
                                                   'observations' => [
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
                                                   'projectid' => 'TJ01',
                                                   'moon' => 101,
                                                   'tau' => bless( {
                                                                     'Min' => 0,
                                                                     'Max' => undef
                                                                   }, 'OMP::Range' ),
                                                   'priority' => 99
                                                 },
#          'f723d9868568bb625755d3ff57ba1915' => {
           'c050ad5c7961d3ad21e654269e7b28a4' => {
                                                  'telescope' => 'UKIRT',
                                                  'cloud' => 101,
                                                  'remaining' => '1',
                                                  'obscount' => 3,
                                                  'observations' => [
                                                             {
                                                               'telescope' => 'UKIRT',
                                                               'waveband' => bless( {
                                                                                      'Instrument' => 'CGS4',
                                                                                      'Cache' => {
                                                                                                   'wavelength' => '2.1'
                                                                                                 }
                                                                                    }, 'Astro::WaveBand' ),
                                                               'wavelength' => '2.1',
                                                               'target' => 'Bias:CGS4:Dark',
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
                                                               'timeest' => '179.0'
                                                             },
                                                             {
                                                               'telescope' => 'UKIRT',
                                                               'waveband' => bless( {
                                                                                      'Instrument' => 'UFTI',
                                                                                      'Cache' => {
                                                                                                   'filter' => 'Blank'
                                                                                                 }
                                                                                    }, 'Astro::WaveBand' ),
                                                               'wavelength' => -2.222,
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
                                                               'timeest' => '75.0'
                                                             },
                                                             {
                                                               'telescope' => 'UKIRT',
                                                               'waveband' => bless( {
                                                                                      'Instrument' => 'UFTI',
                                                                                      'Cache' => {
                                                                                                   'filter' => 'Blank'
                                                                                                 }
                                                                                    }, 'Astro::WaveBand' ),
                                                               'wavelength' => -2.222,
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
                                                               'timeest' => '75.0'
                                                             }
                                                           ],
                                                  'seeing' => bless( {
                                                                       'Min' => '0.0',
                                                                       'Max' => '0.4'
                                                                     }, 'OMP::Range' ),
                                                  'title' => 'Array Tests',
                                                  'timeest' => '329.0',
                                                  'projectid' => 'TJ01',
                                                  'moon' => 101,
                                                  'tau' => bless( {
                                                                    'Min' => 0,
                                                                    'Max' => undef
                                                                  }, 'OMP::Range' ),
                                                  'priority' => 99
                                                },
#          '21bef2414c47c1d1b863cb036801a26d' => {
           'ed69d6514357775e2037d6dc0301434d' => {
                                                  'telescope' => 'UKIRT',
                                                  'cloud' => 101,
                                                  'remaining' => '1',
                                                  'obscount' => 1,
                                                  'observations' => [
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
                                                  'projectid' => 'TJ01',
                                                  'moon' => 101,
                                                  'tau' => bless( {
                                                                    'Min' => 0,
                                                                    'Max' => undef
                                                                  }, 'OMP::Range' ),
                                                  'priority' => 99
                                                },
#          'bc34d57d94224154a445598ad60e147eOA' => {
           '53dd1ebb190da0b306d65ecd79a8b434OA' => {
                                                    'telescope' => 'UKIRT',
                                                    'cloud' => 101,
                                                    'remaining' => '1',
                                                    'obscount' => 1,
                                                    'observations' => [
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
                                                    'projectid' => 'TJ01',
                                                    'moon' => 101,
                                                    'tau' => bless( {
                                                                      'Min' => 0,
                                                                      'Max' => undef
                                                                    }, 'OMP::Range' ),
                                                    'priority' => 99
                                                  },
#          '15a547e0edb2cb0c81f0af34c1242b06A' => {
           '50431bcfb6237208fe27008d5676b0f2A' => {
                                                   'telescope' => 'UKIRT',
                                                   'cloud' => 101,
                                                   'remaining' => '6',
                                                   'obscount' => 3,
                                                   'observations' => [
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
                                                                'timeest' => '123.752004876'
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
                                                                'coords' => $VAR1->{'15a547e0edb2cb0c81f0af34c1242b06A'}{'observations'}[1]{'coords'},
                                                                'type' => 'i'
                                                              }
                                                            ],
                                                   'seeing' => bless( {
                                                                        'Min' => '0.0',
                                                                        'Max' => '0.4'
                                                                      }, 'OMP::Range' ),
                                                   'title' => 'Pol test',
                                                   'timeest' => '131.992004876',
                                                   'projectid' => 'TJ01',
                                                   'moon' => 101,
                                                   'tau' => bless( {
                                                                     'Min' => 0,
                                                                     'Max' => undef
                                                                   }, 'OMP::Range' ),
                                                   'priority' => 50
                                                 },
#          '75487f16203ecf5c8af5377cbf5cfd3eO' => {
           '36bcaeaba76f6a44b7088e71b34856d5O' => {
                                                   'telescope' => 'UKIRT',
                                                   'cloud' => 101,
                                                   'remaining' => '1',
                                                   'obscount' => 1,
                                                   'observations' => [
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
                                                   'projectid' => 'TJ01',
                                                   'moon' => 101,
                                                   'tau' => bless( {
                                                                     'Min' => 0,
                                                                     'Max' => undef
                                                                   }, 'OMP::Range' ),
                                                   'priority' => 99
                                                 },
#          '35f15b8b7d395bb3ea0b955567ec454c' => {
          'f5e0350c606c4f082269b459d1736b50' => {
                                                  'telescope' => 'UKIRT',
                                                  'cloud' => 101,
                                                  'remaining' => '1',
                                                  'obscount' => 1,
                                                  'observations' => [
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
                                                  'projectid' => 'TJ01',
                                                  'moon' => 101,
                                                  'tau' => bless( {
                                                                    'Min' => 0,
                                                                    'Max' => undef
                                                                  }, 'OMP::Range' ),
                                                  'priority' => 99
                                                },
#          'f001ffe51a696895375246378d7e034cOA' => {
           '32c856c0ddbb532c748d134169ccb312OA' => {
                                                    'telescope' => 'UKIRT',
                                                    'cloud' => 101,
                                                    'remaining' => '1',
                                                    'obscount' => 1,
                                                    'observations' => [
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
                                                    'projectid' => 'TJ01',
                                                    'moon' => 101,
                                                    'tau' => bless( {
                                                                      'Min' => 0,
                                                                      'Max' => undef
                                                                    }, 'OMP::Range' ),
                                                    'priority' => 99
                                                  },
#          '7cad9ca196339ba303eb436ed3ce7801' => {
           'c08db4fb2eea8e8486e99bc1ee0f7ac2' => {
                                                  'telescope' => 'UKIRT',
                                                  'cloud' => 101,
                                                  'remaining' => '2',
                                                  'obscount' => 2,
                                                  'observations' => [
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
                                                  'projectid' => 'TJ01',
                                                  'moon' => 101,
                                                  'tau' => bless( {
                                                                    'Min' => 0,
                                                                    'Max' => undef
                                                                  }, 'OMP::Range' ),
                                                  'priority' => 99
                                                },
#          '971e659be8cbb43a91fce29383319b84O' => {
           'f7ec47641cadef30e7a3cc62002b632cO' => {
                                                   'telescope' => 'UKIRT',
                                                   'cloud' => 101,
                                                   'remaining' => '1',
                                                   'obscount' => 1,
                                                   'observations' => [
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
                                                   'projectid' => 'TJ01',
                                                   'moon' => 101,
                                                   'tau' => bless( {
                                                                     'Min' => 0,
                                                                     'Max' => undef
                                                                   }, 'OMP::Range' ),
                                                   'priority' => 99
                                                 }
        };
