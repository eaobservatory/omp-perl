
# Simple test of OMP::Constants
use strict;
use warnings;
use Test;
BEGIN { plan tests => 12 }

use OMP::Constants qw/ :all /;

# Difficult to test more than the fact that they exist

# Status
ok( defined OMP__OK );
ok( defined OMP__ERROR );
ok( defined OMP__FATAL );

# Feedback
ok( defined OMP__FB_INFO );
ok( defined OMP__FB_IMPORTANT );
ok( defined OMP__FB_HIDDEN );
ok( defined OMP__FB_DELETE );

# MSB Done
ok( defined OMP__DONE_FETCH );
ok( defined OMP__DONE_DONE );
ok( defined OMP__DONE_ALLDONE );
ok( defined OMP__DONE_COMMENT );

# And a fake one
eval "defined OMP__BLAH";
ok( $@ );
