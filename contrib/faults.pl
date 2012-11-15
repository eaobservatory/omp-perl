#!/local/bin/perl
#
# Quick script to download and order the faults in the usual
# opsmeeting format:
#              - All faults between given dates
#              - All faults open from week before
#              - All faults closed during the week
#

use strict;
use Getopt::Long;

BEGIN { $ENV{SYBASE} = "/local/progs/sybase";
        $ENV{OMP_CFG_DIR} = "/jac_sw/omp/msbserver/cfg"
          unless exists $ENV{OMP_CFG_DIR};
        $ENV{PATH} = "/usr/bin:/usr/local/bin:/usr/local/progs/bin:/usr/sbin";
      }

use DBI;
use DBD::Sybase;

use lib "/jac_sw/omp/msbserver";
use OMP::DBbackend;

my $dbs =  new OMP::DBbackend;
my $dbtable = "ompfaultbody,ompfault";


my ($help, $man, $tel, $ut, $days);
my $status = GetOptions("help" => \$help,
                        "man" => \$man,
                        "ut=s" => \$ut,
                        "tel=s" => \$tel,
                        "days=s" => \$days
                       );

# Some help
#
do { &help(); exit; } if ( defined($help) or defined($man) );

# First thing we need to do is determine the telescope and
# the UT date
my $startut;
if ( defined($ut) ) {
  $startut = $ut;
} elsif ( $#ARGV == 0 ) {
  $startut = $ARGV[0];
} else {
    &help();
    die "*Error*: no start ut specified\n\n";
}
chomp($startut);

# Telescope
my $telescope = "JCMT";
if(defined($tel)) {
  $telescope = "JCMT" if ($tel =~ /^J/i);
  $telescope = "UKIRT" if ($tel =~ /^U/i);
}
die "*Error*: telescope must be J(CMT) or U(KIRT). Exiting.\n"
   if ($telescope ne "JCMT" and $telescope ne "UKIRT");

my $delta = 7;
$delta = $days if ( defined($days) );

my @statusname = (
                    "OPEN",
	            "CLOSED",
	            "WORKS FOR ME",
	            "NOT A FAULT",
	            "WON'T BE FIXED",
	            "DUPLICATE",
                    "WILL BE FIXED"
                  );

# Get the connection handle
  my $db = $dbs->handle || do
	   {
             die qq{Error connecting to DB: $DBI::errstr};
           };

print
qq{___________________________________________________________________________


...New faults this week:

};

my $current_ref = $db->selectall_arrayref(
      qq{select
              F.faultid,
              convert(char(5),dateadd(hh,-10,date),8)+'HST',
              substring(subject,1,80),
              author,
              0.01*convert(int,100*timelost),
              status
         from ompfault F, ompfaultbody FB
         where date between "$startut" and
                            dateadd(hh,${delta}*24,"$startut")
         and FB.faultid = F.faultid
         and category='${telescope}' and isfault = 1
         order by substring(subject,1,80),faultid})
   || die qq{Error retrieving from DB: $DBI::errstr};

# order by (-1*timelost)})  === previous sort by timelost

# Group same faults together

my %faults;

my $totallost = 0;

foreach my $row (@$current_ref) {

    my ($faultid, $time, $subject, $author, $timelost, $status) = @$row;

    $subject =~ s/^\s+//;
    $subject = substr($subject,0,55);
    $subject =~ s/\s+$//;

    # Try to omit some variations and anything after a '('
    my $subj = $subject;

    my $index = index( $subj, '(' );
    $subj = substr($subj,0,$index) if ($index > -1);

    $subj =~ s/Errors/Error/i;
    $subj =~ s/Faults/Fault/i;
    $subj =~ s/\s+$//g;

    # Now just get rid of all spaces for key
    $subj =~ s/\s+/\_/g;

    $author = substr($author,0,5) . substr($author,-1,1)
      if ( length($author) > 6 );

    if ( exists $faults{$subj} ) {

      $faults{$subj}{totallost} += $timelost;
      $faults{$subj}{listing} .=
          sprintf "%12.12s %8.8s  %-s\n", $faultid, $time, $subject;
      $faults{$subj}{author} .= ',' . $author
	unless ( $faults{$subj}{author} =~ /$author/i );
      $faults{$subj}{status} = $statusname[$status]
	if ( $statusname[$status] =~ /open/i );


    } else {

      my %ref;
      $ref{totallost} = $timelost;
      $ref{listing} =
          sprintf "%12.12s %8.8s  %-s\n", $faultid, $time, $subject;
      $ref{author} = $author;
      $ref{status} = $statusname[$status];
      $faults{$subj} = \%ref;

    }

}

# Now print everything in from largest time lost
foreach my $subj
  (sort {$faults{"$b"}{totallost} cmp $faults{"$a"}{totallost} }
   keys %faults) {

  printf "%s", $faults{$subj}{listing};
  printf " %-21.21s %4.4s hrs lost %25.25s %s\n\n",
    $faults{$subj}{author}, $faults{$subj}{totallost}, ' ',
      $faults{$subj}{status};
}

print qq{

=========================================================================
                              OBSERVATORY STATUS
=========================================================================

...Last week faults, still OPEN:

};

my $previous_ref = $db->selectall_arrayref(
      qq{select
              F.faultid,
              convert(char(5),dateadd(hh,-10,date),8)+'HST',
              substring(subject,1,80),
              author,
              0.01*convert(int,100*timelost),
              status
         from ompfault F, ompfaultbody FB
         where date between dateadd(hh,-${delta}*24,"$startut")
                        and "$startut"
         and FB.faultid = F.faultid
         and category='${telescope}' and isfault = 1
         and status in (0, 6) order by (-1*timelost)})
   || die qq{Error retrieving from DB: $DBI::errstr};

foreach my $row (@$previous_ref) {
    my ($faultid, $time, $subject, $author, $timelost, $status) = @$row;

    $subject =~ s/^\s+//;
    $subject = substr($subject,0,55);
    $subject =~ s/\s+$//g;

    printf "%12.12s %8.8s  %-s\n %-21.21s %4.4s hrs lost %25.25s %s\n\n",
       $faultid, $time, $subject,
       $author, $timelost, ' ', $statusname[$status];
}

print qq{
...Selected older faults, Fixed/Closed this week:

};

my $previous_ref = $db->selectall_arrayref(
      qq{select
              distinct F.faultid,
              substring(subject,1,80),
              0.01*convert(int,100*timelost),
              status
         from ompfault F, ompfaultbody FB
         where date between "$startut" and
                            dateadd(hh,${delta}*24,"$startut")
         and faultdate < "$startut"
         and FB.faultid = F.faultid
         and status = 1
         and category='${telescope}' order by  F.faultid})
   || die qq{Error retrieving from DB: $DBI::errstr};


foreach my $row (@$previous_ref) {
    my ($faultid, $subject, $timelost, $status) = @$row;

    $subject =~ s/^\s+//;
    $subject = substr($subject,0,55);
    $subject =~ s/\s+$//g;

    printf "%12.12s %8.8s  %-s\n\n",
       $faultid, ' ', $subject;
}



# DISCONNECT FROM DB SERVER
$db->disconnect;

sub help () {

    print "\n";
    print "Use: faults.pl [-tel JCMT|UKIRT] [-days #] yyyymmdd\n";
    print "     faults.pl [-tel JCMT|UKIRT] [-days #] -ut yyyymmdd\n\n";
    print "Defaults are JCMT and periods of 7 days\n\n";

}
