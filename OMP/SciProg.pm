package OMP::SciProg;

=head1 NAME

OMP::SciProg - Class representing an OMP Science Program

=head1 SYNOPSIS

  $sp = new OMP::SciProg( XML => $xml );
  @msbs = $sp->msbs;


=head1 DESCRIPTION

This class manipulates OMP Science Programs.

=cut

use 5.006;
use strict;
use warnings;
use Carp;

# External modules
use XML::LibXML; # Our standard parser
use OMP::MSB;    # Standard MSB organization
use OMP::Error;

our $VERSION = (qw$Revision$)[1];

# Overloading
use overload '""' => "stringify";


=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

The constructor takes an XML representation of the science
program as argument and returns a new object.

		$sp = new OMP::SciProg( XML => $xml );

		$sp = new OMP::SciProg( FILE => $xmlfile );

The argument hash can either refer to an XML string or
an XML file. If neither is supplied no object will be
instantiated. If both C<XML> and C<FILE> keys exist, the
C<XML> key takes priority.

The science program is checked for well formedness and its validity
against the DTD. Throws an SpBadStructure exception if the science
program is neither valid nor well-formed.

=cut

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;

  throw OMP::Error::BadArgs('Usage : OMP::SciProg->new(XML => $xml, FILE => $file)') unless @_;

  my %args = @_;

  my $xml;
  if (exists $args{XML}) {
    $xml = $args{XML};
  } elsif (exists $args{FILE}) {
    # Dont check for existence - the open will do that for me
    open my $fh, "<$args{FILE}" or return undef;
    local $/ = undef; # slurp whole file
    $xml = <$fh>;
  } else {
    # Nothing of use
    return undef;
  }

  # Now convert XML to parse tree
  XML::LibXML->validation(1);
  my $parser = new XML::LibXML;
  my $tree = eval { $parser->parse_string( $xml ) };
  if ($@) {
    throw OMP::Error::SpBadStructure("Error whilst parsing science program: $@\n");
  }


  # Now create our Science Program hash
  my $sp = {
	    Parser => $parser,
	    Tree => $tree,
	    MSBS => [],
	    REFS => {},
	   };

  # and create the object
  bless $sp, $class;

  # Since it is possible for some one to attempt to write this
  # science program to disk without needing the MSBs and since
  # the MSB finding can change the form of the Science Program
  # by consolidating identical MSBs to a single MSB we need to make
  # sure that the consolidation is triggered immediately
  $sp->msb;

  return $sp;
}

=back

=head2 Accessor Methods

Instance accessor methods. Methods beginning with an underscore
are deemed to be private and do not form part of the publi interface.

=over 4

=item B<projectID>

Returns the project ID associated with this science program.

  $projectid = $sp->projectID;

=cut

sub projectID {
  my $self = shift;
  if (@_) { 
    $self->{ProjectID} = shift; 
  } else {
    $self->find_projectid unless defined $self->{ProjectID};
  }
  return $self->{ProjectID};
}

=item B<msb>

Return the C<OMP::MSB> objects associated with this science program.

  @msbs = $sp->msb;

If no MSBs are stored we automatically go and look for them using
C<locate_msbs()>.

=cut

sub msb {
  my $self = shift;
  if (@_) { 
    @{ $self->{MSBS} } = @_; 
  } else {
    # check to see if we have something
    unless (@{$self->{MSBS}}) {
      $self->locate_msbs;
    }
  }
  return @{ $self->{MSBS} };
}

=item B<refs>

Return a hash (reference) containing all the XML elements that
have ID tags. The hash keys are the ID attribute values (since these
are unique for a given science program). The XML is represented
by parse trees.

  $hashref = $sp->refs;
  %refs = $sp->refs;

Returns a hash reference in scalar context, a hash in list context.
The object can be populated by using a hash argument.

  $sp->refs( %refs );

The values in the hash are not checked (so we do not enforce
object type).

If no keys are stored we automatically run C<locate_refs>.

=cut

sub refs {
  my $self = shift;
  if (@_) { 
    %{ $self->{REFS} } = @_; 
  } else {
    # If people are asking for the refs we want to find them
    # if we havent already got them.
    unless (keys %{$self->{REFS}}) {
      # Only do this if we havent got anything in the hash
      $self->locate_refs;
    }
  }

  # Return the correct thing for the context
  if (wantarray() ) {
    return %{ $self->{REFS} };
  } else {
    return $self->{REFS};
  }
}

=item B<_parser>

Retrieves or sets the underlying XML parser object.

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

=item B<timestamp>

Set or retrieve a timestamp associated with the science program.
In general this is the timestamp of the science program most
recently written to disk in the database. The XML representation
is updated if the timestamp is updated.

Returns undef if the science program has never been stored.

=cut

sub timestamp {
  my $self = shift;
  if (@_) {
    my $timestamp = shift;
    $self->_tree->documentElement->setAttribute( "timestamp", $timestamp );
  }
  return $self->_tree->documentElement->getAttribute( "timestamp" );
}

=back

=head2 General Methods

=over 4

=item B<summary>

Summarize the science program. This can either be in the form
of an XML string containing summaries of all the MSBs, or as an
array of text where each line is an ASCII summary of each
MSB (the first line of which is the column names).

The XML summary is of the form

  <SpProgSummary>

    <SpMSBSummary>
      ...
    </SpMSBSummary>
    <SpMSBSummary>
      ...
    </SpMSBSummary>

  </SpProgSummary>

where the SpMSBSummary element is defined in L<OMP::MSB>.

=cut

sub summary {
  my $self = shift;

  if (wantarray()) {
    # Plain text
    my @strings;
    for my $msb ($self->msb) {
      my %summary = $msb->summary;
      # The title
      push(@strings, $summary{summary}{header} ) unless @strings;
      # The contents
      push(@strings,  $summary{summary}{string} );
    }

    return @strings;

  } else {
    # XML version
    my $xml = "<SpProgSummary>\n";

    for my $msb ($self->msb) {
      $xml .= $msb->summary;
    }
    $xml .= "</SpProgSummary>\n";

    return $xml;

  }


}


=item B<find_projectid>

Determine the project ID of the science program and store the information
in the object.

Automatically invoked by the C<projectID()> method the first time
that method is invoked.

=cut

sub find_projectid {
  my $self = shift;

  my ($element) = $self->_tree->findnodes('.//projectID[1]');

  # projectID element contains PCData that is the actual project ID
  if (defined $element) {
    $self->projectID( $element->getFirstChild->toString );
  } else {
    throw OMP::Error::UnknownProject("The Science Program does not contain a project identifier");
  }

}

=item B<fetchMSB>

Given a checksum, search through the science program for a matching
MSB.

  $msb = $sp->fetchMSB( $checksum );

The MSB is returned as an OMP::MSB object. Returns C<undef> on error.

=cut

sub fetchMSB {
  my $self = shift;
  my $checksum = shift;

  my $found;
  for my $msb ($self->msb) {
    if ($checksum eq $msb->checksum) {
      $found = $msb;
      last;
    }
  }
  return $found;
}

=item B<locate_msbs>

Find the MSBs within a science program and store references
to them.

  $sp->locate_msbs

Usually called during object initialisation. Use the C<msb()> method
to retrieve the MSB objects

MSBs are indicated by either C<SpMSB> elements or lone C<SpObs> elements.

Duplicate MSBs (i.e. those that do exactly the same thing) are consolidated
into a single MSB by determining the total count and then removing
all but the first MSB from the tree.

=cut

sub locate_msbs {
  my $self = shift;

  # Find all the SpMSB elements
  my @spmsb = $self->_tree->findnodes("//SpMSB");

  # Find all the SpObs elements that are not in SpMSB
  # Don't worry about this yet - need to think about the XPath
  # syntax
  push( @spmsb, $self->_tree->findnodes('//SpObs[@msb="true"]'));

  # Create new OMP::MSB objects
  my $refhash = $self->refs;
  my $projectid = $self->projectID;
  my @objs = map { new OMP::MSB( TREE => $_, 
				 REFS => $refhash,
				 PROJECTID => $projectid ) } @spmsb;

  # Remove duplicates
  # Build up a hash keyed by checksum
  my %unique;
  my $unbound = 0;
  for my $msb (@objs) {
    my $checksum = $msb->checksum;
    if (exists $unique{$checksum}) {
      # Increment the first MSB by the amount remaining in the current MSB
      my $newtotal = $unique{$checksum}->remaining() + $msb->remaining();
      $unique{$checksum}->remaining($newtotal);

      # Remove the current msb object from the science program tree
      $msb->_tree->unbindNode;
      $unbound = 1;

    } else {
      $unique{$checksum} = $msb;
    }
  }

  # If we've deleted some msbs from the tree we need to rescan 
  # the internal idrefs to make sure that we are no longer holding
  # references to objects that are not in the tree
  # Note that since we store a hash reference in the MSB objects
  # we can just update the hash itself. If OMP::MSB copies the hash
  # we are in trouble.
  # if we dont do this we are bound to get a core dump at some point
  # it is quicker to use a variable to indicate that we had
  # duplicates rather than compare the contents of @objs with the
  # contents of "values %unique"
  $self->locate_refs if $unbound;

  # The hash now contains all the unique objects
  @objs = values %unique;

  # And store them
  $self->msb(@objs);

}

=item B<locate_refs>

Find all the objects that have XML ID strings and store them
in a hash (keyed by ID).

Effectively this is simply XPath but it stores the results for easy
retrieval (caching).

=cut

sub locate_refs {
  my $self = shift;

  # Find all the elements with IDs
  # This returns the actual attribute objects
  my @refs = $self->_tree->findnodes('//@id');

  # Now for each of these determine the ID
  # and store it in a hash
  my %refs;
  for my $el (@refs) {
    my $key = $el->getValue();
    # and store the parent
    $refs{$key} = $el->getOwnerElement;
  }

  # Just to make sure we have something in the hash we make something
  # up here so that the refs() method can tell the difference between
  # no references (but we were invoked) and no references (bur we haven't
  # been invoked yet). Thus avoiding the additional overhead of scanning
  # the science program multiple times even though we know there are no
  # refs
  $refs{__Been_here_already} = undef;

  # Store it in the object
  $self->refs( %refs );

}


=item B<stringify>

Convert the Science Program object into XML.

  $xml = $sp->stringify;

This method is also invoked via a stringification overload.

  print "$sp";

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

