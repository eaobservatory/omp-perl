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


use lib "/jac_sw/omp/msbserver";

use strict;

use Getopt::Long;

use OMP::Config;
use OMP::FindTarget qw/find_and_display_targets/;

OMP::Config->cfgdir( "/jac_sw/omp/msbserver/cfg");

# not 0: debug output
my $debug = 0;

# This routine can be used to mine coordinates in the OMP. 
# Hence: only continue if permission for world is 'no access'
# group is 'staff'.

my ($dev,$ino,$fmode,$nlink,$uid,$gid,$rdev,$size,
       $atime,$mtime,$ctime,$blksize,$blocks)
           = stat($0);
my $mode = sprintf "%04o", $fmode & 07777;
my $world = substr $mode, (length $mode)-1, 1;

print "World: $world  Group: $gid\n" if ($debug);

($world == 0 && $gid == 10) ||
  die qq { 
-------------------------------------------------------------- 
	Error:       ompfindtarget can only be used by 'staff'
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
  $proj = uc $1;
  $proj =~ s/\*/\&/g;
} elsif ( defined $prj ) {
  die qq {
--------------------------------------------------------------
 Error:       Invalid value for project: '$prj'.
--------------------------------------------------------------
};
}
print "Projectid: $proj\n" if ($debug);

my $ra = "";
my $dec = "";
if ($proj eq "" && (defined $rra || defined $ddec)) {
  if ($rra =~ /^([\d\:\.\ ]+)$/) {
    $ra = $1;
  }
  else {
    die qq {
--------------------------------------------------------------
 Error:       Invalid format for ra: '$rra'
--------------------------------------------------------------
};
  }

  if ($ddec =~ /^([\d\-\:\.\ ]+)$/ ) {
    $dec = $1;
  }
  else {
    die qq {
--------------------------------------------------------------
 Error:       Invalid format for dec: '$ddec'
--------------------------------------------------------------
};
  }

  $ra  .= ' 00' if (length $ra < 7);
  $dec .= ' 00' if (length $dec < 7);
  $ra  .= ' 00' if (length $ra < 7);
  $dec .= ' 00' if (length $dec < 7);
  $ra  =~ s/\:/\ /g;
  $dec =~ s/\:/\ /g;
}

print "RA Dec: $ra / $dec\n" if ($debug);

# Separation:
my $sep = 600;
if ( $ssep =~ /^(\d+)$/ ) {
  $sep = $1;
} elsif ( defined $ssep ) {
  die qq {
--------------------------------------------------------------
 Error:       Invalid value for separation: '$ssep'.
--------------------------------------------------------------
};
}
print "Separation: $sep arcsecs\n" if ($debug);

# Telescope:
my $tel = "UKIRT";
if ( $ttel =~ /^u/i ) {
  # Is default: do nothing.
} elsif ( $ttel =~ /^j/i ) {
  $tel = "JCMT";
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
my ($sem, $psem) = find_semester();

if ( $ssem =~ /^([\d\*\&]+[AB])$/i ) {
  $sem = uc $1;
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

unless ( ($ra ne "" && $dec ne "")  || $proj ne "" ) {
  die qq {
--------------------------------------------------------------
 Error:       You must specify ra \& dec or a science program.
              Type '$program -help' for additional info.
--------------------------------------------------------------
};
}

find_and_display_targets(
    proj  => $proj,
    ra    => $ra,
    dec   => $dec,
    sep   => $sep,
    tel   => $tel,
    sem   => $sem,
);

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

  return($sem, $psem);
}
