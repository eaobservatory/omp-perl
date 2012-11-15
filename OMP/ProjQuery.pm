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

  $sql = $query->sql( $projtable, $projusertable );

Returns undef if the query could not be formed.

=cut

sub sql {
  my $self = shift;

  throw OMP::Error::DBMalformedQuery("ProjQuery: sql method invoked with incorrect number of arguments\n") 
    unless scalar(@_) == 3;

  my ($projtable, $projqueuetable, $projusertable) = @_;

  # Generate the WHERE clause from the query hash
  # Note that we ignore elevation, airmass and date since
  # these can not be dealt with in the database at the present
  # time [they are used to calculate source availability]
  # Disabling constraints on queries should be left to this
  # subclass
  my $subsql = $self->_qhash_tosql();

  # Now need to put this SQL into the template query
  # Only do a join if required by the CoI or Support query
  my @join_tables;
  my @join_sql;
  # Note that we match multiple times but we do not reset the position
  # this allows us to jump out eventually.
  my %found;
  while ($subsql =~ /\b(U\d)\.userid\b/cg ) {
    # Keep track of the tables we have covered already
    next if exists $found{$1};
    $found{$1}++;

    push(@join_tables, ", $projusertable $1");
    push(@join_sql, " P.projectid = $1.projectid ");
  }

  # Join with the Q table if required
  if ($subsql =~ /\bQ\./) {
    push(@join_tables, ", $projqueuetable Q");
    push(@join_sql, " P.projectid = Q.projectid ");
  }

  # Construct the the where clause. Depends on which
  # additional queries are defined
  my @where = grep { $_ } (@join_sql, $subsql);
  my $where = '';
  $where = " WHERE " . join( " AND ", @where)
    if @where;

  # The final query
  # Note that we are only interested in the ProjTable contents
  # since the user information is read after the match
  my $sql = "SELECT DISTINCT P.projectid, P.* FROM $projtable P " .
    join(" ",@join_tables) .
      "$where ORDER BY P.projectid";

  #print "SQL: $sql\n";
  return "$sql\n";

}

=begin __PRIVATE__METHODS__

=item B<_root_element>

Class method that returns the name of the XML root element to be
located in the query XML. This changes depending on whether we
are doing an MSB or Project query.
Returns "ProjQuery" by default.

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

Does not convert abbreviated project names to full form
(this would require knowledge of a telescope).

=cut

sub _post_process_hash {
  my $self = shift;
  my $href = shift;

  # Do the generic pre-processing
  $self->SUPER::_post_process_hash( $href );

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

    }

  }

  # Case sensitivity
  # If we are dealing with a these we should make sure we upper
  # case them (more efficient to upper case everything than to do a
  # query that ignores case)
  $self->_process_elements($href, sub { uc(shift) },
			   [qw/projectid telescope support coi semester person pi country/]);

  # These entries are in more than one table so we have to 
  # explicitly choose the project table
  for (qw/ projectid telescope /) {
    if (exists $href->{$_}) {
      my $key = "P.$_";
      $href->{$key} = $href->{$_};
      delete $href->{$_};
    }
  }

  # These entries are in the queue table [but also currently
  # in the proj table for backwards compatibility reasons
  for (qw/ country tagpriority /) {
    if (exists $href->{$_}) {
      my $key = "Q.$_";
      $href->{$key} = $href->{$_};
      delete $href->{$_};
    }
  }


  # Need to do multiple joins each time we have a distinct query
  # for a USER
  my $counter = 1;
  my $prefix = 'U';

  # A coi query is really a query on U.userid but with capacity of COI
  if (exists $href->{coi}) {
    my $U = $prefix . $counter;
    $href->{coi} = { _JOIN => 'AND', "$U.userid" => $href->{coi}, 
		     "$U.capacity" => ['COI']};
    $counter++;
  }

  # Similarly for "support" query
  if (exists $href->{support}) {
    my $U = $prefix . $counter;
    $href->{support} = { _JOIN => 'AND', "$U.userid" => $href->{support}, 
			 "$U.capacity" => ['SUPPORT']};
    $counter++;
  }

  # "person" means CoI or PI in ompprojuser table
  # i.e. userid = "Y" AND capacity in ('PI', 'COI')
  # but only if we are looking for distinct projects

  # if someone uses <person>X</person><person>Y</person>
  # this is deemed to be an OR and not an AND ie
  # userid in ('X','Y') AND capacity in ('PI','COI')
  # Also want distinct U.projectid if at all possible
  # Note that hash refs indicate OR so we could do this as
  # auser => { userid => 'X', userid => 'Y'},
  # acapacity => { capacity => 'PI', capacity => 'COI' }

  if (exists $href->{person}) {
    my $U = $prefix . $counter;
    $href->{person} = {
		       _JOIN => 'AND',
		       auser => {"$U.userid" => $href->{person}},
		       acapacity => { "$U.capacity"=> ['COI','PI']},
		      };
    $counter++;
  }

  # "support" means
  #  userid = 'Y' AND capacity = 'SUPPORT'
  # but this is difficult since we have no way of grouping AND
  # entries 
  # Maybe  support => { _JOIN => 'AND', capacity => 'SUPPORT', userid => 'Y'}

  # Remove attributes since we dont need them anymore
  delete $href->{_attr};
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

1;
