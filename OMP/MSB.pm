package OMP::MSB;

=head1 NAME

OMP::MSB - Class representing an OMP Science Program

=head1 SYNOPSIS

  $msb = new OMP::MSB( XML => $xml );
  $msb = new OMP::MSB( Tree => $tree, Refs => \@trees );

=head1 DESCRIPTION

This class can be used to manipulate and interrogate Minimum
Schedulable Blocks (MSB).

=cut


use 5.006;
use strict;
use warnings;
use Carp;

# External modules
use XML::LibXML; # Our standard parser
use Digest::MD5 qw/ md5_hex /;
use OMP::Error;

our $VERSION = (qw$Revision$)[1];

our $DEBUG = 0;

# Overloading
use overload '""' => "stringify";

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

The constructor takes an XML representation of the science
program as argument and returns a new object.

		$msb = new OMP::MSB( XML => $xml );

		$msb = new OMP::MSB( TREE => $tree, REFS => \%refs 
                                     PROJECTID => $proj);

The argument hash can either refer to an XML string or an
C<XML::LibXML::Element> object representing the MSB and, optionally, a
hash of C<XML::LibXML::Element> objects representing any references
referred to in the MSB.  If neither is supplied no object will be
instantiated. If both C<XML> and C<TREE> keys exist, the C<XML> key
takes priority.

The PROJECTID key can be used to inform the MSB the project with
which it is associated. This information can be added at a later 
date by using the C<projectID()> method.

If parsed, the MSB is checked for well formedness. The XML form of the
MSB is assumed to be self-contained (no external references).

=cut

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;

  throw OMP::Error::BadArgs('Usage : OMP::MSB->new(XML => $xml, TREE => $tree)') unless @_;

  my %args = @_;

  my ($parser, $tree);
  my $refs = {};
  if (exists $args{XML}) {
    # Now convert XML to parse tree
    XML::LibXML->validation(1);
    $parser = new XML::LibXML;
    $tree = eval { $parser->parse_string( $args{XML} ) };
    return undef if $@;
  } elsif (exists $args{TREE}) {
    $tree = $args{TREE};
    # Now get the references
    $refs = $args{REFS} if exists $args{REFS};
  } else {
    # Nothing of use
    return undef;
  }

  my $projid;
  $projid = $args{PROJECTID} if exists $args{PROJECTID};

  # Now create our Science Program hash
  my $sp = {
	    ProjectID => $projid,
	    Parser => $parser,
	    XMLRefs => $refs,
	    Tree => $tree,
	    CheckSum => undef,
	    ObsSum => [],
	   };

  # and create the object
  bless $sp, $class;

}

=back

=head2 Accessor Methods

Instance accessor methods. Methods beginning with an underscore
are deemed to be private and do not form part of the publi interface.

=over 4

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

=item B<projectID>

Retrieves or sets the name of the project this MSB is associated with.

  my $pid = $msb->projectID;

=cut

sub projectID {
  my $self = shift;
  if (@_) { $self->{ProjectID} = shift; }
  return $self->{ProjectID};
}

=item B<checksum>

Retrieves or sets the value to be used to uniquely identify the
MSB. This is usually an MD5 checksum determined by the C<find_checksum>
method. The checksum is stored in hexadecimal format.

  $checksum = $msb->checksum;

A C<checksum> attribute is added to the XML tree.

=cut

sub checksum {
  my $self = shift;
  if (@_) { 
    $self->{CheckSum} = shift;

    # And update the XML
    $self->_tree->setAttribute("checksum", $self->{CheckSum});

  } else {
    $self->find_checksum unless defined $self->{CheckSum};
  }
  return $self->{CheckSum};
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

=item B<_xmlrefs>

Retrieves a hash containing the parse trees associated with
elements of the core science program that are referenced by
an MSB. The type of tree depends on the underlying XML parser.

  $hashref = $msb->_xmlrefs;

Returns a reference in scalar context and a hash in list context.

=cut

sub _xmlrefs {
  my $self = shift;
  if (wantarray()) {
    return %{$self->{XMLRefs}};
  } else {
    return $self->{XMLRefs};
  }
}

=item B<obssum>

Returns (or sets) an array containing summary hashes for each
component observation.

  @obs = $msb->obssum;
  $msb->obssum( @obs );

The C<summarize_obs> method is automatically invoked if this
method is called without argument and the array is empty.

Usually called by the C<summary> method to form a summary
of the MSB itself.

=cut

sub obssum {
  my $self = shift;
  if (@_) {
    @{ $self->{ObsSum} } = @_;
  } elsif (scalar(@{$self->{ObsSum}}) == 0) {
    $self->summarize_obs;
  }
  return @{ $self->{ObsSum} };
}


=item B<remaining>

Returns the number of times the MSB is to be observed.

  $remaining = $msb->remaining;

This is related to the C<remaining> attribute of an SpObs
and SpMSB element. The value can also be modified.

  $msb->remaining(5);

or decremented:

  $msb->remaining(-1);

Negative numbers are treated as a special case. When found the
value is subtracted from the current count.

The number remaining can not go below zero.

If the argument is the constant C<MSB::REMOVED>
this indicates that the MSB has not been observed but
it has been removed from consideration (generally because
another MSB has been observed in an SpOR folder).

=cut

# This is an attribute of the XML rather than this object
# but the two are synonymous, the only difference being
# that we do not store the value in our hash

sub remaining {
  my $self = shift;
  if (@_) {
    my $arg = shift;

    # Get the current value
    my $current = $self->_tree->getAttribute("remaining");


    # Decrement the counter if the argument is negative
    # unless either the current value or the new value are the 
    # MAGIC value

    if ($arg != REMOVED() and $current != REMOVED() and $arg < 0){
      $current += $arg;

      # Now Force to zero if necessary
      $current = 0 if $current < 0;

    }

    # Set the new value
    $self->_tree->setAttribute("remaining", $current);
  }

  return $self->_tree->getAttribute("remaining");
}


=back

=head2 General Methods

=over 4

=item B<find_checksum>

Calculates the MD5 checksum associated with the MSB and stores
it in the object. Usually this method is invoked automatically
the first time the C<checksum> method is invoked.

The checksum is calculated from the string form of the MSB
with the outer layer removed (ie the SpMSB or SpObs tags
are not present for the calculation). This is so that the transient
information (eg the number of times the MSB is to be observed) can
be separated from the information that uniquely identifies the MSB.

If the MSB is within a logic element (SpAND or SpOR) then that element
name (actually a substring) is appended to the checksum. This is done
so that we can make some attempt to protect against MSBs being
consolidated when one MSB is in some logic and another is outside some
logic.

=cut

sub find_checksum {
  my $self = shift;

  # Get all the children (this is "safer" than stringifying
  # the XML and stripping off the tags and allows me to expand references).
  # I want to do this without having to know anything about XML.

  my $string = $self->_get_qualified_children_as_string;

  # and generate a checksum
  my $checksum = md5_hex( $string );

  # In order to ditinguish MSBs associated with logic we prefixx
  # an OR and/or AND if the MSB is in such a construct. Otherwise
  # the MSB consolidation code might move MSBs out of a logic block
  # without realising the effect it will have. This is a first order
  # effect - if people start copying MSBs around within the same or
  # other logic then this fix wont be good enough.
  $checksum .= "O" if $self->_tree->findnodes('ancestor-or-self::SpOR');
  $checksum .= "A" if $self->_tree->findnodes('ancestor-or-self::SpAND');

  # And store it
  $self->checksum($checksum);

}

=item B<summary>

Summarize the MSB.  This is useful for providing entries in the
feedback system and summaries for the query tool.

In list context, returns the summary as a hash:

  %summary = $msb->summary();

All keys are lower-cased. The hash includes a special key.
C<summary> contains a hash with the following keys:

  string => Plain text representation suitable for a log file.
  header => Header text suitable for first line of log file.
  keys   => Array of keys, in order, used to create the text summary.

In scalar context the summary is returned in XML format:

  $string = $msb->summary();

The XML format will be something like the following:

 <SpMSBSummary id="string">
    <checksum>de252f2aeb3f8eeed59f0a2f717d39f9</checksum>
    <remaining>2</remaining>
     ...
  </SpMSBSummary>

where the elements match the key names in the hash. An C<id> key
is treated specially. When present this id is used in the SpMSBSummary
element directly.

If an optional argument is supplied this method will act like
a class method that uses the supplied hash to form a summary rather
than the object itself.

  $summary = OMP::MSB->summary( \%hash );

Warnings will be issued if fundamental keys such as "remaining",
"checksumn" and "projectid" are missing.

=cut

sub summary {
  my $self = shift;

  my %summary;
  if (@_) {
    my $summary_ref = shift;
    %summary = %$summary_ref;
  } else {

    # Populate the hash from the object if no arg
    $summary{checksum} = $self->checksum;
    $summary{remaining} = $self->remaining;
    $summary{projectid} = $self->projectID;

    my @obs = $self->obssum;

  }

  # Summary string
  my $head = "Project  Remainder  Checksum\n";
  my $string = "$summary{projectid}\t$summary{remaining}\t$summary{checksum}";

  $summary{summary} = {
		       keys => [qw/projectid remaining checksum/],
		       string => $string,
		       header => $head,
		      };


  if (wantarray()) {
    # Hash required
    return %summary;

  } else {
    # XML version
    my $xml = "<SpMSBSummary ";
    $xml .= "id=\"$summary{id}\"" if exists $summary{id};
    $xml .= ">\n";

    for my $key (keys %summary) {
      # Special case the summary and ID keys
      next if $key eq "summary";
      next if $key eq "id";

      $xml .= "<$key>$summary{$key}</$key>\n";

    }
    $xml .= "</SpMSBSummary>\n";

    return $xml;

  }

}

=item B<hasBeenObserved>

Indicate that this MSB has been observed. This involves decrementing
the C<remaining()> counter by 1 and, if this is part of an SpOR block
and the parent tree is accessible, adjusting the logic.

It is usually combined with an update of the database contents to reflect
the modified state.

If the MSB is within an SpOR the following occurs in addition to
decrementing the remaining counter:

 - Move the MSB (and enclosing SpAND) out of the SpOR into the
   main tree

 - Decrement the counter on the SpOR.

 - Since MSBs are currently located in a science programby name
   without checking for SpOR counter, if the SpOR counter hits zero all
   remaining MSBs are marked with the magic value for remaining() to
   indicate they have been removed by the OMP rather than by
   observation.

This all requires that there are no non-MSB elements in an SpOR
since inheritance breaks if we move just the MSB (that is only
true if the OT ignores IDREF attributes).

=cut

sub hasBeenObserved {
  my $self = shift;

  # This is the easy bit
  $self->remaining( -1 );

  # Now for the hard part... SpOr/SpAND

  # First have to find out if I have a parent that is an SpOR
  my ($SpOR) = $self->_tree->findnodes('ancestor-or-self::SpOR');

  if ($SpOR) {

    # Okay - we are in a logic nightmare

    # First see if we are in an SpAND
    my ($SpAND) = $self->_tree->findnodes('ancestor-or-self::SpAND');

    # Now we need to move the MSB or the enclosing SpAND to
    # just after the SpOR

    # Decide what we are moving
    my $node = ( $SpAND ? $SpAND : $self->_tree );

    # Now find the parent of the SpOR since we have to insert in
    # the parent relative to the SpOR
    my $ORparent = $SpOR->parentNode;

    # Unbind the node we are moving from its parent
    $node->unbindNode;

    # Move it
    $ORparent->insertAfter($node, $SpOR );

    # Now decrement the counter on the SpOR
    my $n = $SpOR->getAttribute("numberOfItems");
    $n--;
    $n = 0 if $n < 0;
    $SpOR->setAttribute("numberOfItems", $n);

    # If the number of remaining items is 0 we need to go
    # and find all the MSBs that are left and fix up their
    # "remaining" attributes so that they will no longer be accepted
    # This code is identical to that in OMP::SciProg so we should
    # be doing this in a cleverer way.
    # For now KLUGE KLUGE KLUGE
    if ($n == 0) {
      print "Attempting to REMOVE remaining MSBs\n" if $DEBUG;
      my @msbs = $SpOR->findnodes(".//SpMSB");
      print "Located SpMSB...\n" if $DEBUG;
      push(@msbs, $SpOR->findnodes('.//SpObs[@msb="true"]'));
      print "Located SpObs...\n" if $DEBUG;

      for (@msbs) {
	# Eek this should be happening on little OMP::MSB objects
	$_->setAttribute("remaining",REMOVED());
      }
    }

  }

}


=item B<stringify>

Convert the MSB object into XML.

  $xml = $msb->stringify;

This method is also invoked via a stringification overload.

  print "$sp";

By default the XML is fully expanded in the sense that references (IDREFs)
are resolved and included.

  $resolved = $msb->stringify;
  $resolved = "$msb";

=cut

sub stringify {
  my $self = shift;

  # Getting the children is easy.
  my $resolved = $self->_get_qualified_children_as_string;

  my $tree = $self->_tree; # for efficiency;

  # We now need the wrapper element and it's attributes
  my @attr = $tree->getAttributes;
  my $name = $tree->getName;

  # Build up the wrapper
  return "<$name ".
    join(" ",
	 map { $_->getName . '="'. $_->getValue .'"' } @attr)
      .">\n"
	. $resolved
	  . "\n</$name>";


}

=item B<stringify_noresolve>

Convert the parse tree to XML string without resolving any
internal references. This returns the XML equivalent to that
found in the original science program.

=cut

sub stringify_noresolve {
  my $self = shift;
  return $self->_tree->toString;
}


=item B<summarize_obs>

Walk through the MSB calculating a summary for each observation
that is present.

We have to walk through the tree properly in order to determine
correct inheritance. This is a pain. The alternative is to find
each observe and then find ancestors and siblings - problem here
is to stop XPath going beyond the MSB itself.
We are essentially doing a SAX parse.

When complete, the object contains an array of summary hashes
that can be returned using the C<obssum> method. The same array
is returned by this method on completion.

=cut

sub summarize_obs {
  my $self = shift;


  # Get an element
  # If a processing method exists simply call it with
  # a hash containing the current state.
  # if returns a new hash with the new state

  my %status; # for storing current parameters
  my @obs; # for storing results
  # Get all the children and loop over them
  for ( $self->_tree->getChildnodes ) {

    # Resolve refs if required
    my $el = $self->_resolve_ref( $_ );

    # Get the name of the item
    my $name = $el->getName;
    print "Name is $name \n";

    if ($self->can($name)) {
      if ($name eq 'SpObs') {
	# Special case. When it is an observation we want to
	# return the final hash for the observation rather than
	# an augmented hash used for inheritance
	push(@obs, $self->SpObs($el, %status ));
	
      } else {
	%status = $self->$name($el, %status );	
      }
    }
  }

  # Now we have all the hashes we can store them in the object
  $self->obssum( @obs ) if @obs;

  use Data::Dumper;
  print Dumper(\@obs);

  return @obs;
}

=item B<_get_qualified_children>

Retrieve the parse trees that represent the component
elements of the MSB. This includes resolved references (any 
element that looks like <SpXXXRef idref="blah"> is replaced
with the corresponding <SpXXX id="blah">).

  @children = $msb->_get_qualified_children;

=cut

sub _get_qualified_children {
  my $self = shift;

  # First get the children with findnodes and then for each of those
  # store either the element itself, or for references, the resolved
  # node.
  my @children = 
    map { 
      $self->_resolve_ref( $_ );
    } $self->_tree->findnodes('child::*');

  return @children;

}


=item B<_get_qualified_children_as_string>

Obtain a stringified form of the child elements of the MSB with
all the references resolved.

  $string = $msb->_get_qualified_children_as_string;

=cut

sub _get_qualified_children_as_string {
  my $self = shift;

  my @children = $self->_get_qualified_children;

  # Now generate a string form of the MSB
  my $string;
  for my $child (@children) {
    $string .= $child->toString;
  }

  return $string;
}

=item B<_resolve_ref>

Given a reference node, translate it to the corresponding
element.

 $el = $mab->_resolve_ref( $ref );

Returns itself if there is no idref. Raises an exception if there is
an idref but it can not be resolved.

=cut

sub _resolve_ref {
  my $self = shift;
  my $ref = shift;

  my $idref;
  $idref= $ref->getAttribute("idref") if $ref->can("getAttribute");
  return $ref unless defined $idref;

  # We have to make sure that we have the key
  my $el;
  if (exists $self->_xmlrefs->{$idref}) {
    # ...and do the replacement if we need to
    # using the implicit aliasing of the loop variable
    $el = $self->_xmlrefs->{$idref};
  } else {
    throw OMP::Error::FatalError("There is a reference to an element that does not exist (idref=$idref)\n");
  }
  return $el;
}


=item B<_get_pcdata>

Given an element and a tag name, find the element corresponding to
that tag and return the PCDATA entry from the last matching element.

 $pcdata = $msb->_get_pcdata( $el, $tag );

Convenience wrapper.

=cut

sub _get_pcdata {
  my $self = shift;
  my ($el, $tag ) = @_;
  my @tauband = $el->getElementsByTagName( $tag );
  my $pcdata;
  $pcdata = $tauband[-1]->firstChild->toString
    if @tauband;
  return $pcdata;
}

# Methods associated with individual elements

=item B<SpObs>

Walk through an SpObs element to determine its parameters.

Takes as argument the object representing the SpObs element
in the tree and a hash of C<default> parameters derived from
components prior to this element in the hierarchy.
Returns a reference to a hash summarizing the observation.

  $summaryref = $msb->SpObs( $el, %default );

Raises an C<MSBMissingObserve> exception if the observation
does not include an observe iterator (the thing that actually
triggers the translator to take data.

Note that there is an argument that can be made to make C<OMP::Obs>
an even more fundamental class...

=cut

sub SpObs {
  my $self = shift;
  my $el = shift;
  my %summary = @_;
  print "In SpOBS\n";

  throw OMP::Error::MSBMissingObserve("SpObs is missing an observe iterator\n")
    unless $el->findnodes(".//SpIterObserve");

  # Now walk through all the child elements extracting information
  # and overriding the default values (if present)
  # This is almost the same as the summarize() method but I can not
  # think of an obvious way to combine the loops and recursion seems
  # like overkill since I dont want to go down multiple depths in the
  # tree.
  for ( $el->getChildnodes ) {
    # Resolve refs if necessary
    my $el = $self->_resolve_ref( $_ );
    my $name = $el->getName;
    print "SpObs: $name\n";
    %summary = $self->$name( $el, %summary )
      if $self->can( $name );
  }

  return \%summary;

}

=item B<SpInstCGS4>

Examine the structure of this name and add information to the
argument hash.

  %summary = $self->SpInstCGS4( $el, %summary );

where C<$el> is the XML node object and %summary is the
current hierarchy.

=cut

sub SpInstCGS4 {
  my $self = shift;
  my $el = shift;
  my %summary = @_;

  $summary{instrument} = "CGS4";

  return %summary;
}

=item B<SpInstUFTI>

Examine the structure of this name and add information to the
argument hash.

  %summary = $self->SpInstUFTI( $el, %summary );

where C<$el> is the XML node object and %summary is the
current hierarchy.

=cut

sub SpInstUFTI {
  my $self = shift;
  my $el = shift;
  my %summary = @_;

  $summary{instrument} = "UFTI";

  return %summary;
}

=item B<SpInstMichelle>

Examine the structure of this name and add information to the
argument hash.

  %summary = $self->SpInstMichelle( $el, %summary );

where C<$el> is the XML node object and %summary is the
current hierarchy.

=cut

sub SpInstMichelle {
  my $self = shift;
  my $el = shift;
  my %summary = @_;

  $summary{instrument} = "Michelle";

  return %summary;
}

=item B<SpInstIRCAM3>

Examine the structure of this name and add information to the
argument hash.

  %summary = $self->SpInstIRCAM3( $el, %summary );

where C<$el> is the XML node object and %summary is the
current hierarchy.

=cut

sub SpInstIRCAM3 {
  my $self = shift;
  my $el = shift;
  my %summary = @_;

  $summary{instrument} = "IRCAM3";

  return %summary;
}

=item B<SpSiteQualityObsComp>

Site quality component.

 %summary = $msb->SpSiteQualityObsComp( $el, %summary );

=cut

sub SpSiteQualityObsComp {
  my $self = shift;
  my $el = shift;
  my %summary = @_;
  print "In site quality\n";
  # Need to get "seeing" and "tauband"
  $summary{tauband} = $self->_get_pcdata( $el, "tauBand" );
  $summary{seeing} = $self->_get_pcdata( $el, "seeing" );

  return %summary;
}

=back

=head1 CONSTANTS

The following constants are available from this class:

=over 4

=item B<MSB::REMOVED>

The magic value indicating to C<remaining()> that the MSB
should be removed from further consideration even though it
has not been observed.

=cut

use constant REMOVED => -999;

=back

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;

