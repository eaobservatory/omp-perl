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

The following arguments are supported:

=over 4

=item B<-help>

A help message.

=item B<-man>

This manual page.

=item B<-debug>

Do not send messages to the feedback system. Send all messages
to standard output.

=back

=cut

use warnings;
use strict;

use Pod::Usage;
use Getopt::Long;

# Load the servers (but use them locally without SOAP)
use OMP::MSBServer;
use OMP::FBServer;
use OMP::General;

# Options
my ($help, $man, $debug);
my $status = GetOptions("help" => \$help,
			"man" => \$man,
			"debug" => \$debug,
		       );

pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

# Get the UT date
my $utdate = shift(@ARGV);
$utdate = OMP::General->today unless $utdate;

# Get the list of MSBs
my $done = OMP::MSBServer->observedMSBs( $utdate, 0, 'data');

# Now sort by project ID
my %sorted;
for my $msbid (@$done) {

  # Get the project ID
  my $projectid = $msbid->{projectid};

  # Create a new entry in the hash if this is new ID
  $sorted{$projectid} = [] unless exists $sorted{projectid};

  # Push this one onto the array
  push(@{ $sorted{$projectid} }, $msbid);

}


# Now create the comment and send it to feedback system
my $fmt = "%-8s %-20s %-20s %-10s %-35s";
for my $proj (keys %sorted) {

  # Each project info is sent independently to the
  # feedback system so we need to construct a message string
  my $msg = sprintf "$fmt\n", "Project", "Target", "Instrument",
    "Waveband", "Checksum";

  for my $msbid ( @{ $sorted{$proj} } ) {

    $msg .= sprintf "$fmt\n",
      $proj,$msbid->{target},
	$msbid->{instrument},$msbid->{waveband},$msbid->{checksum};

  }

  # If we are in debug mode just send to stdout. Else
  # contact feedback system
  if ($debug) {
    print $msg;
  } else {
    my ($user, $host, $email) = OMP::General->determine_host;
    OMP::FBServer->addComment(
			      $proj,
			      {
			       author => $user,
			       subject => "MSB summary for $utdate",
			       program => "observed.pl",
			       sourceinfo => $host,
			       text => "<pre>\n$msg\n</pre>\n",
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

