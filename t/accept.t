#!perl

# Test MSB acceptance, without interacting with the database.

# Copyright (C) 2018 East Asian Observatory.
# All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation; either version 2 of the License, or (at your option) any later
# version.
#
# This program is distributed in the hope that it will be useful,but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
# details.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, write to the Free Software Foundation, Inc.,51 Franklin
# Street, Fifth Floor, Boston, MA  02110-1301, USA

use strict;
use warnings;

use Test::More tests => 17;

require_ok('OMP::SciProg');
require_ok('OMP::MSBDB');

my $prog = new OMP::SciProg(FILE => 't/data/accept.xml');

isa_ok($prog, 'OMP::SciProg');

my $msbs = msb_list($prog);

my %checksum = map {$_->[0] => $_->[2]} @$msbs;

is(substr($checksum{'MSB A'}, 32), '', 'MSB A normal checksum');
is(substr($checksum{'MSB B'}, 32), 'O', 'MSB B or checksum');
is(substr($checksum{'MSB C'}, 32), 'O', 'MSB C or checksum');

is_deeply($msbs, [
    ['MSB A',  '10', $checksum{'MSB A'}],
    ['MSB B',  '10', $checksum{'MSB B'}],
    ['MSB C',  '10', $checksum{'MSB C'}],
], 'Inital MSB list');

# Accept MSB "A" (outside the OR folder).
ok(accept_msb($prog, $checksum{'MSB A'}), 'Accept A');

is_deeply(msb_list($prog), [
    ['MSB A',   '9', $checksum{'MSB A'}],  # Decremented
    ['MSB B',  '10', $checksum{'MSB B'}],
    ['MSB C',  '10', $checksum{'MSB C'}],
], 'MSB list after accepting A');

# Accept MSB "B" (inside the OR folder).
ok(accept_msb($prog, $checksum{'MSB B'}), 'Accept B (first time)');

$checksum{'MSB B'} =~ s/O//;
is_deeply(msb_list($prog), [
    ['MSB A',   '9', $checksum{'MSB A'}],
    ['MSB C', '-10', $checksum{'MSB C'}],  # Removed (-ve counter)
    ['MSB B',   '9', $checksum{'MSB B'}],  # Moved after OR, decremented
], 'MSB list after accepting B (once)');

# Accept MSB "B" again.
# Note: we are giving its old checksum (with the trailing 'O').
ok(accept_msb($prog, $checksum{'MSB B'}), 'Accept B (second time)');

is_deeply(msb_list($prog), [
    ['MSB A',   '9', $checksum{'MSB A'}],
    ['MSB C', '-10', $checksum{'MSB C'}],
    ['MSB B',   '8', $checksum{'MSB B'}],  # Decremented
], 'MSB list after accepting B (twice)');

# Undo MSB "A".
ok(undo_msb($prog, $checksum{'MSB A'}), 'Undo A');

is_deeply(msb_list($prog), [
    ['MSB A',  '10', $checksum{'MSB A'}],  # Incremented
    ['MSB C', '-10', $checksum{'MSB C'}],
    ['MSB B',   '8', $checksum{'MSB B'}],
], 'MSB list after undoing A');

# Undo MSB "B".
# Note: doesn't put the OR folder back together again.
ok(undo_msb($prog, $checksum{'MSB B'}), 'Undo B');

is_deeply(msb_list($prog), [
    ['MSB A',  '10', $checksum{'MSB A'}],
    ['MSB C', '-10', $checksum{'MSB C'}],
    ['MSB B',   '9', $checksum{'MSB B'}],  # Incremented
], 'MSB list after undoing B');


sub msb_list {
    my $prog = shift;

    my @result;

    foreach my $msb ($prog->msb()) {
        push @result, [$msb->msbtitle(), $msb->remaining(), $msb->checksum()];
    };

    return \@result;
}

sub accept_msb {
    return _accept_or_undo(@_, 1);
}

sub undo_msb {
    return _accept_or_undo(@_, 0);
}

sub _accept_or_undo {
    my $prog = shift;
    my $checksum = shift;
    my $accept = shift;

    # Accept the MSB the same way as OMP::MSBDB::doneMSB does: find it by
    # checksum and then call its hasBeenObserved method.

    my $msb = OMP::MSBDB::_find_msb_tolerant($prog, $checksum);

    return unless $msb;

    if ($accept) {
        $msb->hasBeenObserved();
    }
    else {
        $msb->undoObserve();
    }

    # Ensure the MSB list is up to date.
    $prog->locate_msbs();

    return 1;
}
