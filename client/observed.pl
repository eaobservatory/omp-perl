#!/local/perl-5.6/bin/perl

=head1 NAME

observed - Determine what has been observed and contact the feedback system

=head1 SYNOPSIS

  observed [YYYYMMDD]
  observed --debug

=head1 DESCRIPTION

Queries the MSB server to determine the details of all MSBs observed
on the supplied UT date. This information is then sorted by project
ID and sent to the feedback system.

If a UT date is not supplied the current date is assumed.

Usually run via a cron job every night.

=head1 ARGUMENTS

The following arguments are allowed:

=over 4

=item B<date>

If supplied, the date should be in YYYYMMDD or YYYY-MM-DD format.

=back

=head1 OPTIONS

The following options are supported:

=over 4

=item B<-help>

A help message.

=item B<-man>

This manual page.

=item B<-debug>

Do not send messages to the feedback system. Send all messages
to standard output.

=item B<-yesterday>

If no date is supplied, default to the date for yesterday
An error is thrown if a date is also supplied.

=back

=cut

use warnings;
use strict;

use Pod::Usage;
use Getopt::Long;

# Add to @INC for OMP libraries.
use FindBin;
use lib "$FindBin::RealBin/..";

# Load the servers (but use them locally without SOAP)
use OMP::MSBServer;
use OMP::FBServer;
use OMP::ProjServer;
use OMP::General;
use OMP::Constants qw(:fb);

# Options
my ($help, $man, $debug, $yesterday);
my $status = GetOptions("help" => \$help,
			"man" => \$man,
			"debug" => \$debug,
			"yesterday" => \$yesterday,
		       );

pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

# Get the UT date
my $utdate = shift(@ARGV);

die "Can not specify both a date [$utdate] and the -yesterday flag\n"
  if ($yesterday && defined $utdate);

# Default the date
if (!$utdate) {
  if ($yesterday) {
    $utdate = OMP::General->yesterday;
  } else {
    $utdate = OMP::General->today;
  }
}

# Get the list of MSBs
my $done = OMP::MSBServer->observedMSBs( {date => $utdate, 
					  returnall => 0, 
					  format => 'data'} );

# Now sort by project ID
my %sorted;
for my $msbid (@$done) {

  # Get the project ID
  my $projectid = $msbid->projectid;

  # Create a new entry in the hash if this is new ID
  $sorted{$projectid} = [] unless exists $sorted{$projectid};

  # Push this one onto the array
  push(@{ $sorted{$projectid} }, $msbid);
}

# Now create the comment and send it to feedback system
my $fmt = "%-14s %03d %-20s %-20s %-10s %-35s";
my $hfmt= "%-14s Rpt %-20s %-20s %-10s %-35s";
for my $proj (keys %sorted) {

  # Each project info is sent independently to the
  # feedback system so we need to construct a message string
  my $msg = sprintf "$hfmt\n", "Project", "Target", "Instrument",
    "Waveband", "Checksum";

  for my $msbid ( @{ $sorted{$proj} } ) {

    # Note that %s does not truncate strings so we have to do that
    # This will be problematic if the format is modified
    $msg .= sprintf "$fmt\n",
      $proj,$msbid->nrepeats,substr($msbid->target,0,20),
	substr($msbid->instrument,0,20),
	  substr($msbid->waveband,0,10),
	    $msbid->checksum;

  }

  ### TEMPORARILY, if this is a UKIRT project make the comment hidden
  #my $details = OMP::ProjServer->projectDetails($proj, "***REMOVED***", "object");
  #my $status = ($details->telescope eq "UKIRT" ? OMP__FB_HIDDEN : OMP__FB_IMPORTANT);

  # If we are in debug mode just send to stdout. Else
  # contact feedback system
  if ($debug) {
    print $msg;
    print "\nStatus: $status\n";
  } else {
    my ($user, $host, $email) = OMP::General->determine_host;

    my $fixed_text = "<p>Data was obtained for your project on date $utdate.\nYou can retrieve it from the <a href=\"http://omp.jach.hawaii.edu/cgi-bin/projecthome.pl\">OMP feedback system</a></p>\n\n";

    
    OMP::FBServer->addComment(
			      $proj,
			      {
			       author => undef, # this is done by cron
			       subject => "MSB summary for $utdate",
			       program => "observed.pl",
			       sourceinfo => $host,
			       status => $status,
			       text => "$fixed_text<pre>\n$msg\n</pre>\n",
			      }
			     );
  }

}


=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

