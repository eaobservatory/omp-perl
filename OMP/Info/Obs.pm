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
use OMP::Constants qw/ :obs /;
use OMP::Error qw/ :try /;

use Astro::FITS::Header::NDF;
use Astro::FITS::Header::GSD;
use Astro::FITS::HdrTrans;
use Astro::WaveBand;
use Astro::Coords;
use Time::Piece;
use Text::Wrap qw/ $columns &wrap /;

# Text wrap column size.
$Text::Wrap::columns = 72;

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
    if( $filename =~ /sdf$/ ) {
      $FITS_header = new Astro::FITS::Header::NDF( File => $filename );
    } elsif( $filename =~ /(gsd|dat)$/ ) {
      $FITS_header = new Astro::FITS::Header::GSD( File => $filename );
    }
    $obs = $class->new( fits => $FITS_header );
    $obs->filename( $filename );
  }
  catch Error with {
    my $Error = shift;
    print "Error in Info::Obs::readfile: $Error\n";
  };
  return $obs;
}

=back

=begin __PRIVATE__

=head2 Create Accessor Methods

Create the accessor methods from a signature of their contents.

=cut

__PACKAGE__->CreateAccessors( _fits => 'Astro::FITS::Header',
                              _hdrhash => '%',

                              airmass => '$',
                              airmass_start => '$',
                              airmass_end => '$',
                              backend => '$',
                              bolometers => '@',
                              checksum => '$',
                              chopangle => '$',
                              chopsystem => '$',
                              chopthrow => '$',
                              columns => '$',
                              comments => '@OMP::Info::Comment',
                              coords => 'Astro::Coords',
                              cycle_length => '$',
                              decoff => '$',
                              disperser => '$',
                              drrecipe => '$',
                              duration => '$',
                              endobs => 'Time::Piece',
                              filename => '$',
                              grating => '$',
                              group => '$',
                              instrument => '$',
                              mode => '$',
                              nexp => '$',
                              number_of_cycles => '$',
                              object => '$',
                              order => '$',
                              pol => '$',
                              projectid => '$',
                              raoff => '$',
                              rest_frequency => '$',
                              rows => '$',
                              runnr => '$',
                              seeing => '$',
                              slitangle => '$',
                              slitname => '$',
                              speed => '$',
                              standard => '$',
                              startobs => 'Time::Piece',
                              target => '$',
                              tau => '$',
                              timeest => '$',
                              telescope => '$',
                              type => '$',
                              utdate => '$',
                              velocity => '$',
                              velsys => '$',
                              waveband => 'Astro::WaveBand',

                              isScience => '$',
                              isSciCal => '$',
                              isGenCal => '$',
                              calType  => '$',
                            );


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

=item B<calType>

A string identifying the calibration type required by this
observation. In general this string is not useful since it
it aimed at tools rather than for the user. It is used mainly
to determine time accounting.

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

sub status {
  my $self = shift;
  if( @_ ) {
    $self->{status} = shift;
    my @comments = $self->comments;
    if(defined($comments[0])) {
      $comments[0]->status( $self->{status} );
      $self->comments( \@comments );
    }
  }
  if( !exists( $self->{status} ) ) {
    # Fallback in case the accessor hasn't been used.
    # Grab the status from the comments. If no comments
    # exist, then set the status as being good.
    my @comments = $self->comments;
    if( defined( $comments[0] ) ) {
      $self->{status} = $comments[0]->status;
    } else {
      $self->{status} = OMP__OBS_GOOD;
    }
  }
  return $self->{status};
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
  '72col' - 72-column summary, with comments.

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

  } elsif( $format eq '72col' ) {
    my $obssum = sprintf("%4.4s %8.8s %8.8s %-20.20s %-36.36s\n",$self->runnr, $self->startobs->hms, $self->instrument, $self->target, $self->mode);
    my $commentsum;
    foreach my $comment ( $self->comments ) {
      if(defined($comment)) {
        my $tc = sprintf("%19s UT / %s: %s\n", $comment->date->ymd . " " . $comment->date->hms, $comment->author->name, $comment->text);
        $commentsum .= wrap(' ',' ',$tc)
      }
    }
    if (wantarray) {
      return ($obssum, $commentsum);
    } else {
      return $obssum . $commentsum;
    }
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

There may also be {_STRING_LONG} and {_STRING_HEADER_LONG} keys that give
multiple-line summaries of the observations.

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

# *** SCUBA

    $return{'Run'} = $self->runnr;
    $return{'UT time'} = defined($self->startobs) ? $self->startobs->hms : '';
    $return{'Obsmode'} = $self->mode;
    $return{'Project ID'} = $self->projectid;
    $return{'Object'} = $self->target;
    $return{'Tau225'} = sprintf( "%.2f", $self->tau);
    $return{'Seeing'} = $self->seeing;
    $return{'Filter'} = defined($self->waveband) ? $self->waveband->filter : '';
    $return{'Bolometers'} = $self->bolometers;
    $return{'RA'} = defined($self->coords) ? $self->coords->ra( format => 's' ) : '';
    $return{'Dec'} = defined($self->coords) ? $self->coords->dec( format => 's' ) : '';
    $return{'Coordinate Type'} = defined($self->coords) ? $self->coords->type : '';
    $return{'Mean Airmass'} = defined($self->airmass) ? $self->airmass : 0;
    $return{'Chop Throw'} = defined($self->chopthrow) ? $self->chopthrow : 0;
    $return{'Chop Angle'} = defined($self->chopangle) ? $self->chopangle : 0;
    $return{'Chop System'} = defined($self->chopsystem) ? $self->chopsystem : '';

    $return{'_ORDER'} = [ "Run", "UT time", "Obsmode", "Project ID", "Object",
                          "Tau225", "Seeing", "Filter", "Bolometers" ];

    $return{'_STRING_HEADER'} = "Run  UT time   Obsmode    Project ID  Object      Tau225  Seeing  Filter     Bolometers";
    $return{'_STRING'} = sprintf("%-3u  %8s  %-10.10s %-11s %-11.11s %-6.3f  %-6.3f  %-10s %-15s", $return{'Run'}, $return{'UT time'}, $return{'Obsmode'}, $return{'Project ID'}, $return{'Object'}, $return{'Tau225'}, $return{'Seeing'}, $return{'Filter'}, $return{'Bolometers'}[0]);

    $return{'_STRING_HEADER_LONG'} = "Run  UT start  Obsmode    Project ID  Object      Tau225  Seeing  Filter     Bolometers\n            RA           Dec  Coord Type  Mean AM  Chop Throw  Chop Angle  Chop Coords";
    $return{'_STRING_LONG'} = sprintf("%-3u  %8s  %-10.10s %-11s %-11.11s %-6.3f  %-6.3f  %-10s %-15s\n %13.13s %13.13s    %8.8s  %7.2f  %10.1f  %10.1f  %11.11s", $return{'Run'}, $return{'UT time'}, $return{'Obsmode'}, $return{'Project ID'}, $return{'Object'}, $return{'Tau225'}, $return{'Seeing'}, $return{'Filter'}, $return{'Bolometers'}[0], $return{'RA'}, $return{'Dec'}, $return{'Coordinate Type'}, $return{'Mean Airmass'}, $return{'Chop Throw'}, $return{'Chop Angle'}, $return{'Chop System'});

  } elsif( $instrument =~ /^(rx|mpi)/i ) {

# *** Heterodyne instruments

    $return{'Run'} = $self->runnr;
    my $utdate = $self->startobs->ymd;
    $utdate =~ s/-//g;
    $return{'UT'} = $utdate . " " . $self->startobs->hms;
    $return{'Mode'} = uc($self->mode);
    $return{'Source'} = $self->target;
    $return{'Cycle Length'} = $self->cycle_length;
    $return{'Number of Cycles'} = $self->number_of_cycles;
    $return{'Receiver'} = uc($self->instrument);
    $return{'Frequency'} = $self->rest_frequency;
    $return{'Velocity'} = $self->velocity;
    $return{'Velsys'} = $self->velsys;
    $return{'Project ID'} = $self->projectid;

    $return{'_ORDER'} = [ "Run", "Project ID", "UT", "Mode", "Source", "Cycle Length", "Number of Cycles",
                          "Receiver", "Frequency", "Velocity", "Velsys" ];

    $return{'_STRING_HEADER'} = " Run  Project           UT start      Mode      Source Sec/Cyc   Rec Freq   Vel/Velsys";
    $return{'_STRING'} = sprintf("%4s %8s  %17s %10s %10s %3d/%3d %5s  %3d %5d/%6s", $return{'Run'}, $return{'Project ID'}, $return{'UT'}, $return{'Mode'}, $return{'Source'}, $return{'Cycle Length'}, $return{'Number of Cycles'}, $return{'Receiver'}, $return{'Frequency'}, $return{'Velocity'}, $return{'Velsys'});
    $return{'_STRING_HEADER_LONG'} = $return{'_STRING_HEADER'};
    $return{'_STRING_LONG'} = $return{'_STRING'};

  } elsif($instrument =~ /(cgs4|ircam|ufti|uist|michelle)/i) {

# UKIRT instruments

    $return{'Observation'} = $self->runnr;
    $return{'Group'} = defined($self->group) ? $self->group : 0;
    $return{'Object'} = defined($self->target) ? $self->target : '';
    $return{'Observation type'} = defined($self->type) ? $self->type : '';
    $return{'RA offset'} = defined($self->raoff) ? sprintf( "%.3f", $self->raoff) : 0;
    $return{'Dec offset'} = defined($self->decoff) ? sprintf( "%.3f", $self->decoff) : 0;
    $return{'UT time'} = defined($self->startobs) ? $self->startobs->hms : '';
    $return{'Airmass'} = defined($self->airmass) ? sprintf( "%.2f", $self->airmass) : 0;
    $return{'Exposure time'} = defined($self->duration) ? sprintf( "%.1f",$self->duration ) : 0;
    $return{'DR Recipe'} = defined($self->drrecipe) ? $self->drrecipe : '';
    $return{'Project ID'} = $self->projectid;
    $return{'_ORDER'} = [ "Observation", "Group", "Project ID", "UT time", "Object",
                          "Observation type", "Exposure time", "RA offset", "Dec offset",
                          "Airmass", "DR Recipe" ];

    $return{'_STRING_HEADER'} = " Obs  Grp Project ID  UT Start         Object     Type   ExpT  RAoff DecOff    AM Recipe";
    $return{'_STRING'} = sprintf("%4d %4d %10s  %8s %14.14s %8.8s  %6.2f  %5.1f  %5.1f  %4.2f  %16s", $return{'Observation'}, $return{'Group'}, $return{'Project ID'}, $return{'UT time'}, $return{'Object'}, $return{'Observation type'}, $return{'Exposure time'}, $return{'RA offset'}, $return{'Dec offset'}, $return{'Airmass'}, $return{'DR Recipe'});

  } elsif($instrument =~ /michelle/i) {

# *** MICHELLE

    $return{'Observation'} = $self->runnr;
    $return{'Group'} = $self->group;
    $return{'Object'} = $self->target;
    $return{'Observation type'} = $self->type;
    $return{'UT start'} = defined($self->startobs) ? $self->startobs->hms : '';
    $return{'Exposure time'} = sprintf("%.1f",$self->duration);
    $return{'Number of Exposures'} = $self->nexp;
    $return{'Mode'} = $self->mode;
    $return{'Speed'} = $self->speed;
    $return{'Filter'} = (defined($self->waveband) && defined($self->waveband->filter) )
                        ? $self->waveband->filter
                        : '';
    $return{'Wavelength'} = (defined($self->waveband) && defined($self->waveband->wavelength))
                            ? $self->waveband->wavelength
                            : '';
    $return{'Airmass'} = sprintf("%.2f",$self->airmass);
    $return{'Columns'} = $self->columns;
    $return{'Rows'} = $self->rows;
    $return{'RA'} = defined($self->coords) ? $self->coords->ra( format => 's' ) : '';
    $return{'DEC'} = defined($self->coords) ? $self->coords->dec( format => 's' ) : '';
    $return{'Equinox'} = defined($self->coords) ? $self->coords->type : '';
    $return{'RA offset'} = defined($self->raoff) ? $self->raoff : 0.0;
    $return{'Dec offset'} = defined($self->decoff) ? $self->decoff : 0.0;
    $return{'DR Recipe'} = defined($self->drrecipe) ? $self->drrecipe : '';
    $return{'Standard'} = $self->standard;


    $return{'Position Angle'} = $self->slitangle;
    $return{'Grating'} = defined($self->grating) ? $self->grating : '';
    $return{'Order'} = $self->order;
    $return{'Wavelength'} = defined($self->waveband) ? $self->waveband->wavelength : '';
    $return{'Project ID'} = $self->projectid;
    $return{'_ORDER'} = [ "Observation", "Group", "Project ID", "Object", "Observation type",
                          "UT start", "Exposure time",
                          "Filter", "Airmass", "RA", "DEC", "Equinox", "RA offset", "Dec Offset",
                          "Slit", "Position Angle", "Grating",
                          "Wavelength", "DR Recipe" ];

    $return{'_STRING_HEADER'} = " Obs  Grp           Object  UT start   ExpT Nexp    Filter Grating Wvlnth     Type   AM  RAoff DecOff Recipe";
    $return{'_STRING'} = sprintf("%4u %4u %16.16s  %-8.8s %6.2f %4f  %8.8s %7.7s %6.3f %8.8s %4.2f%6.1f %6.1f %20.20s", $return{'Observation'}, $return{'Group'}, $return{'Object'}, $return{'UT start'}, $return{'Exposure time'}, $return{'Number of Exposures'}, $return{'Filter'}, $return{'Grating'}, $return{'Wavelength'}, $return{'Observation type'}, $return{'Airmass'}, $return{'RA Offset'}, $return{'Dec Offset'}, $return{'DR Recipe'});

  } elsif($instrument =~ /ufti/i) {

# *** UFTI

    $return{'Observation'} = $self->runnr;
    $return{'Group'} = defined($self->group) ? $self->group : 0;
    $return{'Object'} = $self->target;
    $return{'Observation type'} = $self->type;
    $return{'UT start'} = defined($self->startobs) ? $self->startobs->hms : '';
    $return{'Exposure time'} = sprintf("%.1f",$self->duration);
    $return{'Number of exposures'} = $self->nexp;
    $return{'Mode'} = defined($self->mode) ? $self->mode : '';
    $return{'Speed'} = $self->speed;
    $return{'Filter'} = ( defined($self->waveband) && defined($self->waveband->filter) )
                        ? $self->waveband->filter
                        : '';
    $return{'Airmass'} = sprintf("%.2f",$self->airmass);
    $return{'Columns'} = defined($self->columns) ? $self->columns : 0;
    $return{'Rows'} = defined($self->rows) ? $self->rows : 0;
    $return{'RA'} = defined($self->coords) ? $self->coords->ra( format => 's' ) : '';
    $return{'DEC'} = defined($self->coords) ? $self->coords->dec( format => 's' ) : '';
    $return{'Equinox'} = defined($self->coords) ? $self->coords->type : '';
    $return{'RA Offset'} = $self->raoff;
    $return{'Dec Offset'} = $self->decoff;
    $return{'DR Recipe'} = defined($self->drrecipe) ? $self->drrecipe : '';
    $return{'Project ID'} = $self->projectid;
    $return{'_ORDER'} = [ "Observation", "Group", "Project ID", "Object",
                          "Observation type", "UT start", "Exposure time",
                          "Filter", "Airmass", "RA", "DEC", "Equinox",
                          "RA Offset", "Dec Offset", "DR Recipe" ];
    $return{'_STRING_HEADER'} = "  Obs   UT Start           Object    Filter   ExpT  Coadds    AM  Array Size  Recipe";
#    $return{'_STRING_HEADER'} = " Obs  Grp           Object UT start   ExpT    Filter    Type    AM  RAoff DecOff Recipe";
    $return{'_STRING'} = sprintf("%5u   %-8.8s %16.16s %9.9s %6.2f    %4d  %4.2f   %9.9s %-26s",$return{'Observation'}, $return{'UT start'}, $return{'Object'}, $return{'Filter'}, $return{'Exposure time'}, $return{'Number of coadds'}, $return{'Airmass'}, $return{'Columns'} . 'x' . $return{'Rows'}, $return{'DR Recipe'});
#    $return{'_STRING'} = sprintf("%4u %4u %16.16s %-8.8s %6.2f %9.9s %7.7s  %4.2f %6.1f %6.1f %-26.26s", $return{'Observation'}, $return{'Group'}, $return{'Object'}, $return{'UT start'}, $return{'Exposure time'}, $return{'Filter'}, $return{'Observation type'}, $return{'Airmass'}, $return{'RA Offset'}, $return{'Dec Offset'}, $return{'DR Recipe'});

  } elsif( $instrument =~ /uist/i ) {

# *** UIST

    $return{'Observation'} = $self->runnr;
    $return{'Group'} = $self->group;
    $return{'Object'} = $self->target;
    $return{'Observation type'} = $self->type;
    $return{'UT start'} = defined($self->startobs) ? $self->startobs->hms : '';
    $return{'Exposure time'} = sprintf("%.1f", $self->duration );
    $return{'Filter'} = (defined($self->waveband) && defined($self->waveband->filter))
                        ? $self->waveband->filter : '';
    $return{'Wavelength'} = (defined($self->waveband) && defined($self->waveband->wavelength))
                            ? $self->waveband->wavelength :
                            '';

    if(defined($self->slitname)) {
      $return{'Slit Name'} = "1pix" if ( $self->slitname eq "0m" );
      $return{'Slit Name'} = "2pix" if ( $self->slitname eq "0w" );
      $return{'Slit Name'} = "4pix" if ( $self->slitname eq "0ew" );
      $return{'Slit Name'} = "2p-e" if ( $self->slitname eq "36.9w" );
      $return{'Slit Name'} = "1p-e" if ( $self->slitname eq "36.9m" );
    }

    $return{'Slit Angle'} = defined($self->slitangle) ? $self->slitangle : '';
    $return{'Number of Exposures'} = defined($self->nexp) ? $self->nexp : 0;
    $return{'Grating'} = defined($self->grating) ? $self->grating : '';
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
    $return{'_STRING_HEADER'} = " Obs  Grp           Object  UT start   ExpT Nexp    Filter Grating Wvlnth     Type   AM  RAoff DecOff Recipe";
    $return{'_STRING'} = sprintf("%4u %4u %16.16s  %-8.8s %6.2f %4f  %8.8s %7.7s %6.3f %8.8s %4.2f%6.1f %6.1f %20.20s", $return{'Observation'}, $return{'Group'}, $return{'Object'}, $return{'UT start'}, $return{'Exposure time'}, $return{'Number of Exposures'}, $return{'Filter'}, $return{'Grating'}, $return{'Wavelength'}, $return{'Observation type'}, $return{'Airmass'}, $return{'RA Offset'}, $return{'Dec Offset'}, $return{'DR Recipe'});

  }

  foreach my $comment ($self->comments) {
    if(defined($comment)) {
      if( exists( $return{'_STRING'} ) ) {
        $return{'_STRING'} .= sprintf("\n %19s UT / %s: %-50s",$comment->date->ymd . ' ' . $comment->date->hms, $comment->author->name, $comment->text);
      }
      if( exists( $return{'_STRING_LONG'} ) ) {
        $return{'_STRING_LONG'} .= sprintf("\n %19s UT / %s: %-50s",$comment->date->ymd . ' ' . $comment->date->hms, $comment->author->name, $comment->text);
      }
    }
  }

  return %return;

}

=item B<file_from_bits>

  $filename = $obs->file_from_bits;

Returns a filename based on information given in the C<Obs> object.

=cut

sub file_from_bits {
  my $self = shift;
  my $filename;

  my $instrument = $self->instrument;
  throw OMP::Error("file_from_bits: Unable to determine instrument to create filename.")
    unless defined $instrument;

  if( $instrument =~ /(ufti|ircam|cgs4|michelle|uist)/i ) {

    my $utdate;
    ( $utdate = $self->startobs->ymd ) =~ s/-//g;
    my $runnr = sprintf( "%05u", $self->runnr );

    $filename = OMP::Config->getData( 'rawdatadir',
                                      telescope => 'UKIRT',
                                      instrument => $instrument,
                                      utdate => $self->startobs->ymd );

    if( $instrument =~ /ufti/i ) {
      $filename .= "/f" . $utdate . "_" . $runnr . ".sdf";
    } elsif( $instrument =~ /uist/i ) {
      $filename .= "/u" . $utdate . "_" . $runnr . ".sdf";
    } elsif( $instrument =~ /ircam/i ) {
      $filename .= "/i" . $utdate . "_" . $runnr . ".sdf";
    } elsif( $instrument =~ /cgs4/i ) {
      $filename .= "/c" . $utdate . "_" . $runnr . ".sdf";
    } elsif( $instrument =~ /michelle/i ) {
      $filename .= "/m" . $utdate . "_" . $runnr . ".sdf";
    }
  } elsif( $instrument =~ /^(rx|het)/i ) {
    my $project = $self->projectid;
    my $ut = $self->startobs->datetime;
    my $timestring = sprintf("%02u%02u%02u_%02u%02u%02u",
                             $ut->yy,
                             $ut->mon,
                             $ut->mday,
                             $ut->hour,
                             $ut->min,
                             $ut->sec);
    my $backend = $self->backend;
    my $runnr = sprintf( "%04u", $self->runnr );
    $filename = OMP::Config->getData( 'rawdatadir',
                                      telescope => 'JCMT',
                                      instrument => 'heterodyne',
                                      utdate => $self->startobs->ymd );
    $filename = "$project\@" . $timestring . "_" . $backend . "_" . $runnr . ".gsd";
  } elsif( $instrument =~ /scuba/i ) {
    my $utdate;
    ( $utdate = $self->startobs->ymd ) =~ s/-//g;
    my $runnr = sprintf( "%04u", $self->runnr );
    $filename = OMP::Config->getData( 'rawdatadir',
                                      telescope => 'JCMT',
                                      instrument => 'SCUBA',
                                      utdate => $self->startobs->ymd );
    $filename .= $utdate . "_dem_" . $runnr . ".sdf";
  } else {
    throw OMP::Error("file_from_bits: Unable to determine filename for $instrument");
  }

  return $filename;
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
  $self->instrument( uc( $generic_header{INSTRUMENT} ) );
  $self->duration( $generic_header{EXPOSURE_TIME} );
  $self->disperser( $generic_header{GRATING_NAME} );
  $self->type( $generic_header{OBSERVATION_TYPE} );
  $generic_header{TELESCOPE} =~ /^(\w+)/;
  $self->telescope( $1 );
  $self->filename( $generic_header{FILENAME} );

  # Build the Astro::WaveBand object
  if ( length( $generic_header{GRATING_WAVELENGTH} . "" ) != 0 ) {
    $self->waveband( new Astro::WaveBand( Wavelength => $generic_header{GRATING_WAVELENGTH},
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

  # The default calibration is simply the project ID. This will
  # ensure that all calibrations associated with a project
  # are allocated to the project rather than shared. This is
  # not true for SCUBA. For UKIRT we will have to set things up
  # so that calibrations are not shared amongst projects at all
  $self->calType($self->projectid);

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

    # Set the string that specifies the calibration type
    $self->calType( $odfobject->calType );

    # We should really be including the polarimeter state
    # at this point but I am not sure whether the POL_CONN
    # keyword is stored in the database

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
        $self->coords( new Astro::Coords( ra    => $generic_header{RA_BASE},
                                           dec   => $generic_header{DEC_BASE},
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
  $self->airmass( ( $generic_header{AIRMASS_START} + $generic_header{AIRMASS_END} ) / 2 );
  $self->airmass_start( $generic_header{AIRMASS_START} );
  $self->airmass_end( $generic_header{AIRMASS_END} );
  $self->rows( $generic_header{Y_DIM} );
  $self->columns( $generic_header{X_DIM} );
  $self->drrecipe( $generic_header{DR_RECIPE} );
  $self->group( $generic_header{DR_GROUP} );
  $self->standard( $generic_header{STANDARD} );
  $self->slitname( $generic_header{SLIT_NAME} );
  $self->slitangle( $generic_header{SLIT_ANGLE} );
  $self->raoff( $generic_header{RA_TELESCOPE_OFFSET} );
  $self->decoff( $generic_header{DEC_TELESCOPE_OFFSET} );
  $self->grating( $generic_header{GRATING_NAME} );
  $self->order( $generic_header{GRATING_ORDER} );
  $self->tau( $generic_header{TAU} );
  $self->seeing( defined( $generic_header{SEEING} ?
                           sprintf("%.1f",$generic_header{SEEING}) :
                           "" ) );
  $self->bolometers( $generic_header{BOLOMETERS} );
  $self->velocity( $generic_header{VELOCITY} );
  $self->velsys( $generic_header{VELSYS} );
  $self->nexp( $generic_header{NUMBER_OF_EXPOSURES} );
  $self->chopthrow( $generic_header{CHOP_THROW} );
  $self->chopangle( $generic_header{CHOP_ANGLE} );
  $self->chopsystem( $generic_header{CHOP_COORDINATE_SYSTEM} );
  $self->rest_frequency( $generic_header{REST_FREQUENCY} );
  $self->cycle_length( $generic_header{CYCLE_LENGTH} );
  $self->number_of_cycles( $generic_header{NUMBER_OF_CYCLES} );
  $self->backend( $generic_header{BACKEND} );

  # Set the filename if it's not set.
#  if( !defined($self->filename) ) {
#    $self->filename( $self->file_from_bits );
#  }

}

=back

=head1 SEE ALSO

L<OMP::Info::MSB>

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>,
Brad Cavanagh E<lt>b.cavanagh@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
