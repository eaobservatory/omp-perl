package OMP::MSBServer;

=head1 NAME

OMP::MSBServer - OMP MSB Server class

=head1 SYNOPSIS

  $xml = OMP::MSBServer->fetchMSB( $uniqueKey );
  @results = OMP::MSBServer->queryMSB( $xmlQuery, $max );
  OMP::MSBServer->doneMSB( $project, $checksum );

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
use OMP::MSBDoneDB;
use OMP::MSBQuery;
use OMP::Error qw/ :try /;

# Inherit server specific class
use base qw/OMP::SOAPServer OMP::DBServer/;

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
    my $db = new OMP::MSBDB(
			    DB => $class->dbConnection
			   );

    $msb = $db->fetchMSB( msbid => $key );

  } catch OMP::Error with {
    # Just catch OMP::Error exceptions
    # Server infrastructure should catch everything else
    $E = shift;

  } otherwise {
    # This is "normal" errors. At the moment treat them like any other
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
    my $db = new OMP::MSBDB(
			    DB => $class->dbConnection
			   );

    # Do the query
    @results = $db->queryMSB( $query );

  } catch OMP::Error with {
    # Just catch OMP::Error exceptions
    # Server infrastructure should catch everything else
    $E = shift;

  } otherwise {
    # This is "normal" errors. At the moment treat them like any other
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
simply indicates that the science program has been reorganized
or the MSB modified.

=cut

sub doneMSB {
  my $class = shift;
  my $project = shift;
  my $checksum = shift;

  my $E;
  try {
    # Create a new object but we dont know any setup values
    my $db = new OMP::MSBDB(ProjectID => $project,
			    DB => $class->dbConnection
			   );

    $db->doneMSB( $checksum );

  } catch OMP::Error with {
    # Just catch OMP::Error exceptions
    # Server infrastructure should catch everything else
    $E = shift;

  } otherwise {
    # This is "normal" errors. At the moment treat them like any other
    $E = shift;

  };
  # This has to be outside the catch block else we get
  # a problem where we cant use die (it becomes throw)
  $class->throwException( $E ) if defined $E;


}

=item B<alldoneMSB>

Mark the specified MSB (identified by project ID and MSB checksum) as
being completely done. This simply involves setting the remaining
counter for the MSB to zero regardless of how many were thought to be
remaining. This is useful for removing an MSB when the required noise
limit has been reached but the PI of the project is not available to
update their science program. The MSB is still present in the science
program.

If the MSB happens to be part of some OR logic
it is possible that the Science program will be reorganized.

  OMP::MSBServer->alldoneMSB( $project, $checksum );

Nothing happens if the MSB can no longer be located since this
simply indicates that the science program has been reorganized
or the MSB modified.

=cut

sub alldoneMSB {
  my $class = shift;
  my $project = shift;
  my $checksum = shift;

  my $E;
  try {
    # Create a new object but we dont know any setup values
    my $db = new OMP::MSBDB(ProjectID => $project,
			    DB => $class->dbConnection
			   );

    $db->alldoneMSB( $checksum );

  } catch OMP::Error with {
    # Just catch OMP::Error exceptions
    # Server infrastructure should catch everything else
    $E = shift;

  } otherwise {
    # This is "normal" errors. At the moment treat them like any other
    $E = shift;

  };
  # This has to be outside the catch block else we get
  # a problem where we cant use die (it becomes throw)
  $class->throwException( $E ) if defined $E;


}

=item B<historyMSB>

Retrieve the observation history for the specified MSB (identified
by checksum and project ID).

  $xml = OMP::MSBServer->historyMSB( $project, $checksum, 'xml');
  $hashref = OMP::MSBServer->historyMSB( $project, $checksum, 'data');
  $arrref  = OMP::MSBServer->historyMSB( $project, '', 'data');

If the checksum is not supplied a full project observation history
is returned. Note that the information retrieved consists of:

 - Target name, waveband and instruments
 - Date of observation or comment
 - Comment associated with action

The XML is retrieved in the following style:

 <msbHistories projectid="M01BU53" projectid="M01BU53">
   <msbHistory checksum="yyy">
     <instrument>UFTI</instrument>
     <waveband>J/H</waveband>
     <target>FS21</target>
     <comment>
       <text>MSB retrieved</text>
       <date>2002-04-02T05:52</date>
     </comment>
     <comment>
       <text>MSB marked as done</text>
       <date>2002-04-02T06:52</date>
     </comment>
   </msbHistory>
   <msbHistory checksum="xxx" projectid="M01BU53">
     ...
   </msbHistory>
 <msbHistories>

When checksum is defined the data structure is of the form:

  $data = {
           projectid => "M01BU53",
           checksum => 'xxx',
           instrument => "UFTI",
           waveband => "J/H",
           target => "FS21",
           comment => [
                       { 
                        text => "MSB retrieved",
                        date => "2002-04-02T05:52"
                       },
                       { 
                        text => "MSB marked as done",
                        date => "2002-04-02T06:52"
                       },
                      ],
  };

When checksum is not defined an array is returned (as a reference in perl)
containing a hash as defined above for each MSB in the project.

=cut

sub historyMSB {
  my $class = shift;
  my $project = shift;
  my $checksum = shift;
  my $type = shift;

  my $E;
  my $result;
  try {
    # Create a new object but we dont know any setup values
    my $db = new OMP::MSBDoneDB(ProjectID => $project,
				DB => $class->dbConnection
			       );

    $result = $db->historyMSB( $checksum, $type );

  } catch OMP::Error with {
    # Just catch OMP::Error exceptions
    # Server infrastructure should catch everything else
    $E = shift;

  } otherwise {
    # This is "normal" errors. At the moment treat them like any other
    $E = shift;

  };
  # This has to be outside the catch block else we get
  # a problem where we cant use die (it becomes throw)
  $class->throwException( $E ) if defined $E;

  return $result;
}

=item B<observedMSBs>

Return all the MSBs observed (ie "marked as done") on the specified
date.

  $output = OMP::MSBServer->observedMSBs( $date, $allcomments, 'xml' );

The C<allcomments> parameter governs whether all the comments
associated with the observed MSBs are returned (regardless of when
they were added) or only those added for the specified night. If the
value is false only the comments for the night are returned.

The output format matches that returned by C<historyMSB>.

If no date is defined (e.g. an empty string is sent) the current UT
date is used.

=cut

sub observedMSBs {
  my $class = shift;
  my $date = shift;
  my $allcomments = shift;
  my $type = shift;

  my $E;
  my $result;
  try {
    # Create a new object but we dont know any setup values
    my $db = new OMP::MSBDoneDB(
				DB => $class->dbConnection
			       );

    $result = $db->observedMSBs( $date, $allcomments, $type );

  } catch OMP::Error with {
    # Just catch OMP::Error exceptions
    # Server infrastructure should catch everything else
    $E = shift;

  } otherwise {
    # This is "normal" errors. At the moment treat them like any other
    $E = shift;

  };
  # This has to be outside the catch block else we get
  # a problem where we cant use die (it becomes throw)
  $class->throwException( $E ) if defined $E;

  return $result;
}

=item B<addMSBcomment>

Associate a comment with a previously observed MSB.

  OMP::MSBServer->addMSBComment( $project, $checksum, $comment );

=cut

sub addMSBcomment {
  my $class = shift;
  my $project = shift;
  my $checksum = shift;
  my $comment = shift;

  my $E;
  my $result;
  try {
    # Create a new object but we dont know any setup values
    my $db = new OMP::MSBDoneDB(ProjectID => $project,
				DB => $class->dbConnection
			       );

    $result = $db->addMSBcomment( $checksum, $comment );

  } catch OMP::Error with {
    # Just catch OMP::Error exceptions
    # Server infrastructure should catch everything else
    $E = shift;

  } otherwise {
    # This is "normal" errors. At the moment treat them like any other
    $E = shift;

  };
  # This has to be outside the catch block else we get
  # a problem where we cant use die (it becomes throw)
  $class->throwException( $E ) if defined $E;

}


=item B<testServer>

Test the server is actually handling requests.

Run with no arguments. Returns 1 if working.

=cut

sub testServer {
  my $class = shift;
  return 1;
}



=back

=head1 SEE ALSO

OMP document OMP/SN/003.

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=cut

1;
