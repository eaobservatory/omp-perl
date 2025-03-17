=head1 NAME

OMP::QStatus - Observing queue status utility module

=head1 SUBROUTINES

=over 4

=cut

package OMP::QStatus;

use strict;

use base 'Exporter';

use Time::Piece;
use Time::Seconds qw/ONE_MINUTE ONE_HOUR/;

use OMP::Config;
use OMP::DateTools;
use OMP::DateSun;
use OMP::DB::MSB;
use OMP::Query::MSB;
use OMP::DB::ProjAffiliation qw/@AFFILIATIONS/;

our @EXPORT_OK = qw/query_queue_status group_queue_status/;

=item query_queue_status(%opt)

Perform a series of MSB queries in order to generate information about
the status of the observing queue.

Contains code extracted from the F<client/qstatus.pl> script.

Options:

=over 4

=item DB

Database backend object.  Required.

=item telescope

Required.

=item date

Optional Time::Piece object.

=item full_day

If specified, query for the whole day rather than usual observing time
as determined by C<OMP::DateSun::_process_freeut_range>.

=item country

Optional.

=item semester

Optional.

=item instrument

Optional.

=item tau

Optional.

=item affiliation

Affiliation code (optional).

=back

Returns a reference to a hash of projects giving hashes of MSBs
by checksum, along with start and end times as Time::Piece objects.

    my ($proj_msb, $utmin, $utmax) = query_queue_status(%opt);

B<Note:> currently generates the queue information by performing queries
at one hour increments.

=cut

sub query_queue_status {
    my %opt = @_;

    my $telescope = $opt{'telescope'};
    die 'telescope not specified' unless defined $telescope;

    # Create MSB database instance
    my $backend = $opt{'DB'};
    my $db = OMP::DB::MSB->new(DB => $backend);

    # Are we searching for a particular affiliation?  If so read the list
    # of project affiliations.
    my $affiliation = $opt{'affiliation'};
    my $affiliations = undef;
    if ($affiliation) {
        die 'Unknown affiliation "' . $affiliation .'"'
            unless grep {$_ eq $affiliation} @AFFILIATIONS;

        my $affiliation_db = OMP::DB::ProjAffiliation->new(DB => $backend);
        $affiliations = $affiliation_db->get_all_affiliations();
    }

    # The hour range for queries should be restricted by the freetimeut
    # parameter from the config system, unless the -fullday command line
    # switch was supplied.
    my $today = exists $opt{'date'} ? $opt{'date'} : OMP::DateTools->today(1);
    my ($utmin, $utmax);
    if ($opt{'full_day'}) {
        $utmin = OMP::DateTools->parse_date($today->ymd() . 'T00:00:00');
        $utmax = OMP::DateTools->parse_date($today->ymd() . 'T23:59:59');
    }
    else {
        my $datesun = OMP::DateSun->new;
        ($utmin, $utmax) = $datesun->get_freeut_range(
                tel => $telescope, date => $today);

        # Expand range to hour boundaries.
        $utmin -= ONE_MINUTE * $utmin->min() if $utmin->min() > 0;
        $utmax += ONE_MINUTE * (60 - $utmax->min()) if $utmax->min() > 0;
    }

    $utmin = gmtime($utmin->epoch());
    $utmax = gmtime($utmax->epoch());

    my %msb;

    # Run a simulated set of queries to determine which projects
    # have MSBs available

    my %query_hash = (
        telescope => $telescope,
        (exists $opt{'country'}
            ? (country => $opt{'country'})
            : ()),
        (exists $opt{'semester'}
            ? (semester => $opt{'semester'})
            : ()),
        (exists $opt{'instrument'}
            ? (instrument => $opt{'instrument'})
            : ()),
        (exists $opt{'tau'}
            ? (tau => $opt{'tau'})
            : ()),
    );

    for (my $refdate = $utmin; $refdate <= $utmax; $refdate += ONE_HOUR) {
        my $hr = $refdate->hour();

        # Form query object
        my $query = OMP::Query::MSB->new(
            HASH => {%query_hash, date => $refdate->datetime()});

        my @results = $db->queryMSB($query);

        for my $msb (@results) {
            my $p = $msb->projectid();

            # If we have an affiliation constraint, apply it now.
            if (defined $affiliation) {
                next unless exists $affiliations->{$p}->{$affiliation};
            }

            my $checksum = $msb->checksum();

            $msb{$p} = {} unless exists $msb{$p};

            unless (exists $msb{$p}->{$checksum}) {
                $msb->extra->{'qstatus_hours'} = [map {0} (0..23)];
                $msb{$p}->{$checksum} = $msb;
            }
            $msb{$p}->{$checksum}->extra->{'qstatus_hours'}->[$hr] ++;
        }
    }

    return (\%msb, $utmin, $utmax);
}

=item group_queue_status

Convert the hash returned by C<query_queue_status>
to the data structures originally accumulated by
F<client/qstatus.pl> (except that the values of C<$projinst>
are now MSBs rather than hits (MSBs * hours)).

    ($projq, $projmsb, $projinst) = query_queue_status($proj_msb);

=cut

sub group_queue_status {
    my $proj_msb = shift;

    my %projq;
    my %projmsb;
    my %projinst;

    foreach my $p (keys %$proj_msb) {
        my $msbs = $proj_msb->{$p};
        foreach my $checksum (keys %$msbs) {
            my $msb = $msbs->{$checksum};

            # init array
            $projq{$p} = [map {0} (0..23)] unless exists $projq{$p};

            # indicate a hit for this project with this MSB
            my $hours = $msb->extra->{'qstatus_hours'};
            $projq{$p}[$_] += $hours->[$_] foreach (0 .. 23);

            # store the MSB id so that we know how many MSBs were
            # observable in the period
            $projmsb{$p}{$checksum} ++;

            # Store the instrument information
            my $inst = $msb->instrument();
            for my $i (split(/\//,$inst)) {
                $projinst{$p}{$i} ++;
            }
        }
    }

    return (\%projq, \%projmsb, \%projinst);
}

1;

__END__

=back

=head1 COPYRIGHT

Copyright (C) 2004-2005 Particle Physics and Astronomy Research Council.
Copyright (C) 2015 East Asian Observatory.
All Rights Reserved.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the
Free Software Foundation, Inc., 59 Temple Place, Suite 330,
Boston, MA  02111-1307  USA

=cut
