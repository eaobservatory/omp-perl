package OMP::ShiftQuery;

=head1 NAME

OMP::ShiftQuery - Class representing queries of the shift log table.

=head1 SYNOPSIS

$query = new OMP::ShiftQuery( XML => $xml );
  $sql = $query->sql( $table );

=head1 DESCRIPTION

This class can be used to process OMP shift log queries. The queries
are usually represented as XML.

=cut

use 5.006;
use strict;
use warnings;
use Carp;

# External modules
use OMP::Error;
use OMP::General;

# Inheritance
use base qw/ OMP::DBQuery /;

# Package globals

our $VERSION = (qw$Revision$ )[1];

=head1 METHODS

=head2 General Methods

=over 4

=item B<sql>

Returns an SQL representation of the XML Query using the specified
database table.

  $sql = $query->sql( $table )

Returns undef if the query could not be formed.

The results can include more than one row per shift log entry.
It is up to the caller to reorganize the resulting data into
data structures indexed by single MSB IDs with multiple comments.

=cut

sub sql {
  my $self = shift;

  throw OMP::Error::DBMalformedQuery("sql method invoked with incorrect number of arguments\n")
    unless scalar(@_) == 1;

  my ($donetable) = @_;

  # Generate the WHERE clause from the query hash
  # Note that we ignore elevation, airmass and date since
  # these can not be dealt with in the database at the present
  # time [they are used to calculate source availability]
  # Disabling constraints on queries should be left to this
  # subclass
  my $subsql = $self->_qhash_tosql();
  # Construct the the where clause. Depends on which
  # additional queries are defined
  my @where = grep { $_ } ( $subsql);
  my $where = '';
  $where = " WHERE " . join( " AND ", @where)
    if @where;

  # Now need to put this SQL into the template query
  # This returns a row per response
  # So will duplicate static fault info
  my $sql = "(SELECT * FROM $donetable $where)";

  return "$sql\n";

}

=back

=begin __PRIVATE__METHODS__

=over 4

=item B<_root_element>

Class method that returns the name of the XML root element to be
located in the query XML. Returns "ShiftQuery" by default.

=cut

sub _root_element {
  return "ShiftQuery";
}

=back

=end __PRIVATE__METHODS__

=head1 AUTHOR

Brad Cavanagh E<lt>b.cavanagh@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2002 Particle Physics and Astronomy Research Council.
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
along with this program (see SLA_CONDITIONS); if not, write to the 
Free Software Foundation, Inc., 59 Temple Place, Suite 330, 
Boston, MA  02111-1307  USA


=cut

1;
