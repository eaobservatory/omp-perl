package OMP::MSBServer;

=head1 NAME

OMP::MSBServer - OMP MSB Server class

=head1 SYNOPSIS

    $xml = OMP::MSBServer->fetchMSB($uniqueKey);
    $xmlResults = OMP::MSBServer->queryMSB($xmlQuery, $max);
    OMP::MSBServer->doneMSB($project, $checksum);

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
use Encode qw/encode/;

# OMP dependencies
use OMP::User;
use OMP::DB::User;
use OMP::DB::MSB;
use OMP::Query::MSB;
use OMP::Info::MSB;
use OMP::Info::Comment;
use OMP::Constants qw/:done/;
use OMP::Error qw/:try/;

use Time::HiRes qw/tv_interval gettimeofday/;

# Inherit server specific class
use base qw/OMP::SOAPServer/;

our $VERSION = '2.000';

=head1 METHODS

=over 4

=item B<fetchMSB>

Retrieve an MSB from the database and return it in XML format.

    $xml = OMP::MSBServer->fetchMSB($key);

The key is obtained from a query to the MSB server and is all that
is required to uniquely specify the MSB (the key is the ID string
for <SpMSBSummary> elements).

The MSB is contained in an SpProg element for compatibility with
standard Science Program classes.

Returns nothing is no MSB is found.  Throws I<OMP::Error> exception on
errors.

A second argument controls what form the returned MSB should
take, see the C<OMP::SOAPServer::compressReturnedItem> function
for details.

B<Note>: exposed privately via SOAP by C<msbsrv.pl>.

=cut

sub fetchMSB {
    my $class = shift;
    my ($key, $rettype) = @_;

    my $t0 = [gettimeofday];
    OMP::General->log_message("fetchMSB: Begin.\nKey=$key\n");

    my $msb;
    my $E;
    try {
        # Create a new object but we dont know any setup values
        my $db = OMP::DB::MSB->new(DB => $class->dbConnection);

        $msb = $db->fetchMSB(msbid => $key);
    }
    catch OMP::Error with {
        # Just catch OMP::Error exceptions
        # Server infrastructure should catch everything else
        $E = shift;
    }
    otherwise {
        # This is "normal" errors. At the moment treat them like any other
        $E = shift;

    };
    # This has to be outside the catch block else we get
    # a problem where we cant use die (it becomes throw)
    $class->throwException($E) if defined $E;

    return unless defined $msb;

    # Return stringified form of object
    # Note that we have to make these actual Science Programs
    # so that the OM and Java Sp class know what to do.
    my $spprog = $msb->dummy_sciprog_xml();

    my $converted = $class->compressReturnedItem(
        encode('UTF-8', $spprog), $rettype);

    OMP::General->log_message(sprintf
        "fetchMSB: Complete in %d seconds. Project=%s\nChecksum=%s\n",
        tv_interval($t0), $msb->projectID, $msb->checksum);

    return $converted;
}

=item B<fetchCalProgram>

Retrieve the *CAL project science program from the database.

    $xml = OMP::MSBServer->fetchCalProgram($telescope);

The return argument is an XML representation of the science
program (encoded in base64 for speed over SOAP if we are using
SOAP).

The first argument is the name of the telescope that is
associated with the calibration program to be returned.

A second argument controls what form the returned science program should
take, see the C<OMP::SOAPServer::compressReturnedItem> function
for details.

B<Note>: exposed privately via SOAP by C<msbsrv.pl>.

=cut

sub fetchCalProgram {
    my $class = shift;
    my $telescope = shift;
    my $rettype = shift;

    my $t0 = [gettimeofday];
    OMP::General->log_message(
        "fetchCalProgram: Begin.\nTelescope=$telescope\nFormat=$rettype\n");

    my $sp;
    my $E;
    try {
        # Create new DB object
        my $db = OMP::DB::MSB->new(
            ProjectID => uc($telescope) . 'CAL',
            DB => $class->dbConnection,
        );

        # Retrieve the Science Program object
        $sp = $db->fetchSciProg;
    }
    catch OMP::Error with {
        # Just catch OMP::Error exceptions
        # Server infrastructure should catch everything else
        $E = shift;
    }
    otherwise {
        # This is "normal" errors. At the moment treat them like any other
        $E = shift;

    };
    # This has to be outside the catch block else we get
    # a problem where we cant use die (it becomes throw)
    $class->throwException($E) if defined $E;

    my $converted = $class->compressReturnedItem($sp, $rettype);

    OMP::General->log_message(
        "fetchCalProgram: Complete in " . tv_interval($t0) . " seconds\n");

    return $converted;
}

=item B<queryMSB>

Send a query to the MSB server (encoded as an XML document) and
retrieve results as an XML document consisting of summaries
for each of the matching MSBs.

    XML document = OMP::MSBServer->queryMSB($xml, $max);

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

    <?xml version="1.0" encoding="UTF-8"?>
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

B<Note>: exposed privately via SOAP by C<msbsrv.pl>.

=cut

sub queryMSB {
    my $class = shift;
    my $xmlquery = shift;
    my $maxCount = shift;

    my $t0 = [gettimeofday];
    my $m = (defined $maxCount ? $maxCount : '[undefined]');
    OMP::General->log_message("queryMSB:\n$xmlquery\nMaxcount=$m\n");

    my @results;
    my $E;
    try {
        # Convert the Query to an object
        # Triggers an exception on fatal errors
        my $query = OMP::Query::MSB->new(
            XML => $xmlquery,
            MaxCount => $maxCount,
        );

        # Not really needed if exceptions work
        return '' unless defined $query;

        # Create a new object but we dont know any setup values
        my $db = OMP::DB::MSB->new(DB => $class->dbConnection);

        # Do the query
        @results = $db->queryMSB($query);
    }
    catch OMP::Error with {
        # Just catch OMP::Error exceptions
        # Server infrastructure should catch everything else
        $E = shift;
    }
    otherwise {
        # This is "normal" errors. At the moment treat them like any other
        $E = shift;
    };
    # This has to be outside the catch block else we get
    # a problem where we cant use die (it becomes throw)
    $class->throwException($E) if defined $E;

    # Convert results to an XML document
    my $result;

    try {
        my $tag = "QueryResult";
        my $xmlhead = '<?xml version="1.0" encoding="UTF-8"?>';
        $result = "$xmlhead\n<$tag>\n"
            . join("\n", map {scalar $_->summary('xmlshort')} @results)
            . "\n</$tag>\n";

        OMP::General->log_message(
            "queryMSB: Complete. Retrieved " . @results
            . " MSBs in " . tv_interval($t0) . " seconds\n");
    }
    catch OMP::Error with {
        $E = shift;
    }
    otherwise {
        $E = shift;
    };
    $class->throwException($E) if defined $E;

    $result = SOAP::Data->type(base64 => encode('UTF-8', $result))
        if exists $ENV{'HTTP_SOAPACTION'};

    return $result;
}

=item B<doneMSB>

Mark the specified MSB (identified by project ID and MSB checksum)
as having been observed.

This will have the effect of decrementing the overall observing
counter for that MSB. If the MSB happens to be part of some OR logic
it is possible that the Science program will be reorganized.

    OMP::MSBServer->doneMSB($project, $checksum);

Nothing happens if the MSB can no longer be located since this
simply indicates that the science program has been reorganized
or the MSB modified.

Optionally, a userid and/or reason for the marking as complete
can be supplied:

    OMP::MSBServer->doneMSB($project, $checksum, $userid, $reason);

A transaction ID can also be specified

    OMP::MSBServer->doneMSB($project, $checksum, $userid, $reason, $msbtid);

The transaction ID is a string that should be unique for a particular
instance of an MSB. Userid and reason must be specified (undef is okay)
if a transaction ID is supplied.

A shift type can also be specified:

    OMP::MSBServer->doneMSB($project, $checksum, $userid, $reason, $msbtid, $shifttype);

This is a standard shift name.

An MSB title can also be specified:

    OMP::MSBServer->doneMSB($project, $checksum, $userid, $reason, $msbtid, $shifttype, $msbtitle);

B<Note>: exposed privately via SOAP by C<msbsrv.pl>.

=cut

sub doneMSB {
    my $class = shift;
    my $project = shift;
    my $checksum = shift;
    my $userid = shift;
    my $reason = shift;
    my $msbtid = shift;
    my $shift_type = shift;
    my $msbtitle = shift;

    my $reastr = (defined $reason ? $reason : "<None supplied>");
    my $ustr = (defined $userid ? $userid : "<No User>");
    my $tidstr = (defined $msbtid ? $msbtid : '<No MSBTID>');

    my $t0 = [gettimeofday];
    OMP::General->log_message(
        "doneMSB: Begin.\nProject=$project\nChecksum=$checksum\nUser=$ustr\nReason=$reastr\nMSBTID=$tidstr\n");

    my $E;
    try {
        # Create a comment object for doneMSB
        # We are allowed to specify a user regardless of whether there
        # is a reason
        my $user;
        if ($userid) {
            $user = OMP::User->new(userid => $userid);
            my $userdb = OMP::DB::User->new(DB => $class->dbConnection);
            unless ($userdb->verifyUser($user->userid)) {
                throw OMP::Error::InvalidUser(
                    "The userid [$userid] is not a valid OMP user ID. Please supply a valid id.");
            }
        }

        # We must have a valid user if there is an explicit reason
        if ($reason && ! defined $user) {
            throw OMP::Error::BadArgs(
                "A user ID must be supplied if a reason for the rejection is given");
        }

        # Form the comment object
        my $comment = OMP::Info::Comment->new(
            status => OMP__DONE_DONE,
            text => $reason,
            author => $user,
            tid => $msbtid,
        );

        # Create a new object but we dont know any setup values
        my $db = OMP::DB::MSB->new(
            ProjectID => $project,
            DB => $class->dbConnection);

        # If the shift type and/or msbtitle was defined, create an option hash.
        my %optargs;

        if (defined $shift_type) {
            $optargs{'shifttype'} = $shift_type;
        }

        if (defined $msbtitle) {
            $optargs{'msbtitle'} = $msbtitle;
        }

        # We want to set the option 'notify_first_accept=1' to the
        # OMP::DB::MSB::doneMSB option hash; we will actually check in
        # OMP::DB::MSB::MSBDone to only send that notification if the telescope
        # is JCMT. this is to avoid having to look up the telescope here.
        $optargs{'notify_first_accept'} = 1;

        $db->doneMSB($checksum, $comment, \%optargs);
    }
    catch OMP::Error with {
        # Just catch OMP::Error exceptions
        # Server infrastructure should catch everything else
        $E = shift;
    }
    otherwise {
        # This is "normal" errors. At the moment treat them like any other
        $E = shift;
    };
    # This has to be outside the catch block else we get
    # a problem where we cant use die (it becomes throw)
    $class->throwException($E) if defined $E;

    OMP::General->log_message(
        "doneMSB: $project Complete. " . tv_interval($t0) . " seconds\n");
}

=item B<getResultColumns>

Retrieve the column names that will be used for the XML query
results. Requires a telescope name be provided as single argument.

    $colnames = OMP::MSBServer->getResultColumns($tel);

Returns an array (as a reference).

B<Note>: exposed privately via SOAP by C<msbsrv.pl>.

=cut

sub getResultColumns {
    my $class = shift;
    my $tel = shift;

    my $E;
    my @result;
    try {
        # Create a new object but we dont know any setup values
        @result = OMP::Info::MSB->getResultColumns($tel);
    }
    catch OMP::Error with {
        # Just catch OMP::Error exceptions
        # Server infrastructure should catch everything else
        $E = shift;
    }
    otherwise {
        # This is "normal" errors. At the moment treat them like any other
        $E = shift;
    };
    # This has to be outside the catch block else we get
    # a problem where we cant use die (it becomes throw)
    $class->throwException($E) if defined $E;

    return \@result;
}

=item B<getTypeColumns>

Retrieve the data types associated with the column names that will be
used for the XML query results (as returned by
getResultColumns). Requires a telescope name be provided as single
argument.

    $coltypes = OMP::MSBServer->getTypeColumns($tel);

Returns an array (as a reference).

B<Note>: exposed privately via SOAP by C<msbsrv.pl>.

=cut

sub getTypeColumns {
    my $class = shift;
    my $tel = shift;

    my $E;
    my @result;
    try {
        # Create a new object but we dont know any setup values
        @result = OMP::Info::MSB->getTypeColumns($tel);
    }
    catch OMP::Error with {
        # Just catch OMP::Error exceptions
        # Server infrastructure should catch everything else
        $E = shift;
    }
    otherwise {
        # This is "normal" errors. At the moment treat them like any other
        $E = shift;
    };
    # This has to be outside the catch block else we get
    # a problem where we cant use die (it becomes throw)
    $class->throwException($E) if defined $E;

    return \@result;
}

1;

__END__

=back

=head1 SEE ALSO

OMP document OMP/SN/003.

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
along with this program; if not, write to the
Free Software Foundation, Inc., 59 Temple Place, Suite 330,
Boston, MA  02111-1307  USA

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=cut
