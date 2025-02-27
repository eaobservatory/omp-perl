#!perl

use strict;
use Test::More tests => 11;

require_ok('OMP::Query');

# Expected processed hash form of our query:
my %expect = (
    alpha => ['A & A'],
    beta => {min => 40},
    gamma => {max => 30},
    delta => {null => 1},
    epsilon => {null => 0},
    zeta => {null => 1},
    eta => ['B < B', 'C > C'],
    theta => ['DDD', 'EEE'],
    mu => [1234],
    nu => {like => 'III'},

    _attr => {
        alpha => {},
        beta => {},
        gamma => {},
        delta => {},
        epsilon => {},
        zeta => {},
        eta => {},
        theta => {},
        mu => {
            delta => 3,
        },
        nu => {},
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
);

# Try constructing a query from XML:
my $query = OMP::Query->new(XML => '<Query>
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
    <mu delta="3">1234</mu>
    <nu><like>III</like></nu>
</Query>');

isa_ok($query, 'OMP::Query');

my $hash = $query->raw_query_hash;

is_deeply($hash, \%expect);

# Try Constructing an equivalent query from a hash:
my $query2 = OMP::Query->new(HASH => {
    alpha => 'A & A',
    beta => {min => 40},
    gamma => {max => 30},
    delta => {null => 1},
    epsilon => {null => 0},
    zeta => {null => 1},
    eta => [
        'B < B',
        'C > C',
    ],
    theta => [
        'DDD',
        'EEE',
    ],
    EXPR__1 => {or => {
        iota => 'FFF',
        kappa => 'GGG',
    }},
    EXPR__2 => {not => {
        lambda => 'HHH',
    }},
    mu => {
        value => 1234,
        delta => 3,
    },
    nu => {
        like => 'III',
    },
});

isa_ok($query2, 'OMP::Query');

my $hash2 = $query2->raw_query_hash;

is_deeply($hash2, \%expect);

# Check some entries in the processed query hash.
my $qhash = $query2->query_hash;

isa_ok($qhash->{'beta'}, 'OMP::Range');
isa_ok($qhash->{'gamma'}, 'OMP::Range');
isa_ok($qhash->{'delta'}, 'OMP::Query::Null');
isa_ok($qhash->{'epsilon'}, 'OMP::Query::Null');
isa_ok($qhash->{'zeta'}, 'OMP::Query::Null');
isa_ok($qhash->{'nu'}, 'OMP::Query::Like');
