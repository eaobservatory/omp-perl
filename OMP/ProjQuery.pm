package OMP::ProjQuery;

=head1 NAME

OMP::ProjQuery - Class representing an XML OMP query of the Project database

=head1 SYNOPSIS

  $query = new OMP::ProjQuery( XML => $xml );
  $sql = $query->sql( $table );


=head1 DESCRIPTION

This class can be used to process OMP Project queries.
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
use Time::Piece ':override'; # for gmtime

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

  $sql = $query->sql( $projtable );

Returns undef if the query could not be formed.

=cut

sub sql {
  my $self = shift;

  throw OMP::Error::DBMalformedQuery("sql method invoked with incorrect number of arguments\n") 
    unless scalar(@_) ==1;

  my ($projtable) = @_;

  # Generate the WHERE clause from the query hash
  # Note that we ignore elevation, airmass and date since
  # these can not be dealt with in the database at the present
  # time [they are used to calculate source availability]
  # Disabling constraints on queries should be left to this
  # subclass
  my $subsql = $self->_qhash_tosql();

  # If the resulting query contained anything we should prepend
  # an AND so that it fits in with the rest of the SQL. This allows
  # an empty query to work without having a naked "AND".
  $subsql = " WHERE " . $subsql if $subsql;

  # Now need to put this SQL into the template query
  my $sql = "SELECT * FROM $projtable $subsql";

  return "$sql\n";

}

=begin __PRIVATE__METHODS__

=item B<_root_element>

Class method that returns the name of the XML root element to be
located in the query XML. This changes depending on whether we
are doing an MSB or Project query.
Returns "MSBQuery" by default.

=cut

sub _root_element {
  return "ProjQuery";
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
  $self->SUPER::_post_process_hash( $href );

  # Need a telescope
  throw OMP::Error::MSBMalformedQuery( "Please supply a telescope")
    unless exists $href->{telescope};

  # Loop over each key
  for my $key (keys %$href ) {
    # Skip private keys
    next if $key =~ /^_/;

    if ($key eq 'status') {

      # Convert status to query on remaining-pending
      # This is a bit of a kluge until we have a pseudo-column
      my $new = "(remaining-pending)";
      my $break = 0.01;
      if ($href->{status}->[0] =~ /^active$/i) {
	$href->{$new} = new OMP::Range( Min => $break);
      } else {
	$href->{$new} = new OMP::Range( Max => $break);
      }

      # Remove the status column
      delete $href->{status};

    } elsif ($key eq 'projectid') {

      # Get the telescope and date if we know it
      my %options;
      $options{telescope} = $href->{telescope}->[0] 
	if exists $href->{telescope};
      $options{date} = $href->{date}->[0]
	if exists $href->{date}->[0];

      # Translate project IDs
      for my $pid (@{ $href->{$key}}) {
	$pid = OMP::General->infer_projectid(%options,
					     projectid => $pid);
      }

    }

  }

  # Case sensitivity
  # If we are dealing with a these we should make sure we upper
  # case them (more efficient to upper case everything than to do a
  # query that ignores case)
  $self->_process_elements($href, sub { uc(shift) }, 
			   [qw/projectid telescope/]);


  # Remove attributes since we dont need them anymore
  delete $href->{_attr};

  # For now, telescope is not actually in the table
  delete $href->{telescope};

}


=end __PRIVATE__METHODS__

=back

=head1 Query XML

The Query XML is specified as follows:

=over 4

=item B<ProjQuery>

The top-level container element is E<lt>ProjQueryE<gt>.

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

=item B<project status>

A special C<status> field can be used to specify whether the project
is "ACTIVE" or "INACTIVE".

=back

=head1 SEE ALSO

OMP/SN/004, C<OMP::DBQuery>

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
