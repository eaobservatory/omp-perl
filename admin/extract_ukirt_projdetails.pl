#!perl

# Given a tab delimited file from Janes spreadsheet extract the
# information required to populate the OMP database
#
# Note that as of 03A we change columns:
# Project ID, PI, PI initial, PI email, Support, title, hours, tag priority, 
#  moon, seeing, tau, sky, cois (multiple entries)

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

# Pipe in from standard input

my @proj;
while (<>) {
  next if /^\#/;
  next unless /\w/;
  chomp;

  my $line = $_;

  my @parts = split /\t/,$line;

  # The coi field needs to be converted to an array
  # CoIs are 12..$#parts
  my $coi = [];
  for (my $i = 12; $i<$#parts; $i+=2) {
    if (length($parts[$i]) > 0 && length($parts[$i+1]) > 0) {
      my $surname = $parts[$i+1];
      my $initials = $parts[$i];
      push(@$coi, "$initials $surname");
    }
  }

  # The tau needs to be converted to a range
  my $tau = new OMP::Range( Min => 0 );
  if (exists $taumax{$parts[10]}) {
    $tau->max( $taumax{$parts[10]});
  } else {
    # There is no max
  }

  # The seeing needs to be converted to a range
  my $seeing = new OMP::Range( Min => 0 );
  if (exists $seeing{$parts[9]}) {
    $seeing->max( $seeing{$parts[9]});
  } else {
    # There is no max
  }

  # Also need cloud
  my $cloudtxt = $parts[11];
  $cloudtxt =~ s/\W//g;
  my $cloud;
  if (exists $cloud{$cloudtxt}) {
    $cloud = $cloud{$cloudtxt};
  }

  # Support scientists
  my $ss = $parts[4];
  if (exists $support{$ss}) {
    $ss = $support{$ss};
  } else {
    print "Can not determine support scientist $ss\n";
    exit;
  }

  # The allocation is in nights
  #my $alloc = $parts[7] * HRS_PER_NIGHT;
  my $alloc = $parts[6];

  # The country
  my $country = "UK";
  if ($parts[0] =~ /\/J/i) {
    $country = "JP";
  } elsif ($parts[0] =~ /\/H/i) {
    $country = "UH";
  }

  # Remove any zero padding in the last number
  $parts[0] =~ s/([ABab]\/[JHjh]?)0+/$1/;

  # Remove quotes from title
  $parts[5] =~ s/^\"//;
  $parts[5] =~ s/\"\s*$//;



  # Store in a hash
  push(@proj, {
	       projectid => uc($parts[0]),
	       pi => "$parts[2]. $parts[1]",
	       piemail => $parts[3],
	       coi => $coi,
	       title => $parts[5],
	       support => $ss,
	       tau => $tau,
	       allocation => $alloc,
	       country => $country,
	       seeing => $seeing,
	       moon => $parts[8],
	       cloud => $cloud,
	       tagpriority => $parts[7],
	      });


}

#print Dumper(\@proj);

# Now do consistency check on users
my @allusers;
for my $details (@proj) {

  my $projectid = $details->{projectid};

  my $pi = $details->{pi};

  my @names = ($pi, @{$details->{coi}});

  my $piuser = _generate_user( $pi, $details->{piemail} );

  if ($piuser) {
    $details->{pi} = $piuser;
  } else {
    die "A PI user ID must be generated [$pi for $projectid]\n";
  }

  my @coi;
  for my $name (@{$details->{coi}}) {
    my $user = _generate_user( $name );
    push(@coi, $user) if defined $user;
    print "Can not work with: $name\n" unless defined $user;
  }

  $details->{coi} = \@coi;

  # Store all the user information for later sorting
  push(@allusers, $piuser, @coi);

}

# User verification and write out input file
my @sorted = sort { $a->userid cmp $b->userid } @allusers;
open my $fh, ">newusers.dat" or die "Error opening newusers.dat";

for my $user (@sorted) {
  my $id = $user->userid;
  my $dbuser = OMP::UserServer->getUser( $id );
  #    my $dbuser;
  if (defined $dbuser) {
    no warnings;
    print "User $id in database\n";
    print sprintf("%-15s ",$id)."DB: $dbuser [".$dbuser->email.
      "]:::::: Current: $user [".$user->email."]\n";
  } else {
    no warnings;
    print "User $id [".$user->name."/".$user->email
      ."] not currently in database\n";

    # Write information to file for editing
    print $fh "$id,". $user->name . ",". $user->email . "\n";
  }
}
close $fh or die "Error closing newusers.dat";


# Now create the output file
foreach my $proj (@proj) {

  print "[". uc($proj->{projectid}) ."]\n";
  print "tagpriority=" . (exists $proj->{tagpriority} ? $proj->{tagpriority} : 1) . "\n";

  print "support=" . $proj->{support} . "\n";
  print "pi=" . $proj->{pi}->userid ."\n";
  print "coi=" . join(",",map { $_->userid } @{$proj->{coi}})."\n";
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

# Given a name string and email (optional) return user ID
# Return undef if we can not derive a user ID
sub _generate_user {
  my ($name, $email) = @_;

  my $userid = OMP::User->infer_userid( $name );

  # Trap the obvious ones
  return undef if $name =~ /consortium/i;
  return undef if $name =~ /student/i;


  if (defined $userid) {
#    print "Derived user ID for $name of $userid\n";
  } else {
#    print "Unable to derive user ID from $name\n";
    return undef;
  }

  my $obj = new OMP::User( name => $name, email => $email,
			   userid => $userid,
			 );

  return $obj;
}
