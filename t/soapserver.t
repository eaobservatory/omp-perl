# Copyright (C) 2025 East Asian Observatory
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

use Compress::Zlib;
use OMP::Error qw/:try/;

use Test::More tests => 15;

require_ok('OMP::SOAPServer');
require_ok('OMP::SciProg');

# Check interpretation of return types.
is(OMP::SOAPServer->_find_return_type(),
    OMP::SOAPServer::OMP__SCIPROG_XML(),
    'Interpret undefined return type');
is(OMP::SOAPServer->_find_return_type('XML'),
    OMP::SOAPServer::OMP__SCIPROG_XML(),
    'Interpret return type XML');
is(OMP::SOAPServer->_find_return_type('GZIP'),
    OMP::SOAPServer::OMP__SCIPROG_GZIP(),
    'Interpret return type GZIP');
is(OMP::SOAPServer->_find_return_type('AUTO'),
    OMP::SOAPServer::OMP__SCIPROG_AUTO(),
    'Interpret return type AUTO');

my $E;
try {
    OMP::SOAPServer->_find_return_type('UNKNOWN');
} catch OMP::Error with {
    $E = shift;
};
ok(defined $E);
is($E->text, 'Unrecognised return type',
    'Error on bad return type');

# Check functionality of "compressReturnedItem" method.
my $sp = OMP::SciProg->new(XML => '<SpProg><projectID>TEST</projectID></SpProg>');
my $expect = "<?xml version=\"1.0\"?>\n<SpProg><projectID>TEST</projectID></SpProg>\n";

do {
    delete local $ENV{'HTTP_SOAPACTION'};
    my $xml = OMP::SOAPServer->compressReturnedItem($sp, 'XML');
    is($xml, $expect, '"Compress" as XML');

    my $zip = OMP::SOAPServer->compressReturnedItem($sp, 'GZIP');
    is($zip, Compress::Zlib::memGzip($expect), 'Compress as GZIP');
};

do {
    local $ENV{'HTTP_SOAPACTION'} = 'X';
    my $soap = OMP::SOAPServer->compressReturnedItem($sp, 'XML');
    isa_ok($soap, 'SOAP::Data');
};

# Check functionality of "uncompressGivenItem" method.
is(OMP::SOAPServer->uncompressGivenItem('plain text'),
    'plain text',
    '"Uncompress" plain text');

is(OMP::SOAPServer->uncompressGivenItem("\x1f\x8b\x08\x00\xe3\x64\xbe\x67\x00\x03\x2b\x49\x2d\x2e\x01\x00\x0c\x7e\x7f\xd8\x04\x00\x00\x00"),
    'test',
    'Uncompress gzipped data');

undef $E;
try {
    OMP::SOAPServer->uncompressGivenItem("\x1f\x8bXXXX");
} catch OMP::Error with {
    $E = shift;
};
ok(defined $E);
like($E->text, qr/did not uncompress correctly/,
    'Error on failure to uncompress gzipped data');
