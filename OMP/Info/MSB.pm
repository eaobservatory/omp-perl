package OMP::Info::MSB;

=head1 NAME

OMP::Info::MSB - MSB information

=head1 SYNOPSIS

  use OMP::Info::MSB;

  $msb = new OMP::Info::MSB( %hash );

  $checksum = $msb->checksum;
  $projectid = $msb->projectid;

  @observations = $msb->observations;
  @comments = $msb->comments;

  $xml = $msb->summary('xml');
  $html = $msb->summary('html');
  $text = "$msb";

=head1 DESCRIPTION

A compact way of handling information associated with an MSB. This
includes possible comments and information on component observations.


This class should not be confused with C<OMP::MSB>. That class 
is based around the Science Program XML representation of an MSB
and not for general purpose MSB information.

=cut

use 5.006;
use strict;
use warnings;
use Carp;
use OMP::Range;
use OMP::Error;
use OMP::Constants qw/ :msb /;
use Time::Seconds;
use OMP::General; # For Time::Seconds::pretty_print


use base qw/ OMP::Info::Base /;

our $VERSION = (qw$Revision$)[1];

use overload '""' => "stringify";

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

=back

=begin __PRIVATE__

=head2 Create Accessor Methods

Create the accessor methods from a signature of their contents.

=cut

__PACKAGE__->CreateAccessors( projectid => '$__UC__',
			      msbid => '$',
                              tau => 'OMP::Range',
                              checksum => '$',
                              seeing => 'OMP::Range',
                              priority => '$',
			      schedpri => '$',
                              moon =>  'OMP::Range',
			      sky => 'OMP::Range',
                              timeest => '$',
                              title => '$',
                              datemin => 'Time::Piece',
                              datemax => 'Time::Piece',
                              telescope => '$',
                              cloud => 'OMP::Range',
                              observations => '@OMP::Info::Obs',
 	                      wavebands => '$',
 	                      targets => '$',
 	                      instruments => '$',
			      coordstypes => '$',
			      nrepeats => '$',
			      elevation => 'OMP::Range',
                              remaining => '$',
			      completion => '$',
                              comments => '@OMP::Info::Comment',
                              approach => '$',
                             );
#' for the emacs color coding 

=end __PRIVATE__

=head2 Accessor Methods

Scalar accessors:

=over 4

=item B<projectid>

=item B<checksum>

=item B<priority>

Priority allocated by the TAG (integer part) and the PI (decimal part).

=item B<schedpri>

The scheduling priority. Not necessarily the same as the (TAG) priority.
Usually depends on the time it was calculated (the airmass/hour angle is used
in the calculation) and so is not calculated dynamically in this class.

=item B<timeest>

=item B<title>

Title of the MSB.

=item B<completion>

Completion percentage for the project associated with this MSB.

=item B<remaining>

Number of repeat counts remaining. The isRemoved check should be
made prior to using this number just in case the MSB has been removed
from consideration.

=item B<msbid>

Not to be confused with the checksum, this is simply a link
to the database row used to store MSB information.

=item B<nrepeats>

Number of times this MSB has been repeated (the complement
to the "remaining" field). In many cases this entry is empty.
Only really relevant when using results from the
MSB done table.

=back

Accessors requiring/returning C<OMP::Range> objects:

=over 4

=item B<tau>

Tau range.

=item B<seeing>

Seeing range in arcsec.

=item B<moon>

Allowed Moon illumination percentage range. 0% implies the moon is not up.

=item B<cloud>

Allowed cloud attenuation variability percentage range

=item B<sky>

Allowed Sky brightness range. Units and filter are telescope dependent.

=item B<elevation>

The minimum and maximum usable elevation for all the targets within this MSB.

=back

Accessors requiring/returning C<Time::Piece> objects

=over 4

=item B<datemin>

=item B<datemax>

=back

Array accessors:

=over 4

=item B<observations>

=item B<comments>

Array of C<OMP::Info::Comment> objects.

=back

=head2 General Methods

=over 4

=item B<waveband>

Construct a waveband summary of the MSB. This retrieves the waveband
from each observation and returns a single string. Duplicate wavebands
are ignored.

  $wb = $msb->waveband();

If a waveband string has been stored in C<wavebands()> that value
will be used in preference to looking for constituent observations.

If a value is supplied it is passed onto the C<wavebands> method.

=cut

sub waveband {
  my $self = shift;
  if (@_) {
    my $wb = shift;
    return $self->wavebands( $wb );
  } else {
    my $cache = $self->wavebands;
    if ($cache) {
      return $cache;
    } else {
      # Ask the observations
      return scalar($self->_process_obs("waveband",1));
    }
  }

}

=item B<instrument>

Construct a instrument summary of the MSB. This retrieves the instrument
from each observation and returns a single string. Duplicate instruments
are ignored.

  $targ = $msb->instrument();

If a instruments string has been stored in C<instruments()> that value
will be used in preference to looking for constituent observations.

If a value is supplied it is passed onto the C<instruments> method.

=cut

sub instrument {
  my $self = shift;
  if (@_) {
    my $i = shift;
    return $self->instruments( $i );
  } else {
    my $cache = $self->instruments;
    if ($cache) {
      return $cache;
    } else {
      # Ask the observations
      return scalar($self->_process_obs("instrument",1));
    }
  }

}

=item B<msbtid>

Return a list of MSB transaction ids associated with this MSB object.

 @msbtids = $msb->msbtid;

If a transaction ID is supplied as an argument, returns the comment objects
associated with that specific transaction.

 @comments = $msb->msbtid( $msbtid );

=cut

sub msbtid {
  my $self = shift;
  my @comments = $self->comments;

  if (@_) {
    my $msbtid = shift;
    return grep { defined $_->tid && $_->tid eq $msbtid } @comments;
  } else {
    return map { $_->tid } grep { defined $_->tid } @comments;
  }
}

=item B<target>

Construct a target summary of the MSB. This retrieves the target
from each observation and returns a single string. Duplicate targets
are ignored.

  $targ = $msb->target();

If a targets string has been stored in C<targets()> that value
will be used in preference to looking for constituent observations.

If a value is supplied it is passed onto the C<targets> method.

=cut

sub target {
  my $self = shift;
  if (@_) {
    my $t = shift;
    return $self->targets( $t );
  } else {
    my $cache = $self->targets;
    if ($cache) {
      return $cache;
    } else {
      # Ask the observations
      return scalar($self->_process_obs("target",1));
    }
  }

}

=item B<ha>

Construct a summary of the hour angle for each of the observation
targets. This simply uses the C<Astro::Coords> object in each
observation object. If no observations are present returns
an empty string.

  $ha = $msb->ha;

Takes no arguments.

=cut

sub ha {
  my $self = shift;
  # Ask the observations
  my @ha = $self->_process_coords( sub {
				     my $c = shift;
				     return sprintf("%.1f",
						    $c->ha( format => "h",
							   normalize => 1));
				   });
  return join("/",@ha);
}

=item B<airmass>

Construct a summary of the airmass for each of the observation
targets. This simply uses the C<Astro::Coords> object in each
observation object. If no observations are present returns
an empty string.

  $ha = $msb->airmass;

Takes no arguments.

=cut

sub airmass {
  my $self = shift;
  # Ask the observations
  my @am = $self->_process_coords( sub {
				     my $c = shift;
				     return sprintf("%.3f",
						    $c->airmass);
				   });
  return join("/",@am);
}

=item B<ra>

Construct a summary of the apparent right ascension for each of the observation
targets. This simply uses the C<Astro::Coords> object in each
observation object. If no observations are present returns
an empty string.

  $ra = $msb->ra;

Takes no arguments.

=cut

sub ra {
  my $self = shift;
  # Ask the observations
  my @ra = $self->_process_coords( sub {
				     my $c = shift;
				     return sprintf("%.1f",
						    $c->ra_app( format => "h",
							       normalize => 1));
				   });
  return join("/",@ra);
}

=item B<dec>

Construct a summary of the apparent declination for each of the observation
targets. This simply uses the C<Astro::Coords> object in each
observation object. If no observations are present returns
an empty string.

  $dec = $msb->dec;

Takes no arguments.

=cut

sub dec {
  my $self = shift;
  # Ask the observations
  my @dec = $self->_process_coords( sub {
				     my $c = shift;
				     return sprintf("%.1f",
						    $c->dec_app( format => "d")),
				   });
  return join("/",@dec);
}

=item B<az>

Construct a summary of the azimuth for each of the observation
targets. This simply uses the C<Astro::Coords> object in each
observation object. If no observations are present returns
an empty string.

  $az = $msb->az;

Takes no arguments.

=cut

sub az {
  my $self = shift;
  # Ask the observations
  my @az = $self->_process_coords( sub {
				     my $c = shift;
				     return sprintf("%.0f",
						    $c->az( format => "d")),
				   });
  return join("/",@az);
}


=item B<coordstype>

Construct a coordinate type summary of the MSB. This retrieves the
type from each observation and returns a single string. Duplicate
types are ignored.

  $types = $msb->coordstype();

If a type string has been stored in C<coordstypes()> that value
will be used in preference to looking for constituent observations.

If a value is supplied it is passed onto the C<coordstypes> method.

=cut

sub coordstype {
  my $self = shift;
  if (@_) {
    my $t = shift;
    return $self->coordstypes( $t );
  } else {
    my $cache = $self->coordstypes;
    if ($cache) {
      return $cache;
    } else {
      # Ask the observations
      my @types = map { $_->coords->type } 
	grep { defined $_->coords } 
	  $self->observations;
      @types = $self->_compress_array( @types );
      return join("/", @types);
    }
  }

}

=item B<obscount>

Returns the number of observations stored in the MSB.

  $nobs = $msb->obscount;

=cut

sub obscount {
  my $self = shift;
  return scalar(@{ $self->observations });
}

=item B<addComment>

Push a comment onto the stack.

  $msb->addComment;

The comment must be of class C<OMP::Info::Comment>.

=cut

sub addComment {
  my $self = shift;
  my $comment = shift;

  # Go verbose in order for the observations() method
  # to check class. Alternative is to check class here
  # and then use the array reference
  my @comments = $self->comments;
  push(@comments, $comment);
  $self->comments( \@comments );
}

=item B<isRemoved>

Returns true if the MSB status indicates that it has been removed from
scheduling consideration or if the remaining field is not defined.

=cut

sub isRemoved {
  my $self = shift;
  return 1 if !defined $self->remaining;
  return 1 if $self->remaining == OMP__MSB_REMOVED;
  return ($self->remaining < 0 ? 1 : 0 );
}

=item B<summary>

Return a summary of this object in the requested format.

  $summary = $msb->summary( 'xml' );

If called in a list context default result is 'hash'. In scalar
context default result if 'xml'.

Allowed formats are:

 'textshort' - short text summary (one line)
 'textshorthdr' - header for short text summary 
 'textlong'  - long text summary
 'xmlshort' - XML summary where observations are compressed
 'xml' - XML summary where Observations are explicitly separate
 'htmlshort' - short HTML summary
 'html' - longer HTML summary
 'htmlcgi' - longer HTML summary with 'add comment' button
 'hashshort' - returns hash representation of MSB where Observations
               are retained as objects
 'hashlong'  - hash rep. of MSB where Observations are array of hashes

If the string '_noast' is appended to any format (resulting in,
for example, 'textlong_noast'), no information that requires
astrometry to be performed (such as RA and DEC) will be included in
the summary.  This can greatly reduce the amount of time it takes
to generate a summary.

The XML short format will be something like the following:

 <SpMSBSummary id="string">
    <checksum>de252f2aeb3f8eeed59f0a2f717d39f9</checksum>
    <remaining>2</remaining>
     ...
    <instruments>CGS4/IRCAM</instruments>
  </SpMSBSummary>

where the elements match the key names in the hash. An C<msbid> key
is treated specially. When present this id is used in the SpMSBSummary
element directly.

The long XML format includes explicit observations.

 <SpMSBSummary id="string">
    <checksum>de252f2aeb3f8eeed59f0a2f717d39f9</checksum>
    <remaining>2</remaining>
     ...
    <SpObsSummary>
      <instrument>IRCAM</instrument>
       ...
    </SpObsSummary>
    <SpObsSummary>
      <instrument>CGS4</instrument>
       ...
    </SpObsSummary>
  </SpMSBSummary>

The XML representation includes the hour angle, elevation
and airmass (using the C<Astro::Coords> objects stored in the
observations if present).

=cut

sub summary {
  my $self = shift;

  # Calculate default formatting
  my $format = (wantarray() ? 'hash' : 'xml');

  # Read the actual value
  $format = lc(shift);

  # If 'noast' is appended to format value, do not include elements
  # in the summary that require astrometry to be performed
  my $noast;
  if ($format =~ /_noast$/) {

    # Get rid of the _noast portion
    $format =~ s/_noast$//;

    # Set the 'noast' option to true
    $noast = 1;
  }

  # Field widths for short text summary. Do this early
  # so that we can process textshorthdr without querying
  # the object
  my @keys = qw/projectid title remaining obscount tau seeing
    pol type instrument waveband target coordstype timeest /;

  # Field widths %s does not substr a string - real pain
  # Therefore need to substr ourselves
  my @width = qw/ 11 10 3 3 9 8 3 3 20 20 20 6 8 /;
  throw OMP::Error::FatalError("Bizarre problem in OMP::Info::MSB::summary ")
    unless @width == @keys;
  my $textformat = join(" ",map { "%-$_"."s" } @width);

  # Generate the header
  if ($format eq 'textshorthdr') {
    my @head = map {
      substr(ucfirst($keys[$_]),0,$width[$_])
    } 0..$#width;
    return sprintf $textformat, @head;
  }

  # First build up a hash from the object
  my %summary;

  # These are the scalar/objects
  my @elements = qw/ projectid checksum tau seeing priority moon timeest title
		     elevation datemin datemax telescope cloud sky remaining
                     msbid approach schedpri completion /;

  # Include astrometry elements unless 'noast' option is being used
  push @elements, qw/ ra airmass ha dec az /
    unless ($noast);

  for (@elements) {
    $summary{$_} = $self->$_();
  }

  # Convert to Time::Seconds and pretty print
  # unless we are asking for hashlong. Need to do this until
  # we can fix the DB writing code since MSBDB uses hashlong to generate
  # the summary and can not then write the time estimates to the
  # database table.
  unless ($format eq 'hashlong') {
    $summary{timeest} = new Time::Seconds( $summary{timeest} )->pretty_print;
  }

  # obscount
  $summary{obscount} = $self->obscount;

  # Now get a long text form for the remaining number
  my $remstatus;
  if (!defined $summary{remaining}) {
    $remstatus = "Remaining count unknown";
    $summary{remaining} = "N/A";
  } elsif ($self->isRemoved) {
    $remstatus = "REMOVED from consideration";
    $summary{remaining} = "REM"; # Magic value
  } elsif ($summary{remaining} == 0) {
    $remstatus = "COMPLETE";
  } else {
    $remstatus = "$summary{remaining} remaining to be observed";
  }

  # Get the observations but retain them as objects for now
  my @obs = $self->observations;

  # For hash mode we just return what we have
  if ($format =~ /^hash/) {
    if ($format eq 'hashlong') {
      $summary{observations} = [ map { scalar($_->summary('hash')) } @obs  ];
    } else {
      $summary{observations} = \@obs;
    }
    if (wantarray) {
      return %summary;
    } else {
      return \%summary;
    }
  };

  # The other modes may require text representation of
  # the observations so generate those
  for (qw/ waveband instrument target disperser coordstype pol type /) {
    # If we have the method in this class call it
    if ($self->can($_)) {
      $summary{$_} = $self->$_;
    } else {
      # we dont know how to do this so ask the objects
      $summary{$_} = $self->_process_obs( $_, 1 );
    }
  }

  # Fill in some unknowns
  for (qw/ timeest priority title seeing tau cloud sky /) {
    $summary{$_} = "??" unless defined $summary{$_};
  }


  # Text summary
  if ($format eq 'textshort' ) {

    # Substr each string using the supplied widths.
    my @sub = map { 
      my $key;
      if (exists $summary{$keys[$_]} && defined $summary{$keys[$_]}) {
	$key = $summary{$keys[$_]};
      } else {
	$key = '';
      }
      substr($key,0,$width[$_])
    } 0..$#width;

    return sprintf $textformat, @sub;

  } elsif ($format eq 'textlong') {

    # Long and verbose ASCII
    my @text;
    push(@text, "\tTitle:    $summary{title} [$remstatus]");
    push(@text, "\tDuration: $summary{timeest} sec");
    push(@text, "\tPriority: $summary{priority}\tSeeing: $summary{seeing}\tTau: $summary{tau}");

    push(@text, "\tObservations:");

    # Now go through the observations
    my $obscount = 0;
    for my $obs (@obs) {
      $obscount++;
      my $string = "\t $obscount - ";
      $string .= "Inst:".$obs->instrument if $obs->instrument;
      $string .= "Target:".$obs->target if $obs->target;
      $string .= "Coords:".$obs->coords if $obs->coords;
      $string .= "Waveband:".$obs->waveband if $obs->waveband;
      push(@text, $string );
    }

    # Return a list or a string
    if (wantarray) {
      return @text;
    } else {
      return join("\n", @text) . "\n";
    }

  } elsif ($format =~ /^html/) {

    # Fix up HTML escapes
    for (qw/ title tau seeing /) {
      my $string = $summary{$_};
      # Should use real HTML escape class from CPAN
      $string =~ s/</\&lt\;/g;
      $string =~ s/>/\&gt\;/g;
      $string =~ s/\"/\&quot\;/g;

      $summary{$_} = $string;
    }


    my @text;
    push(@text, "<h3>$summary{title} (<em>$remstatus</em>)</h3>");

    push(@text, "<TABLE border='0'>");
    push(@text, "<tr><td>Duration:</td><td><b>$summary{timeest} sec</b></td>");
    push(@text, "<td>Priority:</td><td><b>$summary{priority}</b></td></tr>");
    push(@text, "<tr><td>Seeing:</td><td><b>$summary{seeing}</b></td>");
    push(@text, "<td>Tau:</td><td><b>$summary{tau}</b></td></tr>");
    push(@text, "</TABLE>");

    push(@text,"<TABLE  border='1'>");
    push(@text,"<TR bgcolor='#7979aa'>");
    push(@text,"<td>#</td><TD>Instrument</td><td>Target</td><td>Coords</td><td>Waveband</td></tr>");

    # Now go through the observations
    my $obscount = 0;
    for my $obs (@obs) {
      $obscount++;
      push(@text,
	   "<TR bgcolor='#7979aa'>","<td>$obscount</td>",
	   map { "<td>" . $obs->$_() . "</td>" 
	       } (qw/ instrument target coords waveband/));
    }

    push(@text, "</TABLE>");

    # Add the 'add comment' button
    if ($format eq 'htmlcgi') {
      push(@text, "<br><form method='post' action='/cgi-bin/fbmsb.pl' enctype='application/x-www-form-urlencoded'>");
      push(@text, "<input type='hidden' name='checksum' value=\'$summary{checksum}\' /><input type='hidden' name='projectid' value=\'$summary{projectid}\' /><input type='hidden' name='show_output' value='1' /><input type='submit' name='Add Comment' value='Add Comment' /></form>");
    }

    # Return a list or a string
    if (wantarray) {
      return @text;
    } else {
      return join("\n", @text) . "\n";
    }

  } elsif ($format =~ /^xml/) {

    # First the MSB things that are not dependent on
    # observations [this may include some information
    # summaries such as waveband and target]

    # Add ha, airmass and ra
    for my $method (qw/ ha airmass ra dec az /) {
      $summary{$method} = $self->$method();
    }

    # XML version
    my $xml = "<SpMSBSummary ";
    $xml .= "id=\"$summary{msbid}\"" 
      if exists $summary{msbid} and defined $summary{msbid};
    $xml .= ">\n";

    # force key order
    for my $key ($self->getResultColumns($summary{telescope})) {
      # Special case the summary and ID keys
      next if $key eq "summary";
      next if $key =~ /^_/;
      next unless defined $summary{$key};

      # Allow OMP::Range objects to stringify in the summary
      if (ref($summary{$key})) {
	next unless UNIVERSAL::isa( $summary{$key}, "OMP::Range");

	# Now we know we have to escape the > and < and &
	$summary{$key} = OMP::General::escape_entity( $summary{$key}."" );
      }

      # Currently Matt needs the msbid to be included
      # in the XML elements as well as an attribute
      # next if $key eq "msbid";

      # Create XML segment
      $xml .= "  <$key>$summary{$key}</$key>\n";
    }

    # Now add in the observations if we are doing the long version
    if ($format !~ /short/) {
      for (@obs) {
	$xml .= '    '.$_->summary("xml");
      }
    }

    # And the comments
    if ($format !~ /short/) {
      for ($self->comments) {
	$xml .= '     '.$_->summary('xml');
      }
    }

    $xml .= "</SpMSBSummary>\n";

    return $xml;



  } else {
    throw OMP::Error::BadArgs("Unknown output format: $format\n");
  }




}

=item B<stringify>

Convert the object to a string. Equivalent to calling the
C<summary()> method with a value of "textlong".

=cut

sub stringify {
  my $self = shift;
  my $string = $self->summary("textlong") ."\n";
  return $string;
}

=back

=begin __INTERNAL__

=head2 Internal Methods

=over 4

=item B<_process_obs>

For each observation, run the specified method and either return the
results as a list or join them together as a single delimited string.

  @wavebands = $msb->_process_obs( "waveband" );
  $wavebands = $msb->_process_obs( "waveband" );

In some cases it is desirable to remove duplicated entries. An optional
second argument can be used to specify that repeated entries are
removed from the array/string. For example if the instruments used
by the MSB are listed as "IRCAM", "CGS4" and "IRCAM", with compression
turned on this method will return just "IRCAM" and "CGS4".

  @wavebands = $msb->_process_obs( "waveband", 1 );
  $wavebands = $msb->_process_obs( "waveband", 1 );

If the method is "pol" the return value in scalar context is
treated as the OR of all the booleans. (ie pol is true if
any one of the observations uses the polarimeter).

=cut

sub _process_obs {
  my $self = shift;
  my $method = shift;
  my $compress = shift;

  # Loop through each observation running the method
  my @results = map { $_->$method() }
    grep { $_->can($method) }
      $self->observations;

  # Compress if required
  @results = $self->_compress_array( @results )
    if $compress;

  # Return string or array
  if (wantarray) {
    return @results;
  } else {
    if ($method eq 'pol') {
      my $count = grep { $_ } @results;
      return ( $count ? 1 : 0 );
    } else {
      return join("/", @results);
    }
  }
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

=item B<_process_coords>

For each observation, retrieve the coordinate object if present.  If
the observation is not a calibration frame, run the callback and store
the result in an array. If it is a calibration store "CAL" in the
array.  Return the array when complete

The callback is passed the calibration object.

  @ha = $msb->_process_coords( sub { my $c = shift; return $c->ha} );

If any type other than CAL exists the CAL is removed in order to
give more space to the more important information.

=cut

sub _process_coords {
  my $self = shift;
  my $cb = shift;
  my @results;
  for my $obs ($self->observations ) {
    my $coords = $obs->coords;
    next unless $coords;
    my $type = $coords->type;
    if ($type ne "CAL") {
      push(@results, $cb->($coords));
    } else {
      push(@results, "CAL");
    }
  }

  # remove CAL if we have more than one result
  if (scalar(@results) > 1 ) {
    # look for CAL
    @results = grep { $_ !~ /^CAL$/ } @results;
  }

  @results = $self->_compress_array( @results );
  return @results;
}

=back

=end __INTERNAL__

=head2 Class Methods

=over 4

=item B<getResultColumns>

Returns the data columns (ie XML element names for
XML summary) that are of interest for a particular telescope.
Returns a list in the order that they should be displayed.

 @columns = OMP::Info::MSB->getResultsColumns( $telescope );

Accepts a telescope name as argument. Default columns are returned
if the telescope can not be determined.

=cut

sub getResultColumns {
  my $class = shift;
  my $tel = shift;
  $tel = '' unless $tel;
  $tel = uc($tel);

  # The order must be forced
  my @order;
  if ($tel eq 'JCMT') {
    @order = qw/ projectid priority schedpri completion instrument waveband title target
                 ra dec coordstype ha az airmass tau pol type
	         timeest remaining obscount
                 checksum msbid /;
  } elsif ($tel eq 'UKIRT') {
    @order = qw/ projectid priority schedpri completion instrument waveband title target
		 ra dec coordstype ha airmass tau seeing cloud moon sky pol type
		 timeest remaining obscount disperser
                 checksum msbid /;
  } else {
    # Generic order
    @order = qw/ projectid priority schedpri completion instrument waveband title target
                 ra dec coordstype ha airmass tau seeing pol type
	         timeest remaining obscount
                 checksum msbid /;
  }

  return @order;
}

=item B<getTypeColumns>

Retrieves an array of data types associated with each column
returned using an XML summary format. The order matches the
order returned by C<getResultColumns>

  @types = OMP::Info::MSB->getTypeColumns( $tel );

Uses a telescope name to control the column information.

=cut

# best to use a single data structure for this
my %coltypes = (
		schedpri => 'Float',
		remaining => 'Integer',
		projectid => 'String',
		priority => 'Float',
		instrument => 'String',
		waveband => 'String',
		title => 'String',
		target => 'String',
		ra => 'String',
		ha => 'String',
		dec => 'String',
                az => 'String',
                el => 'String',
		airmass => 'String',
		pol => 'Boolean',  # Boolean?
		type => 'String',
		coordstype => 'String',
		timeest => 'String',  # can keep this as hours?
		obscount => 'Integer',
		checksum => 'String',
		msbid => 'Integer',
		moon => 'String',
		tau => 'String',
		cloud => 'String',
		sky => 'String',
		seeing => 'String',
		disperser => 'String',
		completion => 'Float',
	       );

sub getTypeColumns {
  my $class = shift;
  my $tel = shift;
  $tel = '' unless $tel;
  $tel = uc($tel);

  my @order = $class->getResultColumns($tel);

  my @types;
  for my $col (@order) {
    if (exists $coltypes{$col}) {
      push(@types, $coltypes{$col});
    } else {
      throw OMP::Error::FatalError("Error determining type of column $col");
    }
  }
  return @types;

}

=back

=head1 SEE ALSO

L<OMP::Info::Obs>

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>,
Brad Cavanagh E<lt>b.cavanagh@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001-2005 Particle Physics and Astronomy Research Council.
Copyright (C) 2007 Science and Technology Facilities Council.
All Rights Reserved.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful,but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc., 59 Temple
Place,Suite 330, Boston, MA  02111-1307, USA

=cut

1;
