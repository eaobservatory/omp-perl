package OMP::TimeAcctQuery;

=head1 NAME

OMP::TimeAcctQuery - Class representing an XML OMP query of the time accouting database

=head1 SYNOPSIS

  $query = new OMP::TimeAcctQuery( XML => $xml );
  $sql = $query->sql( $table );

=head1 DESCRIPTION

This class can be used to process OMP time accounting queries.
The queries are usually represented as XML.

=cut

use 5.006;
use strict;
use warnings;
use Carp;

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

  $sql = $query->sql( $projtable, $coitable );

Returns undef if the query could not be formed.

=cut

sub sql {
  my $self = shift;

  throw OMP::Error::DBMalformedQuery("sql method invoked with incorrect number of arguments\n") 
    unless scalar(@_) ==1;

  # get the table name
  my $accttable = shift;

  # generate the WHERE clause from the query hash
  my $subsql = $self->_qhash_tosql();
  my $where = '';
  $where = " WHERE $subsql " if $subsql;

  # Now add this to the template
  my $sql = "SELECT * FROM $accttable $where";

  return $sql;
}

=begin __PRIVATE__METHODS__

=item B<_root_element>

Class method that returns the name of the XML root element to be
located in the query XML. This changes depending on whether we
are doing an MSB or Project query.
Returns "TimeAcctQuery" by default.

=cut

sub _root_element {
  return "TimeAcctQuery";
}


=item B<_post_process_hash>

Do table specific post processing of the query hash. For time accounting this
mainly entails converting range hashes to C<OMP::Range> objects (via
the base class), and upcasing some entries.

  $query->_post_process_hash( \%hash );

=cut

sub _post_process_hash {
  my $self = shift;
  my $href = shift;

  # Do the generic pre-processing
  $self->SUPER::_post_process_hash( $href );

  # Case sensitivity
  # If we are dealing with a these we should make sure we upper
  # case them (more efficient to upper case everything than to do a
  # query that ignores case)
  $self->_process_elements($href, sub { uc(shift) },
                           [qw/ projectid /]);

  # Remove attributes since we dont need them anymore
  delete $href->{_attr};

}

=end __PRIVATE__METHODS__

=back

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
