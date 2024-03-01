#!/local/perl/bin/perl

=head1 NAME

jcmtenterdata - Parse headers and store in database

=head1 SYNOPSIS

Show the usage...

    jcmtenterdata -help

Run with current UT date in insert mode ...

    jcmtenterdata

Run in dry-run mode for Jun 25, 2008 ...

    jcmtenterdata --dry-run 20080625

=head1 DESCRIPTION

Reads the headers of all data from either the current date or the
specified UT date, and uploads the results to the header database. If
no date is supplied the current localtime is used to determine the
relevant UT date (which means that it will still pick up last night's
data even if run after 2pm).

=head2 OPTIONS

By default both ACSIS & SCUBA2 instruments are used, unless specified
by the options otherwise.

=over 2

=item B<-help>

Show this message.

=item B<-files>

Specify to indicate that the argument(s) given is(are) a raw file
name(s), not a date.

=item B<-from-files>

Indicate that the first argument (other than any options) is a file
containing raw file paths, one per line; I<overides -files option>.

=item B<-from-mongodb>

Retrieve file information from MongoDB only.

Usage of this mode implies C<--nobounds> and C<--nostate>.

=item B<-force-disk>

Force to locate raw files on disk; default is find file paths in
database.

Only applies in "calcbounds" mode.

=item B<-acsis>

Enter data for ACSIS.

=item B<-bounds>

Run bound calculations (applies only for ACSIS data). By default bound
calculations are done.

=item B<-nobounds>

Skip bound calculations (applies only for ACSIS data)

=item B<-nostate>

Skip setting a state, used otherwise to keep track of transfers.

=item B<--dry-run>

Run in "dry run" mode, nothing actually is changed in database.

=item B<-inbeam>

Update only the inbeam values.

=item B<-logfile> file

Log non-error messages in a file.

=item B<-debugfile> file

File into which to dump header information prior to it being entered into
the database.  Can be combined with the "--dry-run" option to not produce
this output only.  The file can be specified as "-" to use standard output.

=item B<-obstime>

Update only the observation times.

=item B<-rxh3>

Enter data for RxH3.

=item B<-scuba2>

Enter data for SCUBA2.

=item B<-simulation>

Specify to force processing of simulations, which are otherwise
skipped.

=item B<-wait> second

Specify wait time in seconds before checking for new files again to ingest.
The program will run on this interval until the "limited datetime" changes,
i.e. 1 hour past the UT date change.

If not specified then the program runs once and exits.
Should not be used if files or a date are specified.

=item B<-calcbounds>

Run in bounds calculation mode, i.e. performing the action previously
done by a separate "calc-bounds.pl" script.  This updates the bounds
of observations in the database.

Many of the other options will not apply in this mode.

=item B<-overwrite> / B<-nooverwrite>

Enable or disable "overwrite" updating mode.  If not specified, "overwrite"
mode will be used unless "-wait" is given.  Overwrite mode updates differing
database entries directly rather than applying update rules suitable for
incremental data entry.

Does not apply in bounds calculation mode.

=item B<-starlink> directory

Set STARLINK_DIR to the specified value.  [Default: /star]

=back

=head1 NOTES

Skips any data files that are from simulated runs (SIMULATE=T).

=cut

use strict;
use warnings;

# Add "archiving" because JCMT::DataVerify is needed by JSA::EnterData.
use JAC::Setup qw/omp jsa archiving/;

BEGIN {
    $ENV{'OMP_SITE_CONFIG'} = '/jac_sw/etc/enterdata/enterdata.cfg';
}

use OMP::FileUtils;

use OMP::DBbackend::Archive;
use JSA::Datetime qw/make_datetime make_limited_datetime/;
use JSA::EnterData;
use JSA::EnterData::ACSIS;
use JSA::EnterData::RxH3;
use JSA::EnterData::SCUBA2;
use JSA::LogSetup qw/make_logfile/;

use FindBin;
use File::Spec;
use Time::Piece;
use Getopt::Long;
use IO::File;
use Pod::Usage;
use Log::Log4perl;
use Log::Log4perl::Level;

$| = 1;

do {
    #  Set for ACSIS.
    my $find_bounds = 1;
    my $n_err = 0;

    my ($dry_run, $verbose, $calcbounds) = (0) x 3;
    my ($obstime, $inbeam, $skip_state, $skip_db_path, $logfile, $wait);
    my ($help, $acsis, $rxh3, $scuba2, $file_src, $mongo_src, $simulation, $overwrite, $debugfile);
    my $starlink_dir = '/star';

    GetOptions(
        'help'           => \$help,
        'log|logfile=s'  => \$logfile,

        'acsis|ACSIS!'   => \$acsis,
        'rxh3|RXH3!'     => \$rxh3,
        'scuba2|SCUBA2!' => \$scuba2,

        'starlink=s'     => \$starlink_dir,
        'wait=i'         => \$wait,
        'dry-run'        => \$dry_run,
        'verbose!'       => \$verbose,
        'obstime'        => \$obstime,
        'inbeam'         => \$inbeam,
        'nostate'        => \$skip_state,
        'bounds!'        => \$find_bounds,
        'simulation!'    => \$simulation,
        'calcbounds'     => \$calcbounds,
        'overwrite!'     => \$overwrite,
        'debugfile=s'    => \$debugfile,

        'force-disk!'    => \$skip_db_path,

        'files!'         => sub {$file_src = 'args';},
        'from-files!'    => sub {$file_src = 'from-file';},
        'from-mongodb!'  => \$mongo_src,
    )
    or pod2usage('-exitval' => 2, '-verbose' => 1);

    pod2usage('-exitval' => 1, '-verbose' => 2) if $help;

    JSA::LogSetup::logfile(make_logfile(
        defined $logfile ? $logfile : 'jcmtenterdata.log'));

    Log::Log4perl->init(JSA::LogSetup::get_config());
    my $log = Log::Log4perl->get_logger('');
    $log->level($verbose ? $DEBUG : $INFO);

    # For makemap|makecube.
    $ENV{'STARLINK_DIR'} = $starlink_dir;
    $ENV{'KAPPA_DIR'} = File::Spec->catdir($starlink_dir, 'bin', 'kappa');
    $ENV{'SMURF_DIR'} = File::Spec->catdir($starlink_dir, 'bin', 'smurf');

    my $debug_fh = undef;
    if (defined $debugfile) {
        if ($debugfile eq '-') {
            $debug_fh = \*STDOUT;
        }
        else {
            $debug_fh = new IO::File($debugfile, 'w');
        }
    }

    my %insts = get_instruments(
        ACSIS => $acsis,
        'SCUBA-2' => $scuba2,
        RxH3 => $rxh3,
        debug_fh => $debug_fh);

    # Reference to list of files to process. Can be undef if date-based.
    my $files = undef;

    # List of dates to process.  This can be (undef) for a non-date-based
    # entry, i.e. for files mode.
    my @dates = ();

    # File collection.
    if ($file_src) {
        die 'Files given with multiple instruments'
            if 1 != scalar keys %insts;

        die 'Files given in MongoDB mode'
            if $mongo_src;

        $files = (lc $file_src eq 'args')
            ? [@ARGV] : files_in_list($ARGV[0]);

        push @dates, undef;
    }
    elsif (@ARGV) {
        @dates = @ARGV;
    }
    elsif (not defined $wait) {
        die 'Date not given in MongoDB mode'
            if $mongo_src;

        push @dates, make_datetime()->ymd('');
    }

    # Ensure suitable options are set for MongoDB mode.
    if ($mongo_src) {
        $skip_state = 1;
        $find_bounds = 0;
    }

    # Enable overwrite by default except in wait mode.
    if (not defined $wait) {
        if (not defined $overwrite) {
            $overwrite = 1;
        }
    }
    elsif ($overwrite) {
        die 'Overwrite mode should not be used for incremental entry';
    }

    unless ($calcbounds) {
        # Original "enter data" mode.

        $OMP::FileUtils::RETURN_RECENT_FILES = 1;

        my %enter_options = (
            dry_run => $dry_run,
            skip_state => $skip_state,
            overwrite => $overwrite,
            process_simulation => $simulation,
            update_only_inbeam => $inbeam,
            update_only_obstime => $obstime,
            from_mongodb => $mongo_src,
        );

        my $lim_date_initial = undef;

        if (defined $wait) {
            die 'Entry from MongoDB not supported in wait mode'
                if $mongo_src;

            # Ensure files / date not specified.
            # (Note: Files mode will have put undef in @dates.)
            die 'Wait option given with files or dates' if @dates;

            $lim_date_initial = make_limited_datetime()->ymd('');
        }

        while (1) {
            if (defined $wait) {
                my $cur_date = make_datetime()->ymd('');
                my $lim_date = make_limited_datetime()->ymd('');

                # Exit if $lim_date changed.
                last if $lim_date ne $lim_date_initial;

                @dates = ($lim_date);
                push @dates, $cur_date unless $cur_date eq $lim_date;

                $log->debug('Wait-mode data entry for dates: ' . join(', ', @dates));
            }

            foreach my $date (@dates) {
                while (my ($instrument_name, $enter) = each %insts) {
                    my $is_acsis = ($instrument_name eq 'ACSIS');

                    my %extra_options = ();
                    $extra_options{'files'} = $files if defined $files;
                    $extra_options{'date'} = $date if defined $date;

                    $enter->prepare_and_insert(
                        calc_radec => ($find_bounds and $is_acsis),
                        %enter_options, %extra_options);
                }
            }

            last unless defined $wait;
            sleep $wait;
        }
    }
    else {
        # Merged "calc bounds" mode.

        die 'Entry from MongoDB not supported in calcbounds mode'
            if $mongo_src;

        die 'Wait not supported in calcbounds mode'
            if defined $wait;

        my @obs_types = qw/pointing science focus/;

        if (defined $files) {
            $skip_db_path = 1;
        }

        foreach my $date (@dates) {
            foreach my $enter (values %insts) {
                unless (defined $files) {
                    $files = $enter->calcbounds_find_files(
                        'avoid-db'    => $skip_db_path,
                        'date'        => $date,
                        obs_types => \@obs_types);

                    next unless scalar @$files;
                }

                my %extra_options = ();
                $extra_options{'files'} = $files;
                $extra_options{'date'} = $date if defined $date;

                $n_err += $enter->calcbounds_update_bound_cols(
                    obs_types => \@obs_types,
                    dry_run => $dry_run, skip_state => $skip_state,

                    # If we don't specify "avoid-db", calcbounds_find_files
                    # will only have searched the database, so there's no
                    # need to mark the files found in the transfer table.
                    skip_state_found => (not $skip_db_path),

                    %extra_options);
            }
        }
    }

    if (defined $debugfile and $debugfile ne '-') {
        $debug_fh->close();
    }

    exit 1 if $n_err;
};

exit;


sub get_instruments {
    my %opt = @_;
    my $debug_fh = delete $opt{'debug_fh'};

    my %class = (
        ACSIS => 'JSA::EnterData::ACSIS',
        'RxH3' => 'JSA::EnterData::RxH3',
        'SCUBA-2' => 'JSA::EnterData::SCUBA2',
    );

    # By default, use all instruments if none is specified.
    my $no_inst = not scalar grep {$opt{$_}} keys %class;

    my %inst;

    while (my ($key, $class) = each %class) {
        next unless $no_inst || $opt{$key};

        my $enter = $class->new(
            dict => "$FindBin::RealBin/import/data.dictionary",
            debug_fh => $debug_fh);

        $inst{$enter->instrument_name()} = $enter;
    }

    return %inst;
}

sub files_in_list {
    my ($file) = @_;

    my $log = Log::Log4perl->get_logger('');

    $log->error_die("Undefined file list was given.\n")
        unless defined $file;

    my @file;
    open my $fh, '<' , $file
        or $log->error_die('Cannot open ' . $file . " to read: $!\n");

    while (my $line = <$fh>) {
        next if $line =~ /^\s*$/
             || $line =~ /^\s*#/;

        $line =~ s/^\s+//;
        $line =~ s/\s+$//;

        push @file, $line;
    }

    close $fh
        or $log->error_die('Cannot close ' . $file . ": $!\n");

    $log->debug('Files found in file ', $file, ' : ', scalar @file);

    return \@file;
}

__END__

=head1 AUTHORS

=over 2

=item *

Anubhav E<lt>a.agarwal@jach.hawaii.eduE<gt>

=back

Copyright (C) 2006-2013 Science and Technology Facilities Council.
Copyright (C) 2015-2017 East Asian Observatory
All Rights Reserved.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or (at
your option) any later version.

This program is distributed in the hope that it will be useful,but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place,Suite 330, Boston, MA  02111-1307,
USA

=cut
