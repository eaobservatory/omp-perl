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
use OMP::General;
use OMP::Range;
use OMP::Info::MSB;
use OMP::Info::Obs;
use OMP::Constants qw/ :msb /;
use Astro::Coords;
use Astro::WaveBand;

our $VERSION = (qw$Revision$)[1];

our $DEBUG = 0;

# Overloading
use overload '""' => "stringify";

# Specify default time interval. These limits
# are the limits of unix epoch (more or less)
our $MAXTIME = OMP::General->parse_date("2035-01-01T01:00");
our $MINTIME = OMP::General->parse_date("1971-01-01T01:00");

# Default values for "DONT CARE"
use constant CLOUD_DONT_CARE  => 101;
use constant MOON_DONT_CARE   => 101;

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
    $parser = new XML::LibXML;
    $parser->validation(1);
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
	    Weather => {},
	    SchedConst => {},
	   };

  # and create the object
  bless $sp, $class;

}

=back

=head2 Accessor Methods

Instance accessor methods. Methods beginning with an underscore
are deemed to be private and do not form part of the public interface.

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

The C<_get_obs> method is automatically invoked if this
method is called without argument and the array is empty.

Usually called by the C<summary> method to form a summary
of the MSB itself.

=cut

sub obssum {
  my $self = shift;
  if (@_) {
    @{ $self->{ObsSum} } = @_;
  } elsif (scalar(@{$self->{ObsSum}}) == 0) {
    $self->_get_obs;
  }
  return @{ $self->{ObsSum} };
}


=item B<weather>

Return the weather constraints associated with this
MSB. This is usually conditions such as seeing and tau.

Returns a hash containing the relevant values for this MSB.

  %weather = $msb->weather();

=cut

sub weather {
  my $self = shift;
  # if our cache is empty we need to fill it
  unless (%{$self->{Weather}}) {
    # Fill
    %{$self->{Weather}} = $self->_get_weather_data;
  }
  return %{$self->{Weather}};
}

=item B<sched_constraints>

Return the scheduling constraints. This is usually
the earliest and latest observation dates as well
as, possibly, a minimum elevation to be used for observing.

  %schedconst = $msb->sched_contraints;

If an earliest or latest value can not be found, default values
in the past and in the far future are chosen (so as not to constrain
the query).

The earliest and latest dates are returned in keys "datemin" and
"datemax" so that they match the style used for other ranges.

=cut

sub sched_constraints {
  my $self = shift;
  # if our cache is empty we need to fill it
  unless (%{$self->{SchedConst}}) {
    # Fill
    %{$self->{SchedConst}} = $self->_get_sched_constraints;

    # Fill in blanks
    $self->{SchedConst}->{datemin} = $MINTIME
      unless exists $self->{SchedConst}->{datemin};
    $self->{SchedConst}->{datemax} = $MAXTIME
      unless exists $self->{SchedConst}->{datemax};

  }
  return %{$self->{SchedConst}};
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

If the argument is the constant C<OMP::Constants::OMP__MSB_REMOVED>
this indicates that the MSB has not been observed but
it has been removed from consideration. (e.g. from a OR block
reorganisation or via C<hasBeenCompletelyObserved>).

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

    my $new;
    if ($arg != OMP__MSB_REMOVED() and 
	$current != OMP__MSB_REMOVED() and $arg < 0){
      $new = $current + $arg;

      # Now Force to zero if necessary
      $new = 0 if $new < 0;

    } else {
      $new = $arg;
    }

    # Set the new value
    $self->_tree->setAttribute("remaining", $new);
  }

  return $self->_tree->getAttribute("remaining");
}

=item B<msbtitle>

Return the MSB title.

 $title = $msb->msbtitle;

Return undef if the title is not present.

We can not use C<title> as the method name since this clashes
with the XML element name (and the internal tree traversal routine
will attempt to call this routine when it encounters the element
of the same name).

Title is set to "-" if none is present.

=cut

sub msbtitle {
  my $self = shift;
  my $title = $self->_get_pcdata( $self->_tree, "title");
  $title = "-" unless defined $title;
  return $title;
}

=item B<internal_priority>

Return the MSB internal priority.

 $title = $msb->internal_priority;

Internal priority is converted from a string (in the XML) to a
number:

  0  Target of Opportunity [none of those listed below]
  1  High
  2  Medium
  3  Low

Return 1 if the priority is not present.

=cut

sub internal_priority {
  my $self = shift;
  my $pri = $self->_get_pcdata( $self->_tree, "priority");

  if (defined $pri) {
    if ($pri =~ /high/i) {
      $pri = 1;
    } elsif ($pri =~ /medium/i) {
      $pri = 2;
    } elsif ($pri =~ /low/i) {
      $pri = 3;
    } else {
      $pri = 0;
    }

  } else {
    $pri = 1;
  }

  return $pri;
}

=item B<estimated_time>

Return the estimated time (in seconds) for the MSB to be executed.

  $est = $msb->estimated_time;

Returns 0 if the value can not be determined.

=cut

sub estimated_time {
  my $self = shift;

  # First try for estimatedDuration and then
  # for the older elapsedTime
  my $est = $self->_get_pcdata( $self->_tree, "estimatedDuration");
  $est = $self->_get_pcdata( $self->_tree, "elapsedTime")
    unless defined $est;

  $est = 0 unless defined $est;

  return $est;
}

=item B<telescope>

Retrieve the telescope to be used for this MSB.
There can only be one telescope per MSB.

  $telescope = $msb->telescope;

=cut

sub telescope {
  my $self = shift;

  # Look in cache
  unless ( defined $self->{Telescope} ) {

    # First retrieve the observation summaries since those
    # mention the telescope (since it is keyed from the instrument)
    #  - yes that will cause a problem with michelle on gemini)
    my $telescope;
    for my $obs ( $self->obssum ) {
      my $tel = $obs->{telescope};
      if (defined $telescope) {
	# Oops - two different telescopes
	throw OMP::Error::SpBadStructure("It seems this MSB comes from two telescopes!\n")
	  if $tel ne $telescope;
      } else {
	$telescope = $tel;
      }
    }
    $self->{Telescope} = $telescope;

  }

  return $self->{Telescope};
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
  my $checksum = md5_hex( "$string" );

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

=item B<info>

Return an C<OMP::Info::MSB> object summarizing the MSBs and observations
contained in the XML.

  $info = $msb->summary();

=cut

sub info {
  my $self = shift;

  # Create a hash summary of *this* class
  my %summary;

  # Populate the hash from the object
  $summary{checksum} = $self->checksum;
  $summary{remaining} = $self->remaining;
  $summary{projectid} = $self->projectID;
  $summary{telescope} = $self->telescope;
  %summary = (%summary, $self->weather);
  %summary = (%summary, $self->sched_constraints);

  # MSB internal priority and estimated time
  $summary{priority} = $self->internal_priority;
  $summary{timeest} = $self->estimated_time;

  # Title and observation count
  $summary{title} = $self->msbtitle;
  $summary{title} = "unknown" unless defined $summary{title};

  # Create the object
  my $info = new OMP::Info::MSB( %summary );

  # Populate with observations
  my @obs = map { new OMP::Info::Obs( %{$_} ) } $self->obssum;
  $info->observations(@obs);

  return $info;
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

 - Since MSBs are currently located in a science program by name
   without checking for SpOR counter, if the SpOR counter hits zero
   all remaining MSBs are marked with the magic value for remaining()
   to indicate they have been removed by the OMP rather than by
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
	$_->setAttribute("remaining",OMP__MSB_REMOVED());
      }
    }

  }

}

=item B<hasBeenCompletelyObserved>

Indicate that this MSB has been completely observed. This involves
decrementing the C<remaining()> counter to the value
C<OMP__MSB_REMOVED>. Since this is not associated with an actual
observation no rearranging of OR blocks is required (see
C<hasBeenObserved>).

  $msb->hasBeenCompletelyObserved();

It is usually combined with an update of the database contents to reflect
the modified state.

Essentially a thin layer around C<remaining>.

=cut

sub hasBeenCompletelyObserved {
  my $self = shift;

  # This is the easy bit
  $self->remaining( OMP__MSB_REMOVED() );

}


=item B<addFITStoObs>

Add additional FITS headers (as XML elements) to each SpObs such
that each SpObs can be translated standalone without having 
to retain context.

Used to add the checksum and project ID as elements
"msbid" and "project". These are required for the data files.

  $msb->addFITStoObs;

=cut

sub addFITStoObs {
  my $self = shift;

  # If we are a lone SpObs we want to use ourself rather
  # than the children
  my @nodes;
  if ($self->_tree->getName eq 'SpObs') {
    @nodes = $self->_tree;
  } else {
    # Get the SpObs elements
    push(@nodes, $self->_tree->findnodes('.//SpObs'));
  }

  # Some XML elements that we can insert
  # problems with XML::LibXML mean that we need to create
  # some XML as text, parse it and then insert the nodes.
  # If I try to creat the Elements from constructors
  # I have trouble populating them. I also get core dumps
  # with insertBefore...
  my $xml = "<root><project>" . $self->projectID . "</project>\n" .
    "<msbid>" . $self->checksum . "</msbid>\n</root>\n";

  # Create hash with information we wish to insert
  my %data = (
	      msbid => $self->checksum,
	      project => $self->projectID,
	     );


  # For each SpObs insert these elements.
  # problems with insertBefore so I have to insert at end
  for my $obs (@nodes) {
    for my $el (keys %data) {
      $obs->appendTextChild($el, $data{$el});
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


=item B<_summarize_obs>

Return a summary of the individual observations suitable
for the query tool or for a one line summary.

This summary is not used for scheduling (individual queries to
the observation table should be used for that).

Usually invoked via the C<summary> method.

  %hash = $msb->_summarize_obs;

Returns keys:

  instrument
  target
  waveband
  coordstype
  pol
  type

If the values are different between observations the options are
separated with a "/".

If an array reference is supplied as an argument it is assumed
to contain the observation summaries rather than retrieving it
from the object.

  %hash = OMP::MSB->_summarize_obs( \@obs );

=cut

sub _summarize_obs {
  my $self = shift;
  my @obs;
  if (@_ && ref($_[0]) eq 'ARRAY') {
    @obs = @{$_[0]};
  } elsif (@_) {
    confess "Got an argument that wasn't an array (",scalar(@_),")!\n";
  } else {
    @obs = $self->obssum;
  }


  my %summary;

  foreach my $key (qw/ instrument waveband target coordstype pol type ha airmass ra disperser/) {

    # Now go through each observation looking for the specific
    # key. Need to do this long hand since order over observations
    # must be preserved (although something like cgs4/ircam/cgs4
    # would come out as cgs4/ircam to save space [that is better
    # than it coming out as "ircam/cgs4"])
    my @unique = $self->_compress_array( map { defined $_ ? $_->{$key} : "NONE" } @obs);

    # Now put the array together
    $summary{$key} = join("/", @unique);

  }

  #use Data::Dumper;
  #print Dumper(\%summary);

  return %summary;

}

=item B<_get_obs>

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

sub _get_obs {
  my $self = shift;


  # Get an element
  # If a processing method exists simply call it with
  # a hash containing the current state.
  # if returns a new hash with the new state

  my %status; # for storing current parameters
  my @obs; # for storing results

  # If we are a lone SpObs we want to use ourself rather
  # than the children
  my @searchnodes;
  if ($self->_tree->getName eq 'SpObs') {
    @searchnodes = $self->_tree;
  } else {
    @searchnodes = $self->_tree->getChildnodes;
  }


  # Get all the children and loop over them
  for ( @searchnodes ) {

    # Resolve refs if required
    my $el = $self->_resolve_ref( $_ );

    # Get the name of the item
    my $name = $el->getName;
    #print "Name is $name \n";

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

  #use Data::Dumper;
  #print Dumper(\@obs);

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

=item B<_get_weather_data>

Return the contents of the SiteQuality component as a hash.
Usually used internally by the C<weather> method.

=cut

sub _get_weather_data {
  my $self = shift;

  # First get the SpSiteQualityComp and refs
  my @comp;
  push(@comp, $self->_tree->findnodes(".//SpSiteQualityObsCompRef"),
        $self->_tree->findnodes(".//SpSiteQualityObsComp"));

  # and use the last one in the list (hopefully we are only allowed
  # to specify a single value). We get the last one because we want
  # inheritance to work and the refs from outside the MSB are put in
  # before the actual MSB contents
  return () unless @comp;

  my $el = $self->_resolve_ref($comp[-1]);

  my %summary;

  # Need to get "seeing" and "tau". These are ranges
  # so store the upper and lower limits in an OMP::Range object
  $summary{tau} = $self->_get_range( $el, "csoTau" );
  $summary{seeing} = $self->_get_range( $el, "seeing" );

  # and (if defined) cloud information
  # This is an implict range (bounded by 0)
  # so the default value should be some high number
  $summary{cloud} = $self->_get_pcdata( $el, "cloud");
  $summary{cloud} = CLOUD_DONT_CARE unless defined $summary{cloud};

  # Moon
  # This is an implict range (essentially the fraction of
  # illumination) bounded by 0 [since you essentially
  # never complain if your observation comes up with no moon
  # present]
  $summary{moon} = $self->_get_pcdata( $el, "moon");
  $summary{moon} = MOON_DONT_CARE unless defined $summary{moon};


  # Big kluge - if the site quality is there but we
  # dont have any values defined (due to a bug in the OT)
  # then make something up
  $summary{tau} = new OMP::Range( Min => 0 )
    unless defined $summary{tau};
  $summary{seeing} = new OMP::Range( Min => 0 )
    unless defined $summary{seeing};


#  use Data::Dumper;
#  print Dumper(\%summary);

  return %summary;

}

=item B<_get_sched_constraints>

Return the contents of the SchedConstObsComp component as a hash.
Usually used internally by the C<sche_constraints> method.

Only returns keys that are actually present.

=cut

sub _get_sched_constraints {
  my $self = shift;

  # First attempt to get the SpSchedConstObsComp and refs
  # (if present)
  my @comp;
  push(@comp, $self->_tree->findnodes(".//SpSchedConstObsCompRef"),
        $self->_tree->findnodes(".//SpSchedConstObsComp"));

  # and use the last one in the list (hopefully we are only allowed
  # to specify a single value). We get the last one because we want
  # inheritance to work and the refs from outside the MSB are put in
  # before the actual MSB contents
  return () unless @comp;

  my $el = $self->_resolve_ref($comp[-1]);

  my %summary;

  # Need to get earliest and latest
  # Convert them to Time::Piece objects
  my %columns = ( # Since XML key is different to db column
		 earliest => "datemin",
		 latest => "datemax");
  for my $key ( qw/ earliest latest / ) {
    my $val = $self->_get_pcdata( $el, $key );
    if (defined $val) {
      my $date = OMP::General->parse_date($val);
      $summary{$columns{$key}} = $date if defined $date;
    }
  }

  return %summary;

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

Returns C<undef> if the element can not be found.

Returns C<undef> if the element can be found but does not contain
anything (eg E<lt>targetName/E<gt>).

=cut

sub _get_pcdata {
  my $self = shift;
  my ($el, $tag ) = @_;

  my @matches;
  if ($XML::LibXML::VERSION < 1.4) {
    @matches = $el->getElementsByTagName( $tag );
  } else {
    @matches = $el->getChildrenByTagName( $tag );
  }
  my $pcdata;
  if (@matches) {
    my $child = $matches[-1]->firstChild;
    # Return undef if the element contains no text children
    return undef unless defined $child;
    $pcdata = $child->toString;
  }

  return $pcdata;
}

=item B<_get_range>

Given an element and a tag name, find the element corresponding
to that tag, look inside it and return the contents of C<max> and
C<min> elements as an C<OMP::Range> object.

The XML is expected to look something like:

  <seeing>
    <max>25.0</max>
    <min>0.0</min>
  </seeing>

Returns C<undef> if element could not be located
or if neither C<max> nor C<min> could be found.

=cut

sub _get_range {
  my $self = shift;
  my ($el, $tag) = @_;

  my $result;

  # Get the element
  my @matches = $el->getElementsByTagName( $tag );
  if (@matches) {

    # Now just look for max and min elements
    my $min = $self->_get_pcdata( $matches[-1], "min");
    my $max = $self->_get_pcdata( $matches[-1], "max");

    $result = new OMP::Range(Min => $min, Max => $max)
      if defined $min and defined $max;

  }

  return $result;
}

=item B<_get_child_elements>

Retrieves child elements of the specified name or matching the
specified regexp. The regexp must be supplied using qr (it is
assumed to be a regexp if the argument is a reference).

  @el = $msb->_get_child_element( $parent, qr/System$/ );

  @el = $msb->_get_child_elements( $parent, "hmsdegSystem" );

Need to use this until I can find how to use XPath to specify
a match.


=cut

sub _get_child_elements {
  my $self = shift;
  my $el = shift;
  my $name = shift;

  my @res;
  if (ref($name)) {

    @res = grep { $_->getName =~ /$name/ } $el->getChildnodes;

  } else {

    @res = $el->findnodes(".//$name");

  }

  return @res;
}

=item B<_compress_array>

Helper method to compress an array so that only the first occurrence
of a particular element remains (but the order is not changed).

  @compressed = $msb->_compress_array( @array );

For example

  CGS4, UKIRT, CGS4

is returned as

  CGS4, UKIRT

undefined values are by default converted to empty strings.

=cut

sub _compress_array {
  my $self = shift;
  my @array = @_;

  my (%unique, @unique);
  for (@array) {

    my $value = ( defined $_ ? $_ : "" );

    # If it is in our hash skip to the next one
    next if exists $unique{ $value };

    # Store it in our hash
    $unique{$value} = undef;

    # And push on the value
    push(@unique, $value);

  }

  return @unique;
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
triggers the translator to take data).

Note that there is an argument that can be made to make C<OMP::Obs>
an even more fundamental class...

=cut

sub SpObs {
  my $self = shift;
  my $el = shift;
  my %summary = @_;
  #print "In SpOBS\n";

  # First get the top-level information
  # Could do these with callbacks of the right name
  # but that might get confused with the identical
  # MSB element names.
  # note that this returns the last element if there are
  # repeats.
  $summary{timeest} = $self->_get_pcdata($el, "estimatedDuration" );
  $summary{timeest} = $self->_get_pcdata($el, "elapsedTime" )
    unless defined $summary{timeest}; # to support old format XML

  $summary{timeest} = 0.0 unless defined $summary{timeest};

  # Reset polarimeter bit since the presence of an SpIterPOL
  # can indicate that the polarimeter is to be used but there
  # will be nothing to indicate its absence. This only works
  # if we are not reading polarimeter information from
  # instrument components (from which we can inherit)
  $summary{pol} = 0;

  # Now walk through all the child elements extracting information
  # and overriding the default values (if present)
  # This is almost the same as the summarize() method but I can not
  # think of an obvious way to combine the loops and recursion seems
  # like overkill since I dont want to go down multiple depths in the
  # tree.
  for ( $el->getChildnodes ) {
    # Resolve refs if necessary
    my $child = $self->_resolve_ref( $_ );
    my $name = $child->getName;
    next unless defined $name;
    #print "SpObs: $name\n";
    %summary = $self->$name( $child, %summary )
      if $self->can( $name );
  }

  # Check that we have an observe iterator of some kind.
  throw OMP::Error::MSBMissingObserve("SpObs is missing an observe iterator\n")
    unless exists $summary{obstype};

  # Check to see if a Target was present but no Observe
  # If there were calibration observations that do not need
  # targets then we should fill in the targetname now with
  # CAL
  # This test needs to be expanded for SCUBA
  if ( grep /^Observe$/, @{$summary{obstype}} or
       grep /Pointing|Photom|Jiggle|Stare/, @{$summary{obstype}}) {
    if (!exists $summary{coords}) {
      throw OMP::Error::MSBMissingObserve("SpObs has an Observe iterator without corresponding target specified\n");
    }
    # We have a normal observe - just use it and the associated target
    # information

  } else {
    # We have a calibration observation
    $summary{coords} = Astro::Coords::Calibration->new;
    $summary{coordstype} = $summary{coords}->type;

    # The target name should not include duplicates here
    # Use a hash to compress it
    my @compressed = $self->_compress_array( @{ $summary{obstype}});
    $summary{target} = join(":", @compressed);
  }

  return \%summary;

}

=item B<SpIterFolder>

Examine the sequence folder looking for observes. This populates
an array with hash key "obstype" containing all the observation
modes used.

The "obstype" key is only placed in the summary hash if an
observe iterator of some kind is present.

Sometimes an SpIterFolder contains other folders such as SpIterRepeat
and SpIterOffset. These may contain SpIterObserve and so must be
examined a special cases of SpIterFolder. All iterators (except Repeat
and Offset) are pushed onto the obstype array regardless of depth.

=cut

sub SpIterFolder {
  my $self = shift;
  my $el = shift;
  my %summary = @_;
  my @types;

  for my $child ( $el->getChildnodes ) {
    my $name = $child->getName;
    next unless defined $name;

    # If we are SpIterRepeat or SpIterOffset or SpIterIRPOL 
    # or other iterators
    # we need to go down a level
    if ($name =~ /SpIter(Repeat|Offset|IRPOL|POL|Chop)/) {
      my %dummy = $self->SpIterFolder($child);

      # obstype is a special key
      if (exists $dummy{obstype}) {
	push(@types, @{$dummy{obstype}});
	delete $dummy{obstype};
      }

      # Merge information with child iterators
      %summary = (%summary, %dummy);

      # SpIterPOL and SpIterIRPOL signifies something significant
      $summary{pol} = 1 if $name =~ /POL$/;

      next;
    }

    # Remove the SpIter string
    next unless $name =~ /SpIter/;
    $name =~ s/^SpIter//;
    $name =~ s/Obs$//;

    push(@types, $name);


  }

  $summary{obstype} = \@types if @types;

  return %summary;

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

  $summary{telescope} = "UKIRT";
  $summary{instrument} = "CGS4";

  # We have to make sure we set all instrument related components
  # else the hierarchy might print through
  my $wavelength = $self->_get_pcdata( $el, "centralWavelength" );
  $summary{waveband} = new Astro::WaveBand( Wavelength => $wavelength,
					    Instrument => 'CGS4');
  $summary{wavelength} = $summary{waveband}->wavelength;
  $summary{disperser} = $self->_get_pcdata( $el, "disperser" );

  # Camera mode
  $summary{type} = "s";

  # Polarimeter
  #my $pol = $self->_get_pcdata( $el, "polariser" );
  #$summary{pol} = ( $pol eq "none" ? 0 : 1 );


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

  $summary{telescope} = "UKIRT";
  $summary{instrument} = "UFTI";
  my $filter  = $self->_get_pcdata( $el, "filter" );
  $summary{waveband} = new Astro::WaveBand( Filter => $filter,
					    Instrument => 'UFTI');
  $summary{wavelength} = $summary{waveband}->wavelength;
  $summary{disperser} = undef;

  # Camera mode
  $summary{type} = "i";

  # Polarimeter
  #my $pol = $self->_get_pcdata( $el, "polariser" );
  #$summary{pol} = ( $pol eq "none" ? 0 : 1 );

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

  $summary{telescope} = "UKIRT";
  $summary{instrument} = "Michelle";

  # We have to make sure we set all instrument related components
  # else the hierarchy might print through

  # If we are IMAGING we need to pick up the filter name
  # If we are SPECTROSCOPY we need to pick up the central
  # wavelength
  my $type = $self->_get_pcdata( $el, "camera" );

  if ($type eq 'imaging') {
    my $filter = $self->_get_pcdata( $el, "filterOT" );
    $summary{waveband} = new Astro::WaveBand( Filter => $filter,
					      Instrument => 'MICHELLE');

    $summary{disperser} = undef;
  } else {
    my $wavelength = $self->_get_pcdata( $el, "centralWavelength" );
    $summary{waveband} = new Astro::WaveBand( Wavelength => $wavelength,
					      Instrument => 'MICHELLE');

    $summary{disperser} = $self->_get_pcdata( $el, "disperser" );
  }

  $summary{wavelength} = $summary{waveband}->wavelength;

  # Camera mode
  $summary{type} = ( $type eq "imaging" ? "i" : "s" );

  # Polarimeter
  #my $pol = $self->_get_pcdata( $el, "polarimetry" );
  #$summary{pol} = ( $pol eq "no" ? 0 : 1 );

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

  $summary{telescope} = "UKIRT";
  $summary{instrument} = "IRCAM3";
  $summary{disperser} = undef;

  # We have to make sure we set all instrument related components
  # else the hierarchy might print through
  my $filter  = $self->_get_pcdata( $el, "filter" );
  $summary{waveband} = new Astro::WaveBand( Filter => $filter,
					    Instrument => 'IRCAM');
  $summary{wavelength} = $summary{waveband}->wavelength;

  # Camera mode
  $summary{type} = "i";

  # Polarimeter
  #my $pol = $self->_get_pcdata( $el, "polariser" );
  #$summary{pol} = ( $pol eq "none" ? 0 : 1 );


  return %summary;
}

=item B<SpInstSCUBA>

Examine the structure of this name and add information to the
argument hash.

  %summary = $self->SpInstSCUBA( $el, %summary );

where C<$el> is the XML node object and %summary is the
current hierarchy.

=cut

sub SpInstSCUBA {
  my $self = shift;
  my $el = shift;
  my %summary = @_;

  $summary{telescope} = "JCMT";
  $summary{instrument} = "SCUBA";

  # We have to make sure we set all instrument related components
  # else the hierarchy might print through
  my $filter  = $self->_get_pcdata( $el, "filter" );
  $summary{waveband} = new Astro::WaveBand( Filter => $filter,
					    Instrument => 'SCUBA');
  $summary{wavelength} = $summary{waveband}->wavelength;

  # Camera mode
  $summary{type} = "i";

  return %summary;
}

=item B<SpTelescopeObsComp>

Target information.

  %summary = $msb->SpTelescopeObsComp( $el, %summary );

=cut

sub SpTelescopeObsComp {
  my $self = shift;
  my $el = shift;
  my %summary = @_;
  #print "In target\n";

  # Need to support two versions of the TCS XML.
  # Old version has
  # <base>
  #  <target type="science">
  #       ...
  # New version has:
  # <BASE TYPE="Base">
  #   <target>
  #        ....
  # and changes hmsdeg and degdeg to spherSystem

  # First try the new method
  # XML::LibXML does not seem to support an | for attributes so do it
  # in two passes (ie './/BASE[@TYPE="Base"|@TYPE="SCIENCE"]/target'
  # gives failures and type warnings from xpath.c line 9492/8695
  my ($base) = $el->findnodes( './/BASE[@TYPE="Base"]/target');

  ($base) = $el->findnodes( './/BASE[@TYPE="SCIENCE"]/target')
    unless $base;

  # Try again if at first we dont succeed
  # Get the base target element
  ($base) = $el->findnodes(".//base/target")
    unless $base;

  # Could be an error (it is for now) but we may be specifying 
  # "best guess" as an option for the translator for pointing and
  # standards
  throw OMP::Error::SpBadStructure("No base target position specified in SpTelescopeObsComp\n") unless $base;

  $summary{target} = $self->_get_pcdata($base, "targetName");
  $summary{target} = "NONE SUPPLIED" unless defined $summary{target};

  # Now we need to look for the coordinates. If we have hmsdegSystem
  # or degdegSystem (for Galactic) we translate those to a nice easy
  # J2000. If we have conicSystem or namedSystem then we have a moving
  # source on our hands and we have to work out it's azel dynamically
  # If we have a degdegSystem with altaz we can always schedule it.
  # spherSystem now replaces hmsdegsystem and degdegsystem

  # Search for the element matching (this will be targetName 90% of the time)
  # We know there is only one system element per target
  my ($system) = $self->_get_child_elements($base, qr/System$/);

  my $sysname = $system->getName;
  if ($sysname eq "hmsdegSystem" or $sysname eq "degdegsystem"
     or $sysname eq 'spherSystem') {

    # Get the "long" and "lat"
    my $c1 = $self->_get_pcdata( $system, "c1");
    my $c2 = $self->_get_pcdata( $system, "c2");

    # Get the coordinate frame. This is either "type" or "SYSTEM"
    my $type = ($sysname eq 'spherSystem'  ? $system->getAttribute("SYSTEM")
		: $system->getAttribute("type"));

    # degdeg uses different keys to hmsdeg
    #print "System: $sysname\n";
    my ($long ,$lat);
    if ($type eq "J2000" or $type eq "B1950") {
      $long = "ra";
      $lat = "dec";
    } elsif ($type eq "GAL") {
      $type = "galactic"; # So that Astro::Coords understands
      $long = "long";
      $lat = "lat";
    } else {
      $long = "UNKNOWN";
      $lat = "UNKNOWN";
    }

    # Create a new coordinate object
    $summary{coords} = new Astro::Coords( $long => $c1,
					  $lat => $c2,
					  type => $type
					);

    throw OMP::Error::FatalError( "Coordinate frame $type not yet supported by the OMP\n") unless defined $summary{coords};

    $summary{coordstype} = $summary{coords}->type;

  } elsif ($sysname eq "conicSystem") {

    # Orbital elements. We need to get the (up to) 8 numbers
    # and store them in an Astro::Coords.
    $summary{coordstype} = "ELEMENTS";

    throw OMP::Error::FatalError("Orbital elements not yet supported\n");

  } elsif ($sysname eq "namedSystem") {

    # A planet that the TCS already knows about

    $summary{coordstype} = "PLANET";
    $summary{coords} = Astro::Coords->new( planet => $summary{target});

    throw OMP::Error::FatalError("Unable to process planet $summary{target}\n")
      unless defined $summary{coords};

  } else {

    throw OMP::Error::FatalError("Target system ($sysname) not recognized\n");

  }


  return %summary;
}

=back

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;

