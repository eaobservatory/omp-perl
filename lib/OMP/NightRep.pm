package OMP::NightRep;

=head1 NAME

OMP::NightRep - Generalized routines to details from a given night

=head1 SYNOPSIS

  use OMP::NightRep;

  $nr = new OMP::NightRep( date => '2002-12-18',
                           telescope => 'jcmt');

  $obs = $nr->obs;
  $faultgroup = $nr->faults;
  $timelost = $nr->timelost;
  @acct = $nr->accounting;
  $weather = $nr->weatherLoss;


=head1 DESCRIPTION

A high-level wrapper around routines useful for generating nightly
activity reports. Provides a means to obtain details of observations
taken on a night, faults occuring and project accounting.

=cut

use strict;
use warnings;
use Carp;
our $VERSION = (qw$ Revision: 1.2 $ )[1];

# CGI classes are only loaded on demand for web applications
# in the ashtml method. Do not use 'use'
use OMP::Error qw/ :try /;
use OMP::Constants;
use OMP::General;
use OMP::DBbackend;
use OMP::DBbackend::Archive;
use OMP::ArchiveDB;
use OMP::ArcQuery;
use OMP::Info::ObsGroup;
use OMP::TimeAcctDB;
use OMP::TimeAcctGroup;
use OMP::TimeAcctQuery;
use OMP::ShiftDB;
use OMP::ShiftQuery;
use OMP::DateTools;
use OMP::FaultDB;
use OMP::FaultQuery;
use OMP::FaultGroup;
use OMP::CommentServer;
use OMP::MSBDoneDB;
use OMP::MSBDoneQuery;
use Time::Piece qw/ :override /;
use Text::Wrap;
use OMP::BaseDB;
use OMP::Display;

# This is the key used to specify warnings in result hashes
use vars qw/ $WARNKEY /;
$WARNKEY = '__WARNINGS__';

=head1 METHODS

=head2 Constructors

=over 4

=item B<new>

Create a new night report object. Accepts a hash argument specifying
the date, delta and telescope to use for all queries.

  $nr = OMP::NightRep->new( telescope => 'JCMT',
                            date => '2002-12-10',
                            delta_day => '7',
                          );

The date can be specified as a Time::Piece object and the telescope
can be a Astro::Telescope object.  Default delta is 1 day.

=cut

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my %args = @_;

  my $nr = bless {
                  DBAccounts => undef,
                  HdrAccounts => undef,
                  Faults => undef,
                  Warnings => [],
                  Telescope => undef,
                  UTDate => undef,
                  UTDateEnd => undef,
                  DeltaDay => 1,
                  DB => undef,
                 },
                 $class;


  # Deal with arguments
  if (@_) {
    my %args = @_;

    # rather than populate hash directly use the accessor methods
    # allow for upper cased variants of keys
    for my $key (keys %args) {
      my $method = lc($key);
      if ($nr->can($method)) {
        $nr->$method( $args{$key} );
      }
    }

  }
  return $nr;
}

=back

=head2 Accessor Methods

=over 4

=item B<date>

Return the date associated with this object. Returns a Time::Piece
object (in UT format).

  $date = $nr->date();
  $nr->date( $date );
  $nr->date( '2002-12-10' );

Accepts a string or a Time::Piece object. The Hours, minutes and seconds
are stripped. The date is assumed to be UT if supplied as a string.
If supplied as an object the local vs UT time can be inferred.

If no date has been specified, the current day will be returned.

If the supplied date can not be parsed as a date, the method will
throw an exception.

=cut

# Defaulting behaviour is dealt with here rather than the constructor
# in case the UT date changes.

sub date {
  my $self = shift;
  if (@_) {
    # parse_date can handle local time
    my $arg = shift;
    my $date = OMP::DateTools->parse_date( $arg );
    throw OMP::Error::BadArgs("Unable to parse $arg as a date")
      unless defined $date;
    $self->{UTDate} = $date;
  }

  if (!defined $self->{UTDate}) {
    return OMP::DateTools->today( 1 );
  } else {
    return $self->{UTDate};
  }
}

=item B<date_end>

Return the end date associated with this object. Returns a Time::Piece
object (in UT format).  If the end date is defined, it, rather than
the B<delta_day> value, will be used when generating the night report.

  $date = $nr->date();
  $nr->date( $date );
  $nr->date( '2002-12-10' );

Accepts a string or a Time::Piece object. The Hours, minutes and seconds
are stripped. The date is assumed to be UT if supplied as a string.
If supplied as an object the local vs UT time can be inferred.

If no date has been specified, the undef value will be returned.

If the supplied date can not be parsed as a date, the method will
throw an exception.

=cut

sub date_end {
  my $self = shift;
  if (@_) {
    # parse_date can handle local time
    my $arg = shift;
    my $date = OMP::DateTools->parse_date( $arg );
    throw OMP::Error::BadArgs("Unable to parse $arg as a date")
      unless defined $date;
    $self->{UTDateEND} = $date;
  }

  return $self->{UTDateEND};
}

=item B<db_accounts>

Return time accounts from the time accounting database. Time accounts
are represented by an C<OMP::TimeAcctGroup> object.

  $acct = $nr->db_accounts();
  $nr->db_accounts( $acct );

Accepts a C<OMP::TimeAcctGroup> object.  Returns undef if no accounts
were retrieved from the time accounting database.

=cut

sub db_accounts {
  my $self = shift;
  if (@_) {
    my $acctgrp = $_[0];
    throw OMP::Error::BadArgs("Accounts must be provided as an OMP::TimeAcctGroup object")
      unless UNIVERSAL::isa($acctgrp, 'OMP::TimeAcctGroup');
    $self->{DBAccounts} = $acctgrp;
  } elsif (! defined $self->{DBAccounts}) {
    # No accounts cached.  Retrieve some
    # Database connection
    my $db = new OMP::TimeAcctDB( DB => $self->db );

    # XML query
    my $xml = "<TimeAcctQuery>".
      $self->_get_date_xml(timeacct=>1) .
        "</TimeAcctQuery>";

    # Get our sql query
    my $query = new OMP::TimeAcctQuery( XML => $xml );

    # Get the time accounting statistics from
    # the TimeAcctDB table. These are returned as a list of
    # Project::TimeAcct.pm objects. Note that there will be more than
    # one per project now that there are multiple shift types etc.

    my @acct = $db->queryTimeSpent( $query );

    # Keep only the results for the telescope we are querying for
    @acct = grep { OMP::ProjServer->verifyTelescope( $_->projectid,
                                                     $self->telescope
                                                   )} @acct;

    # Store result
    my $acctgrp = new OMP::TimeAcctGroup(accounts=>\@acct,
                                         telescope=>$self->telescope,);

    $self->{DBAccounts} = $acctgrp;
  }
  return $self->{DBAccounts};
}

=item B<delta_day>

Return the delta in days (24 hour periods, really) associated with this object.
If B<date_end> is defined, this delta will not be used when generating the night
report.

  $delta = $nr->delta_day();
  $nr->delta_day( 8 );

To retrieve a week long summary a delta of 8 would be used since there are
8 24 hour periods in 7 days.

=cut

sub delta_day {
  my $self = shift;

  if (@_) {
    my $arg = shift;

    $self->{DeltaDay} = $arg;
  }

  return $self->{DeltaDay};
}

=item B<faults>

The faults relevant to this telescope and reporting period.  The faults
are represented by an C<OMP::FaultGroup> object.

  $fault_group = $nr->faults;
  $nr->faults($fault_group);

Accepts and returns an C<OMP::FaultGroup> object.

=cut

sub faults {
  my $self = shift;
  if (@_) {
    my $fgroup = $_[0];
    throw OMP::Error::BadArgs("Must provide faults as an OMP::FaultGroup object")
      unless UNIVERSAL::isa($fgroup, 'OMP::FaultGroup');
    $self->{faults} = $fgroup;
  } elsif (! $self->{faults}) {
    # Retrieve faults from the fault database
    my $fdb = new OMP::FaultDB( DB => $self->db );

    my %xml;
    # We have to do two separate queries in order to get back faults that
    # were filed on and occurred on the reporting dates

    # XML query to get faults filed on the dates we are reaporting for
    $xml{filed} = "<FaultQuery>".
      $self->_get_date_xml() .
        "<category>". $self->telescope ."</category>".
          "<isfault>1</isfault>".
            "</FaultQuery>";

    # XML query to get faults that occurred on the dates we are reporting for
    $xml{actual} = "<FaultQuery>".
      $self->_get_date_xml(tag => 'faultdate') .
        "<category>". $self->telescope ."</category>".
          "</FaultQuery>";

    # Do both queries and merge the results
    my %results;
    for my $xmlquery (keys %xml) {
      my $query = new OMP::FaultQuery( XML => $xml{$xmlquery} );
      my @results = $fdb->queryFaults( $query );

      for (@results) {
        # Use fault date epoch followed by ID for key so that we can
        # sort properly and maintain uniqueness
        if ($xmlquery =~ /filed/) {
          # Don't keep results that have an actual date if they were
          # returned by our "filed on" query
          if (! $_->faultdate) {
            $results{$_->date->epoch . $_->id} = $_;
          }
        } else {
          $results{$_->date->epoch . $_->id} = $_;
        }
      }
    }
    # Convert result hash to array, then to fault group object
    my @results = map {$results{$_}} sort keys %results;
    my $fgroup = new OMP::FaultGroup(faults=>\@results);
    $self->{faults} = $fgroup;
  }
  return $self->{faults};
}

=item B<faultsbyshift>

The faults relevant to this telescope and reporting period, stored in
a hash with keys of the shifttype.  The faults are represented by an
C<OMP::FaultGroup> object.

  $faults_shift = $nr->faultsbyshift;

Returns a hash of C<OMP::FaultGroup> objects. Cannot be used to set
the faults.

=cut

sub faultsbyshift {
  my $self = shift;
  my $faults = $self->faults;
  my @faultlist = $faults->faults;


  # Get all shifttypes
  my @shifttypes = $faults->shifttypes;

  # Create a hash with shifttypes as keys and faults as the objects

  my %resulthash;
  for my $shift (@shifttypes) {
      my @results = grep{ $_->shifttype eq $shift } @faultlist;
      my $fgroup = new OMP::FaultGroup(faults=>\@results);

      # $shift can be an empty string as the database allows Faults to
      # have a NULL shifttype. Therefore convert empty string to
      # UNKNOWN here so time accounting works.
      my $shiftname = $shift;
      if ($shift eq '') {
          $shiftname = 'UNKNOWN';
      }
      $resulthash{$shiftname} = $fgroup;
  }
  return %resulthash;
}


=item B<hdr_accounts>

Return time accounts derived from the data headers.  Time accounts are
represented by an C<OMP::TimeAcctGroup> object.

  $acctgrp = $nr->hdr_accounts();
  $nr->hdr_accounts( $acctgrp );

Accepts an C<OMP::TimeAcctGroup> object.  Returns undef list if no time
accounts could be obtained from the data headers.

=cut

sub hdr_accounts {
  my $self = shift;
  my $method = shift;
  if (@_) {
    my $acctgrp = $_[0];
    throw OMP::Error::BadArgs("Accounts must be provided as an OMP::TimeAcctGroup object")
      unless UNIVERSAL::isa($acctgrp, 'OMP::TimeAcctGroup');
    $self->{HdrAccounts} = $acctgrp;
  } elsif (! defined $self->{HdrAccounts}) {
    # No accounts cached, retrieve some.
    # Get the time accounting statistics from the data headers
    # Need to catch directory not found


    # gets all observations from that night as Omp::Project::TimeAcct
    # objects. These include shifttype and remote.
    my $obsgrp = $self->obs();

    my ($warnings, @acct);
    if ($obsgrp) {
        # locate time gaps > 1 second when calculating statistics.
        $obsgrp->locate_timegaps( 1 );

        # Get one value per shift.
        ($warnings, @acct) = $obsgrp->projectStats('BYSHIFT');

    } else {
        $warnings = [];
    }
    # Store the result
    my $acctgrp = new OMP::TimeAcctGroup(accounts => \@acct);
    $self->{HdrAccounts} = $acctgrp;

    # Store warnings
    $self->warnings($warnings);
  }
  return $self->{HdrAccounts};
}

=item B<telescope>

The telescope to be used for all database queries. Stored as a string
but can be supplied as an Astro::Telescope object.

  $tel = $nr->telescope;
  $nr->telescope( 'JCMT' );
  $nr->telescope( $tel );

=cut

sub telescope {
  my $self = shift;
  if (@_) {
    my $arg = shift;
    if (UNIVERSAL::isa($arg, "Astro::Telescope")) {
      $arg = $arg->name;
    }
    throw OMP::Error::BadArgs( "Bad argument to telescope method: $arg")
      if ref $arg;

    $self->{Telescope} = uc($arg);

  }
  return $self->{Telescope};
}

=item B<db>

A shared database connection (an C<OMP::DBbackend> object). The first
time this is called, triggers a database connection.

  $db = $nr->db;

Takes no arguments.

=cut

sub db {
  my $self = shift;
  if (!defined $self->{DB}) {
    $self->{DB} = new OMP::DBbackend;
  }
  return $self->{DB};
}

=item B<warnings>

Any warnings that were generated as a result of querying the data
headers for time accounting information.

  $warnings = $nr->warnings;
  $nr->warnings(\@warnings);

Accepts an array reference. Returns an array reference.

=cut

sub warnings {
  my $self = shift;
  if (@_) {
    my $warnings = $_[0];
    throw OMP::Error::BadArgs("Warnings must be provided as an array reference")
      unless ref($warnings) eq 'ARRAY';
    $self->{Warnings} = $warnings;
  }
  return $self->{Warnings};
}

=back

=head2 General Methods

=over 4

=item B<accounting>

Retrieve all the project accounting details for the night as a hash.
The keys are projects and for each project there is a hash containing
keys "DATA" and "DB" indicating whether the information comes from the
data headers or the time accounting database directly.
All accounting details are C<OMP::Project::TimeAcct> objects.

Optionally  this can be limited by SHIFTTYPE and by REMOTE status.

Data from the accounting database may or may not be confirmed time.
For data from the data headers the confirmed status is not relevant.

  %details = $nr->accounting;

A special key, "__WARNINGS__" includes any warnings generated by the
accounting query (a reference to an array of strings). See
L<"NOTES">. This key is in the top level hash and is a combination of
all warnings generated.

=cut

sub accounting {
  my $self = shift;

  # Hash for the results
  my %results;

  # Get the time accounting info
  my %db = $self->accounting_db();
  $results{DB} = \%db;

  # Get the info from the headers
  my %hdr = $self->accounting_hdr;
  $results{DATA} = \%hdr;

  # Now generate a combined hash
  my %combo;

  # Assume you have data from multiple shifts. Return $combo{SHIFT/wARNINGKEY}{PROJECT}

  for my $src (qw/ DB DATA /) {
      for my $shift (keys %{ $results{$src} } ) {

          # Special case for warnings
          if ($shift eq $WARNKEY) {
              $combo{$WARNKEY} = [] unless exists $combo{$WARNKEY};
              push(@{ $combo{$WARNKEY} }, @{ $results{$src}->{$shift} });

          } else {
              for my $proj (keys %{ $results{$src}{$shift} } ) {
                  # Store the results in the right place
                  $combo{$shift}{$proj}->{$src} = $results{$src}->{$shift}->{$proj};

              }
          }
      }
  }


  return %combo;

}

=item B<accounting_db>

Return the time accounting database details for each project observed
this night. A hash is returned indexed by project ID and pointing to
the appropriate C<OMP::Project::TimeAcct> object or hash of accounting
information; alternately it can be indexed by shifttype at the top
level then project ID below that.

This is a cut down version of the C<accounting> method that returns
details from all methods of determining project accounting including
estimates.

  %projects = $nr->accounting_db($);
  %projects = $nr->accounting_db($data);

This method takes an optional argument determining the return format. Valid formats are:

    'byproject'- returns a hash of hashes for each project with the
                keys 'pending', 'total' and 'confirmed'

    'byshftprj' - returns a hash of hashes; primary keys are shifttype,
               secondary are projects.. Items in them are OMP::Project::TimeAcct objects.

    'byshftremprj' - returns a hash of hashes, primary keys are combo of
                  shifttype and remote, secondary are project
                  names. Inside that are OMP::Project::TimeAcct
                  objects.

(previuos just took an alternate value that if true returns a hash of
hashes for each project with the keys 'pending', 'total' and 'confirmed'
instead of C<OMP::Project::TimeAcct> objects.

=cut

sub accounting_db {
  my $self = shift;
  my $return_format = shift;

  my $acctgrp = $self->db_accounts;
  my @dbacct = $acctgrp->accounts;

  my %results;


  if ($return_format) {
      # Returning data
      # Combine Time accounting info for a multiple nights.  See documentation
      # for summarizeTimeAcct method in OMP::Project::TimeAcct
      %results = OMP::Project::TimeAcct->summarizeTimeAcct( $return_format, @dbacct)
          unless (! defined $dbacct[0]);
  } else {
    # Returning objects
    #  Convert to a hash with keys shifttype and project [since we can guarantee one instance of a
    # project for a single UT date and project]
    # Ensure we get separate time accts for each shift.
        for my  $acct (@dbacct) {
            $results{ $acct->shifttype }{ $acct->projectid } = $acct;
    }
  }

  return %results;
 }

=item B<accounting_hdr>

Return time accounting statistics generated from the data headers
for this night.

 %details = $nr->accounting_hdr();


Returned as a hash with top level keys of shift types, and second
level keys are project type.

Also returns a reference to an array of warning information generated
by the scan. The keys in the returned hash are project IDs and the
values are C<OMP::Project::TimeAcct> objects. Warnings are returned
as a reference to an array using key "__WARNINGS__" (See L<"NOTES">).

This results in a subset of the information returned by the C<accounting>
method.

=cut

sub accounting_hdr {
  my $self = shift;

  my $acctgrp = $self->hdr_accounts;

  my @hdacct = $acctgrp->accounts;
  my $warnings = $self->warnings;

  # Form a hash
  my %shifts;
  if (@hdacct) {
      for my $acct (@hdacct) {
          $shifts{$acct->shifttype}{$acct->projectid } = $acct;
      }
  }
  $shifts{$WARNKEY} = $warnings;

  return %shifts;
}

=item B<ecTime>

Return the time spent on E&C projects during this reporting period for
this telescope.  That's time spent observing projects associated with
the E&C queue and during non-extended time.

  my $time = $nr->ecTime();

Returns a C<Time::Seconds> object.

=cut

sub ecTime {
  my $self = shift;
  my $dbacct = $self->db_accounts;

  return $dbacct->ec_time;
}

=item B<shutdownTime>

Return the time spent closed, planned or otherwise, during this reporting period
for this telescope.

  my $time = $nr->shutdownTime();

Returns a C<Time::Seconds> object.

=cut

sub shutdownTime {
  my $self = shift;
  my $dbacct = $self->db_accounts;

  return $dbacct->shutdown_time;
}

=item B<obs>

Return the observation details relevant to this telescope, night and
UT date. This will include time gaps. Information is returned as an
C<OMP::Info::ObsGroup> object.

Returns undef if no observations could be located.

=cut

sub obs {
  my $self = shift;

#  my $db = new OMP::ArchiveDB( DB => new OMP::DBbackend::Archive );

  my $db = new OMP::ArchiveDB();

  # XML query to get all observations
  my $xml = "<ArcQuery>".
    "<telescope>". $self->telescope ."</telescope>".
      "<date delta=\"". $self->delta_day ."\">". $self->date->ymd ."</date>".
        "</ArcQuery>";

  # Convert XML to an sql query
  my $query = new OMP::ArcQuery( XML => $xml );

  # Get observations
  my @obs = $db->queryArc( $query, 0, 1 );

  my $grp;
  try {
    $grp = new OMP::Info::ObsGroup( obs => \@obs );
    $grp->commentScan;
  };

  return $grp;
}

=item B<msbs>

Retrieve MSB information for the night and telescope in question.


Information is returned in a hash indexed by project ID and with
values of C<OMP::Info::MSB> objects.

=cut

sub msbs {
  my $self = shift;

  my $db = new OMP::MSBDoneDB( DB => $self->db );

  # Our XML query to get all done MSBs fdr the specified date and delta
  my $xml = "<MSBDoneQuery>" .
    "<status>". OMP__DONE_DONE ."</status>" .
      "<status>" . OMP__DONE_REJECTED . "</status>" .
        "<status>" . OMP__DONE_SUSPENDED . "</status>" .
          "<status>" . OMP__DONE_ABORTED . "</status>" .
            "<date delta=\"". $self->delta_day ."\">". $self->date->ymd ."</date>".
              "</MSBDoneQuery>";

  my $query = new OMP::MSBDoneQuery( XML => $xml );

  my @results = $db->queryMSBdone( $query, { 'comments' => 0 } );

  # Currently need to verify the telescope outside of the query
  # This verification really slows things down
  @results = grep { OMP::ProjServer->verifyTelescope( $_->projectid,
                                                      $self->telescope
                                                    )} @results;

  # Index by project id
  my %index;
  for my $msb (@results) {
    my $proj = $msb->projectid;
    $index{$proj} = [] unless exists $index{$proj};
    push(@{$index{$proj}}, $msb);
  }

  return %index;
}

=item B<scienceTime>

Return the time spent on science during this reporting period for
this telescope.  That's time spent observing projects not
associated with the E&C queue and during non-extended time.

  my $time = $nr->scienceTime();

Returns a C<Time::Seconds> object.

=cut

sub scienceTime {
  my $self = shift;
  my $dbacct = $self->db_accounts;

  return $dbacct->science_time;
}


=item B<shiftComments>

Retrieve all the shift comments associated with this night and
telescope. Entries are retrieved as an array of C<OMP::Info::Comment>
objects.

 @comments = $nr->shiftComments;

=cut

sub shiftComments {
  my $self = shift;

  my $sdb = new OMP::ShiftDB( DB => $self->db );

  my $xml = "<ShiftQuery>".
     "<date delta=\"". $self->delta_day ."\">". $self->date->ymd ."</date>".
       "<telescope>". $self->telescope ."</telescope>".
         "</ShiftQuery>";

  my $query = new OMP::ShiftQuery( XML => $xml );

  # These will have HTML comments
  my @result = $sdb->getShiftLogs( $query );

  return @result;
}

=item B<timelost>

Returns the time lost to faults on this night and telescope.
The time is returned as a Time::Seconds object.  Timelost to
technical or non-technical faults can be returned by calling with
an argument of either "technical" or "non-technical."  Returns total
timelost when called without arguments.

=cut

sub timelost {
  my $self = shift;
  my $arg = shift;
  my $faults = $self->faults;
  return undef
    unless defined $faults;
  if ($arg) {
    if ($arg eq "technical") {
      return $faults->timelostTechnical;
    } elsif ($arg eq "non-technical") {
      return $faults->timelostNonTechnical;
    }
  } else {
    return ($faults->timelost ? $faults->timelost : new Time::Seconds(0));
  }
}
=item B<timelostbyshift>

Returns the time lost to faults on this night and telescope.
The time is returned as a Time::Seconds object.  Timelost to
technical or non-technical faults can be returned by calling with
an argument of either "technical" or "non-technical."  Returns total
timelost when called without arguments.

=cut

sub timelostbyshift {
  my $self = shift;
  my $arg = shift;
  my %faults = $self->faultsbyshift;

  return undef
    unless %faults;

  my %results;
  my $res;
  for my $shift (keys %faults) {
      my $shiftfaults = $faults{$shift};

      if ($arg && $arg eq "technical") {
          $res = $shiftfaults->timelostTechnical ? $shiftfaults->timelostTechnical : new Time::Seconds(0);
          $results{$shift} = $res;

      } elsif ($arg && $arg eq "non-technical") {
          $res = $shiftfaults->timelostNonTechnical ? $shiftfaults->timelostNonTechnical : new Time::Seconds(0);
          $results{$shift} = $res;

      } else {
          $res = $shiftfaults->timelost ? $shiftfaults->timelost : new Time::Seconds(0);
          $results{$shift} = $res;
      }
  }
  return %results;
}
=item B<timeObserved>

Return the time spent observing on this night.  That's everything
but time lost to weather and faults, and time spent doing "other"
things.

  my $time = $nr->timeObserved();


Returns a C<Time::Seconds> object.

=cut

sub timeObserved {
  my $self = shift;
  my $dbacct = $self->db_accounts;

  return $dbacct->observed_time
}

=item B<totalTime>

Return total for all time accounting information.

  my $time = $nr->totalTime();

Returns a C<Time::Seconds> object.

=cut

sub totalTime {
  my $self = shift;
  my $dbacct = $self->db_accounts;

  return $dbacct->totaltime;
}

=item B<weatherLoss>

Return the time lost to weather during this reporting period for
this telescope.

  my $time = $nr->weatherLoss();

Returns a C<Time::Seconds> object.

=cut

sub weatherLoss {
  my $self = shift;
  my $dbacct = $self->db_accounts;

  return $dbacct->weather_loss;
}

=back

=head2 Summarizing

=over 4

=item B<astext>

Generate a plain text summary of the night.

  $text = $nr->astext;

In scalar context returns a single string. In list context returns
a collection of lines (without newlines).

=cut

sub astext {
  my $self = shift;

  my $tel  = $self->telescope;
  my $date = $self->date->ymd;

  my @lines;

  # The start
  my $str = qq{

    Observing Report for $date at the $tel

};

  #   T I M E   A C C O U N T I N G

  # Get shifts from time accounting and from timelostbyshift.
  my %times = $self->accounting;

  my %timelostbyshift = $self->timelostbyshift;

  my @shifts;
  for my $key (keys %times){
      unless(!defined $key  || $key eq '' || $key eq $WARNKEY) {
          push @shifts, $key;
      }
  }

  # Only include faultshifts if time was charged.
  my @faultshifts = (keys %timelostbyshift);
  for my $shift (@faultshifts) {
      my $losttime = $timelostbyshift{$shift};
      if((! exists($times{$shift}) ) && ($shift ne '') && ($losttime > 0)) {
          push @shifts, $shift;
      }
  }

  my $shiftcount = scalar @shifts;

  $str .= "There were shiftypes of ";
  for my $shift(@shifts) {
      $str .= "$shift ";
  }
  $str .= "in this timeperiod\n";
  $str .= "\n\n";
  $str .= "Overall Project Time Summary\n\n";
  my $format = "  %-25s %5.2f hrs   %s\n";

  # Just do project accounting
  my %acct = $self->accounting_db();

  # Get closed time
  my $shuttime = $self->shutdownTime;

  # Convert shutdown time to hours, we won't ever want to see seconds.
  $shuttime = $shuttime->hours;

  # Weather and Extended and UNKNOWN and OTHER
  my %text = ( WEATHER => "Time lost to weather:",
               OTHER   =>  "Other time:",
               EXTENDED => "Extended Time:",
               CAL      => "Calibrations:",
      );

  # 1. Get total time overall for all shifts.
  if ($shiftcount > 1) {

      my %overallresults = $self->accounting_db("byproject");

      # Total time
      my $total = 0.0;
      my $totalobserved = 0.0; # Total time spent observing
      my $totalproj = 0.0;


      # Add shutdown time to total
      $total += $shuttime;

      # Time lost to faults
      my $faultloss = $self->timelost->hours;
      $str .= sprintf("$format", "Time lost to faults:", $faultloss, "");
      $total += $faultloss;

      for my $proj (qw/ WEATHER OTHER EXTENDED CAL /) {
          my $time = 0.0;
          if (exists $overallresults{$tel.$proj}) {
              $time = $overallresults{$tel.$proj}{'total'}->hours;
              $total += $time unless $proj eq 'EXTENDED';
              $totalobserved += $time unless $proj =~ /^(OTHER|WEATHER)$/;
          }
          $str .= sprintf("$format", $text{$proj}, $time);
      }

      for my $proj (keys %overallresults) {
          next if $proj =~ /^$tel/;
          $str .= sprintf("$format", $proj.':', $overallresults{$proj}{'total'}->hours,);
          $total += $overallresults{$proj}{'total'}->hours;
          $totalobserved += $overallresults{$proj}{'total'}->hours;
          $totalproj += $overallresults{$proj}{'total'}->hours;
      }

      if ($shuttime) {
          $str .= "\n";
          $str .= sprintf($format, "Closed time:", $shuttime, '');
      }
      $str .= "\n";
      $str .= sprintf($format, "Project time", $totalproj, "");
      $str .= "\n";
      $str .= sprintf($format, "Total time observed:", $totalobserved, "");
      $str .= "\n";
      $str .= sprintf($format, "Total time:", $total, "");
      $str .= "\n";
  }


  # Now get time by shift if there was more than one type of shift.


  for my $shift (@shifts) {

      if ($shiftcount > 1) {
          $str .= "\n";
          $str .="$shift summary\n\n";
      }
      # Total time
      my $total = 0.0;
      my $totalobserved = 0.0; # Total time spent observing
      my $totalproj = 0.0;
      my $comment;
      if (exists $timelostbyshift{$shift}) {
          my $faultloss = $timelostbyshift{$shift}->hours;
          $str .= sprintf("$format", "Time lost to faults:", $faultloss);
          $total += $faultloss;
      }

      for my $proj (qw/ WEATHER OTHER EXTENDED CAL /) {

          my $time = 0.0;
          if (exists $acct{$shift}{$tel.$proj}) {

              $time = $acct{$shift}{$tel.$proj}->timespent->hours;
              $comment = $acct{$shift}{$tel.$proj}->comment;
              $total += $time unless $proj eq 'EXTENDED';
              $totalobserved += $time unless $proj =~ /^(OTHER|WEATHER)$/;
          }
          if ($time > 0 || (defined $comment)) {
              $str .= sprintf("$format", $text{$proj}, $time, $comment);
          }
      }

      for my $proj (keys %{$acct{$shift}}) {
          next if $proj =~ /^$tel/;
          $comment = $acct{$shift}{$proj}->comment;
          $str .= sprintf("$format", $proj.':', $acct{$shift}{$proj}->timespent->hours, $comment);
          $total += $acct{$shift}{$proj}->timespent->hours;
          $totalobserved += $acct{$shift}{$proj}->timespent->hours;
          $totalproj += $acct{$shift}{$proj}->timespent->hours;
      }

      if ($shuttime) {

          if (exists $acct{$shift}{$tel.'_SHUTDOWN'}) {
              my $shiftshuttime = $acct{$shift}{$tel.'_SHUTDOWN'}->timespent->hours;
              if ($shiftshuttime > 0) {
                  $str .= sprintf($format, "Closed time:", $shiftshuttime);
              }
              # Add shutdown time to total
              $total += $shiftshuttime;
              }
      }
      $str .= "\n";
      $str .= sprintf($format, "Project time", $totalproj);
      $str .= "\n";
      $str .= sprintf($format, "Total time observed:", $totalobserved);
      $str .= "\n";
      $str .= sprintf($format, "Total time:", $total);
      $str .= "\n";

  }


  # M S B   S U M M A R Y
  # Add MSB summary here
  $str .= "Observation summary\n\n";

  my %msbs = $self->msbs;

  for my $proj (keys %msbs) {
      $str .= "  $proj\n";
      for my $msb (@{$msbs{$proj}}) {
          $str .= sprintf("    %-30s %s    %s", substr($msb->targets,0,30),
                          $msb->wavebands, $msb->title). "\n";
      }
  }
  $str .= "\n";

  # Fault summary
  my @faults = $self->faults->faults;

  $str .= "Fault Summary\n\n";

  if (@faults) {
    for my $fault (@faults) {
      my $date = $fault->date;
      my $local = localtime($date->epoch);
      $str.= sprintf qq[  %s [%s] %s (%s hrs lost)\n],
                ( $fault->faultid() || '(No Fault ID)' ),
                $local->strftime( '%H:%M %Z' ),
                ( $fault->subject() || '(No Subject)' ),
                $fault->timelost()
                ;

    }
  } else {
    $str .= "  No faults filed on this night.\n";
  }

  $str .= "\n";

  # Shift log summary
  $str .= "Comments\n\n";

  my @comments = $self->shiftComments;
  $Text::Wrap::columns = 72;

  for my $c (@comments) {
    # Use local time
    my $date = $c->date;
    my $local = localtime( $date->epoch );
    my $author = $c->author() ? $c->author()->name() : '(Unknown Author)' ;

    # Get the text and format it as plain text from HTML
    my $text = $c->text;
    $text =~ s/\t/ /g;
    # We are going to use 'wrap' to indent by 4 and then wrap
    # to 72, so have html2plain use a smaller width to try to
    # avoid wrapping the same text twice.
    $text = OMP::Display->html2plain( $text, {rightmargin => 64} );

    # Word wrap (but do not "fill")
    $text = wrap("    ","    ",$text);

    # Now print the timestamped comment
    $str .= "  ".$local->strftime("%H:%M:%S %Z") . ": $author\n";
    $str .= $text ."\n\n";
  }

  # Observation log
  $str .= "Observation Log\n\n";

  my $grp = $self->obs;
  $grp->locate_timegaps( OMP::Config->getData("timegap") );
  my $tmp = $grp->summary('72col');
  $str   .= defined $tmp ? $tmp : '' ;

  if (wantarray) {
    return split("\n", $str);
  }
  return $str;
}


=item B<projectsummary_ashtml>

Optionally do for a specific shift.
=cut

sub projectsummary_ashtml {
    my $self = shift;
    my $showcomment = shift;
    my $shift = shift;


    my $tel  = $self->telescope;
    my $date = $self->date->ymd;
    my $format = "%5.2f hrs\n";

    my $ompurl = OMP::Config->getData('cgidir');

    # T i m e  A c c o u n t i n g
    # Get shifts from time accounting and from timelostbyshift.



    my $total = 0.0;
    my $total_pending = 0.0;
    my $total_proj = 0.0; # Time spent on projects only


    my $shuttime = 0.0;
    my $title;
    my $faultloss = 0.0;
    my $technicalloss = 0.0;
    my $nontechnicalloss = 0.0;
    my %acct;
    my %fullact;
    if ($showcomment) {
        %fullact = $self->accounting_db();
    }
    my %shiftacct;

    # If $shift is not defined, then just do overall.
    if (! defined $shift) {

        %acct = $self->accounting_db('byproject');
        $shuttime = $self->shutdownTime->hours;
        $title = 'Overall';
        $faultloss = $self->timelost->hours;
        $technicalloss = $self->timelost('technical')->hours;
        $nontechnicalloss = $self->timelost('non-technical')->hours;
    } else {

        # Get full information


        # Go through only for that shift.
        my %times = $self->accounting_db('byshftprj');
        if (exists($times{$shift})) {
            %acct = %{$times{$shift}};
        } else {
            %acct = ();
        }


        if (exists ($fullact{$shift})) {
            %shiftacct = %{$fullact{$shift}};
        } else {
            %shiftacct = ();
        }


        if (exists($acct{$tel.'_SHUTDOWN'})) {
            $shuttime = $acct{$tel.'_SHUTDOWN'}->timespent->hours;
        }
        my %timelost = $self->timelostbyshift;
        if (exists($timelost{$shift})) {
            $faultloss = $timelost{$shift}->hours;
        }
        %timelost = $self->timelostbyshift('technical');
        if (exists($timelost{$shift})) {
            $technicalloss = $timelost{$shift}->hours;
        }
        %timelost = $self->timelostbyshift('non-technical');
        if (exists($timelost{$shift})) {
            $nontechnicalloss = $timelost{$shift}->hours;
        }
        $title = $shift;
    }

    # Format table
    print "<table class='sum_table' cellspacing='0' width='600'>";
    print "<tr class='sum_table_head'>";
    print "<td colspan='4'><strong class='small_title'>$title Project Time Summary</strong></td>";

    # Closed time (if any)
    if ($shuttime) {
        print "<tr class='sum_other'>";
        print "<td>Closed</td>";
        print "<td colspan='2'>". sprintf($format, $shuttime) . "</td><td/>";
        print "</tr>";

        $total += $shuttime;
    }

    # Time lost to faults.
    print "<tr class='sum_other'>";
    print "<td>Time lost to technical faults</td>";
    print "<td colspan=2>" . sprintf($format, $technicalloss) . "</td><td/>";
    print "<tr class='sum_other'>";
    print "<td>Time lost to non-technical faults</td>";
    print "<td colspan=2>" . sprintf($format, $nontechnicalloss) . "</td><td/>";
    print "<tr class='sum_other'>";
    print "<td>Total time lost to faults</td>";
    print "<td>" . sprintf($format, $faultloss) . " </td><td><a href='#faultsum' class='link_dark'>Go to fault summary</a></td><td/>";

     $total += $faultloss;

    # Time lost to weather, extended accounting.
      my %text = (
              WEATHER => "<tr class='proj_time_sum_weather_row'><td>Time lost to weather</td>",
              EXTENDED => "<tr class='proj_time_sum_extended_row'><td>Extended Time</td>",
              OTHER => "<tr class='proj_time_sum_other_row'><td>Other Time</td>",
              CAL => "<tr class='proj_time_sum_weather_row'><td>Calibrations</td>",
             );

    for my $proj (qw/WEATHER OTHER EXTENDED CAL/) {
        my $time = 0.0;
        my $pending;
        my $comment;
        if (exists $acct{$tel.$proj}) {
            $time = $acct{$tel.$proj}->{total}->hours;
            if ($acct{$tel.$proj}->{pending}) {
                $pending += $acct{$tel.$proj}->{pending}->hours;
            }
            $total += $time unless $proj eq 'EXTENDED';
            if ($showcomment) {
                if (exists $shiftacct{$tel.$proj}) {
                    $comment = $shiftacct{$tel.$proj}->{Comment};
                }
            }
        }
        print "$text{$proj}<td>" . sprintf($format, $time);
        if ($pending) {
            print " [unconfirmed]";
        }
        print "<td>$comment</td><td></td>";
    }

    # Sort project accounting by country
    my %acct_by_country;
    for my $proj (keys %acct) {

        next if $proj =~ /^$tel/;

        # No determine_country method exists, so we'll get project
        # details instead
        my $details = OMP::ProjServer->projectDetails($proj, "object");

        $acct_by_country{$details->country}{$proj} = $acct{$proj};
    }

    # Project Accounting
    my $bgcolor = "a";
    for my $country (sort keys %acct_by_country) {

        # Get country total timespent
        my $country_total;
        for (keys %{$acct_by_country{$country}}) {
            $country_total += $acct_by_country{$country}{$_}->{total}->hours
        }

        my $rowcount = 0;

        for my $proj (sort keys %{$acct_by_country{$country}}) {
            $rowcount++;

            my $account = $acct_by_country{$country}{$proj};
            $total += $account->{total}->hours;
            $total_proj += $account->{total}->hours;

            my $pending;
            if  ($account->{pending}) {
                $total_pending += $account->{pending}->hours;
                $pending = $account->{pending}->hours;
            }
            my $comment;
            if ($showcomment) {
                if (exists $shiftacct{$proj}) {
                    $comment = $shiftacct{$proj}->{Comment};
                }
            }
            print "<tr class='row_$bgcolor'>";
            print "<td><a href='$ompurl/projecthome.pl?project=$proj' class='link_light'>$proj</a></td><td>";
            printf($format, $account->{total}->hours);
            print " [unconfirmed]" if ($pending);
            print "</td>";
            if ($self->delta_day != 1) {
                if ($rowcount == 1) {
                    print "<td>$comment</td><td class=country_$country>$country ". sprintf($format, $country_total) ."</td>";
                } else {
                    print "<td>$comment</td><td class=country_$country></td>";
                }
            } else {
                print "<td>$comment</td><td></td>";
            }

            # Alternate background color
            ($bgcolor eq "a") and $bgcolor = "b" or $bgcolor = "a";
        }
    }

    print "<tr class='row_$bgcolor'>";
    print "<td class='sum_other'>Total</td><td colspan=2 class='sum_other'>". sprintf($format,$total);

    # Print total unconfirmed if any
    print " [". sprintf($format, $total_pending) . " of which is unconfirmed]"
        if ($total_pending > 0);

    print "</td><td></td>";

    # Print total time spent on projects alone
    print "<tr class='row_$bgcolor'>";
    print "<td class='sum_other'>Total time spent on projects</td><td colspan=2 class='sum_other'>".
        sprintf($format, $total_proj).
        "</td><td></td>";

    # Get clear time
    my $cleartime = $total - $shuttime;
    $cleartime -= $acct{$tel.'WEATHER'}->{total}->hours
        if exists $acct{$tel.'WEATHER'};

    if ($cleartime > 0) {
        print "<tr class='proj_time_sum_weather_row'>";
        print "<td class='sum_other'>Clear time lost to faults</td><td colspan=2 class='sum_other'>". sprintf("%5.2f%%", $faultloss / $cleartime * 100) ." </td><td></td>";
        print "<tr class='proj_time_sum_other_row'>";
        print "<td class='sum_other'>Clear time lost to technical faults</td><td colspan=2 class='sum_other'>". sprintf("%5.2f%%", $technicalloss / $cleartime * 100) ." </td><td></td>";
    }

    print "</table>";
    print "<p>";
}

=item B<ashtml>

Generate a summary of the night formatted using HTML.

  $nr->ashtml();

This method takes an optional hash argument with the following keys:

=over 4

=item *

worfstyle - Write WORF links to the staff WORF page. Can be either
'staff', 'none', or 'project', and will default to 'project'.

=item *

commentstyle - Write observation comment links to the staff-only page. Can
be either 'staff' or 'project', and will default to 'project'.

=back

=cut

sub ashtml {
  my $self = shift;
  my %options = @_;

  # Check the options.
  my $worfstyle;
  my $worflink;
  if( exists( $options{worfstyle} ) && defined( $options{worfstyle} ) &&
      lc( $options{worfstyle} ) eq 'staff' ) {
    $worfstyle = 'staff';
    $worflink = 'staffworfthumb.pl';
  } elsif ( exists( $options{worfstyle} ) && defined( $options{worfstyle} ) &&
              lc( $options{worfstyle} ) eq 'none' ) {
      $worfstyle = 'none';
      $worflink = '';
  } else {
    $worfstyle = 'project';
    $worflink = 'fbworfthumb.pl';
  }

  my $commentstyle;
  if( exists( $options{commentstyle} ) && ( defined( $options{commentstyle} ) ) &&
      lc( $options{commentstyle} ) eq 'staff' ) {
    $commentstyle = 'staff';
  } else {
    $commentstyle = 'project';
  }

  # Need to load CGI specified classes
  require OMP::CGIComponent::Obslog;
  require OMP::CGIComponent::Shiftlog;


  my $tel  = $self->telescope;
  my $date = $self->date->ymd;

  my $total = 0.0;
  my $total_pending = 0.0;
  my $total_proj = 0.0; # Time spent on projects only

  my $ompurl = OMP::Config->getData('cgidir');

  if ($worfstyle ne 'none') {
      print "<a href='$worflink?ut=$date&telescope=$tel'>View WORF thumbnails</a><br>";
  }

  if ($self->delta_day < 14) {
    print "<a href='#faultsum'>Fault Summary</a><br>";
    print "<a href='#shiftcom'>Shift Log Comments</a> / <a href=\"shiftlog.pl?date=$date&telescope=$tel\">Add shift log comment</a><br>";
    print "<a href='#obslog'>Observation Log</a><br>";
    print "<p>";
  }

  my $showcomment = 1;
  if ($self->delta_day > 1) {
      $showcomment = 0;
  }
  # T i m e A c c o u n t i n g


  #Get shifts from time accounting database. and from timelostbyshift.

  # HTML version does not show any times from the headers, so no need
  # to ever get them. Just get the accounting_db stuff.
  my %times = $self->accounting_db;

  my %timelostbyshift = $self->timelostbyshift;

  my @shifts;
  for my $key (keys %times){
      unless(!defined $key  || $key eq '' || $key eq $WARNKEY) {
          push @shifts, $key;
      }
  }
  # Only include faultshifts if time was charged.
  my @faultshifts = (keys %timelostbyshift);
  for my $shift (@faultshifts) {
      my $losttime = $timelostbyshift{$shift};
      if((! exists($times{$shift}) ) && ($shift ne '') && ($losttime > 0)) {
          push @shifts, $shift;
      }
  }

  # First of all do overall per night.
  print "<p> There were shiftypes of ";
  for my $shift(@shifts) {
      print "$shift ";
  }
  print "in this timeperiod.</p>";

  $self->projectsummary_ashtml;


  # Now do it per shift.
  if (@shifts > 1) {
      for my $shift (@shifts) {
         $self->projectsummary_ashtml($showcomment, $shift);
      }
  }
  if ($self->delta_day < 14) {
    # M S B  S u m m a r y
    # Get observed MSBs
    my %msbs = $self->msbs;

    # Decide whether to show MSB targets or MSB name
    my $display_msb_name = OMP::Config->getData( 'msbtabdisplayname',
                                                 telescope => $self->telescope,);
    my $alt_msb_column = ($display_msb_name ? 'Name' : 'Target');

    print "<table class='sum_table' cellspacing='0' width='600'>";
    print "<tr class='sum_table_head'><td colspan=5><strong class='small_title'>MSB Summary</strong></td>";

    for my $proj (keys %msbs) {
      print "<tr class='sum_other'><td><a href='$ompurl/msbhist.pl?project=$proj' class='link_dark'>$proj</a></td>";
      print "<td>$alt_msb_column</td><td>Waveband</td><td>Instrument</td><td>N Repeats</td>";

      for my $msb (@{$msbs{$proj}}) {
        print "<tr class='row_a'>";
        print "<td></td>";
        print "<td>". ($display_msb_name ? $msb->title : substr($msb->targets,0,30)) ."</td>";
        print "<td>". $msb->wavebands ."</td>";
        print "<td>". $msb->instruments ."</td>";
        print "<td>". $msb->nrepeats ."</td>";
      }
    }

    print "</table>";
    print "<p>";

    # F a u l t  S u m m a r y
    # Get faults
    my @faults = $self->faults->faults;

    # Sort faults by date
    my %faults;
    for my $f (@faults) {
      my $time = gmtime($f->date->epoch);
      push(@{$faults{$time->ymd}}, $f);
    }

    print "<a name=faultsum></a>";
    print "<table class='sum_table' cellspacing='0' width='600'>";
    print "<tr class='fault_sum_table_head'>";
    print "<td colspan=4><strong class='small_title'>Fault Summary</strong></td><td><strong class='small_title'>Shift</strong></td></tr>";

    for my $date (sort keys %faults) {
      my $timecellclass = 'time_a';
      if ($self->delta_day != 1) {

        # Summarizing faults for more than one day

        # Do all this date magic so we can use the appropriate CSS class
        # (i.e.: time_mon, time_tue, time_wed)
        my $fdate = $faults{$date}->[0]->date;
        my $time = gmtime($fdate->epoch);
        $timecellclass = 'time_' . $time->day . '_a';

        print "<tr class=sum_other valign=top><td class=$timecellclass colspan=2>$date</td><td colspan=2></td><td></td>";
    }
      for my $fault (@{$faults{$date}}) {
        print "<tr class=sum_other valign=top>";
        print "<td><a href='$ompurl/viewfault.pl?fault=". $fault->id ."' class='link_small'>". $fault->id ."</a></td>";

        my $time = gmtime($fault->date->epoch);
        print "<td class='$timecellclass'>". $time->strftime("%H:%M UT") ."</td>";
        print "<td><a href='$ompurl/viewfault.pl?fault=". $fault->id ."' class='subject'>".$fault->subject ."</a></td>";
        print "<td class='time' align=right>". $fault->timelost ." hrs lost</td>";
        print "<td class='shift' align=right>". $fault->shifttype ."</td>";
        print "</tr>";
      }
    }

    print "</table>";
    print "<p>";

    # S h i f t  L o g  C o m m e n t s
    my @comments = $self->shiftComments;

    print "<a name=\"shiftcom\"></a>";

    if ($comments[0]) {
      OMP::CGIComponent::Shiftlog->new()->display_shift_table( \@comments );
    } else {
      print "<strong>No Shift comments available</strong>";
    }
    print "<p>";

    # O b s e r v a t i o n  L o g
    # Display only if we are summarizing a single night
    if ($self->delta_day == 1) {
      # Can fall back to files now that JCMT disk is mounted
      # on mauiola. This line was here for when we could never
      # get the files of disk and only use the archive
      #$OMP::ArchiveDB::FallbackToFiles = 0;
      my $grp;
      try {
        $grp = $self->obs;
        $grp->locate_timegaps( OMP::Config->getData("timegap") );
      } catch OMP::Error::FatalError with {
        my $E = shift;
        print "<pre>An error has been encountered:<p> $E</pre><p>";
      } otherwise {
        my $E = shift;
        print "<pre>An error has been encountered:<p> $E</pre><p>";
      };

      print "<a name=\"obslog\"></a>";

      if ($grp and $grp->numobs > 0) {

        # Display log as plain text if there are a huge amount of observations
        my $plaintext = ($grp->numobs > 5000 ? 1 : 0);

        print "<pre>" if ($plaintext);

        OMP::CGIComponent::Obslog->new()->obs_table(
            $grp,
            sort => 'chronological',
            worfstyle => $worfstyle,
            commentstyle => $commentstyle,
            text => $plaintext,
        );

        print "</pre>" if ($plaintext);

      } else {
        # Don't display the table if no observations are available
        print "No observations available for this night";
      }
    }
  }
}

=item B<mail_report>

Mail a text version of the report to the relevant mailing list.

  $nr->mail_report();

An optional argument can be used to specify the details of the person
filing the report. Supplied as an OMP::User object. Defaults to
an email adress of "flex@maildomain" if no argument is specified,
where "maildomain" is stored in the config system.

=cut

sub mail_report {
  my $self = shift;
  my $user = shift;

  # Get the mailing list
  my @mailaddr = map { OMP::User->new(email => $_) }
    OMP::Config->getData( 'nightrepemail',
                          telescope => $self->telescope);

  # Should CC observers

  # Get the text
  my $report = $self->astext;

  # Who is filing this report (need the email address)
  my $from;
  if (defined $user && defined $user->email) {
    $from = $user;
  } else {
    $from = OMP::User->new(email => 'flex@' . OMP::Config->getData('maildomain'),);
  }

  # and mail it
  OMP::BaseDB->_mail_information(
                                 to => \@mailaddr,
                                 from => $from,
                                 subject => 'OBS REPORT: '.$self->date->ymd .
                                 ' at the ' . $self->telescope,
                                 message => $report,
                                );
}

=back

=head2 Internal Methods

=over 4

=item B<_get_date_xml>

Return the date portion of an XML query.

  $xmlpart = $self->_get_date_xml(tag => $tagname, timeacct => 1);

Arguments are provided in hash form.  The name of the date tag defaults to
'date', but this can be overridden by providing a 'tag' key that points to
the name to be used. If the 'timeacct' key points to a true value, the
query will adjust the delta so that it returns only the correct time accounts.

=cut

sub _get_date_xml {
  my $self = shift;
  my %args = @_;
  my $tag = (defined $args{tag} ? $args{tag} : "date");

  if ($self->date_end) {
    return "<$tag><min>".$self->date->ymd."</min><max>".$self->date_end->ymd."</max></$tag>";
  } else {
    # Use the delta
    # Subtract 1 day from the delta (if we are doing time account query
    # since the time accouting table stores dates with times as 00:00:00
    # and we'll end up getting more back than we expected.
    my $delta = $self->delta_day;
    $delta -= 1
      if (defined $args{timeacct});
    return "<$tag delta=\"$delta\">". $self->date->ymd ."</$tag>";
  }
}

=back

=head1 NOTES

The key used for warnings from results hashes (eg the C<accounting>
method) can be retrieved in global variable C<$OMP::NightRep::WARNKEY>.

=head1 SEE ALSO

See C<OMP::TimeAcctDB>, C<OMP::Info::ObsGroup>, C<OMP::FaultDB>,
C<OMP::ShiftDB>

=head1 COPYRIGHT

Copyright (C) 2002-2003 Particle Physics and Astronomy Research
Council.  All Rights Reserved.

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

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>,
Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>

=cut

1;
