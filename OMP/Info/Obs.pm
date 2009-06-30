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
use OMP::Constants qw/ :obs :logging /;
use OMP::Error qw/ :try /;
use OMP::ObslogDB;
use OMP::DBbackend;
use Scalar::Util qw/ blessed /;

use Astro::FITS::Header::NDF;
use Astro::FITS::Header::GSD;
use Astro::FITS::HdrTrans;
use Astro::WaveBand;
use Astro::Telescope;
use Astro::Coords;
use Storable qw/ dclone /;
use Time::Piece;
use Text::Wrap qw/ $columns &wrap /;
use File::Basename;

use NDF qw/ :ndf :err /;

# Text wrap column size.
$Text::Wrap::columns = 72;

use base qw/ OMP::Info::Base /;

our $VERSION = (qw$Revision$)[1];

use overload '""' => "stringify";

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

Create a new C<OMP::Info::Obs> object.

Special keys are:

  retainhdr =>
  fits =>
  hdrhash =>

=cut

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;

  my $obs = $class->SUPER::new( @_ );

  # if we have fits but nothing else
  # translate the fits header to generic
  my %args = @_;

  $obs->_populate()
    if ( $args{'fits'}    && $args{'fits'}    )
    || ( $args{'hdrhash'} && $args{'hdrhash'} )
    ;

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
  my %args = @_;

  my $obs;

  my $SAVEOUT;

  try {
    my $FITS_header;
    my $frameset;

    if( $filename =~ /\.sdf$/ ) {

      $FITS_header = new Astro::FITS::Header::NDF( File => $filename );

      # Open the NDF environment.
      my $STATUS = &NDF::SAI__OK;
      ndf_begin();
      err_begin( $STATUS );

      # Retrieve the FrameSet.
      ndf_find( NDF::DAT__ROOT, $filename, my $indf, $STATUS );
      $frameset = ndfGtwcs( $indf, $STATUS );
      ndf_annul( $indf, $STATUS );
      ndf_end( $STATUS );

      # Handle errors.
      if( $STATUS != &NDF::SAI__OK ) {
        my ( $oplen, @errs );
        do {
          err_load( my $param, my $parlen, my $opstr, $oplen, $STATUS );
          push @errs, $opstr;
        } until ( $oplen == 1 );
        err_annul( $STATUS );
        err_end( $STATUS );
        throw OMP::Error::FatalError( "Error retrieving WCS from NDF:\n" . join "\n", @errs );
      }
      err_end( $STATUS );

    } elsif( $filename =~ /\.(gsd|dat)$/ ) {

      $FITS_header = new Astro::FITS::Header::GSD( File => $filename );

    } else {
      throw OMP::Error::FatalError("Do not recognize file suffix for file $filename. Can not read header");
    }
    $obs = $class->new( fits => $FITS_header, wcs => $frameset, %args );
    $obs->filename($filename);
  }
  catch Error with {

    my $Error = shift;

    OMP::General->log_message("OMP::Error in OMP::Info::Obs::readfile:\nfile: $filename\ntext: " . $Error->{'-text'} . "\nsource: " . $Error->{'-file'} . "\nline: " . $Error->{'-line'}, OMP__LOG_ERROR);

    throw OMP::Error::ObsRead("Error reading FITS header from file $filename: " . $Error->{'-text'});
  };

  return $obs;
}

=item B<copy>

Copy constructor. New object will be independent of the original.

 $new = $old->copy();

=cut

sub copy {
  my $self = shift;
  return dclone( $self );
}

=item B<subsystems>

Returns C<OMP::Info::Obs> objects representing each subsystem present in the observation.
If only one subsystem is being used, this method will return a single object that will be
distinct from the primary object.

  @obs = $obs->subsystems();

Subsytems are determined by looking at the C<subsystem_idkey> in the FITS header.

=cut

sub subsystems {
  my $self = shift;

  my $copy = $self->copy();

  # get a hash representation of the FITS header
  my $hdr = $copy->hdrhash;
  my $fits = $copy->fits;

  # Get the grouping key
  my $idkey = $copy->subsystem_idkey;

  # If we do not have a grouping key or there is no FITS header or
  # there is only a single instance of the idkey we only have a single
  # subsystem
  return $copy if !defined $idkey;
  return $copy if !defined $hdr;
  return $copy if exists $hdr->{$idkey};

  # see if the primary key is in the subheader (and disable multi
  # subsystem if it isn't)
  return $copy unless exists $hdr->{SUBHEADERS}->[0]->{$idkey};

  # Now need to group the fits headers
  # First take a copy of the common headers and delete subheaders
  my %common = %$hdr;
  delete $common{SUBHEADERS};

  # and then get the actual subheaders
  my @subhdrs = $fits->subhdrs;

  # Get the filenames
  my @filenames = $copy->filename;

  # sanity check
  if (@filenames != @{$hdr->{SUBHEADERS}}) {
    throw OMP::Error::FatalError("Number of filenames in Obs object does not match number of subheaders\n");
  }


  # Now get the subheaders and split them up on the basis of primary key
  # Need to track filenames as well (which are assumed to track the subheader)
  my %subsys;
  my %subscans;
  my @suborder;
  for my $i (0..$#filenames) {
    my $subhdr = $subhdrs[$i];
    my $subid = $subhdr->value($idkey);
    if (!exists $subsys{$subid}) {
      $subsys{$subid} = [];
      $subscans{$subid} = [];
      push(@suborder, $subid); # keep track of original order
    }
    push(@{$subscans{$subid}}, $filenames[$i]);
    push(@{$subsys{$subid}}, $subhdr);
  }

  # create a common header
  my $comhdr = Astro::FITS::Header->new( Hash => \%common );

  # merge headers for each subsystem
  my %headers;
  for my $subid (keys %subsys) {
    my $primary = $subsys{$subid}->[0];
    my $merged;
    if (@{$subsys{$subid}} > 1) {
      ($merged, my @different) = $primary->merge_primary( { merge_unique => 1 },
                                                          @{ $subsys{$subid} }[1..$#{$subsys{$subid}}]);
      $merged->subhdrs( @different );
    } else {
      $merged = $primary;
    }

    # Merge with common headers
    $merged->splice( 0, 0, $comhdr->allitems );

    $headers{$subid} = $merged;
  }

  # Create new subsystem Obs objects
  my @obs;
  for my $subid (@suborder) {
    my $obs = new OMP::Info::Obs( fits => $headers{$subid}, retainhdr => $copy->retainhdr );
    $obs->filename( $subscans{$subid} );
    push(@obs, $obs);
  }

  return @obs;
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
                              bandwidth_mode => '$',
                              bolometers => '@',
                              camera => '$',
                              camera_number => '$',
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
#                              filename => '$',
                              filter => '$',
                              frontend => '$',
                              grating => '$',
                              group => '$',
                              humidity => '$',
                              instrument => '$',
                              inst_dhs => '$',
                              mode => '$',
                              msbtid => '$',
                              nexp => '$',
                              number_of_coadds => '$',
                              number_of_cycles => '$',
                              object => '$',
                              obsid => '$',
                              order => '$',
                              pol => '$',
                              pol_in => '$',
                              projectid => '$',
                              raoff => '$',
                              rest_frequency => '$',
                              retainhdr => '$',
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
                              tile => '$',
                              timeest => '$',
                              telescope => '$',
                              type => '$',
                              user_az_corr => '$',
                              user_el_corr => '$',
                              velocity => '$',
                              velsys => '$',
                              waveband => 'Astro::WaveBand',
                              wcs => 'Starlink::AST::FrameSet',

                              isScience => '$',
                              isSciCal => '$',
                              isGenCal => '$',
                              calType  => '$',
                              subsystem_idkey => '$',
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

=item B<utdate>

The UT date of the observation in YYYYMMDD integer form.

Can accept an integer, a C<Time::Piece> or C<DateTime> object.

=cut

sub utdate {
  my $self = shift;
  if (@_) {
    my $arg = shift;
    if (blessed($arg) && $arg->can('year')) {
      $arg = sprintf('%04d%02d%02d',
                     $arg->year, $arg->mon, $arg->mday);
    }
    $self->{UTDATE} = $arg;
  }
  return $self->{UTDATE};
}

=item B<subsystem_idkey>

Specifies which FITS header key should be used to group subsystems. If undefined
only a single subsystem is available.

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

=item B<filename>

Return or set filename(s) associated with the observation.

  my $filename = $obs->filename;
  my @filenames = $obs->filename;

If called in scalar context, returns the first filename. If called in
list context, returns all filenames.

  $obs->filename( \@filenames );

When setting, the filenames must be passed in as an array
reference. Any filenames passed in override those previously set.

An optional flag can be used to force a raw data directory to be prepended
if no path is present in the filename.

  $obs->filename( \@filesnames, $ensure_full_path );

=cut

sub filename {
  my $self = shift;
  my $filenames = shift;
  my $ensure_full_path = shift;

  if( defined( $filenames ) ) {
    if (! ref($filenames)) {
      $self->{FILENAME} = [$filenames];
    } elsif (ref($filenames) eq 'ARRAY') {
      $self->{FILENAME} = $filenames;
    } else {
      throw OMP::Error::BadArgs("Argument must be an ARRAY reference");
    }

    if ($ensure_full_path) {
      # put a path in front of everything.
      # Note that rawdatadir() calls this method without arguments
      my $rawdir = $self->rawdatadir;

      for my $f (@{$self->{FILENAME}}) {
        my ($vol, $path, $file) = File::Spec->splitpath( $f );
        next if $path;
        # change filename in place
        $f = File::Spec->catpath( $vol, $rawdir, $file );
      }
    }

  }

  if( wantarray ) {
    return @{$self->{FILENAME}};
  } else {
    return ${$self->{FILENAME}}[0];
  }
}

sub fits {
  my $self = shift;
  if( @_ ) {
    $self->_fits( @_ );

    # Do not synchronize if we're not retaining headers.
    return unless $self->retainhdr;
  }

  unless ( $self->_defined_fits ) {

    warn "Neither '_fits' nor '_hdrhash' is defined";
    return;
  }

  my $fits = $self->_fits;
  if( ! defined( $fits ) ) {
    my $hdrhash = $self->hdrhash;
    if( defined( $hdrhash ) ) {

      # Create the Header object.
      $fits = Astro::FITS::Header->new( Hash => $hdrhash );
      $self->_fits( $fits );

    }
  }
  return $fits;
}


sub hdrhash {
  my $self = shift;
  if( @_ ) {
    $self->_hdrhash( @_ );

    # Do not synchronize if we're not retaining headers.
    return unless $self->retainhdr;
  }

  unless ( $self->_defined_fits ) {

    warn "Neither '_fits' nor '_hdrhash' is defined";
    return;
  }

  my $hdr = $self->_hdrhash;
  if( ! defined( $hdr ) || scalar keys %$hdr == 0) {
    my $fits = $self->fits;
    if( defined( $fits ) ) {
      my $FITS_header = $self->fits;
      $FITS_header->tiereturnsref( 1 );
      tie my %header, ref($FITS_header), $FITS_header;

      $hdr = \%header;
      $self->_hdrhash( $hdr );
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

sub removefits {
  my $self = shift;
  delete $self->{_fits};
  delete $self->{_hdrhash};
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

    # Make sure we can handle a missing startobs (e.g. if this object
    # is created from a science program before it is observed)
    my $startobs = $self->startobs;
    my $start = (defined $startobs ? $startobs->hms : '<NONE>');

    # Protect against undef [easy since the sprintf expects strings]
    # Silently fix things.
    my @strings = map { defined $_ ? $_ : '' } $self->runnr,
      $start, $self->projectid, $self->instrument,
        $self->target, $self->mode;

    my $obssum = sprintf("%4.4s %8.8s %15.15s %8.8s %-18.18s %-14.14s\n",
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

  } elsif( $instrument =~ /^(rx|mpi|fts|harp)/i ) {

# *** Heterodyne instruments

    $return{'Run'} = $self->runnr;
    my $utdate = $self->startobs->ymd;
    $utdate =~ s/-//g;
    $return{'UT'} = $self->startobs->hms;
    $return{'Mode'} = uc($self->mode);
    $return{'Source'} = $self->target;
    $return{'Cycle Length'} = ( defined( $self->cycle_length ) ?
                                sprintf( "%3d", $self->cycle_length ) :
                                ' - ' );
    $return{'Number of Cycles'} = $self->number_of_cycles;
    $return{'Frequency'} = $self->rest_frequency;

    # Convert the rest frequency into GHz for display purposes.
    $return{'Frequency'} /= 1000000000;

    $return{'Velocity'} = $self->velocity;

    # Prettify the velocity.
    if( $return{'Velocity'} < 1000 ) {
      $return{'Velocity'} = sprintf( "%5.1f", $return{'Velocity'} );
    } else {
      $return{'Velocity'} = sprintf( "%5d", $return{'Velocity'} );
    }

    $return{'Velsys'} = $self->velsys;
    $return{'Project ID'} = $self->projectid;
    $return{'Bandwidth Mode'} = $self->bandwidth_mode;

    $return{'_ORDER'} = [ "Run", "UT", "Mode", "Project ID", "Source", "Cycle Length", "Number of Cycles",
                          "Frequency", "Velocity", "Velsys", "Bandwidth Mode" ];

    $return{'_STRING_HEADER'} = "Run  UT start              Mode     Project          Source  Sec/Cyc  Rest Freq   Vel/Velsys     BW Mode";
#    $return{'_STRING_HEADER'} = " Run  Project           UT start      Mode      Source Sec/Cyc   Rec Freq   Vel/Velsys";
    $return{'_STRING'} = sprintf("%3s  %8s  %16.16s %11s %15.15s  %3s/%3d    %7.3f %5s/%6s %11s", $return{'Run'}, $return{'UT'}, $return{'Mode'}, $return{'Project ID'}, $return{'Source'}, $return{'Cycle Length'}, $return{'Number of Cycles'}, $return{'Frequency'}, $return{'Velocity'}, $return{'Velsys'}, $return{'Bandwidth Mode'});
    $return{'_STRING_HEADER_LONG'} = $return{'_STRING_HEADER'};
    $return{'_STRING_LONG'} = $return{'_STRING'};

  } elsif($instrument =~ /wfcam/i) {

# WFCAM

    $return{'Observation'} = $self->runnr;
    $return{'Group'} = defined( $self->group ) ? $self->group : 0;
    $return{'Tile'} = defined( $self->tile ) ? $self->tile : 0;
    $return{'Object'} = defined( $self->target ) ? $self->target : '';
    $return{'Observation type'} = defined( $self->type ) ? $self->type : '';
    $return{'Waveband'} = defined( $self->filter ) ? $self->filter : '';
    $return{'RA offset'} = defined( $self->raoff ) ? sprintf( "%.3f", $self->raoff ) : 0;
    $return{'Dec offset'} = defined( $self->decoff ) ? sprintf( "%.3f", $self->decoff ) : 0;
    $return{'UT time'} = defined( $self->startobs ) ? $self->startobs->hms : '';
    $return{'Airmass'} = defined( $self->airmass ) ? sprintf( "%.2f", $self->airmass ) : 0;
    $return{'Exposure time'} = defined( $self->duration ) ? sprintf( "%.2f", $self->duration ) : 0;
    $return{'Number of coadds'} = defined( $self->number_of_coadds ) ? sprintf( "%d", $self->number_of_coadds ) : 0;
    $return{'DR Recipe'} = defined( $self->drrecipe ) ? $self->drrecipe : '';
    $return{'Project ID'} = defined( $self->projectid ) ? $self->projectid : '';
    $return{'Hour Angle'} = defined( $self->coords ) ? $self->coords->ha( "s" ) : '';
    $return{'_ORDER'} = [ "Observation", "Group", "Tile", "Project ID", "UT time", "Object",
                          "Observation type", "Exposure time", "Number of coadds", "Waveband",
                          "RA offset", "Dec offset", "Airmass", "Hour Angle", "DR Recipe" ];
    $return{'_STRING_HEADER'} = " Obs  Grp Tile     Project ID UT Start          Object     Type  ExpT  Filt     Offsets   AM Recipe";
    $return{'_STRING'} = sprintf("%4d %4d %4d %14.14s %8.8s %15.15s %8.8s %5.2f %5.5s %5.1f/%5.1f %4.2f %-12.12s", $return{'Observation'}, $return{'Group'}, $return{'Tile'}, $return{'Project ID'}, $return{'UT time'}, $return{'Object'}, $return{'Observation type'}, $return{'Exposure time'}, $return{'Waveband'}, $return{'RA offset'}, $return{'Dec offset'}, $return{'Airmass'}, $return{'DR Recipe'});

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
      $return{'Coadds'} = $self->nexp;

      push @{$return{'_ORDER'}}, ( "Slit Name", "PA", "Grating", "Order", "Wavelength", "RA", "Dec", "Nexp" );
      $return{'_STRING_HEADER_LONG'} = $return{'_STRING_HEADER'} . "\n   Slit Name      PA    Grating  Order            RA          Dec  Coadds";
      $return{'_STRING_LONG'} = $return{'_STRING'} . sprintf("\n   %9.9s  %6.2f %10.10s  %5d  %12.12s %12.12s  %6d", $return{'Slit Name'}, $return{'PA'}, $return{'Grating'}, $return{'Order'}, $return{'RA'}, $return{'Dec'}, $return{'Coadds'});

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
  } else {
    # Unexpected instrument
    $return{Run} = $self->runnr;
    $return{ProjectID} = $self->projectid;
    $return{UT} = $self->startobs->hms;
    $return{Source} = $self->target;
    $return{Mode} = uc($self->mode);

    $return{_ORDER} = [ "Run", "UT", "Mode", "ProjectID", "Source" ];
    $return{_STRING_HEADER} = "Run  UT start              Mode     Project          Source";
    $return{_STRING} = sprintf("%3s  %8s  %16.16s %11s %15s",
                               $return{'Run'}, $return{'UT'}, $return{'Mode'}, $return{'ProjectID'},
                               $return{'Source'});
    $return{'_STRING_HEADER_LONG'} = $return{'_STRING_HEADER'};
    $return{'_STRING_LONG'} = $return{'_STRING'};
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

Returns a filename (including path) based on information given in the C<Obs> object.

=cut

sub file_from_bits {
  my $self = shift;

  my $instrument = $self->instrument;
  throw OMP::Error("file_from_bits: Unable to determine instrument to create filename.")
    unless defined $instrument;

  # first get the raw data directory
  my $rawdir = $self->rawdatadir;

  # Now work out the full path
  my $filename;
  if( $instrument =~ /(ufti|ircam|cgs4|michelle|uist|wfcam)/i ) {

    my $utdate;
    ( $utdate = $self->startobs->ymd ) =~ s/-//g;
    my $runnr = sprintf( "%05u", $self->runnr );

    # work out the instrument prefix. Seems that we can not use a hash because
    # the instrument names may include numbers (eg ircam3)
    my $instprefix;
    if( $instrument =~ /ufti/i ) {
      $instprefix = "f";
    } elsif( $instrument =~ /uist/i ) {
      $instprefix = "u";
    } elsif( $instrument =~ /ircam/i ) {
      $instprefix = "i";
    } elsif( $instrument =~ /cgs4/i ) {
      $instprefix = "c";
    } elsif( $instrument =~ /michelle/i ) {
      $instprefix = "m";
    } elsif( $instrument =~ /wfcam/i ) {
      my %prefix = ( 1 => 'w',
                     2 => 'x',
                     3 => 'y',
                     4 => 'z',
                   );
      $instprefix = $prefix{ $self->camera_number };
    } else {
      throw OMP::Error("file_from_bits: Unrecognized UKIRT instrument: '$instrument'");
    }

    $filename = File::Spec->catdir( $rawdir, $instprefix. $utdate . "_" . $runnr . ".sdf" );

  } elsif( $instrument =~ /^(rx|het|fts)/i &&
           uc( $self->backend ) ne 'ACSIS' ) {
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
    $filename = "$project\@" . $timestring . "_" . $backend . "_" . $runnr . ".gsd";
  } elsif( $instrument =~ /scuba/i ) {
    my $utdate;
    ( $utdate = $self->startobs->ymd ) =~ s/-//g;
    my $runnr = sprintf( "%04u", $self->runnr );

    $filename = File::Spec->catfile( $rawdir, $utdate . "_dem_" . $runnr . ".sdf");
  } elsif( $self->backend =~ /acsis/i ) {
    my $utdate;
    ( $utdate = $self->startobs->ymd ) =~ s/-//g;
    my $runnr = sprintf( "%05u", $self->runnr );
    $filename = File::Spec->catfile( $filename,
                                     "a" . $utdate . "_" . $runnr . "_00_0001.sdf" );

  } else {
    throw OMP::Error("file_from_bits: Unable to determine filename for $instrument");
  }

  return $filename;
}

=item B<rawdatadir>

Using information in the Obs object either derive the raw data dir or determine it
from the path attached to filenames (if any).

  $rawdir = $obs->rawdatadir;

Note that this data directory is suitable for a single raw observation rather than
a set of observations. This is because some data are written into per-observation sub
directories and that is taken into account.

=cut

sub rawdatadir {
  my $self = shift;

  # First look at the filenames
  my %dirs;
  for my $f ($self->filename) {
    my ($vol, $path, $file) = File::Spec->splitpath( $f );
    $dirs{$path}++ if $path;
  }

  # if we have one match then return it
  # else work something else out
  if (keys %dirs  == 1) {
    my ($dir) = keys %dirs;
    return $dir;
  }

  # Now we need an instrument name
  my $instrument = $self->instrument;
  throw OMP::Error("rawdatadir: Unable to determine instrument to determine raw data directory.")
    unless defined $instrument;

  # We need the date in YYYYMMDD format
  my $utdate = $self->startobs->ymd;

  my ( $dir , $tel , $sub_inst ) ;
  if( $instrument =~ /(ufti|ircam|cgs4|michelle|uist|wfcam)/i ) {
    $dir = OMP::Config->getData( 'rawdatadir',
                                 telescope => 'UKIRT',
                                 instrument => $instrument,
                                 utdate => $utdate );
  } elsif( $self->backend =~ /acsis/i ) {
    $dir = OMP::Config->getData( 'rawdatadir',
                                 telescope => 'JCMT',
                                 instrument => 'ACSIS',
                                 utdate => $utdate);
    $dir =~ s/dem//;

    # For ACSIS the actual files are in a subdir
    my $runnr = sprintf( "%05u", $self->runnr );

    my ( $pre, $post ) = split /acsis/, $dir;
    $dir = File::Spec->catdir( $pre, 'acsis', 'spectra', $post, $runnr );

    $sub_inst  = 'ACSIS';

  } elsif( $instrument =~ /^(rx|het|fts)/i ) {
    $dir = OMP::Config->getData( 'rawdatadir',
                                 telescope => 'JCMT',
                                 instrument => 'heterodyne',
                                 utdate => $utdate );

    $sub_inst = 'heterodyne';

  } elsif( $instrument =~ /^scuba$/i ) {
    $dir = OMP::Config->getData( 'rawdatadir',
                                 telescope => 'JCMT',
                                 instrument => 'SCUBA',
                                 utdate => $utdate );

    $sub_inst = 'SCUBA';

  } elsif ( $instrument =~ /^scuba-?2$/i ) {
    #throw OMP::Error("file_from_bits: Unable to determine filename for $instrument");
  }

  #  Need to have run number appeneded (as least in case of ACSIS backend).
  my $new_dir;
  try {

    my $cfg = OMP::Config->new;
    my $back = $self->backend() || $instrument;
    $new_dir =
      $cfg->getData( "${back}.rawdatadir",
                      telescope => $cfg->inferTelescope( 'instruments', $instrument),
                      instrument => $back,
                      utdate => $utdate,
                    );
  }
  catch OMP::Error::BadCfgKey with {

    my ( $err ) = @_;

    throw $err
      unless $err =~ /^Key.+could not be found in OMP config system/i;
  };

  return $dir;
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

  @obs = $db->updateObsComment( \@obs );

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

As for the filename() method, can return multiple files
in list context, or the first file in scalar context.

=cut

sub simple_filename {
  my $self = shift;

  # Get the filename(s)
  my @infiles = $self->filename;

  my @outfiles;

  my $scuba_re = qr{^scuba-?2?$}i;

  for my $infile (@infiles) {

    # Get the filename without path
    my $base = basename( $infile );

    if ($self->telescope eq 'JCMT' && $self->instrument !~ $scuba_re
        && uc( $self->backend ) ne 'ACSIS') {

      # Want YYYYMMDD_backend_nnnn.dat
      my $yyyy = $self->startobs->strftime('%Y%m%d');
      $base = $yyyy . '_' . $self->backend .'_' .
          sprintf('%04u', $self->runnr) . '.dat';

    }
    push(@outfiles, $base);
  }

  # Return the simplified filename
  return (wantarray ? @outfiles : shift(@outfiles) );

}

=item B<uniqueid>

Returns a unique ID for the object.

  $id = $object->uniqueid;

=cut

sub uniqueid {
  my $self = shift;

  return if ( ! defined( $self->runnr ) ||
              ! defined( $self->instrument ) ||
              ! defined( $self->telescope ) ||
              ! defined( $self->startobs ) );

  if( uc( $self->backend ) eq 'ACSIS' ) {
    return $self->runnr . $self->backend . $self->telescope . $self->startobs->ymd . $self->startobs->hms;
  }
  return $self->runnr . $self->instrument . $self->telescope . $self->startobs->ymd . $self->startobs->hms;
}

=back

=head2 Private Methods

=over 4

=item B<_defined_fits>

Returns a truth value indicating whether one of L<Astro::FITS::Header>
object or a hash representation of L<Astro::FITS::Header> has been
defined (for the L<OMP::Info::Obs> object).

  $def = $obs->_defined_fits;

=cut

sub _defined_fits {

  my ( $self ) = @_;

  # Poke inside the implementation to avoid infinite recursion.
  return defined $self->{'_fits'}
    || defined $self->{'_hdrhash'};
}

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
  return unless $header;

  my %generic_header = Astro::FITS::HdrTrans::translate_from_FITS($header, frameset => $self->wcs);
  return unless keys %generic_header;

  $self->projectid( $generic_header{PROJECT} );
  $self->checksum( $generic_header{MSBID} );
  $self->msbtid( $generic_header{MSB_TRANSACTION_ID} );
  $self->instrument( uc( $generic_header{INSTRUMENT} ) );

  $self->duration( $generic_header{EXPOSURE_TIME} );
  $self->number_of_coadds( $generic_header{NUMBER_OF_COADDS} );
  $self->disperser( $generic_header{GRATING_NAME} );
  $self->type( $generic_header{OBSERVATION_TYPE} );
  $generic_header{TELESCOPE} =~ /^(\w+)/;
  $self->telescope( uc($1) );
  $self->filename( $generic_header{FILENAME} );
  $self->inst_dhs( $generic_header{INST_DHS} );
  $self->subsystem_idkey( $generic_header{SUBSYSTEM_IDKEY} );

  # Build the Astro::WaveBand object
  if ( defined( $generic_header{GRATING_WAVELENGTH} ) &&
       length( $generic_header{GRATING_WAVELENGTH} ) != 0 ) {
    $self->waveband( new Astro::WaveBand( Wavelength => $generic_header{GRATING_WAVELENGTH},
                                           Instrument => $generic_header{INSTRUMENT} ) );
  } elsif ( defined( $generic_header{FILTER} ) &&
            length( $generic_header{FILTER} ) != 0 ) {
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

  # Easy object modifiers (some of which are used later in the method
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
  $self->velsys( $generic_header{SYSTEM_VELOCITY} );
  $self->nexp( $generic_header{NUMBER_OF_EXPOSURES} );
  $self->chopthrow( $generic_header{CHOP_THROW} );
  $self->chopangle( $generic_header{CHOP_ANGLE} );
  $self->chopsystem( $generic_header{CHOP_COORDINATE_SYSTEM} );
  $self->chopfreq( $generic_header{CHOP_FREQUENCY} );
  $self->rest_frequency( $generic_header{REST_FREQUENCY} );
  $self->cycle_length( $generic_header{CYCLE_LENGTH} );
  $self->number_of_cycles( $generic_header{NUMBER_OF_CYCLES} );
  $self->backend( $generic_header{BACKEND} );
  $self->bandwidth_mode( $generic_header{BANDWIDTH_MODE} );
  $self->filter( $generic_header{FILTER} );
  $self->camera( $generic_header{CAMERA} );
  $self->camera_number( $generic_header{CAMERA_NUMBER} );
  $self->pol( $generic_header{POLARIMETRY} );
  if( defined( $generic_header{POLARIMETER} ) ) {
    $self->pol_in( $generic_header{POLARIMETER} ? 'T' : 'F' );
  } else {
    $self->pol_in( 'unknown' );
  }
  $self->switch_mode( $generic_header{SWITCH_MODE} );
  $self->ambient_temp( $generic_header{AMBIENT_TEMPERATURE} );
  $self->humidity( $generic_header{HUMIDITY} );
  $self->user_az_corr( $generic_header{USER_AZIMUTH_CORRECTION} );
  $self->user_el_corr( $generic_header{USER_ELEVATION_CORRECTION} );
  $self->tile( $generic_header{TILE_NUMBER} );

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

  if (!exists $generic_header{INSTRUMENT}) {
    warnings::warnif "Unable to work out instrument name for observation $generic_header{OBSERVATION_NUMBER}\n";
  }

  if( exists $generic_header{INSTRUMENT} &&
      $generic_header{'INSTRUMENT'} =~ /scuba/i &&
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

# Set the target name.
    $self->target( $generic_header{OBJECT} );

# Arcs, darks and biases don't get coordinates associated with them, since they're
# not really on-sky observations.
    if( ! defined( $self->type ) || ( defined( $self->type ) && $self->type !~ /ARC|DARK|BIAS/ ) ) {

      if( $self->target =~ /MERCURY|VENUS|MARS|JUPITER|SATURN|URANUS|NEPTUNE|PLUTO/ ) {

# Set up a planet coordinate system.
        my $coords = new Astro::Coords( planet => $self->target );
        $self->coords( $coords );
      } elsif ( defined ( $generic_header{COORDINATE_TYPE} ) ) {

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

      if( defined( $self->coords ) ) {
        if( defined( $self->startobs ) ) {
          $self->coords->datetime( $self->startobs );
        }
        if( defined( $self->telescope ) ) {
          $self->coords->telescope( new Astro::Telescope( $self->telescope ) );
        }
      }
    }

    # Set science/scical/gencal defaults.
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
      # BIAS are generic calibrations
      # DARKs are generic calibrations if they have an ARRAY_TESTS-like DR recipe
      # DARK and FLAT and ARC are science calibrations
      my $drrecipe = (exists $generic_header{DR_RECIPE} && defined $generic_header{DR_RECIPE}
                      ? $generic_header{DR_RECIPE} : '');
      if ($self->projectid =~ /CAL$/ ||
          length($self->projectid) == 0 ||
          $self->type =~ /BIAS/ ||
          $drrecipe =~ /ARRAY_TESTS|MEASURE_READNOISE|DARK_AND_BPM/
         ) {
        $self->isGenCal( 1 );
        $self->isScience( 0 );
      } elsif ($self->type =~ /DARK|FLAT|ARC/ ||
               $generic_header{STANDARD}
              ) {
        $self->isSciCal( 1 );
        $self->isScience( 0 );
      }

    } elsif ($self->telescope eq 'JCMT') {
      # SCUBA is done in other branch

      # For ACSIS/SCUBA-2 data we use less guess work
      # A Science observation has OBS_TYPE == science
      # Project id of "jcmt", or "jcmtcal" or "cal" or "deferred obs" (!) == gencal unless STANDARD
      # Standard will have STANDARD==T (isSciCal)

      # fivepoint/focus are generic
      # anything with 'jcmt' or 'jcmtcal' or 'cal' is generic
      # Do not include planets in the list.
      # Standard spectra are science calibrations but we have to be
      # careful with this since they may also be science observations.
      # For now, only check name matches (names should match pointing
      # catalog name exactly) and also that it is a single SAMPLE. Should really
      # be cleverer than that...
      if (( defined( $self->projectid ) && ($self->projectid =~ /JCMT|DEFERRED/i || $self->projectid eq 'CAL') ) ||
          ( defined( $self->mode ) && $self->mode =~ /pointing|fivepoint|focus/i )
         ) {
        $self->isGenCal( 1 );
        $self->isScience( 0 );
      } elsif ($self->mode =~ /sample/i && $self->target =~ /^(w3\(oh\)|l1551\-irs5|crl618|omc1|n2071ir|oh231\.8|irc\+10216|16293\-2422|ngc6334i|g34\.3|w75n|crl2688|n7027|n7538irs1)$/i) {
        # this only occurs on DAS because ACSIS does not have SAMPLE mode
        $self->isSciCal( 1 );
        $self->isScience( 0 );
      } elsif( $self->standard ) {
        # modern data
        $self->isSciCal( 1 );
        $self->isScience( 0 );
      }

    }
  }

  # Remaining generic header
  if ($generic_header{OBSERVATION_ID}) {
    $self->obsid( $generic_header{OBSERVATION_ID} );
  } else {
    my $date_str = $self->startobs->strftime("%Y%m%dT%H%M%S");
    my $instrument = $generic_header{INSTRUMENT} eq 'UKIRTDB' ? $header->{TEMP_INST}
                   : $generic_header{BACKEND} eq 'ACSIS'      ? 'ACSIS'
                   :                                            $generic_header{INSTRUMENT}
                   ;

    $instrument = lc( $instrument );

    my $obsid = $instrument . '_' . $self->runnr . '_' . $date_str;
    $self->obsid( $obsid );
  }

  if( ! $self->retainhdr ) {
    $self->fits( undef );
    $self->hdrhash( undef );
  }

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

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program (see SLA_CONDITIONS); if not, write to the
Free Software Foundation, Inc., 59 Temple Place, Suite 330,
Boston, MA  02111-1307  USA

=cut

1;
