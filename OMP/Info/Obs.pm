package OMP::Info::Obs;

=head1 NAME

OMP::Info::Obs - Observation information

=head1 SYNOPSIS

  use OMP::Info::Obs;

  $obs = new OMP::Info::Obs( %hash );

  $checksum = $obs->checksum;
  $projectid = $obs->projectid;

  @comments = $obs->comments;

  $xml = $obs->summary('xml');
  $html = $obs->summary('html');
  $text = "$obs";

=head1 DESCRIPTION

A compact way of handling information associated with an
Observation. This includes possible comments and information on
component observations.

=cut

use 5.006;
use strict;
use warnings;
use Carp;
use OMP::Range;
use OMP::General;
use OMP::Error qw/ :try /;
use Astro::FITS::Header::NDF;
use Astro::FITS::HdrTrans;
use Astro::WaveBand;
use Astro::Coords;
use Time::Piece;

use base qw/ OMP::Info::Base /;

our $VERSION = (qw$Revision$)[1];

use overload '""' => "stringify";

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>


=cut

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;

  my $obs = $class->SUPER::new( @_ );

  # if we have fits but nothing else
  # translate the fits header to generic
  my %args = @_;
  # count keys
  if ( ( ( exists $args{fits} ) || ( exists $args{hdrhash} ) ) && scalar( keys %args ) < 2) {
    $obs->_populate();
  }

  return $obs;
}


=item B<readfile>

Creates an C<OMP::Info::Obs> object from a given filename.

  $o = readfile OMP::Info::Obs( $filename, $instrument );

If the constructor is unable to read the file, undef will be returned.

=cut

sub readfile {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $filename = shift;
  my $instrument = shift;

  my $FITS_header;
  my $obs;

  try {
    $FITS_header = new Astro::FITS::Header::NDF( File => $filename );
    $obs = $class->new( fits => $FITS_header );
    $obs->filename( $filename );
  }
  catch Error with {
    my $Error = shift;
    print "Error in Info::Obs::readfile: " . $Error->{'-text'} . "\n";
  };
  return $obs;
}

=back

=begin __PRIVATE__

=head2 Create Accessor Methods

Create the accessor methods from a signature of their contents.

=cut

__PACKAGE__->CreateAccessors( projectid => '$',
                              checksum => '$',
                              waveband => 'Astro::WaveBand',
                              instrument => '$',
                              disperser => '$',
                              coords => 'Astro::Coords',
                              target => '$',
                              pol => '$',
                              timeest => '$',
                              duration => '$',
                              startobs => 'Time::Piece',
                              endobs => 'Time::Piece',
                              type => '$',
                              _fits => 'Astro::FITS::Header',
                              _hdrhash => '%',
                              comments => '@OMP::Info::Comment',
                              telescope => '$',
                              runnr => '$',
                              utdate => '$',
                              object => '$',
                              mode => '$',
                              speed => '$',
                              airmass => '$',
                              rows => '$',
                              columns => '$',
                              drrecipe => '$',
                              group => '$',
                              standard => '$',
                              slitname => '$',
                              slitangle => '$',
                              raoff => '$',
                              decoff => '$',
                              grating => '$',
                              order => '$',
                              tau => '$',
                              seeing => '$',
                              bolometers => '@',
                              velocity => '$',
                              systemvelocity => '$',
                              nexp => '$',
                              filename => '$',
                              isScience => '$',
                              isSciCal => '$',
                              isGenCal => '$',
                            );
#'

=end __PRIVATE__

=head2 Accessor Methods

Scalar accessors:

=over 4

=item B<projectid>

=item B<checksum>

=item B<instrument>

=item B<timeest>

=item B<target>

=item B<disperser>

=item B<type>

=item B<filename>

=item B<isScience>

=item B<isSciCal>

=item B<isGenCal>

[Imaging or Spectroscopy]

=item B<pol>

=back

Accessors requiring/returning objects:

=over 4

=item B<waveband>

[Astro::WaveBand]

=item B<coords>

[Astro::Coords]

=back

Hash accessors:

=over 4

=item B<fits>

=back

Array Accessors

=over 4

=item B<comments>

=back

=cut

sub fits {
  my $self = shift;
  if( @_ ) {
    $self->_fits( @_ );
  }

  my $fits = $self->_fits;
  if( ! defined( $fits ) ) {
    my $hdrhash = $self->hdrhash;
    if( defined( $hdrhash ) ) {

      my @items = map { new Astro::FITS::Header::Item( Keyword => $_,
                                                       Value => $hdrhash->{$_}
                                                     ) } keys (%{$hdrhash});

      # Create the Header object.
      $fits = new Astro::FITS::Header( Cards => \@items );

      $self->_fits( $fits );

    }
  }
  return $fits;
}

sub hdrhash {
  my $self = shift;
  if( @_ ) {
    $self->_hdrhash( @_ );
  }

  my $hdr = $self->_hdrhash;
  if( ! defined( $hdr ) || scalar keys %$hdr == 0) {
    my $fits = $self->fits;
    if( defined( $fits ) ) {
      my $FITS_header = $self->fits;
      tie my %header, ref($FITS_header), $FITS_header;

      $self->_hdrhash( \%header );
    }
  }
  return $hdr;
}

=head2 General Methods

=over 4

=item B<summary>

Summarize the object in a variety of formats.

  $summary = $obs->summary( 'xml' );

If called in a list context default result is 'hash'. In scalar
context default result if 'xml'.

Allowed formats are:

  'xml' - XML summary of the main observation parameters
  'hash' - hash representation of main obs. params.
  'html'
  'text'

XML is returned looking something like:

  <SpObsSummary>
    <instrument>CGS4</instrument>
    <waveband>2.2</waveband>
    ...
  </SpObsSummary>

=cut

sub summary {
  my $self = shift;

  # Calculate default formatting
  my $format = (wantarray() ? 'hash' : 'xml');

  # Read the actual value
  $format = lc(shift);

  # Build up the hash
  my %summary;
  for (qw/ waveband instrument disperser coords target pol timeest
       type telescope/) {
    $summary{$_} = $self->$_();
  }

  if ($format eq 'hash') {
    if (wantarray) {
      return %summary;
    } else {
      return \%summary;
    }
  } elsif ($format eq 'text') {
    # Simple  - needs more work
    return join "\n", map { "$_: $summary{$_}" } 
      grep { defined $_ and defined $summary{$_} } keys %summary;
  } elsif ($format eq 'xml') {

    my $xml = "<SpObsSummary>\n";

    for my $key ( keys %summary ) {
      next if $key =~ /^_/;
      next unless defined $summary{$key};

      # Create XML segment
      $xml .= "<$key>$summary{$key}</$key>\n";

    }
    $xml .= "</SpObsSummary>\n";
    return $xml;

  } else {
    throw OMP::Error::BadArgs("Format $format not yet implemented");
  }


}

=item B<stringify>

String representation of the object. Called automatically on
stringification. Effectively a call to C<summary> method
with format "text".

=cut

sub stringify {
  my $self = shift;
  return $self->summary("text");
}

=item B<nightlog>

Returns a hash representation of data contained in an C<Info::Obs>
object that can be used for summary purposes.

  %nightlog = $obs->nightlog;

An optional parameter may be supplied. This parameter is a string
whose values are either 'short' or 'long', which will cause the
method to return either a small amount of information (i.e. for a
brief summary) or the full information contained in the object. The
default is 'short'.

'long' information is not currently implemented.

The returned hash is of the form {header_name => value}, with an additional
{_ORDER => @ORDER_ARRAY} key-value pair to indicate the order in
which the values should be displayed, a {_STRING => string} key-value pair
which gives a one-line summary of the observation, and a
{_STRING_HEADER => string} key-value pair which gives the header
for the corresponding _STRING value.

=cut

sub nightlog {
  my $self = shift;
  my $display = shift || 'short';

  my %return;

  # Confirm that the $display variable is either 'short' or 'long'
  if($display !~ /long|short/i) {
    $display = 'short';
  }
  $display = lc($display);

  # We're going to accomplish this through a large if-then-else block,
  # keyed on the instrument given in the Info::Obs object. If an
  # instrument isn't given, then we're stuffed, so throw an error.
  if(!($self->instrument)) {
    throw OMP::Error::BadArgs("Info::Obs object did not supply an instrument.");
  }

  my $instrument = $self->instrument;

  if($instrument =~ /scuba/i) {
    $return{'Run'} = $self->runnr;
    $return{'UT time'} = defined($self->startobs) ? $self->startobs->hms : '';
    $return{'Obsmode'} = $self->mode;
    $return{'Project ID'} = $self->projectid;
    $return{'Object'} = $self->target;
    $return{'Tau225'} = sprintf( "%.2f", $self->tau);
    $return{'Seeing'} = $self->seeing;
    $return{'Filter'} = defined($self->waveband) ? $self->waveband->filter : '';
    $return{'Bolometers'} = $self->bolometers;
    $return{'_ORDER'} = [ "Run", "UT time", "Obsmode", "Project ID", "Object",
                          "Tau225", "Seeing", "Filter", "Bolometers" ];
    $return{'_STRING_HEADER'} = "Run  UT time   Obsmode    Project ID  Object      Tau225  Seeing  Filter     Bolometers";
    $return{'_STRING'} = sprintf("%-3u  %8s  %-10.10s %-11s %-11.11s %-6.3f  %-6.3f  %-10s %-15s", $return{'Run'}, $return{'UT time'}, $return{'Obsmode'}, $return{'Project ID'}, $return{'Object'}, $return{'Tau225'}, $return{'Seeing'}, $return{'Filter'}, $return{'Bolometers'}[0]);
    foreach my $comment ($self->comments) {
      if(defined($comment)) {
        $return{'_STRING'} .= sprintf("\n %19s UT / %-.12s: %-50s",$comment->{Date}->ymd . ' ' . $comment->{Date}->hms, $comment->{Author}->userid, $comment->{Text});
      }
    }
  } elsif($instrument =~ /ircam/i) {
    $return{'Observation'} = $self->runnr;
    $return{'Group'} = $self->group;
    $return{'Object'} = $self->target;
    $return{'Obstype'} = $self->type;
    $return{'UT start'} = defined($self->startobs) ? $self->startobs->hms : '';
    $return{'Exposure time'} = sprintf( "%.1f", $self->duration );
    $return{'Number of exposures'} = $self->nexp;
    $return{'Mode'} = $self->mode;
    $return{'Speed'} = $self->speed;
    $return{'Filter'} = defined($self->waveband) ? $self->waveband->filter : '';
    $return{'Airmass'} = sprintf( "%.2f", $self->airmass );
    $return{'Columns'} = $self->columns;
    $return{'Rows'} = $self->rows;
    $return{'RA'} = defined($self->coords) ? $self->coords->ra( format => 's' ) : '';
    $return{'DEC'} = defined($self->coords) ? $self->coords->dec( format => 's' ) : '';
    $return{'Equinox'} = defined($self->coords) ? $self->coords->type : '';
    $return{'RA Offset'} = $self->raoff;
    $return{'Dec Offset'} = $self->decoff;
    $return{'DR Recipe'} = $self->drrecipe;
    $return{'Project ID'} = $self->projectid;
    $return{'_ORDER'} = [ "Observation", "Group", "Project ID", "Object", "Obstype",
                          "UT start", "Exposure time", "Number of exposures",
                          "Filter", "Airmass", "RA", "DEC", "Equinox",
                          "RA Offset", "Dec Offset", "DR Recipe" ];
  } elsif($instrument =~ /cgs4/i) {
    $return{'Observation'} = $self->runnr;
    $return{'Group'} = $self->group;
    $return{'Object'} = $self->target;
    $return{'Standard'} = $self->standard;
    $return{'Observation type'} = $self->type;
    $return{'Slit'} = $self->slitname;
    $return{'Position Angle'} = $self->slitangle;
    $return{'RA offset'} = sprintf( "%.3f", $self->raoff);
    $return{'Dec offset'} = sprintf( "%.3f", $self->decoff);
    $return{'UT time'} = defined($self->startobs) ? $self->startobs->hms : '';
    $return{'Airmass'} = sprintf( "%.2f", $self->airmass);
    $return{'Exposure time'} = sprintf( "%.1f",$self->duration );
    $return{'Number of exposures'} = $self->nexp;
    $return{'Grating'} = $self->grating;
    $return{'Order'} = $self->order;
    $return{'Wavelength'} = defined($self->waveband) ? $self->waveband->wavelength : '';
    $return{'DR Recipe'} = $self->drrecipe;
    $return{'Project ID'} = $self->projectid;
    $return{'_ORDER'} = [ "Observation", "Group", "Project ID", "Object", "Standard",
                          "Observation type", "Slit", "Position Angle",
                          "RA offset", "Dec offset", "UT time", "Airmass",
                          "Exposure time", "Grating",
                          "Order", "Wavelength", "DR Recipe" ];
  } elsif($instrument =~ /michelle/i) {
    $return{'Observation'} = $self->runnr;
    $return{'Group'} = $self->group;
    $return{'Object'} = $self->target;
    $return{'Observation type'} = $self->type;
    $return{'UT start'} = defined($self->startobs) ? $self->startobs->hms : '';
    $return{'Exposure time'} = sprintf("%.1f",$self->duration);
    $return{'Number of exposures'} = $self->nexp;
    $return{'Mode'} = $self->mode;
    $return{'Speed'} = $self->speed;
    $return{'Filter'} = defined($self->waveband) ? $self->waveband->filter : '';
    $return{'Airmass'} = sprintf("%.2f",$self->airmass);
    $return{'Columns'} = $self->columns;
    $return{'Rows'} = $self->rows;
    $return{'RA'} = defined($self->coords) ? $self->coords->ra( format => 's' ) : '';
    $return{'DEC'} = defined($self->coords) ? $self->coords->dec( format => 's' ) : '';
    $return{'Equinox'} = defined($self->coords) ? $self->coords->type : '';
    $return{'RA offset'} = $self->raoff;
    $return{'Dec offset'} = $self->decoff;
    $return{'DR Recipe'} = $self->drrecipe;
    $return{'Standard'} = $self->standard;
    $return{'Slit'} = $self->slitname;
    $return{'Position Angle'} = $self->slitangle;
    $return{'Grating'} = $self->grating;
    $return{'Order'} = $self->order;
    $return{'Wavelength'} = defined($self->waveband) ? $self->waveband->wavelength : '';
    $return{'Project ID'} = $self->projectid;
    $return{'_ORDER'} = [ "Observation", "Group", "Project ID", "Object", "Observation type",
                          "UT start", "Exposure time",
                          "Filter", "Airmass", "RA", "DEC", "Equinox", "RA offset", "Dec Offset", 
                          "Slit", "Position Angle", "Grating",
                          "Wavelength", "DR Recipe" ];
  } elsif($instrument =~ /ufti/i) {
    $return{'Observation'} = $self->runnr;
    $return{'Group'} = $self->group;
    $return{'Object'} = $self->target;
    $return{'Observation type'} = $self->type;
    $return{'UT start'} = defined($self->startobs) ? $self->startobs->hms : '';
    $return{'Exposure time'} = sprintf("%.1f",$self->duration);
    $return{'Number of exposures'} = $self->nexp;
    $return{'Mode'} = $self->mode;
    $return{'Speed'} = $self->speed;
    $return{'Filter'} = defined($self->waveband) ? $self->waveband->filter : '';
    $return{'Airmass'} = sprintf("%.2f",$self->airmass);
    $return{'Columns'} = $self->columns;
    $return{'Rows'} = $self->rows;
    $return{'RA'} = defined($self->coords) ? $self->coords->ra( format => 's' ) : '';
    $return{'DEC'} = defined($self->coords) ? $self->coords->dec( format => 's' ) : '';
    $return{'Equinox'} = defined($self->coords) ? $self->coords->type : '';
    $return{'RA Offset'} = $self->raoff;
    $return{'Dec Offset'} = $self->decoff;
    $return{'DR Recipe'} = $self->drrecipe;
    $return{'Project ID'} = $self->projectid;
    $return{'_ORDER'} = [ "Observation", "Group", "Project ID", "Object",
                          "Observation type", "UT start", "Exposure time",
                          "Filter", "Airmass", "RA", "DEC", "Equinox",
                          "RA Offset", "Dec Offset", "DR Recipe" ];
  } elsif( $instrument =~ /uist/i ) {
    $return{'Observation'} = $self->runnr;
    $return{'Group'} = $self->group;
    $return{'Object'} = $self->target;
    $return{'Observation type'} = $self->type;
    $return{'UT start'} = defined($self->startobs) ? $self->startobs->hms : '';
    $return{'Exposure time'} = sprintf("%.1f", $self->duration );
    $return{'Filter'} = defined($self->waveband) ? $self->waveband->filter : '';
    $return{'Airmass'} = $self->airmass;
    $return{'RA'} = defined($self->coords) ? $self->coords->ra( format => 's' ) : '';
    $return{'DEC'} = defined($self->coords) ? $self->coords->dec( format => 's' ) : '';
    $return{'Equinox'} = defined($self->coords) ? $self->coords->type : '';
    $return{'RA Offset'} = $self->raoff;
    $return{'Dec Offset'} = $self->decoff;
    $return{'DR Recipe'} = $self->drrecipe;
    $return{'Project ID'} = $self->projectid;
    $return{'_ORDER'} = [ "Observation", "Group", "Project ID", "Object",
                          "Observation type", "UT start", "Exposure time",
                          "Airmass", "Filter", "RA", "DEC", "Equinox",
                          "RA Offset", "Dec Offset", "DR Recipe", ];
  }
  return %return;

}

=back

=head2 Private Methods

=over 4

=item B<_populate>

Given an C<OMP::Info::Obs> object that has the 'fits' accessor, populate
the remainder of the accessors.

  $obs->_populate();

Note that if other accessors exist prior to running this method, they will
be overwritten.

=cut

sub _populate {
  my $self = shift;

  my $header = $self->hdrhash;
  my %generic_header = Astro::FITS::HdrTrans::translate_from_FITS($header);

  $self->projectid( $generic_header{PROJECT} );
  $self->checksum( $generic_header{MSBID} );
  $self->instrument( $generic_header{INSTRUMENT} );
  $self->duration( $generic_header{EXPOSURE_TIME} );
  $self->disperser( $generic_header{GRATING_NAME} );
  $self->type( $generic_header{OBSERVATION_TYPE} );
  $self->telescope( $generic_header{TELESCOPE} );
  $self->filename( $generic_header{FILENAME} );

  # Build the Astro::WaveBand object
  if ( length( $generic_header{WAVELENGTH} . "" ) != 0 ) {
    $self->waveband( new Astro::WaveBand( Wavelength => $generic_header{WAVELENGTH},
                                           Instrument => $generic_header{INSTRUMENT} ) );
  } elsif ( length( $generic_header{FILTER} . "" ) != 0 ) {
    $self->waveband( new Astro::WaveBand( Filter     => $generic_header{FILTER},
                                           Instrument => $generic_header{INSTRUMENT} ) );
  }

  # Build the Time::Piece startobs and endobs objects
  if(length($generic_header{UTSTART} . "") != 0) {
    my $startobs = OMP::General->parse_date($generic_header{UTSTART});
    $self->startobs( $startobs );
  }
  if(length($generic_header{UTEND} . "") != 0) {
    my $endobs = OMP::General->parse_date($generic_header{UTEND});
    $self->endobs( $endobs );
  }

  # Build the Astro::Coords object

  # If we're SCUBA, we can use SCUBA::ODF::getTarget to make the
  # Astro::Coords object for us. Hooray!

  if( $generic_header{'INSTRUMENT'} =~ /scuba/i ) {
    require SCUBA::ODF;
    my $odfobject = new SCUBA::ODF( HdrHash => $header );

    if(defined($odfobject->getTarget)) {
      $self->coords( $odfobject->getTarget );
    };

    # Let's get the real object name as well.
    if(defined($odfobject->getTargetName)) {
      $self->target( $odfobject->getTargetName );
    };

    # Set science/scical/gencal.
    $self->isScience( $odfobject->isScienceObs );
    $self->isSciCal( $odfobject->iscal );
    $self->isGenCal( $odfobject->isGenericCal );

    # Set the observation mode.
    $self->mode( $odfobject->mode_summary );

  } else {

    # Default the equinox to J2000, but if it's 1950 change to B1950.
    # Anything else will be converted to J2000.
    my $type = "J2000";
    if ( $generic_header{EQUINOX} =~ /1950/ ) {
      $type = "B1950";
    }
    if ( defined ( $generic_header{COORDINATE_TYPE} ) ) {
      if ( $generic_header{COORDINATE_TYPE} eq 'galactic' ) {
        $self->coords( new Astro::Coords( lat   => $generic_header{Y_BASE},
                                           long  => $generic_header{X_BASE},
                                           type  => $generic_header{COORDINATE_TYPE},
                                           units => $generic_header{COORDINATE_UNITS}
                                         ) );
      } elsif ( ( $generic_header{COORDINATE_TYPE} eq 'J2000' ) ||
                ( $generic_header{COORDINATE_TYPE} eq 'B1950' ) ) {
        $self->coords( new Astro::Coords( ra    => $generic_header{X_BASE},
                                           dec   => $generic_header{Y_BASE},
                                           type  => $generic_header{COORDINATE_TYPE},
                                           units => $generic_header{COORDINATE_UNITS}
                                         ) );
      }
    }

    # Set the target name.
    $self->target( $generic_header{OBJECT} );

    # Set science/scical/gencal.
    $self->isScience( 1 );
    $self->isSciCal( 0 );
    $self->isGenCal( 0 );

    # Set the observation mode.
    $self->mode( $generic_header{OBSERVATION_MODE} );
  }

  $self->runnr( $generic_header{OBSERVATION_NUMBER} );
  $self->utdate( $generic_header{UTDATE} );
  $self->speed( $generic_header{SPEED_GAIN} );
  $self->airmass( $generic_header{AIRMASS_START} );
  $self->rows( $generic_header{Y_DIM} );
  $self->columns( $generic_header{X_DIM} );
  $self->drrecipe( $generic_header{DR_RECIPE} );
  $self->group( $generic_header{DR_GROUP} );
  $self->standard( $generic_header{STANDARD} );
  $self->slitname( $generic_header{SLIT_NAME} );
  $self->slitangle( $generic_header{SLIT_ANGLE} );
  $self->raoff( $generic_header{X_OFFSET} );
  $self->decoff( $generic_header{Y_OFFSET} );
  $self->grating( $generic_header{GRATING_NAME} );
  $self->order( $generic_header{GRATING_ORDER} );
  $self->tau( $generic_header{TAU} );
  $self->seeing( defined( $generic_header{SEEING} ?
                           sprintf("%.1f",$generic_header{SEEING}) :
                           "" ) );
  $self->bolometers( $generic_header{BOLOMETERS} );
  $self->velocity( $generic_header{VELOCITY} );
  $self->systemvelocity( $generic_header{SYSTEM_VELOCITY} );
  $self->nexp( $generic_header{NUMBER_OF_EXPOSURES} );

}

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>
Brad Cavanagh E<lt>b.cavanagh@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
