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
use OMP::ObslogDB;
use OMP::DBbackend;

use Astro::FITS::Header::NDF;
use Astro::FITS::Header::GSD;
use Astro::FITS::HdrTrans;
use Astro::WaveBand;
use Astro::Coords;
use Time::Piece;
use Text::Wrap qw/ $columns &wrap /;
use File::Basename;

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

  $o = readfile OMP::Info::Obs( $filename );

If the constructor is unable to read the file, undef will be returned.

=cut

sub readfile {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $filename = shift;

  my $obs;

  try {
    my $FITS_header;
    if( $filename =~ /\.sdf$/ ) {
      # Redirect STDOUT in case this fails (if reading in the NDF fails,
      # AFHN directs the error messages to STDOUT, which is not really what
      # we want, since it's ugly).
      open(SAVEOUT, ">&STDOUT") or throw OMP::Error::FatalError("Can't save STDOUT.\n");
      open(STDOUT, ">/dev/null") or throw OMP::Error::FatalError("Can't open STDOUT to /dev/null.");

      $FITS_header = new Astro::FITS::Header::NDF( File => $filename );

      close(STDOUT);
      open(STDOUT, ">&SAVEOUT");	
    } elsif( $filename =~ /\.(gsd|dat)$/ ) {

      # Redirect STDOUT in case this fails.
      open(SAVEOUT, ">&STDOUT") or throw OMP::Error::FatalError("Can't save STDOUT.\n");
      open(STDOUT, ">/dev/null") or throw OMP::Error::FatalError("Can't open STDOUT to /dev/null.");

      $FITS_header = new Astro::FITS::Header::GSD( File => $filename );

      close(STDOUT);
      open(STDOUT, ">&SAVEOUT");	

    } else {
      throw OMP::Error::FatalError("Do not recognize file suffix for file $filename. Can not read header");
    }
    $obs = $class->new( fits => $FITS_header );
    $obs->filename( $filename );
  }
  catch Error with {

    close(STDOUT);
    open(STDOUT, ">&SAVEOUT");

    my $Error = shift;

    OMP::General->log_message( "OMP::Error in OMP::Info::Obs::readfile:\n text: " . $Error->{'-text'} . "\n file: " . $Error->{'-file'} . "\n line: " . $Error->{'-line'});

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
                              ambient_temp => '$',
                              backend => '$',
                              bolometers => '@',
                              camera => '$',
                              checksum => '$',
                              chopangle => '$',
                              chopfreq => '$',
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
                              filter => '$',
                              grating => '$',
                              group => '$',
                              humidity => '$',
                              instrument => '$',
                              inst_dhs => '$',
                              mode => '$',
                              nexp => '$',
                              number_of_cycles => '$',
                              object => '$',
                              order => '$',
                              pol => '$',
                              pol_in => '$',
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
                              switch_mode => '$',
                              target => '$',
                              tau => '$',
                              timeest => '$',
                              telescope => '$',
                              type => '$',
                              user_az_corr => '$',
                              user_el_corr => '$',
                              utdate => 'Time::Piece',
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
      $self->{status} = $comments[$#comments]->status;
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

    # Protect against undef [easy since the sprintf expects strings]
    # Silently fix things.
    my @strings = map { defined $_ ? $_ : '' } $self->runnr, 
      $self->startobs->hms, $self->projectid, $self->instrument, 
	$self->target, $self->mode;

    my $obssum = sprintf("%4.4s %8.8s %11.11s %8.8s %-20.20s %-16.16s\n",
			@strings);
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
      $commentsum = '' unless defined $commentsum;
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

  %nightlog = $obs->nightlog( %options );

An optional parameter may be supplied containing a hash of options. These are:

=over 4

=item comments - add comments to the nightlog string, a boolean. Defaults
to false (0).

=item display - type of display to show, a string either being 'long' or
'short'. Defaults to 'short'. 'long' information is not currently implemented.

=back

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
  my %options = @_;

  my $comments;
  if( exists( $options{comments} ) && defined( $options{comments} ) ) {
    $comments = $options{comments};
  } else {
    $comments = 0;
  }

  my $display;
  if( exists( $options{display} ) && defined( $options{display} ) ) {
    $display = $options{display};
  } else {
    $display = 'short';
  }

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
    $return{'Pol In?'} = defined( $self->pol_in ) ? $self->pol_in : '';
    $return{'Bolometers'} = $self->bolometers;
    $return{'RA'} = defined($self->coords) ? $self->coords->ra( format => 's' ) : '';
    $return{'Dec'} = defined($self->coords) ? $self->coords->dec( format => 's' ) : '';
    $return{'Coordinate Type'} = defined($self->coords) ? $self->coords->type : '';
    $return{'Mean Airmass'} = defined($self->airmass) ? $self->airmass : 0;
    $return{'Chop Throw'} = defined($self->chopthrow) ? $self->chopthrow : 0;
    $return{'Chop Angle'} = defined($self->chopangle) ? $self->chopangle : 0;
    $return{'Chop System'} = defined($self->chopsystem) ? $self->chopsystem : '';

    $return{'_ORDER'} = [ "Run", "UT time", "Obsmode", "Project ID", "Object",
                          "Tau225", "Seeing", "Filter", "Pol In?", "Bolometers" ];

    $return{'_STRING_HEADER'} = "Run  UT start        Mode     Project          Source Tau225  Seeing  Filter     Bolometers";
    $return{'_STRING'} = sprintf("%3s  %8s  %10.10s %11s %15s  %-6.3f  %-6.3f  %-10s %-15s", $return{'Run'}, $return{'UT time'}, $return{'Obsmode'}, $return{'Project ID'}, $return{'Object'}, $return{'Tau225'}, $return{'Seeing'}, $return{'Filter'}, $return{'Bolometers'}[0]);

    $return{'_STRING_HEADER_LONG'} = "Run  UT start        Mode     Project          Source Tau225  Seeing  Filter     Bolometers\n            RA           Dec  Coord Type  Mean AM  Chop Throw  Chop Angle  Chop Coords";
    $return{'_STRING_LONG'} = sprintf("%3s  %8s  %10.10s %11s %15s  %-6.3f  %-6.3f  %-10s %-15s\n %13.13s %13.13s    %8.8s  %7.2f  %10.1f  %10.1f  %11.11s", $return{'Run'}, $return{'UT time'}, $return{'Obsmode'}, $return{'Project ID'}, $return{'Object'}, $return{'Tau225'}, $return{'Seeing'}, $return{'Filter'}, $return{'Bolometers'}[0], $return{'RA'}, $return{'Dec'}, $return{'Coordinate Type'}, $return{'Mean Airmass'}, $return{'Chop Throw'}, $return{'Chop Angle'}, $return{'Chop System'});

  } elsif( $instrument =~ /^(rx|mpi|fts)/i ) {

# *** Heterodyne instruments

    $return{'Run'} = $self->runnr;
    my $utdate = $self->startobs->ymd;
    $utdate =~ s/-//g;
    $return{'UT'} = $self->startobs->hms;
    $return{'Mode'} = uc($self->mode);
    $return{'Source'} = $self->target;
    $return{'Cycle Length'} = $self->cycle_length;
    $return{'Number of Cycles'} = $self->number_of_cycles;
    $return{'Receiver'} = uc($self->instrument);
    $return{'Frequency'} = $self->rest_frequency;
    $return{'Velocity'} = $self->velocity;
    $return{'Velsys'} = $self->velsys;
    $return{'Project ID'} = $self->projectid;

    $return{'_ORDER'} = [ "Run", "UT", "Mode", "Project ID", "Source", "Cycle Length", "Number of Cycles",
                          "Receiver", "Frequency", "Velocity", "Velsys" ];

    $return{'_STRING_HEADER'} = "Run  UT start        Mode     Project          Source  Sec/Cyc   Rec Freq   Vel/Velsys";
#    $return{'_STRING_HEADER'} = " Run  Project           UT start      Mode      Source Sec/Cyc   Rec Freq   Vel/Velsys";
    $return{'_STRING'} = sprintf("%3s  %8s  %10.10s %11s %15s  %3d/%3d %5s  %3d %5d/%6s", $return{'Run'}, $return{'UT'}, $return{'Mode'}, $return{'Project ID'}, $return{'Source'}, $return{'Cycle Length'}, $return{'Number of Cycles'}, $return{'Receiver'}, $return{'Frequency'}, $return{'Velocity'}, $return{'Velsys'});
    $return{'_STRING_HEADER_LONG'} = $return{'_STRING_HEADER'};
    $return{'_STRING_LONG'} = $return{'_STRING'};

  } elsif($instrument =~ /(cgs4|ircam|ufti|uist|michelle)/i) {

# UKIRT instruments

    $return{'Observation'} = $self->runnr;
    $return{'Group'} = defined($self->group) ? $self->group : 0;
    $return{'Object'} = defined($self->target) ? $self->target : '';
    $return{'Observation type'} = defined($self->type) ? $self->type : '';
    $return{'Waveband'} = defined($self->waveband->filter) ? $self->waveband->filter : ( defined( $self->waveband->wavelength ) ? sprintf("%.2f", $self->waveband->wavelength) : '' );
    $return{'RA offset'} = defined($self->raoff) ? sprintf( "%.3f", $self->raoff) : 0;
    $return{'Dec offset'} = defined($self->decoff) ? sprintf( "%.3f", $self->decoff) : 0;
    $return{'UT time'} = defined($self->startobs) ? $self->startobs->hms : '';
    $return{'Airmass'} = defined($self->airmass) ? sprintf( "%.2f", $self->airmass) : 0;
    $return{'Exposure time'} = defined($self->duration) ? sprintf( "%.2f",$self->duration ) : 0;
    $return{'DR Recipe'} = defined($self->drrecipe) ? $self->drrecipe : '';
    $return{'Project ID'} = $self->projectid;
    $return{'_ORDER'} = [ "Observation", "Group", "Project ID", "UT time", "Object",
                          "Observation type", "Exposure time", "Waveband", "RA offset", "Dec offset",
                          "Airmass", "DR Recipe" ];

    $return{'_STRING_HEADER'} = " Obs  Grp  Project ID UT Start      Object     Type   ExpT Wvbnd     Offsets    AM Recipe";
    $return{'_STRING'} = sprintf("%4d %4d %11.11s %8.8s %11.11s %8.8s %6.2f %5.5s %5.1f/%5.1f  %4.2f %-22.22s", $return{'Observation'}, $return{'Group'}, $return{'Project ID'}, $return{'UT time'}, $return{'Object'}, $return{'Observation type'}, $return{'Exposure time'}, $return{'Waveband'}, $return{'RA offset'}, $return{'Dec offset'}, $return{'Airmass'}, $return{'DR Recipe'});

# And now for the specifics.

    if( $instrument =~ /cgs4/i ) {

      $return{'Wavelength'} = $self->waveband->wavelength;
      $return{'Slit Name'} = $self->slitname;
      $return{'PA'} = $self->slitangle;
      if(defined($self->coords)) {
        $return{'RA'} = $self->coords->ra( format => "s" );
        $return{'Dec'} = $self->coords->dec( format => "s" );
      } else {
        $return{'RA'} = "--:--:--";
        $return{'Dec'} = "--:--:--";
      }
      $return{'Grating'} = $self->grating;
      $return{'Order'} = $self->order;
      $return{'Nexp'} = $self->nexp;

      push @{$return{'_ORDER'}}, ( "Slit Name", "PA", "Grating", "Order", "Wavelength", "RA", "Dec", "Nexp" );
      $return{'_STRING_HEADER_LONG'} = $return{'_STRING_HEADER'} . "\n   Slit Name      PA    Grating  Order            RA          Dec  Nexp";
      $return{'_STRING_LONG'} = $return{'_STRING'} . sprintf("\n   %9.9s  %6.2f %10.10s  %5d  %12.12s %12.12s  %4d", $return{'Slit Name'}, $return{'PA'}, $return{'Grating'}, $return{'Order'}, $return{'RA'}, $return{'Dec'}, $return{'Nexp'});

    } elsif( $instrument =~ /ircam/i ) {

    } elsif( $instrument =~ /ufti/i ) {

      $return{'Filter'} = $self->filter;
      $return{'Readout Area'} = $self->columns . "x" . $self->rows;
      $return{'Speed'} = $self->speed;
      if(defined($self->coords)) {
        $return{'RA'} = $self->coords->ra( format => "s" );
        $return{'Dec'} = $self->coords->dec( format => "s" );
      } else {
        $return{'RA'} = "--:--:--";
        $return{'Dec'} = "--:--:--";
      }
      $return{'Nexp'} = $self->nexp;

      push @{$return{'_ORDER'}}, ( "Filter", "Readout Area", "Speed", "RA", "Dec" );
      $return{'_STRING_HEADER_LONG'} = $return{'_STRING_HEADER'} . "\n   Filter  Readout Area      Speed            RA          Dec  Nexp";
      $return{'_STRING_LONG'} = $return{'_STRING'} . sprintf("\n   %6.6s     %9.9s %10s  %12.12s %12.12s  %4d", $return{'Filter'}, $return{'Readout Area'}, $return{'Speed'}, $return{'RA'}, $return{'Dec'}, $return{'Nexp'});

    } elsif( $instrument =~ /uist/i ) {

      $return{'Mode'} = $self->mode;
      if(defined($self->slitname)) {
        if( $self->mode =~ /(spectroscopy|ifu)/i ) {
          $return{'Slit Angle'} = $self->slitangle;
          if(lc($self->slitname) eq "0m") { $return{'Slit'} = "1pix"; }
          elsif(lc($self->slitname) eq "0w") { $return{'Slit'} = "2pix"; }
          elsif(lc($self->slitname) eq "0ew") { $return{'Slit'} = "4pix"; }
          elsif(lc($self->slitname) eq "36.9w") { $return{'Slit'} = "2p-e"; }
          elsif(lc($self->slitname) eq "36.9m") { $return{'Slit'} = "1p-e"; }
          else { $return{'Slit'} = $self->slitname; }
          $return{'Wavelength'} = $self->waveband->wavelength;
          $return{'Grism'} = $self->grating;
          $return{'Speed'} = "-";
        } else {
          $return{'Grism'} = "-";
          $return{'Wavelength'} = "0";
          $return{'Slit'} = "-";
          $return{'Slit Angle'} = "0";
          $return{'Speed'} = $self->speed;
        }
      }
      $return{'Filter'} = $self->filter;
      $return{'Readout Area'} = $self->columns . "x" . $self->rows;
      $return{'Camera'} = $self->camera;
      $return{'Nexp'} = $self->nexp;

      push @{$return{'_ORDER'}}, ( "Mode", "Slit", "Slit Angle", "Grism", "Wavelength", "Filter", "Readout Area", "Camera", "Nexp", "Speed" );
      $return{'_STRING_HEADER_LONG'} = $return{'_STRING_HEADER'} . "\n          Mode Slit     PA      Grism Wvlnth Filter  Readout Area  Camera Nexp   Speed";
      $return{'_STRING_LONG'} = $return{'_STRING'} . sprintf("\n  %12.12s %4.4s %6.2f %10.10s %6.3f %6.6s     %9.9s  %6.6s %4d %7.7s", $return{'Mode'}, $return{'Slit'}, $return{'Slit Angle'}, $return{'Grism'}, $return{'Wavelength'}, $return{'Filter'}, $return{'Readout Area'}, $return{'Camera'}, $return{'Nexp'}, $return{'Speed'});

    } elsif( $instrument =~ /michelle/i ) {
      $return{'Mode'} = $self->mode;
      $return{'Chop Angle'} = sprintf("%.2f", $self->chopangle);
      $return{'Chop Throw'} = sprintf("%.2f", $self->chopthrow);
      if( $self->mode =~ /spectroscopy/i ) {
        $return{'Slit Angle'} = sprintf("%.2f", $self->slitangle);
        $return{'Slit'} = $self->slitname;
        $return{'Wavelength'} = sprintf("%.4f", $self->waveband->wavelength);
      } else {
        $return{'Slit Angle'} = 0;
        $return{'Slit'} = '-';
        $return{'Wavelength'} = 0;
      }
      
    }

  }

  if( $comments ) {
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
  } elsif( $instrument =~ /^(rx|het|fts)/i ) {
    my $project = $self->projectid;
    my $ut = $self->startobs;
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

=item B<remove_comment>

  $obs->remove_comment( $userid );

Removes the existing comment for the given user ID from the C<OMP::Info::Obs>
object and sets all comments for the given user ID and C<OMP::Info::Obs> object
as inactive in the database.

=cut

sub remove_comment {
  my $self = shift;
  my $userid = shift;

  if(!defined($userid)) {
    throw OMP::Error::BadArgs("Must supply user ID in order to remove comments");
  }

  my $db = new OMP::ObslogDB( DB => new OMP::DBbackend );

  $db->removeComment( $self, $userid );

  my @obs;
  push @obs, $self;

  $db->updateObsComment( \@obs );

}

=item B<simple_filename>

Returns a filename (without path contents) that is suitable
for use in data processing. Usually this only refers to
JCMT heterodyne data where the filename stored in the
DB is impossible to use in specx. Most instruments simply
return the root filename without modification.

The filename returned has no path attached.

 $simple = $obs->simple_filename();

Note that this method does uses the C<filename>
method implicitly. Note also that this method
must work with a valid Obs object.

=cut

sub simple_filename {
  my $self = shift;

  # Get the filename
  my $infile = $self->filename;

  # Get the filename without path
  my $base = basename( $infile );

  if ($self->telescope eq 'JCMT' && $self->instrument ne 'SCUBA') {
    # Want YYYYMMDD_backend_nnnn.dat
    my $yyyy = $self->startobs->strftime('%Y%m%d');
    $base = $yyyy . '_' . $self->backend .'_' .
      sprintf('%04u', $self->runnr) . '.dat';

  }

  # Return the simplified filename
  return $base;

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
  $self->telescope( uc($1) );
  $self->filename( $generic_header{FILENAME} );
  $self->inst_dhs( $generic_header{INST_DHS} );

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
  if( defined( $self->projectid ) ) {
    $self->calType($self->projectid);
  }

  # Build the Astro::Coords object

  # If we're SCUBA, we can use SCUBA::ODF::getTarget to make the
  # Astro::Coords object for us. Hooray!

  if( $generic_header{'INSTRUMENT'} =~ /scuba/i &&
      exists( $generic_header{'COORDINATE_TYPE'} ) &&
      defined( $generic_header{'COORDINATE_TYPE'} ) ) {

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
    if ( defined( $generic_header{EQUINOX} ) &&
         $generic_header{EQUINOX} =~ /1950/ ) {
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

    # if we are UKIRT or JCMT Heterodyne try to generate the calibration
    # flags. We should probably put this in the header translator
    if ($self->telescope eq 'UKIRT') {

      # Observations with STANDARD=T are science calibrations
      # Observations with PROJECT =~ /CAL/ are generic calibrations
      # DARKS and BIAS are generic calibrations
      # FLAT and ARC are science calibrations
      if ($self->projectid =~ /CAL$/ ||
          length($self->projectid) == 0 ||
          $self->type =~ /DARK|BIAS/
         ) {
        $self->isGenCal( 1 );
        $self->isScience( 0 );
      } elsif ($self->type =~ /FLAT|ARC/ ||
               $generic_header{STANDARD}
              ) {
        $self->isSciCal( 1 );
        $self->isScience( 0 );
      }

    } elsif ($self->telescope eq 'JCMT') {
      # SCUBA is done in other branch

      # fivepoint/focus are generic
      # anything with 'jcmt' or 'jcmtcal' is generic
      # Do not include planets in the list.
      # Standard spectra are science calibrations but we have to be
      # careful with this since they may also be science observations.
      # For now, only check name matches (names should match pointing
      # catalog name exactly) and also that it is a single SAMPLE. Should really
      # be cleverer than that...
      if (( defined( $self->projectid ) && $self->projectid =~ /JCMT/  ) ||
          ( defined( $self->mode ) && $self->mode =~ /fivepoint|focus/i )
         ) {
        $self->isGenCal( 1 );
        $self->isScience( 0 );
      } elsif ($self->mode =~ /sample/i && $self->target =~ /^(w3\(oh\)|l1551\-irs5|crl618|omc1|n2071ir|oh231\.8|irc\+10216|16293\-2422|ngc6334i|g34\.3|w75n|crl2688|n7027|n7538irs1)$/i) {
        $self->isSciCal( 1 );
        $self->isScience( 0 );
      }

    }

  }

  $self->runnr( $generic_header{OBSERVATION_NUMBER} );
  $self->utdate( $generic_header{UTDATE} );
  $self->speed( $generic_header{SPEED_GAIN} );
  if( defined( $generic_header{AIRMASS_END} ) ) {
    $self->airmass( ( $generic_header{AIRMASS_START} + $generic_header{AIRMASS_END} ) / 2 );
  } else {
    $self->airmass( $generic_header{AIRMASS_START} );
  }
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
  $self->chopfreq( $generic_header{CHOP_FREQUENCY} );
  $self->rest_frequency( $generic_header{REST_FREQUENCY} );
  $self->cycle_length( $generic_header{CYCLE_LENGTH} );
  $self->number_of_cycles( $generic_header{NUMBER_OF_CYCLES} );
  $self->backend( $generic_header{BACKEND} );
  $self->filter( $generic_header{FILTER} );
  $self->camera( $generic_header{CAMERA} );
  $self->pol( $generic_header{POLARIMETRY} );
  $self->pol_in( $generic_header{POLARIMETER} );
  $self->switch_mode( $generic_header{SWITCH_MODE} );
  $self->ambient_temp( $generic_header{AMBIENT_TEMPERATURE} );
  $self->humidity( $generic_header{HUMIDITY} );
  $self->user_az_corr( $generic_header{USER_AZIMUTH_CORRECTION} );
  $self->user_el_corr( $generic_header{USER_ELEVATION_CORRECTION} );

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
