#!perl

use strict;
use Test::More tests => 3;

require_ok('OMP::DBQuery');

my $query = OMP::DBQuery->new(XML => '<DBQuery>
    <alpha>A &amp; A</alpha>
    <beta><min>40</min></beta>
    <gamma><max>30</max></gamma>
    <delta><null/></delta>
    <epsilon><null>0</null></epsilon>
    <zeta><null>1</null></zeta>
    <etas>
        <eta>B &lt; B</eta>
        <eta>C &gt; C</eta>
    </etas>
    <theta>DDD</theta>
    <theta>EEE</theta>
    <or>
        <iota>FFF</iota>
        <kappa>GGG</kappa>
    </or>
    <not>
        <lambda>HHH</lambda>
    </not>
</DBQuery>');

isa_ok($query, 'OMP::DBQuery');

my $hash = $query->raw_query_hash;

is_deeply($hash, {
    alpha => ['A & A'],
    beta => {min => 40},
    gamma => {max => 30},
    delta => {null => 1},
    epsilon => {null => 0},
    zeta => {null => 1},
    eta => ['B < B', 'C > C'],
    theta => ['DDD', 'EEE'],

    _attr => {
        alpha => {},
        beta => {},
        gamma => {},
        delta => {},
        epsilon => {},
        zeta => {},
        eta => {},
        theta => {},
    },

    EXPR__1 => {
        _JOIN => 'OR',
        iota => ['FFF'],
        kappa => ['GGG'],
        _attr => {
            iota => {},
            kappa => {},
        },
    },

    EXPR__2 => {
        _FUNC => 'NOT',
        _JOIN => 'AND',
        lambda => ['HHH'],
        _attr => {
            lambda => {},
        },
    },
});
