#!/local/perl/bin/perl -w

BEGIN {
  # command line tools probably do not want full logging enabled
  # unless they are asking for it
  $ENV{OMP_LOG_LEVEL} = 'IMPORTANT'
    unless exists $ENV{OMP_LOG_LEVEL};
  $ENV{OMP_CFG_DIR} = "/jac_sw/omp/msbserver/cfg";
}

use strict;

use lib qw(/jac_sw/omp/msbserver);

use Getopt::Long;
use Graphics::PLplot qw(:all);

use OMP::DBbackend;
use OMP::General;
use OMP::NightRep;

my $tel;
my @sems;
my $verbose;
my $help;
my $result = GetOptions("tel=s" => \$tel,
			"sem=s" => \@sems,
			"v" => \$verbose,
		        "h|help" => \$help,);

if (defined $help) {
  print "$0 - Generate statistics based on OMP data\n";
  print "$0 -tel <telescope> -sem <semester1 [semester2...]>\n";
  print "\t-tel - Telescope name\n";
  print "\t-sem - Semester name, or a space-separated list of contiguous semesters\n";
  print "\t-v   - Be verbose\n";
  print "\t-h   - Display this help message\n";
  exit;
}

die ("Please specify -tel and -sem\n")
  unless (defined $tel and defined $sems[0]);

# Get semester boundaries
my ($startdate, $enddate) = OMP::General->semester_boundary(semester=>\@sems, tel=>$tel);

# Create the night report
my $nr = new OMP::NightRep(date => $startdate->ymd,
			   date_end => $enddate->ymd,
			   telescope => $tel,);

print "Retrieving time accounts...\n"
  if ($verbose);
my $acct = $nr->db_accounts;

print "Retrieving faults...\n"
  if ($verbose);
my @fault_acct = $nr->faults->timeacct;
$acct->pushacct(@fault_acct);

print "Generating statistics...\n"
  if ($verbose);
my %coords = $acct->completion_stats();

for my $stat (keys %coords) {
  open DATA, ">", "nr${stat}.dat"
    or die ("Could not create dat file: $!\n");
  print DATA join("\n", map {$_->[0] ." ". $_->[1]} @{$coords{$stat}}) . "\n";
  close DATA;

  # Print name of dat file to STDERR
  print STDERR "Created file nr${stat}.dat\n";
}

# Draw plot
print "Drawing plot...\n"
  if ($verbose);

plsdev( "xwin" );
plinit();
plfont(2);

plcol0(1);
plenv( $coords{science}->[0]->[0], $coords{science}->[-1]->[0], 0, 100, 0, 1);
pllab ("", "", "Completion Statistics");

my $color = 1;
my $texty = 95;
for my $stat (keys %coords) {
  my (@x, @y);
  @x = map {$_->[0]} @{$coords{$stat}};
  @y = map {$_->[1]} @{$coords{$stat}};
  plcol0(++$color);
  plline(\@x, \@y);
  plptex($x[0] + 3, $texty, 0, 0, 0, "$stat");
  $texty -= 5;
}

plend();

print "Done.\n"
  if ($verbose);

