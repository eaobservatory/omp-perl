#!/usr/bin/env perl

# This is an example script showing one possible way to produce PDF
# reports for given collections of faults.  The example is currently
# set up to report leaks and spills at JCMT and at JAC in Hilo.

use OMP::Display;
use OMP::Fault;
use OMP::FaultUtil;
use OMP::FaultServer;

use strict;

# Specify text phrases to search for.

my @query_phrases = (
    'spill',
    'leak',
);

# List of Hilo locations.

my @hilo_locations = (
    OMP::Fault::JAC,
    OMP::Fault::TOILET,
    OMP::Fault::OFFICE,
    OMP::Fault::LIBRARY,
    OMP::Fault::COMP_ROOM,
    OMP::Fault::MEETING_ROOM,
    OMP::Fault::LAB,
    OMP::Fault::WORKSHOP,
    OMP::Fault::VEHICLE_BAY,
    OMP::Fault::CAR_PARK,
    OMP::Fault::SYSTEMOTHER,
);

# List of the queries to perform.  If an entry is a hashref
# (eg \@hilo_locations) then it should be turned into a query
# for any of the entries listed.

my @queries = (
    {
        category => 'JCMT',
    },
    {
        category => 'FACILITY',
        'system' => OMP::Fault::JCMT,
    },
    {
        category => 'SAFETY',
        location => OMP::Fault::JCMT,
    },
    {
        category => 'FACILITY',
        'system' => \@hilo_locations,
    },
    {
        category => 'SAFETY',
        location => \@hilo_locations,
    },
);

# Loop over the query types.

foreach my $query (@queries) {
    foreach my $phrase (@query_phrases) {
        # Report name (used as part of file name).
        my $name = join('_', (map {ref $query->{$_} ? 'MULTIPLE' : $query->{$_}}
                                  sort keys %$query), $phrase);

        # Query XML.
        my $xml = join("\n",
            '<FaultQuery>',
            (map {query_component($_, $query->{$_})} keys %$query),
            '<text>' . $phrase . '</text>',
            '</FaultQuery>');

        # Perform the query.
        query_to_pdf($name, $xml);
    }
}

# Expand a query parameter and single or multiple values into XML.

sub query_component {
    my $name = shift;
    my $value = shift;

    $value = [$value] unless ref $value;

    return join("\n", map {'<' . $name . '>' . $_ . '</' . $name . '>'} @$value);
}

# Perform the query, write PS and convert it to PDF.

sub query_to_pdf {
    my $name = shift;
    my $xml = shift;

    my $faults = OMP::FaultServer->queryFaults($xml, 'object');
    my $toprint = '';

    foreach my $f (@$faults) {
        # Get the subject and fault ID
        my $subject = $f->subject;
        my $faultid = $f->id;

        print "$name: $faultid $subject\n";

        # Get the raw fault text
        my $text = OMP::FaultUtil->format_fault($f, 1);

        # Convert it to plain text
        my $plaintext = OMP::Display->html2plain($text);

        $toprint .= "Fault ID: $faultid\nSubject: $subject\n\n$plaintext\f";
    }

    # Set up output. Should check that enscript can be found.
    my $printcom =  '/usr/bin/enscript -G -fCourier10 -b"Faults" -o ' . $name . '.ps';
    open(my $PRTHNDL, '|-', $printcom);
    print $PRTHNDL $toprint;
    close($PRTHNDL);

    # Convert to PDF and remove the PS version.
    system('ps2pdf ' . $name . '.ps');
    system('rm ' . $name . '.ps');
}
