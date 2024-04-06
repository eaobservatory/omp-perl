#!/local/perl/bin/perl

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

# Add to @INC for OMP libraries.
use FindBin;
use lib "$FindBin::RealBin/../lib";

use OMP::Constants qw/:fb/;
use OMP::DB::Backend;
use OMP::FBQuery;
use OMP::FeedbackDB;
use OMP::ProjDB;
use OMP::ProjQuery;
use OMP::Mail;

# Options
my ($help, $man, $debug);
my $status = GetOptions(
    "help" => \$help,
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
    $maxdate = Time::Piece->strptime($maxdate, '%Y%m%d');
}
else {
    $maxdate = localtime;
}

if ($mindate) {
    $mindate = Time::Piece->strptime($mindate, '%Y%m%d');
}
else {
    $mindate = $maxdate - 86400;  # 24 hours ago
}

# Get our database connection
my $dbconnection = OMP::DB::Backend->new();

# Instantiate a new FeedbackDB object
my $db = OMP::FeedbackDB->new(DB => $dbconnection);

# Create our query
my $fbquery = OMP::FBQuery->new(HASH => {
    date => {min => $mindate->ymd, max => $maxdate->ymd},
    msgtype => OMP__FB_MSG_SP_SUBMITTED,
});

# Run our query to retrieve comments
my $comments = $db->_fetch_comments($fbquery);

unless (scalar grep {defined $_} @$comments) {
    if ($debug) {
        print "No comments returned by query.\n";
    }
    exit;
}

# Get project IDs for all comments returned.
my %projects = map {$_->{projectid}, undef} @$comments;

# Instantiate a new ProjDB object.  We'll need this
# to get support details for each project returned
my $projdb = OMP::ProjDB->new(DB => $dbconnection);

# Query on all project IDs returned
my $projquery = OMP::ProjQuery->new(HASH => {
    projectid => [keys %projects],
});

# Retrieve details for all projects returned
my $projects = $projdb->listProjects($projquery);

# Find out which of the projects is a new submission.
# Probably easiest just to have the database do the hard work
# and make a complete list of first submissions.
# First convert $mindate to a string only including the
# date part.  Otherwise we can get incorrect results
# if the script is run in non-debug mode since $mindate
# includes the time.
my $mindate_str = $mindate->ymd('');
my %new_submission = ();
my $dbh = $dbconnection->handle();
my $sth = $dbh->prepare('SELECT projectid, MIN(date) FROM '
        . $OMP::FeedbackDB::FBTABLE
        . ' WHERE msgtype=' . OMP__FB_MSG_SP_SUBMITTED
        . ' GROUP BY projectid');
die 'Error preparing minimum date query: ' . $DBI::errstr if $DBI::err;
$sth->execute();
die 'Error executing minimum date query: ' . $DBI::errstr if $DBI::err;

while (my ($proj, $first) = $sth->fetchrow_array()) {
    die 'Did not understand date'
        unless $first =~ /^(\d\d\d\d)-(\d\d)-(\d\d) /a;
    $first = "$1$2$3";
    $new_submission{$proj} = ($first ge $mindate_str);
}

# Sort projects according to support person
my %proj_by_support;
for my $project (@$projects) {
    for my $support ($project->support) {
        my $userid = $support->userid;
        $proj_by_support{$userid} = {
            user => $support,
            projects => [],
        } unless exists $proj_by_support{$userid};

        push @{$proj_by_support{$userid}->{'projects'}}, $project;
    }
}

if ($debug) {
    foreach (sort keys %proj_by_support) {
        my $support = $proj_by_support{$_};
        print $support->{'user'}->name . ":\n";
        for (@{$support->{'projects'}}) {
            print "\t\t" . ($new_submission{$_->projectid} ? 'New' : 'Resub.')
                . "\t" . $_->projectid
                . "\n";
        }
    }
}
else {
    # Send out emails
    for my $userid (keys %proj_by_support) {
        my $support = $proj_by_support{$userid};
        my $projects = $support->{'projects'};

        # Construct the message
        my $anyNew = 0;
        my $text = join "\n",
            'Science programs have been submitted for the following projects:',
            '',
            map {
                my $projectid = $_->projectid;
                my $isNew = $new_submission{$projectid};
                $anyNew ||= $isNew;
                ($isNew ? 'NEW ' : '    ') . $projectid . ' [' . $_->pi . ']'
            } @{$projects};

        my $subject = 'Science program submissions'
            . ($anyNew ? ' [NEW]' : ' [resubmission]');

        #print 'Email to: ', $support->{'user'}->email, "\nSubject: ", $subject, "\n", $text, "\n\n";

        my $mailer = OMP::Mail->new();
        my $msg = $mailer->build(
            from => OMP::User->get_flex(),
            to => [$support->{'user'}],
            subject => $subject,
            message => $text,
        );
        $mailer->send($msg);
    }
}

# Subroutine to generate the project information snippet
# Takes a project object and the submitter's hostname as
# arguments.
sub proj_info {
    my $project = shift;
    my $host = shift;

    my $text;
    my $offset = 78 - length($project->id);

    $text = sprintf "%s%${offset}s", '[' . $project->id . ']', "submitted by: $host\n";
    $text .= 'Title: ' . $project->title . "\n";
    $text .= 'PI: ' . $project->pi . "\n";
    $text .= 'CoI(s): ' . $project->coi . "\n";
}

__END__

=head1 AUTHOR

Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2002-2005 Particle Physics and Astronomy Research Council.
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
