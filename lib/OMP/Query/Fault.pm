package OMP::Query::Fault;

=head1 NAME

OMP::Query::Fault - Class representing an XML OMP query of the fault database

=head1 SYNOPSIS

    $query = OMP::Query::Fault->new(XML => $xml);
    $sql = $query->sql($faulttable, $resptable);

=head1 DESCRIPTION

This class can be used to process OMP fault queries.
The queries are usually represented as XML.

=cut

use 5.006;
use strict;
use warnings;
use Carp;

# External modules
use OMP::Error;
use OMP::General;
use OMP::Range;

# Inheritance
use base qw/OMP::Query/;

# Package globals

our $VERSION = '2.000';

=head1 METHODS

=head2 General Methods

=over 4

=item B<sql>

Returns an SQL representation of the XML Query using the specified
database table.

    $sql = $query->sql($faulttable, $resptable, %options);

Returns undef if the query could not be formed.

The SQL returned by this query will include an entry for each response
that matches (in the joined fault and response table).  This needs to
be the case since a query on date or author must include the fault
response table but it is therefore possible to match partial
faults. In order to overcome this and to obtain a full fault
(including responses) the data returned by the query must be sifted
for fault IDs and the responses must be retrieved by additional
queries to the response table. [we could of course create a temporary
table with just the faultids and then do an internal query that
gets all the faults with that faultid]

=cut

sub sql {
    my $self = shift;

    throw OMP::Error::DBMalformedQuery(
        "sql method invoked with incorrect number of arguments\n")
        unless scalar(@_) >= 2;

    my ($faulttable, $resptable, %options) = @_;

    # Generate the WHERE clause from the query hash
    # Note that we ignore elevation, airmass and date since
    # these can not be dealt with in the database at the present
    # time [they are used to calculate source availability]
    # Disabling constraints on queries should be left to this
    # subclass
    my $subsql = $self->_qhash_tosql();

    # In principal we do not need to join the response table
    # in the initial query if we are only looking for general
    # information such as fault id or fault category.
    # Since it is difficult to spot whether a response join
    # is required we explicitly prefix "R." on all response
    # fields to make it obvious.

    # Reasonable join queries could be for "author", "isfault" or
    # "date". A query on "text" would required LIKE pattern matching but
    # should be possible. [isfault can be used to search for all faults
    # responded to by person X or all faults filed by person X]
    my $r_table = '';
    if ($subsql =~ /\bR\.\w/) {  # Look for R. field
        $r_table = " JOIN $resptable R ON R.faultid = F.faultid ";
    }

    # Construct the the where clause. Depends on which
    # additional queries are defined
    my $where = $subsql ? " WHERE $subsql " : '';

    # Determine if we have "relevance" information to prepare.
    my (@frel, @rrel);
    push @{/\bR\.\w/ ? \@rrel : \@frel}, $_ foreach $self->_qhash_relevance();
    my ($frel, $rrel) = map {(scalar @$_) ? (join ' + ', @$_) : '0'} (\@frel, \@rrel);

    # Now need to put this SQL into the template query
    # This returns a row per response
    # So will duplicate static fault info
    my $select = $options{'no_text'}
        ? "F.*, R.respid, R.date, R.author, R.isfault, R.respnum, R.flag"
        : "F.*, R.*";
    $select .= ", $frel + SUBSEL.relevance AS relevance";

    my $sql = "SELECT $select FROM $faulttable F
         JOIN $resptable R ON F.faultid = R.faultid
         JOIN (
             SELECT F.faultid, SUM($rrel) AS relevance
             FROM $faulttable F $r_table
             $where
             GROUP BY F.faultid
         ) AS SUBSEL ON F.faultid = SUBSEL.faultid
         ORDER BY R.isfault desc, R.date";

    return "$sql\n";
}

=item B<_root_element>

Class method that returns the name of the XML root element to be
located in the query XML. This changes depending on whether we
are doing an MSB or Project query.
Returns "FaultQuery" by default.

=cut

sub _root_element {
  return "FaultQuery";
}

=item B<_post_process_hash>

Do table specific post processing of the query hash. For projects this
mainly entails converting range hashes to C<OMP::Range> objects (via
the base class), upcasing some entries and converting "status" fields
to queries on "remaining" and "pending" columns.

  $query->_post_process_hash( \%hash );

Also converts abbreviated form of project name to the full form
recognised by the database (this is why a telescope is required).

=cut

sub _post_process_hash {
    my $self = shift;
    my $href = shift;

    # Do the generic pre-processing
    $self->SUPER::_post_process_hash($href);

    # Loop over each key
    for my $key (keys %$href) {
        # Skip private keys
        next if $key =~ /^_/;

        # Protect against rounding errors
        # Not sure we need this so leave it out for now
        # if ($key eq 'faultid') {
        # Need to loop over each fault
        # $href->{$key} = [map {
        #     OMP::Range->new(Min => ($_ - 0.0005), Max => ($_ + 0.0005))
        # } @{$href->{$key}}];
    }

    # These entries are in more than one table so we have to
    # explicitly choose the Fault table
    for (qw/faultid/) {
        if (exists $href->{$_}) {
            my $key = "F.$_";
            $href->{$key} = $href->{$_};
            delete $href->{$_};
        }
    }

    # These entries must be forced to come from Response table
    for (qw/author date isfault text respid/) {
        if (exists $href->{$_}) {
            my $key = "R.$_";
            $href->{$key} = $href->{$_};
            delete $href->{$_};
            $href->{'_attr'}->{$key} = delete $href->{'_attr'}->{$_}
                if exists $href->{'_attr'}->{$_};
        }
    }

    # These are TEXT columns so need special kluging
    for (qw/ subject R.text /) {
        if (exists $href->{$_}) {
            my $prefix = 'TEXTFIELD__';
            $prefix .= 'BOOLEAN__'
                if exists $href->{'_attr'}->{$_}
                and exists $href->{'_attr'}->{$_}->{'mode'}
                and $href->{'_attr'}->{$_}->{'mode'} eq 'boolean';
            my $key = $prefix . $_;
            $href->{$key} = $href->{$_};
            delete $href->{$_};
        }
    }

    # These entries have a different column name in the table,
    # so replace them with the actual column name
    for (qw/system/) {
        if (exists $href->{$_}) {
            my $key = "f" . $_;
            $href->{$key} = $href->{$_};
            delete $href->{$_};
        }
    }

    # Remove attributes since we dont need them anymore
    delete $href->{_attr};
}

1;

__END__

=back

=head1 Query XML

The Query XML is specified as follows:

=over 4

=item B<FaultQuery>

The top-level container element is E<lt>FaultQueryE<gt>.

=item B<Equality>

Elements that contain simply C<PCDATA> are assumed to indicate
a required value.

    <instrument>SCUBA</instrument>

Would only match if C<instrument=SCUBA>.

=item B<Ranges>

Elements that contain elements C<max> and/or C<min> are used
to indicate ranges.

    <elevation><min>30</min></elevation>
    <priority><max>2</max></priority>

Why dont we just use attributes?

    <priority max="2" /> ?

Using explicit elements is probably easier to generate.

Ranges are inclusive.

=item B<Multiple matches>

Elements that contain other elements are assumed to be containing
multiple alternative matches (C<OR>ed).

    <instruments>
        <instrument>CGS4</instrument>
        <instrument>IRCAM</instrument>
    </isntruments>

C<max> and C<min> are special cases. In general the parser will
ignore the plural element (rather than trying to determine that
"instruments" is the plural of "instrument"). This leads to the
dropping of plurals such that multiple occurrence of the same element
in the query represent variants directly.

    <name>Tim</name>
    <name>Kynan</name>

would suggest that names Tim or Kynan are valid. This also means

    <instrument>SCUBA</instrument>
    <instruments>
        <instrument>CGS4</instrument>
    </instruments>

will select SCUBA or CGS4.

Neither C<min> nor C<max> can be included more than once for a
particular element. The most recent values for C<min> and C<max> will
be used. It is also illegal to use ranges inside a plural element.

=back

=head1 SEE ALSO

L<OMP::Query>, L<OMP::Query::MSB>

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
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
