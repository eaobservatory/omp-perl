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
                              fits => 'Astro::FITS::Header',
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
which the values should be displayed.

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
    $return{'UT time'} = $self->startobs->hms;
    $return{'Obsmode'} = $self->mode;
    $return{'Project ID'} = $self->projectid;
    $return{'Object'} = $self->target;
    $return{'Tau225'} = $self->tau;
    $return{'Seeing'} = $self->seeing;
    $return{'Filter'} = $self->waveband->filter;
    $return{'Bolometers'} = $self->bolometers;
    $return{'_ORDER'} = [ "Run", "UT time", "Obsmode", "Project ID", "Object",
                          "Tau225", "Seeing", "Filter", "Bolometers" ];
  } elsif($instrument =~ /ircam/i) {
    $return{'Observation'} = $self->runnr;
    $return{'Group'} = $self->group;
    $return{'Object'} = $self->target;
    $return{'Obstype'} = $self->type;
    $return{'UT start'} = $self->startobs->hms;
    $return{'Exposure time'} = $self->duration;
    $return{'Number of exposures'} = $self->nexp;
    $return{'Mode'} = $self->mode;
    $return{'Speed'} = $self->speed;
    $return{'Filter'} = $self->waveband->filter;
    $return{'Airmass'} = $self->airmass;
    $return{'Columns'} = $self->columns;
    $return{'Rows'} = $self->rows;
    $return{'RA'} = $self->coords->ra;
    $return{'DEC'} = $self->coords->dec;
    $return{'Equinox'} = $self->coords->type;
    $return{'DR Recipe'} = $self->drrecipe;
    $return{'_ORDER'} = [ "Observation", "Group", "Object", "Obstype",
                          "UT start", "Exposure time", "Number of exposures",
                          "Mode", "Speed", "Filter", "Airmass", "Columns",
                          "Rows", "RA", "DEC", "Equinox", "DR Recipe" ];
  } elsif($instrument =~ /cgs4/i) {
    $return{'Observation'} = $self->runnr;
    $return{'Group'} = $self->group;
    $return{'Object'} = $self->target;
    $return{'Standard'} = $self->standard;
    $return{'Observation type'} = $self->type;
    $return{'Slit'} = $self->slitname;
    $return{'Position Angle'} = $self->slitangle;
    $return{'RA offset'} = $self->raoff;
    $return{'Dec offset'} = $self->decoff;
    $return{'UT time'} = $self->startobs->hms;
    $return{'Airmass'} = $self->airmass;
    $return{'Exposure time'} = $self->duration;
    $return{'Number of exposures'} = $self->nexp;
    $return{'Grating'} = $self->grating;
    $return{'Order'} = $self->order;
    $return{'Wavelength'} = $self->waveband->wavelength;
    $return{'DR Recipe'} = $self->drrecipe;
    $return{'_ORDER'} = [ "Observation", "Group", "Object", "Standard",
                          "Observation type", "Slit", "Position Angle",
                          "RA offset", "Dec offset", "UT time", "Airmass",
                          "Exposure time", "Number of exposures", "Grating",
                          "Order", "Wavelength", "DR Recipe" ];
  } elsif($instrument =~ /michelle/i) {
    $return{'Observation'} = $self->runnr;
    $return{'Group'} = $self->group;
    $return{'Object'} = $self->target;
    $return{'Observation type'} = $self->type;
    $return{'UT start'} = $self->startobs->hms;
    $return{'Exposure time'} = $self->duration;
    $return{'Number of exposures'} = $self->nexp;
    $return{'Mode'} = $self->mode;
    $return{'Speed'} = $self->speed;
    $return{'Filter'} = $self->waveband->filter;
    $return{'Airmass'} = $self->airmass;
    $return{'Columns'} = $self->columns;
    $return{'Rows'} = $self->rows;
    $return{'RA'} = $self->coords->ra;
    $return{'DEC'} = $self->coords->dec;
    $return{'Equinox'} = $self->coords->type;
    $return{'DR Recipe'} = $self->drrecipe;
    $return{'Standard'} = $self->standard;
    $return{'Slit'} = $self->slitname;
    $return{'Position Angle'} = $self->slitangle;
    $return{'RA offset'} = $self->raoff;
    $return{'Dec offset'} = $self->decoff;
    $return{'Grating'} = $self->grating;
    $return{'Order'} = $self->order;
    $return{'Wavelength'} = $self->waveband->wavelength;
    $return{'_ORDER'} = [ "Observation", "Group", "Object", "Observation type",
                          "UT start", "Exposure time", "Number of exposures",
                          "Mode", "Speed", "Filter", "Airmass", "Columns",
                          "Rows", "RA", "DEC", "Equinox", "Slit", "Position Angle",
                          "RA offset", "Dec offset", "Grating", "Order",
                          "Wavelength", "DR Recipe" ];
  } elsif($instrument =~ /ufti/i) {
    $return{'Observation'} = $self->runnr;
    $return{'Group'} = $self->group;
    $return{'Object'} = $self->target;
    $return{'Observation type'} = $self->type;
    $return{'UT start'} = $self->startobs->hms;
    $return{'Exposure time'} = $self->duration;
    $return{'Number of exposures'} = $self->nexp;
    $return{'Mode'} = $self->mode;
    $return{'Speed'} = $self->speed;
    $return{'Filter'} = $self->waveband->filter;
    $return{'Airmass'} = $self->airmass;
    $return{'Columns'} = $self->columns;
    $return{'Rows'} = $self->rows;
    $return{'RA'} = $self->coords->ra;
    $return{'DEC'} = $self->coords->dec;
    $return{'Equinox'} = $self->coords->type;
    $return{'DR Recipe'} = $self->drrecipe;
    $return{'_ORDER'} = [ "Observation", "Group", "Object",
                          "Observation type", "UT start", "Exposure time",
                          "Number of exposures", "Mode", "Speed", "Filter",
                          "Airmass", "Columns", "Rows", "RA", "DEC",
                          "Equinox", "DR Recipe" ];
  }

  return %return;

}

=back

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>
Brad Cavanagh E<lt>b.cavanagh@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
