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
use OMP::Constants qw/ :msb /;

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
                              tau => 'OMP::Range', 
                              checksum => '$',
                              seeing => 'OMP::Range',
                              priority => '$',
                              moon =>  '$',
                              timeest => '$',
                              title => '$',
                              datemin => 'Time::Piece',
                              datemax => 'Time::Piece',
                              telescope => '$',
                              cloud => '$',
                              observations => '@OMP::Info::Obs',
 	                      wavebands => '$',
 	                      targets => '$',
 	                      instruments => '$',
			      coordstypes => '$',
                              remaining => '$',
                              comments => '@OMP::Info::Comment'
                             );
#' for the emacs color coding 

=end __PRIVATE__

=head2 Accessor Methods

Scalar accessors:

=over 4

=item B<projectid>

=item B<checksum>

=item B<priority>

=item B<timeest>

=item B<title>

=back

Accessors requiring/returning C<OMP::Range> objects:

=over 4

=item B<tau>

=item B<seeing>

=item B<moon>

=item B<cloud>

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
 'hashshort' - returns hash representation of MSB where Observations
               are retained as objects
 'hashlong'  - hash rep. of MSB where Observations are array of hashes

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

=cut

sub summary {
  my $self = shift;

  # Calculate default formatting
  my $format = (wantarray() ? 'hash' : 'xml');

  # Read the actual value
  $format = lc(shift);

  # Field widths for short text summary. Do this early
  # so that we can process textshorthdr without querying
  # the object
  my @keys = qw/projectid title remaining obscount tau seeing
    pol type instrument waveband target coordstype timeest/;

  # Field widths %s does not substr a string - real pain
  # Therefore need to substr ourselves
  my @width = qw/ 11 10 3 3 8 8 3 3 20 20 20 6 5 /;
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
  for (qw/ projectid checksum tau seeing priority moon timeest title
       datemin datemax telescope cloud remaining /) {
    $summary{$_} = $self->$_();
  }

  # Now get a long text form for the remaining number
  my $remstatus;
  if (!defined $summary{remaining}) {
    $remstatus = "Remaining count unknown";
    $summary{remaining} = "N/A";
  } elsif ($summary{remaining} == OMP__MSB_REMOVED) {
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
      push(@text, "\t $obscount - Inst:".$obs->instrument
	   . "\tTarget: ".$obs->target
	   . "\tCoords: ".$obs->coords
	   . "\tWaveband: ". $obs->waveband
	  );
    }

    # Return a list or a string
    if (wantarray) {
      return @text;
    } else {
      return join("\n", @text) . "\n";
    }

  } elsif ($format eq 'html') {

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

    # XML version
    my $xml = "<SpMSBSummary ";
    $xml .= "id=\"$summary{msbid}\"" if exists $summary{msbid};
    $xml .= ">\n";

    for my $key ( keys %summary ) {
      # Special case the summary and ID keys
      next if $key eq "summary";
      next if $key =~ /^_/;
      next unless defined $summary{$key};

      # This will skip OMP::Range objects!
      next if ref($summary{$key});

      # Currently Matt needs the msbid to be included
      # in the XML elements as well as an attribute
      # next if $key eq "msbid";

      # Create XML segment
      $xml .= "<$key>$summary{$key}</$key>\n";
    }

    # Now add in the observations
    for (@obs) {
      $xml .= $_->summary("xml");
    }

    # And the comments
    for ($self->comments) {
      $xml .= $_->summary('xml');
    }


    $xml .= "</SpMSBSummary>\n";

    return $xml;



  }




}

=item B<stringify>

=cut

sub stringify {
  my $self = shift;
  return "NOT YET IMPLEMENTED";
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
    return join("/", @results);
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

=back

=end __INTERNAL__

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
