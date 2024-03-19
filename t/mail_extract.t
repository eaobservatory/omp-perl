#!perl

# Copyright (C) 2024 East Asian Observatory
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

use Test::More tests => 2 + 9;

use File::Spec;
use MIME::Entity;
use MIME::Parser;

require_ok('OMP::Mail');

# Basic check with constructed MIME entity.
my $entity = MIME::Entity->build(
    Type => 'multipart/mixed',
);
$entity->attach(
    Type => 'text/plain',
    Data => 'Hello!',
);

my $text = OMP::Mail->extract_body_text($entity);
is($text, 'Hello!');

# Test some example emails.
foreach (
        [
            'text-interleaved.txt',
            'Paragraph 1.

            A part of type [image/png] was removed.

            Paragraph 2.

            A part of type [image/png] was removed.

            Paragraph 3.

            A part of type [image/png] was removed.'
        ],
        [
            'text-attachment.txt',
            'This is the text of the email itself.

            1 attachment(s) of type [text/plain] removed.'
        ],
        [
            'html-images.txt',
            'This is an example.



            With HTML formatting.'
        ],
        [
            'html-text-attachment.txt',
            'This is a message with HTML formatting.'
        ],
        [
            'text-pine.txt',
            'Plain text written in Pine.

            2 attachment(s) of type [image/png] removed.',
        ],
        [
            'text-gmail.txt',
            'Example plain text from GMail.

            1 attachment(s) of type [image/png] removed.
            1 attachment(s) of type [text/plain] removed.'
        ],
        [
            'html-gmail.txt',
            'An *HTML* message from *GMail.*

            1 attachment(s) of type [image/png] removed.
            1 attachment(s) of type [text/plain] removed.'
        ],
        [
            'html-outlook.txt',
            'Message from outlook.live.com.

            3 attachment(s) of type [image/png] removed.'
        ],
        [
            'html-unicode.txt',
            "Message with \x{6c49}\x{5b57} in it."
        ]
        ) {
    my ($filename, $expect) = @$_;

    $expect =~ s/^ {12}//mg;

    my $parser = MIME::Parser->new();
    $parser->output_to_core(1);
    my $entity = $parser->parse_open(File::Spec->catfile('t', 'mail', $filename));

    my $text = OMP::Mail->extract_body_text($entity);

    is($text, $expect);
}
