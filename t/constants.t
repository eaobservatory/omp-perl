
# Simple test of OMP::Constants
use strict;
use warnings;
use Test;
BEGIN { plan tests => 8 }

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

# And a fake one
eval "defined OMP__BLAH";
ok( $@ );
