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
use OMP::User;
use OMP::MSBDB;
use OMP::MSBDoneDB;
use OMP::MSBQuery;
use OMP::Info::MSB;
use OMP::Info::Comment;
use OMP::Constants qw/ :done /;
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

  OMP::General->log_message( "fetchMSB: key $key\n");

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
  # One complication is that the format of the XML changed
  # mid stream. We need to put a different heading for each.
  my $spprog = q{<?xml version="1.0" encoding="ISO-8859-1"?>  };
  my $msbxml = "$msb";

  # optionally include the OT version
  my $otvers = '';
  if (defined $msb->ot_version) {
    $otvers = "<ot_version>".$msb->ot_version."</ot_version>\n";
  }

  # Switch on meta_gui
  if ($msbxml =~ /meta_gui/) {
    $spprog .= q{
<SpProg type="pr" subtype="none">
  <meta_gui_filename>ompdummy.xml</meta_gui_filename>
  <meta_gui_hasBeenSaved>true</meta_gui_hasBeenSaved>
  <meta_gui_dir>/tmp</meta_gui_dir>
  <meta_gui_collapsed>false</meta_gui_collapsed>
} . $otvers;
  } else {
    $spprog .= q{
<SpProg>
  <ItemData name="new" package="gemini.sp" subtype="none" type="pr"/>
};
  }

  my $spprogend = "\n</SpProg>\n";

  # Also add in the projectID
  $spprog .= "<projectID>" . $msb->projectID . "</projectID>\n";

  OMP::General->log_message( "fetchMSB: Success: Projectid: " . 
			     $msb->projectID . " and checksum: ".
			     $msb->checksum ."\n");

  return "$spprog$msbxml$spprogend" if defined $msb;
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

  my $m = ( defined $maxCount ? $maxCount : '[undefined]' );
  OMP::General->log_message("queryMSB:\n$xmlquery\nMaxcount=$m\n");

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

Optionally, a userid and/or reason for the marking as complete
can be supplied:

  OMP::MSBServer->doneMSB( $project, $checksum, $userid, $reason );

=cut

sub doneMSB {
  my $class = shift;
  my $project = shift;
  my $checksum = shift;
  my $userid = shift;
  my $reason = shift;

  my $reastr = (defined $reason ? $reason : "<None supplied>");
  my $ustr = (defined $userid ? $userid : "<No User>");
  OMP::General->log_message("doneMSB: $project $checksum User: $ustr Reason: $reastr");

  my $E;
  try {

    # Create a comment object for doneMSB
    # We are allowed to specify a user regardless of whether there
    # is a reason
    my $user;
    if ($userid) {
      $user = new OMP::User( userid => $userid );
      if (!$user->verify) {
	throw OMP::Error::InvalidUser("The userid [$userid] is not a valid OMP user ID. Please supply a valid id.");
      }
    }


    # We must have a valid user if there is an explicit reason
    if ($reason && ! defined $user) {
      throw OMP::Error::BadArgs( "A user ID must be supplied if a reason for the rejection is given");
    }

    # Form the comment object
    my $comment = new OMP::Info::Comment( status => OMP__DONE_DONE,
					  text => $reason,
					  author => $user,
					);

    # Create a new object but we dont know any setup values
    my $db = new OMP::MSBDB(ProjectID => $project,
			    DB => $class->dbConnection
			   );

    $db->doneMSB( $checksum, $comment );

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

=item B<undoMSB>

Mark the specified MSB (identified by project ID and MSB checksum)
as not having been observed.

This will have the effect of incrementing by one the overall observing
counter for that MSB. This method can not reverse OR logic
reorganization triggered by an earlier C<doneMSB> call.

  OMP::MSBServer->undoMSB( $project, $checksum );

Nothing happens if the MSB can no longer be located since this
simply indicates that the science program has been reorganized
or the MSB modified.

=cut

sub undoMSB {
  my $class = shift;
  my $project = shift;
  my $checksum = shift;

  OMP::General->log_message("undoMSB: $project $checksum\n");

  my $E;
  try {
    # Create a new object but we dont know any setup values
    my $db = new OMP::MSBDB(ProjectID => $project,
			    DB => $class->dbConnection
			   );

    $db->undoMSB( $checksum );

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


=item B<suspendMSB>

Cause the MSB to go into a "suspended" state such that the next
time it is translated only some of the files will be sent to
the sequencer.

The "suspended" flag is cleared only when an MSB is marked
as "done".

  OMP::MSBServer->suspendMSB( $project, $checksum, $label );

The label must match the observation labels generated by the
C<unroll_obs> method in C<OMP::MSB>. This label is used by the
translator to determine which observation to start at.

Nothing happens if the MSB can no longer be located since this
simply indicates that the science program has been reorganized
or the MSB modified.

Optionally, a user ID and reason for the suspension can be supplied
(similar to the C<doneMSB> method).

  OMP::MSBServer->suspendMSB( $project, $checksum, $label, $userid,
                              $reason);

Reason is optional. User id is mandatory if a reason is supplied.

=cut

sub suspendMSB {
  my $class = shift;
  my $project = shift;
  my $checksum = shift;
  my $label = shift;
  my $userid = shift;
  my $reason = shift;

  my $reastr = (defined $reason ? $reason : "<None supplied>");
  my $ustr = (defined $userid ? $userid : "<No User>");
  OMP::General->log_message("suspendMSB: $project $checksum $label\n".
			   "User: $ustr Reason: $reastr\n");

  my $E;
  try {

    # Create a comment object for suspendMSB
    # We are allowed to specify a user regardless of whether there
    # is a reason
    my $user;
    if ($userid) {
      $user = new OMP::User( userid => $userid );
      if (!$user->verify) {
	throw OMP::Error::InvalidUser("The userid [$userid] is not a valid OMP user ID. Please supply a valid id.");
      }
    }


    # We must have a valid user if there is an explicit reason
    if ($reason && ! defined $user) {
      throw OMP::Error::BadArgs( "A user ID must be supplied if a reason for the rejection is given");
    }

    # Form the comment object
    my $comment = new OMP::Info::Comment( status => OMP__DONE_DONE,
					  text => $reason,
					  author => $user,
					);


    # Create a new object but we dont know any setup values
    my $db = new OMP::MSBDB(ProjectID => $project,
			    DB => $class->dbConnection
			   );

    $db->suspendMSB( $checksum, $label, $comment );

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

  OMP::General->log_message("alldoneMSB: $project $checksum\n");

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

=item B<rejectMSB>

Indicate that the MSB has been partially observed but has been
rejected by the observer rather than being marked as complete
using C<doneMSB>.

  OMP::MSBServer->rejectMSB( $project, $checksum, $userid, $reason );

This method simply places an entry in the MSB history - it is a
wrapper around addMSBComment method. The optional reason string can be
used to specify a particular reason for the rejection. The userid
is optional unless a reason is supplied (in which case it must be defined
and must match a valid user ID).

=cut

sub rejectMSB {
  my $class = shift;
  my $project = shift;
  my $checksum = shift;
  my $userid = shift;
  my $reason = shift;

  my $reastr = (defined $reason ? $reason : "<None supplied>");
  my $ustr = (defined $userid ? $userid : "<No User>");
  OMP::General->log_message("rejectMSB: $project $checksum User: $ustr Reason: $reastr");

  my $E;
  try {

    # We are allowed to specify a user regardless of whether there
    # is a reason
    my $user;
    if ($userid) {
      $user = new OMP::User( userid => $userid );
      if (!$user->verify) {
	throw OMP::Error::InvalidUser("The userid [$userid] is not a valid OMP user ID. Please supply a valid id.");
      }
    }

    # We must have a valid user if there is an explicit reason
    if ($reason && ! defined $user) {
      throw OMP::Error::BadArgs( "A user ID must be supplied if a reason for the rejection is given");
    }

    # Default comment
    $reason = "This MSB was observed but was not accepted by the observer/TSS. No reason was given."
      unless defined $reason;

    # Add prefix
    $reason = "MSB rejected: $reason";

    # Form the comment object
    my $comment = new OMP::Info::Comment( status => OMP__DONE_REJECTED,
					  text => $reason,
					  author => $user,
					);

    # Add the comment
    OMP::MSBServer->addMSBcomment($project, $checksum, $comment);

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

  return;
}

=item B<historyMSB>

Retrieve the observation history for the specified MSB (identified
by checksum and project ID).

  $xml = OMP::MSBServer->historyMSB( $project, $checksum, 'xml');
  $info = OMP::MSBServer->historyMSB( $project, $checksum, 'data');
  $arrref  = OMP::MSBServer->historyMSB( $project, '', 'data');

If the checksum is not supplied a full project observation history
is returned. Note that the information retrieved consists of:

 - Target name, waveband and instruments
 - Date of observation or comment
 - Comment associated with action

Only "data" and "xml" are understood as valid types.  If "data" is
specified the results are retrieved as either a single
C<OMP::Info::MSB> object or a reference to an array of
C<OMP::Info::MSB> objects. If XML is requested (the default) an XML
string is returned with a wrapper element of SpMSBSummaries and
content matching that generated from C<OMP::Info::MSB> objects.

   <SpMSBSummaries>
     <SpMSBSummary>
       ...
     </SpMSBSummary>
     <SpMSBSummary>
       ...
     </SpMSBSummary>
   </SpMSBSummaries>

=cut

sub historyMSB {
  my $class = shift;
  my $project = shift;
  my $checksum = shift;
  my $type = lc(shift);
  $type ||= 'xml';

  OMP::General->log_message("historyMSB: project:$project, checksum:" .
			    (defined $checksum ? $checksum : "none") ."\n");

  my $E;
  my $result;
  try {
    # Create a new object but we dont know any setup values
    my $db = new OMP::MSBDoneDB(ProjectID => $project,
				DB => $class->dbConnection
			       );

    $result = $db->historyMSB( $checksum );

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

  if ($type eq 'xml') {
    # Generate the XML
    my $xml = "<SpMSBSummaries>\n";
    my @msbs = ( ref($result) eq 'ARRAY' ? @$result : $result );
    for my $msb (@msbs) {
      $xml .= $msb->summary('xml') . "\n";
    }
    $xml .= "</SpMSBSummaries>\n";
    $result = $xml;
  }

  return $result;
}

=item B<observedMSBs>

Return all the MSBs observed (ie "marked as done" or MSBs started) on
the specified date and/or for the specified project.

  $output = OMP::MSBServer->observedMSBs( { date => $date,
					    returnall => 1,
					    format => 'xml',
					    projectid => $proj,
					  } );

The C<returnall> parameter governs whether all the comments
associated with the observed MSBs are returned (regardless of when
they were added) or only those added for the specified night. If the
value is false only the comments for the night are returned.

The output format matches that returned by C<historyMSB>.

If the current date is required use the "usenow" flag:

  $output = OMP::MSBServer->observedMSBs( { usenow => 1,
					    returnall => 1,
					    format => 'xml',
					  } );

At least one of "usenow", "projectid" or "date" must be defined
else the query is too open-ended (and would result in every MSB
ever observed).

Note that the argument is a reference to a hash.

=cut

sub observedMSBs {
  my $class = shift;
  my $args = shift;

  my $type = lc( $args->{format} );
  $type ||= 'xml';
  delete $args->{format};

  # Check basic consistency of arguments
  if (!exists $args->{usenow} && !exists $args->{date} &&
     !exists $args->{projectid}) {
    throw OMP::Error::BadArgs("observedMSBs: Please supply one of usenow, date or projectid");
  }

  # Log message
  my $string;
  my $dstr = (exists $args->{date} ? $args->{date} : "<undef>");
  my $pstr = (exists $args->{projectid} ? $args->{projectid} : "<undef>");
  my $ustr = (exists $args->{usenow} ? $args->{usenow} : "<undef>");
  OMP::General->log_message("observedMSBs: date: $dstr project: $pstr  UseNow: $ustr\n");


  my $E;
  my $result;
  try {

    # Create a new object but we dont know any setup values
    my $db = new OMP::MSBDoneDB(
				DB => $class->dbConnection
			       );

    # Do we have a project?
    $db->projectid( $args->{projectid} )
      if exists $args->{projectid} && defined $args->{projectid};
    delete $args->{projectid};

    $result = $db->observedMSBs( %$args );

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

  if ($type eq 'xml') {
    # Generate the XML
    my $xml = "<SpMSBSummaries>\n";
    my @msbs = ( ref($result) eq 'ARRAY' ? @$result : $result );
    for my $msb (@msbs) {
      $xml .= $msb->summary('xml') . "\n";
    }
    $xml .= "</SpMSBSummaries>\n";
    $result = $xml;
  }


  return $result;
}

=item B<observedDates>

Return an array (as reference) of all dates (in YYYYMMDD format) on
which data for the specified project has been taken.

  $ref = OMP::MSBServer->observedDates( $projectid );

A project ID must be supplied. An optional boolean second argument can
be used to specify that the dates should be returned as C<Time::Piece>
objects (usually only relevant outside of a SOAP environment)

  $ref = OMP::MSBServer->observedDates( $projectid, 1 );

=cut

sub observedDates {
  my $class = shift;
  my $projectid = shift;
  my $useobj = shift;

  my $E;
  my @result;
  try {
    # Create a new object but we dont know any setup values
    my $db = new OMP::MSBDoneDB(
				ProjectID => $projectid,
				DB => $class->dbConnection
			       );

    @result = $db->observedDates($useobj);

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


  return \@result;
}

=item B<queryMSBdone>

Return all the MSBs that match the specified XML query 

  $output = OMP::MSBServer->queryMSBdone( $xml, $allcomments, 'xml' );

The C<allcomments> parameter governs whether all the comments
associated with the matching MSBs are returned (regardless of when
they were added) or only those added for the specific query. If the
value is false only the comments for the query are returned.

The output format matches that returned by C<historyMSB>.

The XML query must match that described in C<OMP::MSBDoneQuery>.

=cut

sub queryMSBdone {
  my $class = shift;
  my $xml = shift;
  my $allcomments = shift;
  my $type = lc(shift);
  $type ||= 'xml';

  OMP::General->log_message("queryMSBdone: xml $xml\n");

  my $E;
  my $result;
  try {
    # Create a new object but we dont know any setup values
    my $db = new OMP::MSBDoneDB(
				DB => $class->dbConnection
			       );

    my $q = new OMP::MSBDoneQuery( XML => $xml );

    $result = $db->queryMSBdone( $q, $allcomments );

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

  if ($type eq 'xml') {
    # Generate the XML
    my $xml = "<SpMSBSummaries>\n";
    my @msbs = ( ref($result) eq 'ARRAY' ? @$result : $result );
    for my $msb (@msbs) {
      $xml .= $msb->summary('xml') . "\n";
    }
    $xml .= "</SpMSBSummaries>\n";
    $result = $xml;
  }


  return $result;
}

=item B<addMSBcomment>

Associate a comment with a previously observed MSB.

  OMP::MSBServer->addMSBcomment( $project, $checksum, $comment );

=cut

sub addMSBcomment {
  my $class = shift;
  my $project = shift;
  my $checksum = shift;
  my $comment = shift;

  # Store the comment text for the log message
  my $text;
  if (UNIVERSAL::isa($comment, "OMP::Info::Comment")) {
    $text = $comment->text;
  } else {
    $text = $comment;
  }

  OMP::General->log_message("addMSBComment: $project $checksum $text\n");

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

=item B<getMSBCount>

Return the total number of MSBs, and the total number of active MSBs, for a
given list of projects.

  %msbcount = OMP::MSBServer->getMsbCount(@projectids);

The only argument is a list (or reference to a list) of project IDs.
Returns a hash of hashes indexed by project ID where the second-level
hashes contain the keys 'total' and 'active' (each points to a number).
If a project has no MSBs, not key is included for that project.  If
a project has no MSBs with remaining observations, no 'active' key
is returned for that project.

=cut

sub getMSBCount {
  my $class = shift;
  my @projectids = (ref($_[0]) eq 'ARRAY' ? @{$_[0]} : @_);

  my $E;
  my %result;
  try {
    # Create a new object but we dont know any setup values
    my $db = new OMP::MSBDB(
			    DB => $class->dbConnection
			   );

    %result = $db->getMSBCount(@projectids);

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

  return %result;
}

=item B<getResultColumns>

Retrieve the column names that will be used for the XML query
results. Requires a telescope name be provided as single argument.

  $colnames = OMP::MSBServer->getResultColumns( $tel );

Returns an array (as a reference).

=cut

sub getResultColumns {
  my $class = shift;
  my $tel = shift;

  my $E;
  my @result;
  try {
    # Create a new object but we dont know any setup values
    @result = OMP::Info::MSB->getResultColumns( $tel );

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

  return \@result;

}

=item B<getTypeColumns>

Retrieve the data types associated with the column names that will be
used for the XML query results (as returned by
getResultColumns). Requires a telescope name be provided as single
argument.

  $coltypes = OMP::MSBServer->getTypeColumns( $tel );

Returns an array (as a reference).

=cut

sub getTypeColumns {
  my $class = shift;
  my $tel = shift;

  my $E;
  my @result;
  try {
    # Create a new object but we dont know any setup values
    @result = OMP::Info::MSB->getTypeColumns( $tel );

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

  return \@result;

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
