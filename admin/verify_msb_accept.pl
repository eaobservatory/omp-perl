#!/local/perl-5.6/bin/perl

use strict;
use lib qw|/jac_sw/omp/msbserver|;
BEGIN { $ENV{OMP_CFG_DIR} = "/jac_sw/omp/msbserver/cfg"; };
use OMP::Info::ObsGroup;
use OMP::MSBServer;
use OMP::ProjServer;
use Data::Dumper;

my $refdate = '2003-06-13';
my $tel = 'UKIRT';

# What does the done table say?
my $output = OMP::MSBServer->observedMSBs( {
					    date => $refdate,
					    returnall => 0,
					    format => 'object',
					   });

# Need to convert the OMP::Info::MSB with comments to a time
# series. [yes this was how they were stored originally]
my @msbs;
for my $msb (@$output) {
  next unless OMP::ProjServer->verifyTelescope( $msb->projectid, $tel);
  for my $c ($msb->comments) {
    my $newmsb = $msb->new( checksum => $msb->checksum,
			    projectid => $msb->projectid,
			  );
    $newmsb->comments( $c );

    push(@msbs, $newmsb);

  }
}

my @sorted_msbdb = sort { $a->comments->[0]->date->epoch <=> $b->comments->[0]->date->epoch} @msbs;

print "---> MSB activity ----\n";
for my $msb (@sorted_msbdb) {
  print "[".$msb->projectid."] ".$msb->checksum . " -> ". 
    $msb->comments->[0]->date->datetime. 
      " [".(defined $msb->comments->[0]->author ? 
	    $msb->comments->[0]->author->userid : 'UNKNOWN')."/".
	$msb->comments->[0]->status 
	  ."/". $msb->comments->[0]->text
	    ."]\n";
}


# Look at the real data:
print "---> Data headers ----\n";
my $grp = new OMP::Info::ObsGroup( telescope => $tel,
				   date => $refdate,
				 );

# Go through looking for MSBs
my @sorted_msbhdr;
my $previd = '';
my $prevdate = 0;
my $prevtime;
my $prevproj = '';
for my $obs (sort { $a->startobs->epoch <=> $b->startobs->epoch} $grp->obs) {
  my $fits = $obs->fits;
  my $msbid = $fits->itembyname('MSBID')->value;
  my $project = $obs->projectid;
  my $end = $obs->endobs->datetime;

  if ($previd ne $msbid) {
    # New MSB, dump the previous one
    if ($previd && $previd ne 'CAL') {
      print "[$prevproj] $previd -> $prevdate\n";
      push(@sorted_msbhdr, { date => $prevtime, projectid => $prevproj,
			     msbid => $previd } );
    }
  }

  # Store new
  $previd = $msbid;
  $prevdate = $end;
  $prevproj = $project;
  $prevtime = $obs->endobs;

}

# and last 
unless ($previd eq 'CAL') {
  print "[$prevproj] $previd -> $prevdate\n" unless $previd eq 'CAL';
  push(@sorted_msbhdr, { date => $prevtime, projectid => $prevproj,
			 msbid => $previd } );
}

# Now write them out in date order. Need to make a hash
# indexed by epoch (since they will never be exact)
my %times = map { $_->{date}->epoch, $_ } @sorted_msbhdr;

# Second set is slower so we can spot duplicates
for my $msb (@sorted_msbdb) {
  my $key = $msb->comments->[0]->date->epoch;
  if (exists $times{$key}) {
    print "Warning: Key $key already exists!!\n";
    $key += 0.5;
  }
  $times{$key} = $msb;
}

my @order = sort keys %times;

for (my $i=0; $i<=$#order; $i++) {
  my $prev = ( $i == 0 ? undef : $order[$i-1]);
  my $this = $order[$i];

  my $this_msb = $times{$this};
  my $prev_msb = ( defined $prev ? $times{$prev} : undef);

  print_msb( $this_msb );
  next unless defined $prev_msb;

  # Get rid of extra 0.5 second for dupliocates
  $prev = int($prev);
  $this = int($this);

  # Now flag the gap
  my $gap = $this - $prev;
  if (abs($gap) < (5*60)) {
    print "\tPossible match !! Gap = $gap seconds\n";
  }

}


exit;

sub print_msb { 
  my $msb = shift;
  my ($projectid, $msbid, $date, $user, $comment, $type);
  if (UNIVERSAL::isa( $msb, "OMP::Info::MSB")) {
    $projectid = $msb->projectid;
    $msbid = $msb->checksum;
    $date = $msb->comments->[0]->date->datetime;
    $user = (defined $msb->comments->[0]->author ? 
	    $msb->comments->[0]->author->userid : 'UNKNOWN');
    $comment = $msb->comments->[0]->text;
    $type = 'MSB';
  } else {
    $projectid = $msb->{projectid};
    $msbid = $msb->{msbid};
    $date = $msb->{date}->datetime;
    $comment = '';
    $user = '';
    $type = 'HDR';
  }
  print "$type -- $date,$projectid,$msbid ".
    ($user ? ",$user,$comment" : '') ."\n";

}
