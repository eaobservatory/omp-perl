use strict;
use warnings;

use Test::More tests => 7;

use OMP::Error qw/:try/;
use OMP::TLEDB qw/standardize_tle_name/;

is(standardize_tle_name('NORAD12345'), 'NORAD12345',
    'Standardize TLE name which is already OK');

is(standardize_tle_name(' nOrAd 42 '), 'NORAD00042',
    'Standardize TLE name which can be corrected');

# Various bad names.
foreach my $target (
        'nombat 5565',      # Not a valid catalog name 
        'norad 444333',     # Too many digits
        'norad',            # No digits
        'x norad 4',        # Leading junk
        'norad 4 x',        # Trailing junk
        ) {
    my $threw = 0;

    try {
        standardize_tle_name($target);
    }
    catch OMP::Error with {
        $threw = 1;
    };

    ok($threw, 'Reject bad TLE name "' . $target . '"');
}
