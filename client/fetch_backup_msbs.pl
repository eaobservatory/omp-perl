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

use lib "$FindBin::RealBin/..";

use OMP::Config;
use OMP::MSBQuery;
use OMP::DBbackend;
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
# UK, CA, INT separately.  Include as XML to deal with the annoying
# fact that we need to set the semester also for JLS.
my %query = (
    jls => '<country>JLS</country><semester>JLS</semester>',
    pi => '<country>CA</country><country>INT</country><country>UK</country><semester/>',
    nl => '<country>NL</country><semester/>',
);

# Calibration patterns.  Only include calibrations observations if
# they match one of these patterns.
my %cal_patterns = (
    'SCUBA-2' => [
        qr/Setup/,
        qr/Pointing/,
        qr/Focus.*7-steps/,
        qr/^Standard/,
        qr/^Planet/,
    ],
    'HARP' => [
        qr/Point/,
        qr/Focus/,
    ],
    'RxA3' => [
        qr/Point/,
        qr/Focus/,
    ],
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

my $date_step = new DateTime::Duration(minutes => 30);

my $backend = new OMP::DBbackend;

my $utdate = $date_start->ymd('-');
my %msb_filename = ();


# In calibration mode we simply loop over instruments and fetch suitable
# calibrations.
do {
    foreach my $instrument (qw/SCUBA-2 HARP RxA3/) {
        print "CAL $instrument\n\n";

        my $qxml = "<MSBQuery>\n" .
            "<telescope>JCMT</telescope>\n" .
            "<projectid full=\"1\">JCMTCAL</projectid>\n" .
            "<instrument>$instrument</instrument>\n" .

            "<disableconstraint>remaining</disableconstraint>\n" .
            "<disableconstraint>allocation</disableconstraint>\n" .
            "<disableconstraint>observability</disableconstraint>\n " .
            "<disableconstraint>zoa</disableconstraint>\n " .
            "</MSBQuery>\n";

        my $db = new OMP::MSBDB(DB => $backend);
        my @results = $db->queryMSB(new OMP::MSBQuery(XML => $qxml), 'object');

        next unless scalar @results;

        # Results were found, so prepare to write them out.
        my $directory = join '/', $basedir, $utdate, 'CAL', lc($instrument);

        foreach my $result (@results) {
            my $msbid = $result->msbid();
            my $title = $result->title();
            next unless grep {$title =~ $_} @{$cal_patterns{$instrument}};

            # Make safe version of MSB title for inclusion in the file name.
            my $filename = substr($result->title(), 0, 30);
            $filename =~ s/[^a-zA-Z0-9]/_/g;

            my $pathname = "$directory/$filename.xml";
            my $pathnameinfo = "$directory/$filename.info";

            # Abort if the file already exists.
            if (-e $pathname) {
                print STDERR "File already exists: $pathname\n";
                next;
            }

            # Write the XML to a file.

            my $xml = fetch_msb($result->projectid, $msbid);

            print "Writing: $pathname\n";
            make_path($directory);
            my $fh = new IO::File($pathname, 'w');
            print $fh $xml;
            $fh->close();

            # Write the MSB information to another file.
            my $fh = new IO::File($pathnameinfo, 'w');
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
        foreach my $instrument (qw/SCUBA-2 HARP RxA3/) {
            while (my ($query, $countrysemester) = each %query) {
                print "$utdate $hst band $band $instrument $query\n\n";

                my $qxml = "<MSBQuery>\n" .
                    "<telescope>$telescope</telescope>\n" .
                    "<date>" . $date->iso8601() . "</date>\n" .
                    "<tau>$tau</tau>\n" .
                    "<instrument>$instrument</instrument>\n" .
                    "$countrysemester\n".
                    "</MSBQuery>\n";

                my $db = new OMP::MSBDB(DB => $backend);
                my @results = $db->queryMSB(new OMP::MSBQuery(XML => $qxml),
                                            'object');

                next unless scalar @results;

                # Results were found, so prepare to write them out.
                my $directory = join '/', $basedir,
                    $utdate, $hst,
                    'band_' . $band,
                    lc($instrument),
                    $query;

                my $n = 1;
                my %result_id = ();

                foreach my $result (@results) {
                    my $msbid = $result->msbid();

                    # MSBs in multiple queues are returned multiple times!
                    # Is this a bug?  Skip them for now anyway...
                    next if exists $result_id{$msbid};
                    $result_id{$msbid} = 1;

                    # And skip JLS observations outside of the JLS queue
                    # to get a better selection of emergency MSBs...
                    next if $result->projectid() =~ /^MJLS/ && $query ne 'jls';

                    # Make safe version of MSB title for inclusion in the file name.
                    my $title = substr($result->title(), 0, 20);
                    $title =~ s/[^a-zA-Z0-9]/_/g;

                    # Construct filenames.
                    my $filename = join '_', sprintf("%02d", $n), $result->projectid, $title;
                    my $pathname = "$directory/$filename.xml";
                    my $pathnameinfo = "$directory/$filename.info";

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
                        my $xml = fetch_msb($result->projectid, $msbid);

                        # Write the XML to a file.

                        print "Writing: $pathname\n";

                        make_path($directory);
                        my $fh = new IO::File($pathname, 'w');
                        print $fh $xml;
                        $fh->close();

                        # Record this MSB's filenames in case we see it again.
                        $msb_filename{$msbid} = $pathname;
                    }

                    # Write the MSB information to another file, and do this
                    # even if linking the MSB itself as other parameters such
                    # as elevation may have changed.
                    my $fh = new IO::File($pathnameinfo, 'w');
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

sub fetch_msb {
    my $projectid = shift;
    my $msbid = shift;

    # The OMP::MSBDB seems to burn in the project ID after
    # fetching so we need a new one every time!
    my $db = new OMP::MSBDB(DB => $backend);

    my $msb = eval {$db->fetchMSB(msbid => $msbid)};
    unless (defined $msb) {
        print STDERR "Failed to fetch $msbid $@\n";
        next;
    }

    # SP writing code based on OMP::MSBServer::fetchMSB as
    # unfortunately that code isn't in a subroutine we can
    # use.  Might not quite validate, but for the purposes
    # of having emergency backup MSBs, it's probably OK
    # so long as the translator can handle it.
    my @xml = (
        '<?xml version="1.0" encoding="ISO-8859-1"?>',
        '<SpProg type="pr" subtype="none" ' .
            'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ' .
            'xmlns="http://omp.jach.hawaii.edu/schema/TOML">',
        '<meta_gui_collapsed>false</meta_gui_collapsed>',
        '<meta_gui_filename>ompdummy.xml</meta_gui_filename>',
        '<country>UNKNOWN</country>',
    );
    push @xml, '<ot_version>'.$msb->ot_version.'</ot_version>' if defined $msb->ot_version;
    push @xml, (
        '<projectID>' . $projectid . '</projectID>',
        "$msb",
        '</SpProg>'
    );

    return join("\n", @xml);
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
