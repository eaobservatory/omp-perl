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
    $parser = new XML::LibXML;
    $parser->validation(1);
    $tree = eval { $parser->parse_string( $args{XML} ) };
    throw OMP::Error::MSBMalformedQuery("Error parsing XML query [$args{XML}]")
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

=item B<refDate>

Return the date object associated with the query. If no date has been
specified explicitly in the query the current date is returned.
[although technically the "current" date is actually the date when the
query was parsed rather than the date the exact time this method was
called]

  $date = $query->refDate;

The time can not be specified. 

This allows the target availability to be calculated.

=cut

sub refDate {
  my $self = shift;

  # Get the hash form of the query
  my $href = $self->query_hash;

  # Check for "date" key
  my $date;
  if ( exists $href->{date} ) {
    $date = $href->{date}->[0];
  } else {
    # Need to get a gmtime object that stringifies as a Sybase date
    $date = gmtime;

    # Rebless
    bless $date, "Time::Piece::Sybase";
  }
  return $date;
}

=item B<airmass>

Return the requested airmass range as an C<OMP::Range> object.

  $range = $query->airmass;

Returns C<undef> if the range has not been specified.

=cut

sub airmass {
  my $self = shift;

  # Get the hash form of the query
  my $href = $self->query_hash;

  # Check for "airmass" key
  my $airmass;
  $airmass = $href->{airmass} if exists $href->{airmass};
  return $airmass;
}

=item B<constraints>

Returns a hash containing the general project constraints that 
can be applied to this query.

Supported constraints are:

  observability  - is the source up
  remaining      - is the MSB still to be observed
  allocation     - has the full project allocation been used

Each of these will have a true (constraint is active) or false
(constraint is disabled) value.

If the query includes an instruction to disable all constraints
this will be respected by setting all values to false.

Default is all values set to true.

  my %constraints = $q->constraints;

The constraints are cached (ie only calculated once per instance).

=cut

sub constraints {
  my $self = shift;

  # Check in cache
  return %{ $self->{Constraints} } if $self->{Constraints};

  # Get the query in hash form
  my $href = $self->query_hash;

  # Default values
  my %constraints = (
		     observability => 1,
		     remaining => 1,
		     allocation => 1,
		    );

  # Go through the disableconstraint array making a hash
  if (exists $href->{disableconstraint}) {
    for my $con (@{ $href->{disableconstraint} } ) {
      $con = lc( $con );
      # immediately drop out if we hit "all"
      if ($con eq "all" ) {
	for my $key (keys %constraints) {
	  $constraints{$key} = 0;
	}
	last;
      } elsif (exists $constraints{$con}) {
	# If its in the allowed constraints list set to false
	$constraints{$con} = 0;
      }
    }
  }

  # Store it in cache
  $self->{Constraints} = \%constraints;

  return %constraints;

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
    next if $entry eq "airmass"; # just in case
    next if $entry eq "disableconstraint";

    # date is not part of a query because it is the reference
    # date for checking the source is up (scheduling constraints
    # are handled by datemin and datemax
    next if $entry eq "date";


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

    } elsif (ref($query->{$entry}) eq 'HASH') {
      # Obsolete branch for when we used to specify ranges
      # as hashes

      # Use an AND join
      push(@sql,join(" AND ", 
		     map { $self->_querify($entry, $query->{$entry}->{$_}, $_);}
		     keys %{ $query->{$entry} } 
		    ));

    } else {
      throw OMP::Error::MSBMalformedQuery("Query hash contained a non-HASH non-ARRAY non-OMP::Range: ". $query->{$entry}."\n");
    }
  }

  # Now join it all together with an AND
  my $subsql = join(" AND ", @sql);

  # If the resulting query contained anything we should prepend
  # an AND so that it fits in with the rest of the SQL. This allows
  # an empty query to work without having a naked "AND".
  $subsql = " AND " . $subsql if $subsql;

  #print "SQL: $subsql\n";

  # Some explanation is probably in order.
  # We do three queries
  # 1. Do a query on MSB and OBS tables looking for relevant
  #    matches but only retrieving the matching MSBID, the
  #    corresponding MSB obscount and the total number of observations
  #    that matched within each MSB. The result is stored to a temp table
  # 2. Query the temporary table to determine all the MSB's that had
  #    all their observations match and return the MSB information

  # We also DROP the temporary table immediately since sybase
  # keeps them around for until the connection is ended.

  # It is assumed that the observation information will be retrieved
  # in a subsequent query if required.

  # Get the names of the temporary tables
  # Sybase limit if 13 characters for uniqueness
  my $tempcount = "#ompcnt";
  my $tempmsb = "#ompmsb";


  # Additionally there are a number of constraints that are
  # always applied to the query simply because they make
  # sense for the OMP. These are:
  #  observability  - is the source up
  #  remaining      - is the MSB still to be observed
  #  allocation     - has the full project allocation been used
  # These constraints can be disabled individually by using
  # XML eg. <disableconstraint>observability</disableconstraint>
  # All can be disabled using "all".
  my %constraints = $self->constraints;
  my $constraint_sql = '';

  $constraint_sql .= " AND M.remaining > 0 " if $constraints{remaining};
  $constraint_sql .= " AND (P.remaining - P.pending) >= M.timeest " 
    if $constraints{allocation};

  # Now need to put this SQL into the template query
  my $sql = "(SELECT
          M.msbid, M.obscount, COUNT(*) AS nobs
           INTO $tempcount
           FROM $msbtable M,$obstable O, $projtable P
            WHERE M.msbid = O.msbid
              AND P.projectid = M.projectid
               $constraint_sql
                $subsql
              GROUP BY M.msbid)
               (SELECT * FROM $msbtable M2, $tempcount T
                 WHERE M2.msbid = T.msbid
                   AND M2.obscount = T.nobs)

                DROP TABLE $tempcount";

  #print "$sql\n";

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
unless the data structure has already been created.
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

Go through the hash creating C<OMP::Range> objects where appropriate
and fixing up known issues such as "cloud" and "moon" which are
treated as lower limits rather than exact matches.

  $query->_post_process_hash( \%hash );

"date" strings are converted to a date object.

"date", "tau" and "seeing" queries are each converted to two separate
queries (one on "max" and one on "min") [but the "date" key is
retained so that the reference date can be obtained in order to
calculate source availability).

Also converts abbreviated form of project name to the full form
recognised by the database.

=cut

sub _post_process_hash {
  my $self = shift;
  my $href = shift;

  # Do date conversion as a special case since
  # the semester calculation relies on this having been done
  # Need to keep it in an array for consistency of interface
  # Insert current date if none present
  my $date;
  if (exists $href->{date}) {
    # Convert to object
    $date = OMP::General->parse_date( $href->{date}->[0]);
  } else {
    # Need to get a gmtime object that stringifies as a Sybase date
    $date = gmtime;

    # Rebless
    bless $date, "Time::Piece::Sybase";
  }
  $href->{date} = [ $date ];

  # Also do timeest as a special case since that becomes
  # a hash (and so wont be modified in the loop once converted
  # to a range)
  if (exists $href->{timeest}) {

    my $key = "timeest";

    # Need the estimated time to be in seconds
    # Look at the attributes
    if (exists $href->{_attr}->{$key}->{units}) {
      my $units = $href->{_attr}->{$key}->{units};

      my $factor = 1; # multiplication factor
      if ($units =~ /^h/) {
	$factor = 3600;
      } elsif ($units =~ /^m/) {
	$factor = 60;
      }

      # Now scale all values by this factor
      if (ref($href->{timeest}) eq 'HASH') {
	for (keys %{ $href->{timeest} }) {
	  $href->{timeest}->{$_} *= $factor;
	}
      } elsif (ref($href->{timeest}) eq 'ARRAY') {
	for (@{ $href->{timeest}}) {
	  $_ *= $factor;
	}
      }
    }
  }

  # Loop over each key
  for my $key (keys %$href ) {
    # Skip private keys
    next if $key =~ /^_/;

    if (UNIVERSAL::isa($href->{$key}, "HASH")) {
      # Convert to OMP::Range object
      $href->{$key} = new OMP::Range( Min => $href->{$key}->{min},
				      Max => $href->{$key}->{max},
				    );

    } elsif ($key eq "cloud" or $key eq "moon") {
      # convert to range with the supplied value as the min
      $href->{$key} = new OMP::Range( Min => $href->{$key}->[0] );

    } elsif ($key eq "seeing" or $key eq "tau" or $key eq "date") {
      # Convert to two independent ranges

      # Note that taumin indicates a MAX for the supplied value
      # and taumax indicates a minimum for the supplied value
      my %outkey = ( max => "Min", min => "Max");

      # Loop over min and max
      for my $type (qw/ min max /) {
	$href->{"$key$type"} = new OMP::Range( $outkey{$type} =>
					       $href->{$key}->[0]);
      }

      # And remove the old key (unless it is the reference date)
      delete $href->{$key} unless $key eq "date";

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

  # Remove attribute since we dont need them anymore
  delete $href->{_attr};

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
  throw OMP::Error::MSBMalformedQuery("Unknown comparator $cmp in query\n")
    unless exists $cmptable{$cmp};

  # Do we need to quote it
  my $quote = ( $value =~ /[A-Za-z:]/ ? "'" : '' );

  # If we are dealing with a project ID we should make sure we upper
  # case it (more efficient to upper case everything than to do a
  # query that ignores case)
  $value = uc($value) if $name eq 'projectid';

  # same for telescope
  $value = uc($value) if $name eq 'telescope';

  # Additionally, If the name is projectid we need to make sure it
  # comes from the MSB table
  $name = "M." . $name if $name eq 'projectid';

  # Same with timeest
  $name = "M." . $name if $name eq 'timeest';

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

=end __PRIVATE__METHODS__

=back

=head1 Query XML

The Query XML is specified as follows:

=over 4

=item B<MSBQuery>

The top-level container element is E<lt>MSBQueryE<gt>.

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

=item B<Reference date>

The C<date> element can be used to specify a specific date
for the query. This date is used for determining source availability
and is compared with any date constraints for a particular MSB. If a date
is not supplied the current date is automatically inserted. The date
should be supplied in ISO format YYYY-MM-DDTHH:MM

  <date>2002-04-15T04:52</date>

=item B<cloud and moon>

Queries on "cloud" and "moon" columns are really a statement of the
current weather conditions rather than a request for a match of exactly
the specified value. In fact these elements are really saying that the
retrieved records should be within the range 0 to the value in the table.
ie the table contains an upper limit with an implied lower limit of zero.

This translates to an effective query of:

  <moon><min>2</min></moon>

Queries on "cloud" and "moon" are translated to this form.

=item B<tau and seeing>

Queries including tau and seeing reflect the current weather conditions
but do not correspond to an equivalent table in the database. The database
contains allowable ranges (e.g. taumin and taumax) and the supplied
value must lie within the range. Therefore for a query such as:

  <tau>0.06</tau>

the query would become

  taumin <= 0.05 AND taumax >= 0.05

=item B<target observability>

Constraints on the observability of the target are not calculated in
SQL. These must be done post-query. Methods are provided to make the
target constraints available (essentially the minimum elevation).

=item B<constraints>

Additionally there are a number of constraints that are
always applied to the query simply because they make
sense for the OMP. These are:

 observability  - is the source up
 remaining      - is the MSB still to be observed
 allocation     - has the full project allocation been used

These constraints can be disabled individually by using
XML for example,

 <disableconstraint>observability</disableconstraint>

Any number of these elements can be included.

Alternatively all scheduling constraints can be disabled
using "all".

 <disableconstraint>all</disableconstraint>

=back

=head1 SEE ALSO

OMP/SN/004

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
