#!perl

# Test the behaviour of OMP::User objects.

# Copyright (C) 2002-2005 Particle Physics and Astronomy Research Council.
# All Rights Reserved.

# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation; either version 2 of the License, or (at your option) any later
# version.

# This program is distributed in the hope that it will be useful,but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
# PARTICULAR PURPOSE. See the GNU General Public License for more details.

# You should have received a copy of the GNU General Public License along with
# this program; if not, write to the Free Software Foundation, Inc., 59 Temple
# Place,Suite 330, Boston, MA  02111-1307, USA

use Test::More tests => 8 + 31 + (17 * 2) + 13;
use Encode qw/find_encoding/;
use strict;
require_ok('OMP::User');


# Create a simply user object
my $user = OMP::User->new(
    name => 'Frossie Economou',
    email => 'frossie@blah.net',
    userid => 'FROSSIE',
);

isa_ok($user, 'OMP::User');
is($user->name, 'Frossie Economou', 'Check name');
is("$user", $user->name(), 'Check stringification (name)');
is($user->email, 'frossie@blah.net', 'Check email');
is($user->userid, 'FROSSIE', 'Check userid');
is($user->domain, 'blah.net', 'Check email domain');
is($user->addressee, 'frossie', 'Check email addressee');

# see if we can guess some user ids
my %guessed = (
    VANDERHUCHTK => 'Karel van der Hucht',
    JENNESST => ' Tim Jenness ',
    ECONOMOUF => 'Frossie Economou',
    MORIARTYSCHIEVENG => 'Gerald Moriarty-Schieven',
    PERSONA => 'A. Person Jr',
    PERSONB => 'Person Sr, B',
    PERSONC => 'Person Sr., C',
    FULLERG => 'Dr. G. Fuller',
    STEVENSJ => 'Dr J. A. Stevens',
    PERSOND => 'Prof. D. Person',
    PERSONE => 'Mrs E. Person',
    PERSONF => 'Mr. F Person',
    PERSONG => 'Mrs. G. Person',
    PERSONH => 'Person, Ms. H',
    PERSONI => 'Person, Prof I',
    ADAMSONA => 'Adamson, Andy',
    BARNUMP => 'P. T. Barnum',
    VANBEETHOVENL => 'Ludwig van Beethoven',
    MOZARTW => 'Wolfgang Gottlieb Mozart',
    LEGUINU => 'Ursula K Le Guin',
    LEPERSONA => 'Le Person, A.',
    CDEA => 'A.B.CDE',
    DELOREYK => 'K.Delorey',
    DEWITTS => 'Shaun de Witt',
    ROGERSMITH => 'Rogersmith',
    VANTHOFFG => "Griselda van 't Hoff",
    DAVEW => 'White van driver Dave',
    VONNOVATOY => 'Yvonne von Novato',
    DIGORYC => 'Cedric di Gory',
    VANDELAS => 'Spencer van de La',
    MUNOZM => "Mat\x{ed}as Mu\x{f1}oz",
);

for my $userid (keys %guessed) {
    print "# $guessed{$userid}\n";
    is(OMP::User->infer_userid($guessed{$userid}), $userid, 'Infer userid');
}


# Now extract User information from emails and HTML
my @extract = (
    {
        href => '<A href="mailto:timtest@jach.hawaii.edu">Tim Jenness</a>',
        email => 'Tim Jenness <timtest@jach.hawaii.edu>',
        output => OMP::User->new(
            userid => 'JENNESST',
            name => 'Tim Jenness',
            email => 'timtest@jach.hawaii.edu'
        ),
    },
    {
        href => '<A href="mailto:t.jenness@jach">t.jenness@jach</a>',
        email => 't.jenness@jach',
        output => OMP::User->new(
            userid => 'JENNESST',
            name => 'T.Jenness',
            email => 't.jenness@jach'
        ),
    },
);

for my $test (@extract) {
    # First explicitly
    my $emailref;
    my $emailuser = OMP::User->extract_user_from_email($test->{email}, \$emailref);
    my $hrefuser = OMP::User->extract_user_from_href($test->{href});

    # then implictly
    my $guess1 = OMP::User->extract_user($test->{email});
    my $guess2 = OMP::User->extract_user($test->{href});

    for my $user ($emailuser, $hrefuser, $guess1, $guess2) {
        isa_ok($user, 'OMP::User');

        if (defined $user) {
            # now loop over user information
            # and compare (all lower case)
            for my $method (qw/userid name email/) {
                is(lc($user->$method),
                    lc($test->{output}->$method),
                    "Compare $method"
                );
            }
        }
        else {
            for (1 .. 3) {
                ok(0, 'Did not get valid user');
            }
        }
    }

    # Check the value written to $emailref.
    is($emailref,
        $test->{'output'}->email(),
        'Compare email address returned by reference'
    );
}

$user = OMP::User->new(
    name => 'John Smith',
    email => 'john@smith.me',
);

my $encoding = find_encoding('MIME-Header');

is($user->as_email_hdr(),
    '"John Smith" <john@smith.me>',
    'Full email header');
is($user->as_email_hdr($encoding),
    '=?UTF-8?B?Sm9obiBTbWl0aA==?= <john@smith.me>',
    'Full email header (encoded)');
is($user->as_email_hdr_via_flex(),
    '"John Smith (via flex)" <flex@eaobservatory.org>',
    'Full email header (flex)');
is($user->as_email_hdr_via_flex($encoding),
    '=?UTF-8?B?Sm9obiBTbWl0aCAodmlhIGZsZXgp?= <flex@eaobservatory.org>',
    'Full email header (flex, encoded)');

$user = OMP::User->new(
    name => 'John Smith',
);

is($user->as_email_hdr(),
    '"John Smith"',
    'Name-only email header');
is($user->as_email_hdr($encoding),
    '=?UTF-8?B?Sm9obiBTbWl0aA==?=',
    'Name-only email header');
is($user->as_email_hdr_via_flex(),
    '"John Smith (via flex)" <flex@eaobservatory.org>',
    'Name-only email header (flex)');

$user = OMP::User->new(
    email => 'john@smith.me',
);

is($user->as_email_hdr(),
    'john@smith.me',
    'Email-only header');
is($user->as_email_hdr_via_flex(),
    '"OMP" <flex@eaobservatory.org>',
    'Email-only header (flex)');

$user = OMP::User->new();

is($user->as_email_hdr(),
    'No contact information',
    'Empty email header');
is($user->as_email_hdr_via_flex(),
    '"OMP" <flex@eaobservatory.org>',
    'Empty email header (flex)');

is(OMP::User->get_flex()->as_email_hdr(),
    '"OMP" <flex@eaobservatory.org>',
    'Flex email header');

is(OMP::User->get_omp_group()->as_email_hdr(),
    '"OMP Group" <omp-group@eaobservatory.org>',
    'OMP group header');
