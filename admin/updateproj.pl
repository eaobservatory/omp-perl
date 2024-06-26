#!/local/perl/bin/perl

=head1 NAME

updateproj - Update information associated with some project(s)

=head1 SYNOPSIS

    updateproj details.ini

=head1 DESCRIPTION

This program reads in a file containing the project information, and
updates the details to the OMP database. If a project does not exist
in the database a warning is issued.  See L<"FORMAT"> for details on
the file format.

=head1 ARGUMENTS

The following arguments are allowed:

=over 4

=item B<defines>

The project update definitions file name. See L<"FORMAT"> for details
on the file format.

=back

=head1 OPTIONS

The following options are supported:

=over 4

=item B<-version>

Report the version number.

=item B<-help>

A help message.

=item B<-man>

This manual page.

=back

=head1 FORMAT

The input project definitions file is in the C<.ini> file format with
the following layout. Individual projects are specified in sections,
indexed by project ID. The column names in this file must match
accessor method names in an C<OMP::Project> object.

    [m01bu32]
    tagpriority=1
    semester=03A
    incalloc=40.0
    support=GMS,TKERR

The exception to this rule is C<incalloc>. This key is taken to imply
that the specified time (in hours) should be added to the allocation
such that that time is the new time remaining on the project (this is
used for carry over of one project from one semester to another).

The C<fixalloc> key is used to force a specific allocation on the
project (not an increment). This is to be preferred over simply using
the C<allocated> key since the remaining time on the project will be
corrected at the same time. This also uses hours rather than seconds.

If you are overriding normal time-based entries, the values should be
in seconds to match the C<OMP::Project> interface.

=cut

use warnings;
use strict;

use FindBin;
use constant OMPLIB => "$FindBin::RealBin/../lib";

use lib OMPLIB;

BEGIN {
    $ENV{'OMP_CFG_DIR'} = File::Spec->catdir(OMPLIB, '../cfg')
        unless exists $ENV{'OMP_CFG_DIR'};
}

use OMP::Error qw/ :try /;
use Config::IniFiles;
use IO::File;
use OMP::DB::Project;
use OMP::DB::User;
use OMP::DB::Backend;
use OMP::SiteQuality;
use Pod::Usage;
use Getopt::Long;

our $VERSION = '2.000';

# Options
my ($help, $man, $version, $force);
my $status = GetOptions(
    "help" => \$help,
    "man" => \$man,
    "version" => \$version,
) or pod2usage(1);

pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

if ($version) {
    print "updateproj - update project details from file\n";
    print "Version: ", $VERSION, "\n";
    exit;
}

# Read the file
my $file = shift(@ARGV);
my %alloc;
my $fh = IO::File->new($file, 'r');
die "Could not open file '$file'" unless defined $fh;
$fh->binmode(':utf8');
tie %alloc, 'Config::IniFiles', (-file => $fh);
$fh->close();

# Connect to the database
my $dbb = OMP::DB::Backend->new;
my $projdb = OMP::DB::Project->new(DB => $dbb);
my $userdb = OMP::DB::User->new(DB => $dbb);

my $val_split = qr/\s*,\s*/;

# Loop over each project and update it
for my $proj (sort {lc $a cmp lc $b} keys %alloc) {
    printf "Processing project: %s ...\n", uc $proj;

    # Set the project ID in the DB object
    $projdb->projectid($proj);

    # First check that the project exists
    unless ($projdb->verifyProject) {
        warn "Project does not exist in DB so can not update it!\n";
        next;
    }

    # Then need to get the project information from the database
    my $project = $projdb->_get_project_row();

    # Then need to go through the hash values and update
    # being careful to deal with incalloc
    for my $mod (keys %{$alloc{$proj}}) {
        die "Can not yet handle tagpriority or country updates"
            if ($mod eq 'tagpriority' or $mod eq 'country');

        # Verify that SUPPORT info is correct
        if ($mod eq 'support') {
            my @support = split $val_split, $alloc{$proj}->{$mod};
            for my $s (@support) {
                die "Unable to locate user $s in database [mode = $mod]\n"
                    unless $userdb->verifyUser($s);
                $s = $userdb->getUser($s);
            }
            my @old = $project->support;
            print "Changing $mod from " . join(" and ", @old)
                . " to " . join(" and ", @support) . "\n";
            $project->support(@support);
        }
        elsif ($mod eq 'pi') {
            # Need to generate an OMP::User object
            my $pi = $alloc{$proj}->{$mod};
            die "Unable to locate user $pi in database [mode = $mod]\n"
                unless $userdb->verifyUser($pi);
            $pi = $userdb->getUser($pi);
            print "Changing $mod from " . $project->$mod . " to $pi\n";
            $project->$mod($pi);
        }
        elsif ($project->can($mod)) {
            print "Changing $mod from " . $project->$mod . " ";

            my $val = $alloc{$proj}->{$mod};

            # OMP::Project->coi expects userids to be separated by a colon by default.
            # ($OMP::Project::DELIM).  A project configuration has, however, values
            # separated by a comma not a colon.
            local $OMP::Project::DELIM = lc $mod eq 'coi'
                ? $val_split
                : ':';

            $project->$mod($val);
            print " to $val\n";
        }
        elsif ($mod eq 'incalloc') {
            # Special case
            my $inc = $alloc{$proj}->{$mod} * 3600;

            print "Changing allocation from " . $project->allocated . " ";

            # The allocation should be the time spent plus
            # the new increment (converted to hours)
            my $newtotal = $project->used + $inc;
            $project->allocated($newtotal);

            # The time remaining on the project is now the increment
            $project->remaining($inc);
            $project->pending(0);

            print "to $newtotal seconds\n";
        }
        elsif ($mod eq 'fixalloc') {
            # Special case so that we can correct the time remaining.
            my $new = $alloc{$proj}->{$mod} * 3600;
            print "Changing allocation from " . $project->allocated . " ";

            # Get the old allocation and time remaining
            my $old = $project->allocated;
            my $rem = $project->remaining;
            my $inc = $new - $old;

            # Fix up the object
            $project->remaining($rem + $inc);
            $project->allocated($new);

            print "to $new seconds\n";
        }
        elsif ($mod eq 'band') {
            # A tau band
            my @bands = split $val_split, $alloc{$proj}->{band};
            my $taurange = OMP::SiteQuality::get_tauband_range($project->telescope, @bands);
            die "Error determining tau range from band " . $alloc{proj}->{band} . " !"
                unless defined $taurange;
            print "Chaning tau range from " . $project->taurange . " to $taurange\n";
            $project->taurange($taurange);
        }
        else {
            warn "Unrecognized key: $mod\n";
        }
    }

    # Now store the project details back in the database
    $projdb->_update_project_row($project);

    print "Updated details\n";
}

__END__

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2003-2005 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut
