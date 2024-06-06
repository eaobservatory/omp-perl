#!/local/perl/bin/perl

=head1 NAME

bulk - Submit a feedback comment to multiple projects

=head1 SYNOPSIS

    bulk -comment comment.txt -projects projects.txt

=head1 DESCRIPTION

This program submits a feedback comment to multiple projects.  As with
all feedback comments, the comment is e-mailed to any parties that
normally receive e-mail associated with a project.  The comment and
list of project IDs are provided in separate text files.  See the section
on B<FORMAT> for more details on the required format of those files.

=head1 OPTIONS

The following options are supported:

=over 4

=item B<-comment>

Specify the location of the file containing the feedback comment to
be submitted.

=item B<-projects>

Specify the location of the file containing IDs of projects for which
the comment will be submitted.

=item B<-support>

Mark comment with "support" status to limit the emails sent only to the support
staff.

=item B<-dry-run> | B<-n>

Do not actually submit the feedback comment.

=item B<-help>

A help message.

=item B<-man>

This manual page.

=item B<-version>

Report the version number.

=back

=head1 FORMAT

In the text file containing the feedback comment, the first line should
be the subject of the comment.  Any lines following that line will be used
as the message body of the comment.

    Comment Subject
    Comment text line 1.
    Comment text line 2.

In the project IDs text file, the ID of each project for which the comment
is being submitted should be provided on its own line.

    U/05A/1
    U/05A/2
    M05AC01
    M05AU02

=cut

use warnings;
use strict;

use Getopt::Long;
use IO::File;
use Pod::Usage;

# Locate the OMP software through guess work
use FindBin;
use lib "$FindBin::RealBin/../lib";

use OMP::Constants qw/:fb/;
use OMP::DB::Backend;
use OMP::DB::Feedback;
use OMP::Password;
use OMP::DB::Project;

our $VERSION = '2.000';

# Options
my ($commentfile, $help, $man, $projectsfile, $version, $type, $dry_run);

GetOptions(
    'comment=s' => \$commentfile,
    'help' => \$help,
    'man' => \$man,
    'projects=s' => \$projectsfile,
    'n|dry-run' => \$dry_run,
    'version' => \$version,
    'support' => sub {$type = 'support'},
) or pod2usage(-exitstatus => 1, -verbose => 0);

pod2usage(-exitstatus => 0, -verbose => 99, -sections => [
    qw/SYNOPSIS OPTIONS FORMAT/]) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

if ($version) {
    print "bulk - Submit a feedback comment to multiple projects\n";
    print "Version: $VERSION\n";
    exit;
}

# Die if missing certain arguments
unless (defined $commentfile and defined $projectsfile) {
    die "The following arguments are not optional: -comment, -projects";
}

# Get the projects
my $proj_fh = IO::File->new($projectsfile, 'r')
    or die "Couldn't open file [$projectsfile]: $!";

my @projects;
foreach my $id (<$proj_fh>) {
    chomp $id;

    next if $id =~ m/^\s*#/
        or $id =~ m/^\s*$/;

    push @projects, $id;
}

close($proj_fh);

my $database = OMP::DB::Backend->new();

# Verify that the projects exist
foreach my $projectid (@projects) {
    die "Project does not exist [$projectid]"
        unless OMP::DB::Project->new(DB => $database, ProjectID => $projectid)->verifyProject();
}

# Create the comment
my $comment_fh = IO::File->new($commentfile, 'r')
    or die "Couldn't open file [$commentfile]: $!";
my @comment = <$comment_fh>;
$comment_fh->close();

my $subject = shift @comment;
chomp $subject;

# Verify staff membership
my $auth = OMP::Password->get_verified_auth($database, 'staff');

my %comment = (
    text => (join '', @comment),
    author => $auth->user,
    program => 'COMMENT_CLIENT',
    subject => $subject,
);

$comment{'status'} = OMP__FB_SUPPORT
    if defined $type && $type eq 'support';

print "Subject:\n",
    $comment{'subject'}, "\n\n",
    "Text:\n",
    $comment{'text'}, "\n",
    "Projects:\n",
    (join "\n", @projects),
    "\n\n",
    ($dry_run ? 'Dry-run' : 'Active'),
    ' mode: comment ',
    ($dry_run ? 'will not' : 'will'),
    " be submitted\n\n";

# Submit the comment for each project
foreach my $projectid (@projects) {
    print "Submitting the comment for project [$projectid] ...";

    if ($dry_run) {
        print " [DRY-RUN]\n";
        next;
    }

    my $fdb = OMP::DB::Feedback->new(ProjectID => $projectid, DB => $database);
    $fdb->addComment(\%comment);
    print " [DONE]\n";
}

print "The comment has been submitted.\n";

__END__

=head1 AUTHOR

Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2005 Particle Physics and Astronomy Research Council.
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
