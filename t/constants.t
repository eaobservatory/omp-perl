#!perl

# Test the behaviour of OMP::Constants

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
