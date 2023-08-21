#!perl

use strict;

use Test::More tests => 6;

require_ok('OMP::Translator::JCMTHeaders');

is(OMP::Translator::JCMTHeaders->fitsSafeString(
    "Piensa mal y acertar\x{e1}s"),
    'Piensa mal y acertaras',
    'Removal of diacritics');

is(OMP::Translator::JCMTHeaders->fitsSafeString(
    "Text with \x{6c49}\x{5b57} in it"),
    'Text with ?? in it',
    'Replacement of other characters');

is(OMP::Translator::JCMTHeaders->fitsSafeString(
    '1234567890123456789012345678901234567890123456789012345678901234567890'),
    '12345678901234567890123456789012345678901234567890123456789012345678',
    'Truncation to 68 characters');

is(OMP::Translator::JCMTHeaders->fitsSafeString(
    "I can't believe it's already 5 o'clock, Professor O'Brien will be arriving at O'Hare."),
    "I can't believe it's already 5 o'clock, Professor O'Brien will b",
    'Truncation with quote marks');

is(OMP::Translator::JCMTHeaders->fitsSafeString(
    "''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''"),
    "''''''''''''''''''''''''''''''''''",
    'Truncation all quote marks');
