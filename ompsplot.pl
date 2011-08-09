#!/local/bin/perl -TXs

# Warnings are disabled

=head1 NAME

ompsplot - Plot source Elevation versus Time for JCMT/UKIRT for objxects
           associated with projects in the OMP DB.

=head1 DESCRIPTION

PERL wrapper to generate a GIF 'sourceplot' for all objects of a
particular project in the OMP DB.  The actual plotting is
done by the non-interactive routine 'ompsplot.pl'.

=cut

#use CGI qw/ -debug /;
use CGI;
use CGI::Carp qw/ fatalsToBrowser /;
#use File::Copy;
use File::Find;
use JAC::Web;

# Start CGI environment
$query = new CGI;

print $query->header;

print STDOUT make_header( title => 'JAC OMP SOURCEPLOT ',
                          "JAC Software" => "/software/" );

# Directory where plots and temp files will be created
$wwwroot = "/web/html";
$workdir = "/tmp/sourceplot";

# Work out semester
my ($sem,$psem) = &find_semester();

# Calls non-interactive routine to do the job
$command = "/web/jac-bin/ompsplot/scgiplot";

# Make world readable and initialize variables
umask('002');
$msg = "";       # Message buffer which will be printed by show()
$gif = "";       # Name of Gif file produced (if any)

# Change to WORKDIR
chdir "${wwwroot}${workdir}" or do 
    { $msg .= "***ERROR*** Can't cd to '${wwwroot}${workdir}'<br>"; &show() ; exit ; };

# Make sure grfont.dat in place
#copy ("${grfont}", "grfont.dat") unless (-e "${grfont}");

# ----------------------------------------------------------------------
# Parse the command line options

# defaults

$projid = "";
$utdate = "";
$object = "";
$mode   = "";
$ptype  = "";
$agrid  = "";
$tzone  = "";
$labpos = "";

# if we were not called with arguments, create the input page
if (!$query->param) {
  &html_header();
  &show_inputpage();
  &html_footer();
  exit;
}

$proj = $query->param('projid');
$proj =~ /^([\w\/\$\.\_\@]+)$/ && ($projid = $1) || (do {
       $projid = "";
       $msg .= "***ERROR*** must specify a project!<br>";
    } );

$utd = $query->param('utdate');
$utd =~ /^(\d{8})$/ && ($utdate = $1) || (do {
       $utdate = "";
       if ($utd ne "") {
	 $msg .= "***ERROR*** date format: '$utd' incorrect (YYYYMMDD)!<br>";
       }
    } );

$objs = $query->param('object');
$objs =~ /^([\w\/\$\.\_\@\"\'\s]+)$/ && ($object = $1) || ($object = "");

$mod = $query->param('mode');
$mod =~ /^([\w\+\-\.\_]+)$/ && ($mode = $1) || ($mode = "");
$mode =~ s/\'//g;
$mode =~ s/\ /\\\+/g;

$ptyp = $query->param('ptype');
$ptyp =~ /^([\w\+\-\.\_]+)$/ && ($ptype = $1) || ($ptype = "");
$ptype =~ s/\'//g;
$ptype =~ s/\ /\\\+/g;

$air = $query->param('agrid');
$air =~ /^([\w\+\-\.\_]+)$/ && ($agrid = $1) || ($agrid ="");
$agrid =~ s/\'//g;
$agrid =~ s/\ /\\\+/g;

$tzon = $query->param('tzone');
$tzon =~ /^([\w\+\-\.\_]+)$/ && ($tzone = $1) || ($tzone = "");
$tzone =~ s/\'//g;
$tzone =~ s/\ /\\\+/g;

$lpos = $query->param('label');
$lpos =~ /^([\w\+\-\.\_]+)$/ && ($labpos = $1) || ($labpos = "");
$labpos =~ s/\'//g;
$labpos =~ s/\ /\\\+/g;

($v) && do {
   $msg .= "Sourcegraph version 1.0 -- Author: Remo Tilanus,<br>"; 
   $msg .= "Joint Astronomy Centre, Hilo, Hawaii.<br>";
};

(($h) || $msg =~ /^\w+$/) && do {
   $msg .= "<br>Ompsplot -- produce GIF Time-EL plot of objects\n";
   $msg .= " from a science project in the OMP DB.<br><br>";
   $msg .= "Use: ompsplot [projid] [utdate] [mode] [air]<br><br>";
   $msg .= "<ul><li>projid: \tproject ID as listen in comment field of catalog.</li>";
   $msg .= "<li>utdate:\tUTdate to plot for (YYYYMMDD) [today].</li>";
   $msg .= "<li>source:\tSource to plot [All].</li>";
   $msg .= "<li>mode:\taccess Active/Completed/[All] MSBs.</li></ul>";
   $msg .= "<li>agrid:\tGrid-lines at airmass instead EL</li></ul>";
   $msg .= "Submitted parameters: '$projid' '$utdate' '$mode' '$agrid'<br><br>";
   $msg .= "<p>";
};


if ($msg =~ /^\*/) {
   &html_header();
   &show();
   &html_footer();
   exit;
};

# ----------------------------------------------------------------------
# Open catalog and extract object from project to temporary catalog

# Option to specify source not implemented yet.
#$object = 'N7538 IRS1';
#if ($object eq "") {
  $gif = "${projid}.gif";
#} else {
#  $obj = (split(/\s+/,$object))[0];
#  $gif = "${projid}_${obj}.gif";
#}
$gif =~ s/\///g;

if (-e "$command") {
  $utopt = "";
  $utopt = "-ut ${utdate}" if (defined $utdate && $utdate ne "");
  $objopt = "";
  $objopt = "-obj '${object}'" if (defined $object && $object ne "");
  $options = "";
  $options .= "-mode ${mode} "     if (defined $mode && $mode ne "");
  $options .= "-ptype ${ptype} "  if (defined $ptype && $ptype ne "");
#  $options .= "-tzone ${tzone} "  if (defined $tzone && $tzone ne "");
  $options .= "-agrid ${agrid} "  if (defined $agrid && $agrid ne "");
  $options .= "-label ${labpos} " if (defined $labpos && $labpos ne "");

  # Make plot
  my $cmd_line = "${projid} ${objopt} ${utopt} ${options} -out gif";
  my $command_line;
  # Untaint command-line
  ($cmd_line =~ /^([\w\d\@\=\_\-\ \/\'\"\*]+)$/) && 
               ($command_line = "$1") || ($command_line = "");
  $ENV{"PATH"} = "";
  $rep = "";
  $rep = `${command} ${command_line}`;

  # Rename gif to be unique name
  if (-e "${gif}") {
    my ($sec,$min,$hour,$rest) =
       localtime time;
    $sec =~ s/\.//g;
    my $ori_gif = "${gif}";
    $gif =~ s/\./\_${hour}${min}${sec}\./;
    unlink "${gif}" if (-e "${gif}");
    rename "${ori_gif}", "${gif}";
  } else {
    $rep = "Likely the science program does not exist in the OMP." 
         if ($rep == "");
    $msg .= "***ERROR*** failed to create plot:<br>'$gif'<br>'${rep}'<br>";
    $gif = "";
  }
} else {
  $msg .= "***ERROR**** failed to find '$command'<br>Contact Software Support<br>";
}

# Clean-up
system('find \. -name \*.gif -mtime \+3 -exec /bin/rm -f {} \;');

&html_header();
&show();
&show_inputpage();
&html_footer();

exit;

=head1 HISTORY

Creation Date:      Aug 28, 2000

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
# Show plot or error message

sub show {

  print STDOUT "<P><DIV ALIGN=CENTER>\n<H3>$msg</H3>\n</DIV></P>\n";

  print STDOUT "<P><DIV ALIGN=CENTER>\n";
  print STDOUT "<P><a href=\"javascript:close('self')\">Close Window</a><\P>\n";

  if ($gif =~ /\w/) {
    print STDOUT "<TABLE WIDTH=100%><TR><TD ALIGN=CENTER>\n";
    print STDOUT "<H2>${projid}:</H2></TD></TR>\n";
    print STDOUT "<TR><TD ALIGN=LEFT>\n";
    print STDOUT "<a href=\"${workdir}/${gif}\"><IMG ALIGN=left ALT=\"Ompsplot\" SRC=\"${workdir}/${gif}\"></a>\n";
    print STDOUT "</TD></TR></TABLE>\n";
  }

  print STDOUT "</DIV></P>\n";

  print STDOUT "<BR><P><HR WIDTH=100%></P>\n";
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
      $sem = "m${year}a";
      $psem = "m${pyear}b";
  } elsif  ( $monthday < 202 ) {
      $sem = "m${pyear}b";
      $psem = "m${pyear}a";
  } else {
      $sem = "m${year}b";
      $psem = "m${year}a";
  }

  return($sem, $psem);
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

  @modes = ( "All", "Active", "Completed" );

  @ptypes = ( "TIMEEL", "AZEL", "TIMEAZ", "TIMEPA", "TIMENA" );
  @plabel = ( "Time_EL", "AZ_EL", "Time_AZ", "Time_PA", "Time_NA" );

  @grids  = ( "EL grid", "Airmass grid");

  @lposs  = ( "curve", "list" );
  @ltext  = ( "Along track", "List on side");

  print STDOUT qq {

\n<DIV ALIGN=CENTER>\n
<P>&nbsp;</P>
<FONT SIZE="+1" COLOR="blue">Plot sources from an OMP project:<BR></FONT>\n
\n
<FORM NAME="Ompsplot" TARGET="Ompsplot" METHOD="post" ACTION="/jac-bin/ompsplot/ompsplot.pl">\n
<P>\n
&nbsp;\n
<P>\n
<TABLE>\n

  };

# Utdate
  print STDOUT qq {
\n<TR><TD ALIGN=RIGHT>UTdate:<BR>(YYYYMMDD)</TD>\n
<TD><INPUT TYPE="text" NAME="utdate" SIZE="16" value=$utdate></TD>\n
<TD>[today]</TD></TR>\n
  };

# Projid
  print STDOUT qq {
\n<TR><TD ALIGN=RIGHT>Project(s):</TD>\n
<TD><INPUT TYPE="text" NAME="projid" SIZE="16" value=$projid></TD>\n
<TD>One or more separated by '\@'</TD></TR>\n
  };

# Objects
  print STDOUT qq {
\n<TR><TD ALIGN=RIGHT>Object(s):</TD>\n
<TD><INPUT TYPE="text" NAME="object" SIZE="16" value=$object></TD>\n
<TD>(Optional) One or more separated by '\@'.<br>Any planets in this list will always be plotted<br>and not matched against project sources.</td></tr>\n
<tr><td colspan=3>'5planets' will plot mars thru neptune; 'planets' will plot all 9;<br>'solar' will add the Sun and Moon.</TD></TR>\n
  };

# Plot options section
  print STDOUT qq {
\n<TR><TD>&nbsp;</TD></TR>\n
<TR><TD>PLOT OPTIONS:</TD></TR>\n
<TR><TD ALIGN=RIGHT>Source mode:</TD>\n
<TD COLSPAN=2 ALIGN=LEFT>
  };

# MSB mode
  foreach $mod (@modes) {
    $checked = "";
    if (($mode eq "" && $mod =~ /^ac/i) ||
        ($mode =~ /$mod/i)) {
      $checked = "checked";
    }
    print STDOUT qq{ <input type="radio" name="mode" value="$mod" $checked> $mod &nbsp; };
  }

  print STDOUT qq{ </TD></TR>\n };

# Plot type
  print STDOUT qq { 
\n<TR><TD ALIGN=RIGHT>Plot type:</TD>\n
<TD><SELECT NAME="ptype">\n
  };
  for ($i = 0; $i <= $#ptypes; $i++) {
    $ptyp = $ptypes[$i];
    $plab = $plabel[$i];
    $selected = "";
    if (($ptype eq "" && $ptyp =~ /^TIMEEL/i) ||
        ($ptype =~ /$ptyp/i)) {
      $selected = 'SELECTED="selected"';
    }
    print STDOUT qq{ <OPTION $selected VALUE="$ptyp">$plab</OPTION>\n };
  }
  print STDOUT qq{ </SELECT></TD></TR> };

# Airmass grid
  print STDOUT qq { <TR><TD ALIGN=RIGHT>Grid:</TD> };
  for ($i = 0; $i <= $#grids; $i++) {
    $grid = $grids[$i];
    $checked = "";
    if (($agrid eq "" && $i == 0) ||
        ($i == $agrid)) {
      $checked = "checked";
    }
    print STDOUT qq {
<TD><INPUT TYPE="radio" name="agrid" VALUE="$i" $checked> $grid </TD>
    };
  }
  print STDOUT qq { </TD></TR> };

# Label position
  print STDOUT qq {\n<TR><TD ALIGN=RIGHT>Label position:</TD> };
  for ($i = 0; $i <= $#lposs; $i++) {
    $lpos = $lposs[$i];
    $ltxt = $ltext[$i];
    $checked = "";
    if (($labpos eq "" && $lpos =~ /^cu/i) ||
        ($labpos =~ /$lpos/i)) {
      $checked = "checked";
    }
    print STDOUT qq{ <TD><INPUT TYPE="radio" name="label" VALUE=${lpos} $checked> $ltxt </TD> };
  }
  print STDOUT qq { </TR> };

# Time-Zone
#  print STDOUT qq {
#\n<TR><TD ALIGN=RIGHT>Time Zone:</TD>\n
#<TD><SELECT NAME="tzone">\n
#  };
#
#  for ($i = -11; $i <= 12; $i++) {
#    $selected = "";
#    if (($tzone eq "" && $i == 10) ||
#        ($tzone == $i)) {
#      $selected = 'SELECTED="selected"';
#    }
#    print STDOUT qq { <OPTION $selected VALUE="${i}">${i}</OPTION>\n };
#  }
#
#  print STDOUT qq { 
#</SELECT></TD>
#<TD>(Default: 10 = Hawaii)</TD></TR>
#\n
#  };

  print STDOUT qq {
\n</TABLE>\n
<BR>    \n
<INPUT TYPE="submit" VALUE="PLOT SOURCES"></TD>\n
\n
</FORM>\n
</DIV>\n
  };

  return;
}
