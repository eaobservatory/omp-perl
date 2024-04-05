#!/local/perl/bin/perl

=head1 NAME

fetch_backup_msbs - Retrieve a selection of MSBs for offline observation

=head1 SYNOPSIS

    fetch_backup_msbs.pl --directory /export/data/scratch/backup_msbs

=head1 DESCRIPTION

This script queries the database for a selection of MSBs which could
be observed on the current UT date.  These are then stored in a directory
by weather band and time.  Should the database be inaccessible then
observations can be loaded from this directory instead.  Note that
this may result in MSBs being observed an excess number of times,
or when their constraints aren't entirely met, so it should be used
in case of emergency only!

=head1 OPTIONS

=over 4

=item --directory

The directory into which to write the MSBs.

=back

=cut

use strict;

use DateTime;
use DateTime::Duration;
use File::Path qw/make_path/;
use FindBin;
use Getopt::Long;
use IO::File;
use Pod::Usage;

use lib "$FindBin::RealBin/../lib";

use OMP::Config;
use OMP::MSBQuery;
use OMP::DB::Backend;
use OMP::MSBDB;

my ($help, $man, $basedir, $cal);

my $status = GetOptions(
    'help' => \$help,
    'man' => \$man,
    'directory=s' => \$basedir,
    'onlycalibration' => \$cal,
);

pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;
pod2usage("$0: output directory not specified") unless defined $basedir;
pod2usage("$0: output directory does not exist") unless -e $basedir;
pod2usage("$0: output directory is not a directory") unless -d $basedir;

# JCMT only for now.
my $telescope = 'jcmt';

# Number of observations to fetch for each scenario.  Could be a
# command line option?
my $nobs = 15;

# Tau values taken from the "representative values"
# on the SCUBA-2 ITC.
my %band = (
    1 => 0.045,
    2 => 0.064,
    3 => 0.1,
    4 => 0.16,
    5 => 0.23,
);

# Query types to perform.  This has a general PI query instead of
# PI, INT separately.  Include as a hash to deal with the annoying
# fact that we need to set the semester also for LAP.
my %query = (
    lap => {country => 'LAP', semester => 'LAP'},
    pi => {country => ['PI', 'IF']},
    nl => {country => 'NL'},
);

# Calibration patterns.  Only include calibrations observations if
# they match one of these patterns.
my %cal_patterns = (
    'SCUBA-2' => {
        patterns => [
            qr/Setup/,
            qr/Pointing/,
            qr/Focus.*7-steps/,
            qr/^Standard/,
            qr/^Planet/,
            qr/Noise Sky/,
            qr/Noise Dark/,
        ],
    },
    'HARP' => {
        patterns => [
            qr/Point$/,
            qr/Focus.*7-sample/,
        ],
    },
    'Uu' => {
        patterns => [
            qr/Point$/,
            qr/Focus.*7-sample/,
            qr/Align.*7-sample/,
        ],
    },
    'Aweoweo' => {
        patterns => [
            qr/Point$/,
            qr/Focus.*7-sample/,
            qr/Align.*7-sample/,
        ],
    },
    'Alaihi' => {
        patterns => [
            qr/Point$/,
            qr/Focus.*7-sample/,
            qr/Align.*7-sample/,
        ],
        cal_only => 1,
    },
);

# Determine range of times to query for.
my ($date_start, $date_end) = map {
    my ($h, $m) = split ':';
    my $dt = DateTime->now();
    $dt->set_hour($h);
    $dt->set_minute($m);
    $dt->set_second(0);
    $dt;
} OMP::Config->getData('freetimeut', telescope => $telescope);

my $date_step = DateTime::Duration->new(minutes => 30);

my $backend = OMP::DB::Backend->new();

my $utdate = $date_start->ymd('-');
my %msb_filename = ();

# In calibration mode we simply loop over instruments and fetch suitable
# calibrations.
do {
    while (my ($instrument, $instrument_info) = each %cal_patterns) {
        print "CAL $instrument\n\n";

        my $db = OMP::MSBDB->new(DB => $backend);
        my $msbquery = OMP::MSBQuery->new(HASH => {
            telescope => 'JCMT',
            projectid => 'JCMTCAL',
            instrument => $instrument,
            disableconstraint => [qw/remaining allocation observability zoa/],
            _attr => {projectid => {full => 1}},
        }, MaxCount => 10000);
        my @results = $db->queryMSB($msbquery, 'object');

        next unless scalar @results;

        # Results were found, so prepare to write them out.
        my $directory = join '/', $basedir, $utdate, 'CAL', lc($instrument);

        foreach my $result (@results) {
            my $msbid = $result->msbid();
            my $title = $result->title();
            next unless grep {$title =~ $_} @{$instrument_info->{'patterns'}};

            # Make safe version of MSB title for inclusion in the file name.
            my $filename = substr($result->title(), 0, 30);
            $filename =~ s/[^a-zA-Z0-9]/_/g;

            my $pathname = "$directory/$filename.xml";
            my $pathnameinfo = "$directory/$filename.info";

            # Write the XML to a file.

            my $msb = fetch_msb_object($result->projectid, $msbid);
            next unless defined $msb;
            if (exists $instrument_info->{'if'}) {
                my $if = [$msb->obssum]->[0]->{'freqconfig'}->{'subsystems'}->[0]->{'if'};
                next unless $instrument_info->{'if'} eq $if;
            }

            # Abort if the file already exists.

            if (-e $pathname) {
                print STDERR "File already exists: $pathname\n";
                next;
            }

            print "Writing: $pathname\n";
            make_path($directory);
            my $fh = IO::File->new($pathname, 'w');
            $fh->binmode(':utf8');
            print $fh msb_to_xml($result->projectid, $msb);
            $fh->close();

            # Write the MSB information to another file.
            my $fh = IO::File->new($pathnameinfo, 'w');
            $fh->binmode(':utf8');
            print $fh $result->summary('xmlshort');
            $fh->close();
        }
    }

    exit(0) if $cal;
};

# Enter main loop, over: time, band, instrument and query type.
for (my $date = $date_start; $date <= $date_end; $date += $date_step) {
    my $hst = $date->clone;
    $hst->set_time_zone('Pacific/Honolulu');
    $hst = $hst->hms('-');

    while (my ($band, $tau) = each %band) {
        while (my ($instrument, $instrument_info) = each %cal_patterns) {
            next if $instrument_info->{'cal_only'};

            while (my ($query, $countrysemester) = each %query) {
                print "$utdate $hst band $band $instrument $query\n\n";
                my %hash = (
                    telescope => $telescope,
                    date => $date->iso8601(),
                    tau => $tau,
                    instrument => $instrument,
                    %$countrysemester,
                );

                my $db = OMP::MSBDB->new(DB => $backend);
                my $msbquery = OMP::MSBQuery->new(HASH => \%hash);
                my @results = $db->queryMSB($msbquery , 'object');

                next unless scalar @results;

                # Results were found, so prepare to write them out. Number
                # of components of $subdir must match number of ..
                # components in $relpathname below.
                my $subdir = join '/',
                    $hst,
                    'band_' . $band,
                    lc($instrument),
                    $query;
                my $directory = join '/', $basedir, $utdate, $subdir;

                my $n = 1;
                my %result_id = ();

                foreach my $result (@results) {
                    my $msbid = $result->msbid();

                    # MSBs in multiple queues are returned multiple times!
                    # Is this a bug?  Skip them for now anyway...
                    next if exists $result_id{$msbid};
                    $result_id{$msbid} = 1;

                    # And skip LAP observations outside of the LAP queue
                    # to get a better selection of emergency MSBs...
                    next if $result->projectid() =~ /^M\d\d[AB]L/a && $query ne 'lap';

                    # Make safe version of MSB title for inclusion in the file name.
                    my $title = substr($result->title(), 0, 20);
                    $title =~ s/[^a-zA-Z0-9]/_/g;

                    # Construct filenames. ($relpathname is for symlinks)
                    my $filename = join '_', sprintf("%02d", $n), $result->projectid, $title;
                    my $pathname = "$directory/$filename.xml";
                    my $pathnameinfo = "$directory/$filename.info";
                    my $relpathname = "../../../../$subdir/$filename.xml";

                    # Abort if the file already exists.
                    if (-e $pathname) {
                        print STDERR "File already exists: $pathname\n";
                        last;
                    }

                    # Check if we already fetched this MSB and saved it somewhere.
                    if (exists $msb_filename{$msbid}) {
                        make_path($directory);
                        print "Linking: $pathname\n";
                        symlink $msb_filename{$msbid}, $pathname;
                    }
                    else {
                        # This is a new MSB, so fetch from the database.
                        my $msb = fetch_msb_object($result->projectid, $msbid);
                        next unless defined $msb;

                        # Write the XML to a file.

                        print "Writing: $pathname\n";

                        make_path($directory);
                        my $fh = IO::File->new($pathname, 'w');
                        $fh->binmode(':utf8');
                        print $fh msb_to_xml($result->projectid, $msb);
                        $fh->close();

                        # Record this MSB's filenames in case we see it again.
                        # Must be relative pathname so that we can use the files
                        # from another host via the /net/hostname mount.
                        $msb_filename{$msbid} = $relpathname;
                    }

                    # Write the MSB information to another file, and do this
                    # even if linking the MSB itself as other parameters such
                    # as elevation may have changed.
                    my $fh = IO::File->new($pathnameinfo, 'w');
                    $fh->binmode(':utf8');
                    print $fh $result->summary('xmlshort');
                    $fh->close();

                    # Check if we fetched enough MSBs for this query already.
                    last if $nobs < ++ $n;
                }

                print "\n";
            }
        }
    }
}

sub fetch_msb_object {
    my $projectid = shift;
    my $msbid = shift;

    # The OMP::MSBDB seems to burn in the project ID after
    # fetching so we need a new one every time!
    my $db = OMP::MSBDB->new(DB => $backend);

    my $msb = eval {$db->fetchMSB(msbid => $msbid)};
    unless (defined $msb) {
        print STDERR "Failed to fetch $msbid $@\n";
    }

    return $msb;
}

sub msb_to_xml {
    my $projectid = shift;
    my $msb = shift;

    return $msb->dummy_sciprog_xml(
        projectid => $projectid, queue => 'UNKNOWN', xmlns => 1);
}

=head1 AUTHOR

Graham Bell E<lt>g.bell@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2012-2013 Science and Technology Facilities Council.

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

=cut
