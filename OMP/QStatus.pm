=head1 NAME

OMP::QStatus - Observing queue status utility module

=head1 SUBROUTINES

=over 4

=cut

package OMP::QStatus;

use strict;

use base 'Exporter';

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
    my $country = $opt{'country'};
    my $semester = $opt{'semester'};
    my $full_day = $opt{'full_day'};

    die 'telescope not specified' unless defined $telescope;

    # Create MSB database instance
    my $backend = new OMP::DBbackend();
    my $db = new OMP::MSBDB(DB => $backend);

    # The hour range for queries should be restricted by the freetimeut
    # parameter from the config system, unless the -fullday command line
    # switch was supplied.
    my $today = OMP::DateTools->today(1);
    my ($utmin, $utmax);
    if ($full_day) {
        $utmin = 0;
        $utmax = 23.9999;
    }
    else {
      ($utmin, $utmax) = OMP::Config->getData('freetimeut',
                                              telescope => $telescope);

      # parse the values, get them back as date objects
      ($utmin, $utmax) = OMP::DateSun->_process_freeut_range($telescope,
                                                             $today,
                                                             $utmin, $utmax);

      # easier for now to convert them back to an hour
      $utmin = $utmin->hour;
      $utmax = $utmax->hour + ($utmax->min > 0 ? 1 : 0);
    }
    $today = $today->ymd();

    my %projq;
    my %projmsb;
    my %projinst;

    # Run a simulated set of queries to determine which projects
    # have MSBs available
    for my $hr ($utmin..$utmax) {
        my $refdate = $today . "T". sprintf("%02d",$hr) .":00";

        # Form query object via XML
        my $query = new OMP::MSBQuery(XML => '<MSBQuery>' .
            '<telescope>' . $telescope . '</telescope>' .
            (defined $country ? '<country>' . $country . '</country>' : '') .
            (defined $semester ? '<semester>' . $semester . '</semester>' : '') .
            '<date>' . $refdate . '</date>' .
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

    return (\%projq, \%projmsb, \%projinst, $utmin, $utmax);
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
