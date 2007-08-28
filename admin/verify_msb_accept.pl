#!/local/perl/bin/perl

=head1 NAME

verify_msb_accept

=head1 SYNOPSIS

  verify_msb_accept -ut 2002-12-10 -tel jcmt

=head1 DESCRIPTION

This program allows you to compare the MSB accept activity as stored
in the database with the MSBs that were actually observed as obtained
from the data FITS headers.

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

use Pod::Usage;
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
use OMP::UserServer;
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
  print "ompmsbcheck - MSB integrity verification\n";
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


my $term = new Term::ReadLine 'Gather arguments';

my $telescope;
if(defined($opt{tel})) {
  $telescope = uc($opt{tel});
} else {
  $telescope = OMP::General->determine_tel( $term );
  die "Unable to determine telescope. Exiting.\n" unless defined $telescope;
  die "Unable to determine telescope [too many choices]. Exiting.\n"
     if ref $telescope;

}


# What does the done table say?
OMP::General->log_message( "Verifying MSB acceptance for date $ut on telescope $telescope" );
my $output = OMP::MSBServer->observedMSBs( {
					    date => $ut,
					    returnall => 0,
					    format => 'object',
					   });

# Need to convert the OMP::Info::MSB with comments to a time
# series. [yes this was how they were stored originally]
my %TITLES; # MSB titles indexed by checksum
my @msbs;
for my $msb (@$output) {
  next unless OMP::ProjServer->verifyTelescope( $msb->projectid, $telescope);
  my $title = $msb->title;
  $TITLES{$msb->checksum} = $msb->title;
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
my $prevtid = '';
my $prevlid = ''; # MSB TID or MSB ID used last time
my $prevdate = 0;
my $prevtime;
my $prevproj = '';
for my $obs (sort { $a->startobs->epoch <=> $b->startobs->epoch} $grp->obs) {

  my $msbid = $obs->checksum;
  my $msbtid = $obs->msbtid;
  my $project = $obs->projectid;
  my $end = $obs->endobs->datetime;

  # ignore calibration projects
  next if $project =~ /CAL$/;
  next unless defined $msbid;
  next if $msbid eq '999999';  # Special code for broken UKIRT headers

  # if we are lacking an MSB transaction ID for whatever reason we just
  # have to act as if the MSB was not repeated in a single block
  # (2007-08-20 JCMT has contiguous MSBs but with differeing MSBTID)
  # Use a separate variable so that we can store the transaction ID.
  my $localtid = $msbtid;
  $localtid = $msbid unless defined $msbtid;

  if ($prevlid ne $localtid) {
    # New MSB, dump the previous one
    if ($prevlid && $prevlid ne 'CAL') {
      print "[$prevproj] $previd -> $prevdate\n";
      push(@sorted_msbhdr, { date => $prevtime, projectid => $prevproj,
			     msbid => $previd,
			     msbtid => $prevtid} );
    }
  }

  # Store new
  $prevlid = $localtid;
  $prevtid = $msbtid;
  $previd = $msbid;
  $prevdate = $end;
  $prevproj = $project;
  $prevtime = $obs->endobs;

}

# and last 
if ($prevlid && $prevlid ne 'CAL') {
  print "[$prevproj] $previd -> $prevdate\n" unless $previd eq 'CAL';
  push(@sorted_msbhdr, { date => $prevtime, projectid => $prevproj,
			 msbid => $previd, msbtid => $prevtid } );
}

if ($grp->numobs == 0) {
  print "No data headers available\n" if $grp->numobs == 0;
  exit;
}

print "---> Summary ----\n";

# Create a hash indexed by checksum + transaction ID for both the HDR and MSB activity

my %DB;
for my $msb ( @sorted_msbdb ) {
  my $id = $msb->checksum;
  my $tid = ($msb->msbtid)[0]; # should only be one since we unrolled earlier
  my $key = _form_hashkey( $id, $tid );
  if (exists $DB{$key} ) {
    warn "An MSB was accepted more than once with the same transaction ID. Very difficult to manage!";
    push(@{$DB{$key}}, $msb );
  } else {
    $DB{$key} = [ $msb ];
  }
}

my %HDR;
for my $msb ( @sorted_msbhdr ) {
  my $id = $msb->{msbid};
  my $tid = $msb->{msbtid};
  my $key = _form_hashkey( $id, $tid );
  if (exists $HDR{$key} ) {
    warn "An MSB was observed more than once with the same transaction ID. Very difficult to manage!";
    push(@{$HDR{$key}}, $msb );
  } else {
    $HDR{$key} = [ $msb ];
  }
}

my @missing;
my %users;

# Loop over MSBs indicated by the data
for my $i ( 0..$#sorted_msbhdr ) {
  my $msb = $sorted_msbhdr[$i];
  my $id = $msb->{msbid};
  my $msbtid = $msb->{msbtid};

  # unique key
  my $key = _form_hashkey( $id, $msbtid );

  # if we do not have a title for it we have to explicitly look in the database (since it
  # will not have been listed in the observedMSBs response)
  if (!exists $TITLES{$id}) {
    my $missing = OMP::MSBServer->historyMSB( $msb->{projectid}, $id, 'data');
    $TITLES{$id} = $missing->title if defined $missing;
  }

  # Print a header
  print "MSB $id for project ". $msb->{projectid} ." completed at ".$msb->{date}->datetime."\n";
  print "\tMSB title: ". (exists  $TITLES{$id} ? $TITLES{$id} : "<unknown>")."\n";

  if (exists $DB{$key}) {
    # We had some activity. If this is the only entry in the HDR info, dump
    # all table activity. If there are multiple HDR entries just use the first entry
    my @thishdr = @{ $HDR{$key} };

    my @dbmsbs;
    if (@thishdr == 1) {
      @dbmsbs = @{$DB{$key}};
      delete $DB{$key};
    } else {
      push(@dbmsbs, shift(@{$DB{$key}}));
      delete $DB{$key} unless @{$DB{$key}};
    }

    for my $db (@dbmsbs) {
      # We had some activity - remove each MSB DB entry
      my $com = $db->comments->[0];
      my $text = OMP::MSBDoneDB::status_to_text( $com->status );
      my $author = (defined $com->author ? $com->author->userid : "<UNKNOWN>");
      $users{$author}++ if defined $com->author;
      print "\t$text by $author at ". $com->date->datetime ."\n";
      print "\tTransaction ID: ". $com->tid."\n" if defined $com->tid;
      my $gap = $com->date - $msb->{date};
      print "\t\tTime between accept and end of MSB: $gap seconds\n";
    }

  } else {
    # see whether this MSB was accepted at some later date
    # This will only happen when an MSB starts on one night and finishes the
    # next. Eg 2007-08-19
    my $tidhis;
    $tidhis = OMP::MSBServer->historyMSBtid( $msb->{msbtid} ) if defined $msb->{msbtid};
    if ($tidhis) {
      print "\t------>>>>> MSB was processed outside the observing system\n";
      my $com = $tidhis->comments->[0];
      my $text = OMP::MSBDoneDB::status_to_text( $com->status );
      my $author = (defined $com->author ? $com->author->userid : "<UNKNOWN>");
      $users{$author}++ if defined $com->author;
      print "\t$text by $author at ". $com->date->datetime ."\n";
      print "\tTransaction ID: ". $com->tid."\n" if defined $com->tid;
      delete $DB{$key};
    } else {
      push(@missing, $msb);
      print "\t------>>>>> Trans Id ".$msb->{msbtid}.
	" has no corresponding ACCEPT/REJECT in the database <<<<<\n";
    }
  }
}

if (keys %DB) {
  print "\n";
  print "----> MSBs activity not associated with a data file (possibly multiple accepts or UT date overrun)\n";

  for my $msb (values %DB) {
    for my $m (@$msb) {
      print_msb( $m );
    }
  }
}

print "\n\n";

if (@missing) {
  my $ok = $term->readline("Some MSBs were not accepted. Do you wish to accept/reject them now? [Yy|Nn] ");
  if ($ok =~ /^y/i) {
    my @users = keys %users;
    my $default;
    if ( @users == 1) {
      $default = $users[0];
    } else {
      $default = '';
    }
    my $uid = $term->readline("Please enter user id to associated with this acceptance [$default] ");
    $uid = $default if !$uid;

    # Validate the user id
    my $validated = OMP::UserServer->getUser( $uid );
    die "User '$uid' does not validate. Aborting.\n" unless defined $validated;

    print "\tAssociating activity with user: $validated\n";
    print "\tAssuming that date of acceptance is the last observation in the MSB\n";
    print "\tDisabling per-MSB comments\n";
    print "\n";

    # Connect to database
    my $msbdb = new OMP::MSBDB( DB => new OMP::DBbackend );
    my $msbdone = new OMP::MSBDoneDB( DB => new OMP::DBbackend );

    # Loop over all missing MSBs
    for my $msb (@missing) {
      my $id = $msb->{msbid};
      my $projectid = $msb->{projectid};
      my $date = $msb->{date};
      my $msbtid = $msb->{msbtid};
      print "Processing MSB $id for project $projectid\n";
      my $continue = $term->readline("\tAccept [Aa] / Reject [Rr] / Skip [] ");
      my $accept;
      if ($continue =~ /^A/i) {
	$accept = 1;
      } elsif ($continue =~ /^R/i) {
	$accept = 0;
      }
      next unless defined $accept;
      my $status = ($accept ? OMP__DONE_DONE : OMP__DONE_REJECTED );

      my $c = new OMP::Info::Comment( author => $validated,
				      date => $date,
				      tid => $msbtid,
				      status => $status );

      if ($accept) {
	print "\tAccepting MSB. Please wait.\n";
	$msbdb->projectid( $projectid );
	$msbdb->doneMSB( $id, $c, { adjusttime => 0 } );
      } else {
	$c->text("This MSB was observed but was not accepted by the observer/TSS. No reason was given.");
	$msbdone->projectid( $projectid );
	$msbdone->addMSBcomment( $id, $c );
      }
      OMP::General->log_message( "ompmsbcheck: Processed MSB $msbtid ($accept) for date $date" );

    }
    print "\nAll MSBs processed.\n\n";

  } else {
    print "Okay. Not accepting outstanding MSBs\n\n";
  }

} else {
  print "\tAll MSBS for this night were either accepted or rejected\n\n";
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

sub _form_hashkey {
  my $msbid = shift;
  my $msbtid = shift;
  my $key = $msbid;
  $key .= "_$msbtid" if defined $msbtid;
  return $key;
}

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>,

=head1 COPYRIGHT

Copyright (C) 2007 Science and Technology Facilities Council.
Copyright (C) 2003, 2005-2007 Particle Physics and Astronomy Research
Council. All Rights Reserved.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program (see SLA_CONDITIONS); if not, write to the
Free Software Foundation, Inc., 59 Temple Place, Suite 330,
Boston, MA  02111-1307  USA

=cut
