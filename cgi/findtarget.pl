#!/local/bin/perl -TXs

# Warnings are disabled

=head1 NAME

ompfindtarget - This routine performs a pencil-beam search for targets 
 around a specified position or around targets from a specified projects.


=head1 DESCRIPTION

PERL wrapper to generate a html access page. The actual search is
done by the non-interactive routine 'ompfindtarget'.

=cut

#use CGI qw/ -debug /;
use CGI;
use CGI::Carp qw/ fatalsToBrowser /;
use JAC::Web;

# Start CGI environment
$query = new CGI;

print $query->header;

print STDOUT make_header( title => 'JAC OMP OMPFINDTARGET ',
                          "JAC Software" => "/software/" );

# Work out semester
my ($dsem,$psem) = &find_semester();

# Calls non-interactive routine to do the job
my $command = "/web/jac-bin/ompsplot/ompfindtarget";

# Make world readable and initialize variables
my $msg = "";       # Message buffer which will be printed by show()
my $rep = "";       # Results buffer which will be printed by show()

# ----------------------------------------------------------------------
# Parse the command line options

# if we were not called with arguments, create the input page
if (!$query->param) {
  &html_header();
  &show_inputpage();
  &html_footer();
  exit;
}

my ($ra, $dec, $sep, $proj, $tel, $sem);

# Project:
my $prj = $query->param('projid');
($prj =~ /^([\w\/\*]+)$/ ) &&  ($proj = "$1") || ($proj = "");

# RA
my $rra = $query->param('ra');
$rra =~ s/\ /\:/g;
$rra =~ s/^\s+//;
$rra =~ s/\s+$//;
($proj eq "" && $rra =~ /^([\d\:\.\ ]+)$/) && ($ra = "$1") || ($ra = "");

# Dec
my $ddec = $query->param('dec');
$ddec =~ s/\ /\:/g;
$ddec =~ s/^\s+//;
$ddec =~ s/\s+$//;
($proj eq "" && $ddec =~ /^([\d\-\:\.\ ]+)$/) && ($dec = "$1") || ($dec = "");

# Telescope
my $ttel = $query->param('tel');
( $ttel =~ /^(\w+)$/ ) && ($tel = $ttel) || ($tel = "");

# Separation
my $ssep = $query->param('sep');
( $ssep =~ /^(\d+)$/ ) && ($sep = $ssep) || ($sep = "");

# Semester
my $ssem= $query->param('sem');
( $ssem =~ /^([\w\d\*]+)$/ ) && ($sem = $ssem) || ($sem = "");
$sem =~ s/^m//i;

if ( $ra eq "" && $dec eq "" &&  $proj eq "" ) {
  $msg .= "***ERROR*** must specify a valid project or a RA,Dec!<br>";
  $msg .= "            RA, dec: '$rra', '$ddec'; Proj: '$prj'!<br>";
}

my $version = $query->param('version');
if (defined $version) {
   $msg .= "Ompfindtarget version 1.0 -- Author: Remo Tilanus,<br>"; 
   $msg .= "Joint Astronomy Centre, Hilo, Hawaii.<br>";
 }

my $help = $query->param('help');
if (defined $help) {
  $msg .= qq {
<p>
 This routine performs a pencil-beam search for targets around a specfied
 specified position or around targets from a specified projects.
<br>
<table>
<tr><td>&nbsp;</td><td>Ra </td><td>Right Ascension in J2000. 
        </td><td>(No default)</td></tr>
<tr><td>&nbsp;</td><td>Dec </td><td>Declination in J2000. 
        </td><td>(No default)</td></tr>
<tr><td>&nbsp;</td><td>Projectid</td><td>Project to select reference targets from. 
        </td><td>(No default)</td></tr>
<tr><td>&nbsp;</td><td colspan=2>Either specify a RA and Dec or specify a project;
If a project is specified, RA and Dec are ignored.</td></tr>
<tr><td>&nbsp;</td><td>Separation </td><td>Radius in arcsecs for search beam.
       </td><td>(Default 600).</td></tr>
<tr><td>&nbsp;</td><td>Semester </td><td>Semester [ 07A | ... | all ]. 
       </td><td>(Default: current). </td></tr>
<tr><td>&nbsp;</td><td>Telescope </td><td>Telescope name: [ UKIRT | JCMT | all ]. 
       </td><td>(Default: UKIRT).</td></tr>
</table>
<p>
};
}

if ($msg =~ /^\w/) {
   &html_header();
   &show();
   &html_footer();
   exit;
};

# ----------------------------------------------------------------------
# Execute command

if (-e "$command") {
  $options = "";
  $options .= "-proj ${proj} " if (defined $proj && $proj ne "");
  $options .= "-ra ${ra} "     if (defined $ra   && $ra   ne "");
  $options .= "-dec ${dec} "   if (defined $dec  && $dec  ne "");
  $options .= "-sep ${sep} "   if (defined $sep  && $sep  ne "");
  $options .= "-sem ${sem} "   if (defined $sem  && $sem  ne "");
  $options .= "-tel ${tel} "   if (defined $tel  && $tel  ne "");

  # Find targets
  my $cmd_line = "${options}";
  my $command_line;
  # Untaint command-line
  ($cmd_line =~ /^([\w\d\:\_\-\ \/\*]+)$/) && 
               ($command_line = "$1") || ($command_line = "");
  $ENV{"PATH"} = "";
  $rep .= `${command} ${command_line}`;
} else {
  $msg .= "***ERROR**** failed to find '$command'<br>Contact Software Support<br>";
}


&html_header();
&show();
&show_inputpage();
&html_footer();

exit;

=head1 HISTORY

Creation Date:      Jul 1, 2007

=head1 AUTHOR

Remo Tilanus, Joint Astronomy Centre E<lt>r.tilanus@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2004 Particle Physics and Astronomy Research Council.
All Rights Reserved.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful,but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc., 59 Temple
Place,Suite 330, Boston, MA  02111-1307, USA

=cut

1;

#---------------------------------------------------------------------------
# Show output or error message

sub show {

  print STDOUT "<P><DIV ALIGN=CENTER>\n<H3>$msg</H3>\n</DIV></P>\n";

  print STDOUT "<P><DIV ALIGN=CENTER>\n";
  print STDOUT "<P><a href=\"javascript:close('self')\">Close Window</a><\P>\n";

  if ($msg =~ /^\w/) {
    print STDOUT "<TABLE WIDTH=100%><TR><TD ALIGN=CENTER>\n";
    print STDOUT "$msg\n";
  }

  if ($rep =~ /^\w/) {
    my @lines = split /\n/,$rep;
    print STDOUT "<PRE>\n";
    foreach $line (@lines) {
      print STDOUT "$line\n";
    }
    if ($#lines < 1) {
      print STDOUT "\n***ERROR*** Unspecified error querying OMP\n\n";
    }
    print STDOUT "</PRE>\n";
    $rep = "";
  }
  print STDOUT "</DIV></P>\n";

  print STDOUT "<BR><P><HR WIDTH=100%></P>\n";
}

#---------------------------------------------------------------------------
sub html_header {

  print STDOUT qq{

\n<BODY BGCOLOR="#FFFFFF" LINK="#FF00FF" VLINK="#FF00FF" ALINK="#FF00FF">\n
\n
};

}

sub html_footer {

  print make_footer( JAC::Web::file_stat($0),
                   contact => {
                               text => 'Remo Tilanus',
                               email => 'r.tilanus@jach.hawaii.edu'
                              }
                 );
}

sub show_inputpage {

  print STDOUT qq {

\n<DIV ALIGN=CENTER>\n
<P>&nbsp;</P>\n
<FONT SIZE="+1" COLOR="blue">\n
Perform a pencil-beam search for targets around a specified position<BR>
or<BR>
around targets from a specified projects.\n
<BR></FONT>\n
\n
<FORM NAME="Ompfindtarget" TARGET="Ompfindtarget" METHOD="post" ACTION="/jac-bin/ompsplot/ompfindtarget.pl">\n
<P>\n
&nbsp;\n
<P>\n
<TABLE>\n

};

# Projid
  print STDOUT qq {
\n<TR><TD ALIGN=RIGHT>Project(s):</TD>\n
<TD><INPUT TYPE="text" NAME="projid" SIZE="16" value=$prj></TD>\n
<TD>(No default)</TD></TR>\n
};

  print STDOUT qq {
\n<TR><TD ALIGN=RIGHT>&nbsp</TD>\n
<TD ALIGN=CENTER>or</TD>\n
<TD>&nbsp;</TD></TR>\n
};

# RA
  print STDOUT qq {
\n<TR><TD ALIGN=RIGHT>RA:</TD>\n
<TD><INPUT TYPE="text" NAME="ra" SIZE="16" value=$rra></TD>\n
<TD>(hh:mm:ss.s No default)</TD></TR>\n
};
# Dec
  print STDOUT qq {
\n<TR><TD ALIGN=RIGHT>Dec:</TD>\n
<TD><INPUT TYPE="text" NAME="dec" SIZE="16" value=$ddec></TD>\n
<TD>(dd:am:as.s No default)</TD></TR>\n
};

  print STDOUT qq {
\n<TR><TD ALIGN=RIGHT>&nbsp</TD>\n
<TD ALIGN=CENTER>&nbsp;</TD>\n
<TD>&nbsp;</TD></TR>\n
};

# Telescope
  print STDOUT qq {\n<TR><TD ALIGN=RIGHT>Telescope:</TD> };
  print STDOUT qq {<TD COLSPAN=2>};
  print STDOUT qq{<INPUT TYPE="radio" name="tel" VALUE="UKIRT" checked> UKIRT};
  print STDOUT qq{<INPUT TYPE="radio" name="tel" VALUE="JCMT"> JCMT};
  print STDOUT qq {</TD></TR>};

# Separation
  print STDOUT qq {
\n<TR><TD ALIGN=RIGHT>Max Separation:</TD>\n
<TD><INPUT TYPE="text" NAME="sep" SIZE="16" value=$ssep></TD>\n
<TD>(600 arcsecs)</TD></TR>\n
};

# Semester
  print STDOUT qq {
\n<TR><TD ALIGN=RIGHT>Semester:</TD>\n
<TD><INPUT TYPE="text" NAME="sem" SIZE="16" value=$ssem></TD>\n
<TD>(${dsem})</TD></TR>\n
};

  print STDOUT qq {
\n</TABLE>\n
<BR>    \n
<INPUT TYPE="submit" VALUE="FIND TARGETS"></TD>\n
\n
</FORM>\n
</DIV>\n
};

  return;
}

#---------------------------------------------------------------------------
# Find current semester

sub find_semester {

  my ($us, $um, $uh, $md, $mo, $yr, $wd, $yd, $isdst) = gmtime(time);
  my $ut = 10000*(1900+$yr)+100*($mo+1)+($md);
  my $year = substr($ut,2,2);
  my $pyear = substr(($ut-10000),2,2);
  my $monthday= substr($ut,4,4);

  my ($sem, $psem);
  if ( $monthday > 201 && $monthday < 802 ) {
      $sem = "${year}a";
      $psem = "${pyear}b";
  } elsif  ( $monthday < 202 ) {
      $sem = "${pyear}b";
      $psem = "${pyear}a";
  } else {
      $sem = "${year}b";
      $psem = "${year}a";
  }

  return($sem, $psem);
}
