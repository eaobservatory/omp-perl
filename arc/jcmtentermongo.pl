#!/local/perl/bin/perl

=head1 NAME

jcmtentermongo - Read headers and store in MongoDB

=head1 SYNOPSIS

    jcmtentermongo [--dry-run] --date 20180101 --instrument SCUBA-2

=head1 DESCRIPTION

Reads the headers of data files for the specified instrument and date
and stores them in the MongoDB database.

=cut

use strict;
use warnings;

use FindBin;
use File::Spec;

use constant OMPLIB => File::Spec->catdir(
    "$FindBin::RealBin", File::Spec->updir, 'lib');
use lib OMPLIB;

BEGIN {
    $ENV{'OMP_CFG_DIR'} = File::Spec->catdir(OMPLIB, '../cfg')
        unless exists $ENV{'OMP_CFG_DIR'};
}

use JAC::Setup qw/jsa archiving/;

use Getopt::Long;
use Pod::Usage;
use Time::Piece;
use Log::Log4perl qw(:easy);

use OMP::FileUtils;
use OMP::EnterData::ACSIS;
use OMP::EnterData::RxH3;
use OMP::EnterData::SCUBA2;
use OMP::DB::JSA::MongoDB;

my ($help, $date, $instrument_name, $dry_run);
my $verbose = 0;

GetOptions(
    'help'         => \$help,
    'date=s'       => \$date,
    'instrument=s' => \$instrument_name,
    'dry-run'      => \$dry_run,
    'verbose+'     => \$verbose,
) or pod2usage('-exitval' => 2, '-verbose' => 1);

pod2usage('-exitval' => 1, '-verbose' => 2) if $help;

Log::Log4perl->easy_init(($verbose > 1) ? $TRACE : ($verbose ? $DEBUG : $INFO));
my $logger = get_logger();

die 'Date not specified' unless defined $date;
$date = Time::Piece->strptime($date, '%Y%m%d');

die 'Instrument not specified' unless defined $instrument_name;
my %instrument_class = (
    ACSIS => 'OMP::EnterData::ACSIS',
    SCUBA2 => 'OMP::EnterData::SCUBA2',
    RXH3 => 'OMP::EnterData::RxH3',
);
my $class = $instrument_class{uc($instrument_name)};
die "Instrument '$instrument_name' not recognized"
    unless defined $class;
my $instrument = $class->new(
    dict => File::Spec->catfile(OMPLIB, '../cfg/jcmt/data.dictionary'));

my $construct_missing = sub {
    return $instrument->construct_missing_headers(@_);
};

my $observations = OMP::FileUtils->files_on_disk(
    date => $date,
    instrument => $instrument->instrument_name());

$logger->debug('Creating MongoDB access object');
my $db = new OMP::DB::JSA::MongoDB();

my $n_err = 0;

for my $files (@$observations) {
    for my $file (@$files) {
        # Tidy up path by removing '..' references.
        my @comps = split '/', $file;
        my @clean = ();
        my $ndotdot = 0;
        foreach my $comp (reverse @comps) {
            if ($comp eq '..') {
                $ndotdot ++;
            }
            elsif ($ndotdot) {
                $ndotdot --;
            }
            else {
                push @clean, $comp;
            }
        }
        my $file = join '/', reverse @clean;

        # Check if file is present.
        unless (-e $file) {
            $logger->error("File $file not found");
            $n_err ++;
            next;
        }

        $logger->info("Processing file $file");

        eval {
            $db->put_raw_file(
                file => $file,
                extra => $instrument->read_file_extra($file),
                construct_missing => $construct_missing,
                dry_run => $dry_run);
        };

        if ($@) {
            $logger->error("Error putting file $file: $@");
            $n_err ++;
        }
    }
}

exit 1 if $n_err;
