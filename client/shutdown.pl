#!/local/perl/bin/perl

=head1 NAME

shutdown - Produce time accounting for shutdown periods

=head1 SYNOPSIS

  shutdown -tel ukirt
  shutdown -tel jcmt -ut

=head1 DESCRIPTION

This program generates time accounting data and shiftlog comments
for a given date range.  It assumes that observing would have begun
at the start of astronomical twilight.

=head1 OPTIONS

The following options are supported:

=over 4

=item B<-tel>

Specify the telescope with which time accounting data will be
associated.

=item B<-ut>

Use this argument if you will be providing dates in UTC time, otherwise
dates are assumed to be in local time.

=item B<-version>

Report the version number.

=item B<-help>

A help message.

=item B<-man>

This manual page.

=item B<-debug>

Do not write anything to the database.

=back

=cut

use 5.006;
use strict;
use warnings;

use Astro::Coords;
use Astro::Telescope;
use DateTime;
use DateTime::Duration;
use DateTime::Format::Duration;
use DateTime::Format::ISO8601;
use Getopt::Long;
use Pod::Usage;
use Term::ReadLine;
use Time::Piece;

# Locate the OMP software through guess work
use FindBin;
use lib "$FindBin::RealBin/..";

# OMP Classes
use OMP::DBbackend;
use OMP::General;
use OMP::Info::Comment;
use OMP::Project::TimeAcct;
use OMP::ShiftDB;
use OMP::TimeAcctDB;
use OMP::TimeAcctGroup;
use OMP::UserDB;

use vars qw/ $DEBUG /;
$DEBUG = 0;

# Options
my ($help, $man, $version, $tel, $semester, $ut);
my $status = GetOptions("help" => \$help,
                        "man" => \$man,
                        "version" => \$version,
                        "tel=s" => \$tel,
                        "ut" => \$ut,
			"debug" => \$DEBUG,
                       );

pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

if ($version) {
  my $id = '$Id$ ';
  print "shutdown - Produce time accounting for shutdown periods\n";
  print " CVS revision: $id\n";
  exit;
}

# Setup term
my $term = new Term::ReadLine 'Generate time accounting information for planned shutdowns';

# Setup duration object display formats
my $dseconds = DateTime::Format::Duration->new(pattern=>'%s',);

# Connect to the database
my $dbconnection = new OMP::DBbackend;

# Prompt for telescope name (unless it was provided as an argument)
$tel = OMP::General->determine_tel($term)
  unless (defined $tel);

# Verify telescope argument
my %telescopes = map {$_, $_} OMP::General->determine_tel();
if (defined $tel and exists $telescopes{uc($tel)}) {
  $tel = $telescopes{uc($tel)};
} else {
  die "Must provide a valid telescope\n";
}

# Get and verify user ID
my $prompt = "Your OMP user ID: ";
my $userid = $term->readline($prompt);
my $udb = new OMP::UserDB( DB => $dbconnection );
my $user = $udb->getUser( $userid );
die "Invalid user: $userid\n"
  unless (defined $user);

# Get start and end dates
my $parser = DateTime::Format::ISO8601->new;

$prompt = "Shutdown start date (YYYY-MM-DD): ";
my $startdate = $term->readline($prompt);
my $startdt = $parser->parse_datetime($startdate);

$prompt = "Shutdown end date (YYYY-MM-DD): ";
my $enddate = $term->readline($prompt);
my $enddt = $parser->parse_datetime($enddate);

# Currently our dates are in the 'floating' time zone,
# set time zones to local time unless -ut argument was used
my $tz = ($ut ? 'UTC' : 'local');
$startdt->set_time_zone($tz);
$enddt->set_time_zone($tz);

# Get shutdown time amount
$prompt = "Length of each shutdown night (hours) [defaults to twilight]: ";
my $shutlen_arg = $term->readline($prompt);

# If shutdown length was provided, convert it to seconds
my $shutlen;
if ($shutlen_arg) {
  my $shutlendur = DateTime::Duration->new(hours=> $shutlen_arg,);
  $shutlen = $dseconds->format_duration($shutlendur);
}

# Get shutdown reason
$prompt = "Reason for shutdown: ";
my $shutreason = $term->readline($prompt);
die "Must provide a comment"
  unless (defined $shutreason);

# Loop over each night...
my $oneday = DateTime::Duration->new(days=>1,);
my $currentdt = $startdt;
my $set_time;
my @taccts;
my @shiftcomms;
while ($currentdt <= $enddt) {
  # Calculate length of night if the value was not provided

  # Create Astro::Coords object
  my $c = new Astro::Coords(planet=> 'sun',);

  # Register datetime object with the Astro::Coords object
  $c->datetime($currentdt);

  # Register telescope with the Astro::Coords object
  $c->telescope(new Astro::Telescope($tel));

  # Get set time (twilight begin)
  $set_time = $c->set_time( horizon => Astro::Coords::AST_TWILIGHT );

  if (! $shutlen_arg) {
    # We want the rise time for the next day, so set our Astro::Coords object's
    # forward, past the current day's rise time
    $c->datetime($set_time);

    # Get rise time (twilight end)
    my $rise_time = $c->rise_time( horizon => Astro::Coords::AST_TWILIGHT );

    # Get difference between set and rise time
    my $duration = $rise_time - $set_time;

    if ($DEBUG) {
      print "Set: ". $set_time->datetime ." Rise: ". $rise_time->datetime . " Duration: ". $dseconds->format_duration($duration)."\n";
    }

    $shutlen = $dseconds->format_duration($duration);
  }

  # Convert DateTime object to Time::Piece object
  # Assume that observing would begin at the start of astronomical twilight
  my $starttimetp = gmtime($set_time->epoch);

  # Create TimeAcct (use special $tel_SHUTDOWN category)
  my $t = new OMP::Project::TimeAcct(projectid => "${tel}_SHUTDOWN",
				     date      => $starttimetp,
				     timespent => $shutlen,
				     confirmed => 1,);

  push (@taccts, $t);

  # Create shiftlog comments
  my $comment = new OMP::Info::Comment(author => $user,
				       text   => $shutreason,
				       date   => $starttimetp);

  push (@shiftcomms, $comment);

  # Go to the next day
  $currentdt += $oneday;
}

# Store accounts to a group for simple statistics
my $tacctgrp = new OMP::TimeAcctGroup( accounts => \@taccts );

# Display time accounts and shiftlog comments
print "Time accounts created (". scalar(@taccts) .")\n";
printf "Total time: %.2f hours\n", $tacctgrp->totaltime->hours;
print "\nShiftlog comments created (". scalar(@shiftcomms) .")\n";
print "Author: ". $shiftcomms[0]->author . "\n";
print "Comment: ". $shiftcomms[0]->text . "\n";

if ($DEBUG) {
  print "Comment created for the following dates:\n";
  for my $comment (@shiftcomms) {
    print "\t" . $comment->date . "\n";
  }
}

# Store the accounts and comments to the database
if (! $DEBUG) {
  # Store time accounts
  my $acctdb = new OMP::TimeAcctDB( DB => $dbconnection );
  $acctdb->setTimeSpent(@taccts);

  print "Stored time accounts.\n";

  # Store shiftlog comments
  my $shiftdb = new OMP::ShiftDB( DB => $dbconnection );
  for my $comment (@shiftcomms) {
    $shiftdb->enterShiftLog( $comment, $tel );
  }

  print "Stored shiftlog comments.\n";
}

print "Done.\n";

=head1 AUTHOR

Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2004-2005 Particle Physics and Astronomy Research Council.
All Rights Reserved.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful,but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc., 59 Temple
Place,Suite 330, Boston, MA  02111-1307, USA

=cut
