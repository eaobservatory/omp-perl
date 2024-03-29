#!/local/perl/bin/perl
use strict;
use warnings;

use FindBin;
use constant OMPLIB => "$FindBin::RealBin/../lib";

use lib OMPLIB;

BEGIN {
    $ENV{'OMP_CFG_DIR'} = File::Spec->catdir(OMPLIB, '../cfg')
        unless exists $ENV{'OMP_CFG_DIR'};
}

use Time::Piece qw/:override/;
use List::Util qw/min max/;
use OMP::Config;
use File::Spec;

# Analyze log files
my $logdir;
eval {
    $logdir = OMP::Config->getData("logdir");
};
warn "Error obtaining logdir. Falling back: $@\n" if $@;
$logdir = '/tmp/ompLogs' unless defined $logdir;
my $log = File::Spec->catfile($logdir, "log.20030529");

# probably want to analyze a directory of log files...

open my $fh, '<', $log or die "Error opening log file: $!";

# Need to build up stats based on PID and datestamp
my %results;

# loop over each line
while (defined(my $line = <$fh>)) {
    next unless $line =~ /PID:/;

    # Split the line into data, PID and user
    if ($line =~ /^(.*)\s+PID:\s+(\d+)\s+User:\s*(.*)$/) {
        my $date = $1;
        my $pid = $2;
        my $user = $3;

        # Convert the date to an epoch. Note that the date is UT
        # Format is default date: Wed May 28 02:54:47 2003
        my $format = '%a %b %d %T %Y';
        my $tobj = Time::Piece->strptime($date, $format);
        if ($tobj->[Time::Piece::c_islocal]) {
            $tobj = gmtime($tobj->epoch + $tobj->tzoffset);
        }

        # Store the information
        unless (exists $results{$pid}) {
            $results{$pid} = {};
            $results{$pid}->{DATES} = [];
        }

        $results{$pid}->{USER} = $user;
        push @{$results{$pid}->{DATES}}, $tobj;
    }
}

close($fh);

# Now analyze (and generate histogram data)
my @hist;
my $binsize = 5;

for my $pid (sort keys %results) {
    # Calculate the elapsed time
    my @epochs = map {$_->epoch} @{$results{$pid}->{DATES}};
    my $min = min(@epochs);
    my $max = max(@epochs);
    my $duration = $max - $min;

    print "PID: $pid USER: " . $results{$pid}->{USER} . " Duration: $duration\n"
        if $duration >= 15;

    my $bin = int($duration / $binsize);
    $hist[$bin]++;
}

for my $i (0 .. $#hist) {
    my $axis = $i * $binsize;
    $hist[$i] = 0 if not defined $hist[$i];
    print "$axis: " . sprintf('%04d', $hist[$i]) . ' ' . ('*' x $hist[$i]) . "\n";
}
