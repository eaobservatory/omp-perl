#!/usr/local/bin/perl -w
# Import old faults into the new fault system.
# Takes the fault system as the only argument.
# section for storing faults is commented out for safety resons.

use strict;
use lib qw(/home/kynan/omp/msbserver);
use OMP::Fault;
use OMP::FaultServer;
use OMP::UserServer;
use Time::Piece;
use Time::Seconds;

my %lut = (CSG   => "/net/malama/local/JAC/faults/CS/files",
	   JCMT  => "/net/malama/local/JAC/faults/JCMT/files",
	   UKIRT => "/net/malama/local/JAC/faults/UKIRT/files",);

my $category = uc($ARGV[0]);
my $dir = $lut{$ARGV[0]};

# Get the available fault systems and types
my $systems = OMP::Fault->faultSystems($category);
my $types = OMP::Fault->faultTypes($category);
my %urgencies = OMP::Fault->faultUrgency;
my %status = OMP::Fault->faultStatus;

# Map more type names to existing type constants
$types->{'Other/Unknown'} = $types->{Other};

opendir(DIR, $dir) or die "Couldn't open directory: $!\n";
my @listing = readdir DIR;
closedir(DIR);
shift @listing; # get rid of . and ..
shift @listing;

#@listing = qw/2002_07_01_s5_t5_imc.fault/;

chdir($dir);

# Our success log
my $log = "/home/kynan/importfault.log";
open(LOG, ">>$log") or die "Couldn't open the success log $log:\n$!\n";

# Our error log
my $errorlog = "/home/kynan/importfault.error";
open(ERRORLOG, ">>$errorlog") or die "Couldn't open the error log $errorlog:\n$!\n";

my $count;
my $import;

# Loop through the fault files
for my $fault (@listing) {
  print "*** $fault\n";
  $count++;
  my $skip;

  # Get the author
  $fault =~ /(t\d_|!)(\w+?)\d*\.fault$/;
  my $author = $2;

  # Get the user object
  my $user = OMP::UserServer->getUser($author);

  if (! $user) {
    # User doesn't exist so store the fault file name
    # in our error log.
    print ERRORLOG "$fault No such user [$author]\n";
    print "$fault: No such user [$author]\n";
    next;
  }

  # Read in the fault
  open(FAULT, "$fault") or die "Couldn't open fault $fault: $!\n";
  my @fault = <FAULT>;  # Slurrrp!
  close(FAULT);

  # Get the fault meta data (this is the hard part)
  my @meta;
  (! $fault[20]) and @meta = @fault or
    @meta = @fault[0..20];  # meta data should all be within the first 20 lines

  # The pattern matches for extracting our meta data
  my %regexp = (date => 'date:\s+(\d{2}\/\d{2}\s\d{4})',
		system => 'System\sis\s+:\s+(.*)',
		time => 'time:\s+(\d+:\d+)',
		type => 'Fault\stype\sis\s+:\s+(.*)',
		timelost => 'loss:\s+(\d+\W*\d*?)\shrs',
		urgent => '\*\s+(URGENT:\sREQUIRES\sIMMEDIATE\sATTENTION)\s+\*',
		entity => 'Instrument is\s*:\s*(.*)',
		actual => 'Actual time \(HST\) of failure:\s+(.*)',);

  my %meta;

  # Loop over the meta data
  for my $key (keys %regexp) {
    for (@meta) {
      $_ =~ m!$regexp{$key}!i and $meta{$key} = $1;
    }
  }

  # Skip this fault if we didn't get required meta data
  for (qw/time date system type/) {
    if (! exists $meta{$_}) {
      print ERRORLOG "$fault Meta details missing [" .uc($_). "]\n";
      print "$fault Meta details missing [" .uc($_). "]\n";
      $skip++
    }
  }
  next if $skip;

  my %details;

  # Set the category
  $details{category} = $category;

  # Our default status will be closed
  $details{status} = $status{Closed};

  # Set the system and type
  $details{system} = $systems->{$meta{system}};
  $details{type} = $types->{$meta{type}};
  if (! exists $details{system} || ! exists $details{type}) {
    print ERRORLOG "$fault either system [$meta{system}] or type [$meta{type}] are invalid\n";
    print "$fault either system [$meta{system}] or type [$meta{type}] are invalid\n";
    next;
  }

  # Set the file time
  my $date = Time::Piece->strptime("$meta{date} $meta{time}", "%m/%d %Y %H:%M");

  # Set the failure time (and be clever about it)
  # Maybe use Date::Manip?
  if (exists $meta{actual} and $meta{actual}) {
    my $format = 1;
    if ($meta{actual} =~ /^\d+?\W*\d{2}(\s*|\s*pm\s*)$/) {
      # Hour and minutes
      # Get rid of :
      $meta{actual} =~ s/\D//g;
      if ($meta{actual} > 2359 or $meta{actual} == 0) {
	$meta{actual} = 0;
	$format = "%M";
      } else {
	$meta{actual} = sprintf "%04d", $meta{actual};  # Make sure it has 4 digits
	$format = "%H%M";
      }

    } elsif ($meta{actual} =~ /^(\d|\d{2})\s*$/) {
      # Just the hour
      if ($meta{actual} > 23 or $meta{actual} == 0) {
	$meta{actual} = 0;
	$format = "%M";
      } else {
	$format = "%H";
      }
    } elsif ($meta{actual} =~ /^\D*$/) {
      # Bunch of characters that aren't digits.
    } elsif ($meta{actual} =~ /yesterday/i) {
      # Time is "yesterday" so we'll set the occurance time
      # to the file date - one day
      $details{faultdate} = $date;
      $details{faultdate} -= ONE_DAY;
    } else {
      # Can't figure out what format it is
      print ERRORLOG "$fault Time format not understood [$meta{actual}]\n";
      print "$fault Time format not understood [$meta{actual}]\n";
      next;
    }

    if ($format eq "%H%M") {
      $details{faultdate} = Time::Piece->strptime($date->ymd . " $meta{actual}","%Y-%m-%d $format");
    } elsif ($format eq "%M") {
      # Just minutes
      $details{faultdate} = Time::Piece->strptime($date->ymd . " $meta{actual}","%Y-%m-%d $format");
    }
  }

  if (exists $details{faultdate}) {
    # Subtract a day if the failure date is after the file date
    ($details{faultdate} > $date) and $details{faultdate} -= ONE_DAY;

    # Convert to UT
    $details{faultdate} -= $details{faultdate}->tzoffset;
  }

  # Convert the file date to UT
  $date -= $date->tzoffset;

  # Set the time lost
  $details{timelost} = Time::Seconds->new($meta{timelost} * ONE_HOUR)
    if exists $details{timelost};

  # Set the urgency
  (exists $meta{urgent}) and $details{urgency} = $urgencies{Urgent};

  # Figure out the begin index of each response
  my @index;
  my $j = 0;
  for my $line (@fault) {
    if ($line =~ />{20}>*<{20}/) {
      push @index, $j;
    } elsif ($line =~ /~{30}\s*/ and ! $index[0]) {
      push @index, $j;
    }
    $j++;
  }

  # Seperate the responses
  my @resp;
  $j = 0;
  for (@index) {
    if ($index[$j + 1]) {
      push @resp, join('',@fault[$index[$j] .. $index[$j + 1] - 1 ]);
    } else {
      push @resp, join('',@fault[$index[$j] .. $#fault]);
    }
    $j++;
  }

  # Now loop over the responses
  my @responses;
  my $rcount;
  for my $response (@resp) {
    $rcount++;
    my %response;

    if ($responses[0]) {
       # Get the author, date and text all in one go
      if ($response =~ m!<*\s+response\s+by\s+:.*?\(*\[*(\w+)\]*\)*
	                 \s+date:\s*(\d{2}\/\d{2}\s\d{4}|\d{4}\s\w+?\s\d+)
	                 \s*?(\t*.*)!simx) {

	$response{author} = OMP::UserServer->getUser($1);

	my $date = $2;
	$response{text} = $3;

	my $format;
	if ($date =~ m!\/!) {
	  $format = "%m/%d %Y";
	} else {
	  $format = "%Y %B %d";
	}

	$response{date} = Time::Piece->strptime($date, $format);

	# Convert to UT
	$response{date} -= $response{date}->tzoffset;

      }
    } else {
      # This is the initial fault report
      if ($response =~ /^~*(\s*?\n*$|\s*Actual time \(HST\).*?\n|)(\t*.*\Z)/sm) {
	$response{text} = $2;
	$response{author} = $user;
	$response{date} = $date;
      }
    }

    # Verify that we have all the response details, if not, skip this fault
    for (qw/text author date/) {
      if (! $response{$_}) {
	print ERRORLOG "$fault Response [$rcount] details missing [" .uc($_). "]\n";
	print "$fault Response [$rcount] details missing [" .uc($_). "]\n";
	$skip++;
      }
    }

    # Dont parse any more responses if there were details missing
    last if $skip;

    # Get rid of leading and trailing newlines
    $response{text} =~ /\A\n*(.*?)\s*\Z/s and
      $response{text} = $1;

    # Place each response inside <pre> tags since we know none
    # of the responses are in HTML format
    # $response{text} = "<pre>". $response{text} ."</pre>";

    next if (! $response{text});

    # Create the response object
    my $resp = new OMP::Fault::Response(%response);

    # Add it to our response array
    push @responses, $resp;
  }

  # Go to the next fault if we had trouble getting the responses
  next if $skip;

  # Create the fault object
  $details{fault} = $responses[0];
  my $f = new OMP::Fault(%details);

  # Store the responses in the fault object
  $f->respond(\@responses);
  
  #print $f;

  # Store the fault
  #my $faultid = OMP::FaultServer->fileFault( $f );

  #if (! $faultid) {
  #  $skip++;
  #  print ERRORLOG "$fault Not imported\n";
  #  next;
  #}

  # Write the fault ID to our log file
  #print LOG "$faultid $fault\n";
  $import++;
}

my $skipped = $count - $import;
print "Total:\t\t$count\nSkipped:\t$skipped -\n";
print "\t\t-----\nImported: =\t$import\n";
# Close our logs
close LOG;
close ERRORLOG;
