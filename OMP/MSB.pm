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
use Digest::MD5 2.20 qw/ md5_hex /;
use OMP::Error;
use OMP::General;
use OMP::Range;
use OMP::Info::MSB;
use OMP::Info::Obs;
use OMP::Constants qw/ :msb /;
use Astro::Coords;
use Astro::WaveBand;

use Astro::SLA qw(); # elements

use Data::Dumper;
use Time::Piece ':override';
use Time::Seconds;

our $VERSION = (qw$Revision$)[1];

our $DEBUG = 0;

# Overloading
use overload '""' => "stringify";

# Specify default time interval. These limits
# are the limits of unix epoch (more or less)
our $MAXTIME = OMP::General->parse_date("2035-01-01T01:00");
our $MINTIME = OMP::General->parse_date("1971-01-01T01:00");

# This is the attribute name for the observation counter
my $OBSNUM_ATTR = "obsnum";
my $SUSPEND_ATTR = "suspend"; # suspend attribute

# Default values for "DONT CARE"
use constant CLOUD_DONT_CARE  => 101;
use constant MOON_DONT_CARE   => 101;

use constant NO_TARGET => 'NONE SUPPLIED';

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
    $parser->validation(0);
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

  my $ot_version;
  $ot_version = $args{OTVERSION} if exists $args{OTVERSION};

  # Now create our Science Program hash
  my $msb = {
	    ProjectID => $projid,
	    Parser => $parser,
	    XMLRefs => $refs,
	    Tree => $tree,
	    OT_Version => $ot_version,
	    CheckSum => undef,
	    ObsSum => [],
	    Weather => {},
	    SchedConst => {},
	   };

  # and create the object
  bless $msb, $class;

  # Force the setting of an obscounter in each
  # SpObs so that we can use it to label our observations
  # Do this early since it never hurts and we want to ensure
  # that it is available - does not trigger a large overhead
  $msb->_set_obs_counter();

  # fix up any problems
  $msb->_fixup_msb;

  return $msb;
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

On modification, does not affect the DOM tree of the associated
science program (use a method in the corresponding C<OMP::SciProg>
parent for that).

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

=item B<ot_version>

Returns the version of the XML used to generate this MSB.
Can be undefined.

=cut

sub ot_version {
  my $self = shift;
  return $self->{OT_Version};
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

=item B<remote_trigger>

Returns information on whether this MSB has been initiated via
a remote observation trigger or not.

  %info = $msb->remote_trigger();
  $msb->remote_trigger( %info );

Returns a list (hash) with the
following keys:

  src => The source of the remote trigger (e.g. "ESTAR")
  id  => The remote ID issued by the triggering agent

The values can be C<undef> if no information is available.

Can be used to set new values for the triggers. Only "src" and "id"
keys will be recognized. The underlying XML will be modified. Note
that if "src" and "id" exist but the values are C<undef>, the XML will
still be modfied and assume an '' empty string (not a null
element). Nothing will be done if neither "src" nor "id" exist in the
hash.

=cut

sub remote_trigger {
  my $self = shift;

  # Node names
  my $root     = "remote_trigger_";
  my $src_name = $root . "src";
  my $id_name  = $root . "id";

  if (@_) {
    # read the arguments
    my %info = @_;

    # convert case
    %info = map { lc($_), $info{$_} } keys %info;

    # Make sure we have both src and id
    return if (!exists $info{src} || !exists $info{id});

    # convert undef to empty string
    $info{src} = '' unless defined $info{src};
    $info{id}  = '' unless defined $info{id};

    # Look for the nodes
    my %node;
    ($node{src}) = $self->_get_children_by_name( $self->_tree, $src_name);
    ($node{id}) = $self->_get_children_by_name( $self->_tree, $id_name);

    # set values if we have them
    for my $type (qw/ src id /) {
      if (defined $node{$type}) {
	my $child = $node{$type}->firstChild;
	$child->setData( $info{$type} );
      } else {
	# need to make the node
	my $name = $root . $type;
	my $el = new XML::LibXML::Element( $name );
	$self->_tree->appendChild( $el );
	$el->appendText( $info{$type} );
      }
    }

  } else {
    # Get the data
    my $src = $self->_get_pcdata( $self->_tree, $src_name);
    my $id  = $self->_get_pcdata( $self->_tree, $id_name);

    return (src => $src, id => $id);
  }
}

=item B<sched_constraints>

Return the scheduling constraints. This is usually
the earliest and latest observation dates as well
as, possibly, a minimum elevation to be used for observing
and an indication of whether the MSB is periodic.

  %schedconst = $msb->sched_contraints;

If an earliest or latest value can not be found, default values
in the past and in the far future are chosen (so as not to constrain
the query).

The earliest and latest dates are returned in keys "datemin" and
"datemax" so that they match the style used for other ranges.

The allowed elevation range is stored in key "elevation",
the monitoring period is stored in key "period" (unit of days)
and any preference as to whether the sources are rising or setting
is in "approach".

If a single argument of 'undef' is supplied, the cache is cleared
and re-read.

  $msb->sched_constraints( undef );

=cut

sub sched_constraints {
  my $self = shift;

  if (@_ && not defined $_[0]) {
    # clear the cache if we have a single undefined argument.
    %{$self->{SchedConst}} = ();
  }

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

=item B<isPeriodic>

Determine whether this MSB should be rescheduled periodically.
Returns a boolean.

 $monitor = $msb->isPeriodic;

=cut

sub isPeriodic {
  my $self = shift;
  my %const = $self->sched_constraints;
  my $period = $const{period};

  # Is periodic if the period is a defined value
  # (it is periodic even if the period is 0 days)
  return (defined $period ? 1 : 0 );
}

=item B<setDateMin>

Set the earliest date on which the MSB will be scheduled. Usually
used by monitoring programs.

 $msb->setDateMin( $time );

Time must be a C<Time::Piece> object.

The value is ignored if no scheduling constraints element exists
in the MSB.

Returns true if the date was changed and false if there is no
scheduling constraint component.

=cut

sub setDateMin {
  my $self = shift;
  my $time = shift;

  # Set the 'earliest' tag
  return $self->_set_sched_constraints( 'earliest', $time );
}

=item B<setDateMax>

Set the latest date on which the MSB will be scheduled. Usually
used to set an expiry date with automated agents.

 $msb->setDateMax( $time );

Time must be a C<Time::Piece> object.

The value is ignored if no scheduling constraints element exists
in the MSB.

Returns true if the date was changed and false if there is no
scheduling constraint component.

=cut

sub setDateMax {
  my $self = shift;
  my $time = shift;

  # Set the 'latest' tag
  return $self->_set_sched_constraints( 'latest', $time );
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

=item B<remaining_inc>

Increment the remaining counter of the MSB by the specified amount.

  $msb->remaining_inc( 5 );

A separate method for now since the C<remaining> method can not distinguish
a new value from a request to increment the current value.

Do not be surprised if this method disappears at some point.

=cut

sub remaining_inc {
  my $self = shift;
  my $inc = shift;

  # Get the current value
  my $current = $self->remaining;

  # Tricky bit is the support for REMOVED
  # Assume that we are adding to 0
  $current = 0 if $current == OMP__MSB_REMOVED;

  # Get new value
  $current += $inc;

  # Store it
  $self->remaining( $current );

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

Internal priority can be specified as either a string or an
integer. If it is a string the mapping is:

  01  High
  50  Medium
  99  Low

Returns 1 if the priority is not present. Returns 99 if the
priority is greater than 99, 1 if the priority is less than 1.
Always returns an integer. If priority is defined but can
not be parsed, the priority is returned as 1.

=cut

sub internal_priority {
  my $self = shift;
  my $pri = $self->_get_pcdata( $self->_tree, "priority");

  if (defined $pri) {
    if ($pri =~ /\d/) {
      $pri = int($pri);
      if ($pri < 1) {
	$pri = 1;
      } elsif ($pri > 99) {
	$pri = 99;
      }

    } elsif ($pri =~ /high/i) {
      $pri = 1;
    } elsif ($pri =~ /medium/i) {
      $pri = 50;
    } elsif ($pri =~ /low/i) {
      $pri = 99;
    } else {
      $pri = 1;
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

  $self->find_checksum;

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

If the MSB has an MSBID element in it (not the attribute that we set)
then the assumption is that that MSBID should be used for the checksum
rather than calculating it. This is because when the MSB is sent for
translation it is likely that parts will be removed (deferred calibrations)
in which case the calculated checksum will be incorrect. Since we know
that the MSBID element will only appear in MSBs retrieved from the
database (and not sent to the OT) then this is allowed.

=cut

sub find_checksum {
  my $self = shift;

  # First we need to look for an explicit MSBID
  my (@msbids) = $self->_tree->findnodes('.//msbid');
  # and if we get one we assume that is the checksum
  if (@msbids) {
    # quickest to just find the parent again and ask get_pcdata
    my $msbid = $self->_get_pcdata($msbids[0]->parentNode,"msbid");
    if ($msbid) {
      $self->checksum($msbid);
      return;
    }
  }

  # Get all the children (this is "safer" than stringifying
  # the XML and stripping off the tags and allows me to expand references).
  # I want to do this without having to know anything about XML.

  my $string = $self->_get_qualified_children_as_string;

  # make sure that we generate the same checksum regardless of whether
  # an obsnunm attribute is present in an SpObs. This is because we need
  # to make sure the checksum is the same regardless of counter
  # It doesn't really matter because the only time it shouldn't be the
  # same is when the MSBID is explicitly in the XML but it is important
  # for backwards compatibility for the existing checksums
  my $replace = " $OBSNUM_ATTR=\"". '\d+"';
  $string =~ s/$replace//g;

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

=item B<info>

Return an C<OMP::Info::MSB> object summarizing the MSBs and observations
contained in the XML.

  $info = $msb->info();

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
  my @obs = map { new OMP::Info::Obs( %{$_}, 
				      telescope => $summary{telescope} ) } $self->obssum;
  $info->observations(@obs);

  return $info;
}

=item B<hasBeenObserved>

Indicate that this MSB has been observed. This involves decrementing
the C<remaining()> counter by 1 and, if this is part of an SpOR block
and the parent tree is accessible, adjusting the logic.

If this MSB is meant to be observed periodically, the earliest
observing date ("datemin") is modified so that it will not be
scheduled for the required number of days (the earliest date is set to
be current date + period).

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

 - If the structure of the MSB has been modified (either by
   rescheduling it or by moving it out of an OR folder) the
   checksum is recalculated.

This all requires that there are no non-MSB elements in an SpOR
since inheritance breaks if we move just the MSB (that is only
true if the OT ignores IDREF attributes).

If an MSB was suspended that flag is now cleared.

=cut

sub hasBeenObserved {
  my $self = shift;

  # This is the easy bit
  $self->remaining( -1 );

  # Deal with any periodicity issues
  $self->rescheduleMSB()
    if $self->isPeriodic;

  # unsuspend
  $self->clearSuspended;

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
    print "Current number of items: $n\n" if $DEBUG;
    $n--;

    # Do we need to subtract an additional value?
    # due to a bug in the OT. The bug has not been fixed
    # until 04a (deliberately since it is safer that way)
    # The 04A OT was released on 20031223
    print "OT Version: ". $self->ot_version ."\n" if $DEBUG;
    if (defined $self->ot_version && $self->ot_version > 20030522 && 
	$self->ot_version < 20031223) {
      print "Fudging numberOfItems due to OT bug\n" if $DEBUG;
      $n--;
    }

    $n = 0 if $n < 0;
    $SpOR->setAttribute("numberOfItems", $n);

    print "Number of Items after decrement : $n\n" if $DEBUG;

    # If the number of remaining items is 0 we need to go
    # and find all the MSBs that are left and fix up their
    # "remaining" attributes so that they will no longer be accepted
    # This code is identical to that in OMP::SciProg so we should
    # be doing this in a cleverer way.
    # For now KLUGE KLUGE KLUGE
    if ($n == 0) {
      print "Attempting to REMOVE remaining MSBs\n" if $DEBUG;
      my @msbs = $SpOR->findnodes(".//SpMSB");
      print "Located ".@msbs." SpMSB...\n" if $DEBUG;
      my $count = @msbs;
      push(@msbs, $SpOR->findnodes('.//SpObs[@msb="true"]'));
      print "Located ". (@msbs - $count). " SpObs...\n" if $DEBUG;

      for (@msbs) {
	# Eek this should be happening on little OMP::MSB objects
	$_->setAttribute("remaining",OMP__MSB_REMOVED());
      }
    }

  }

  # Recalculate the checksum if we have changed the MSB
  if ($self->isPeriodic || $SpOR) {
    $self->find_checksum();
  }

}

=item B<undoObserve>

Attempt to reverse the effects of C<hasBeenObserved>.

Currently, does not attempt to reverse any reorganizations
of the science program caused by the MSB being part of an OR/AND
block.

Simply increments the remaining counter by 1.

If this MSB is meant to be observed periodically, the earliest
observing date ("datemin") is reset to the current day (ie the
observation is scheduled to be observed again).

It is usually combined with an update of the database contents to
reflect the modified state.

Any suspend flags are cleared.

=cut

sub undoObserve {
  my $self = shift;
  $self->remaining_inc( 1 );

  # Reset datemin if we are a monitoring MSB
  $self->scheduleMSBnow()
    if $self->isPeriodic;

  # unsuspend
  $self->clearSuspended;

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

If this MSB is meant to be observed periodically, the earliest
observing date ("datemin") is reset to the current day (ie the
observation is scheduled to be observed again). [but this is
not really an issue if it has been removed]

=cut

sub hasBeenCompletelyObserved {
  my $self = shift;

  # This is the easy bit
  $self->remaining( OMP__MSB_REMOVED() );

  # Reset datemin if we are a monitoring MSB
  $self->scheduleMSBnow()
    if $self->isPeriodic;

}

=item B<hasBeenSuspended>

Modify the object to indicate that the MSB has been put into
a suspended state so that it can be completed at a later date.

  $msb->hasBeenSuspended( $label );

The label must match a valid observation label within this
MSB.

=cut

sub hasBeenSuspended {
  my $self = shift;
  my $label = shift;

  # In order to suspend an MSB we need to do the following:
  #  - get a list of observation labels eg obs1_5, obs2_2
  #    where the obs count is the SpObs number and the _I
  #    is the unrolled observation within that SpObs
  #  - Compare the supplied label with the list
  #    and throw an exception if the supplied label is not present
  #  - Add this label as an attribute to the SpMSB
  #    suspend="obs1_5"

  # get the labels
  my @labels = $self->_get_obs_labels;

  # look for the label
  my $isvalid = grep /$label/, @labels;

  throw OMP::Error::FatalError("Supplied observation label [$label] can not be found in MSB [contains: ".join(",",@labels)."]") unless $isvalid;

  # Set the suspend attribute in the MSB
  $self->_tree->setAttribute($SUSPEND_ATTR, $label);

}

=item B<isSuspended>

If the MSB has been suspended return the label of the observation
at which it was supsended. Return C<undef> if the MSB has not been
suspended.

  $label = $msb->isSuspended();

=cut

sub isSuspended {
  my $self = shift;

  return $self->_tree->getAttribute($SUSPEND_ATTR);

}

=item B<clearSuspended>

Clear the suspended state of the MSB.

  $msb->clearSuspended;

Usually called by hasBeenObserved() when an MSB has been completed.

=cut

sub clearSuspended {
  my $self = shift;
  $self->_tree->removeAttribute( $SUSPEND_ATTR );
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
  my @nodes = $self->_get_SpObs();

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

=item B<verifyMSB>

Do a simple verification of the MSB itself.

Returns a status and a string describing any problems.

  ($status, $reason) = $msb->verifyMSB;

Allowed status values are:

  0 - everything okay
  1 - some warnings were raised
  2 - fatal error

Note that fatal errors will probably have been caught during the
initial pass. This method does not attempt to check instrumental
specific problems.

If you receive a fatal error, you would normally want to throw
an explicit exception.

Currently, only checks to make sure that none of the targets are
centred at 0h RA, 0 deg Dec - this is the default setting for the
target component in the Observing Tool.

=cut

sub verifyMSB {
  my $self = shift;

  # Assume good status
  my $status = 0;

  # Get the observations
  my @obs = $self->obssum;

  for my $obs (@obs) {
    my $target = $obs->{coords};
    next unless $target;
    next unless $target->type eq 'RADEC';

    if ($target->ra == 0.0 and $target->dec == 0.0) {
      $status = 1;
    }
  }

  # Check status
  my $string = '';
  if ($status == 1) {
    $string = "Some of the observations in the MSB contained default\n" .
      "settings for the target information. Please specify a real target\n" .
	"if this is not correct";
  }

  return ($status, $string);
}


=item B<scheduleMSBnow>

Set the earliest date for scheduling to the current time.

  $msb->scheduleMSBnow();

The internal XML values are updated.

Any previous value of the date is discarded. Usually invoked to
reverse the effect of observing a periodic MSB.

=cut

sub scheduleMSBnow {
  my $self = shift;
  my $now = gmtime();
  $self->setDateMin($now);
}

=item B<rescheduleMSB>

Set the earliest date for scheduling to be the current time
plus the requested rescheduling period (see C<sched_constraints>).

  $msb->rescheduleMSB();

The internal XML values are updated.

Any previous value for the date is discarded. Usually invoked when
an MSB has been observed.

If the MSB is not periodic, the earliest date for observation will
be reset to the current time. If this is not acceptable use C<isPeriodic>
before calling this method.

Note that this method will change the structure of the MSB and will
therefore also change the checksum. You must invoke the C<find_checksum>
method after calling this method if you wish the checksum to remain
consistent with the XML.

=cut

sub rescheduleMSB {
  my $self = shift;

  # First get the period
  my %const = $self->sched_constraints;
  my $period = $const{period};

  # if we do not have a period assume 0
  $period = 0 unless defined $period;

  # Get the current date
  my $now = gmtime();

  # Add on the number of days
  $now += ( $period * ONE_DAY );

  # Usually people mean integer day but this could be dangerous
  # for places where UT is middle of the night. Doesnt really matter
  # since start of the day means we are rescheduling a few hours earlier
  # than we really cared about but hopefully that is not important

  # First get the date as a string
  my $date = sprintf("%d-%02d-%02d",$now->year, $now->mon, $now->mday);

  # Then convert it back into an object
  $now = Time::Piece->strptime($date, "%Y-%m-%d");

  # Then update the start time
  $self->setDateMin( $now );

}

=item B<getObserverNote>

Locate the notes in the MSB that are meant to be read by the observer.
Inheritance is respected.

  ($title, $note) = $msb->getObserverNote( );

Returns empty list if no note can be found with observeInstruction
set to "true".

=cut

sub getObserverNote {
  my $self = shift;

  # First attempt to get the SpNote and refs
  # (if present)
  my @comp;
  push(@comp, $self->_tree->findnodes(".//SpNoteRef"),
        $self->_tree->findnodes(".//SpNote"));

  # Find the last component that refers to an observer note
  my $el;
  for my $c (reverse @comp) {
    my $resolved = $self->_resolve_ref( $c );
    if ($resolved->getAttribute("observeInstruction") eq 'true') {
      $el = $resolved;
      last;
    }
  }

  # No matches
  return () unless defined $el;

  # Extract
  my $title = $self->_get_pcdata( $el, "title" );
  my $note  = $self->_get_pcdata( $el, "note" );

  return ($title, $note);

}


=item B<hasBlankTargets>

Returns true if the MSB includes an undefined target component
(i.e. RADEC target with no name and with 0:0:0 as the coordinates).
Returns false otherwise. Does not matter if the MSB includes
some defined target components.

  $isblank = $msb->hasBlankTargets();

The return valus is actually the number of blank targets located.
RA and Dec and Title must be blank.

Note that this is done by examining the XML itself rather than
by using the C<obssum> method. This is because the C<obssum>
method returns targets for each observation even if there is
only one target component inherited by multiple SpObs.

By default, blank target components inherited by this routine
are ignored in the count. An optional argument can be used
to specify that inheritance is important if it is true.

  $isBlankInherit = $msb->hasBlankTarget( 1 );

Note that if inheritance is enabled, a structure such as

  Tel
  SpMSB
    Tel
    Obs

will result in one blank target even if both of those components
are blank because the Tel in the MSB will override the inherited
tel. With

  Tel
  SpMSB
    Obs
      Tel

There will be a single blank target if inheritance is disabled but
two blank targets if inheritance is enabled.

For the example:

  SpMSB
    BlankTel
      Obs
        FilledInTel

The number of blank targets is zero (since only the filled in
target is relevant). For

  SpMSB
   BlankTel
    Obs
      BlankTel

The number of relevant blanks is zero.

=cut

sub hasBlankTargets {
  my $self = shift;
  my $inherit = shift;

  # Have to look at the XML itself
  my $xml;
  if ($inherit) {
    $xml = $self->stringify;
  } else {
    $xml = $self->stringify_noresolve;
  }

  # First we reparse this xml
  my $parser = new XML::LibXML;
  my $tree = $parser->parse_string( $xml );

  my @tel = $self->_get_tel_comps( tree => $tree );

  # For each of these components read the target info
  my $nblank = 0;
  for my $tel (@tel) {

    $nblank++ if $self->_is_blank_target( $tel );

  }

  return $nblank;
}

=item B<_is_blank_target>

Returns true if the supplied target node contains a blank
target entry (ie RA==Dec=0.0 and no target name).

  $isblank = $msb->_is_blank_target( $node );

Note that the coordinate can be blank either because it
has a value of 0 or because it is not defined at all.

=cut

sub _is_blank_target {
  my $self = shift;
  my $tel = shift;

  # Get summary of the node
  my %summary = $self->SpTelescopeObsComp( $tel );

  # Get the coordinate
  my $c = $summary{coords};

  if ($c->type eq 'RADEC' && $c->dec == 0.0 && $c->ra == 0.0
      && (!defined $c->name || (defined $c->name && length($c->name) == 0))
      || (defined $c->name && $c->name eq NO_TARGET)
     ) {
    return 1;
  } else {
    return 0;
  }

}


=item B<_get_tel_comps>

Retrieve all the nodes in the current MSB that correspond
to useful telescope components. Mainly an internal routine
for processing the catalogue cloning.

  @tel = $msb->_get_tel_comps();

Includes inheritance but also takes inheritance into account.
See hasBlankTarget for a description of the inheritance rules.
Summarising, if each non-standard SpObs includes a telescope
component then only those components will be returned. If one
non-standard SpObs is missing a component then all the SpObs
components will be retrieved as well as either the component
in the MSB or the component inherited from outside the msb (with
priority given to the component in the MSB).

Optional arguments can disable inheritance from outside the MSB:

  @tel = $msb->_get_tel_comps( noinherit => 1);

or can specify a new parse tree distinct from the default parse
 tree:

  @tel = $msb->_get_tel_comps( tree => $tree );

Note that supplying a new tree implies noinherit = 1 because
the reference can not be resolved between trees.

=cut

sub _get_tel_comps {
  my $self = shift;
  my %args = @_;

  my $tree;
  if (exists $args{tree} && defined $args{tree}) {
    $tree = $args{tree};
    $args{noinherit} = 1;
  } else {
    $tree = $self->_tree;
  }

  # Make sure we are sitting at an MSB
  my ($node) = $tree->findnodes(".//SpMSB");
  $tree = $node if defined $node;

  # Now find all the telscope components
  # We need to find the last Telescope component at the MSB
  # level taking into account inheritance if need be
  my @all;
  if (!$args{noinherit}) {
    push(@all,$tree->findnodes("child::SpTelescopeObsCompRef"));
  }

  push(@all,$tree->findnodes("child::SpTelescopeObsComp"));

  my $msbtel = $all[-1];

  # Resolve refs (only if we are inheriting and we have something)
  $msbtel = $self->_resolve_ref($msbtel) if defined $msbtel && $args{noinherit};

  # Now all the ones in SpObs BUT we have to be careful here.
  # If we have a situation where the number of components
  # in SpObs equals the number of SpObs then inheritance
  # from above is meaningless. One caveat here is that the
  # standard obs do not add towards the sum of SpObs.

  # First find all the SpObs
  my @spobs = $tree->findnodes(".//SpObs");

  # Now find all the ones that have standard=false
  my @nonstandard;
  for my $obs (@spobs) {
    my $isstd = $self->_get_pcdata($obs, "standard");
    push(@nonstandard, $obs) if $isstd eq 'false';
  }

  # And now get the telescope components in the remainder
  my @obstel;
  for my $obs (@nonstandard) {
    my ($tel) = $obs->findnodes(".//SpTelescopeObsComp");
    push(@obstel, $tel) if defined $tel;
  }

  # Now compare count to see if we need to include the MSB tel component
  # (assuming we have one)
  my @tel;
  if (scalar(@obstel) != scalar(@nonstandard)) {
    # Need the MSB component
    push(@tel, $msbtel) if defined $msbtel;
  }
  push(@tel, @obstel);

  return @tel;
}


=item B<_fixup_msb>

Fix up the XML associated with the MSB. This is used to correct any
problems in the OT-generated XML. Hopefully should be a no-op if the
OT generates perfect XML.

  $msb->_fixup_msb();

Called from the constructor.

=cut

sub _fixup_msb {
  my $self = shift;

  # Firstly need to make sure that the optional flag is true if we
  # are an observation in an MSB that has the "standard" flag set to
  # true (and are a JCMT observation).

  # Get the telescope
  my $tel = $self->telescope;

  if ($tel eq 'JCMT') {

    # Get all the observations (same as code in addFITStoObs)
    my @observations = $self->_get_SpObs();

    # go through the Observations
    for my $obs (@observations) {

      # Get the msb attribute
      my $ismsb = $self->_get_attribute( $obs, 'msb');
      $ismsb = ( $ismsb eq 'true' ? 1 : 0);

      # if we are an msb we cant be optional anyway
      next if $ismsb;

      # Get the optional attribute
      my $opt = $self->_get_attribute( $obs, 'optional');
      $opt = ( $opt eq 'true' ? 1 : 0);

      # are we a standard
      my $isstd =  $self->_get_pcdata($obs, "standard" );
      $isstd = ( $isstd eq 'true' ? 1 : 0);

      # Fixup the XML if required. Hopefully this should be fixed in the OT
      # No point changing anything if it is correct already
      if ($isstd && !$opt) {
	$obs->setAttribute("optional", "true")
      }

    }
  }

}

=item B<_get_SpObs>

Return all the SpObs nodes associated with the MSB.

  @spobs = $self->_get_SpObs;

=cut

sub _get_SpObs {
  my $self = shift;
  my @observations;
  if ($self->_tree->getName eq 'SpObs') {
    @observations = $self->_tree;
  } else {
    # Get the SpObs elements
    push(@observations, $self->_tree->findnodes('.//SpObs'));
  }
  return @observations;
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

NO LONGER USED. Use OMP::Info:: classes instead.

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

  #print Dumper(\@obs);

  return @obs;
}

=item B<_set_obs_counter>

Set the "obsnum" attribute in each of the SpObs elements
in the MSB. Counting starts at zero.

  $msb->_set_obs_counter();

If an SpObs already has a counter it is not changed. This is important
because sometimes when an MSB object is instantiated the calibration
observations have been removed which should not affect the observation
count (this is required for reliably suspending an MSB)

=cut

sub _set_obs_counter {
  my $self = shift;

  # get all the SpObs nodes
  my @obs = $self->_get_SpObs();

  my $counter = -1;
  for my $obs (@obs) {
    $counter++;
    # look for a "obsnum" attribute
    my $attr = $self->_get_attribute( $obs, $OBSNUM_ATTR );

    if (defined $attr) {
      # someone has already set obsnum
      # in this case we just tweak the counter to that value
      $counter = $attr;
    } else {
      # no value was present so we set one
      $obs->setAttribute( $OBSNUM_ATTR, $counter);
    }
  }
}

=item B<_clear_obs_counter>

Clear the "obsnum" attribute in each of the SpObs elements
in the MSB. This is usually called prior to serving the science
program back to the observing tool (so that we are forced to
recalculate the counters after resubmission which is the desired
behaviour since the OT will not touch the counter attributes).

  $msb->_clear_obs_counter();

=cut

sub _clear_obs_counter {
  my $self = shift;

  # get all the SpObs nodes
  my @obs = $self->_get_SpObs();

  my $counter = -1;
  for my $obs (@obs) {
    $obs->removeAttribute( $OBSNUM_ATTR );
  }
}

=item B<_get_obs_labels>

Retrieve a list of all the observation labels defined in this
MSB. Useful when determining whether a suspension label
is valid.

  @labels = $msb->_get_obs_labels();

=cut

sub _get_obs_labels {
  my $self = shift;

  my @details = $self->unroll_obs();

  return map { $_->{obslabel} } @details;

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


#  print Dumper(\%summary);

  return %summary;

}

=item B<_get_sched_constraints>

Return the contents of the SchedConstObsComp component as a hash.
Usually used internally by the C<sched_constraints> method.

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

  # Now read the minimum and maximum elevation. Can be undefined.  We
  # use undef to indicate that the science program did not care. This
  # allows the scheduling system to decide what a useful minel and
  # maxel should be. The maximum elevation can also be undefined we
  # create an OMP::Range object regardless
  my $minel = $self->_get_pcdata( $el, "minEl");
  my $maxel = $self->_get_pcdata( $el, "maxEl");
  $summary{elevation} = new OMP::Range( Min => $minel, Max => $maxel);

  # See whether we have any period specified
  $summary{period} = $self->_get_pcdata( $el, "period" );

  # see whether we care about rising or setting
  # -1 indicates rising, +1 indicates setting
  my $approach = $self->_get_pcdata( $el, "meridianApproach");
  if (defined $approach) {
    if ($approach =~ /^ris/) {
      $approach = -1;
    } elsif ($approach =~ /^set/) {
      $approach = 1;
    }
  }
  $summary{approach} = $approach; # undef is okay - no preference

  return %summary;

}

=item B<_set_sched_constraints>

Set a single scheduling constraint time.

  $msb->_set_sched_constraints( $tag => $time );

Tag can be one of "earliest" or "latest". Currently other
constraints can not be specified and only one tag can be
specified at a single time.

Returns false if there is no scheduling constraint component
to edit. Returns true otherwise. The C<sched_constraints> cache
is invalidated.

=cut

sub _set_sched_constraints {
  my $self = shift;
  my $tag = shift;

  # Currently we assume value must be a Time::Piece without checking
  # that the Tag is reasonable
  my $value = shift;

  # Verify arguments
  throw OMP::Error::BadArgs("Tag must be one of 'earliest' or 'latest' not $tag")
    unless ($tag eq 'earliest' || $tag eq 'latest' );

  throw OMP::Error::BadArgs("Value must be Time::Piece object not '".
			   ref($value) ."'")
    unless UNIVERSAL::isa($value, 'Time::Piece');


  # Get the element [this is repeat of code in _get_sched_constraints!!]
  # KLUGE
  # First attempt to get the SpSchedConstObsComp and refs
  # (if present)
  my @comp;
  push(@comp, $self->_tree->findnodes(".//SpSchedConstObsCompRef"),
        $self->_tree->findnodes(".//SpSchedConstObsComp"));

  # and use the last one in the list (hopefully we are only allowed
  # to specify a single value). We get the last one because we want
  # inheritance to work and the refs from outside the MSB are put in
  # before the actual MSB contents
  # return false if we do not have anything to edit
  return () unless @comp;

  my $el = $self->_resolve_ref($comp[-1]);

  # Now find the <earliest> element
  my ($early) = $el->findnodes(".//$tag");

  throw OMP::Error::FatalError("Unable to find <$tag> element in MSB despite having found a SpSchedConstObsComp") unless $early;

  # Get the text node
  my $child = $early->firstChild;

  # set it
  $child->setData( $value->datetime );

  # Need to clear the cache
  $self->sched_constraints( undef );

  return 1;
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

  my @matches = $self->_get_children_by_name( $el, $tag);

  my $pcdata;
  if (@matches) {
    my $child = $matches[-1]->firstChild;
    # Return undef if the element contains no text children
    return undef unless defined $child;
    $pcdata = $child->toString;
  }

  return $pcdata;
}

=item B<_get_attribute>

Get the required attribute value from an element. Returns
C<undef> if the attribute is not present.

  $value = $msb->_get_attribute( $el, $attrname );

Wrapper around XML::LibXML methods to compensate for the 
complete lack of getAttribute method in the API.

[strangely enough getAttribute does exist in the API so this
method is useless. Must fix up at some point since it is
much slower than getAttribute]

=cut

sub _get_attribute {
  my $self = shift;
  my $el = shift;
  my $name = shift;

  my @attr = $el->getAttributes;
  my $value;
  for my $attr (@attr) {
    my $attr_name = $attr->getName;
    if ($attr_name eq $name) {
      $value = $attr->getValue;
      last;
    }
  }
  return $value;
}

=item B<_get_attribute_child>

Retrieve the requested attribute from the named child
element.

  $value = $msb->_get_attribute_child( $el, $tag, $attrname );

Similar to C<_get_pcdata> except for attributes.

=cut

sub _get_attribute_child {
  my $self = shift;
  my ($el, $tag, $attr ) = @_;

  my @matches = $self->_get_children_by_name( $el, $tag);

  my $value;
  if (@matches) {
    my $child = $matches[-1];
    $value = $self->_get_attribute( $child, $attr);
  }

  return $value;
}

=item B<_get_children_by_name>

Wrapper for C<getChildrenByTagName>. Need this because
the interface in XML::LibXML changed and we are still supporting
an older version.

  @nodes = $msb->_get_children_by_name( $parent, $tag );

Returns node objects.

=cut

sub _get_children_by_name {
  my $self = shift;
  my $el = shift;
  my $tag = shift;

  my @matches;
  if ($XML::LibXML::VERSION < 1.4) {
    @matches = $el->getElementsByTagName( $tag );
  } else {
    @matches = $el->getChildrenByTagName( $tag );
  }
  return @matches;
}

=item B<_get_pcvalues>

Some of the XML elements represent arrays as:

  <tag>
    <value>a</value>
    <value>b</value>
    ...
  </tag>

This is essentially the "array" form of C<_get_pcdata>.

  @values = $msb->_get_pcvalues( $node, $tag );

Only uses the first tag that matches. Returns empty list if no
matches or if there are no values.

If the tag name is not provided the assumption is made that the the
node supplied as a first argument will be the node containing the
"value" elements rather than the parent (ie it is not necesary to
search for a matching element just the values).

  @matches = $msb->_get_pcvalues( $node );

Returns an empty list if the tag does not exist.

=cut

sub _get_pcvalues {
  my $self = shift;
  my $el = shift;
  my $tag = shift;

  my $node;
  if ($tag) {
    # look for tag
    ($node) = $el->findnodes( $tag );
  } else {
    # assume we already have it
    $node = $el;
  }

  # return empty list if no node
  return () unless defined $node;

  my @valuenodes = $self->_get_children_by_name( $node, 'value');
  my @values = map { $_->firstChild->toString } @valuenodes;

  return @values;
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

=item B<unroll_obs>

Convert the information stored in C<obssum>, which is just
an entry per C<SpObs>, to an array of actual observation.
This unrolls all iterators.

  @details = $msb->unroll_obs;

Data is returned as an array of hashes (I<not> an array of
C<OMP::Info::Obs> objects). This is because the information in the
hashes is simply a reflection of the information in the iterator
XML. Some translation will probably be required to convert this to
information suitable for a true observation specification.

=cut

sub unroll_obs {
  my $self = shift;
  my @obs = $self->obssum;

  #print "INPUT ",Dumper( \@obs);
  #print "Number of observations to process: ",scalar(@obs),"\n";

  # Loop over each observation in the MSB
  my @longobs;
  for my $obs (@obs) {

    # First get a copy of everything except the
    # iterators
    my %config = %$obs;
    delete $config{SpIter};
    delete $config{obstype};

    # Add MSB information that should propogate to header
    $config{MSBID} = $self->checksum;
    $config{PROJECTID} = $self->projectID;
    $config{SUSPENDED} = $self->isSuspended;

    # this counts the number of "observes" in an SpObs
    # the "minor" counter
    my $counter = 0;

    # Now loop over iterators
    $self->_unroll_obs_recurse(\@longobs, \$counter, $obs->{SpIter}, %config);

  }

  #print Dumper( \@longobs);

  return @longobs;

}

# Recursive method for use by unroll_obs()

sub _unroll_obs_recurse {
  my $self = shift;
  my $obsarr = shift;
  my $obscounter_ref = shift; # reference so that it can be changed everywhere
  my $iterator = shift;
  my %config = @_;

#  print "DUMP: ",Dumper($iterator);

  throw OMP::Error::FatalError "Recursing on non-HASH not supported"
    unless ref($iterator) eq 'HASH';

  for my $iter ( @{$iterator->{CHILDREN}} ) {

    # Iterators always are hashes with two keys:
    #   ATTR - iterator attributes
    #   CHILDREN - array of child iterators
    # this is effectively a simplified XML tree structure

    # Each child is stored as an array of hashes
    # The hash key (there is only one) must be the
    # name of the iterator

    # Attributes are stored as array of hashes. Each element
    # of the array will contain information for a single 
    # observation (effectively we will recurse for each element
    # and append that information to the hash sent)

    # Each iterator must ultimately be an ancestor
    # of an observe to have an effect.
    # Observes are just hashes

    # This allows decendants to be children which allows
    # easy recursion for iterators that trigger multiple observations

    # eg:
    # <INSERT EXAMPLE HERE>


    # Get the key - there can only be one
    my @keys = keys %$iter;
    throw OMP::Error::FatalError "More than one hash key in iterator [".
      join(",",@keys)."]"
      unless scalar(@keys) == 1;

    my $key = $keys[0];

    if ($key =~ /Obs$/) {
      # An observation
      # Calculate the label
      $$obscounter_ref++;
      $config{obslabel} = "obs" . $config{msb_obsnum} . "_" . $$obscounter_ref;

      # dump observation details
      #print "Dump observation details $key - $$obscounter_ref\n";
      push(@$obsarr, {%config, MODE => $key, %{$iter->{$key}}});


    } elsif ($key =~ /^SpIter/) {
      # If the key is an Iter we have to recurse.
      # First need to get the ATTRibutes to decide
      # whether to recurse multiple times (once for
      # each observation)
      my @ATTR = @{$iter->{$key}->{ATTR}};

      throw OMP::Error::SpBadStructure("Empty sequence iterator found: $key")
	unless @ATTR;

      # The next layer down ignores the ATTR array

      #print "Recursing for $key\n";
      for my $extra (@ATTR) {
	$self->_unroll_obs_recurse( $obsarr, $obscounter_ref, $iter->{$key}, 
				    %config, %$extra );
      }

    }


  }


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

  # Determine whether we have a standard or not
  $summary{standard} = $self->_get_pcdata($el, "standard" );
  $summary{standard} = ( $summary{standard} eq 'true' ? 1 : 0 );

  # Reset polarimeter bit since the presence of an SpIterPOL
  # can indicate that the polarimeter is to be used but there
  # will be nothing to indicate its absence. This only works
  # if we are not reading polarimeter information from
  # instrument components (from which we can inherit)
  $summary{pol} = 0;

  # Assume we need to supply a target for most things
  $summary{autoTarget} = 0;

  # Since it is possible for a single observation to include
  # calibrations with autoTarget set we need to make sure
  # that autoTarget will be false if there are any observations
  # that do not use autoTarget. Do this with a second hash entry
  # that logs whenever we hit a science target (defined as an
  # science observe that does not have an autoTarget). Must default
  # to false
  $summary{scitarget} = 0;

  # Retrieve the observation number in this MSB
  $summary{msb_obsnum} = $self->_get_attribute( $el, $OBSNUM_ATTR );

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

  # If we are a standard but have no target we are really an autoTarget
  $summary{autoTarget} = 1 if ($summary{standard} && !exists $summary{coords});

  # Check to see if a Target was present but no Observe
  # If there were calibration observations that do not need
  # targets then we should fill in the targetname now with
  # CAL
  if ( grep /^Observe$/, @{$summary{obstype}} or
       grep /Pointing|Photom|Jiggle|Stare|Raster|Focus/, @{$summary{obstype}}) {

    # Raise an exception unless we have been configured with autoTarget
    if ($summary{autoTarget}) {
      # Need to have a dummy CAL observation here
      # since the translator will need to determine the 
      # target at "run time". This can always be scheduled.
      $summary{coords} = Astro::Coords::Calibration->new;
      $summary{coordstype} = $summary{coords}->type;
      $summary{target} = "TBD";

    } elsif (!exists $summary{coords}) {
      throw OMP::Error::MSBMissingObserve("SpObs has an Observe iterator without corresponding target specified\n");
    }
    # We have a normal observe - just use it and the associated target
    # information

  } else {
    # We have a calibration observation
    $summary{coords} = Astro::Coords::Calibration->new();
    $summary{coordstype} = $summary{coords}->type;

    # The target name should not include duplicates here
    # Use a hash to compress it
    my @compressed = $self->_compress_array( @{ $summary{obstype}});
    $summary{target} = join(":", @compressed);
    $summary{coords}->name( $summary{target} );

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
examined a special cases of SpIterFolder. All Obs iterators (for
example not including Repeat, Offset and POL) are pushed onto the
obstype array regardless of depth.

The SpIter key includes the sequence hierarchy as an array of hashes.

=cut

sub SpIterFolder {
  my $self = shift;
  my $el = shift;
  my %summary = @_;
  my @types;
  my @iterators;

  # Determine the parent iterator
  my $parent;
  $parent = ( exists $summary{PARENT} ? $summary{PARENT} : "SpIter");

  # Init the arrayref and attributes hash
  $summary{$parent} = { CHILDREN => [], ATTR => [] };

  for my $child ( $el->getChildnodes ) {
    my $name = $child->getName;
    next unless defined $name;
    # Special components found within iterators that
    # we can identify and need to open
    if ($name eq 'SECONDARY') {
      # SpIterChop details

      my @chops;
      for my $chops ($child->getChildnodes) {
	my $name = $chops->getName;
	next unless $name eq 'CHOP';
	my %details;
	$details{CHOP_SYSTEM} = $self->_get_attribute( $chops, 'SYSTEM');
	$details{CHOP_THROW}  = $self->_get_pcdata($chops, 'THROW');
	$details{CHOP_PA}  = $self->_get_pcdata($chops, 'PA');
	push(@chops, \%details);
      }

      # Store the chop details
      $summary{$parent}{ATTR} = \@chops;
    } elsif ($name eq 'POLIter') {
      # SpIterPOL iterator for waveplates

      # Get the value tags
      my @waveplate = $self->_get_pcvalues( $child );

      # Store the waveplate angles
      # Treat this as a true iterator (one waveplate per obs)
      # Note that this is not true for JCMT jiggle pol maps
      # but is true for JCMT scan maps and IRPOL observations.
      # Need to fix up this discrepancy later but must take
      # care to retain hierarchy here.
      $summary{$parent}{ATTR}  = [map { { waveplate => [$_]} } @waveplate ];
    } elsif ($name eq 'repeatCount') {
      # SpIterRepeat
      my $repeat = $child->firstChild->toString;
      $summary{$parent}{ATTR} = [ map { { repeat => undef } } 1..$repeat ];

    } elsif ($name eq 'obsArea') {
      # SpIterOffset
      # This code is very like the SECONDARY chop code
      my $pa = $self->_get_pcdata( $child, 'PA');

      my @offsets;
      for my $off ($child->getChildnodes) {
	my $name = $off->getName;
	next unless $name eq 'OFFSET';
	my %details;
	$details{OFFSET_PA} = $pa;
	$details{OFFSET_DX}  = $self->_get_pcdata($off, 'DC1');
	$details{OFFSET_DY}  = $self->_get_pcdata($off, 'DC2');
	push(@offsets, \%details);
      }
      $summary{$parent}{ATTR} = \@offsets;
    }

    # Only interested in iterators
    next unless $name =~ /SpIter/;

    # Cache the iterator order. This must come before the
    # recursion to retain ordering
    push(@iterators, $name);

    # If we are SpIterRepeat or SpIterOffset or SpIterIRPOL 
    # or other iterators
    # we need to go down a level
    if ($name =~ /SpIter(Repeat|Offset|IRPOL|POL|Chop|UISTImaging|UISTSpecIFU)/) {
      my %dummy = $self->SpIterFolder($child, PARENT => $name);

      # obstype is a special key
      if (exists $dummy{obstype}) {
	push(@types, @{$dummy{obstype}});
	delete $dummy{obstype};
      }

      # As is the current structure key
      if (exists $dummy{$name}) {
	push(@{$summary{$parent}{CHILDREN}}, {$name => $dummy{$name}});
	delete $dummy{$name};
      }

      # Merge information with child iterators
      # [probably redundant except for the "pol" flag
      %summary = (%summary, %dummy);

      # SpIterPOL and SpIterIRPOL signifies something significant
      $summary{pol} = 1 if $name =~ /POL$/;

      next;

    } elsif ($name eq 'SpIterStareObs') {

      my $nint =  $self->_get_pcdata( $child, 'integrations');

      # For SCUBA
      my $widePhotom = $self->_get_pcdata( $child, 'widePhotometry' );

      # For Het
      my $switchMode = $self->_get_pcdata( $child, 'switchingMode' );
      my $sPerC = $self->_get_pcdata( $child, 'secsPerCycle');
      my $ccal  = $self->_get_pcdata( $child, 'continuousCal');

      # Frequency switch parameters [inc backwards compatibility]
      my $freqRate = $self->_get_pcdata( $child, 'frequencyOffset.rate');
      $freqRate = $self->_get_pcdata( $child, 'frequencyOffsetRate')
	unless defined $freqRate;
      my $freqOffset = $self->_get_pcdata( $child, 'frequencyOffset.throw');
      $freqOffset = $self->_get_pcdata( $child, 'frequencyOffsetThrow')
	unless defined $freqOffset;

      my %stare;
      $stare{nintegrations} = $nint;
      if (defined $widePhotom) {
	if ($widePhotom eq 'true' || $widePhotom == 1) {
	  $stare{widePhotom} = 1;
	} else {
	  $stare{widePhotom} = 0;
	}
      }
      $stare{secsPerCycle}  = $sPerC if defined $sPerC;
      $stare{switchingMode} = $switchMode if defined $switchMode;
      $stare{continuousCal} = $ccal if defined $ccal;
      $stare{frequencyRate} = $freqRate if defined $freqRate;
      $stare{frequencyOffset} = $freqOffset if defined $freqOffset;

      push(@{$summary{$parent}{CHILDREN}}, { $name => \%stare});
      $summary{scitarget} = 1;
      $summary{autoTarget} = 0;

    } elsif ($name eq 'SpIterJiggleObs') {

      my %jiggle;
      $jiggle{jigglePattern} = $self->_get_pcdata($child,
						  'jigglePattern');
      $jiggle{nintegrations} = $self->_get_pcdata( $child, 'integrations');
      $summary{scitarget} = 1;
      $summary{autoTarget} = 0;

      push(@{$summary{$parent}{CHILDREN}}, { SpIterJiggleObs => \%jiggle});

    } elsif ($name eq 'SpIterPointingObs') {

      my $nint =  $self->_get_pcdata( $child, 'integrations');
      my $pix = $self->_get_pcdata( $child, 'pointingPixel');
      my $autoTarget = $self->_get_pcdata( $child, 'autoTarget' );
      my $auto = ( $autoTarget eq 'true' ? 1 : 0);

      # Focus and pointing dont need explicit targets
      # Can only set the global autoTarget switch to true
      # if we have not already had a science target. If the
      # switch is set to false then this is also a science target
      if ($auto) {
	$summary{autoTarget} = 1
	  unless $summary{scitarget};
      } else {
	$summary{scitarget} = 1;
	$summary{autoTarget} = 0;
      }

      push(@{$summary{$parent}{CHILDREN}}, { $name => { 
						       nintegrations => $nint,
						       autoTarget => $auto,
						       #pointingPixel => $pix,
						      }});


    } elsif ($name eq 'SpIterFocusObs') {

      my $nint =  $self->_get_pcdata( $child, 'integrations');
      my $npoints = $self->_get_pcdata( $child, 'focusPoints');
      my $axis = $self->_get_pcdata( $child, 'axis');
      my $steps = $self->_get_pcdata( $child, 'steps');
      my $autoTarget = $self->_get_pcdata( $child, 'autoTarget' );
      my $auto = ( $autoTarget eq 'true' ? 1 : 0);

      # Focus and pointing dont need explicit targets
      # Can only set the global autoTarget switch to true
      # if we have not already had a science target. If the
      # switch is set to false then this is also a science target
      if ($auto) {
	$summary{autoTarget} = 1
	  unless $summary{scitarget};
      } else {
	$summary{scitarget} = 1;
	$summary{autoTarget} = 0;
      }

      push(@{$summary{$parent}{CHILDREN}}, { $name => { 
						       nintegrations => $nint,
						       autoTarget => $auto,
						       focusPoints => $npoints,
						       focusAxis => $axis,
						       focusStep => $steps,
						      }});


    } elsif ($name eq 'SpIterNoiseObs') {

      my $nint =  $self->_get_pcdata( $child, 'integrations');
      my $source = $self->_get_pcdata( $child, 'noiseSource');

      push(@{$summary{$parent}{CHILDREN}}, { $name => {
						       nintegrations => $nint,
						       noiseSource => $source,
						       }});

    } elsif ($name eq 'SpIterSkydipObs') {

      my $nint =  $self->_get_pcdata( $child, 'integrations');
      my $currAz = $self->_get_pcdata( $child, 'useCurrentAz');
      # Defaults to false if not present
      if (defined $currAz) {
	$currAz = ($currAz =~ /^false$/i ? 0 : 1);
      } else {
	$currAz = 0;
      }


      push(@{$summary{$parent}{CHILDREN}}, { $name => { nintegrations => $nint,
							currentAz => $currAz,
						      }});

    } elsif ($name eq 'SpIterRasterObs') {

      $summary{scitarget} = 1;
      $summary{autoTarget} = 0;

      my %scan;
      $scan{nintegrations} =  $self->_get_pcdata( $child, 'integrations');

      # Heterodyne includes some information specific to that mode
      # For scuba sampleTime is a constant: 0.125sec
      my $samptime = $self->_get_pcdata($child, "sampleTime");
      $scan{sampleTime} = $samptime if defined $samptime;

      my $rowsPerCal = $self->_get_pcdata($child, "rowsPerCal");
      $scan{rowsPerCal} = $rowsPerCal if defined $rowsPerCal;

      # scan information is in <obsArea>
      # PA
      my ($node) = $child->findnodes(".//obsArea/PA");
      $scan{MAP_PA} = $node->firstChild->toString;

      ($node) = $child->findnodes(".//obsArea/SCAN_AREA/AREA");
      $scan{MAP_HEIGHT} = $self->_get_attribute($node, 'HEIGHT');
      $scan{MAP_WIDTH} = $self->_get_attribute($node, 'WIDTH');

      ($node) = $child->findnodes(".//obsArea/SCAN_AREA/SCAN");
      $scan{SCAN_DY} = $self->_get_attribute($node, 'DY');
      $scan{SCAN_SYSTEM} = $self->_get_attribute($node, 'SYSTEM');
      $scan{SCAN_VELOCITY} = $self->_get_attribute($node, 'VELOCITY');

      # Dont use _get_pcdata here since we want multiple matches
      my (@scanpa) = $node->findnodes(".//PA");
      $scan{SCAN_PA} = [ map { $_->firstChild->toString } @scanpa ];

      push(@{$summary{$parent}{CHILDREN}}, { SpIterRasterObs => \%scan});

    }


    # Remove the SpIter string
    $name =~ s/^SpIter//;
    $name =~ s/Obs$//;

    # and the list of observes
    push(@types, $name);


  }

  # Store results
  $summary{obstype} = \@types if @types;
#  $summary{SpIter}->{order} = \@iterators if @iterators;

  delete $summary{PARENT};

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

=item B<SpInstUIST>

Examine the structure of this name and add information to the
argument hash.

  %summary = $self->SpInstUIST( $el, %summary );

where C<$el> is the XML node object and %summary is the
current hierarchy.

=cut

sub SpInstUIST {
  my $self = shift;
  my $el = shift;
  my %summary = @_;

  $summary{telescope} = "UKIRT";
  $summary{instrument} = "UIST";

  # We have to make sure we set all instrument related components
  # else the hierarchy might print through

  # If we are IMAGING we need to pick up the filter name
  # If we are SPECTROSCOPY we need to pick up the central
  # wavelength
  my $type = $self->_get_pcdata( $el, "camera" );

  if ($type eq 'imaging') {
    my $filter = $self->_get_pcdata( $el, "filter" );
    $summary{waveband} = new Astro::WaveBand( Filter => $filter,
					      Instrument => 'UIST');

    $summary{disperser} = undef;
  } else {
    my $wavelength = $self->_get_pcdata( $el, "centralWavelength" );
    $summary{waveband} = new Astro::WaveBand( Wavelength => $wavelength,
					      Instrument => 'UIST');

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

  # Get some info required for translator
  $summary{primaryBolometer} = $self->_get_pcdata($el, 'primaryBolometer');

  # Bolometers are either singular (pcdata) or array
  # This is indeed annoying
  # First try it as an array
  $summary{bolometers} = [ $self->_get_pcvalues( $el, 'bolometers') ];

  # If we get nothing useful try it as a single value
  $summary{bolometers} = [$self->_get_pcdata( $el, 'bolometers')]
    unless @{$summary{bolometers}};

  # Camera mode
  $summary{type} = "i";

  return %summary;
}

=item B<SpInstHeterodyne>

Heterodyne configuration. Extracts the front end and rest frequency 
from the heterodyne XML.

  %summary = $self->SpInstHeterodyne( $el, %summary );

where C<$el> is the XML node object and %summary is the
current hierarchy.

=cut

sub SpInstHeterodyne {
  my $self = shift;
  my $el = shift;
  my %summary = @_;

  # In principal we should be deriving the telescope from other sources
  # since this component is generic. For now, force JCMT
  $summary{telescope} = "JCMT";

  # Instrument is derived from the front end name. The backend is
  # irrelevant for scheduling purposes
  $summary{instrument} = uc($self->_get_pcdata($el, 'feName'));

  # We need to tidy up this instrument name because
  # i) we really need Rx in front of A3 but not HARP
  # ii) W(C) is not an instrument
  $summary{instrument} = "RX". $summary{instrument}
    unless ($summary{instrument} =~ /^RX/ || $summary{instrument} eq 'HARP');

  $summary{instrument} =~ s/\(.*\)$//;

  # The wavelength of interest is derived from the rest frequency
  my $rfreq  = $self->_get_pcdata( $el, "restFrequency" );

  if (!defined $rfreq) {
    throw OMP::Error::SpBadStructure("No rest frequency supplied!");
  }

  # Astro::WaveBand should probably take a velocity, velocity frame
  # and line as argument to correctly call itself a WaveBand class
  $summary{waveband} = new Astro::WaveBand( Frequency => $rfreq,
					    Instrument => $summary{instrument}
					  );
  $summary{wavelength} = $summary{waveband}->wavelength;

  # Translator specific stuff [really need to tweak Astro::Waveband
  # so that it handles velocity properly
  $summary{freqconfig} = {
			  restFrequency => $rfreq,
			  # The velocity field always has the optical velocity
			  optVelocity => $self->_get_pcdata($el, "velocity"),
			  velocityDefinition => $self->_get_pcdata($el,
								   "velocityDefinition"),
			  velocityFrame => $self->_get_pcdata($el,"velocityFrame"),
			  velocity => $self->_get_pcdata($el,"referenceFrameVelocity"),
			  bandWidth => $self->_get_pcdata($el,"bandWidth"),
			  sideBand => $self->_get_pcdata($el,"band"),
			  mixers => $self->_get_pcdata($el,"mixers"),
			  sideBandMode => $self->_get_pcdata($el,"mode"),
			  transition => $self->_get_pcdata($el,"transition"),
			  molecule => $self->_get_pcdata($el,"molecule"),
			  configuration => $self->_get_pcdata($el,"configuration"),
			 };

  # Camera mode is really a function of front end and observing
  # mode. "s" for spectroscopy does not really say enough
  # For JCMT we probably should have "imaging" and "sample"
  # to indicate mapping vs photometry mode
  $summary{type} = 's';

  # Everything else is simply information required by the
  # translator but there is an issue over whether the translator
  # will have to work with this subset or simply get the component
  # XML (which could be included in %summary). For the DAS it
  # can probably be done simply.
  # It probably makes sense to create an Object that represents
  # this XML. This object is then passed to the translator.

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
  #  <target type="SCIENCE">
  #       ...
  # New version has:
  # <BASE TYPE="Base">
  #   <target>
  #        ....
  # and changes hmsdeg and degdeg to spherSystem


  # We need to parse each of the BASE positions specified
  # Usually SCIENCE, REFERENCE or BASE and SKY
  # We should find all the BASE entries and parse them in turn.
  # Supporting the old style is a pain

  # Look for BASE
  my @base = $el->findnodes( './/BASE');

  # if we have not got any we look for "base"
  @base = $el->findnodes( './/base') unless @base;

  # Could be an error (it is for now) but we may be specifying 
  # "best guess" as an option for the translator for pointing and
  # standards
  throw OMP::Error::SpBadStructure("No base target position specified in SpTelescopeObsComp\n") unless @base;


  # For each of these nodes we need to extract the target information
  # and the tag
  my %tags;
  for my $b (@base) {
    # The tag is either an attribute of BASE
    # or an attribute of target
    my $tag = $b->getAttribute( 'TYPE' );

    # Now need to find the target
    my ($target) = $b->findnodes( './/target' );

    throw OMP::Error::SpBadStructure("Unable to find target inside BASE SpTelescopeObsComp\n") unless $target;

    # If we have not got a tag we should look for it in target
    $tag = $target->getAttribute( 'type' ) unless defined $tag;

    # Error if we do not have a tag
    throw OMP::Error::SpBadStructure("Unable to find tag associated with this base position") unless defined $tag;

    # Now extract the coordinate information
    $tags{$tag} =  { $self->_extract_coord_info( $target ) };

    # There may be an offset for REFERENCE or SKY
    if ($tag eq 'REFERENCE' || $tag eq 'SKY') {
      # Look for an offset
      my ($offset) = $b->findnodes('.//OFFSET');

      if (defined $offset) {
	# Parse the offset information
	$tags{$tag}->{OFFSET_DX} = $self->_get_pcdata($offset, 'DC1');
	$tags{$tag}->{OFFSET_DY} = $self->_get_pcdata($offset, 'DC2');
      }

    }

  }

  # SCIENCE or Base tags get copied into the main %summary hash
  # REFERENCE, SKY and GUIDE are copied directly
  if (exists $tags{SCIENCE} && exists $tags{Base}) {
    throw OMP::Error::SpBadStructure("You are not allowed to specify both a SCIENCE position and a Base position");
  } elsif (!exists $tags{SCIENCE} && !exists $tags{Base} ) {
    throw OMP::Error::SpBadStructure("You must specify either a SCIENCE position or a Base position");
  }

  for my $t (qw/ SCIENCE Base/) {
    next unless exists $tags{$t};
    %summary = (%summary, %{$tags{$t}});
    delete $tags{$t};
  }

  # Copy all the others
  $summary{coordtags} = \%tags;

  return %summary;
}

=item B<_extract_coord_info>

This routine will parse a TCS XML "target" element and return
the relevant information. Does not know about the TYPE

 %results = $self->_extract_coord_info( $element );

=cut

sub _extract_coord_info {
  my $self = shift;
  my $target = shift;

  # Somewhere to store the information
  my %summary;
  $summary{target} = $self->_get_pcdata($target, "targetName");
  $summary{target} = NO_TARGET unless defined $summary{target};

  # Now we need to look for the coordinates. If we have hmsdegSystem
  # or degdegSystem (for Galactic) we translate those to a nice easy
  # J2000. If we have conicSystem or namedSystem then we have a moving
  # source on our hands and we have to work out it's azel dynamically
  # If we have a degdegSystem with altaz we can always schedule it.
  # spherSystem now replaces hmsdegsystem and degdegsystem

  # Search for the element matching (this will be targetName 90% of the time)
  # We know there is only one system element per target
  my ($system) = $self->_get_child_elements($target, qr/System$/);

  # Get the coordinate system name
  my $sysname = $system->getName;

  # Get the coordinate frame. This is either "type" or "SYSTEM"

  # Frossie says: The OT was using the type attribute when in fact
  # type is a reserved java keyword. Therefore Shaun changed it to
  # upper case TYPE. To avoid breaking existing programs I am changing
  # this to look for either case. The need for this will evaporate
  # after about a semester.

  # Code being replaced:


  #  my $type = ($sysname eq 'spherSystem' ? 
  #  $system->getAttribute("SYSTEM") : $system->getAttribute("type"));

  # New code:

  my $type;

  if ($sysname eq 'spherSystem') {

    $type = $system->getAttribute("SYSTEM");

  } elsif (defined $system->getAttribute("type")) {

    $type = $system->getAttribute("type");

  } else {

    $type = $system->getAttribute("TYPE");

    }




  if ($sysname eq "hmsdegSystem" or $sysname eq "degdegsystem"
     or $sysname eq 'spherSystem') {

    # Get the "long" and "lat"
    my $c1 = $self->_get_pcdata( $system, "c1");
    my $c2 = $self->_get_pcdata( $system, "c2");

    # degdeg uses different keys to hmsdeg
    #print "System: $sysname\n";
    my ($long ,$lat);
    my %coords;
    if ($type eq "J2000" or $type eq "B1950") {
      %coords = ( ra => $c1, dec => $c2, type => $type);
    } elsif ($type =~ /gal/i) {
      %coords = ( long => $c1, lat => $c2, type => 'galactic', units=>'deg' );
    } elsif ($type eq 'Az/El') {
      %coords = ( az => $c1, el => $c2 );
    }

    # Create a new coordinate object
    $summary{coords} = new Astro::Coords( %coords,
					   name => $summary{target});

    throw OMP::Error::FatalError("Error reading coordinates from XML for target $summary{target}. Tried ".
				 Dumper(\%coords))
      unless defined $summary{coords};

    $summary{coordstype} = $summary{coords}->type;

  } elsif ($sysname eq "conicSystem") {

    # Orbital elements. We need to get the (up to) 8 numbers
    # and store them in an Astro::Coords.
    $summary{coordstype} = "ELEMENTS";

    # Lookup table for XML to SLALIB
    # should probably put this in Astro::Coords::Elements
    # and default to knowledge of units if, for example,
    # supplied as 'inclination' rather than 'orbinc'
    # XML should have epoch in MJD without modification
    my %lut = (EPOCH  => 'epoch',
	       ORBINC => 'inclination',
	       ANODE  => 'anode',
	       PERIH  => 'perihelion',
	       AORQ   => 'aorq',
	       E      => 'e',
	       AORL   => 'LorM',
	       DM     => 'n',
	       EPOCHPERIH => 'epochPerih',
	      );

    # Create an elements hash
    my %elements;
    for my $el (keys %lut) {

      # Skip if we are dealing with "comet" or minor planet
      # and are at DM
      next if ($el eq 'DM' && ($type =~ /Comet/i || $type =~ /Minor/i));

      # AORL is not relevant for comet
      next if ($el eq 'AORL' && $type =~ /Comet/i);

      # Get the value from XML
      my $value = $self->_get_pcdata( $system, $lut{$el});

      # Convert to raidnas
      if ($el =~ /^(ORBINC|ANODE|PERIH|AORL|DM)$/) {
	# Convert to radians
	$value *= Astro::SLA::DD2R;
      }

      # Store the value
      $elements{$el} = $value;

    }

    $summary{coords} = Astro::Coords->new( elements => \%elements,
					   name => $summary{target});

    throw OMP::Error::FatalError("Error reading coordinates from XML for target $summary{target}. Tried elements".
				 Dumper(\%elements))
      unless defined $summary{coords};


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

Copyright (C) 2001-2003 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;

