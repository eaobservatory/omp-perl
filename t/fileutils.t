#!perl

use strict;
use Test::More tests => 8;

use OMP::Util::File;

# Check construction and setting "recent_file" option.
my $util = OMP::Util::File->new();
isa_ok($util, 'OMP::Util::File');

ok(not $util->recent_files);
$util->recent_files(1);
ok($util->recent_files);
$util->recent_files(0);
ok(not $util->recent_files);

$util = OMP::Util::File->new(recent_files => 0);
ok(not $util->recent_files);
$util = OMP::Util::File->new(recent_files => 1);
ok($util->recent_files);

# Check other internal attributes.
is(ref $util->{'file_time'}, 'HASH');
is(ref $util->{'file_raw'}, 'HASH');
