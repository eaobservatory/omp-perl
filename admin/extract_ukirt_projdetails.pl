#!perl

# Given a tab delimited file from Janes spreadsheet extract the
# information required to populate the OMP database
#

# As of 04A columns are now:
#  Project ID, PI name, PI email, PI userid, Support ID, Support2 ID, Title, Hours,
#    tag priority, moon, seeing, tau, sky, cois
#
# but note that tau is different - it's a number

# As of 03B columns are now:
# Project ID, PI userid, Support, Title, hours, tag priority, moon, seeing
#  tau, sky, cois (multiple entries as user ids)

# Problem with 03A output is that CoIs are "I\tSurname\tI\tSurname !


# Hash is comment
use strict;
use warnings;
use Data::Dumper;
use OMP::Range;
use OMP::User;

# Tau ranges
my %taumax = ( dry => 0.09, any => undef);

# Number of hours in a night
use constant HRS_PER_NIGHT => 13.0;

# Support scientists
my %support = (thk => 'TKERR',
	       skl => 'SKL',
	       mss => 'MSEIGAR',
	       ms => 'MSEIGAR',
	       jvb => 'JBUCKLE',
	       cjd => 'CDAVIS',
	       ph  => 'PHIRST',
	       aja => 'ADAMSON',
	      );

my %seeing = (
	      "<0.6 arcseconds" => 0.6,
	      "<0.8 arcseconds" => 0.8,
	      "<0.4 arcseconds" => 0.4,
	      any => undef,
	     );

my %cloud = (
	     thin => 1,
	     photo => 0,
	    );

# Index into array
use constant PROJECTID => 0;
use constant PI => 3;
use constant SA => 4;
use constant SA2 => 5;
use constant TITLE => 6;
use constant HOURS => 7;
use constant TAGPRI => 8;
use constant MOON => 9;
use constant SEEING => 10;
use constant TAU => 11;
use constant CLOUD => 12;
use constant COI => 13;

# Pipe in from standard input

my @proj;
while (<>) {
  next if /^\#/;
  next unless /\w/;
  chomp;

  my $line = $_;

  my @parts = split /\t/,$line;

  # The coi field needs to be converted to an array
  # CoIs are 13..$#parts and now use user ids
  my $coi = [grep /\w/, @parts[COI..$#parts]];

  # The tau needs to be converted to a range
  my $tau = new OMP::Range( Min => 0 );
  if (exists $taumax{$parts[TAU]}) {
    $tau->max( $taumax{$parts[TAU]});
  } else {
    # There is no default max but there may be embedded value
    if ($parts[TAU] =~ /^tau\s*<\s*(.*)/) {
      $tau->max( $1 );
    }
  }

  # The seeing needs to be converted to a range
  my $seeing = new OMP::Range( Min => 0 );
  if (exists $seeing{$parts[SEEING]}) {
    $seeing->max( $seeing{$parts[SEEING]});
  } else {
    # There is no max
  }

  # Also need cloud
  my $cloudtxt = $parts[CLOUD];
  $cloudtxt =~ s/\W//g;
  my $cloud;
  if (exists $cloud{$cloudtxt}) {
    $cloud = $cloud{$cloudtxt};
  }

  # Support scientists
  my @support;
  for (SA,SA2) {
    my $ss = $parts[$_];
    if (exists $support{$ss}) {
      push(@support,$support{$ss});
    } else {
      print "Can not determine support scientist $ss\n";
      exit;
    }
  }

  # Support 2

  # The allocation is in hours
  my $alloc = $parts[HOURS];

  # The country
  my $country = "UK";
  if ($parts[PROJECTID] =~ /\/J/i) {
    $country = "JP";
  } elsif ($parts[PROJECTID] =~ /\/H/i) {
    $country = "UH";
  }

  # Remove any zero padding in the last number
  $parts[PROJECTID] =~ s/([ABab]\/[JHjh]?)0+/$1/;

  # Remove quotes from title
  $parts[TITLE] =~ s/^\"//;
  $parts[TITLE] =~ s/\"\s*$//;



  # Store in a hash
  push(@proj, {
	       projectid => uc($parts[PROJECTID]),
	       pi => $parts[PI],
	       coi => $coi,
	       title => $parts[TITLE],
	       support => \@support,
	       tau => $tau,
	       allocation => $alloc,
	       country => $country,
	       seeing => $seeing,
	       moon => $parts[MOON],
	       cloud => $cloud,
	       tagpriority => $parts[TAGPRI],
	      });


}

# Now create the output file
foreach my $proj (@proj) {

  print "[". uc($proj->{projectid}) ."]\n";
  print "tagpriority=" . (exists $proj->{tagpriority} ? $proj->{tagpriority} : 1) . "\n";

  print "support=" . join(",", @{$proj->{support}}) . "\n";
  print "pi=" . uc($proj->{pi}) ."\n";
  print "coi=" . join(",", map { uc($_) } @{$proj->{coi}})."\n";
  print "title=".$proj->{title}."\n";
  print "allocation=" . $proj->{allocation}."\n";
  print "country=" . $proj->{country}."\n";

  # only put in a tau if we need a tau
  my $taumax = $proj->{tau}->max;
  if (defined $taumax) {
    print "taurange=0,$taumax\n";
  }

  # And seeing
  my $seemax = $proj->{seeing}->max;
  if (defined $seemax) {
    print "seeing=0,$seemax\n";
  }

  # And cloud
  if (defined $proj->{cloud}) {
    print "cloud=".$proj->{cloud}."\n";
  }

  print "\n";
}



exit;

