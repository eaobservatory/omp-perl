#!/local/perl-5.6/bin/perl

=head1 NAME

submitted - Contact support for projects which have submitted science programs

=head1 SYNOPSIS

  support [YYYYMMDD YYYYMMDD]
  support --debug

=head1 DESCRIPTION

Determines which projects have had science programs submitted within the given
date range and sends a single email to each support scientist associated with
the projects informing them of the submissions.  If no date range is supplied
then a range of 24 hours is assumed.

Usually run via a cron job every day.

=head1 ARGUMENTS

The following arguments are allowed:

=over 4

=item B<min date>

The mimimum date for the range.  If supplied, the date should be in YYYYMMDD format.  Defaults to 24 hours ago (local time).

=item B<max date>

The maximum date for the range.  If supplied, the date should be in YYYYMMDD format.  Defaults to the current date (local time).  The B<min date> argument must be supplied in order for this argument to be supplied.

=back

=head1 OPTIONS

The following options are supported:

=over 4

=item B<-help>

A help message.

=item B<-man>

This manual page.

=item B<-debug>

Do not send email messages out.  Send a list of project IDs sorted by support to standard
output.

=back

=cut

use warnings;
use strict;

use Pod::Usage;
use Getopt::Long;
use Time::Piece;
use MIME::Lite;

# Add to @INC for OMP libraries.
use FindBin;
use lib "$FindBin::RealBin/..";

use OMP::DBbackend;
use OMP::MSBDB;

# Options
my ($help, $man, $debug);
my $status = GetOptions("help" => \$help,
			"man" => \$man,
			"debug" => \$debug,
		       );

pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

# Get the date range
my $mindate = shift(@ARGV);
my $maxdate = shift(@ARGV);

# Use defaults for arguments that weren't supplied
if ($maxdate) {
  $maxdate = Time::Piece->strptime($maxdate, "%Y%m%d");
} else {
  $maxdate = localtime;
}

if ($mindate) {
  $mindate = Time::Piece->strptime($mindate, "%Y%m%d");
} else {
  $mindate = $maxdate - 86400 # 24 hours ago
}

# Instantiate a new MSBDB object
my $db = new OMP::MSBDB( DB => new OMP::DBbackend,
		         Password => 'kalapana', );

# Get the projects
my @projects = $db->getSubmitted($mindate->epoch, $maxdate->epoch);

# Sort projects according to support person
my %proj_by_support;
for my $project (@projects) {
  for my $support ($project->support) {
    push @{$proj_by_support{$support->email}}, $project;
  }
}

if ($debug) {
  for (keys %proj_by_support) {
    print "$_:\n";
    for (@{$proj_by_support{$_}}) {
      print "\t\t" . $_->projectid . "\n";
    }
  }
} else {
  # Send out emails
  for my $support (keys %proj_by_support) {

    # Construct the message
    my $text;
    if (@{$proj_by_support{$support}}->[1]) {
      $text = "Science programs have been submitted for the following projects:\n\n" .
	join("\n", map {$_->projectid} @{$proj_by_support{$support}});
    } else {
      $text = "A science program has been submitted for project " . @{$proj_by_support{$support}}->[0]->projectid . ".\n";
    }

    my $msg = MIME::Lite->new( From => 'flex@jach.hawaii.edu',
			       To => $support,
			       Subject => 'Science program submissions',
			       Data => $text, );

    MIME::Lite->send("smtp", "mailhost", Timeout => 30);

    # Send the message
    $msg->send
      or die "Error sending message: $!\n";
  }
}

=head1 AUTHOR

Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut


