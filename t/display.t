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

use Test::More tests => 7;
use strict;
require_ok('OMP::Display');

is(OMP::Display->remove_cr("alpha\r\nbeta\r\ngamma"), "alpha\nbeta\ngamma");

# Test that our formatter subclass (OMP::HTMLFormatText) generates the intended
# 8-character horizontal rule.
is(OMP::Display->html2plain('<p>alpha</p><hr><p>beta</p>'),
    "alpha\n\n--------\n\nbeta\n");

# Test formatting into lines and paragraphs.
is(OMP::Display->format_html_inline("a\r\n<b>\r\n\r\n<c>\r\nd", 0),
    "a<br />&lt;b&gt;\n<br />&nbsp;<br />\n&lt;c&gt;<br />d");

is(OMP::Display->format_html_inline("a\r\n<b>\r\n\r\n<c>\r\nd", 1),
    "<p>a<br />&lt;b&gt;</p>\n<p>&lt;c&gt;<br />d</p>");

is(OMP::Display->replace_omp_links('
Plain fault: 20100101.001
Fault with response: 20100101.001#10
Response: #10
JCMT:2020-02-02
UKIRT:2020-02-02
acsis_00001_20240130T035159
scuba2_00002_20240130T100556
',
    fault => 20200202.002),
    '
Plain fault: <a href="/cgi-bin/viewfault.pl?fault=20100101.001">20100101.001</a>
Fault with response: <a href="/cgi-bin/viewfault.pl?fault=20100101.001#response10">20100101.001#10</a>
Response: <a href="#response10">#10</a>
<a href="/cgi-bin/nightrep.pl?tel=JCMT&amp;utdate=2020-02-02">2020-02-02</a>
<a href="/cgi-bin/nightrep.pl?tel=UKIRT&amp;utdate=2020-02-02">2020-02-02</a>
<a href="/cgi-bin/staffworf.pl?telescope=JCMT&amp;obsid=acsis_00001_20240130T035159">acsis_00001_20240130T035159</a>
<a href="/cgi-bin/staffworf.pl?telescope=JCMT&amp;obsid=scuba2_00002_20240130T100556">scuba2_00002_20240130T100556</a>
');

is(OMP::Display->replace_omp_links('
20100101.001
',
    complete_url => 1),
    '
<a href="https://omp.eao.hawaii.edu/cgi-bin/viewfault.pl?fault=20100101.001">20100101.001</a>
');
