
# Simple test of OMP::Constants
use strict;
use warnings;
use Test::More tests => 12;

use OMP::Constants qw/ :all /;

# Difficult to test more than the fact that they exist

# Status
ok( defined OMP__OK, "__OK" );
ok( defined OMP__ERROR, "__ERROR" );
ok( defined OMP__FATAL, "__FATAL" );

# Feedback
ok( defined OMP__FB_INFO, "__FB_INFO" );
ok( defined OMP__FB_IMPORTANT, "__FB_IMPORTANT" );
ok( defined OMP__FB_HIDDEN, "__FB_HIDDEN" );
ok( defined OMP__FB_DELETE, "__FB_DELETE" );

# MSB Done
ok( defined OMP__DONE_FETCH, "__DONE_FETCH" );
ok( defined OMP__DONE_DONE, "__DONE_DONE" );
ok( defined OMP__DONE_ALLDONE, "__DONE_ALLDONE" );
ok( defined OMP__DONE_COMMENT, "__DONE_COMMENT" );

# And a fake one
eval "defined OMP__BLAH";
ok( $@, "Failure okay" );
