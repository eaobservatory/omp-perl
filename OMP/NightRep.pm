package OMP::NightRep;

=head1 NAME

OMP::NightRep - Generalized routines to details from a given night

=head1 SYNOPSIS

  use OMP::NightRep;

  $nr = new OMP::NightRep( date => '2002-12-18',
                           telescope => 'jcmt');

  $obs = $nr->obs;
  @faults = $nr->faults;
  $timelost = $nr->faultloss;
  @acct = $nr->accounting;
  $weather = $nr->weatherloss;


=head1 DESCRIPTION

A high-level wrapper around routines useful for generating nightly
activity reports. Provides a means to obtain details of observations
taken on a night, faults occuring and project accounting.

=cut

use 5.006;
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
use OMP::TimeAcctQuery;
use OMP::ShiftDB;
use OMP::ShiftQuery;
use OMP::FaultDB;
use OMP::FaultQuery;
use OMP::FaultStats;
use OMP::CommentServer;
use OMP::MSBDoneDB;
use OMP::MSBDoneQuery;
use Time::Piece qw/ :override /;
use Text::Wrap;
use OMP::BaseDB;

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
		  Telescope => undef,
		  UTDate => undef,
		  DeltaDay => 1,
		  DB => undef,
		 };


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
    my $date = OMP::General->parse_date( $arg );
    throw OMP::Error::BadArgs("Unable to parse $arg as a date")
      unless defined $date;
    $self->{UTDate} = $date;
  }

  if (!defined $self->{UTDate}) {
    return OMP::General->today( 1 );
  } else {
    return $self->{UTDate};
  }
}

=item B<delta_day>

Return the delta in days (24 hour periods, really) associated with this object.

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

=back

=head2 General Methods

=over 4

=item B<accounting>

Retrieve all the project accounting details for the night as a hash.
The keys are projects and for each project there is a hash containing
keys "DATA" and "DB" indicating whether the information comes from the
data headers or the time accounting database directly.  All accounting
details are C<OMP::Project::TimeAcct> objects.

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
  my %db = $self->accounting_db;
  $results{DB} = \%db;

  # Get the info from the headers
  my %hdr = $self->accounting_hdr;
  $results{DATA} = \%hdr;

  # Now generate a combined hash
  my %combo;

  for my $src (qw/ DB DATA /) {
    for my $proj (keys %{ $results{$src} } ) {
      # Special case for warnings
      if ($proj eq $WARNKEY) {
	$combo{$WARNKEY} = [] unless exists $combo{$WARNKEY};
	push(@{ $combo{$WARNKEY} }, @{ $results{$src}->{$proj} });
      } else {
	# Store the results in the right place
	$combo{$proj}->{$src} = $results{$src}->{$proj};
      }
    }
  }

  return %combo;
}

=item B<accounting_db>

Return the time accounting database details for each project observed
this night. A hash is returned indexed by project ID and pointing
to the appropriate C<OMP::Project::TimeAcct> object or hash of accounting
information.

This is a cut down version of the C<accounting> method that returns
details from all methods of determining project accounting including
estimates.

  %projects = $nr->accounting_db();
  %projects = $nr->accounting_db($data);

This method takes an optional argument that if true returns a hash of
hashes for each project with the keys 'pending', 'total' and 'confirmed'
instead of C<OMP::Project::TimeAcct> objects.

=cut

sub accounting_db {
  my $self = shift;
  my $return_data = shift;

  # Database connection
  my $db = new OMP::TimeAcctDB( DB => $self->db );

  # Subtract 1 day from the delta since the time accouting table
  # stores dates with times as 00:00:00 and we'll end up getting
  # more back than we expected.
  my $delta = $self->delta_day - 1;

  # XML query
  my $xml = "<TimeAcctQuery>".
    "<date delta=\"". $delta ."\">". $self->date->ymd ."</date>".
      "</TimeAcctQuery>";

  # Get our sql query
  my $query = new OMP::TimeAcctQuery( XML => $xml );

  # Get the time accounting statistics from
  # the TimeAcctDB table
  my @dbacct = $db->queryTimeSpent( $query );

  # Keep only the results for the telescope we are querying for
  @dbacct = grep { OMP::ProjServer->verifyTelescope( $_->projectid,
						     $self->telescope
						   )} @dbacct;

  my %projects;
  if ($return_data) {
    # Returning data

    # Combine Time accounting info for a multiple nights.  See documentation
    # for summarizeTimeAcct method in OMP::Project::TimeAcct
    %projects = $dbacct[0]->summarizeTimeAcct( 'byproject', @dbacct )
      unless (! $dbacct[0]);
  } else {
    # Returning objects

    # Convert to a hash [since we can guarantee one instance of a project
    # for a single UT date]
    for my $acct (@dbacct) {
      $projects{ $acct->projectid } = $acct;
    }
  }

  return %projects;
}

=item B<accounting_hdr>

Return time accounting statistics generated from the data headers
for this night.

 %details = $nr->accounting_hdr();

Also returns a reference to an array of warning information generated
by the scan. The keys in the returned hash are project IDs and the
values are C<OMP::Project::TimeAcct> objects. Warnings are returned
as a reference to an array using key "__WARNINGS__" (See L<"NOTES">).

This results in a subset of the information returned by the C<accounting>
method.

=cut

sub accounting_hdr {
  my $self = shift;

  # Get the time accounting statistics from the data headers
  # Need to catch directory not found
  my $obsgrp = $self->obs;
  my ($warnings, @hdacct);
  if ($obsgrp) {
    # locate time gaps > 1 second when calculating statistics
    $obsgrp->locate_timegaps( 1 );

    ($warnings, @hdacct) = $obsgrp->projectStats();
  } else {
    $warnings = [];
  }

  # Form a hash
  my %projects;
  for my $acct (@hdacct) {
    $projects{ $acct->projectid } = $acct;
  }

  $projects{$WARNKEY} = $warnings;

  return %projects;

}

=item B<obs>

Return the observation details relevant to this night and UT date.
This will include time gaps. Information is returned as an
C<OMP::Info::ObsGroup> object.

Returns undef if no observations could be located.

=cut

sub obs {
  my $self = shift;

#  my $db = new OMP::ArchiveDB( DB => new OMP::DBbackend::Archive );

  my $db = new OMP::ArchiveDB();
  try {
    my $fred = new OMP::DBbackend::Archive;
    $db->db( $fred );
  }
  catch OMP::Error::DBConnection with {
    # let it pass through
  };


  # XML query to get all observations
  my $xml = "<ArcQuery>".
    "<telescope>". $self->telescope ."</telescope>".
      "<date delta=\"". $self->delta_day ."\">". $self->date->ymd ."</date>".
	"</ArcQuery>";

  # Convert XML to an sql query
  my $query = new OMP::ArcQuery( XML => $xml );

  # Get observations
  my @obs = $db->queryArc( $query );

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

  my @results = $db->queryMSBdone( $query, 0 );

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

=item B<faults>

Return the fault objects relevant to this telescope and UT date.

  @faults = $nr->faults;

Returns a list of C<OMP::Fault> objects.

=cut

sub faults {
  my $self = shift;

  my $fdb = new OMP::FaultDB( DB => $self->db );

  my %xml;
  # We have to do two separate queries in order to get back faults that
  # were filed on and occurred on the reporting dates

  # XML query to get faults filed on the dates we are reaporting for
  $xml{filed} = "<FaultQuery>".
    "<date delta=\"". $self->delta_day ."\">". $self->date->ymd ."</date>".
      "<category>". $self->telescope ."</category>".
	"<isfault>1</isfault>".
	  "</FaultQuery>";

  # XML query to get faults that occurred on the dates we are reporting for
  $xml{actual} = "<FaultQuery>".
    "<faultdate delta=\"". $self->delta_day ."\">". $self->date->ymd . "</faultdate>".
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

  # Convert result hash to array
  my @results = map {$results{$_}} sort keys %results;
  return @results;
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
  my @faults = $self->faults;
  my $faultstats = new OMP::FaultStats( faults => \@faults );
  if ($arg eq "technical") {
    return $faultstats->timelostTechnical;
  } elsif ($arg eq "non-technical") {
    return $faultstats->timelostNonTechnical;
  } else {
    return $faultstats->timelost;
  }
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

  my @result = $sdb->getShiftLogs( $query );

  return @result;
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

Project Time Summary

};

  #   T I M E   A C C O U N T I N G
  # Total time
  my $total = 0.0;

  # Time lost to faults
  my $format = "  %-25s %5.2f hrs\n";
  my $faultloss = $self->timelost->hours;
  $str .= sprintf("$format", "Time lost to faults:", $faultloss );
  $total += $faultloss;

  # Just do project accounting
  my %acct = $self->accounting_db();

  # Weather and Extended and UNKNOWN and OTHER
  my %text = ( WEATHER => "Time lost to weather:",
	       OTHER   =>  "Other time:",
	       EXTENDED => "Extended Time:",
	       CAL      => "Unallocated calibrations:",
	     );

  for my $proj (qw/ WEATHER OTHER EXTENDED CAL /) {
    my $time = 0.0;
    if (exists $acct{$tel.$proj}) {
      $time = $acct{$tel.$proj}->timespent->hours;
      $total += $time unless $proj eq 'EXTENDED';
    }
    $str .= sprintf("$format", $text{$proj}, $time);
  }

  for my $proj (keys %acct) {
    next if $proj =~ /^$tel/;
    $str .= sprintf("$format", $proj.':', $acct{$proj}->timespent->hours);
    $total += $acct{$proj}->timespent->hours;
  }

  $str .= "\n";
  $str .= sprintf($format, "Total time:", $total);
  $str .= "\n";

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
  my @faults = $self->faults;

  $str .= "Fault Summary\n\n";

  if (@faults) {
    for my $fault (@faults) {
      my $date = $fault->date;
      my $local = localtime($date->epoch);
      $str.= "  ". $fault->faultid ." [". $local->strftime("%H:%M %Z")."] ".
	$fault->subject ."(".$fault->timelost." hrs lost)\n";

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
    my $author = $c->author->name;

    # Get the text and format it
    my $text = $c->text;

    # Really need to convert HTML to text using general method
    $text =~ s/\&apos\;/\'/g;
    $text =~ s/<BR>/\n/gi;

    # Word wrap
    $text = wrap("    ","    ",$text);

    # Now print the comment
    $str .= "  ".$local->strftime("%H:%M %Z") . ": $author\n";
    $str .= $text ."\n\n";
  }


  # Observation log
  $str .= "Observation Log\n\n";

  my $grp = $self->obs;
  $grp->locate_timegaps( OMP::Config->getData("timegap") );
  $str .= $grp->summary('72col');

  if (wantarray) {
    return split("\n", $str);
  }
  return $str;
}

=item B<ashtml>

Generate a summary of the night formatted using HTML.

  $nr->ashtml();

This method takes an optional hash argument with the following keys:

=over 4

=item *

worfstyle - Write WORF links to the staff WORF page. Can be either 'staff'
or 'project', and will default to 'project'.

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
  require OMP::CGIObslog;
  require OMP::CGIShiftlog;


  my $tel  = $self->telescope;
  my $date = $self->date->ymd;

  my $total = 0.0;
  my $total_pending = 0.0;

  my $ompurl = OMP::Config->getData('omp-url') . OMP::Config->getData('cgidir');

  print "<a href='$worflink?ut=$date&telescope=$tel'>View WORF thumbnails</a><br>";
  if ($self->delta_day < 14) {
    print "<a href='#faultsum'>Fault Summary</a><br>";
    print "<a href='#shiftcom'>Shift Log Comments</a> / <a href=\"shiftlog.pl?ut=$date&telescope=$date\">Add shift log comment</a><br>";
    print "<a href='#obslog'>Observation Log</a><br>";
    print "<p>";
  }



  # T i m e  A c c o u n t i n g
  # Get project accounting
  my %acct = $self->accounting_db(1);

  my $format = "%5.2f hrs\n";

  print "<table class='sum_table' cellspacing='0' width='600'>";
  print "<tr class='sum_table_head'>";
  print "<td colspan='3'><strong class='small_title'>Project Time Summary</strong></td>";

  # Time lost to faults
  my $faultloss = $self->timelost->hours;
  my $technicalloss = $self->timelost('technical')->hours;

  print "<tr class='sum_other'>";
  print "<td>Time lost to technical faults</td>";
  print "<td colspan=2>" . sprintf($format, $technicalloss) . "</td>";
  print "<tr class='sum_other'>";
  print "<td>Time lost to non-technical faults</td>";
  print "<td colspan=2>" . sprintf($format, $self->timelost('non-technical')->hours) . "</td>";
  print "<tr class='sum_other'>";
  print "<td>Total time lost to faults</td>";
  print "<td>" . sprintf($format, $faultloss) . " </td><td><a href='#faultsum' class='link_dark'>Go to fault summary</a></td>";

  $total += $faultloss;

  # Time lost to weather, extended accounting
  my %text = (
	      WEATHER => "<tr class='proj_time_sum_weather_row'><td>Time lost to weather</td>",
	      EXTENDED => "<tr class='proj_time_sum_extended_row'><td>Extended Time</td>",
	      OTHER => "<tr class='proj_time_sum_other_row'><td>Other Time</td>",
	      CAL => "<tr class='proj_time_sum_weather_row'><td>Unallocated Calibrations</td>",
	     );

  for my $proj (qw/WEATHER OTHER EXTENDED CAL/) {
    my $time = 0.0;
    my $pending;
    if (exists $acct{$tel.$proj}) {
      $time = $acct{$tel.$proj}->{total}->hours;
      if ($acct{$tel.$proj}->{pending}) {
	$pending += $acct{$tel.$proj}->{pending}->hours;
      }
      $total += $time unless $proj eq 'EXTENDED';
    }
    print "$text{$proj}<td colspan=2>" . sprintf($format, $time);
    if ($pending) {
      print " [unconfirmed]";
    }
    print "</td>";
  }

  # Sort project accounting by country
  my %acct_by_country;
  for my $proj (keys %acct) {
     next if $proj =~ /^$tel/;

    # No determine_country method exists, so we'll get project
    # details instead
    my $details = OMP::ProjServer->projectDetails($proj, "***REMOVED***", "object");

     $acct_by_country{$details->country}{$proj} = $acct{$proj};

#    push(@{$acct_by_country{$details->country}}, {$acct{$proj});
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
    #my $totalrows = scalar(%{$acct_by_country{$country}});

    for my $proj (sort keys %{$acct_by_country{$country}}) {
      $rowcount++;

      my $account = $acct_by_country{$country}{$proj};
      $total += $account->{total}->hours;

      my $pending;
      if  ($account->{pending}) {
	$total_pending += $account->{pending}->hours;
	$pending = $account->{pending}->hours;
      }

      print "<tr class='row_$bgcolor'>";
      print "<td><a href='$ompurl/projecthome.pl?urlprojid=$proj' class='link_light'>$proj</a></td><td>";
      printf($format, $account->{total}->hours);
      print " [unconfirmed]" if ($pending);
      print "</td>";
      if ($self->delta_day != 1) {
	if ($rowcount == 1) {
	  print "<td class=country_$country>$country ". sprintf($format, $country_total) ."</td>";
	} else {
	  print "<td class=country_$country></td>";
	}
      } else {
	print "<td></td>";
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

  print "</td>";

  # Get clear time
  my $cleartime = $total;
  $cleartime -= $acct{$tel.'WEATHER'}->{total}->hours
    if exists $acct{$tel.'WEATHER'};

  if ($cleartime > 0) {
    print "<tr class='proj_time_sum_weather_row'>";
    print "<td class='sum_other'>Clear time lost to faults</td><td colspan=2 class='sum_other'>". sprintf("%5.2f%%", $faultloss / $cleartime * 100) ." </td>";
    print "<tr class='proj_time_sum_other_row'>";
    print "<td class='sum_other'>Clear time lost to technical faults</td><td colspan=2 class='sum_other'>". sprintf("%5.2f%%", $technicalloss / $cleartime * 100) ." </td>";
  }

  print "</table>";
  print "<p>";

  if ($self->delta_day < 14) {
    # M S B  S u m m a r y
    # Get observed MSBs
    my %msbs = $self->msbs;

    print "<table class='sum_table' cellspacing='0' width='600'>";
    print "<tr class='sum_table_head'><td colspan=5><strong class='small_title'>MSB Summary</strong></td>";
    
    for my $proj (keys %msbs) {
      print "<tr class='sum_other'><td><a href='$ompurl/msbhist.pl?urlprojid=$proj' class='link_dark'>$proj</a></td>";
      print "<td>Target</td><td>Waveband</td><td>Instrument</td><td>N Repeats</td>";

      for my $msb (@{$msbs{$proj}}) {
	print "<tr class='row_a'>";
	print "<td></td>";
	print "<td>". substr($msb->targets,0,30) ."</td>";
	print "<td>". $msb->wavebands ."</td>";
	print "<td>". $msb->instruments ."</td>";
	print "<td>". $msb->nrepeats ."</td>";
      }
    }
    
    print "</table>";
    print "<p>";

    # F a u l t  S u m m a r y
    # Get faults
    my @faults = $self->faults;

    # Sort faults by local date
    my %faults;
    for my $f (@faults) {
      my $local = localtime($f->date->epoch);
      push(@{$faults{$local->ymd}}, $f);
    }

    print "<a name=faultsum></a>";
    print "<table class='sum_table' cellspacing='0' width='600'>";
    print "<tr class='fault_sum_table_head'>";
    print "<td colspan=4><strong class='small_title'>Fault Summary</strong></td>";

    for my $date (sort keys %faults) {
      my $timecellclass = 'time_a';
      if ($self->delta_day != 1) {
	
	# Summarizing faults for more than one day

	# Do all this date magic so we can use the appropriate CSS class
	# (i.e.: time_mon, time_tue, time_wed)
	my $fdate = $faults{$date}->[0]->date;
	my $local = localtime($fdate->epoch);
	$timecellclass = 'time_' . $local->day . '_a';

	print "<tr class=sum_other valign=top><td class=$timecellclass colspan=2>$date</td><td colspan=2></td>";
    }
      for my $fault (@{$faults{$date}}) {
	print "<tr class=sum_other valign=top>";
	print "<td><a href='$ompurl/viewfault.pl?id=". $fault->id ."' class='link_small'>". $fault->id ."</a></td>";

	# Use local time for fault date
	my $local = localtime($fault->date->epoch);
	print "<td class='$timecellclass'>". $local->strftime("%H:%M %Z") ."</td>";
	print "<td><a href='$ompurl/viewfault.pl?id=". $fault->id ."' class='subject'>".$fault->subject ."</a></td>";
	print "<td class='time' align=right>". $fault->timelost ." hrs lost</td>";
      }
    }

    print "</table>";
    print "<p>";

    # S h i f t  L o g  C o m m e n t s
    my @comments = $self->shiftComments;

    print "<a name=shiftcom></a>";

    if ($comments[0]) {
      OMP::CGIShiftlog::display_shift_table( \@comments );
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

      print "<a name=obslog></a>";

      if ($grp and $grp->numobs > 1) {
        OMP::CGIHelper::obs_table($grp,
                                  sort => 'chronological',
                                  worfstyle => $worfstyle,
                                  commentstyle => $commentstyle,
                                 );
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

=head1 NOTES

The key used for warnings from results hashes (eg the C<accounting>
method) can be retrieved in global variable C<$OMP::NightRep::WARNKEY>.

=head1 SEE ALSO

See C<OMP::TimeAcctDB>, C<OMP::Info::ObsGroup>, C<OMP::FaultDB>,
C<OMP::ShiftDB>

=head1 COPYRIGHT

Copyright (C) 2002-2003 Particle Physics and Astronomy Research
Council.  All Rights Reserved.

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>,
Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>

=cut

1;
