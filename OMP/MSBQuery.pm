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

# Package globals

our $VERSION = (qw$Revision$)[1];

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

Returns undef if the XML is not valid.

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
    return undef if $@;
  } else {
    # Nothing of use
    return undef;
  }

  my $q = {
	   Parser => $parser,
	   Tree => $tree,
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

=back

=head2 General Methods

=over 4

=item B<sql>

Returns an SQL representation of the Query using the specified
database table.

  $sql = $query->sql( $table );

Returns undef if the query could not be formed.

=cut

sub sql {
  my $self = shift;
  my $table = shift;

  return "SELECT * FROM $table";
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

=back

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
