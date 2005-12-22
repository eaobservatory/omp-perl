#!/local/perl-5.6/bin/perl

=head1 NAME

verify_msb_accept

=head1 SYNOPSIS

  verify_msb_accept -ut 2002-12-10 -tel jcmt

=head1 DESCRIPTION

This program allows you to compare the MSB accept activity as stored in the database
with the MSBs that were actually observed as obtained from the data FITS headers.


=head1 OPTIONS

The following options are supported:

=over 4

=item B<-ut>

Override the UT date used for the report. By default the current date
is used.  The UT can be specified in either YYYY-MM-DD or YYYYMMDD format.
If the supplied date is not parseable, the current date will be used.

=item B<-tel>

Specify the telescope to use for the report. If the telescope can
be determined from the domain name it will be used automatically.
If the telescope can not be determined from the domain and this
option has not been specified a popup window will request the
telescope from the supplied list (assume the list contains more
than one telescope).

=item B<-version>

Report the version number.

=item B<-help>

A help message.

=item B<-man>

This manual page.

=back

=cut

use strict;
use warnings;

use Getopt::Long;
use FindBin;
use File::Spec;
use Data::Dumper;
use Term::ReadLine;

use constant OMPLIB => "$FindBin::RealBin/..";

use lib OMPLIB;

BEGIN {
  $ENV{OMP_CFG_DIR} = File::Spec->catdir( OMPLIB, "cfg" )
    unless exists $ENV{OMP_CFG_DIR};
};

use OMP::Info::ObsGroup;
use OMP::MSBServer;
use OMP::ProjServer;
use OMP::Constants qw/ :done /;

# Command line parsing
my ( %opt, $help, $man, $version );
my $status = GetOptions("ut=s" => \$opt{ut},
                        "tel=s" => \$opt{tel},
                        "help" => \$help,
                        "man" => \$man,
                        "version" => \$version,
                       );

pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

if( $version ) {
  my $id = '$Id$ ';
  print "verify_msb_accept - MSB integrity verification\n";
  print " CVS revision: $id\n";
  exit;
}

# default to today;
my $ut;
if (defined $opt{ut}) {
  $ut = OMP::General->determine_utdate( $opt{ut} )->ymd;
} else {
  $ut = OMP::General->today(1);
  print "Defaulting to today (".$ut->ymd.")\n";
}


my $telescope;
if(defined($opt{tel})) {
  $telescope = uc($opt{tel});
} else {
  my $term = new Term::ReadLine 'Gather arguments';
  $telescope = OMP::General->determine_tel( $term );
  die "Unable to determine telescope. Exiting.\n" unless defined $telescope;
  die "Unable to determine telescope [too many choices]. Exiting.\n"
     if ref $telescope;

}


######## Begin #########

# What does the done table say?
my $output = OMP::MSBServer->observedMSBs( {
					    date => $ut,
					    returnall => 0,
					    format => 'object',
					   });

# Need to convert the OMP::Info::MSB with comments to a time
# series. [yes this was how they were stored originally]
my @msbs;
for my $msb (@$output) {
  next unless OMP::ProjServer->verifyTelescope( $msb->projectid, $telescope);
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
my $grp = new OMP::Info::ObsGroup( telescope => $telescope,
				   date => $ut,
				 );

# Go through looking for MSBs
my @sorted_msbhdr;
my $previd = '';
my $prevdate = 0;
my $prevtime;
my $prevproj = '';
for my $obs (sort { $a->startobs->epoch <=> $b->startobs->epoch} $grp->obs) {

  my $msbid = $obs->checksum;
  my $project = $obs->projectid;
  my $end = $obs->endobs->datetime;

  # ignore calibration projects
  next if $project =~ /CAL$/;

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
if ($previd && $previd ne 'CAL') {
  print "[$prevproj] $previd -> $prevdate\n" unless $previd eq 'CAL';
  push(@sorted_msbhdr, { date => $prevtime, projectid => $prevproj,
			 msbid => $previd } );
}

if ($grp->numobs == 0) {
  print "No data headers available\n" if $grp->numobs == 0;
  exit;
}

print "---> Summary ----\n";

# Create a hash indexed by checksum for both the HDR and MSB activity

my %DB;
for my $msb ( @sorted_msbdb ) {
  my $id = $msb->checksum;
  if (exists $DB{$id} ) {
    push(@{$DB{$id}}, $msb );
  } else {
    $DB{$id} = [ $msb ];
  }
}

my %HDR;
for my $msb ( @sorted_msbhdr ) {
  my $id = $msb->{msbid};
  if (exists $HDR{$id} ) {
    push(@{$HDR{$id}}, $msb );
  } else {
    $HDR{$id} = [ $msb ];
  }
}

for my $i ( 0..$#sorted_msbhdr ) {
  my $msb = $sorted_msbhdr[$i];
  my $id = $msb->{msbid};

  print "MSB $id for project ". $msb->{projectid} ." completed at ".$msb->{date}->datetime."\n";

  if (exists $DB{$id}) {
    # We had some activity. If this is the only entry in the HDR info, dump
    # all table activity. If there are multiple HDR entries just use the first entry
    my @thishdr = @{ $HDR{$id} };

    my @dbmsbs;
    if (@thishdr == 1) {
      @dbmsbs = @{$DB{$id}};
      delete $DB{$id};
    } else {
      push(@dbmsbs, shift(@{$DB{$id}}));
      delete $DB{$id} unless @{$DB{$id}};
    }

    for my $db (@dbmsbs) {
      # We had some activity - remove each MSB DB entry
      my $com = $db->comments->[0];
      my $text = _status_to_text( $com->status );
      my $author = (defined $com->author ? $com->author->userid : "<UNKNOWN>");
      print "\t$text by $author at ". $com->date->datetime ."\n";
      my $gap = $com->date - $msb->{date};
      print "\t\tTime between accept and end of MSB: $gap seconds\n";
    }

  } else {
    print "\t------>>>>> Has no corresponding ACCEPT/REJECT in the database <<<<<\n";
  }
}

if (keys %DB) {
  print "----> MSBs activity not associated with a data file (possibly multiple accepts)\n";

  for my $msb (values %DB) {
    for my $m (@$msb) {
      print_msb( $m );
    }
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


sub _status_to_text {
  my $status = shift;
  my %lut = ( 
	     &OMP__DONE_UNDONE => 'Undone',
	     &OMP__DONE_ALLDONE => 'AllDone',
	     &OMP__DONE_COMMENT => 'Commented Upon',
	     &OMP__DONE_ABORTED => 'Aborted',
	     &OMP__DONE_REJECTED => 'Rejected',
	     &OMP__DONE_SUSPENDED => 'Suspended',
	     &OMP__DONE_DONE     => 'Accepted',
	     &OMP__DONE_FETCH    => 'Retrieved'
	    );
  if (exists $lut{$status} ) {
    return $lut{$status};
  } else {
    return "?????";
  }
}
