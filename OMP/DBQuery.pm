package OMP::DBQuery;

=head1 NAME

OMP::DBQuery - Class representing an OMP database query

=head1 SYNOPSIS

  $query = new OMP::DBQuery( XML => $xml );
  $sql = $query->sql( $table );


=head1 DESCRIPTION

This class can be used to process generic OMP database queries.
The queries are usually represented as XML. Specific database queries
usually inherit from this class since it has no code specific to a
particular table.

=cut

use 5.006;
use strict;
use warnings;
use Carp;

# External modules
use XML::LibXML; # Our standard parser
use OMP::Error;
use OMP::General;
use OMP::Range;
use Time::Piece ':override'; # for gmtime

# Package globals

our $VERSION = (qw$Revision$ )[1];

# Default number of results to return from a query
our $DEFAULT_RESULT_COUNT = 50;


# Overloading
use overload '""' => "stringify";

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

The constructor takes an XML representation of the query and
returns the object.

  $query = new OMP::DBQuery( XML => $xml, MaxCount => $max );

Throws DBMalformedQuery exception if the XML is not valid.

=cut

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;

  croak 'Usage : OMP::MSBQuery->new(XML => $xml)' unless @_;

  my %args = @_;

  my ($parser, $tree);
  if (exists $args{XML}) {
    # Now convert XML to parse tree
    $parser = new XML::LibXML;
    $parser->validation(1);
    $tree = eval { $parser->parse_string( $args{XML} ) };
    throw OMP::Error::DBMalformedQuery("Error parsing XML query [$args{XML}]")
      if $@;
  } else {
    # Nothing of use
    return undef;
  }

  my $q = {
	   Parser => $parser,
	   Tree => $tree,
	   QHash => {},
	   Constraints => undef,
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
  if (!defined $current || $current == 0) {
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

=item B<_root_element>

Class method that returns the name of the XML root element to be
located in the query XML. This changes depending on whether we
are doing an MSB or Project query. Must be specified in a subclass.
Returns "DBQuery" by default.

=cut

sub _root_element {
  return "DBQuery";
}

=item B<_qhash_tosql>

Convert a query hash to a SQL WHERE clause. Called by sub-classes
in order prior to inserting the clause into the main SQL query.

  $where = $q->_qhash_tosql( \@skip );

First argument is a reference to an array that contains the names of keys
in the query hash that should be skipped when constructing the SQL.

Returned SQL segment does not include "WHERE".

=cut

sub _qhash_tosql {
  my $self = shift;
  my $skip = shift;
  $skip = [] unless defined $skip;

  # Retrieve the perl version of the query
  my $query = $self->query_hash;

  # Walk through the hash generating the core SQL
  # a chunk at a time
  my @sql;
  for my $entry ( keys %$query) {
    next if $entry =~ /^_/;  # Skip internal keys

    # Some queries can not be processed yet because they require
    # extra information or stored procedures
    next if grep /^$entry$/, @$skip;

    # Look at the entry and convert to SQL
    if (ref($query->{$entry}) eq 'ARRAY') {
      # use an OR join [must surround it with parentheses]
      push(@sql, "(".join(" OR ", 
			  map { $self->_querify($entry, $_); }
			  @{ $query->{$entry} } 
			 ) . ")");

    } elsif (UNIVERSAL::isa( $query->{$entry}, "OMP::Range")) {
      # A Range object
      my %range = $query->{$entry}->minmax_hash;

      # an AND clause
      push(@sql,join(" AND ",
		     map { $self->_querify($entry, $range{$_}, $_);}
		     keys %range
		    ));

    } else {
      # use Data::Dumper;
      # print Dumper( $query->{$entry});

      throw OMP::Error::DBMalformedQuery("Query hash contained a non-ARRAY non-OMP::Range for $entry ". $query->{$entry}."\n");
    }
  }

  # Now join it all together with an AND
  my $clause = join(" AND ", @sql);

  # Return the clause
  return $clause;

}

=item B<_convert_to_perl>

Convert the XML parse tree to a query data structure.

  $query->_convert_to_perl;

Invoked automatically by the C<query_hash> method
unless the data structure has already been created.
Result is stored in C<query_hash>.

=cut

sub _convert_to_perl {
  my $self = shift;
  my $tree = $self->_tree;

  my %query;

  my $rootelement = $self->_root_element();

  # Get the root element
  my @msbquery = $tree->findnodes($rootelement);
  throw OMP::Error::MSBMalformedQuery("Could not find <$rootelement> element")
    unless @msbquery == 1;
  my $msbquery = $msbquery[0];

  # Loop over children
  for my $child ($msbquery->childNodes) {
    my $name = $child->getName;
    #print "Name: $name\n";

    # Get the attributes
    my %attr = map {  $_->getName, $_->getValue} $child->getAttributes;

    # Now need to look inside to see what the children are
    for my $grand ( $child->childNodes ) {

      if ($grand->isa("XML::LibXML::Text")) {

	# This is just PCDATA

	# Make sure this is not simply white space
	my $string = $grand->toString;
	next unless $string =~ /\w/;

	$self->_add_text_to_hash( \%query, $name, $string, \%attr );

      } else {

	# We have an element. Get its name and add the contents
	# to the hash (we assume only one text node)
	my $childname = $grand->getName;
	$self->_add_text_to_hash(\%query, 
				 $name, $grand->firstChild->toString,
				 $childname, \%attr );

      }

    }


  }

  # Do some post processing to convert to OMP::Ranges and
  # to fix up some standard keys
  $self->_post_process_hash( \%query );

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

Attributes associated with the elements can be supplied as a final argument
(always the last) identified by it being a reference to a hash. These
attributes are copied into the query hash as key C<_attr> - pointing
to a hash with the attributes. Attributes are overwritten if new
values are provided later.

=cut

sub _add_text_to_hash {
  my $self = shift;
  my $hash = shift;
  my $key = shift;
  my $value = shift;

  # Last arg can be a hash ref in special case
  my $attr;
  if (ref($_[-1]) eq 'HASH' ) {
    $attr = pop(@_);
  }

  # Read any remaining args
  my $secondkey = shift;

  # Check to see if we have a special key
  $secondkey = '' unless defined $secondkey;
  my $special = ( $secondkey =~ /max|min/ ? 1 : 0 );

  # primary key is the secondkey if we are not special
  $key = $secondkey unless $special or length($secondkey) eq 0;

  # Clean up the value since SQL does not like new lines
  # in the middle of a clause
  $value =~ s/^\s+//;
  $value =~ s/\s+\Z//;


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

  # Store attributes if they are supplied
  $hash->{_attr} = {} unless exists $hash->{_attr};
  $hash->{_attr}->{$key} = $attr if defined $attr;

}

=item B<_post_process_hash>

Fix up the query hash according to generic rules. These are:

=over 4

=item *

Convert hashes with min/max to C<OMP::Range> objects.

=item *

Convert dates (anything with "date" in the key) to date objects.

=back

Specific query manipulation must be done in a subclass.
Note that subclasses must call this method in order to get
the above manipulation.

 $q->_post_process_hash( \%hash );

The hash is "fixed-up" in place.

=cut

sub _post_process_hash {
  my $self = shift;
  my $href = shift;


  # First convert all keys with "date" in the name to date objects
  for my $key (keys %$href) {
    next if $key =~ /^_/;

    if ($key =~ /date/) {
      # If we are in a hash convert all hash members
      $self->_process_elements($href, 
			       sub { OMP::General->parse_date(shift)},
			       [ $key ] );
    }
  }

  # Loop over each key looking for ranges
  for my $key (keys %$href ) {
    # Skip private keys
    next if $key =~ /^_/;

    if (UNIVERSAL::isa($href->{$key}, "HASH")) {
      # Convert to OMP::Range object
      $href->{$key} = new OMP::Range( Min => $href->{$key}->{min},
				      Max => $href->{$key}->{max},
				    );
    }
  }

  # Done
}

=item B<_querify>

Convert the column name, column value and optional comparator
to an SQL sub-query.

  $sql = $q->_querify( "elevation", 20, "min");
  $sql = $q->_querify( "instrument", "SCUBA" );

Determines whether we have a number or string for quoting rules.

Some keys are duplicated in different tables. In those cases (project
ID is the main one) the table prefix is automatically added.

"coi" and "pi" queries are always done using LIKE rather than equals.

A "name" element is converted to a query in both the "pi" and
"coi" fields (ie you are interested in whether the named person
is associated with the project at all). ie for each query on "name"
a query for both "pi" and "coi" is returned with a logical OR.



=cut

sub _querify {
  my $self = shift;
  my ($name, $value, $cmp) = @_;

  # Default comparator is "equal"
  $cmp = "equal" unless defined $cmp;

  # Lookup table for comparators
  my %cmptable = (
		  equal => "=",
		  min   => ">=",
		  max   => "<=",
		  like  => "like",
		 );

  # Convert the string form to SQL form
  throw OMP::Error::MSBMalformedQuery("Unknown comparator '$cmp' in query\n")
    unless exists $cmptable{$cmp};

  # Do we need to quote it
  my $quote = ( $value =~ /[A-Za-z:]/ ? "'" : '' );

  # Substring comparators fields
  if ($name eq "name" or $name eq "coi" or $name eq "pi") {
    $cmp = "like";
  }

  # If we have "name" then we need to create a query on both
  # pi and coi together
  my @list;
  if ($name eq "name") {
    # two columns
    @list = (qw/ coi pi /);

    # case insensitive [the SQL way]
    $value =~ s/([a-zA-Z])/[\U$1\L$1]/g;

  } else {
    @list = ( $name );
  }

  # Loop over all keys in list
  my $sql = join( " OR ",
		  map { "$_ $cmptable{$cmp} $quote$value$quote"  } @list);


  # Form query
  return $sql

}

=item B<_process_elements>

Process all the array elements or hash members associated with the
supplied keys in the query hash.

  $q->_process_elements( \%qhash, $cb, \@keys );

Where the first argument is the reference to the query hash, the
second argument is a callback (CODREF) to be executed for each
array element or hash member and the last argument is an array
of keys in the query hash to process.

As well as hashes and arrays it recognizes C<OMP::Range> objects.

This method allows you to process all elements in a simple way without
caring about the specific organization in the query hash.

=cut

sub _process_elements {
  my $self = shift;
  my $href = shift;
  my $cb = shift;
  my $keys = shift;

  throw OMP::Error::BadArgs("Third argument to _process_elements must be array ref") unless ref($keys) eq "ARRAY";
  throw OMP::Error::BadArgs("Second argument to _process_elements must be code ref") unless ref($cb) eq "CODE";

  for my $key ( @$keys ) {

    # Check it exists
    if (exists $href->{$key}) {

      my $ref = ref($href->{$key}); # The reference type
      my $val = $href->{$key}; # The value

      if (not $ref) {
	# Simple scalar
	$href->{$key} = $cb->( $val );

      } elsif ($ref eq "ARRAY" ) {
	# An array
	$href->{$key} = [ map { $cb->($_); } @{ $val } ];

      } elsif ($ref eq "HASH") {
	# Simple hash
	my %hash = %$val;
	for my $hkey (keys %hash) {
	  $hash{$hkey} = $cb->( $hash{$hkey} );
	}
	$href->{$key} = \%hash;

      } elsif ($val->isa("OMP::RANGE")) {

	$val->min( $cb->($val->min) ) if defined $val->min;
	$val->max( $cb->($val->max) ) if defined $val->max;

      } else {
	throw OMP::Error::DBMalformedQuery("Unable to process class of type '$ref'");
      }

    }
  }

}

=end __PRIVATE__METHODS__

=back

=head1 Query XML

The Query XML is specified as follows:

=over 4

=item B<DBQuery>

The top-level container element is E<lt>DBQueryE<gt> although
sub-classes can change this.

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

OMP/SN/004, C<OMP::MSBQuery>

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
