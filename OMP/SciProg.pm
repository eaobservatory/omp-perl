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

  # ************** KLUGE **********************
  # Namespace issues with XML::LibXML 2.5.11. If it finds
  # xmlns="" it does not import into the default namespace (seemingly)
  # unless written as xmlns:="". This may be a problem with my
  # understanding of the problem. Should test with v2.6 when supported.
  # For now kluge it by putting in the colon
  $xml =~ s/xmlns=/xmlns:=/;

  # Now convert XML to parse tree
  my $parser = new XML::LibXML;
  $parser->validation(0); # switch on validation
  my $tree = eval { $parser->parse_string( $xml ) };
  if ($@) {
    throw OMP::Error::SpBadStructure("Error whilst parsing science program: $@\n");
  }

  # Look for a SpProg
  my ($root) = $tree->findnodes('.//SpProg');
  throw OMP::Error::SpBadStructure("Error obtaining SpProg root node in constructor") 
    unless defined $root;

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

Modifying the project ID, modifies the underlying DOM tree
but only the 'projectID' tag in the document root. If no
'projectID' node is found in the root, one is added.

=cut

sub projectID {
  my $self = shift;
  if (@_) { 
    $self->{ProjectID} = uc(shift);

    # Fix the DOM tree.
    # Need to rationalise this so that we have a method for getting
    # an element from the node tree and a method for setting a value
    # and retrieving a value. Too much repeated code otherwise
    # This code is shared with find_projectid
    my ($el) = $self->_tree->findnodes( './/projectID[1]');

    # Note that we do not look for 'project' in an SpMSB.
    # If we have no element, need to make one
    if (! defined $el) {
      # Look up the root and create a new element
      my ($root) = $self->_tree->findnodes('.//SpProg');

      throw OMP::Error::SpBadStructure("Error obtaining root node in projectID discovery")
	unless defined $root;

      $el = new XML::LibXML::Element( 'projectID' );
      $root->appendChild( $el );
      $el->appendText( $self->{ProjectID});
    } else {
      # Now set the value of the node
      my $child = $el->firstChild();
      $child->setData( $self->{ProjectID} );
    }

  } else {
    $self->find_projectid unless defined $self->{ProjectID};
  }
  return $self->{ProjectID};
}

=item B<ot_version>

The version of the OT that was used to generate this science programme.

Read-only. Returns C<undef> if no version is available.

=cut

sub ot_version {
  my $self = shift;
  my @nodes = $self->_tree->findnodes('.//ot_version');
  if (defined $nodes[-1]) {
    my $ver = $nodes[-1]->getFirstChild->toString;
    # Clean it.
    $ver =~ s/-//g;

    return $ver;
  }
  # return explicit undef rather than empty list
  return undef;
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

Summarize the science program. This can be in many forms. For example,
in the form of an XML string containing summaries of all the MSBs, or
as an array of text where each line is an ASCII summary of each MSB
(the first line of which is the column names).

An optional argument can be used to switch modes explicitly and to access
different forms of summaries. Allowed values are:

  'xml'         XML summary (equivalent to default scalar context)
  'html'        HTML summary of program
  'htmlcgi'     HTML summary of program with an 'Add Comment' button
  'asciiarray'  Array of MSB summaries in plain text (default in list context)
  'data'        Perl data structure containing an array of hashes.
                One for each MSB. Additionally, observation information
                is in another array of hashes within each MSB hash.
                Respects calling context returning a ref in scalar context.
  'objects'     Returns MSBs as array of OMP::Info::MSB objects
  'ascii'       Plain text summary of the Science Program.
                Returns a list of lines in list context. A block of text
                in scalar context.

The XML summary is of the form

  <SpProgSummary timestamp="9999999" projectid="M01BXXX">
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

  # Determine the mode of summary
  my $mode;
  if (@_ && defined $_[0]) {
    $mode = lc(shift);
  } elsif (wantarray()) {
    # Guess
    $mode = 'asciiarray';
  } else {
    # Guess again
    $mode = 'xml';
  }

  # General sci prog infomation
  my $time = $self->timestamp;
  $time ||= '';
  my $utc = ( $time ? gmtime($time) ." UTC" : "UNKNOWN");

  my $proj = $self->projectID;

  # Retrieve the msbs
  my @msbs = $self->msb;

  # It would be nice to work out how many we have yet to observe
  # even though this really should happen as part of our loop through
  # the msbs themselves. Either I splice in the result later or
  # do it now. .... Do it now - cant use grep because -999 is
  # a magic value to indicate "removed"
  my $active = 0;
  for (@msbs) {
    $active++ if $_->remaining > 0;
  }


  # Now switch on mode
  if ($mode eq 'asciiarray') {
    # Plain text
    my @strings;
    for my $msb ($self->msb) {
      my %summary = $msb->info->summary('hashlong');
      # The title
      push(@strings, $msb->info->summary('textshorthdr') ) unless @strings;
      # The contents
      push(@strings,  $msb->info->summary('textshort') );
    }

    return @strings;

  } elsif ($mode eq 'xml') {
    # XML version
    my $xml = "<SpProgSummary timestamp=\"$time\" projectid=\"$proj\">\n";

    for my $msb (@msbs) {
      $xml .= $msb->info->summary('xmlshort');
    }
    $xml .= "</SpProgSummary>\n";

    return $xml;

  } elsif ($mode eq 'data') {
    # Return an array of hashes (as array ref)
    # Loop over each msb in the science program
    @msbs = map { {$_->info->summary('hashlong') } } @msbs;

    if (wantarray) {
      return @msbs;
    } else {
      return \@msbs;
    }

  } elsif ($mode eq 'objects') {
    # Return the MSB info object
    @msbs = map { $_->info } @msbs;

    if (wantarray) {
      return @msbs;
    } else {
      return \@msbs;
    }


  } elsif ($mode eq 'html' or $mode eq 'htmlcgi') {
    my @lines;

    push(@lines,"<TABLE border='0'>");
    push(@lines, "<tr><td>Project ID:</td><td><b>".uc($proj)."</b></td></tr>");

    # Submission time
    push(@lines, "<tr><td>Time Submitted:</td><td><b>$utc</b></td></tr>");

    # MSB Count
    push(@lines, "<tr><td>Number of MSBs:</td><td><b>".scalar(@msbs)."<b></td></tr>");
    push(@lines, "<tr><td>Active MSBs:</td><td><b>$active</b></td></tr>");
    push(@lines, "</TABLE>");

    # Now process each MSB - This is a clone of "ascii"
    # Must be a better way
    # Must also be a method of OMP::MSB rather than being
    # used directly
    my $count;
    for my $msb (@msbs) {
      $count++;
      my $info = $msb->info;
      push(@lines, $info->summary($mode));
    }

    # Return a list or a string
    if (wantarray) {
      return @lines;
    } else {
      return join("\n", @lines) . "\n";
    }



  } elsif ($mode eq 'ascii') {
    # Plain text
    my @lines;

    # First the project stuff
    push(@lines, "Project ID:\t$proj");

    # Convert the timestamp back into a real time (assuming it is
    # possible). The time stamp is in UTC.
    push(@lines, "Time submitted:\t$utc");

    # Number of MSBs (total and active)
    push(@lines, "Number of MSBs:\t" . scalar(@msbs));
    push(@lines,"Active MSBs:\t$active");


    # Now process each MSB
    # We probably should put this in the OMP::MSB::summary method
    # but there is no obvious way of passing options to that
    # method.
    my $count;
    for my $msb (@msbs) {
      $count++;
      my $info = $msb->info;
      push(@lines, $info->summary('textlong'));
    }

    # Return a list or a string
    if (wantarray) {
      return @lines;
    } else {
      return join("\n", @lines) . "\n";
     }
  } else {
    # Unknown mode
    throw OMP::Error::BadArgs("Unknown mode ($mode) specified for SciProg summary");
  }


}


=item B<find_projectid>

Determine the project ID of the science program and store the information
in the object.

Automatically invoked by the C<projectID()> method the first time
that method is invoked.

If C<projectID> can not be found this method looks for an
element called "project" since that is placed in observations
by the OMP system. This usually occurs when an observation has
been extracted from a full science program.

If no project can be extracted, "UNKNOWN" is chosen rather
than throwing an exception.

This method forces an upper-cased version of the project ID
to be written to the DOM tree itself in the correct place
(even if that project was read from an MSB child).

=cut

sub find_projectid {
  my $self = shift;

  my ($element) = $self->_tree->findnodes('.//projectID[1]');

  # projectID element contains PCData that is the actual project ID
  if (defined $element) {
    # This forces the dom tree to be modified to include an
    # uppercased version
    $self->projectID( $element->getFirstChild->toString );
  } else {
    # Could not find projectID so look for a "project" element
    # which has been added automatically by the OMP
    my ($element2) = $self->_tree->findnodes('.//project[1]');

    if (defined $element2) {
      $self->projectID( $element2->getFirstChild->toString );
    } else {
      #    throw OMP::Error::UnknownProject("The Science Program does not contain a 
      #project identifier");
      $self->projectID( "UNKNOWN" );
    }
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

=item B<existsMSB>

Given a checksum, determine whether that MSB is present in the science program.
Returns a boolean.

  if ($sp->existsMSB( $checksum )) {
     ...
  }

=cut

sub existsMSB {
  my $self = shift;
  my $checksum = shift;

  # This should be optimized by creating a hash
  # and simply using exist rather than stepping through the
  # science program each time.
  for my $msb ($self->msb) {
    if ($checksum eq $msb->checksum) {
      return 1;
    }
  }
  return 0;
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
  # We believe the MSB attribute
  my @spobs = $self->_tree->findnodes('//SpObs[@msb="true"]');

  # occassionally we get some spurious hits here (have not found
  # out why) so go through and remove spobs that have an SpMSB
  # parent [this is the safest way if we do not trust the msb attribute
  # - it may be that we should never trust the attribute and always
  # get every SpObs and then remove spurious ones.
  for (@spobs) {
    my ($parent) = $_->findnodes('ancestor-or-self::SpMSB');
    push(@spmsb, $_) unless $parent;
  }

  # Create new OMP::MSB objects
  my $refhash = $self->refs;
  my $projectid = $self->projectID;
  # returns empty list if fails and so this can not be put directly
  # in the hash constructor without protecting the missing entry
  my $otvers = $self->ot_version;
  my @objs = map { new OMP::MSB( TREE => $_, 
				 REFS => $refhash,
				 PROJECTID => $projectid,
				 OTVERSION => $otvers,
                               ) } @spmsb;

  # Remove duplicates
  # Build up a hash keyed by checksum
  my %unique;
  my @unique; # to preserve order
  my $unbound = 0;
  for my $msb (@objs) {
    my $checksum = $msb->checksum;
    if (exists $unique{$checksum}) {
      # Increment the first MSB by the amount remaining in the current MSB
      my $newtotal = $unique{$checksum}->remaining() + $msb->remaining();
      $unique{$checksum}->remaining($newtotal);

      # Remove the current msb object from the science program tree
      $msb->_tree->unbindNode();
      $unbound = 1;

    } else {
      $unique{$checksum} = $msb;

      # A hash will not preserve MSB order. To preserve it
      # we store the first occurrence of each MSB in an array
      push(@unique, $msb);

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
  # contents of @unique
  $self->locate_refs if $unbound;

  # Copy the list of unique objects, preserving the order
  @objs = @unique;

  # And store them (if we found anything - otherwise
  # we hit infinite recursion)
  $self->msb(@objs)
    if @objs;

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
    $refs{$key} = $el->ownerElement;
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

=item B<verifyMSBs>

Verify that each of the constituent MSBs is okay (as defined
by the C<verifyMSB> method in C<OMP::MSB> class).

Returns a status and a string describing any problems.

  ($status, $reason) = $msb->verifyMSBs;

Allowed status values are:

  0 - everything okay
  1 - some warnings were raised
  2 - fatal error

Note that fatal errors will probably have been caught during the
initial pass. This method does not attempt to check instrumental
specific problems.

If you receive a fatal error, you would normally want to throw
an explicit exception.

=cut

sub verifyMSBs {
  my $self = shift;

  # Assume good status
  my $status = 0;

  # Loop over the MSBs
  my $count = 0;
  my $string = '';
  for my $msb ($self->msb) {
    $count++;
    my ($msbstatus, $msbstring) = $msb->verifyMSB;
    next if $msbstatus == 0;

    # Raise status if required
    $status = $msbstatus if $status < $msbstatus;

    # Cache the string and indicate the MSB number
    $string .= "MSB $count: $msbstring\n";

  }

  return ($status, $string);
}

=item B<cloneMSBs>

Go through the science program and for each MSB containing a blank
science target, clone it using the supplied coordinate objects.

  @messages = $sp->cloneMSBs( @coords );

Currently can not handle coordinate types that are not RADEC.
Non-RADEC coordinates are ignored silently. Returns an array
of informational messages (no newlines).

There is no corresponding method in the C<OMP::MSB> class because
this method completely reorganizes the MSB layout. An C<OMP::MSB>
objects derived from this class will be broken after cloning
and must be retrieved from the science program object again.

=cut

sub cloneMSBs {
  my $self = shift;
  my @sources = @_;

  # Remove any targets that are not RADEC
  @sources = grep { $_->type eq 'RADEC'  } @sources;
  return ("No targets supplied for cloning") unless scalar(@sources);

  # Informational messages
  my @info;

  # Loop over each MSB
  my $ncloned = 0;
  for my $msb ($self->msb) {

    # Count the number of useful blank target components
    # Ignoring inheritance
    my $blanks = $msb->hasBlankTargets(0);
    next unless $blanks > 0;

    # Warn if we do not have an exact match
    push(@info,
	 "Number of blank targets in MSB '".$msb->msbtitle.
	 "' is not divisible into the number of targets supplied.",
	 "Some targets will be missing.")
      if scalar(@sources) % $blanks != 0;

    # Calculate the max number we can support [as an index]
    my $max = int(($#sources+1) / $blanks) * $blanks - 1;

    # Now loop over the source list
    # It is probably more efficent to generate the XML of the clone
    # and then do all the replacements on the XML before parsing
    # it and inserting it back into the tree. For now, do the
    # long hand approach
    my $nrepeats = 0;
    for (my $i = 0; ($i+$blanks-1) <= $max; $i+= $blanks) {

      # Okay now we need to deep clone the MSB
      my $clone = $msb->_tree->cloneNode( 1 );

      # There is no method in OMP::MSB (yet) for replacing target
      # XML with other target XML. The only way we can do this
      # currently is to take each MSB, locate the
      # telescope components, then find the nodes corresponding to
      # the coordinates and change the values
      # Note that _tree is a private method so we really need
      # to provide an explicit OMP::MSB interface for this
      # even though it may cause the object to no longer refer to the tree
      # Get the telescope components
      my @tels = $msb->_get_tel_comps( tree => $clone );

      # And only look at blanks
      @tels = grep { $msb->_is_blank_target($_); } @tels;

      # Now loop over the telescope components
      my $c = 0; # Count number replaced
      for my $tel (@tels) {

	# There is no way this can happen
	throw OMP::Error::FatalError( "Internal error: The number of blank telescope components encountered exceeds the expected number!!!\n")
	  if $c >= $blanks;

	# Now need to get the nodes corresponding to the name
	# RA and Dec. We know they are blank already.
	my ($targetnode) = $tel->findnodes(".//targetName");
	my ($ranode) = $tel->findnodes(".//c1");
	my ($decnode) = $tel->findnodes(".//c2");
	
	# Get the text nodes
	my $ra = $ranode->firstChild;
	my $dec = $decnode->firstChild;
	my $target = $targetnode->firstChild;

	# If we have fallen off the end of the array we
	# have made a mistake
	throw OMP::Error::FatalError("Internal error whilst stepping through spource arrays for MSB cloning")
	  if (($i+$c) > $max);

	# Select the correct target object
	my $coords = $sources[$i + $c];

	# Change the values in the node [making sure we allow for
	# the possibility that there is a blank coordinate]
	# too much code repetition
	if (defined $ra) {
	  $ra->setData( $coords->ra( format => 'sex'));
	} else {
	  my $text = new XML::LibXML::Text( $coords->ra( format => 'sex') );
	  $ranode->appendChild( $text );
	}
	if (defined $dec) {
	  $dec->setData( $coords->dec( format => 'sex'));
	} else {
	  my $text = new XML::LibXML::Text( $coords->dec( format => 'sex') );
	  $decnode->appendChild( $text );
	}

	# There is a remote possibility that we have no
	# target child either
	if (defined $target) {
	  $target->setData( $coords->name );
	} else {
	  my $text = new XML::LibXML::Text( $coords->name );
	  $targetnode->appendChild( $text );
	}

	# increment the tel counter
	$c++;

      }

      # Make sure we replaced the correct number
      throw OMP::Error::FatalError("Internal error: We found fewer blank telescope components than expected!!!\n")
	unless $c == $blanks;

      # Insert the clone node in the correct place
      $msb->_tree->parentNode->insertAfter($clone, $msb);

      # Keep track of the repeat count for this msb for the error message
      $nrepeats++;

    }

    # And remove the template node
    $msb->_tree->unbindNode;
    $ncloned++;

    #  info message
    my $pluraltarg = ($blanks == 1 ? '' : 's');
    my $pluralrep  = ($nrepeats == 1 ? '' : 's');
    push(@info,"Cloned MSB with title '" . $msb->msbtitle . 
	 "' $nrepeats time$pluralrep replacing $blanks blank target component$pluraltarg.");


  }

  # Once we have done this we need to recreate the
  # MSB objects because they will be pointing to invalid nodes
  if ($ncloned > 0) {
    $self->locate_msbs;
  } else {
    push(@info, "No MSBs contained blank target components. No change.");
  }
  # Return the informational messages
  return @info;

}


=back

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut



1;

