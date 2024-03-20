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

use Test::More tests => 1 + 3 + 7 + 7;

use File::Spec;
use MIME::Entity;
use MIME::Parser;

use OMP::User;

require_ok('OMP::Mail');

my $from = OMP::User->new(userid => 'USER1', email => 'u1@example');
my $to = OMP::User->new(userid => 'USER2', email => 'u2@example');

my ($mailer, $mess);

# Plain text message.
$mailer = OMP::Mail->new();
$mess = $mailer->build(
    from => $from,
    to => [$to],
    subject => 'Test',
    message => 'Message.',
    preformatted => 0,
);

isa_ok($mess, 'MIME::Entity');
is($mess->mime_type, 'text/plain');
is($mess->bodyhandle->as_string, 'Message.');

# HTML message.
$mailer = OMP::Mail->new();
$mess = $mailer->build(
    from => $from,
    to => [$to],
    subject => 'Test',
    message => '<p>Message.</p>',
    preformatted => 1,
);

isa_ok($mess, 'MIME::Entity');
is($mess->mime_type, 'multipart/alternative');
is((scalar $mess->parts), 2);
is($mess->parts(0)->mime_type, 'text/plain');
is($mess->parts(0)->bodyhandle->as_string, "Message.\n");
is($mess->parts(1)->mime_type, 'text/html');
is($mess->parts(1)->bodyhandle->as_string, "<p>Message.</p>");

# HTML message with specified plain alternative.
$mailer = OMP::Mail->new();
$mess = $mailer->build(
    from => $from,
    to => [$to],
    subject => 'Test',
    message => '<p>Message.</p>',
    message_plain => 'Plain equivalent.',
    preformatted => 1,
);

isa_ok($mess, 'MIME::Entity');
is($mess->mime_type, 'multipart/alternative');
is((scalar $mess->parts), 2);
is($mess->parts(0)->mime_type, 'text/plain');
is($mess->parts(0)->bodyhandle->as_string, 'Plain equivalent.');
is($mess->parts(1)->mime_type, 'text/html');
is($mess->parts(1)->bodyhandle->as_string, "<p>Message.</p>");
