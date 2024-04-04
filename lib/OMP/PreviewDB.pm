package OMP::PreviewDB;

=head1 NAME

OMP::PreviewDB - Fetch observation previews from the database

=cut

use strict;
use warnings;

use OMP::DateTools;
use OMP::Error;
use OMP::Info::Preview;

use parent qw/OMP::DB/;

our $PREVIEWTABLE = 'omppreview';

=head1 METHODS

=over 4

=item queryPreviews

Query the database for previews.

    $result = $db->queryPreviews($query);

The query is specified as an C<OMP::PreviewQuery> object.

=cut

sub queryPreviews {
    my $self = shift;
    my $query = shift;

    my $sql = $query->sql($PREVIEWTABLE);

    my $ref = $self->_db_retrieve_data_ashash($sql);

    my @result;
    foreach my $row (@$ref) {
        push @result, OMP::Info::Preview->new(
            date => OMP::DateTools->parse_date($row->{'date'}),
            date_modified => OMP::DateTools->parse_date($row->{'date_modified'}),
            group => $row->{'group'},
            filename => $row->{'filename'},
            filesize => $row->{'filesize'},
            instrument => $row->{'instrument'},
            md5sum => $row->{'md5sum'},
            runnr => $row->{'runnr'},
            size => $row->{'size'},
            subscan_number => $row->{'subscan_number'},
            subsystem_number => $row->{'subsystem_number'},
            suffix => $row->{'suffix'},
            telescope => $row->{'telescope'},
        );
    }

    return \@result;
}

=item setPreviews

Add or update the given preview information.

Requires a reference to an array of C<OMP::Info::Preview> objects.

    $db->setPreviews(\@previews);

=cut

sub setPreviews {
    my $self = shift;
    my $previews = shift;

    die 'Not an array reference' unless 'ARRAY' eq ref $previews;

    my $dbh = $self->_dbhandle();
    my $sth = $dbh->prepare(
        'INSERT INTO `' . $PREVIEWTABLE . '`'
        . ' (`filename`, `telescope`, `date`, `instrument`, `runnr`, `group`'
        . ', `subscan_number`, `subsystem_number`, `suffix`'
        . ', `size`, `filesize`, `md5sum`, `date_modified`)'
        . ' VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
        . ' ON DUPLICATE KEY UPDATE'
        . ' `telescope`=?, `date`=?, `instrument`=?, `runnr`=?, `group`=?'
        . ', `subscan_number`=?, `subsystem_number`=?, `suffix`=?'
        . ', `size`=?, `filesize`=?, `md5sum`=?, `date_modified`=?');

    # Start transaction.
    $self->_db_begin_trans();
    $self->_dblock();

    # Insert / update entries.
    foreach my $preview (@$previews) {
        die 'Entry is not an OMP::Info::Preview'
            unless eval {$preview->isa('OMP::Info::Preview')};

        my $key = $preview->filename();
        my @val = (
            $preview->telescope(),
            $preview->date()->strftime('%Y-%m-%d %T'),
            $preview->instrument(),
            $preview->runnr(),
            ($preview->group() ? 1 : 0),
            $preview->subscan_number(),
            $preview->subsystem_number(),
            $preview->suffix(),
            $preview->size(),
            $preview->filesize(),
            $preview->md5sum(),
            $preview->date_modified()->strftime('%Y-%m-%d %T'),
        );

        $sth->execute($key, @val, @val)
            or throw OMP::Error::DBError("Error inserting/updating table $PREVIEWTABLE: $DBI::errstr");
    }

    # End transaction.
    $self->_dbunlock();
    $self->_db_commit_trans();
}

1;

__END__

=back

=head1 COPYRIGHT

Copyright (C) 2024 East Asian Observatory
All Rights Reserved.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful,but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc.,51 Franklin
Street, Fifth Floor, Boston, MA  02110-1301, USA

=cut
