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
use OMP::DBbackend;
use OMP::MSBDB;
use OMP::MSBQuery;

our @EXPORT_OK = qw/query_queue_status/;

=item query_queue_status(%opt)

=cut

sub query_queue_status {
    my %opt = @_;

    my $telescope = $opt{'telescope'};
    die 'telescope not specified' unless defined $telescope;

    # Create MSB database instance
    my $backend = new OMP::DBbackend();
    my $db = new OMP::MSBDB(DB => $backend);

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
      ($utmin, $utmax) = OMP::Config->getData('freetimeut',
                                              telescope => $telescope);

      # parse the values, get them back as date objects
      ($utmin, $utmax) = OMP::DateSun->_process_freeut_range($telescope,
                                                             $today,
                                                             $utmin, $utmax);

      # Expand range to hour boundaries.
      $utmin -= ONE_MINUTE * $utmin->min() if $utmin->min() > 0;
      $utmax += ONE_MINUTE * (60 - $utmax->min()) if $utmax->min() > 0;
    }

    $utmin = gmtime($utmin->epoch());
    $utmax = gmtime($utmax->epoch());

    my %projq;
    my %projmsb;
    my %projinst;

    # Run a simulated set of queries to determine which projects
    # have MSBs available
    for (my $refdate = $utmin; $refdate <= $utmax; $refdate += ONE_HOUR) {
        my $hr = $refdate->hour();

        # Form query object via XML
        my $query = new OMP::MSBQuery(XML => '<MSBQuery>' .
            '<telescope>' . $telescope . '</telescope>' .
            (exists $opt{'country'}
                ? '<country>' . $opt{'country'} . '</country>'
                : '') .
            (exists $opt{'semester'}
                ? '<semester>' . $opt{'semester'} . '</semester>'
                : '') .
            (exists $opt{'instrument'}
                ? '<instrument>'. $opt{'instrument'} . '</instrument>'
                : '') .
            (exists $opt{'tau'}
                ? '<tau>' . $opt{'tau'} . ' </tau>'
                : '') .
            '<date>' . $refdate->datetime() . '</date>' .
            '</MSBQuery>');

        my @results = $db->queryMSB($query, 'object');

        for my $msb (@results) {
            my $p = $msb->projectid();
            # init array
            $projq{$p} = [map {0} (0..23)] unless exists $projq{$p};

            # indicate a hit for this project with this MSB
            $projq{$p}[$hr] ++;

            # store the MSB id so that we know how many MSBs were
            # observable in the period
            $projmsb{$p}{$msb->checksum()} ++;

            # Store the instrument information
            my $inst = $msb->instrument();
            for my $i (split(/\//,$inst)) {
                $projinst{$p}{$i} ++;
            }
        }
    }

    return (\%projq, \%projmsb, \%projinst, $utmin->hour(), $utmax->hour());
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
