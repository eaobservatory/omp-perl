#!/local/perl/bin/perl

=head1 NAME

qstatus - List current status of the observing queue

=head1 SYNOPSIS

    qstatus -tel ukirt -country uk [-semester 10b -fullday]

=head1 DESCRIPTION

Writes the current status of the observing queue to STDOUT.

=head1 OPTIONS

The following options are supported:

=over 4

=item B<-tel>

Specify the telescope to use for the report. If the telescope can
be determined from the domain name it will be used automatically.
If the telescope can not be determined from the domain and this
option has not been specified a popup window will request the
telescope from the supplied list (assume the list contains more
than one telescope).

=item B<-country>

Country to query. Defaults to all countries.

=item B<-fullday>

Give results for a full 24 hour period rather than the
telescope's normal operating hours.

=item B<-semester>

Semester to query. Defaults to current semester.

=item B<--affiliation>

Affiliation code.  If specified, only projects with this affiliation
will be considered.

=item B<-version>

Report the version number.

=item B<-help>

A help message.

=item B<-man>

This manual page.

=back

=cut

use 5.006;
use strict;
use warnings;

use Getopt::Long;
use Pod::Usage;

# Locate the OMP software through guess work
use FindBin;
use lib "$FindBin::RealBin/../lib";

# OMP classes
use OMP::General;
use OMP::DB::Backend;
use OMP::QStatus qw/query_queue_status/;
use Time::Piece qw/:override/;

our $DEBUG = 0;
our $VERSION = '2.000';

# Options
my ($help, $man, $version, $tel, $country, $semester, $affiliation, $full_day);
my $status = GetOptions(
    "help" => \$help,
    "man" => \$man,
    "version" => \$version,
    "country=s" => \$country,
    "semester=s" => \$semester,
    'affiliation=s' => \$affiliation,
    "tel=s" => \$tel,
    'fullday' => \$full_day,
);

pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

if ($version) {
    print "ompqstatus - Display current queue status\n";
    print "Version: ", $VERSION, "\n";
    exit;
}

my $telescope = (defined $tel) ? uc($tel) : undef;

unless (defined $telescope) {
    require Term::ReadLine;
    my $term = Term::ReadLine->new('Gather queue parameters');

    $telescope = OMP::General->determine_tel($term);
    die "Unable to determine telescope. Exiting.\n" unless defined $telescope;
    die "Unable to determine telescope [too many choices]. Exiting.\n"
        if ref $telescope;
}

# Calculate localtime to GMT offset (hours)
my $tzoffset = gmtime()->tzoffset->hours;

print "Analyzing "
    . (defined $country ? uc($country) . ' ' : '')
    . "queue status.\n";

my (%projq, %projmsb, %projinst, $utmin, $utmax);
do {
    my ($q, $m, $i);
    ($q, $m, $i, $utmin, $utmax) = query_queue_status(
        telescope => $telescope,
        country => $country,
        semester => $semester,
        affiliation => $affiliation,
        full_day => $full_day,
    );
    %projq = %$q;
    %projmsb = %$m;
    %projinst = %$i;
};

print "For UT hours $utmin to $utmax:\n";

# Now go through the project hits and work out availability ranges
# and total number of MSBs available in the period
my %projects;

for my $p (keys %projq) {
    my @upstatus = @{$projq{$p}};

    my $uptime;
    my @intervals;

    # make sure we loop one more time than we need to
    # so that we can handle the case where we are observable in the last
    # slot
    for my $hr (0 .. ($#upstatus + 1)) {
        $upstatus[$hr] = 0 unless defined $upstatus[$hr];

        # skip if this is not up and we are not in an up period
        next if $upstatus[$hr] == 0 && !defined $uptime;

        if ($upstatus[$hr] != 0) {
            # this project is observable
            unless (defined $uptime) {
                # first time this is observable so register this fact
                $uptime = $hr;
            }
        }
        elsif (defined $uptime) {
            # this project is not observable now but was previously
            push @intervals, OMP::Range->new(Min => $uptime, Max => ($hr - 1));
            undef $uptime;
        }
        else {
            die "Strange error with $p availability calculation\n";
        }
    }

    # need to deal with the case where two intervals are contiguous
    # because of wrapping. We know the ranges are in time order so
    # we just need to look at the first and last
    if (scalar(@intervals > 1)) {
        if ($intervals[0]->min == 0 && $intervals[-1]->max == 23) {
            $intervals[0]->min($intervals[-1]->min);

            # remove the last interval
            pop @intervals;
        }
    }

    $projects{$p}{availability} = \@intervals;

    # Available MSBs
    $projects{$p}{msb_count} = scalar keys %{$projmsb{$p}};

    # instruments
    $projects{$p}{instruments} = [keys %{$projinst{$p}}];
}

# Now populate the project hash with project details
my $backend = OMP::DB::Backend->new();
my $projdb = OMP::ProjDB->new(DB => $backend,);

for my $p (keys %projects) {
    $projdb->projectid($p);
    my $proj = $projdb->projectDetails('object');
    $projects{$p}{'info'} = $proj;
}

# in order to dynamically size the fields for output, we need to work
# out all the content before printing it.

my @rows;
for my $p (sort {
            $projects{$a}{info}->tagpriority <=> $projects{$b}{info}->tagpriority
        } keys %projects) {
    my %data = %{$projects{$p}};
    my $proj = $data{info};

    # Need projectid
    my $project = $proj->projectid;

    # PI
    my $pi = $proj->pi->userid;

    # instruments
    my $inst = join '/', @{$data{instruments}};

    # conditions
    my $cond = $proj->conditionstxt;

    # TAG rank
    my $tag = $proj->tagpriority;

    # Support
    my @sup = $proj->support;
    my $support = (@sup ? $sup[0]->userid : 'NONE');

    # MSB count
    my $msbcount = $data{msb_count};

    # % complete
    my $compl = $proj->percentComplete;

    # availability
    # Convert to localtime before rendering
    my @avlocal;
    for my $av (@{$data{availability}}) {
        # get the min/max
        my ($min, $max) = $av->minmax;

        if (defined $min) {
            if ($min == $utmin) {
                # lower bound
                $min = undef;
            }
            else {
                $min += $tzoffset;
                $min = _foldhr($min);
            }
        }

        if (defined $max) {
            if ($max == $utmax) {
                # upper bound hit
                $max = undef;
            }
            else {
                $max += $tzoffset;
                $max = _foldhr($max);
            }
        }

        my $text;
        if (defined $max && defined $min && $min == $max) {
            # make sure that x-x is really an interval of 'x'
            $text = $max;
        }
        elsif (!defined $max && !defined $min) {
            $text = 'all';
        }
        else {
            my $intervl = OMP::Range->new(Min => $min, Max => $max);
            $text = "$intervl";
        }

        push @avlocal, $text;
    }

    my $avail = join ',', @avlocal;

    # Store the content
    push @rows, {
        project => $project,
        pi => $pi,
        inst => $inst,
        conditions => $cond,
        rank => $tag,
        ss => $support,
        'msb#' => $msbcount,
        '%com' => $compl,
        avail => $avail,
    };
}

# This next section is generic code useful for creating fixed width
# tables using a dynamic width calculation

# Need a hash containing the default types for the printf
# note that 's' will be converted to the corresponding size
# 'd' will translate to the width of the column heading
# or length of int() the number
my %types = (
    project => 's',
    pi => 's',
    inst => 's',
    conditions => 's',
    rank => 'd',
    ss => 's',
    'msb#' => 'd',
    '%com' => 'd',
    avail => 's',
);

# column order (split because of warning about comment char in qw)
my @headings = (
    qw/project pi inst conditions rank ss/,
    'msb#',
    qw/%com avail/);

# find the column widths for all types that are missing a width specifier
# and begin forming the printf format
my $hfmt = '';
my $rfmt = '';
for my $h (@headings) {
    # see if we have a hard-wired width
    my $len;
    my $fmt;
    if ($types{$h} =~ /(\d+)/) {
        $len = $1;
        $fmt = $types{$h};
    }
    else {
        # default length is the column heading
        $len = length($h);

        # now get the length of the rows
        my $iss = ($types{$h} eq 's');
        my $isd = ($types{$h} eq 'd');

        for my $r (@rows) {
            my $l;
            if ($iss) {
                $l = length($r->{$h});
            }
            elsif ($isd) {
                $l = length(int($r->{$h}));
            }
            $len = $l if $l > $len;
        }

        $fmt = $len . $types{$h};
    }

    # The format
    if ($types{$h} =~ /s$/) {
        $hfmt .= ' %-' . $fmt;
        $rfmt .= ' %-' . $fmt;
    }
    elsif ($types{$h} =~ /d$/) {
        # for numeric fields we need a string heading
        $hfmt .= ' %-' . $len . 's';
        $rfmt .= ' %' . $fmt;
    }
    else {
        $hfmt .= ' %s';
        $rfmt .= ' %' . $fmt;
    }

}

# remove leading space due to algorithm short cut
$hfmt =~ s/^\s//;
$rfmt =~ s/^\s//;

# output the rows
printf "$hfmt\n", @headings;
for my $r (@rows) {
    my %rhash = %$r;
    printf "$rfmt\n", @rhash{@headings};
}

print "\nNotes\n";
print "[1] Conditions are project TAG conditions, not MSB constrained conditions\n";
print "[2] MSB count reflects the MSB returned from queries and not the number of active MSBs in the science program.\n";
print "[3] Availability is in localtime integer hours\n";

exit;

# remap a time to 0-24hr
sub _foldhr {
    my $hr = shift;

    if ($hr >= 24) {
        $hr -= 24;
    }
    elsif ($hr < 0) {
        $hr += 24;
    }
    return $hr;
}

__END__

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

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
