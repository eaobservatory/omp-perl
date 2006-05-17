package OMP::MSBQuery;

=head1 NAME

OMP::MSBQuery - Class representing an OMP query of the MSB database

=head1 SYNOPSIS

  $query = new OMP::MSBQuery( XML => $xml );
  $sql = $query->sql( $table );


=head1 DESCRIPTION

This class can be used to process OMP MSB queries.
The queries are usually represented as XML.

=cut

use 5.006;
use strict;
use warnings;
use Carp;

# External modules
use OMP::Error qw/ :try /;
use OMP::General;
use OMP::Range;
use OMP::SiteQuality;
use Time::Piece ':override'; # for gmtime

# Inheritance
use base qw/ OMP::DBQuery /;

# Package globals
our $VERSION = (qw$Revision$ )[1];

# Constants
use constant D2R => 4 * atan2(1,1) / 180.0; # Degrees to radians

=head1 METHODS

=head2 Accessor Methods

Instance accessor methods. Methods beginning with an underscore
are deemed to be private and do not form part of the publi interface.

=over 4

=item B<refDate>

Return the date object associated with the query. If no date has been
specified explicitly in the query the current date is returned.
[although technically the "current" date is actually the date when the
query was parsed rather than the date the exact time this method was
called]

  $date = $query->refDate;

The time can not be specified as an input argument.

This allows the target availability to be calculated.

=cut

sub refDate {
  my $self = shift;

  # Get the hash form of the query
  my $href = $self->query_hash;

  # Check for "date" key
  my $date;
  if ( exists $href->{date} ) {
    $date = $href->{date}->[0];
  } else {
    # Need to get a gmtime object that stringifies as a Sybase date
    $date = gmtime;

    # Rebless
    bless $date, "Time::Piece::Sybase";
  }
  return $date;
}

=item B<airmass>

Return the requested airmass range as an C<OMP::Range> object.
The range can be specified as either an elevation or an airmass.
If both are specified then the smallest range that satisfies both
will be returned.

  $range = $query->airmass;

Returns C<undef> if the range has not been specified.

=cut

sub airmass {
  my $self = shift;

  # Get the hash form of the query
  my $href = $self->query_hash;

  # Check for "airmass" key
  my $airmass;
  $airmass = $href->{airmass} if exists $href->{airmass};

  # Check for elevation and convert to airmass
  my $airmass_el;
  if (exists $href->{elevation}) {
    my $elevation = $href->{elevation};
    $airmass_el = new OMP::Range;

    # Use simple calculation to convert to airmass
    # Dont worry about refraction effects (no reason
    # to add a SLALIB dependency here)
    for my $method (qw/max min/) {
      my $value = $elevation->$method;
      next unless defined $value;
      $value = 1.0/sin($value * D2R);
      $airmass_el->$method( $value );
    }

    # Of course, an airmass has an inverted sense of range
    # from an elevation
    my ($min, $max) = $airmass_el->minmax;
    $airmass_el->minmax($max, $min);

  }

  # Now determine the final range based on both
  # airmass and elevation.
  if (defined $airmass_el) {
    if (defined $airmass) {
      # we had an elevation and an airmass
      $airmass->intersection( $airmass_el )
	or throw OMP::Error::FatalError("The supplied airmass and elevation ranges do not intersect: airmass $airmass and from el: $airmass_el");
    } else {
      # We only had an elevation
      $airmass = $airmass_el;
    }
  }

  return $airmass;
}

=item B<ha>

Return the requested hour angle range as an C<OMP::Range> object.

  $range = $query->ha;

Returns C<undef> if the range has not been specified.
Units are assumed to be hours.

=cut

sub ha {
  my $self = shift;

  # Get the hash form of the query
  my $href = $self->query_hash;

  # Check for "airmass" key
  my $ha;
  $ha = $href->{ha} if exists $href->{ha};
  return $ha;
}

=item B<seeing>

Return the requested seeing as an C<OMP::Range> object.

  $seeing = $query->seeing;

Returns C<undef> if the seeing has not been specified. Units are
assumed to be in arcseconds.

=cut

sub seeing {
  my $self = shift;

  # Get the hash form of the query.
  my $href = $self->query_hash;

  # Check for 'P.seeingmax' key.
  my $seeing;
  if( exists( $href->{'P.seeingmax'} ) ) {
    $seeing = $href->{'P.seeingmax'}->min;
  }
  return $seeing;
}

=item B<constraints>

Returns a hash containing the general project constraints that 
can be applied to this query.

Supported constraints are:

  observability  - is the source up
  remaining      - is the MSB still to be observed
  allocation     - has the full project allocation been used
  state          - is the project enabled
  zoa            - is the source within the zone-of-avoidance?

Each of these will have a true (constraint is active) or false
(constraint is disabled) value.

If the query includes an instruction to disable all constraints
this will be respected by setting all values to false.

Default is all values set to true.

  my %constraints = $q->constraints;

The constraints are cached (ie only calculated once per instance).

=cut

sub constraints {
  my $self = shift;

  # Check in cache
  return %{ $self->{Constraints} } if $self->{Constraints};

  # Get the query in hash form
  my $href = $self->query_hash;

  # Default values
  my %constraints = (
		     observability => 1,
		     remaining => 1,
		     allocation => 1,
		     state => 1,
                     zoa => 1,
		    );

  # Go through the disableconstraint array making a hash
  if (exists $href->{disableconstraint}) {
    for my $con (@{ $href->{disableconstraint} } ) {
      $con = lc( $con );
      # immediately drop out if we hit "all"
      if ($con eq "all" ) {
	for my $key (keys %constraints) {
	  $constraints{$key} = 0;
	}
	last;
      } elsif (exists $constraints{$con}) {
	# If its in the allowed constraints list set to false
	$constraints{$con} = 0;
      }
    }
  }

  # Store it in cache
  $self->{Constraints} = \%constraints;

  return %constraints;

}

=back

=head2 General Methods

=over 4

=item B<sql>

Returns an SQL representation of the MSB Query using the specified
database table.

  $sql = $query->sql( $msbtable, $obstable, $projtable, $coitable );

Returns undef if the query could not be formed.

The query includes explicit tests to make sure that time remains
on the project and that the target is available (in terms of being
above the horizon and in terms of being schedulable)

=cut

sub sql {
  my $self = shift;

  throw OMP::Error::MSBMalformedQuery("sql method invoked with incorrect number of arguments\n") 
    unless scalar(@_) ==5;

  my ($msbtable, $obstable, $projtable, $projqueuetable, $projusertable) = @_;

  # Generate the WHERE clause from the query hash
  # Note that we ignore elevation, airmass and date since
  # these can not be dealt with in the database at the present
  # time [they are used to calculate source availability]
  # Disabling constraints on queries should be left to this
  # subclass

  # Ignore seeing if we have a telescope that has a variable seeing
  # calculation in the config system. To do this, we need to get the
  # telescope from the query, and if that doesn't exist, use the
  # instrument to determine the telescope, and if that doesn't exist,
  # just assume that we'll use the SQL to filter out seeing.
  my $qhash = $self->query_hash;
  my @ignore;
  if( defined( $qhash->{'M.telescope'} ) ) {

    # Look up the seeing_eq value from the config system. Wrap in a
    # try block because if the value doesn't exist in the config
    # system then we should handle that gracefully.
    try {
      my $seeing_eq = OMP::Config->getData( 'seeing_eq',
                                            telescope => $qhash->{'M.telescope'}->[0] );
      push @ignore, qw/ M.seeingmin M.seeingmax P.seeingmin P.seeingmax /;
    }
    catch OMP::Error::BadCfgKey with {
      # No-op.
    }
    otherwise {
      # No-op.
    };
  }
  push @ignore, qw/ elevation airmass date disableconstraint ha /;

  my $subsql = $self->_qhash_tosql( \@ignore );

  # If the resulting query contained anything we should prepend
  # an AND so that it fits in with the rest of the SQL. This allows
  # an empty query to work without having a naked "AND".
  $subsql = " AND " . $subsql if $subsql;

  # Some explanation is probably in order.
  # We do three queries
  # 1. Do a query on MSB and OBS tables looking for relevant
  #    matches but only retrieving the matching MSBID, the
  #    corresponding MSB obscount and the total number of observations
  #    that matched within each MSB. The result is stored to a temp table
  # 2. Query the temporary table to determine all the MSB's that had
  #    all their observations match and return the MSB information

  # We also DROP the temporary table immediately since sybase
  # keeps them around for until the connection is ended.

  # It is assumed that the observation information will be retrieved
  # in a subsequent query if required.

  # Get the names of the temporary tables
  # Sybase limit if 13 characters for uniqueness
  # Assumes we are connecting to OMP::DBbackend
  my $tempcount = OMP::DBbackend->get_temptable_prefix."ompcnt";

  # Get string we need to use in select to signify we are 
  # creating a temporary table
  my $tempnew = OMP::DBbackend->get_temptable_constructor();

  # Sybase allows us to bracket a select statement so that
  # it does not interfere with a second SELECT in the block.
  # Postgres does not like that and prefers a ;
  my $stmt_start = OMP::DBbackend->get_stmt_start();
  my $stmt_end = OMP::DBbackend->get_stmt_end();

  # Additionally there are a number of constraints that are
  # always applied to the query simply because they make
  # sense for the OMP. These are:
  #  observability  - is the source up
  #  remaining      - is the MSB still to be observed
  #  allocation     - has the full project allocation been used
  #  state          - is the project enabled
  # These constraints can be disabled individually by using
  # XML eg. <disableconstraint>observability</disableconstraint>
  # All can be disabled using "all".
  my %constraints = $self->constraints;
  my $constraint_sql = '';

  $constraint_sql .= " AND M.remaining > 0 " if $constraints{remaining};
  $constraint_sql .= " AND (P.remaining - P.pending) >= M.timeest " 
    if $constraints{allocation};
  $constraint_sql .= " AND P.state = ".
    OMP::DBbackend->get_boolean_true 
    ." " if $constraints{state};

  # It is more efficient if we only join the COI table
  # if we are actually going to use it. Also if no coitable
  # supplied raise an error
  # Only do a join if required by the CoI or Person query
  my @join_tables;
  my @join_sql;
  # Note that we match multiple times but we do not reset the position
  # this allows us to jump out eventually.
  my %found;
  while ($subsql =~ /\b(U\d)\.userid\b/cg ) {
    # Keep track of the tables we have covered already
    next if exists $found{$1};
    $found{$1}++;

    push(@join_tables, ", $projusertable $1");
    push(@join_sql, " P.projectid = $1.projectid ");
  }

  # Add Q table
  # We always need to add the Q table since we always need
  # to store the matching country in the country table
  # so that we can limit the MSB matches when we do the secondd
  # query (else all we get are matching MSBIDs and no constraint
  # on country in the second phase).
  # Additionally, if we are not constraining country we still need
  # to include Q else the obscount will be too high. We in fact
  # wish to return clone MSBs if the country is different.
  push(@join_tables, ", $projqueuetable Q");
  push(@join_sql, " P.projectid = Q.projectid ");

  my $u_sql = '';
  $u_sql = " AND " . join(" AND ", @join_sql) if @join_sql;

  # Use DISTINCT here when we include Q.country else things
  # go crazy and we get millions of rows when trying to group
  # by msbid and by country. Have not really worked out why
  # we need DISTINCT here....
  my $top_sql = $stmt_start . "SELECT
         DISTINCT M.msbid, max(M.obscount) AS obscount, Q.country, COUNT(*) AS nobs
           INTO $tempnew $tempcount
            FROM $msbtable M,$obstable O, $projtable P " .
	     join(" ", @join_tables)
          ."  WHERE M.msbid = O.msbid
              AND P.projectid = M.projectid $u_sql";

  # We need to calculate the intersection of the project TAG Allocated
  # site quality constraints and the MSB specified constraints. This
  # is required so that the QT user can get a feel for how marginal an
  # observation is. The SQL code for this is quite repetitive so we
  # define it here in a loop.
  # There is no explicit function to find the min or max of 2 columns
  # from a row so we calculate the SIGN and use that to control which
  # of the project mins or MSB mins is returned
  # The factor of 2 comes in because we either add 1, say to +1 or to -1
  # obtaining 2 and 0 (or 0 and -2)
  my $minmax;
  for my $col (qw/ tau seeing cloud sky / ) {
    $minmax .= "
    (abs(1-sign(M2.${col}min-P2.${col}min))*P2.${col}min/2 + 
         abs(sign(P2.${col}min-M2.${col}min)-1)*M2.${col}min/2) AS ${col}min,
    (abs(sign(P2.${col}max-M2.${col}max)-1)*P2.${col}max/2 + 
         abs(1-sign(M2.${col}max-P2.${col}max))*M2.${col}max/2) AS ${col}max,\n";
  }

  # The end of the query is generic
  # make sure we include tagpriority here since it is faster
  # than doing an explicit project query later on (although
  # there may be a saving in the fact that the number of MSBs
  # returned is far greater than the number of projects required
  # could in reality generate a OMP::Project object from this and
  # store it in the Info::MSB object. Need to consider this so KLUGE.

  # Note that internal priority field is redefined as a combined tagpriority
  # and internal priority field to aid searching and sorting in the QT and to
  # retuce the number of fields. Internal priority is 1 to 99.
  # We always need to join the QUEUE table since that includes the priority.
  my $bottom_sql = "GROUP BY M.msbid, Q.country $stmt_end
              SELECT M2.*," .
                $minmax .
                "(".
 		  OMP::DBbackend->get_sql_typecast("float","Q2.tagpriority + Q2.tagadj")
		      . " + " .
			OMP::DBbackend->get_sql_typecast("float","M2.priority")
			    . "/100) AS newpriority,
               ((P2.allocated-P2.remaining)/P2.allocated * 100.0) AS completion
                FROM $msbtable M2, $tempcount T, $projtable P2, 
                       $projqueuetable Q2
                 WHERE (M2.msbid = T.msbid
                   AND M2.obscount = T.nobs 
                    AND M2.projectid = P2.projectid 
                      AND M2.projectid = Q2.projectid 
                        AND Q2.country = T.country)
                          ORDER BY newpriority 

                DROP TABLE $tempcount";
  # PostgresQL will not allow the DROP TABLE within the same query.
  # Need to provide an explicit cleanup method to all query classes.

  # Now need to put this SQL into the template query
  my $sql = "$top_sql
              $constraint_sql
                $subsql
                  $bottom_sql";

  #print "$sql\n";

  return "$sql\n";

  # To subvert query
  return "SELECT * FROM $msbtable WHERE remaining > 0";
}

=begin __PRIVATE__METHODS__

=item B<_root_element>

Class method that returns the name of the XML root element to be
located in the query XML. This changes depending on whether we
are doing an MSB or Project query.
Returns "MSBQuery" by default.

=cut

sub _root_element {
  return "MSBQuery";
}

=item B<_post_process_hash>

Go through the hash creating C<OMP::Range> objects where appropriate
and fixing up known issues such as "cloud" and "moon" which used to be
treated as lower limits rather than exact matches (so there are
backwards compatibility traps in place).

  $query->_post_process_hash( \%hash );

"date" strings are converted to a date object.

"date", "tau", "sky", "moon", "cloud" and "seeing" queries are each
converted to two separate queries (one on "max" and one on "min") [but
the "date" key is retained so that the reference date can be obtained
in order to calculate source availability).

Also converts abbreviated form of project name to the full form
recognised by the database, but see below for ways of stopping this.

The current semester is used for all queries unless a semester
or a projectid is explicitly specified in the query.

Tau and seeing must be positive. If they are not positive they will be
ignored.

"timeest" fields are allowed a "units" attribute to indicate whether
the length is specified in minutes or seconds.

The "projectid" field is allowed an attribute of "full" to indicate
whether the project ID is known to be complete (1) or whether it is
abbreviated (0). In the absence of this attribute a telescope I<must>
be supplied since this is required to determine what form a particular
project ID must take. Note that you should be consistent with your
attributes in this case. The assumption will be that if "full" is true
for any project ID then it is true for all project IDs (but that may
depend on the order of the XML and should not be relied upon).

A telescope is required unless a fully expanded project ID is specified.

=cut

sub _post_process_hash {
  my $self = shift;
  my $href = shift;

  # Do the generic pre-processing
  $self->SUPER::_post_process_hash( $href );

  # Need a telescope UNLESS we have a fully specified project ID
  # (ie no inferred projectid)
  throw OMP::Error::MSBMalformedQuery( "Please supply a telescope or explicit unabbreviated project ID")
    if (! exists $href->{telescope} &&
	! $href->{_attr}->{projectid}->{full});

  # Force moon and cloud to be integers (since that is the column type)
  for my $key (qw/ moon cloud /) {
    if (exists $href->{$key}) {
      $href->{$key}->[0] = OMP::General::nint( $href->{$key}->[0] );
    }
  }

  # priority is a call on the Q.tagpriority and Q.tagadjustment columns
  if (exists $href->{priority}) {
    $href->{"Q.tagpriority + Q.tagadj"} = $href->{priority};
    delete $href->{priority};
  }

  # Remove negatives when values are meant to be positive
  for my $key (qw/ tau seeing cloud moon /) {
    if (exists $href->{$key}) {
      delete $href->{$key}
        if $href->{$key}->[0] <= 0;
    }
  }

  # We always need a reference date
  if (exists $href->{date}) {
    # But not a date range
    throw OMP::Error::MSBMalformedQuery( "date can not be specified as a range. Only a specific date can be supplied.")
      unless ref($href->{date}) eq "ARRAY";

  } else {
    # Need to get a gmtime object that stringifies as a Sybase date
    my $date = gmtime;

    # Rebless
    bless $date, "Time::Piece::Sybase";

    # And store it
    $href->{date} = [ $date ];

  }

  # Also do timeest as a special case since that becomes
  # Must deal with the attributes
  if (exists $href->{timeest}) {

    my $key = "timeest";

    # Need the estimated time to be in seconds
    # Look at the attributes
    if (exists $href->{_attr}->{$key}->{units}) {
      my $units = $href->{_attr}->{$key}->{units};

      my $factor = 1; # multiplication factor
      if ($units =~ /^h/) {
	$factor = 3600;
      } elsif ($units =~ /^m/) {
	$factor = 60;
      }

      # Now scale all values by this factor
      # 99% of the time we have an OMP::Range object here
      if (UNIVERSAL::isa($href->{timeest},"OMP::Range")) {
	my @minmax = $href->{timeest}->minmax;
	for (@minmax) {
	  $_ *= $factor if defined $_;
	}
	$href->{timeest}->minmax(@minmax);
      } elsif (ref($href->{timeest}) eq 'HASH') {
	for (keys %{ $href->{timeest} }) {
	  $href->{timeest}->{$_} *= $factor;
	}
      } elsif (ref($href->{timeest}) eq 'ARRAY') {
	for (@{ $href->{timeest}}) {
	  $_ *= $factor;
	}
      }
    }
  }

  # Upgrade "cloud" and "moon" to percentage (if they are not
  # already percentages - 1 is the magic value and will be confusing
  # for "cloud" if that value is ever used for real)
  # we may want to remove the "cloud" trap when we know all sites have
  # updated Query Tools. When that happens "1" will mean "1%"
  # Moon can never be 1% so we can retain this trap.
  if (exists $href->{cloud}) {
    my $range = OMP::SiteQuality::upgrade_cloud( $href->{cloud}->[0] );
    $href->{cloud} = [ $range->max ];
  }
  if (exists $href->{moon}) {
    my $range = OMP::SiteQuality::upgrade_moon( $href->{moon}->[0] );
    $href->{moon} = [ $range->max ];
  }

  # Loop over each key
  for my $key (keys %$href ) {
    # Skip private keys
    next if $key =~ /^_/;

    if ($key eq "seeing" or $key eq "tau" or $key eq "date"
	    or $key eq 'sky' or $key eq 'cloud' or $key eq 'moon') {
      # Convert to two independent ranges

      # Note that taumin indicates a MAX for the supplied value
      # and taumax indicates a minimum for the supplied value
      my %outkey = ( max => "Min", min => "Max");

      # Loop over min and max
      for my $type (qw/ min max /) {
	$href->{"$key$type"} = new OMP::Range( $outkey{$type} =>
					       $href->{$key}->[0]);
      }

      # And remove the old key (unless it is the reference date)
      delete $href->{$key} unless $key eq "date";

    } elsif ($key eq 'projectid' && ! $href->{_attr}->{projectid}->{full}
	    ) {
      # Expand project IDs unless we know that the project ID is
      # already fully expanded.

      # Get the telescope and date if we know it
      my %options;
      $options{telescope} = $href->{telescope}->[0] 
	if exists $href->{telescope};
      $options{date} = $href->{date}->[0]
	if exists $href->{date}->[0];

      # Translate project IDs
      for my $pid (@{ $href->{$key}}) {
	$pid = OMP::General->infer_projectid(%options,
					     projectid => $pid);
      }

    }

  }

  # Add a semester if we have not got one and no projectid
  # specified.
  # Since we always want to default to current semester
  # in the general case.
  if (!exists $href->{semester} && !exists $href->{projectid}) {
    # Need the telescope in this case
    throw OMP::Error::MSBMalformedQuery("Automatic semester determination requires a telescope in the query")
      unless exists $href->{telescope};
    $href->{semester} = [ OMP::General->determine_semester(tel => $href->{telescope}->[0])];
  }


  # Case sensitivity
  # If we are dealing with these we should make sure we upper
  # case them (more efficient to upper case everything than to do a
  # query that ignores case)
  $self->_process_elements($href, sub { uc(shift) }, 
			   [qw/projectid telescope semester country name
			    pi coi instrument person /]);


  # These entries are in more than one table so we have to 
  # explicitly choose the MSB table
  for (qw/ projectid timeest telescope /) {
    if (exists $href->{$_}) {
      my $key = "M.$_";
      $href->{$key} = $href->{$_};
      delete $href->{$_};
    }
  }

  # And these are found in the queue table
  for (qw/ country tagpriority /) {
    if (exists $href->{$_}) {
      my $key = "Q.$_";
      $href->{$key} = $href->{$_};
      delete $href->{$_};
    }
  }


  # Some of the min/max keys need MSB and project variants
  for my $base (qw/ tau seeing cloud sky /) {
    for my $mm (qw/ min max /) {
      my $key = $base . $mm;
      if (exists $href->{$key}) {
	for my $tab (qw/ M. P. /) {
	  $href->{"$tab$key"} = $href->{$key};
	}
	delete $href->{$key};
      }
    }
  }

  # If we have a PERSON query and a COI query then we need to join
  # multiple tables
  my $counter = 1;
  my $prefix = 'U';

  # A coi query is really a query on the ompprojuser table
  # See also OMP::ProjQuery where this code is duplicated
  if (exists $href->{coi}) {
    my $U = $prefix . $counter;
    $href->{coi} = { _JOIN => 'AND', "$U.userid" => $href->{coi}, 
		     "$U.capacity" => ['COI']};
    $counter++;
  }

  # Person requires multiple bits
  # since it wants a PI or a COI to match
  # Note that we actually bring in the PI column from ompprojuser and do
  # not attempt to use P.pi
  # WHERE (P.pi = 'XXX' OR ( U.userid = 'XXX' AND U.capacity = 'COI' )
  # is more complicated to construct from the hash
  if (exists $href->{person}) {
    my $U = $prefix . $counter;
    $href->{person} = {
		       _JOIN => 'AND',
		       auser => {"$U.userid" => $href->{person}},
		       acapacity => { "$U.capacity"=> ['COI','PI']},
		      };
    $counter++;
  }


  # Remove attributes since we dont need them anymore
  delete $href->{_attr};

}


=end __PRIVATE__METHODS__

=back

=head1 Query XML

The Query XML is specified as follows:

=over 4

=item B<MSBQuery>

The top-level container element is E<lt>MSBQueryE<gt>.

=item B<Equality>

Elements that contain simply C<PCDATA> are assumed to indicate
a required value.

  <instrument>SCUBA</instrument>

Would only match if C<instrument=SCUBA>.

=item B<Ranges>

Elements that contain elements C<max> and/or C<min> are used
to indicate ranges.

  <elevation><min>30</min></elevation>
  <priority><max>2</max></priority>

Why dont we just use attributes?

  <priority max="2" /> ?

Using explicit elements is probably easier to generate.

Ranges are inclusive.

=item B<Multiple matches>

Elements that contain other elements are assumed to be containing
multiple alternative matches (C<OR>ed).

  <instruments>
   <instrument>CGS4</instrument>
   <instrument>IRCAM</instrument>
  </isntruments>

C<max> and C<min> are special cases. In general the parser will
ignore the plural element (rather than trying to determine that
"instruments" is the plural of "instrument"). This leads to the
dropping of plurals such that multiple occurrence of the same element
in the query represent variants directly.

  <name>Tim</name>
  <name>Kynan</name>

would suggest that names Tim or Kynan are valid. This also means

  <instrument>SCUBA</instrument>
  <instruments>
    <instrument>CGS4</instrument>
  </instruments>

will select SCUBA or CGS4.

Neither C<min> nor C<max> can be included more than once for a
particular element. The most recent values for C<min> and C<max> will
be used. It is also illegal to use ranges inside a plural element.

=item B<Reference date>

The C<date> element can be used to specify a specific date
for the query. This date is used for determining source availability
and is compared with any date constraints for a particular MSB. If a date
is not supplied the current date is automatically inserted. The date
should be supplied in ISO format YYYY-MM-DDTHH:MM

  <date>2002-04-15T04:52</date>

=item B<tau, seeing, cloud, moon and sky>

Queries including tau and seeing reflect the current weather conditions
but do not correspond to an equivalent table in the database. The database
contains allowable ranges (e.g. taumin and taumax) and the supplied
value must lie within the range. Therefore for a query such as:

  <tau>0.06</tau>

the query would become

  taumin <= 0.05 AND taumax >= 0.05

=item B<target observability>

Constraints on the observability of the target are not calculated in
SQL. These must be done post-query. Methods are provided to make the
target constraints available (essentially the minimum elevation).

=item B<query constraints>

Additionally there are a number of constraints that are
always applied to the query simply because they make
sense for the OMP. These are:

 observability  - is the source up
 remaining      - is the MSB still to be observed
 allocation     - has the full project allocation been used

These constraints can be disabled individually by using
XML for example,

 <disableconstraint>observability</disableconstraint>

Any number of these elements can be included.

Alternatively all scheduling constraints can be disabled
using "all".

 <disableconstraint>all</disableconstraint>

=back

=head1 SEE ALSO

OMP/SN/004, C<OMP::DBQuery>

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>
Brad Cavanagh E<lt>b.cavanagh@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001-2006 Particle Physics and Astronomy Research Council.
All Rights Reserved.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful,but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc., 59 Temple
Place,Suite 330, Boston, MA  02111-1307, USA

=cut

1;
