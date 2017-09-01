#!/local/bin/perl
#
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# Non-interactive (command-line) routine to do a pencil-beam search in
# the OMP for targets around a position certain position or around 
# targets from a particular project. Basically a user interface for
# the OMP::FindTarget::find_and_display_targets function.
# This version connects directly to the OMP to retrieve source
# coordinates and should remain access restricted!!!!
#----------------------------------------------------------------------

use FindBin;
use File::Spec;

use constant OMPLIB => "$FindBin::RealBin/..";

BEGIN { $ENV{SYBASE} = "/local/progs/sybase";
        $ENV{OMP_CFG_DIR} = File::Spec->catdir(OMPLIB, "cfg")
          unless exists $ENV{OMP_CFG_DIR};
        $ENV{PATH} = "/usr/bin:/usr/local/bin:/usr/local/progs/bin:/usr/sbin";
      }


use lib OMPLIB;

use strict;

use Getopt::Long;

use OMP::Config;
use OMP::DateTools;
use OMP::FindTarget qw/find_and_display_targets/;

# not 0: debug output
my $debug = 0;

# Authorize access via staff password
my $password = (exists $ENV{'STAFF_PASSWORD'})
             ? $ENV{'STAFF_PASSWORD'} : undef;
unless (defined $password) {
    require Term::ReadLine;
    my $term = new Term::ReadLine 'Find OMP targets';

    # Needs Term::ReadLine::Gnu
    my $attribs = $term->Attribs;
    $attribs->{redisplay_function} = $attribs->{shadow_redisplay};
    $password = $term->readline( "Please enter staff password: ");
    $attribs->{redisplay_function} = $attribs->{rl_redisplay};
}

OMP::Password->verify_staff_password($password);

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
my $sem = OMP::DateTools->determine_semester(tel => $tel);

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
