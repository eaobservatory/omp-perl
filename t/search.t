#!perl

use strict;
use Test::More tests => 2
    + 2  # No terms
    + 2  # No match
    + 3  # Plain text
    + 3; # HTML

require_ok('OMP::CGIComponent::Search');

my $search = OMP::CGIComponent::Search->new();
isa_ok($search, 'OMP::CGIComponent::Search');

my %opt = (
    context_chars => 8,
);

# Test early exit due to no search terms.
my $text = 'alpha "beta" gamma delta epsilon zeta eta theta iota "kappa" lambda mu'
    . ' nu xi omicron pi rho sigma tau upsilon phi chi psi omega';
is($search->text_snippet('', $text, 0, %opt),
    'alpha "beta"...');
is($search->text_snippet('', $text, 0, html => 1, %opt),
    'alpha &quot;beta&quot;...');

# Test early exit due to to match.
is($search->text_snippet('peorth', $text, 0, %opt),
    'alpha "beta"...');
is($search->text_snippet('peorth', $text, 0, html => 1, %opt),
    'alpha &quot;beta&quot;...');

# Test plain text search.
is($search->text_snippet('beta', $text, 0, %opt),
    'alpha "beta" gamma...');
is($search->text_snippet('"chi psi"', $text, 0, %opt),
    '...phi chi psi omega');
is($search->text_snippet('kappa', $text, 0, %opt),
    '...iota "kappa" lambda...');

# Test HTML highlighting.
$opt{'html'} = 1;

is($search->text_snippet('kappa', $text, 0, %opt),
    '...iota &quot;<b>kappa</b>&quot; lambda...');
is($search->text_snippet('alpha', $text, 0, %opt),
    '<b>alpha</b> &quot;beta&quot;...');
is($search->text_snippet('omega', $text, 0, %opt),
    '...psi <b>omega</b>');
