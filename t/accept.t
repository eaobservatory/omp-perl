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

use Test::More tests => 41;

require_ok('OMP::SciProg');
require_ok('OMP::MSBDB');

my $prog = new OMP::SciProg(FILE => 't/data/accept.xml');

isa_ok($prog, 'OMP::SciProg');

my $msbs = msb_list($prog);

my %checksum = map {$_->[0] => $_->[2]} @$msbs;

is(substr($checksum{'MSB A'}, 32), '', 'MSB A normal checksum');
is(substr($checksum{'MSB B'}, 32), 'O', 'MSB B or checksum');
is(substr($checksum{'MSB C'}, 32), 'O', 'MSB C or checksum');
is(substr($checksum{'MSB D'}, 32), 'OA', 'MSB D or-and checksum');
is(substr($checksum{'MSB E'}, 32), 'OA', 'MSB E or-and checksum');
is(substr($checksum{'MSB F'}, 32), 'OA', 'MSB F or-and checksum');
is(substr($checksum{'MSB G'}, 32), 'OA', 'MSB G or-and checksum');
is(substr($checksum{'MSB H'}, 32), 'OS', 'MSB H or-survey checksum');
is(substr($checksum{'MSB I'}, 32), 'OS', 'MSB I or-survey checksum');
is(substr($checksum{'MSB J'}, 32), 'S', 'MSB J survey checksum');
is(substr($checksum{'MSB J2'}, 32), 'S', 'MSB J2 survey checksum');
is(substr($checksum{'MSB K'}, 32), 'OAS', 'MSB K or-and-survey checksum');
is(substr($checksum{'MSB L'}, 32), 'O', 'MSB L or checksum');

is_deeply($msbs, [
    ['MSB A',  '10', $checksum{'MSB A'}],
    ['MSB B',  '10', $checksum{'MSB B'}],
    ['MSB C',  '10', $checksum{'MSB C'}],
    ['MSB D',  '10', $checksum{'MSB D'}],
    ['MSB E',  '10', $checksum{'MSB E'}],
    ['MSB F',  '10', $checksum{'MSB F'}],
    ['MSB G',  '10', $checksum{'MSB G'}],
    ['MSB H',  '10', $checksum{'MSB H'}],
    ['MSB I',  '10', $checksum{'MSB I'}],
    ['MSB J',   '5', $checksum{'MSB J'}],
    ['MSB J2',  '5', $checksum{'MSB J2'}],
    ['MSB K',  '10', $checksum{'MSB K'}],
    ['MSB L',  '10', $checksum{'MSB L'}],
], 'Inital MSB list');

# Accept MSB "A" (outside the OR folder).
ok(accept_msb($prog, $checksum{'MSB A'}), 'Accept A');

is_deeply(msb_list($prog), [
    ['MSB A',   '9', $checksum{'MSB A'}],  # Decremented
    ['MSB B',  '10', $checksum{'MSB B'}],
    ['MSB C',  '10', $checksum{'MSB C'}],
    ['MSB D',  '10', $checksum{'MSB D'}],
    ['MSB E',  '10', $checksum{'MSB E'}],
    ['MSB F',  '10', $checksum{'MSB F'}],
    ['MSB G',  '10', $checksum{'MSB G'}],
    ['MSB H',  '10', $checksum{'MSB H'}],
    ['MSB I',  '10', $checksum{'MSB I'}],
    ['MSB J',   '5', $checksum{'MSB J'}],
    ['MSB J2',  '5', $checksum{'MSB J2'}],
    ['MSB K',  '10', $checksum{'MSB K'}],
    ['MSB L',  '10', $checksum{'MSB L'}],
], 'MSB list after accepting A');

# Accept MSB "B" (inside the OR folder).
ok(accept_msb($prog, $checksum{'MSB B'}), 'Accept B (first time)');

$checksum{'MSB B'} =~ s/O//;
is_deeply(msb_list($prog), [
    ['MSB A',   '9', $checksum{'MSB A'}],
    ['MSB C', '-10', $checksum{'MSB C'}],  # Removed (-ve counter)
    ['MSB B',   '9', $checksum{'MSB B'}],  # Moved after OR, decremented
    ['MSB D',  '10', $checksum{'MSB D'}],
    ['MSB E',  '10', $checksum{'MSB E'}],
    ['MSB F',  '10', $checksum{'MSB F'}],
    ['MSB G',  '10', $checksum{'MSB G'}],
    ['MSB H',  '10', $checksum{'MSB H'}],
    ['MSB I',  '10', $checksum{'MSB I'}],
    ['MSB J',   '5', $checksum{'MSB J'}],
    ['MSB J2',  '5', $checksum{'MSB J2'}],
    ['MSB K',  '10', $checksum{'MSB K'}],
    ['MSB L',  '10', $checksum{'MSB L'}],
], 'MSB list after accepting B (once)');

# Accept MSB "B" again.
# Note: we are giving its old checksum (with the trailing 'O').
ok(accept_msb($prog, $checksum{'MSB B'}), 'Accept B (second time)');

is_deeply(msb_list($prog), [
    ['MSB A',   '9', $checksum{'MSB A'}],
    ['MSB C', '-10', $checksum{'MSB C'}],
    ['MSB B',   '8', $checksum{'MSB B'}],  # Decremented
    ['MSB D',  '10', $checksum{'MSB D'}],
    ['MSB E',  '10', $checksum{'MSB E'}],
    ['MSB F',  '10', $checksum{'MSB F'}],
    ['MSB G',  '10', $checksum{'MSB G'}],
    ['MSB H',  '10', $checksum{'MSB H'}],
    ['MSB I',  '10', $checksum{'MSB I'}],
    ['MSB J',   '5', $checksum{'MSB J'}],
    ['MSB J2',  '5', $checksum{'MSB J2'}],
    ['MSB K',  '10', $checksum{'MSB K'}],
    ['MSB L',  '10', $checksum{'MSB L'}],
], 'MSB list after accepting B (twice)');

# Undo MSB "A".
ok(undo_msb($prog, $checksum{'MSB A'}), 'Undo A');

is_deeply(msb_list($prog), [
    ['MSB A',  '10', $checksum{'MSB A'}],  # Incremented
    ['MSB C', '-10', $checksum{'MSB C'}],
    ['MSB B',   '8', $checksum{'MSB B'}],
    ['MSB D',  '10', $checksum{'MSB D'}],
    ['MSB E',  '10', $checksum{'MSB E'}],
    ['MSB F',  '10', $checksum{'MSB F'}],
    ['MSB G',  '10', $checksum{'MSB G'}],
    ['MSB H',  '10', $checksum{'MSB H'}],
    ['MSB I',  '10', $checksum{'MSB I'}],
    ['MSB J',   '5', $checksum{'MSB J'}],
    ['MSB J2',  '5', $checksum{'MSB J2'}],
    ['MSB K',  '10', $checksum{'MSB K'}],
    ['MSB L',  '10', $checksum{'MSB L'}],
], 'MSB list after undoing A');

# Undo MSB "B".
# Note: doesn't put the OR folder back together again.
ok(undo_msb($prog, $checksum{'MSB B'}), 'Undo B');

is_deeply(msb_list($prog), [
    ['MSB A',  '10', $checksum{'MSB A'}],
    ['MSB C', '-10', $checksum{'MSB C'}],
    ['MSB B',   '9', $checksum{'MSB B'}],  # Incremented
    ['MSB D',  '10', $checksum{'MSB D'}],
    ['MSB E',  '10', $checksum{'MSB E'}],
    ['MSB F',  '10', $checksum{'MSB F'}],
    ['MSB G',  '10', $checksum{'MSB G'}],
    ['MSB H',  '10', $checksum{'MSB H'}],
    ['MSB I',  '10', $checksum{'MSB I'}],
    ['MSB J',   '5', $checksum{'MSB J'}],
    ['MSB J2',  '5', $checksum{'MSB J2'}],
    ['MSB K',  '10', $checksum{'MSB K'}],
    ['MSB L',  '10', $checksum{'MSB L'}],
], 'MSB list after undoing B');

# Accept MSB "D" (in AND folder).
ok(accept_msb($prog, $checksum{'MSB D'}), 'Accept D');

$checksum{'MSB D'} =~ s/O//;
$checksum{'MSB E'} =~ s/O//;
is_deeply(msb_list($prog), [
    ['MSB A',  '10', $checksum{'MSB A'}],
    ['MSB C', '-10', $checksum{'MSB C'}],
    ['MSB B',   '9', $checksum{'MSB B'}],
    ['MSB F', '-10', $checksum{'MSB F'}],  # Removed (-ve counter)
    ['MSB G', '-10', $checksum{'MSB G'}],  # Removed (-ve counter)
    ['MSB D',   '9', $checksum{'MSB D'}],  # Moved out
    ['MSB E',  '10', $checksum{'MSB E'}],  # Moved out
    ['MSB H',  '10', $checksum{'MSB H'}],
    ['MSB I',  '10', $checksum{'MSB I'}],
    ['MSB J',   '5', $checksum{'MSB J'}],
    ['MSB J2',  '5', $checksum{'MSB J2'}],
    ['MSB K',  '10', $checksum{'MSB K'}],
    ['MSB L',  '10', $checksum{'MSB L'}],
], 'MSB list after accepting D');

# Accept MSB "H" (in OR folder and survey container).
ok(accept_msb($prog, $checksum{'MSB H'}), 'Accept H');

$checksum{'MSB H'} =~ s/O//;
is_deeply(msb_list($prog), [
    ['MSB A',  '10', $checksum{'MSB A'}],
    ['MSB C', '-10', $checksum{'MSB C'}],
    ['MSB B',   '9', $checksum{'MSB B'}],
    ['MSB F', '-10', $checksum{'MSB F'}],
    ['MSB G', '-10', $checksum{'MSB G'}],
    ['MSB D',   '9', $checksum{'MSB D'}],
    ['MSB E',  '10', $checksum{'MSB E'}],
    ['MSB I', '-10', $checksum{'MSB I'}],  # Removed (-ve counter)
    ['MSB H',   '9', $checksum{'MSB H'}],  # Moved out
    ['MSB J',   '5', $checksum{'MSB J'}],
    ['MSB J2',  '5', $checksum{'MSB J2'}],
    ['MSB K',  '10', $checksum{'MSB K'}],
    ['MSB L',  '10', $checksum{'MSB L'}],
], 'MSB list after accepting H');

like("$prog", qr/<choose>1<\/choose>/, 'Choose 1 before accepting J');
unlike("$prog", qr/<choose>0<\/choose>/, 'Not choose 0 before accepting J');

# Accept MSB "J" (in choose-1 survey container).
ok(accept_msb($prog, $checksum{'MSB J'}), 'Accept J');

like("$prog", qr/<choose>0<\/choose>/, 'Choose 0 after accepting J');
unlike("$prog", qr/<choose>1<\/choose>/, 'Not choose 1 after accepting J');

is_deeply(msb_list($prog), [
    ['MSB A',  '10', $checksum{'MSB A'}],
    ['MSB C', '-10', $checksum{'MSB C'}],
    ['MSB B',   '9', $checksum{'MSB B'}],
    ['MSB F', '-10', $checksum{'MSB F'}],
    ['MSB G', '-10', $checksum{'MSB G'}],
    ['MSB D',   '9', $checksum{'MSB D'}],
    ['MSB E',  '10', $checksum{'MSB E'}],
    ['MSB I', '-10', $checksum{'MSB I'}],
    ['MSB H',   '9', $checksum{'MSB H'}],
    ['MSB J',   '4', $checksum{'MSB J'}],  # Decremented
    ['MSB J2', '-5', $checksum{'MSB J2'}], # Removed (-ve counter)
    ['MSB K',  '10', $checksum{'MSB K'}],
    ['MSB L',  '10', $checksum{'MSB L'}],
], 'MSB list after accepting J');

# Accept MSB "K" (in nested OR / AND / survey container).
ok(accept_msb($prog, $checksum{'MSB K'}), 'Accept K');

$checksum{'MSB K'} =~ s/O//;
is_deeply(msb_list($prog), [
    ['MSB A',  '10', $checksum{'MSB A'}],
    ['MSB C', '-10', $checksum{'MSB C'}],
    ['MSB B',   '9', $checksum{'MSB B'}],
    ['MSB F', '-10', $checksum{'MSB F'}],
    ['MSB G', '-10', $checksum{'MSB G'}],
    ['MSB D',   '9', $checksum{'MSB D'}],
    ['MSB E',  '10', $checksum{'MSB E'}],
    ['MSB I', '-10', $checksum{'MSB I'}],
    ['MSB H',   '9', $checksum{'MSB H'}],
    ['MSB J',   '4', $checksum{'MSB J'}],
    ['MSB J2', '-5', $checksum{'MSB J2'}],
    ['MSB L', '-10', $checksum{'MSB L'}],  # Remove (-ve counter)
    ['MSB K',   '9', $checksum{'MSB K'}],  # Moved out
], 'MSB list after accepting K');

# Try the "hasBeenCompletelyObserved" method.
ok(complete_msb($prog, $checksum{'MSB A'}), 'Complete A');

is_deeply(msb_list($prog), [
    ['MSB A', '-10', $checksum{'MSB A'}], # Remove (-ve counter)
    ['MSB C', '-10', $checksum{'MSB C'}],
    ['MSB B',   '9', $checksum{'MSB B'}],
    ['MSB F', '-10', $checksum{'MSB F'}],
    ['MSB G', '-10', $checksum{'MSB G'}],
    ['MSB D',   '9', $checksum{'MSB D'}],
    ['MSB E',  '10', $checksum{'MSB E'}],
    ['MSB I', '-10', $checksum{'MSB I'}],
    ['MSB H',   '9', $checksum{'MSB H'}],
    ['MSB J',   '4', $checksum{'MSB J'}],
    ['MSB J2', '-5', $checksum{'MSB J2'}],
    ['MSB L', '-10', $checksum{'MSB L'}],
    ['MSB K',   '9', $checksum{'MSB K'}],
], 'MSB list after completing A');


sub msb_list {
    my $prog = shift;

    my @result;
    my %seen;

    foreach my $msb ($prog->msb()) {
        my $title = $msb->msbtitle();
        # Number duplicates to deal with survey containers.
        $title .= $seen{$title} if $seen{$title} ++;
        push @result, [$title, $msb->remaining(), $msb->checksum()];
    };

    return \@result;
}

sub accept_msb {
    return _accept_or_undo(@_, 1);
}

sub undo_msb {
    return _accept_or_undo(@_, 0);
}

sub complete_msb {
    return _accept_or_undo(@_, 'complete');
}

sub _accept_or_undo {
    my $prog = shift;
    my $checksum = shift;
    my $accept = shift;

    # Accept the MSB the same way as OMP::MSBDB::doneMSB does: find it by
    # checksum and then call its hasBeenObserved method.

    my $msb = OMP::MSBDB::_find_msb_tolerant($prog, $checksum);

    return unless $msb;

    if ($accept eq 'complete') {
        $msb->hasBeenCompletelyObserved();
    }
    elsif ($accept) {
        $msb->hasBeenObserved();
    }
    else {
        $msb->undoObserve();
    }

    # Ensure the MSB list is up to date.
    $prog->locate_msbs();

    return 1;
}
