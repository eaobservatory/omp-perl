package OMP::Query;

=head1 NAME

OMP::Query - Class representing an OMP database query

=head1 SYNOPSIS

    $query = OMP::Query->new(XML => $xml);
    $sql = $query->sql($table);

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
use XML::LibXML;  # Our standard parser
use OMP::Error;
use OMP::DateTools;
use OMP::General;
use OMP::Range;
use Time::Piece ':override'; # for gmtime
use Time::Seconds;

# Package globals

our $VERSION = '2.000';

# Default number of results to return from a query
our $DEFAULT_RESULT_COUNT = 500;

# Hash of column names which are also MySQL reserved words - these must
# be quoted in SQL queries.
our %RESERVED_WORDS = map {$_ => 1} qw/condition group/;

# Overloading
use overload '""' => "stringify";

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

The constructor takes an XML representation of the query and
returns the object.

    $query = OMP::Query->new(XML => $xml, MaxCount => $max);

Throws DBMalformedQuery exception if the XML is not valid.

As an alternative, the query can be specified via a hashref
"HASH" instead of XML.  Please see the C<_process_given_hash>
description for more information about this option.

=cut

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;

    croak 'Usage : OMP::Query->new(XML => $xml)' unless @_;

    my %args = @_;

    my ($parser, $tree, $givenhash);
    if (exists $args{XML}) {
        # Now convert XML to parse tree
        $parser = XML::LibXML->new;
        $parser->validation(0);
        $tree = eval {$parser->parse_string($args{XML})};
        throw OMP::Error::DBMalformedQuery(
            "Error parsing XML query [$args{XML}] from: $@")
            if $@;
    }
    elsif (exists $args{'HASH'}) {
        $givenhash = $args{'HASH'};
        throw OMP::Error::DBMalformedQuery(
            "Given HASH argument is not a hashref")
            unless 'HASH' eq ref $givenhash;
    }
    else {
        # Nothing of use
        return undef;
    }

    my $q = {
        Parser => $parser,
        Tree => $tree,
        QHash => {},
        Constraints => undef,
        GivenHash => $givenhash,
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
    $query->maxCount($max);

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
    if (! defined $current || $current == 0) {
        return $DEFAULT_RESULT_COUNT;
    }
    else {
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
    if (@_) {$self->{Parser} = shift;}
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
    if (@_) {$self->{Tree} = shift;}
    return $self->{Tree};
}

=item B<_given_hash>

Retrieves or sets an explicit query hash, possibly given as
constructor argument C<HASH>.

=cut

sub _given_hash {
    my $self = shift;
    if (@_) {$self->{'GivenHash'} = shift;}
    return $self->{'GivenHash'};
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
    }
    else {
        # Check to see if we have something
        unless (%{$self->{QHash}}) {
            $self->_convert_to_perl;
        }
    }
    return $self->{QHash};
}

=item B<raw_query_hash>

Retrieve query in the form of a perl hash. Entries are either hashes
or arrays. Keys with array references refer to multiple matches (OR
relationship) [assuming there is more than one element in the array]
and Keys with hash references refer to ranges (whose hashes must have
C<max> and/or C<min> as keys).

    $hashref = $query->raw_query_hash();

This is similar to C<query_hash> but has not been post processed
with database table information.

=cut

sub raw_query_hash {
    my $self = shift;
    if (@_) {
        $self->{RawQHash} = shift;
    }
    else {
        # Check to see if we have something
        unless ((exists $self->{'RawQHash'}) and %{$self->{RawQHash}}) {
            $self->_convert_to_perl;
        }
    }
    return $self->{RawQHash};
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

    my $tree = $self->_tree;
    return $tree->toString if defined $tree;

    my $givenhash = $self->_given_hash;
    if (defined $givenhash) {
        require Data::Dumper;
        my $dumper = Data::Dumper->new([$givenhash], [$self->_root_element]);
        $dumper->Indent(0);
        $dumper->Sortkeys(1);
        return $dumper->Dump;
    }

    return 'UNDEFINED';
}

=item B<_root_element>

Class method that returns the name of the XML root element to be
located in the query XML. This changes depending on whether we
are doing an MSB or Project query. Must be specified in a subclass.
Returns "Query" by default.

=cut

sub _root_element {
    return "Query";
}

=item B<_qhash_tosql>

Convert a query hash to a SQL WHERE clause. Called by sub-classes
in order prior to inserting the clause into the main SQL query.

    $where = $q->_qhash_tosql(\@skip);

First argument is a reference to an array that contains the names of
keys in the query hash that should be skipped when constructing the
SQL.

Returned SQL segment does not include "WHERE".

=cut

sub _qhash_tosql {
    my $self = shift;
    my $skip = shift;
    $skip = [] unless defined $skip;

    # Retrieve the perl version of the query
    my $query = $self->query_hash;

    # Remove the elements that are not "useful"
    # ie those that start with _ and those that
    # are in the skip array
    # [tried it with a grep but it didnt work first
    # time out - may come back to this later]
    my @keys;
    for my $entry (sort keys %$query) {
        next if $entry =~ /^_/;
        next if grep /^$entry$/, @$skip;
        push @keys, $entry;
    }

    # Walk through the hash generating the core SQL
    # a chunk at a time - skipping if required
    my @sql = grep {defined $_}
        map {$self->_create_sql_recurse($_, $query->{$_})}
        @keys;

    # Now join it all together with an AND
    my $clause = join ' AND ', @sql;

    # Return the clause
    return $clause;
}


=item B<_create_sql_recurse>

Routine called to translate each key of the query hash into SQL.
Separated from C<_qhash_tosql> in order to allow recursion.
Returns a chunk of SQL

    $sql = $self->_create_sql_recurse($column, $entry);

where C<$column> is the database column name and
C<$entry> can be

=over 4

=item *

An array of values that will be ORed.

=item *

An OMP::Range object.

=item *

A hash containing items to be ORed
using the rules for OMP::Range and array refs
[hence recursion]. If a _TYPE field is present in this
hash that can be used in the join rather than OR. ie
_TYPE => 'AND' will allow the hash values to be ANDed.

=back

KLUGE: If the key begins with TEXTFIELD__ a full text search
will be performed.

Note that the hashref option does not use the column name at all
in the final SQL.

Column names beginning with an _ are ignored.

=cut

sub _create_sql_recurse {
    my $self = shift;
    my $column = shift;
    my $entry = shift;

    return undef if $column =~ /^_/;

    my $sql;
    if (ref($entry) eq 'ARRAY') {
        # default to actual column name and simple equality
        my $colname = $column;
        my $cmp = "equal";
        if ($colname =~ /^TEXTFIELD__/) {
            $colname =~ s/^TEXTFIELD__//;
            $cmp = 'fulltext';
            $cmp .= 'boolean' if $colname =~ s/^BOOLEAN__//;
        }

        # Link all of the search queries together with an OR [must be inside
        # parentheses].
        $sql = '('
            . join(' OR ', map {$self->_querify($colname, $_, $cmp);} @{$entry})
            . ')';
    }
    elsif (UNIVERSAL::isa($entry, "OMP::Range")) {
        # A Range object
        my %range = $entry->minmax_hash;

        # an AND clause
        $sql = join(" AND ",
            map {$self->_querify($column, $range{$_}, $_);}
            reverse sort keys %range);
    }
    elsif (UNIVERSAL::isa($entry, 'OMP::Query::Any')) {
        # Do nothing.
    }
    elsif (UNIVERSAL::isa($entry, 'OMP::Query::Null')) {
        $sql = $self->_querify($column, $entry->null(), 'null');
    }
    elsif (UNIVERSAL::isa($entry, 'OMP::Query::True')) {
        $sql = $self->_querify($column, $entry->true(), 'true');
    }
    elsif (eval {$entry->isa('OMP::Query::In')}) {
        $sql = $self->_querify($column, $entry->values(), 'in');
    }
    elsif (eval {$entry->isa('OMP::Query::Like')}) {
        $sql = $self->_querify($column, $entry->value(), 'like');
    }
    elsif (eval {$entry->isa('OMP::Query::SubQuery')}) {
        my $expr = $entry->expression;
        my $table = $entry->table;
        my $subquery = $entry->query;

        # Assume operator is "IN" for now.
        my $condition = "SELECT $expr FROM $table";
        if (scalar %$subquery) {
            $condition .= " WHERE "
            . (join ' AND ', map {$self->_create_sql_recurse($_, $subquery->{$_})} sort keys %$subquery);
        }

        $sql = "($column IN ($condition))";
    }
    elsif (ref($entry) eq 'HASH') {
        # Call myself but join with an OR or AND
        my @chunks = map {$self->_create_sql_recurse($_, $entry->{$_})}
            sort keys %$entry;

        # Use an OR by default but if we have a key _JOIN then use it
        my $j = (exists $entry->{_JOIN} ? uc($entry->{_JOIN}) : "OR");

        # Are we applying a function to the result?
        my $func = (exists $entry->{'_FUNC'} ? $entry->{'_FUNC'} : '');

        # Need to bracket each of the sub entries
        $sql = $func . "("
            . join(" $j ", map {"($_)"} grep {defined $_} @chunks) . ")";
    }
    else {
        throw OMP::Error::DBMalformedQuery(
            "Query hash contained a non-ARRAY non-OMP::Range non-HASH for $column: $entry\n");
    }

    return $sql;
}

=item B<_qhash_relevance>

Get a list of relevance expressions for the TEXTFIELD values in this query.

    my @relevance = $q->_qhash_relevance();

=cut

sub _qhash_relevance {
    my $self = shift;

    return $self->_qhash_relevance_recurse($self->query_hash());
}

sub _qhash_relevance_recurse {
    my $self = shift;
    my $query = shift;

    my @relevance = ();

    while (my ($colname, $entry) = each %$query) {
        next if $colname =~ /^_/;
        if (ref($entry) eq 'ARRAY') {
            if ($colname =~ /^TEXTFIELD__/) {
                push @relevance, $self->_create_sql_recurse($colname, $entry);
            }
        }
        elsif (ref($entry) eq 'HASH') {
            push @relevance, $self->_qhash_relevance_recurse($entry);
        }
    }

    return @relevance;
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

    my %query;
    my $tree = $self->_tree;
    if (defined $tree) {
        my $rootelement = $self->_root_element();

        # Get the root element
        my @msbquery = $tree->findnodes($rootelement);
        throw OMP::Error::MSBMalformedQuery(
            "Could not find <$rootelement> element")
            unless @msbquery == 1;
        my $msbquery = $msbquery[0];

        %query = $self->_convert_elem_to_perl($msbquery);
    }
    else {
        my $givenhash = $self->_given_hash;
        throw OMP::Error::MSBMalformedQuery(
            "Query has neither XML nor given HASH")
            unless defined $givenhash;

        %query = $self->_process_given_hash($givenhash);
    }

    # Store it before post-processing
    $self->raw_query_hash({%query});

    # Do some post processing to convert to OMP::Ranges and
    # to fix up some standard keys
    $self->_post_process_hash(\%query);

    # Store the hash
    $self->query_hash(\%query);

    #  use Data::Dumper;
    #  print STDERR Dumper(\%query);
}

=item B<_convert_elem_to_perl>

Convert parsed XML element to intermediate hash representation.

    my %query = $self->_convert_elem_to_perl($element);

=cut

sub _convert_elem_to_perl {
    my $self = shift;
    my $msbquery = shift;

    my %query = ();

    # Loop over children
    my $i = 0;
    for my $child ($msbquery->childNodes) {
        my $name = $child->getName;
        #print "Name: $name\n";

        if (grep {$name eq $_} qw/or not/) {
            my %expr = $self->_convert_elem_to_perl($child);
            # Check if the expression is empty.  We have to do this here
            # as we check for non-white-space values at this level (see
            # the PCDATA case below).
            next unless scalar %expr;
            if ($name eq 'or') {
                $query{'EXPR__' . ++ $i} = {
                    _JOIN => 'OR',
                    %expr};
            }
            elsif ($name eq 'not') {
                $query{'EXPR__' . ++ $i} = {
                    _JOIN => 'AND',
                    _FUNC => 'NOT',
                    %expr};
            }
            else {
                die 'Block name was matched but is now not recognized';
            }
            next;
        }

        # Get the attributes
        my %attr = map {$_->getName, $_->getValue} $child->getAttributes;

        # Now need to look inside to see what the children are
        for my $grand ($child->childNodes) {
            if ($grand->isa("XML::LibXML::Text")) {
                # This is just PCDATA

                # Make sure this is not simply white space
                my $string = $grand->textContent;
                next unless $string =~ /\w/;

                $self->_add_text_to_hash(\%query, $name, $string, \%attr);
            }
            else {
                # We have an element. Get its name and add the contents
                # to the hash (we assume only one text node)
                my $childname = $grand->getName;

                # it is possible for the xml to be <max/> (sent by the QT
                # so we must trap that
                my $firstchild = $grand->firstChild;
                if ($firstchild) {
                    $self->_add_text_to_hash(
                        \%query, $name, $grand->textContent, $childname, \%attr);
                }
                elsif ($childname eq 'null') {
                   # Allow <null/> as a special case (short for <null>1</null>).
                    $self->_add_text_to_hash(
                        \%query, $name, '1', $childname, \%attr);
                }
            }
        }
    }

    return %query;
}

=item B<_add_text_to_hash>

Add content to the query hash. Compares keys of arguments with
the existing content and does the right thing depending on whether
the key has occurred before or it has a special case (null, max or min).

    $query->_add_text_to_hash(\%query, $key, $value, $secondkey);

The secondkey is used as the primary key unless it is one of the
special reserved key (null, min or max). In that case the secondkey
is used as a hash key in the hash pointed to by $key.

For example, key=instruments value=cgs4 secondkey=instrument

    $query{instrument} = ["cgs4"];

key=elevation value=20 sescondkey=max

    $query{elevation} = {max => 20}

key=instrument value=scuba secondkey=undef

    $query{instrument} = ["cgs4", "scuba"];

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
    if (ref($_[-1]) eq 'HASH') {
        $attr = pop(@_);
    }

    # Read any remaining args
    my $secondkey = shift;

    # Check to see if we have a special key
    $secondkey = '' unless defined $secondkey;
    my $special = ($secondkey =~ /max|min|null|like/ ? 1 : 0);

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
        }
        else {
            # Append it to the array
            push(@{$hash->{$key}}, $value);
        }
    }
    else {
        if ($special) {
            $hash->{$key} = {$secondkey => $value};
        }
        else {
            $hash->{$key} = [$value];
        }
    }

    # Store attributes if they are supplied
    $hash->{_attr} = {} unless exists $hash->{_attr};
    $hash->{_attr}->{$key} = $attr if defined $attr;
}

=item B<_process_given_hash>

Process an explicitly given query hash to produce a similar intermediate
representation as C<_convert_elem_to_perl> would do.

    my %query = $self->_process_given_hash($hashref);

This method promotes scalar values to single-element arrays.
It ensures that there is an entry in C<_attr> for each key in
in the given hash.  Values can be hashes including the
following sets of keys:

=over 4

=item value, delta

Moves the C<delta> parameter to the C<_attr> section.

=item value, mode

Moves the C<mode> parameter to the C<_attr> section.

=item boolean =E<gt> 0 | 1

Converted to C<OMP::Query::True> object.

=item or =E<gt> \%subquery

Converted to OR expresion.  (Key name is arbitrary, should start C<EXPR__>.)

=item not =E<gt> \%subquery

Converted to NOT expresion.  (Key name is arbitrary, should start C<EXPR__>.)

=item and =E<gt> \%subquery

Converted to AND expresion.  (Key name is arbitrary, should start C<EXPR__>.)

=item min, max

Left as is.

=item null =E<gt> 0 | 1

Left as is.

=item any =E<gt> 1

Left as is.

=item in =E<gt> \@values

Left as is.

=back

=cut

sub _process_given_hash {
    my $self = shift;
    my $givenhash = shift;

    my %query = (
        _attr => (exists $givenhash->{'_attr'})
            ? $givenhash->{'_attr'}
            : {},
    );

    foreach my $key (keys %$givenhash) {
        next if $key eq '_attr';
        my $value = $givenhash->{$key};

        # Recognize recursive entries first, before ensuring _attr entry exists.
        if ('HASH' eq ref $value) {
            if (exists $value->{'or'}) {
                $query{$key} = {
                    _JOIN => 'OR',
                    $self->_process_given_hash($value->{'or'})};
                next;
            }
            elsif (exists $value->{'and'}) {
                $query{$key} = {
                    _JOIN => 'AND',
                    $self->_process_given_hash($value->{'and'})};
                next;
            }
            elsif (exists $value->{'not'}) {
                $query{$key} = {
                    _JOIN => 'AND',
                    _FUNC => 'NOT',
                    $self->_process_given_hash($value->{'not'})};
                next;
            }
        }

        $query{'_attr'}->{$key} = {}
            unless exists $query{'_attr'}->{$key};

        if ('ARRAY' eq ref $value) {
            $query{$key} = $value;
        }
        elsif ('HASH' eq ref $value) {
            if (exists $value->{'value'} and exists $value->{'delta'}) {
                $query{$key} = [$value->{'value'}];
                $query{'_attr'}->{$key}->{'delta'} = $value->{'delta'};
            }
            elsif (exists $value->{'value'} and exists $value->{'mode'}) {
                $query{$key} = [$value->{'value'}];
                $query{'_attr'}->{$key}->{'mode'} = $value->{'mode'};
            }
            elsif (exists $value->{'boolean'}) {
                $query{$key} = OMP::Query::True->new(true => $value->{'boolean'});
            }
            else {
                # Pass through representations such as {min => ..., max => ...}.
                $query{$key} = $value;
            }
        }
        else {
            $query{$key} = [$value];
        }
    }

    return %query;
}

=item B<_post_process_hash>

Fix up the query hash according to generic rules. These are:

=over 4

=item *

Convert hashes with min/max to C<OMP::Range> objects.

=item *

Convert dates (anything with "date" in the key) to date objects.

=item *

Dates with an attribute of "delta" (but specified without
a min/max range) will be converted into a range bounded by
the supplied date and the date plus the delta. Default is
for "delta" to be in units of days. A "units" attribute
can be used to change the units. Acceptable units are
"days","hours","minutes","seconds".

    <date range="60" units="minutes">2002-02-04T12:00</date>

will extract data between 12 and 1pm on 2002 April 02.

=back

Specific query manipulation must be done in a subclass (this includes
specifying which fields are TEXT fields and prepending "TEXTFIELD__"
on to the key name).  Note that subclasses must call this method in
order to get the above manipulation.

    $q->_post_process_hash(\%hash);

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
            $self->_process_elements(
                $href,
                sub {
                    my $string = shift;
                    my $date = OMP::DateTools->parse_date($string);
                    throw OMP::Error::DBMalformedQuery(
                        "Error parsing date string '$string'")
                        unless defined $date;
                    return $date;
                },
                [$key]);

            # See if there is a range attribute
            if (exists $href->{_attr}->{$key}->{delta}) {
                # There is but now see if we have an array
                if (ref($href->{$key}) eq 'ARRAY') {
                    # with only one element
                    if (scalar(@{$href->{$key}}) == 1) {
                        # Now convert to a range
                        my $date = $href->{$key}->[0];
                        my $delta = $href->{_attr}->{$key}->{delta};

                        # Get the units
                        my $units = "days";
                        $units = $href->{_attr}->{$key}->{units}
                            if exists $href->{_attr}->{$key}->{units};

                        # Derive sql units
                        my %sqlunits = (
                            'days' => ONE_DAY,
                            'seconds' => 1,
                            'minutes' => ONE_MINUTE,
                            'hours' => ONE_HOUR,
                            'years' => ONE_YEAR,
                        );

                        # KLUGE This returns a Time::Piece object rather than
                        # the class of object that was passed in. Need to rebless
                        my $enddate = $date + $sqlunits{$units} * $delta;
                        bless $enddate, ref($date);

                        my ($min, $max) = ('Min', 'Max');
                        if ($delta < 0) {
                            # negative
                            $min = 'Max';
                            $max = 'Min';
                        }

                        $href->{$key} = OMP::Range->new(
                            $min => $date,
                            $max => $enddate);
                    }
                }
            }
        }
    }

    # Loop over each key looking for "expressions" and ranges
    for my $key (keys %$href) {
        # Skip private keys
        next if $key =~ /^_/;

        if ($key =~ /^EXPR__/) {
            # Recursively process "expression".
            $self->_post_process_hash($href->{$key});
        }
        elsif (ref($href->{$key}) eq "HASH") {
            if (exists $href->{$key}->{'null'}) {
                $href->{$key} = OMP::Query::Null->new(null => $href->{$key}->{'null'});
            }
            elsif (exists $href->{$key}->{'any'}) {
                $href->{$key} = OMP::Query::Any->new();
            }
            elsif (exists $href->{$key}->{'like'}) {
                $href->{$key} = OMP::Query::Like->new(value => $href->{$key}->{'like'});
            }
            elsif (exists $href->{$key}->{'in'}) {
                $href->{$key} = OMP::Query::In->new(values => $href->{$key}->{'in'});
            }
            else {
                # Convert to OMP::Range object
                $href->{$key} = OMP::Range->new(
                    Min => $href->{$key}->{min},
                    Max => $href->{$key}->{max},
                );
            }
        }
    }

    # Convert date

    # Done
}

=item B<_querify>

Convert the column name, column value and optional comparator
to an SQL sub-query.

    $sql = $q->_querify("elevation", 20, "min");
    $sql = $q->_querify("instrument", "SCUBA");

Determines whether we have a number or string for quoting rules.
The string is not quoted if it matches the string "dateadd" since that
is treated as an SQL function.

Some keys are duplicated in different tables. In those cases (project
ID is the main one) the table prefix is automatically added.

A "name" element is converted to a query in both the "pi" and
"coi" fields (ie you are interested in whether the named person
is associated with the project at all). ie for each query on "name"
a query for both "pi" and "coi" is returned with a logical OR.

If a LIKE match is requested the string is automatically surrounded
by "%" (SQL equivalent to ".*"). For now the assumption is that
a LIKE query implies a request to match a sub-string. The substring
probably should not have a "%" included since the code does not
contain a means of escaping the per cent.

If the column name appears in C<%RESERVED_WORDS>, then it is
enclosed in backticks.

=cut

sub _querify {
    my $self = shift;
    my ($name, $value, $cmp) = @_;

    if ($RESERVED_WORDS{$name}) {
        $name = '`' . $name . '`';
    }

    # Default comparator is "equal"
    $cmp = "equal" unless defined $cmp;

    $cmp = lc($cmp);

    # Special case for fulltext search.
    if ($cmp eq 'fulltext' or $cmp eq 'fulltextboolean') {
        $value =~ s/([\\'])/\\$1/g;
        my $modifier = $cmp eq 'fulltextboolean' ? ' IN BOOLEAN MODE' : '';
        return "(MATCH ($name) AGAINST ('$value'$modifier))";
    }
    elsif ($cmp eq 'null') {
        my $expr = $value ? 'NULL' : 'NOT NULL';
        return "($name IS $expr)";
    }
    elsif ($cmp eq 'true') {
        my $expr = $value ? '' : 'NOT';
        return "($expr $name)";
    }
    elsif ($cmp eq 'in') {
        return "($name IN (" . (join ', ', map {"\"$_\""} @$value) . '))';
    }

    # Always quote if we have "like" expression.
    my $quote = '';
    if ($cmp eq 'like') {
        $quote = "'";
    }

    # Lookup table for comparators.
    my %cmptable = (
        equal => '=',
        min => '>=',
        max => '<=',
        like => 'like',
    );

    # Convert the string form to SQL form
    throw OMP::Error::MSBMalformedQuery("Unknown comparator '$cmp' in query\n")
        unless exists $cmptable{$cmp};

    # Also quote if we have word characters or a semicolon
    $quote = "'" if $value =~ /[A-Za-z:]/;

    # We do not want to quote if we have a SQL function
    # dateadd & datediff are special
    $quote = '' if $value =~ /^date(?:add|diff)/i;

    # If we have "name" then we need to create a query on both
    # pi and coi together. This is of course not portable and should
    # not be in the base class implementation
    my @list;
    if ($name eq "name") {
        # two columns
        @list = (qw/ pi C.userid /);
        #@list = (qw/ pi /);
    }
    else {
        @list = ($name);
    }

    # Loop over all keys in list
    my $sql = join(" OR ", map {"$_ $cmptable{$cmp} $quote$value$quote"} @list);

    # Form query
    return $sql
}

=item B<_process_elements>

Process all the array elements or hash members associated with the
supplied keys in the query hash.

    $q->_process_elements(\%qhash, $cb, \@keys);

Where the first argument is the reference to the query hash, the
second argument is a callback (CODEREF) to be executed for each
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

    throw OMP::Error::BadArgs(
        "Third argument to _process_elements must be array ref")
        unless ref($keys) eq "ARRAY";
    throw OMP::Error::BadArgs(
        "Second argument to _process_elements must be code ref")
        unless ref($cb) eq "CODE";

    for my $key (@$keys) {
        # Check it exists
        if (exists $href->{$key}) {
            my $ref = ref($href->{$key});  # The reference type
            my $val = $href->{$key};  # The value

            if (not $ref) {
                # Simple scalar
                $href->{$key} = $cb->($val);
            }
            elsif ($ref eq "ARRAY") {
                # An array
                $href->{$key} = [map {$cb->($_);} @{$val}];
            }
            elsif ($ref eq "HASH") {
                # Simple hash
                my %hash = %$val;
                for my $hkey (keys %hash) {
                    $hash{$hkey} = $cb->($hash{$hkey}) unless $hkey eq 'null';
                }
                $href->{$key} = \%hash;
            }
            elsif ($val->isa("OMP::Range")) {
                $val->min($cb->($val->min)) if defined $val->min;
                $val->max($cb->($val->max)) if defined $val->max;
            }
            elsif ($val->isa('OMP::Query::Like')) {
                $val->value($cb->($val->value));
            }
            elsif ($val->isa('OMP::Query::In')) {
                $val->values([map {$cb->($_)} @{$val->values}]);
            }
            elsif ($val->isa('OMP::Query::SubQuery')) {
                # Do not try to manipulate subquery.
            }
            else {
                throw OMP::Error::DBMalformedQuery(
                    "Unable to process class of type '$ref'");
            }
        }
    }
}

=item B<_set_subquery_table>

Modify the query hash by searching for SubQuery objects for
which the C<filter> function returns a true value and setting
their C<table> attribute to the given value.

    $q->_set_subquery_table($table, $filter, [\%qhash, $parent]);

(The 3rd and 4th arguments of a hash reference and parent key name
are used when this method recurses.)

The C<filter> function is called with the parent key (if present),
key and SubQuery object.

    $filter->($parent, $key, $subquery)

=cut

sub _set_subquery_table {
    my $self = shift;
    my $table = shift;
    my $filter = shift;
    my $qhash = shift;
    my $parent = shift;

    unless (defined $qhash) {
        $qhash = $self->query_hash;
    }
    foreach my $key (keys %$qhash) {
        my $ref = ref $qhash->{$key};
        my $val = $qhash->{$key};

        if (not $ref) {
        }
        elsif ($ref eq "ARRAY") {
        }
        elsif ($ref eq "HASH") {
            $self->_set_subquery_table($table, $filter, $val, $key);
        }
        elsif ($val->isa('OMP::Query::SubQuery')) {
            if ($filter->($parent, $key, $val)) {
                $val->table($table);
            }
        }
    }
}

=back

=head1 Query XML

The Query XML is specified as follows:

=over 4

=item B<Query>

The top-level container element is E<lt>QueryE<gt> although
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

=item B<Null values>

Elements can contain a null element.  This should contain a true
or false value, or be self-closing (implies true).

    <semester><null/></semester>

    <instrument><null>0</null></instrument>

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

=item B<Or blocks>

There can be "or" blocks containing elements to be combined
as alternatives.

    <or>
        <subject>query string</subject>
        <text>query string</text>
    </or>

=item B<Not blocks>

There can also be "not" blocks.

    <not>
        <semester>99X</semester>
    </not>

=back

=head1 SEE ALSO

OMP/SN/004, C<OMP::Query::MSB>

=cut

package OMP::Query::Null;

sub new {
    my $class = shift;
    my %opt = @_;

    my $self = bless {
        null => $opt{'null'},
    }, $class;

    return $self;
}

sub null {
    my $self = shift;
    if (@_) {
        $self->{'null'} = shift;
    }
    return $self->{'null'};
}

package OMP::Query::Any;

sub new {
    my $class = shift;
    my %opt = @_;

    my $self = bless {
    }, $class;

    return $self;
}

package OMP::Query::True;

sub new {
    my $class = shift;
    my %opt = @_;

    my $self = bless {
        true => $opt{'true'},
    }, $class;

    return $self;
}

sub true {
    my $self = shift;
    if (@_) {
        $self->{'true'} = shift;
    }
    return $self->{'true'};
}

package OMP::Query::In;

sub new {
    my $class = shift;
    my %opt = @_;

    return bless {
        values => $opt{'values'},
    }, $class;
}

sub values {
    my $self = shift;
    $self->{'values'} = shift if @_;
    return $self->{'values'};
}

package OMP::Query::Like;

sub new {
    my $class = shift;
    my %opt = @_;

    return bless {
        value => $opt{'value'},
    }, $class;
}

sub value {
    my $self = shift;
    $self->{'value'} = shift if @_;
    return $self->{'value'};
}

package OMP::Query::SubQuery;

sub new {
    my $class = shift;
    my %opt = @_;

    return bless {
        expression => $opt{'expression'},
        query => $opt{'query'},
    }, $class;
}

sub expression {
    my $self = shift;
    $self->{'expression'} = shift if @_;
    return $self->{'expression'};
}

sub table {
    my $self = shift;
    $self->{'table'} = shift if @_;
    return $self->{'table'};
}

sub query {
    my $self = shift;
    $self->{'query'} = shift if @_;
    return $self->{'query'};
}

1;

__END__

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
