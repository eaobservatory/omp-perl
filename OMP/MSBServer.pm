package OMP::MSBServer;

=head1 NAME

OMP::MSBServer - OMP MSB Server class

=head1 SYNOPSIS

  $xml = OMP::MSBServer->fetchMSB( $uniqueKey );
  @results = OMP::MSBServer->queryMSB( $xmlQuery, $max );

=head1 DESCRIPTION

This class provides the public server interface for the OMP MSB
database server. The interface is specified in document
OMP/SN/003.

This class is intended for use as a stateless server. State is
maintained in external databases. All methods are class methods.

=cut

use strict;
use warnings;
use Carp;

# OMP dependencies
use OMP::MSBDB;
use OMP::MSBQuery;
use OMP::Error qw/ :try /;

# Inherit server specific class
use base qw/OMP::SOAPServer/;

our $VERSION = (qw$Revision$)[1];

=head1 METHODS

=over 4

=item B<fetchMSB>

Retrieve an MSB from the database and return it in XML format.

  $xml = OMP::MSBServer->fetchMSB( $key );

The key is obtained from a query to the MSB server and is all that
is required to uniquely specify the MSB (the key is the ID string
for <SpMSBSummary> elements).

The MSB is contained in an SpProg element for compatibility with
standard Science Program classes.

Returns empty string on error (but should raise an exception).

=cut

sub fetchMSB {
  my $class = shift;
  my $key = shift;

  my $msb;
  my $E;
  try {

    # Create a new object but we dont know any setup values
    my $db = new OMP::MSBDB();

    $msb = $db->fetchMSB( id => $key );

  } catch OMP::Error with {
    # Just catch OMP::Error exceptions
    # Server infrastructure should catch everything else
    $E = shift;

  };
  # This has to be outside the catch block else we get
  # a problem where we cant use die (it becomes throw)
  $class->throwException( $E ) if defined $E;

  # Return stringified form of object
  # Note that we have to make these actual Science Programs
  # so that the OM and Java Sp class know what to do.
  my $spprog = q{<?xml version="1.0" encoding="ISO-8859-1"?>
<SpProg>
  <ItemData name="new" package="gemini.sp" subtype="none" type="pr"/>
};
  my $spprogend = "\n</SpProg>\n";

  return "$spprog$msb$spprogend" if defined $msb;
}

=item B<queryMSB>

Send a query to the MSB server (encoded as an XML document) and
retrieve results as an XML document consisting of summaries
for each of the matching MSBs.

  XML document = OMP::MSBServer->queryMSB( $xml, $max );

The query string is described in OMP/SN/003 but looks something like:

  <MSBQuery>
    <tauBand>1</tauBand>
    <seeing>
      <max>2.0</max>
    </seeing>
    <elevation>
      <max>85.0</max>
      <min>45.0</min>
    </elevation>
    <projects>
      <project>M01BU53</project>
      <project>M01BH01</project>
    </projects>
    <instruments>
      <instrument>SCUBA</instrument>
    </instruments>
  </MSBQuery>

The second argument indicates the maximum number of results summaries
to return. If this value is negative all results are returned and if it
is zero then the default number are returned (usually 100).

The format of the resulting document is:

  <?xml version="1.0" encoding="ISO-8859-1"?>
  <QueryResult>
   <SpMSBSummary id="unique">
     <something>XXX</something>
     ...
   </SpMSBSummary>
   <SpMSBSummary id="unique">
     <something>XXX</something>
     ...
   </SpMSBSummary>
   ...
  </QueryResult>

The elements inside C<SpMSBSummary> may or may not relate to
tables in the database.

Throws an exception on error.

=cut

sub queryMSB {
  my $class = shift;
  my $xmlquery = shift;
  my $maxCount = shift;

  my @results;
  my $E;
  try {
    # Convert the Query to an object
    # Triggers an exception on fatal errors
    my $query = new OMP::MSBQuery( XML => $xmlquery,
				   MaxCount => $maxCount,
				 );

    # Not really needed if exceptions work
    return '' unless defined $query;

    # Create a new object but we dont know any setup values
    my $db = new OMP::MSBDB();

    # Do the query
    @results = $db->queryMSB( $query );

  } catch OMP::Error with {
    # Just catch OMP::Error exceptions
    # Server infrastructure should catch everything else
    $E = shift;

  };
  # This has to be outside the catch block else we get
  # a problem where we cant use die (it becomes throw)
  $class->throwException( $E ) if defined $E;

  # Convert results to an XML document
  my $tag = "QueryResult";
  my $xmlhead = '<?xml version="1.0" encoding="ISO-8859-1"?>';
  my $result = "$xmlhead\n<$tag>\n". join("\n",@results). "\n</$tag>\n";

  return $result;
}

=item B<doneMSB>

Mark the specified MSB (identified by project ID and MSB checksum)
as having been observed.

This will have the effect of decrementing the overall observing
counter for that MSB. If the MSB happens to be part of some OR logic
it is possible that the Science program will be reorganized.

  OMP::MSBServer->doneMSB( $project, $checksum );

Nothing happens if the MSB can no longer be located since this
simply indicates that the science program has been reorganized.

=cut

sub doneMSB {
  my $class = shift;
  my $project = shift;
  my $checksum = shift;

  my $E;
  try {
    # Create a new object but we dont know any setup values
    my $db = new OMP::MSBDB(ProjectID => $project );

    $db->doneMSB( $checksum );

  } catch OMP::Error with {
    # Just catch OMP::Error exceptions
    # Server infrastructure should catch everything else
    $E = shift;

  };
  # This has to be outside the catch block else we get
  # a problem where we cant use die (it becomes throw)
  $class->throwException( $E ) if defined $E;


}


=back

=head1 SEE ALSO

OMP document OMP/SN/003.

=head1 COPYRIGHT

Copyright (C) 2001 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=cut

1;
