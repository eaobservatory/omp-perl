#!/local/bin/perl -T

use CGI;
use CGI::Carp qw/ fatalsToBrowser /;
use JAC::Web;

# Start CGI environment
$query = new CGI;

print $query->header;

print STDOUT make_header( title => 'Misc. OMP Web Utilities',
                          "JAC Software" => "/software/" );

print STDOUT qq{

\n<BODY BGCOLOR="#FFFFFF" LINK="#FF00FF" VLINK="#FF00FF" ALINK="#FF00FF">\n
\n
<br>
<p>
<table width=500>\n

<tr><td colspan=2 align=center><h2>Misc. OMP Web Utilities</h2></rd></tr>\n
<tr><td valign=top><a href="ompsplot.pl">Ompsplot</a></td>\n
<td>Plot OMP science program targets</td></tr>\n

<tr><td colspan=2>&nbsp;</td></tr>\n

<tr><td valign=top><a href="ompfindtarget.pl">Ompfindtarget</a></td>\n
<td>Pencil-beam search for OMP targets around a given RA, Dec<BR>\n 
    or around targets from a specified science program</td></tr>\n

</table>\n
};

print make_footer( JAC::Web::file_stat($0),
                   contact => {
                               text => 'Remo Tilanus',
                               email => 'r.tilanus@jach.hawaii.edu'
                              }
                 );

