package OMP::MSBQuery;

=head1 NAME

OMP::MSBQuery - Class representing an OMP query

=head1 SYNOPSIS

  $query = new OMP::MSBQuery( XML => $xml );
  $sql = $query->sql( $table );


=head1 DESCRIPTION

This class can be used to process OMP MSB queries.
The queries are usually represented as XML.

=cut

use 5.006;
use strict;
use warnings;
use Carp;

# External modules
use XML::LibXML; # Our standard parser
use OMP::Error;

# Package globals

our $VERSION = (qw$Revision$ )[1];

# Default number of results to return from a query
our $DEFAULT_RESULT_COUNT = 10;


# Overloading
use overload '""' => "stringify";

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

The constructor takes an XML representation of the query and
returns the object.

  $query = new OMP::MSBQuery( XML => $xml, MaxCount => $max );

Throws MSBMalformedQuery exception if the XML is not valid.

=cut

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;

  croak 'Usage : OMP::MSBQuery->new(XML => $xml)' unless @_;

  my %args = @_;

  my ($parser, $tree);
  if (exists $args{XML}) {
    # Now convert XML to parse tree
    XML::LibXML->validation(1);
    $parser = new XML::LibXML;
    $tree = eval { $parser->parse_string( $args{XML} ) };
    throw OMP::Error::MSBMalformedQuery("Error parsing XML query")
      if $@;
  } else {
    # Nothing of use
    return undef;
  }

  my $q = {
	   Parser => $parser,
	   Tree => $tree,
	   QHash => {},
	  };

  # and create the object
  bless $q, $class;

  # Read other hash values if appropriate - use proper accessors here
  $q->maxCount($args{MaxCount}) if exists $args{MaxCount};

  return $q;
}

=back

=head2 Accessor Methods

Instance accessor methods. Methods beginning with an underscore
are deemed to be private and do not form part of the publi interface.

=over 4

=item B<maxCount>

Return (or set) the maximum number of rows that are to be returned
by the query. In general this number must be used after the SQL
query has been executed.

  $max = $query->maxCount;
  $query->maxCount( $max );

If the value is undefined or negative all results are returned. If the
supplied value is zero a default value is used instead.

=cut

sub maxCount {
  my $self = shift;
  if (@_) {
    my $max = shift;
    if (defined $max and $max >= 0) {
      $self->{MaxCount} = $max;
    }
  }
  my $current = $self->{MaxCount};
  if (defined $current && $current == 0) {
    return $DEFAULT_RESULT_COUNT;
  } else {
    return $current;
  }
}


=item B<_parser>

Retrieves or sets the underlying XML parser object. This will only be
defined if the constructor was invoked with an XML string rather
than a pre-existing C<XML::LibXML::Element>.

=cut

sub _parser {
  my $self = shift;
  if (@_) { $self->{Parser} = shift; }
  return $self->{Parser};
}

=item B<_tree>

Retrieves or sets the base of the document tree associated
with the science program. In general this is DOM based. The
interface does not guarantee the underlying object type
since that relies on the choice of XML parser.

=cut

sub _tree {
  my $self = shift;
  if (@_) { $self->{Tree} = shift; }
  return $self->{Tree};
}

=item B<query_hash>

Retrieve query in the form of a perl hash. Entries are either hashes
or arrays. Keys with array references refer to multiple matches (OR
relationship) [assuming there is more than one element in the array]
and Keys with hash references refer to ranges (whose hashes must have
C<max> and/or C<min> as keys).

  $hashref = $query->query_hash();

=cut

sub query_hash {
  my $self = shift;
  if (@_) { 
    $self->{QHash} = shift; 
  } else {
    # Check to see if we have something
    unless (%{ $self->{QHash} }) {
      $self->_convert_to_perl;
    }
  }
  return $self->{QHash};
}


=back

=head2 General Methods

=over 4

=item B<sql>

Returns an SQL representation of the Query using the specified
database table.

  $sql = $query->sql( $msbtable, $obstable, $projtable );

Returns undef if the query could not be formed.

The query includes explicit tests to make sure that time remains
on the project and that the target is available (in terms of being
above the horizon and in terms of being schedulable)

=cut

sub sql {
  my $self = shift;

  throw OMP::Error::MSBMalformedQuery("sql method invoked with incorrect number of arguments\n") 
    unless scalar(@_) ==3;

  my ($msbtable, $obstable, $projtable) = @_;

  # Retrieve the perl version of the query
  my $query = $self->query_hash;

  # Walk through the hash generating the core SQL
  # a chunk at a time
  my @sql;
  for my $entry ( keys %$query) {

    # Some queries can not be processed yet because they require
    # extra information or stored procedures
    next if $entry eq "elevation";
    next if $entry eq "date";

    # Look at the entry and convert to SQL
    if (ref($query->{$entry}) eq 'ARRAY') {
      # use an OR join [must surround it with parentheses]
      push(@sql, "(".join(" or ", 
			  map { $self->_querify($entry, $_); }
			  @{ $query->{$entry} } 
			 ) . ")");

    } elsif (ref($query->{$entry}) eq 'HASH') {

      # Use an AND join
      push(@sql,join(" and ", 
		     map { $self->_querify($entry, $query->{$entry}->{$_}, $_);}
		     keys %{ $query->{$entry} } 
		    ));

    } else {
      throw OMP::Error::MSBMalformedQuery("Query hash contained a non-HASH non-ARRAY: ". $query->{$entry}."\n");
    }
  }
  # Now join it all together with an AND
  my $subsql = join(" AND ", @sql);

  # If the resulting query contained anything we should prepend
  # an AND so that it fits in with the rest of the SQL. This allows
  # an empty query to work without having a naked "AND".
  $subsql = " AND " . $subsql if $subsql;

  # Some explanation is probably in order.
  # We do three queries
  # 1. Do a query on MSB and OBS tables looking for relevant
  #    matches but only retrieving the matching MSBID, the
  #    corresponding MSB obscount and the total number of observations
  #    that matched within each MSB. The result is stored to a temp table
  # 2. Query the temporary table to determine all the MSB's that had
  #    all their observations match
  # 3. Use that list of MSBs to fetch the corresponding contents

  # We also DROP the temporary tables immediately since sybase
  # keeps them around for until the connection is ended.

  # It is assumed that the observation information will be retrieved
  # in a subsequent query if required.

  # Get the names of the temporary tables
  # Sybase limit if 13 characters for uniqueness
  my $tempcount = "#ompcnt";
  my $tempmsb = "#ompmsb";

  # Now need to put this SQL into the template query
  my $sql = "(SELECT
          $msbtable.msbid, $msbtable.obscount, COUNT(*) AS nobs
           INTO $tempcount
           FROM $msbtable,$obstable, $projtable
            WHERE $msbtable.msbid = $obstable.msbid
              AND $projtable.projectid = $msbtable.projectid
               AND $msbtable.remaining > 0
                AND ($projtable.remaining - $projtable.pending) >= $msbtable.timeest
                $subsql
              GROUP BY $msbtable.msbid)
                (SELECT msbid INTO $tempmsb FROM $tempcount
                 WHERE nobs = obscount)
               (SELECT * FROM $msbtable,$tempmsb
                 WHERE $msbtable.msbid = $tempmsb.msbid
                 )";

  # Same as above but without worrying about elapsed time
  $sql = "(SELECT
          $msbtable.msbid, $msbtable.obscount, COUNT(*) AS nobs
           INTO $tempcount
           FROM $msbtable,$obstable, $projtable
            WHERE $msbtable.msbid = $obstable.msbid
              AND $projtable.projectid = $msbtable.projectid
               AND $msbtable.remaining > 0
                $subsql
              GROUP BY $msbtable.msbid)
               (SELECT * FROM $msbtable,$tempcount
                 WHERE $msbtable.msbid = $tempcount.msbid
                   AND $msbtable.obscount = $tempcount.nobs)

                DROP TABLE $tempcount";

#  print "SQL: $sql\n";


  return "$sql\n";

  # To subvert query
  return "SELECT * FROM $msbtable WHERE remaining > 0";
}

=item B<stringify>

Convert the Query object into XML.

  $string = $query->stringify;

This method is also invoked via a stringification overload.

  print "$query";

=cut

sub stringify {
  my $self = shift;
  $self->_tree->toString;
}

=begin __PRIVATE__METHODS__

=item B<_convert_to_perl>

Convert the XML parse tree to a query data structure.

  $query->_convert_to_perl;

Invoked automatically by the C<query_hash> method
unless the data structure has alrady been created.
Result is stored in C<query_hash>.

=cut

sub _convert_to_perl {
  my $self = shift;
  my $tree = $self->_tree;

  my %query;

  # Get the root element
  my @msbquery = $tree->findnodes('MSBQuery');
  throw OMP::Error::MSBMalformedQuery("Could not find <MSBQuery> element")
    unless @msbquery == 1;
  my $msbquery = $msbquery[0];

  # Loop over children
  for my $child ($msbquery->childNodes) {
    my $name = $child->getName;
    #print "Name: $name\n";

    # Now need to look inside to see what the children are
    for my $grand ( $child->childNodes ) {

      if ($grand->isa("XML::LibXML::Text")) {

	$self->_add_text_to_hash( \%query, $name, $grand->toString );

      } else {

	# We have an element. Get its name and add the contents
	# to the hash (we assume only one text node)
	my $childname = $grand->getName;
	$self->_add_text_to_hash(\%query, 
				 $name, $grand->firstChild->toString,
				 $childname );

      }

    }


  }

  # Store the hash
  $self->query_hash(\%query);

#  use Data::Dumper;
#  print Dumper(\%query);

}

=item B<_add_text_to_hash>

Add content to the query hash. Compares keys of arguments with
the existing content and does the right thing depending on whether
the key has occurred before or it has a special case (max or min).

$query->_add_text_to_hash( \%query, $key, $value, $secondkey );

The secondkey is used as the primary key unless it is one of the
special reserved key (min or max). In that case the secondkey
is used as a hash key in the hash pointed to by $key.

For example, key=instruments value=cgs4 secondkey=instrument

  $query{instrument} = [ "cgs4" ];

key=elevation value=20 sescondkey=max

  $query{elevation} = { max => 20 }

key=instrument value=scuba secondkey=undef

  $query{instrument} = [ "cgs4", "scuba" ];

Note that single values are always stored in arrays in case
a second value turns up. Note also that special cases become
hashes rather than arrays.

=cut

sub _add_text_to_hash {
  my $self = shift;
  my $hash = shift;
  my $key = shift;
  my $value = shift;
  my $secondkey = shift;

  # Check to see if we have a special key
  $secondkey = '' unless defined $secondkey;
  my $special = ( $secondkey =~ /max|min/ ? 1 : 0 );

  # primary key is the secondkey if we are not special
  $key = $secondkey unless $special or length($secondkey) eq 0;

  if (exists $hash->{$key}) {

    if ($special) {
      # Add it into the hash ref
      $hash->{$key}->{$secondkey} = $value;

    } else {
      # Append it to the array
      push(@{$hash->{$key}}, $value);
    }

  } else {
    if ($special) {
      $hash->{$key} = { $secondkey => $value };
    } else {
      $hash->{$key} = [ $value ];
    }
  }

}

=item B<_querify>

Convert the column name, column value and optional comparator
to an SQL sub-query.

  $sql = $q->_querify( "elevation", 20, "min");
  $sql = $q->_querify( "instrument", "SCUBA" );

Determines whether we have a number or string for quoting rules.

=cut

sub _querify {
  my $self = shift;
  my ($name, $value, $cmp) = @_;

  # Default comparator is "equal"
  $cmp = "equal" unless defined $cmp;

  # Lookup table for comparators
  my %cmptable = (
		  equal => "=",
		  min   => ">",
		  max   => "<",
		 );

  # Convert the string form to SQL form
  throw OMP::Error::MSBMalformedQuery("Unknown comparator $cmp in query\n")
    unless exists $cmptable{$cmp};

  # Do we need to quote it
  my $quote = ( $value =~ /[A-Za-z]/ ? "'" : '' );

  # Form query
  return "$name $cmptable{$cmp} $quote$value$quote";

}

=end __PRIVATE__METHODS__

=back

=head1 Query XML

The Query XML is specified as follows:

=over 4

=item B<MSBQuery>

The top-level container element is E<lt>MSBQueryE</gt>.

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

  <tauband>1</tauband>
  <tauband>3</tauband>

would suggest that taubands 1 or 3 are valid. This also means

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

OMP/SN/004

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
