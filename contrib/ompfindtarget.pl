#!/local/bin/perl
#
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# Non-interactive (command-line) routine to do a pencil-beam search in
# the OMP for targets around a position certain position or around 
# targets from a particular project. Basically a user interface for
# the ompfindtarget stored procedure in the DB.
# This version connects directly to the OMP to retrieve source
# coordinates and should remain access restricted!!!!
#----------------------------------------------------------------------


BEGIN { $ENV{SYBASE} = "/local/progs/sybase";
        $ENV{OMP_CFG_DIR} = "/jac_sw/omp/msbserver/cfg"
          unless exists $ENV{OMP_CFG_DIR};
        $ENV{PATH} = "/usr/bin:/usr/local/bin:/usr/local/progs/bin:/usr/sbin";
      }

use DBI;
use DBD::Sybase;

use lib "/jac_sw/omp/msbserver";
use OMP::DBbackend;
use Astro::SLA;

use strict;
use Getopt::Long;
use Math::Trig;

OMP::Config->cfgdir( "/jac_sw/omp/msbserver/cfg");

# not 0: debug output
my $debug = 0;

# This routine can be used to mine coordinates in the OMP. 
# Hence: only continue if permission for world is 'no access'
# group is 'staff' or user is 'http*' (assuming that htpasswd
# will be used to regulate access though a cgi script.)

my $user = $ENV{'USER'};

my ($dev,$ino,$fmode,$nlink,$uid,$gid,$rdev,$size,
       $atime,$mtime,$ctime,$blksize,$blocks)
           = stat($0);
my $mode = sprintf "%04o", $fmode & 07777;
my $world = substr $mode, (length $mode)-1, 1;

print "User: $user  World: $world  Group: $gid\n" if ($debug);

( ($user =~ /^http/) || ($world == 0 && $gid == 10)) ||
  die qq { 
-------------------------------------------------------------- 
	Error:       ompfindtarget can only be used by 'staff'
                     or through password protected http access. 
-------------------------------------------------------------- 
}; 

# Program name
my $program = ( split( /\//, $0 ) )[-1];

#----------------------------------------------------------------------
# Get command-line parameters.

my $cmd_line = join(' ', @ARGV);

my ($help, $rra, $ddec, $ssep, $prj, $ttel, $ssem, $dbug);
my $status = GetOptions("help"   => \$help,
                        "ra=s"   => \$rra,
                        "dec=s"  => \$ddec,
                        "proj=s" => \$prj,
                        "sep=s"  => \$ssep,
                        "tel=s"  => \$ttel,
                        "sem=s"  => \$ssem,
                        "debug"  => \$dbug
                       );

if (defined($dbug)) {
  print "DEBUG output on\n";
  $debug = 1;
}

if (defined($help)) {
  print qq {
-------------------------------------------------------------------------
 This routine performs a pencil-beam search for targets around a specfied
 specified position or around targets from a specified projects.

 Use: $program [-ra ra -dec dec | -proj projid] [-sep separation] 
               [-tel telescope] [-sem semester]

\t\t-ra  \tRight Ascension in J2000. (No default)
\t\t-dec \tDeclination in J2000. (No default)
\t\t-proj\tProject to select reference targets from. (No default)
\t\t     \tEither specify a RA and Dec or specify a project;
\t\t     \tIf a project is specified, RA and Dec are ignored.
\t\t-sep \tRadius in arcsecs for search beam. (Default 600).
\t\t-sem \tSemester [ 07A | ... | all ]. (Default: current). 
\t\t-tel \tTelescope name: [ UKIRT | JCMT | all ]. (Default: UKIRT).
\t\t-help\tThis help
\t\t-debug\tSwitch on some debug output

 All switches can be abbreviated.

 Examples:
 \t ${program} -ra '09:27:46.7' -dec '-06:04:16' -sep 60 -tel UKIRT
 \t ${program} -proj U/07A/3 -sep 60 -tel UKIRT
---------------------------------------------------------------------------

};
  exit;
};

# Make all parameters trusted

# Ra, Dec, Project:
my $proj = "";
if ( $prj =~ /^([\w\/\*]+)$/ ) {
  $prj = uc $prj;
  $proj = "\@proj='$prj'";
} elsif ( defined $prj ) {
  die qq {
--------------------------------------------------------------
 Error:       Invalid value for project: '$prj'.
--------------------------------------------------------------
};
}
$proj =~ s/\*/\&/g;
print "Projectid: $proj\n" if ($debug);

my $radec = "";
if ($proj eq "" && $rra =~ /^([\d\:\.\ ]+)$/ && $ddec =~ /^([\d\-\:\.\ ]+)$/ ) {
  $rra  .= ' 00' if (length $rra < 7);
  $ddec .= ' 00' if (length $ddec < 7);
  $rra  .= ' 00' if (length $rra < 7);
  $ddec .= ' 00' if (length $ddec < 7);
  $radec = "\@ra='$rra',\@dec='$ddec'";
  $radec =~ s/\:/\ /g;
} elsif ( $proj eq "" && (defined $rra || defined $ddec) ) {
  die qq {
--------------------------------------------------------------
 Error:       Invalid format for ra and/or dec:\t '$rra' '$ddec'
--------------------------------------------------------------
};
}
print "RA Dec: $radec\n" if ($debug);

# Separation:
my $dsep = 600;
my $sep = "\@sep=${dsep}";
if ( $ssep =~ /^(\d+)$/ ) {
  $sep = "\@sep=$ssep";
  $dsep = $ssep;
} elsif ( defined $ssep ) {
  die qq {
--------------------------------------------------------------
 Error:       Invalid value for separation: '$ssep'.
--------------------------------------------------------------
};
}
print "Separation: $sep arcsecs\n" if ($debug);

# Telescope:
my $tel = "\@tel='UKIRT'";
if ( $ttel =~ /^[u,j]/i ) {
  $ttel = uc $ttel;
  $tel = "\@tel='$ttel'";
} elsif ( $ttel =~ /^a/i ) {
  $tel = "";                    # Wildcard is default 
} elsif ( defined $ttel ) {
  die qq {
--------------------------------------------------------------
 Error:       Telescope must be: u[kirt] | j[cmt | a[ll].
--------------------------------------------------------------
};
}
print "Telescope: $tel\n" if ($debug);

# Semester:
my ($sem, $psem) = &find_semester();

if ( $ssem =~ /^([\d\*\&])+[AB]$/i ) {
  $ssem = uc $ssem;
  $sem = "\@sem='$ssem'";
} elsif ( $ssem =~ /^a/i ) {
  $sem = "";                     # Empty string defaults to all
} elsif ( defined $ssem ) {
  die qq {
--------------------------------------------------------------
 Error:       Invalid format for semester: '$ssem'.
--------------------------------------------------------------
};
}
$sem =~ s/\*/\&/g;
print "Semester: $sem\n" if ($debug);

unless ( $radec ne "" || $proj ne "" ) {
  die qq {
--------------------------------------------------------------
 Error:       You must specify ra \& dec or a science program.
              Type '$program -help' for additional info.
--------------------------------------------------------------
};
}

my $sqlcmd = "ompfindtarget ${proj}${radec},${sep},${tel},${sem}";
$sqlcmd =~ s/(\,)+/\,/g;
$sqlcmd =~ s/\,$//;
print "$sqlcmd\n";

#----------------------------------------------------------------------
# Get the connection handle

my $dbs =  new OMP::DBbackend;
my $dbtable = "ompproj";

my $db = $dbs->handle || die qq {
--------------------------------------------------------------
 Error:       Connecting to Db: $DBI::errstr
--------------------------------------------------------------
};

my $row_ref = $db->selectall_arrayref( qq{exec $sqlcmd}) || die qq {
--------------------------------------------------------------
 Error:       Executing DB procedure: $DBI::errstr
--------------------------------------------------------------
};

# Disconnect from DB server
$db->disconnect;

# Print output
$ssep = "default" if (not defined $sep);
my ($hh, $mm, $ss, $sss, $sign, $dd, $am, $as, $ass );
my $pi = 4.0*atan(1.0);

print "----------------------------------------------------------------------------\n";
if ($#$row_ref < 0 ) {
  print "No targets within $dsep arcsecs from reference.\n";
} else {

  my $n = 0;
  my $pref = "";
  foreach my $row (@$row_ref) {
    $n++;

    my ($ref, $proj, $target, $sep, $ra, $dec, $instr) = @$row;

    my (@hh, @dd, $sign);
    if ($n == 1 || $ref ne $pref ) {
      if ($ref =~ /^\d/) {
        my ($ra_r, $dec_r) = split /\s+/, $ref;
        slaDr2tf (2, $ra_r,  $sign, @hh);
        slaDr2af (2, $dec_r, $sign, @dd);
        $ref = sprintf "%2.2d %2.2d %2.2d.%2.2d %1.1s%2.2d %2.2d %2.2d.%2.2d",
                     $hh[0], $hh[1], $hh[2], $hh[3],
                     $sign, $dd[0], $dd[1], $dd[2], $dd[3];
      }
      print "Targets within $dsep arcsecs from  ${ref}:\n";
      $pref = $ref;
    }

    slaDr2tf (2, $ra,  $sign, @hh);
    slaDr2af (2, $dec, $sign, @dd);

    printf qq{%-12s %12s %8d"  %2.2d %2.2d %2.2d.%2.2d %1.1s%2.2d %2.2d %2.2d.%2.2d %8s\n},
      $proj, $target, int($sep+0.5), $hh[0], $hh[1], $hh[2], $hh[3], 
                     $sign, $dd[0], $dd[1], $dd[2], $dd[3], $instr;
  }
}
print "----------------------------------------------------------------------------\n";

sub find_semester {

  my ($us, $um, $uh, $md, $mo, $yr, $wd, $yd, $isdst) = gmtime(time);
  my $ut = 10000*(1900+$yr)+100*($mo+1)+($md);
  my $year = substr($ut,2,2);
  my $pyear = substr(($ut-10000),2,2);
  my $monthday= substr($ut,4,4);

  my ($sem, $psem);
  if ( $monthday > 201 && $monthday < 802 ) {
      $sem = "${year}A";
      $psem = "${pyear}B";
    } elsif  ( $monthday < 202 ) {
      $sem = "${pyear}B";
      $psem = "${pyear}A";
    } else {
      $sem = "${year}B";
      $psem = "${year}A";
  }

  $sem = "\@sem='$sem'";
  $psem = "\@psem='$psem'";
  return($sem, $psem);
}
