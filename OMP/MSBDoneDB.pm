package OMP::MSBDoneDB;

=head1 NAME

OMP::MSBDoneDB - Manipulate MSB Done table

=head1 SYNOPSIS

  use OMP::MSBDoneDB;

  $db = new OMP::MSBDoneDB( ProjectID => 'm01bu05',
                            DB => new OMP::DBbackend);

  $xml = OMP::MSBServer->historyMSB( $checksum, 'xml');
  $db->addMSBcomment( $checksum, $comment );


=head1 DESCRIPTION

The MSB "done" table exists to allow us to associate user supplied
comments with MSBs that have been observed. It does this by having a
simple logging table where a new row is added each time an MSB is
observed or commented upon.

The existence of this table allows comments for an MSB to be
associated directly with data stored in the data archive (where the
MSB checksum will be stored in the FITS headers). There is no direct
link with the OMP MSB table. This can be thought of as a specialised
MSB Feedback table.

As each MSB comment comes in it is simply added to the table and a
status flag of previous entries is updated (set to false). One wrinkle
is that there is no guarantee that an MSB will still be in the MSB
table (science program) when the trigger to mark the MSB as done is
received (a new science program may have been submitted in the
interim). To overcome this problem a row is added to the table each
time an MSB is retrieved from the system using C<fetchMSB>- this
guarantees that the MSB summary information is available to us since
we simply read the table prior to submitting a new row.

=cut

use 5.006;
use warnings;
use strict;

use OMP::Constants qw/ :done /;
use Time::Piece;

use base qw/ OMP::BaseDB /;

our $VERSION = (qw$Revision$)[1];
our $MSBDONETABLE = "ompmsbdone";

=head1 METHODS

=head2 Public Methods

=over 4

=item B<historyMSB>

Retrieve the observation history for the specified MSB (identified
by checksum and project ID) or project.

  $xml = OMP::MSBServer->historyMSB( $checksum, 'xml');
  $hashref = OMP::MSBServer->historyMSB( $checksum, 'data');
  $arrref  = OMP::MSBServer->historyMSB( '', 'data');

If the checksum is not supplied a full project observation history
is returned. Note that the information retrieved consists of:

 - Target name, waveband and instruments
 - Date of observation or comment
 - Comment associated with action

The XML is retrieved in the following style:

 <msbHistories>
   <msbHistory checksum="yyy" projectid="M01BU53">
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
	   checksum => "xxx",
           projectid => "M01BU53",
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
  my $self = shift;
  my $checksum = shift;
  my $style = shift;

  # Form hash
  my %query;
  $query{checksum} = $checksum if $checksum;
  $query{projectid} = $self->projectid if $self->projectid;
  $query{allinfo} = 1; # want all the information

  # First read the rows from the database table
  # and get the array ref
  my @rows = $self->_fetch_msb_done_info( %query );

  # Now reorganize the data structure to better match
  # our output format
  my $msbs = $self->_reorganize_msb_done( \@rows );

  # Now reformat the data structure to the required output
  # format
  return $self->_format_output_info( $msbs, $checksum, $style);

}

=item B<addMSBcomment>

Add a comment to the specified MSB.

 $db->addMSBcomment( $checksum, $comment );

If the MSB has not yet been observed this command will fail.

Optionally, an object of class C<OMP::MSB> can be supplied as the
third argument. This can be used to extract summary information if the
MSB is not currently in the table. The supplied checksum must match
that of the C<OMP::MSB> object (unless the checksum is not defined).

Additionally, a fourth argument can be supplied specifying the status
of the comment. Default is to treat it as OMP__DONE_COMMENT. See 
C<OMP::Constants> for more information on the different comment
status.

 $db->addMSBcomment( $checksum, $comment, undef, OMP__DONE_FETCH );

=cut

sub addMSBcomment {
  my $self = shift;
  my $checksum = shift;
  my $comment = shift;
  my $msb = shift;
  my $status = shift;

  $self->_store_msb_done_comment( $checksum, $self->projectid, $msb,
				$comment, $status );

}

=item B<observedMSBs>

Return all the MSBs observed (ie "marked as done") on the specified
date. If a project ID has been set only those MSBs observed on the
date for the specified project will be returned.

  $output = $db->observedMSBs( $date, $allcomments, $style );

The C<allcomments> parameter governs whether all the comments
associated with the observed MSBs are returned (regardless of when
they were added) or only those added for the specified night. If the
value is false only the comments for the night are returned.

The output format matches that returned by C<historyMSB>.

If no date is defined the current UT date is used.

=cut

sub observedMSBs {
  my $self = shift;
  my $date = shift;
  my $allcomment = shift;
  my $style = shift;

  # Construct the query 
  my %query;
  $query{date} = $date;
  $query{projectid} = $self->projectid if $self->projectid;
  $query{allinfo} = 1; # want all the information

  # First read the rows from the database table
  # and get the array ref
  my @rows = $self->_fetch_msb_done_info( %query );

  # Now reorganize the data structure to better match
  # our output format
  my $msbs = $self->_reorganize_msb_done( \@rows );

  # If all the comments are required then we now need
  # to loop through this hash and refetch the data
  # using a different query. 
  if ($allcomment) {
    foreach my $checksum (keys %$msbs) {
      # over write the previous entry
      $msbs->{$checksum} = $self->historyMSB($checksum,  'data');
    }
  }

  # Now reformat the data structure to the required output
  # format
  return $self->_format_output_info( $msbs, undef, $style);

}

=back

=head2 Internal Methods

=over 4

=item B<_fetch_msb_done_info>

Retrieve the information from the MSB done table. Can retrieve the
most recent information of all information associated with the MSB.

  %msbinfo = $db->_fetch_msb_done_info( checksum => $sum,
                                         projectid => $proj);

  @allmsbinfo = $db->_fetch_msb_done_info( checksum => $sum,
                                           projectid => $proj,
                                           allinfo => 1);

Project ID is retrieved from the object if none is supplied.
Returns empty list if no rows can be found.

If no checksum is supplied information for all MSBs associated with
the project is retrieved (if C<allinfo> is true, else just the last
one is retrieved). If no checksum and no project ID then all will be
retrieved.

Finally, if C<date> is supplied only those MSBs that were observed
on the specified UT date (ie those with status C<OMP__DONE_DONE>)
will be retrieved. Bear in mind that only comments submitted
on that date will be retrieved. If you want all comments for a particular
MSB then a subsequent targetted query will be required.

=cut

sub _fetch_msb_done_info {
  my $self = shift;
  my %args = @_;

  # Decide whether to retrieve all information or just the last
  my $allinfo = ( exists $args{allinfo} ? $args{allinfo} : 0 );
  delete $args{allinfo} if exists $args{allinfo};

  # Need to remove date field from the list since it
  # is a special case
  my $date;
  if (exists $args{date}) {
    $date = $args{date};
    delete $args{date};

    # Default it to something if not defined
    $date = OMP::General->today() unless $date;
  }

  # Get the project id if it is here
  $args{projectid} = $self->projectid
    if !exists $args{projectid} and defined $self->projectid;

  # Assume that query keys match column names
  my @substrings = map { " $_ = ? " } sort keys %args;

  # and construct the SQL command using bind variables so that 
  # we dont have to worry about quoting
  my $statement = "SELECT * FROM $MSBDONETABLE WHERE" .
    join("AND", @substrings);

  # If we have a date field need to add a bit of extra
  # query
  if ($date) {
    $statement .= " date > '$date' AND date < dateadd(dd,1,'$date') " . 
      " AND status = " . OMP__DONE_DONE();
  }


  # prepare and execute
  my $dbh = $self->_dbhandle;
  throw OMP::Error::DBError("Database handle not valid") unless defined $dbh;

  my $ref = $dbh->selectall_arrayref( $statement, { Columns=>{} },
				      map { $args{$_} } sort keys %args
				    );

  # If they want all the info just return the ref
  # else return the first entry
  if ($ref) {
    if ($allinfo) {
      return @$ref;
    } else {
      my $hashref = (defined $ref->[0] ? $ref->[0] : {});
      return %{ $hashref };
    }
  } else {
    return ();
  }

}

=item B<_add_msb_done_info>

Add the supplied information to the MSB done table and mark all previous
entries as old (status = false).

 $db->_add_msb_done_info( %msbinfo );

where the relevant keys in C<%msbinfo> are:

  checksum - the MSB checksum
  projectid - the project associated with the MSB
  comment   - a comment associated with this action
  instrument,target,waveband - msb summary information

The datestamp is added automatically.

All entries with status OMP__DONE_FETCH and the same
checksum are removed prior to uploading this information. This
is because the FETCH information is really just a placeholder
to guarantee that the information is available and is not
the main purpose of the table.

=cut

sub _add_msb_done_info {
  my $self = shift;
  my %msbinfo = @_;

  # Get the DB handle
  my $dbh = $self->_dbhandle or
    throw OMP::Error::DBError("Database handle not valid");

  # Get the projectid
  $msbinfo{projectid} = $self->projectid
    if (!exists $msbinfo{projectid} and defined $msbinfo{projectid});

  throw OMP::Error::BadArgs("No projectid supplied for add_msb_done_info")
    unless exists $msbinfo{projectid};

  # First remove any placeholder observations
  $dbh->do("DELETE FROM $MSBDONETABLE WHERE checksum = '$msbinfo{checksum}' AND projectid = '$msbinfo{projectid}' AND status = " . OMP__DONE_FETCH)
    or throw OMP::Error::DBError("Error removing placeholder from MSB done table: $DBI::errstr");

  # Now insert the information into the table

  # First get the timestamp
  my $t = gmtime;
  my $date = $t->strftime("%b %e %Y %T");

  # Dummy text for the TEXT field
  my $dummy = "pwned!2";

  # Simply use "do" since there is only a single insert
  # (without the text field)
  $dbh->do("INSERT INTO $MSBDONETABLE VALUES (?,?,?,?,?,?,?,'$dummy')",undef,
	   $msbinfo{checksum}, $msbinfo{status}, $msbinfo{projectid},
	   $date, $msbinfo{target}, $msbinfo{instrument}, $msbinfo{waveband})
    or throw OMP::Error::DBError("Error inserting new MSB done rows: $DBI::errstr");

  # Now the text field
  # Now replace the text using writetext
  $dbh->do("declare \@val varbinary(16)
select \@val = textptr(comment) from $MSBDONETABLE where comment like \"$dummy\"
writetext $MSBDONETABLE.comment \@val '$msbinfo{comment}'")
    or throw OMP::Error::DBError("Error inserting comment into database: ". $dbh->errstr);



}

=item B<_store_msb_done_comment>

Given a checksum, project ID, (optional) MSB object and a comment,
update the MSB done table to contain this information.

If the MSB object is defined the table information will be retrieved
from the object. If it is not defined the information will be
retrieved from the done table (we cannot read it from the MSB table
because that would involve reading the msb and obs table in order to
reconstruct the target and instrument info). An exception is triggered
if the information for the table is not available (this is the reason
why the checksum and project ID are supplied even though, in
principal, this information could be obtained from the MSB object).

  $db->_store_msb_done_comment( $checksum, $proj, $msb, $text );

An optional fifth argument can be used to specify the status of the
message. Default is for the message to be treated as a comment.
This allows you to specify that the comment is associated with
an MSB fetch or a "msb done" action. The OMP__DONE_FETCH is
treated as a special case. If that status is used a row is added
to the table only if no previous information exists for that MSB.
(this prevents lots of entries associated with repeat fetches
but no action).

=cut

sub _store_msb_done_comment {
  my $self = shift;
  my ($checksum, $project, $msb, $comment, $status ) = @_;

  # default to a normal comment
  $status = ( defined $status ? $status : OMP__DONE_COMMENT );

  # check first before writing if required
  # I realise this leads to the possibility of two fetches from
  # the database....
  # If status is OMP__DONE_FETCH then we only want one entry
  # ever so only write it if nothing previously exists
  return if $status == OMP__DONE_FETCH and $self->_fetch_msb_done_info(
								       checksum => $checksum,
								       projectid => $project,
								      );

  # If the MSB is defined we do not need to read from the database
  my %msbinfo;
  if (defined $msb) {

    %msbinfo = $msb->summary;
    $msbinfo{target} = $msbinfo{_obssum}{target};
    $msbinfo{instrument} = $msbinfo{_obssum}{instrument};
    $msbinfo{waveband} = $msbinfo{_obssum}{waveband};

    $checksum = $msb->checksum unless defined $checksum;

    # Compare checksums
    throw OMP::Error::FatalError("Checksum mismatch!")
      if $checksum ne $msb->checksum;

  } else {
    %msbinfo = $self->_fetch_msb_done_info(
					   checksum => $checksum,
					   projectid => $project,
					  );

  }

  # throw an exception if we dont have anything yet
  throw OMP::Error::MSBMissing("Unable to associate any information with the checksum $checksum in project $project") 
    unless %msbinfo;

  # provide a status
  $msbinfo{status} = $status;

  # Add the comment into the mix
  $msbinfo{comment} = ( defined $comment ? $comment : '' );

  # Add this information to the table
  $self->_add_msb_done_info( %msbinfo );


}

=item B<_organize_msb_done>

Given the results from the query (returned as a row per comment)
convert this output to a hash containing one entry per MSB.

  $hashref = $db->_reorganize_msb_done( $query_output );

The resultant data structure is a hash (keyed by checksum)
each pointing to a hash with keys:

  checksum - the MSB checksum (a repeat of the key)
  projectid - the MSB project id
  target
  waveband
  instrument
  comment

C<comment> is a reference to an array containing a reference to a hash
for each comment associated with the MSB. The hash contains the
comment itself (C<text>), the C<date> and the C<status> associated
with that comment.

=cut

sub _reorganize_msb_done {
  my $self = shift;
  my $rows = shift;

  # Now need to go through all the rows forming the
  # data structure (need to organize the data structure
  # before forming the (optional) xml output)
  my %msbs;
  for my $row (@$rows) {

    # see if we've met this msb already
    if (exists $msbs{ $row->{checksum} } ) {

      # Add the new comment
      push(@{ $msbs{ $row->{checksum} }->{comment} }, {
						       text => $row->{comment},
						       date => $row->{date},
						       status => $row->{status},
						      });


    } else {
      # populate a new entry
      $msbs{ $row->{checksum} } = {
				   checksum => $row->{checksum},
				   target => $row->{target},
				   waveband => $row->{waveband},
				   instrument => $row->{instrument},
				   projectid => $row->{projectid},
				   comment => [
					       {
						text => $row->{comment},
						date => $row->{date},
						status => $row->{status},
					       }
					      ],
				  };
    }


  }

  return \%msbs;

}


=item B<_format_output_info>

Format the data structure generated by C<_reorganize_msb_done>
to the format required by the particular user. Options are
"data" (return the data structure with minimal modification) and
"xml" (return an XML string representing the data structure).

  $output = $db->_format_output_info( $hashref, $checksum, $style);

The checksum is provided in case a subset of the data structure
is required. The style governs the output format.

=cut

sub _format_output_info {
  my $self = shift;
  my %msbs = %{ shift() };
  my $checksum = shift;
  my $style = shift;

  # Now form the XML if required
  if ( defined $style && $style eq 'xml' ) {

    # Wrapper element
    my $xml = "<msbHistories>\n";

    # loop through each MSB
    for my $msb (keys %msbs) {

      # If an explicit msb has been mentioned we only want to
      # include that MSB
      if ($checksum) {
	next unless $msb eq $checksum;
      }

      # Start writing the wrapper element
      $xml .= " <msbHistory checksum=\"$msb\" projectid=\"" . $msbs{$msb}->{projectid} 
	. "\">\n";

      # normal keys
      foreach my $key (qw/ instrument waveband target /) {
	$xml .= "  <$key>" . $msbs{$msb}->{$key} . "</$key>\n";
      }

      # Comments
      for my $comment ( @{ $msbs{$msb}->{comment} } ) {
	$xml .= "  <comment>\n";
	for my $key ( qw/ text date status / ) {
	  $xml .= "    <$key>" . $comment->{$key} . "</$key>\n";
	}
	$xml .= "  </comment>\n";
      }

      $xml .= " </msbHistory>\n";

    }

    $xml .= "</msbHistories>\n";

    return $xml;

  } else {
    # The data structure returned is actually an array  when checksum
    # was not defined or a hash ref if it was

    if ($checksum) {

      return $msbs{$checksum};

    } else {

      my @all = map { $msbs{$_} }
	sort { $msbs{$a}{projectid} cmp $msbs{$b}{projectid} } keys %msbs;

      return \@all;


    }

  }
}

=back

=head1 SEE ALSO

This class inherits from C<OMP::BaseDB>.

For related classes see C<OMP::ProjDB> and C<OMP::FeedbackDB>.

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
