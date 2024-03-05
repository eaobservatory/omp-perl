use strict;

use Test::More tests => 2;

BEGIN {use_ok('OMP::DB::JSA::TableCOMMON');}

# Check that the range end columns match the start columns
# by applying conversions.
my @end = map {
    s/_obs$/_end/;
    s/start$/end/;
    s/st$/en/;
    $_;
} OMP::DB::JSA::TableCOMMON::range_start_columns;

is_deeply(\@end, [OMP::DB::JSA::TableCOMMON::range_end_columns]);
